"""Run policy against local Git repositories, never a live owner branch."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from test_pipeline import pipeline


class SubmodulePolicyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="fork policy ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        self.framework = self.root / "framework"
        for path in (self.source, self.framework):
            path.mkdir()
            self.git(path, "init", "--initial-branch=feature-work")
            self.git(path, "config", "user.name", "CI fixture")
            self.git(path, "config", "user.email", "fixture@example.invalid")
        (self.framework / "feature.txt").write_text("preserved feature work\n")
        self.git(self.framework, "add", "feature.txt")
        self.git(self.framework, "commit", "-m", "fixture feature commit")
        self.sha = self.git(self.framework, "rev-parse", "HEAD")
        self.url = "https://github.com/tbui17/muse_framework.git"
        environment = {
            "GIT_CONFIG_COUNT": "2",
            "GIT_CONFIG_KEY_0": "url." + self.framework.as_uri() + ".insteadOf",
            "GIT_CONFIG_VALUE_0": self.url,
            "GIT_CONFIG_KEY_1": "protocol.file.allow",
            "GIT_CONFIG_VALUE_1": "always",
        }
        self.environment = patch.dict(os.environ, environment)
        self.environment.start()
        self.addCleanup(self.environment.stop)

    @staticmethod
    def git(path, *args):
        return subprocess.run(["git", "-C", str(path), *args], check=True, text=True, capture_output=True).stdout.strip()

    def commit_pin(self, sha, url=None):
        (self.source / ".gitmodules").write_text(f'[submodule "muse_framework"]\n\tpath = muse\n\turl = {url or self.url}\n')
        self.git(self.source, "add", ".gitmodules")
        self.git(self.source, "update-index", "--add", "--cacheinfo", "160000," + sha + ",muse")
        self.git(self.source, "commit", "-m", "exact framework pin")

    def test_fork_feature_commit_is_preserved_without_main_ancestry(self):
        self.commit_pin(self.sha)
        url, sha = pipeline.check_submodule(self.source, pipeline.REPOSITORY)
        self.assertEqual((url, sha), (self.url, self.sha))
        self.assertEqual((self.source / "muse/feature.txt").read_text(), "preserved feature work\n")

    def test_unavailable_gitlink_fails_without_fallback(self):
        self.commit_pin("a" * 40)
        with self.assertRaises(subprocess.CalledProcessError):
            pipeline.check_submodule(self.source, pipeline.REPOSITORY)

    def test_unapproved_owner_rejected_before_initialization(self):
        self.commit_pin(self.sha, "https://github.com/unapproved/muse_framework.git")
        with self.assertRaisesRegex(ValueError, "Framework URL"):
            pipeline.check_submodule(self.source, pipeline.REPOSITORY)
        self.assertFalse((self.source / "muse").exists())


if __name__ == "__main__":
    unittest.main()
