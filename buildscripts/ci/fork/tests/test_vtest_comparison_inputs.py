"""Run the visual preflight and inspect its workflow wiring, without rendering."""
import copy
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[4]
SCRIPT = ROOT / "buildscripts/ci/vtests/resolve_comparison.py"
WORKFLOW = ROOT / ".github/workflows/check_visual_tests.yml"
BASE = "a" * 40
CURRENT = "b" * 40
PR = {"number": 42, "pull_request": {"base": {"ref": "moving-branch", "sha": BASE},
                                    "head": {"sha": "c" * 40}, "title": "Palette checks"}}


class ComparisonInputTests(unittest.TestCase):
    def run_preflight(self, *, event=None, event_name="pull_request", candidate=CURRENT,
                      number="260927001", raw=None, missing_event=False, missing_output=False):
        with tempfile.TemporaryDirectory(prefix="visual preflight ") as temp:
            root = Path(temp)
            event_path = root / "event.json"
            if not missing_event:
                event_path.write_text(raw if raw is not None else json.dumps(PR if event is None else event),
                                      encoding="utf-8")
            output_path = root / "outputs"
            output_path.write_text("previous_output=preserved\n", encoding="utf-8")
            env = dict(os.environ, GITHUB_EVENT_PATH=str(event_path), GITHUB_EVENT_NAME=event_name,
                       GITHUB_SHA=candidate, BUILD_NUMBER=number, GITHUB_OUTPUT=str(output_path))
            if missing_output:
                env.pop("GITHUB_OUTPUT")
            result = subprocess.run([sys.executable, str(SCRIPT)], env=env, cwd=root,
                                    capture_output=True, text=True, timeout=10, check=False)
            return result, output_path.read_text(encoding="utf-8")

    def assert_success(self, **kwargs):
        result, output = self.run_preflight(**kwargs)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        lines = output.splitlines()
        self.assertEqual(len(lines), 5, "Preflight must emit exactly four single-line records")
        self.assertEqual(lines[0], "previous_output=preserved")
        values = dict(line.split("=", 1) for line in lines[1:])
        self.assertEqual(set(values), {"do_run", "reference_ref", "candidate_ref", "artifact_name"})
        self.assertEqual(values["do_run"], "true")
        return values

    def assert_rejected(self, **kwargs):
        result, output = self.run_preflight(**kwargs)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Invalid visual-test inputs:", result.stderr)
        self.assertEqual(output, "previous_output=preserved\n", "Invalid inputs must emit no success output")
        return result

    def test_pr_uses_event_base_sha_and_candidate_merge_sha(self):
        values = self.assert_success()
        self.assertEqual(values["reference_ref"], BASE)
        self.assertEqual(values["candidate_ref"], CURRENT)
        self.assertIn("PR 42 Palette checks", values["artifact_name"])

    def test_base_branch_name_is_not_resolved_or_used(self):
        event = copy.deepcopy(PR)
        event["pull_request"]["base"]["ref"] = "renamed-or-deleted-branch"
        values = self.assert_success(event=event)
        self.assertEqual(values["reference_ref"], BASE)

    def test_manual_run_accepts_only_an_explicit_immutable_reference(self):
        values = self.assert_success(event_name="workflow_dispatch", event={"inputs": {"reference_sha": BASE}})
        self.assertEqual(values["reference_ref"], BASE)
        self.assertEqual(values["candidate_ref"], CURRENT)
        self.assertIn("manual " + BASE[:12], values["artifact_name"])

    def test_manual_run_without_reference_cannot_succeed_by_skipping(self):
        for event in ({}, {"inputs": {}}, {"inputs": None}, {"inputs": {"reference_sha": ""}}):
            with self.subTest(event=event):
                self.assert_rejected(event_name="workflow_dispatch", event=event)

    def test_invalid_reference_values_are_rejected(self):
        for value in ("main", "HEAD~1", "a" * 7, "g" * 40, "0" * 40, " " + BASE, BASE + "\n", 42):
            for event_name in ("pull_request", "workflow_dispatch"):
                with self.subTest(value=value, event_name=event_name):
                    event = copy.deepcopy(PR) if event_name == "pull_request" else {"inputs": {}}
                    if event_name == "pull_request":
                        event["pull_request"]["base"]["sha"] = value
                    else:
                        event["inputs"]["reference_sha"] = value
                    self.assert_rejected(event_name=event_name, event=event)

    def test_invalid_candidate_is_rejected(self):
        for candidate in ("main", "", "g" * 40, "0" * 40, CURRENT + "\n"):
            with self.subTest(candidate=candidate):
                self.assert_rejected(candidate=candidate)

    def test_self_comparison_is_rejected_case_insensitively(self):
        for event_name, event in (("pull_request", PR),
                                  ("workflow_dispatch", {"inputs": {"reference_sha": BASE}})):
            with self.subTest(event_name=event_name):
                self.assert_rejected(candidate=BASE.upper(), event_name=event_name, event=event)

    def test_hex_shas_are_canonicalized(self):
        event = copy.deepcopy(PR)
        event["pull_request"]["base"]["sha"] = BASE.upper()
        values = self.assert_success(event=event, candidate=CURRENT.upper())
        self.assertEqual(values["reference_ref"], BASE)
        self.assertEqual(values["candidate_ref"], CURRENT)

    def test_missing_or_malformed_event_fails_closed(self):
        self.assert_rejected(missing_event=True)
        for raw in ("{", "null", "[]", '"text"'):
            with self.subTest(raw=raw):
                self.assert_rejected(raw=raw)
        for event in ({}, {"pull_request": []}, {"pull_request": {"base": []}}):
            with self.subTest(event=event):
                self.assert_rejected(event=event)

    def test_invalid_pr_number_or_title_is_rejected(self):
        for field, value in (("number", True), ("number", -1), ("number", "42"), ("title", [])):
            with self.subTest(field=field, value=value):
                event = copy.deepcopy(PR)
                (event if field == "number" else event["pull_request"])[field] = value
                self.assert_rejected(event=event)

    def test_invalid_build_numbers_cannot_inject_output(self):
        for value in ("", "42\ndo_run=false", " 42", "x", "4" * 21):
            with self.subTest(value=value):
                self.assert_rejected(number=value)

    def test_title_cannot_inject_output_records_or_artifact_path_characters(self):
        event = copy.deepcopy(PR)
        event["pull_request"]["title"] = 'Title\r\ndo_run=false\u2028candidate_ref=evil\x00<>:"/\\|?*'
        values = self.assert_success(event=event)
        self.assertEqual(values["candidate_ref"], CURRENT)
        self.assertTrue(values["artifact_name"].isprintable())
        self.assertFalse(set(values["artifact_name"]) & set('":<>|*?/\\'))

    def test_long_unicode_artifact_name_is_bounded_without_broken_utf8(self):
        event = copy.deepcopy(PR)
        event["pull_request"]["title"] = "音符" * 500
        name = self.assert_success(event=event)["artifact_name"]
        self.assertLessEqual(len(name.encode("utf-8")), 200)
        self.assertNotIn("\ufffd", name)

    def test_unsupported_events_and_missing_output_path_fail(self):
        self.assert_rejected(event_name="push")
        self.assert_rejected(event_name="schedule")
        self.assert_rejected(missing_output=True)


class WorkflowWiringTests(unittest.TestCase):
    def job(self, name):
        source = WORKFLOW.read_text(encoding="utf-8")
        match = re.search(r"^  " + name + r":\n(.*?)(?=^  [a-z_]+:|\Z)", source, re.M | re.S)
        self.assertIsNotNone(match, name)
        return match.group(1)

    def test_preflight_is_unconditional_and_receives_its_script(self):
        setup = self.job("setup")
        self.assertIn("run: python3 ./buildscripts/ci/vtests/resolve_comparison.py", setup)
        self.assertIn("sparse-checkout-cone-mode: false", setup)
        self.assertIn("          buildscripts/ci/vtests/resolve_comparison.py", setup)
        self.assertIn("candidate_ref: ${{ steps.output_data.outputs.candidate_ref }}", setup)
        self.assertNotIn("      if:", setup)
        self.assertNotIn("pull_request.title", setup)

    def test_builds_and_comparison_consume_frozen_outputs(self):
        for job, output in (("build_current", "candidate_ref"), ("build_reference", "reference_ref"),
                            ("generate_and_compare", "candidate_ref")):
            with self.subTest(job=job):
                source = self.job(job)
                self.assertIn("ref: ${{ needs.setup.outputs." + output + " }}", source)
                self.assertIn("persist-credentials: false", source)
                self.assertNotIn("base.ref", source)

    def test_manual_reference_is_required_and_differences_fail_for_all_triggers(self):
        source = WORKFLOW.read_text(encoding="utf-8")
        self.assertRegex(source, r"workflow_dispatch:\n    inputs:\n      reference_sha:\n.*\n        required: true")
        comparison = self.job("generate_and_compare")
        self.assertIn("if: contains( env.VTEST_DIFF_FOUND, 'true')", comparison)
        self.assertIn("        exit 1", comparison)
        self.assertNotIn("    - name: Comment push commit", comparison)
        self.assertEqual(comparison.count("        ./vtest/vtest-compare-pngs.sh --ci 1"), 3)
        self.assertIn("bash ./buildscripts/ci/vtests/generate_pngs.sh", comparison)


if __name__ == "__main__":
    unittest.main()
