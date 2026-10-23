"""Pin a published stable release without changing the checkout's Pub lockfile."""

import argparse
import json
import os
import shutil
import stat
import subprocess
import tempfile
import urllib.parse
import urllib.request
from pathlib import Path

import yaml


API = "https://api.github.com/repos/NPP-exe/Harmony-Music"


def request(path):
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "Harmony-Music-flake"}
    token = os.environ.get("GH_TOKEN")
    if token:
        headers["Authorization"] = "Bearer " + token
    query = urllib.request.Request(
        API + path,
        headers=headers,
    )
    with urllib.request.urlopen(query, timeout=60) as response:
        return json.load(response)


def run(*command, **kwargs):
    # Public source downloads and dependency resolution do not need the API token.
    kwargs.setdefault("env", {
        name: value for name, value in os.environ.items()
        if name not in ("GH_TOKEN", "GITHUB_TOKEN")
    })
    return subprocess.run(command, check=True, text=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "tag", nargs="?", help="Published stable tag; defaults to the latest stable release"
    )
    parser.add_argument(
        "--force", action="store_true", help="Resolve dependencies again even if this release is pinned"
    )
    args = parser.parse_args()
    root = Path.cwd()
    destination = root / "nix/release"
    if not (root / "flake.nix").is_file() or not destination.is_dir():
        parser.error("run from the Harmony Music project root")

    release = request(
        "/releases/tags/" + urllib.parse.quote(args.tag, safe="")
        if args.tag else "/releases/latest"
    )
    if release["draft"] or release["prerelease"]:
        parser.error("only published stable releases are supported")
    release_tag = release["tag_name"]
    tag = urllib.parse.quote(release_tag, safe="")
    target = request("/git/ref/tags/" + tag)["object"]
    while target["type"] == "tag":
        target = request("/git/tags/" + target["sha"])["object"]
    if target["type"] != "commit":
        parser.error("the release tag does not point to a commit")
    revision = target["sha"]
    metadata_path = root / "nix/release.json"
    current = json.loads(metadata_path.read_text()) if metadata_path.exists() else {}
    if (
        not args.force
        and current.get("tag") == release_tag
        and current.get("rev") == revision
        and all((destination / name).is_file() for name in ("pubspec.lock.json", "git-hashes.json"))
    ):
        print(f"{release_tag} ({revision}) is already pinned; nothing to update.")
        return
    url = f"https://github.com/NPP-exe/Harmony-Music/archive/{revision}.tar.gz"
    fetched = json.loads(run(
        "nix", "--extra-experimental-features", "nix-command flakes",
        "store", "prefetch-file", "--unpack", "--json", url, capture_output=True,
    ).stdout)

    with tempfile.TemporaryDirectory(prefix="harmony-release-") as temporary:
        source = Path(temporary) / "source"
        shutil.copytree(fetched["storePath"], source, copy_function=shutil.copyfile)
        for directory, _, _ in os.walk(source):
            path = Path(directory)
            path.chmod(path.stat().st_mode | stat.S_IWUSR)
        manifest = yaml.safe_load((source / "pubspec.yaml").read_text())
        version = manifest["version"].split("+", 1)[0]
        if release_tag not in (version, "v" + version):
            parser.error("release tag and pubspec.yaml version do not match")

        run("flutter", "--suppress-analytics", "pub", "get", cwd=source)
        staging = Path(temporary) / "packaging"
        staging.mkdir()
        if (destination / "git-hashes.json").exists():
            shutil.copyfile(destination / "git-hashes.json", staging / "git-hashes.json")
        run("harmony-update-lockfile", str(source / "pubspec.lock"), str(staging / "pubspec.lock.json"))
        metadata = {"version": version, "tag": release_tag, "rev": revision, "hash": fetched["hash"]}
        for filename in ("pubspec.lock.json", "git-hashes.json"):
            shutil.copyfile(staging / filename, destination / filename)
        metadata_path.write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"Pinned {release_tag} ({revision}). Review the diff, then run nix flake check.")


if __name__ == "__main__":
    main()
