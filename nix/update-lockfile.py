"""Export a resolved Pub lockfile and record Nix hashes for its Git sources."""

import argparse
import json
import os
import subprocess
from pathlib import Path

import yaml


def encode(value):
    return json.dumps(value, indent=2, sort_keys=True) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", nargs="?", type=Path, default=Path("pubspec.lock"))
    parser.add_argument("output", nargs="?", type=Path, default=Path("nix/pubspec.lock.json"))
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--resolve", action="store_true", help="Resolve Pub dependencies with Flutter first")
    args = parser.parse_args()

    environment = {
        name: value for name, value in os.environ.items()
        if name not in ("GH_TOKEN", "GITHUB_TOKEN")
    }

    if args.resolve:
        manifest_path = args.source.parent / "pubspec.yaml"
        manifest = yaml.safe_load(manifest_path.read_text())
        if manifest.get("name") != "harmonymusic":
            parser.error("dependency resolution requires a Harmony Music manifest")
        subprocess.run(
            ["flutter", "--suppress-analytics", "pub", "get"],
            cwd=args.source.parent, env=environment, check=True,
        )

    lock = yaml.safe_load(args.source.read_text())
    hashes_path = args.output.with_name("git-hashes.json")
    hashes = json.loads(hashes_path.read_text()) if hashes_path.exists() else {}
    resolved_hashes = {}
    for name, package in lock["packages"].items():
        if package["source"] != "git":
            continue
        description = package["description"]
        url, rev = description["url"], description["resolved-ref"]
        previous = hashes.get(name, {})
        if previous.get("url") == url and previous.get("rev") == rev and previous.get("hash"):
            resolved_hashes[name] = previous
        elif args.check:
            parser.error(f"stale Git hash for {name}; run harmony-update-lockfile")
        else:
            result = subprocess.run(
                ["nix-prefetch-git", "--fetch-submodules", "--url", url, "--rev", rev],
                text=True, capture_output=True, check=True, env=environment,
            )
            resolved_hashes[name] = {"url": url, "rev": rev, "hash": json.loads(result.stdout)["hash"]}

    for path, content in [(args.output, encode(lock)), (hashes_path, encode(resolved_hashes))]:
        if args.check:
            if not path.exists() or path.read_text() != content:
                parser.error(f"{path} is stale; run harmony-update-lockfile")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)


if __name__ == "__main__":
    main()
