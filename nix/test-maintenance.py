"""Regression checks for lock synchronization and the publishing boundary."""

import contextlib
import io
import json
import os
import runpy
import subprocess
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import yaml


SCRIPTS = Path(__file__).resolve().parent
WORKFLOW = Path(os.environ.get(
    "NIX_MAINTENANCE_WORKFLOW",
    SCRIPTS.parent / ".github/workflows/nix-maintenance.yml",
))


class MaintenanceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        previous = Path.cwd()
        os.chdir(self.root)
        self.addCleanup(os.chdir, previous)

    def run_script(self, name, *arguments):
        output = io.StringIO()
        with (
            patch("sys.argv", [name, *map(str, arguments)]),
            contextlib.redirect_stdout(output),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            runpy.run_path(str(SCRIPTS / name), run_name="__main__")
        return output.getvalue()

    def configure_fixture(self):
        Path("pubspec.yaml").write_text("name: harmonymusic\n")
        Path("pubspec.lock").write_text("packages: {}\nsdks: {}\n")
        Path("expected.json").write_text('{"sdks": {}, "packages": {}}')
        Path("config.json").write_text(json.dumps({"packages": [
            {"name": "harmonymusic", "rootUri": "old"},
            {"name": "youtube_explode_dart", "rootUri": "old"},
        ]}))
        Path(".dart_tool").mkdir()
        Path(".dart_tool/package_config.json").write_text("preserve me")

    def test_matching_lock_ignores_serialization_and_configures_local_sources(self):
        self.configure_fixture()
        self.run_script("configure-development.py", "config.json", "expected.json")
        packages = json.loads(Path(".dart_tool/package_config.json").read_text())["packages"]
        self.assertEqual(packages[0]["rootUri"], "../")
        self.assertEqual(packages[1]["rootUri"], (self.root / "packages/youtube_explode_dart").as_uri())

    def test_stale_or_missing_lock_preserves_existing_configuration(self):
        self.configure_fixture()
        for content in ('{"packages": {"changed": {}}, "sdks": {}}', None):
            if content is None:
                Path("expected.json").unlink()
            else:
                Path("expected.json").write_text(content)
            with self.assertRaises(SystemExit):
                self.run_script("configure-development.py", "config.json", "expected.json")
            self.assertEqual(Path(".dart_tool/package_config.json").read_text(), "preserve me")

    def test_workflow_routes_tag_pushes_and_daily_checks_to_releases(self):
        workflow = yaml.safe_load(WORKFLOW.read_text())
        update = next(step for step in workflow["jobs"]["prepare"]["steps"]
                      if step.get("id") == "update")
        for name in ("pubspec.lock", "flake.lock", "nix/pubspec.lock.json",
                     "nix/git-hashes.json", "nix/release.json",
                     "nix/release/pubspec.lock.json", "nix/release/git-hashes.json"):
            path = Path(name)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("{}")
        cases = [
            ("push", {"WORKFLOW_REF_TYPE": "tag"}, "release", "run .#update-release"),
            ("push", {"WORKFLOW_REF_TYPE": "branch"}, "lockfile", "run .#resolve-lockfile"),
            ("release", {}, "release", "run .#update-release"),
            ("schedule", {"WORKFLOW_SCHEDULE": "23 6 * * *"}, "release", "run .#update-release"),
            ("schedule", {"WORKFLOW_SCHEDULE": "23 5 1 * *"}, "nixpkgs", "flake update nixpkgs"),
            ("workflow_dispatch", {"REQUESTED_OPERATION": "release", "RELEASE_TAG": "v1.24.0"},
             "release", "run .#update-release -- v1.24.0"),
            ("workflow_dispatch", {"REQUESTED_OPERATION": "lockfile"}, "lockfile", "run .#resolve-lockfile"),
            ("workflow_dispatch", {"REQUESTED_OPERATION": "nixpkgs"}, "nixpkgs", "flake update nixpkgs"),
        ]
        for event, inputs, operation, command in cases:
            with self.subTest(event=event, inputs=inputs):
                output, log = self.root / "output", self.root / "commands"
                output.write_text("")
                log.write_text("")
                environment = {
                    **os.environ, "WORKFLOW_EVENT": event, "WORKFLOW_REF_TYPE": "",
                    "WORKFLOW_SCHEDULE": "", "REQUESTED_OPERATION": "", "RELEASE_TAG": "",
                    "GITHUB_OUTPUT": str(output), "NIX_COMMAND_LOG": str(log),
                    "RUNNER_TEMP": str(self.root / "runner"), **inputs,
                }
                stub = 'nix() { printf "%s\\n" "$*" >> "$NIX_COMMAND_LOG"; }\n'
                subprocess.run(["bash", "-e", "-o", "pipefail", "-c", stub + update["run"]],
                               env=environment, check=True, capture_output=True, text=True)
                self.assertEqual(output.read_text(), f"operation={operation}\n")
                self.assertEqual(log.read_text(), command + "\n")

    @patch("subprocess.run", return_value=SimpleNamespace(stdout='{"hash": "test-hash"}'))
    def test_resolution_and_prefetch_do_not_receive_github_tokens(self, run):
        Path("pubspec.yaml").write_text("name: harmonymusic\n")
        Path("pubspec.lock").write_text(json.dumps({"packages": {"plugin": {
            "source": "git", "description": {"url": "https://example.org/plugin", "resolved-ref": "abc"},
        }}}))
        with patch.dict(os.environ, {"GH_TOKEN": "test-only", "GITHUB_TOKEN": "test-only"}):
            self.run_script("update-lockfile.py", "--resolve")
        self.assertEqual(len(run.call_args_list), 2)
        for call in run.call_args_list:
            self.assertNotIn("GH_TOKEN", call.kwargs["env"])
            self.assertNotIn("GITHUB_TOKEN", call.kwargs["env"])

    def apply_fixture(self):
        Path("artifact").mkdir()
        Path("artifact/flake.lock").write_text("new")
        Path("flake.lock").write_text("old")

    @patch("subprocess.check_output", return_value="base\n")
    def test_publishing_accepts_only_data_for_the_selected_operation(self, _git):
        self.apply_fixture()
        output = self.run_script("apply-maintenance.py", "artifact", "nixpkgs", "base")
        self.assertEqual(Path("flake.lock").read_text(), "new")
        self.assertIn("branch=automation/nix-nixpkgs\n", output)

    @patch("subprocess.check_output", return_value="base\n")
    def test_publishing_rejects_extra_files_symlinks_missing_files_and_stale_base(self, _git):
        self.apply_fixture()
        extra = Path("artifact/script.py")
        extra.write_text("must not execute")
        with self.assertRaises(SystemExit):
            self.run_script("apply-maintenance.py", "artifact", "nixpkgs", "base")
        extra.unlink()
        Path("artifact/flake.lock").unlink()
        Path("artifact/flake.lock").symlink_to(self.root / "flake.lock")
        with self.assertRaises(SystemExit):
            self.run_script("apply-maintenance.py", "artifact", "nixpkgs", "base")
        Path("artifact/flake.lock").unlink()
        with self.assertRaises(SystemExit):
            self.run_script("apply-maintenance.py", "artifact", "nixpkgs", "base")
        Path("artifact/flake.lock").write_text("new")
        with self.assertRaises(SystemExit):
            self.run_script("apply-maintenance.py", "artifact", "nixpkgs", "stale")
        self.assertEqual(Path("flake.lock").read_text(), "old")


if __name__ == "__main__":
    unittest.main()
