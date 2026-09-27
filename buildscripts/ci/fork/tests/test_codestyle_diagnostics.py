"""Exercise exact formatter evidence with real scratch Git repositories, not Qt."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[4]
SPEC = importlib.util.spec_from_file_location(
    "codestyle_diagnostics", ROOT / "buildscripts/ci/checkcodestyle/collect_diagnostics.py")
diag = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(diag)


class CodestyleDiagnosticsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="formatter evidence ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repository with spaces"
        self.repo.mkdir()
        self.output = self.root / "evidence"
        self.git("init", "-q")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        (self.repo / "src").mkdir()
        self.source = self.repo / "src/file with spaces.cpp"
        self.original = b'int main() {\n  return 0;\n}\n'
        self.formatted = b'int main()\n{\n    return 0;\n}\n'
        self.source.write_bytes(self.original)
        (self.repo / "outside.txt").write_text("unchanged\n")
        self.git("add", ".")
        self.git("commit", "-qm", "Fixture source")

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.repo), *args], check=True,
                              capture_output=True, timeout=10).stdout

    def collect(self):
        diag.collect(self.repo, "src", self.output)
        return json.loads((self.output / "manifest.json").read_text())

    def test_clean_repository_records_no_changes(self):
        manifest = self.collect()
        self.assertEqual(manifest["files"], [])
        self.assertEqual((self.output / "changes.patch").read_bytes(), b"")
        diag.verify_stable(self.repo, "src", self.output)
        self.assertTrue((self.output / "idempotence.txt").is_file())

    def test_exact_bytes_and_git_blob_identities_are_preserved(self):
        self.source.write_bytes(self.formatted)
        manifest = self.collect()
        self.assertEqual(manifest["source_sha"], self.git("rev-parse", "HEAD").decode().strip())
        self.assertEqual(manifest["scope"], "src")
        self.assertEqual(len(manifest["files"]), 1)
        record = manifest["files"][0]
        self.assertEqual(record["before_blob"], self.git("rev-parse", "HEAD:src/file with spaces.cpp").decode().strip())
        self.assertEqual(record["after_blob"], self.git("hash-object", str(self.source)).decode().strip())
        for folder, expected in (("before", self.original), ("after", self.formatted)):
            self.assertEqual((self.output / folder / record["path"]).read_bytes(), expected)
            self.assertEqual(record[folder + "_sha256"], diag.digest(expected))
        changes = (self.output / "changes.patch").read_bytes()
        self.assertEqual(manifest["patch_sha256"], diag.digest(changes))
        self.assertIn(record["before_blob"].encode(), changes)
        self.assertIn(record["after_blob"].encode(), changes)
        self.assertEqual(self.source.read_bytes(), self.formatted, "Collection must not apply/revert a patch")

    def test_second_pass_must_match_exactly(self):
        self.source.write_bytes(self.formatted)
        self.collect()
        self.source.write_bytes(self.formatted + b"\n")
        with self.assertRaisesRegex(ValueError, "changed again"):
            diag.verify_stable(self.repo, "src", self.output)
        self.assertFalse((self.output / "idempotence.txt").exists())

    def test_changed_head_and_tampered_patch_are_rejected(self):
        self.collect()
        (self.output / "changes.patch").write_bytes(b"tampered")
        with self.assertRaisesRegex(ValueError, "identity mismatch"):
            diag.verify_stable(self.repo, "src", self.output)
        (self.output / "changes.patch").write_bytes(b"")
        self.git("commit", "--allow-empty", "-qm", "New source")
        with self.assertRaisesRegex(ValueError, "identity mismatch"):
            diag.verify_stable(self.repo, "src", self.output)

    def test_staged_formatting_is_not_omitted(self):
        self.source.write_bytes(self.formatted)
        self.git("add", "src")
        self.assertEqual(len(self.collect()["files"]), 1)

    def test_untracked_logs_are_not_captured_as_source(self):
        (self.repo / "private-untracked-log.txt").write_text("not formatter input")
        self.assertEqual(self.collect()["files"], [])

    def test_deleted_added_or_out_of_scope_changes_fail_closed(self):
        changes = ("deleted", "added", "outside")
        for change in changes:
            with self.subTest(change=change):
                self.git("reset", "--hard", "-q", "HEAD")
                self.git("clean", "-fdq")
                if change == "deleted":
                    self.source.unlink()
                elif change == "added":
                    (self.repo / "src/new.cpp").write_text("new")
                    self.git("add", "src/new.cpp")
                else:
                    (self.repo / "outside.txt").write_text("changed")
                with self.assertRaises(ValueError):
                    self.collect()
                self.assertFalse(self.output.exists())

    def test_symlink_output_is_not_read(self):
        self.source.unlink()
        try:
            self.source.symlink_to(self.repo / "outside.txt")
        except OSError:
            self.skipTest("This platform cannot create symlinks")
        with self.assertRaises(ValueError):
            self.collect()
        self.assertFalse(self.output.exists())

    def test_size_budget_is_enforced_before_evidence_creation(self):
        self.source.write_bytes(self.formatted)
        with patch.object(diag, "MAX_FILE_BYTES", 4):
            with self.assertRaisesRegex(ValueError, "bounded regular"):
                self.collect()
        with patch.object(diag, "MAX_TOTAL_BYTES", 4):
            with self.assertRaisesRegex(ValueError, "total size"):
                self.collect()
        self.assertFalse(self.output.exists())

    def test_second_pass_out_of_scope_changes_are_rejected(self):
        self.collect()
        (self.repo / "outside.txt").write_text("changed after evidence capture")
        with self.assertRaisesRegex(ValueError, "changed again"):
            diag.verify_stable(self.repo, "src", self.output)
        self.assertFalse((self.output / "idempotence.txt").exists())

    def test_second_pass_new_staged_out_of_scope_file_is_rejected(self):
        self.collect()
        (self.repo / "new-outside.txt").write_text("unapproved tracked change")
        self.git("add", "new-outside.txt")
        with self.assertRaisesRegex(ValueError, "changed again"):
            diag.verify_stable(self.repo, "src", self.output)
        self.assertFalse((self.output / "idempotence.txt").exists())

    def test_failed_reverification_removes_stale_success_marker(self):
        self.collect()
        diag.verify_stable(self.repo, "src", self.output)
        self.assertTrue((self.output / "idempotence.txt").exists())
        self.source.write_bytes(self.formatted)
        with self.assertRaisesRegex(ValueError, "changed again"):
            diag.verify_stable(self.repo, "src", self.output)
        self.assertFalse((self.output / "idempotence.txt").exists())

    def test_existing_evidence_is_never_overwritten(self):
        self.collect()
        original = (self.output / "manifest.json").read_bytes()
        with self.assertRaises(FileExistsError):
            self.collect()
        self.assertEqual((self.output / "manifest.json").read_bytes(), original)


class CodestyleWorkflowTests(unittest.TestCase):
    def test_failures_are_not_masked_and_framework_runs_independently(self):
        workflow = (ROOT / ".github/workflows/check_codestyle.yml").read_text()
        self.assertNotIn("continue-on-error", workflow)
        self.assertNotIn("|| true", workflow)
        framework = workflow.split("    - name: Test MF coding style\n", 1)[1].split("    - name:", 1)[0]
        self.assertIn("steps.tools.outcome == 'success'", framework)
        self.assertIn("!cancelled()", framework)
        self.assertIn("working-directory: muse", framework)
        self.assertIn("shell: bash", framework)
        self.assertIn("./framework/", framework)
        self.assertIn("always() && steps.checkout.outcome == 'success'", workflow)
        self.assertIn("collect_diagnostics.py verify-stable", workflow)


if __name__ == "__main__":
    unittest.main()
