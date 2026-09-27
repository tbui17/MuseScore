"""Check TC14's assertion paths, not Qt, screen-reader speech, or native GUI behavior."""
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[4]
SCRIPT = ROOT / "share/testflowscripts/TC14_CommandPaletteAnnounce.js"
NODE = shutil.which("node")

HARNESS = r"""
const fs = require('fs');
const vm = require('vm');
const scenario = process.argv[1];
let query = '', announcement = '', palette = false, about = false, selectedAll = false;
let panel = '', control = '';
const hasResults = () => !query.includes('zzznonexistentcommandzzz');
const sandbox = {api: {
  dispatcher: {dispatch(action) {
    if (action !== 'command-palette') throw new Error('Unexpected dispatch: ' + action);
    palette = true; query = ''; panel = 'CommandPaletteSearch'; control = 'CommandPaletteSearchField';
  }},
  keyboard: {
    text(text) { query = selectedAll ? text : query + text; selectedAll = false; },
    key(key, modifier) {
      if (key === 'A' && modifier === 'CTRL') { selectedAll = true; return; }
      if (key === 'Down' || key === 'Up') {
        if (hasResults()) announcement = 'About MuseScore, 1 of 1';
        else if (scenario !== 'silent-empty') announcement = 'No matching commands';
      } else if (key === 'Return') {
        if (hasResults() || scenario === 'stale-command') { about = true; palette = false; }
      } else if (key === 'Escape') {
        if (about) about = false;
        else if (scenario !== 'escape-stuck') palette = false;
      } else throw new Error('Unexpected key: ' + key);
    }
  },
  accessibility: {announcement: () => announcement},
  interactive: {isOpened(uri) {
    if (uri !== 'musescore://about/musescore') throw new Error('Unexpected URI');
    return about;
  }},
  navigation: {
    goToControl(section, nextPanel, nextControl) {
      if (!palette || scenario === 'search-disabled') return false;
      if (section !== 'CommandPaletteDialog' || nextPanel !== 'CommandPaletteSearch'
          || nextControl !== 'CommandPaletteSearchField') throw new Error('Unexpected navigation target');
      panel = scenario === 'search-inactive' ? 'WrongPanel' : nextPanel;
      control = nextControl;
      return true;
    },
    activeSection: () => palette ? 'CommandPaletteDialog' : 'OtherDialog',
    activePanel: () => panel,
    activeControl: () => control
  },
  testflow: {
    waitPopup() {}, seeChanges() {}, setInterval() {},
    fatal(message) { throw new Error(message); },
    runTestCase(testCase) { for (const step of testCase.steps) step.func(); }
  }
}};
try {
  vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync(process.argv[2], 'utf8'), sandbox, {timeout: 1000});
  sandbox.main();
  console.log('PASS');
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
"""


@unittest.skipUnless(NODE, "Node.js is required for testflow script contract checks")
class TC14ScriptTests(unittest.TestCase):
    def run_scenario(self, scenario):
        return subprocess.run([NODE, "-e", HARNESS, scenario, str(SCRIPT)], text=True,
                              capture_output=True, timeout=10, check=False)

    def test_complete_script_accepts_the_expected_contract(self):
        result = self.run_scenario("healthy")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("PASS", result.stdout)

    def test_silent_empty_results_are_rejected(self):
        result = self.run_scenario("silent-empty")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("empty-result feedback", result.stderr)

    def test_unreachable_search_is_rejected(self):
        result = self.run_scenario("search-disabled")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Search navigation was disabled", result.stderr)

    def test_found_but_inactive_search_is_rejected(self):
        result = self.run_scenario("search-inactive")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("could not become navigation-active", result.stderr)

    def test_stale_command_dispatch_is_rejected(self):
        result = self.run_scenario("stale-command")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stale About command", result.stderr)

    def test_keyboard_trap_on_escape_is_rejected(self):
        result = self.run_scenario("escape-stuck")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("keyboard navigation trapped", result.stderr)


if __name__ == "__main__":
    unittest.main()
