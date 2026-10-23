"""Regression checks for lock synchronization and the publishing boundary."""

import contextlib
import io
import json
import os
import runpy
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch


SCRIPTS = Path(__file__).resolve().parent


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
