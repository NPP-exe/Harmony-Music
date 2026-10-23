"""Apply only maintenance data; run from the trusted publishing checkout."""

import argparse
import shutil
import subprocess
from pathlib import Path


OPERATIONS = {
    "release": (
        "chore(nix): update stable release",
        {"nix/release.json", "nix/release/pubspec.lock.json", "nix/release/git-hashes.json"},
    ),
    "lockfile": (
        "chore(nix): synchronize Dart dependency lock",
        {"pubspec.lock", "nix/pubspec.lock.json", "nix/git-hashes.json"},
    ),
    "nixpkgs": ("chore(nix): update nixpkgs", {"flake.lock"}),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path)
    parser.add_argument("operation", choices=OPERATIONS)
    parser.add_argument("base")
    args = parser.parse_args()
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    if commit != args.base:
        parser.error("default branch changed during preparation; rerun maintenance")

    title, allowed = OPERATIONS[args.operation]
    found = set()
    for path in args.artifact.rglob("*"):
        if path.is_symlink():
            parser.error("artifact must not contain symbolic links")
        if path.is_dir():
            continue
        relative = path.relative_to(args.artifact).as_posix()
        if not path.is_file() or relative not in allowed:
            parser.error(f"unexpected artifact file: {relative}")
        found.add(relative)
    if found != allowed:
        parser.error("artifact is missing required update files")

    # Validate the complete artifact and destinations before copying anything.
    root = Path.cwd().resolve()
    for relative in allowed:
        destination = root / relative
        if destination.is_symlink() or destination.resolve() != destination:
            parser.error(f"destination must not traverse symbolic links: {relative}")
    for relative in sorted(allowed):
        destination = root / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(args.artifact / relative, destination)
    print(f"branch=automation/nix-{args.operation}")
    print(f"title={title}")


if __name__ == "__main__":
    main()
