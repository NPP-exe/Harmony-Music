"""Use Nix-provided plugins while keeping the application and YouTube fork local."""

import json
import sys
from pathlib import Path

import yaml


root = Path.cwd()
manifest = yaml.safe_load((root / "pubspec.yaml").read_text())
if manifest.get("name") != "harmonymusic":
    raise SystemExit("Run harmony-configure from the Harmony Music project root")

# Compare against the lock that produced this Nix dependency graph, including
# when the exports in the checkout were changed after entering an older shell.
try:
    lock = yaml.safe_load((root / "pubspec.lock").read_text())
    expected = json.loads(Path(sys.argv[2]).read_text())
except (OSError, ValueError, yaml.YAMLError) as error:
    raise SystemExit(f"Cannot verify Pub locks; package_config.json was not changed: {error}")
if lock != expected:
    raise SystemExit(
        "Pub locks differ; package_config.json was not changed. "
        "Run nix run .#resolve-lockfile, then re-enter nix develop."
    )

config = json.loads(Path(sys.argv[1]).read_text())
for package in config["packages"]:
    if package["name"] == "harmonymusic":
        package["rootUri"] = "../"
    elif package["name"] == "youtube_explode_dart":
        package["rootUri"] = (root / "packages/youtube_explode_dart").as_uri()

directory = root / ".dart_tool"
directory.mkdir(exist_ok=True)
temporary = directory / "package_config.json.tmp"
temporary.write_text(json.dumps(config, indent=2) + "\n")
temporary.replace(directory / "package_config.json")
print("Nix dependencies configured. Use flutter run or flutter analyze.")
