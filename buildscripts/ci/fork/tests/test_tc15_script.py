"""Static contract for the TC15 GUI test's bounded navigation readiness gate."""
from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[4]
SCRIPT_PATH = REPOSITORY_ROOT / "share" / "testflowscripts" / "TC15_RegionEntryAnnounce.js"
EXPECTED_STEPS = [
    "Close score (if opened) and go to home to start",
    "Open New Score Dialog",
    "Select Instruments",
    "Create score",
    "Wait for notation page to settle",
    "Verify 'Score view' was announced on score open",
    "Tab to status bar — should NOT re-announce 'Score view'",
    "Return to score canvas — should announce 'Score view'",
    "F6 to next section — should NOT re-announce 'Score view'",
]


class TC15ScriptContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SCRIPT_PATH.read_text(encoding="utf-8")

    def test_declares_exact_reviewed_nine_step_case(self):
        step_names = re.findall(
            r'^\s*\{name: "([^"]+)", func: function\(\) \{',
            self.source,
            flags=re.MULTILINE,
        )
        self.assertEqual(step_names, EXPECTED_STEPS)

    def test_wait_uses_stable_navigation_probe_and_explicit_budget(self):
        self.assertIn("var NAVIGATION_READY_TIMEOUT_MSEC = 30000", self.source)
        self.assertIn("var NAVIGATION_READY_POLL_MSEC = 100", self.source)
        self.assertIn(
            "return api.navigation.goToControl(sectionName, panelName, controlName)",
            self.source,
        )
        self.assertIn(
            "api.testflow.seeChanges(NAVIGATION_READY_POLL_MSEC)",
            self.source,
        )
        self.assertIn(
            "was not available within \" + NAVIGATION_READY_TIMEOUT_MSEC",
            self.source,
        )
        self.assertNotIn("api.navigation.panels(", self.source)
        self.assertNotIn("api.navigation.controls(", self.source)
        self.assertNotIn("api.testflow.sleep(", self.source)
        self.assertIn(
            'waitForNavigationControl("NewScoreDialog", "BottomPanel", "Done")',
            self.source,
        )
        self.assertIn(
            'waitForNavigationControl("NotationView", "ScoreView", "Score")',
            self.source,
        )

    def test_readiness_wait_precedes_score_creation_and_navigation_assertions(self):
        create_score = self.source.index('{name: "Create score"')
        wait_for_done = self.source.index(
            'waitForNavigationControl("NewScoreDialog", "BottomPanel", "Done")',
            create_score,
        )
        create_done = self.source.index("NewScore.done()", create_score)
        settle_step = self.source.index('{name: "Wait for notation page to settle"')
        wait_for_score = self.source.index(
            'waitForNavigationControl("NotationView", "ScoreView", "Score")',
            settle_step,
        )
        first_navigation_assertion = self.source.index(
            "Expected announcement after opening score",
            settle_step,
        )

        self.assertLess(wait_for_done, create_done)
        self.assertLess(create_done, wait_for_score)
        self.assertLess(wait_for_score, first_navigation_assertion)


if __name__ == "__main__":
    unittest.main()
