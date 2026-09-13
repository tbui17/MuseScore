"""Trust boundaries: malformed input and corrupted artifacts never reach publication."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("pipeline", Path(__file__).resolve().parents[1] / "pipeline.py")
pipeline = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pipeline)


class TrustBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.expected = dict(repository=pipeline.REPOSITORY, requested_source_ref="feat/with-slash",
                             source_sha="a" * 40, framework_url="https://github.com/tbui17/muse_framework.git",
                             framework_sha="b" * 40, workflow_sha="c" * 40, run_id="123", run_attempt="1")
        self.name = "tbui17-MuseScore-5.0-x64-aaaaaaaaaaaa.zip"
        payload = self.directory / self.name
        payload.write_bytes(b"controlled artifact bytes, not a real application")
        self.digest = pipeline.hashlib.sha256(payload.read_bytes()).hexdigest()
        self.manifest = dict(self.expected, package=dict(filename=self.name, size=payload.stat().st_size, sha256=self.digest))
        self.save_manifest()
        (self.directory / "SHA256SUMS.txt").write_text(f"{self.digest}  {self.name}\n")

    def save_manifest(self):
        (self.directory / "build-manifest.json").write_text(json.dumps(self.manifest))

    def test_feature_ref_is_accepted_without_shell_interpretation(self):
        self.assertEqual(pipeline.valid_ref("feat/with-slash"), "feat/with-slash")
        for value in ("--upload-pack=bad", "main;touch bad", "https://example.com/repo", "main\nother", "main~1", "a/../b"):
            with self.subTest(value=value), self.assertRaises((ValueError, pipeline.subprocess.CalledProcessError)):
                pipeline.valid_ref(value)

    def test_release_namespace_rejects_ambiguous_refs(self):
        self.assertEqual(pipeline.valid_tag("fork-2026.09.13.1"), "fork-2026.09.13.1")
        for value in ("v5.0", "fork-2026.09.13.0", "fork-2026.09.13.1/other", "fork-2026.09.13.1\n"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                pipeline.valid_tag(value)

    def test_valid_manifest_and_checksum_agree(self):
        self.assertEqual(pipeline.verify_artifact(self.directory, self.expected)["package"]["sha256"], self.digest)

    def test_corrupt_binary_rejected(self):
        (self.directory / self.name).write_bytes(b"corrupt")
        with self.assertRaisesRegex(ValueError, "size or SHA-256"):
            pipeline.verify_artifact(self.directory, self.expected)

    def test_forged_source_rejected(self):
        self.manifest["source_sha"] = "d" * 40
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, "source_sha"):
            pipeline.verify_artifact(self.directory, self.expected)

    def test_traversal_filename_rejected(self):
        self.manifest["package"]["filename"] = "../escape.zip"
        self.save_manifest()
        with self.assertRaisesRegex(ValueError, "filename"):
            pipeline.verify_artifact(self.directory, self.expected)

    def test_metadata_only_and_extra_payloads_rejected(self):
        (self.directory / self.name).unlink()
        with self.assertRaisesRegex(ValueError, "exactly"):
            pipeline.verify_artifact(self.directory, self.expected)

    def test_checksum_mismatch_rejected(self):
        (self.directory / "SHA256SUMS.txt").write_text("0" * 64 + "  " + self.name)
        with self.assertRaisesRegex(ValueError, "Checksum"):
            pipeline.verify_artifact(self.directory, self.expected)

    def test_unqualified_compiler_cache_request_is_refused(self):
        class Args:
            source = self.directory
            output = self.directory / "provenance.json"

        environment = {
            "GITHUB_REPOSITORY": pipeline.REPOSITORY,
            "GITHUB_EVENT_NAME": "workflow_dispatch",
            "GITHUB_REF": "refs/heads/main",
            "WORKFLOW_SHA": "b" * 40,
            "SOURCE_REF": "main",
            "USE_CACHE": "true",
        }
        with patch.dict(os.environ, environment), patch.object(pipeline, "api") as api:
            with self.assertRaisesRegex(ValueError, "use_cache"):
                pipeline.preflight(Args())
            api.assert_not_called()

    def test_untrusted_event_never_calls_release_api(self):
        with patch.dict(os.environ, {"GITHUB_EVENT_NAME": "pull_request", "CREATE_RELEASE": "true"}), patch.object(pipeline, "api") as api:
            with self.assertRaisesRegex(ValueError, "manual-only"):
                pipeline.release(None)
            api.assert_not_called()

    def test_conflicting_tag_never_writes(self):
        provenance = self.directory.parent / (self.directory.name + "-provenance.json")
        provenance.write_text(json.dumps(self.expected))
        self.addCleanup(provenance.unlink)
        args = pipeline.argparse.Namespace(artifacts=self.directory, provenance=provenance)
        environment = {"GITHUB_EVENT_NAME": "workflow_dispatch", "GITHUB_REF": "refs/heads/main", "CREATE_RELEASE": "true",
                       "RELEASE_TAG": "fork-2026.09.13.1", "WORKFLOW_SHA": "c" * 40}
        calls = []

        def existing_tag(path, **kwargs):
            calls.append((path, kwargs.get("method", "GET")))
            return {"object": {"sha": "e" * 40}}

        with patch.dict(os.environ, environment), patch.object(pipeline, "api", side_effect=existing_tag):
            with self.assertRaisesRegex(ValueError, "already exists"):
                pipeline.release(args)
        self.assertEqual([method for _, method in calls], ["GET"])


if __name__ == "__main__":
    unittest.main()
