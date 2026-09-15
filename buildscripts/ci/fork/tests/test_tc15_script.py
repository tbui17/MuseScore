"""Static contract for TC15's bounded non-navigation notation-page readiness gate."""
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

    def test_wait_uses_nonblocking_page_state_and_explicit_budget(self):
        self.assertIn('var NOTATION_PAGE_URI = "musescore://notation"', self.source)
        self.assertIn("var NOTATION_READY_TIMEOUT_MSEC = 30000", self.source)
        self.assertIn("var NOTATION_READY_POLL_MSEC = 100", self.source)
        self.assertIn(
            "api.interactive.isOpened(NOTATION_PAGE_URI)",
            self.source,
        )
        self.assertIn(
            "api.testflow.seeChanges(NOTATION_READY_POLL_MSEC)",
            self.source,
        )
        self.assertIn(
            "was not open within \" + NOTATION_READY_TIMEOUT_MSEC",
            self.source,
        )
        helper_start = self.source.index("function waitForNotationPage")
        helper_end = self.source.index("var testCase", helper_start)
        helper = self.source[helper_start:helper_end]
        self.assertNotRegex(helper, r"api\.navigation\.")
        self.assertNotIn("api.testflow.sleep(", helper)
        self.assertEqual(
            len(re.findall(r"function waitForNotationPage\(", self.source)),
            1,
        )
        self.assertIn(
            "waitForNotationPage()",
            self.source,
        )

        readiness_step = self.source[
            self.source.index('{name: "Wait for notation page to settle"'):
            self.source.index('{name: "Verify \'Score view\' was announced on score open"')
        ]
        self.assertNotRegex(readiness_step, r"api\.navigation\.")

    def test_readiness_wait_follows_pre_submit_control_selection_and_precedes_assertions(self):
        create_score = self.source.index('{name: "Create score"')
        done_selection = self.source.index(
            'api.navigation.goToControl("NewScoreDialog", "BottomPanel", "Done")',
            create_score,
        )
        done_guard = self.source.index("if (!doneReady)", create_score)
        create_submit = self.source.index('api.keyboard.key("Return")', create_score)
        settle_step = self.source.index('{name: "Wait for notation page to settle"')
        wait_for_page = self.source.index(
            "waitForNotationPage()",
            settle_step,
        )
        first_navigation_assertion = self.source.index(
            "Expected announcement after opening score",
            settle_step,
        )

        self.assertNotIn("NewScore.done()", self.source)
        self.assertLess(done_selection, done_guard)
        self.assertLess(done_guard, create_submit)
        self.assertLess(create_submit, wait_for_page)
        self.assertLess(wait_for_page, first_navigation_assertion)

        return_step = self.source.index(
            '{name: "Return to score canvas — should announce \'Score view\'"',
        )
        announcement_capture = self.source.index(
            "var announcementBeforeReturn = api.accessibility.announcement()",
            return_step,
        )
        reentry_action = self.source.index(
            'api.navigation.goToControl("NotationView", "ScoreView", "Score")',
            return_step,
        )
        self.assertLess(announcement_capture, reentry_action)


if __name__ == "__main__":
    unittest.main()
