var NewScore = require("steps/NewScore.js")
var Home = require("steps/Home.js")
var NOTATION_PAGE_URI = "musescore://notation"
var NOTATION_READY_TIMEOUT_MSEC = 30000
var NOTATION_READY_POLL_MSEC = 100

function waitForNotationPage()
{
    var waitAttempts = NOTATION_READY_TIMEOUT_MSEC / NOTATION_READY_POLL_MSEC
    for (var i = 0; i < waitAttempts; ++i) {
        if (api.interactive.isOpened(NOTATION_PAGE_URI)) {
            return
        }
        api.testflow.seeChanges(NOTATION_READY_POLL_MSEC)
    }

    api.testflow.fatal("Notation page " + NOTATION_PAGE_URI
                       + " was not open within " + NOTATION_READY_TIMEOUT_MSEC + " msec")
}


var testCase = {
    name: "TC15: Region entry announces score view on focus",
    description: "Verify that opening a score triggers a screen reader announcement containing 'Score view', and that tabbing between score canvas and toolbar does not re-announce",
    steps: [
        {name: "Close score (if opened) and go to home to start", func: function() {
            api.dispatcher.dispatch("file-close")
            Home.goToHome()
            api.testflow.seeChanges(500)
        }},
        {name: "Open New Score Dialog", func: function() {
            NewScore.openNewScoreDialog()
        }},
        {name: "Select Instruments", func: function() {
            NewScore.selectTab("instruments")
            NewScore.chooseInstrument("Keyboards", "Piano")
            api.testflow.seeChanges()
        }},
        {name: "Create score", func: function() {
            // The dialog navigation tree is stable before submission. Select Done
            // synchronously, then use the direct keyboard action to submit it.
            var doneReady = api.navigation.goToControl("NewScoreDialog", "BottomPanel", "Done")
            if (!doneReady) {
                api.testflow.fatal("New Score Done control was not available before submission")
            }
            api.keyboard.key("Return")
            api.testflow.seeChanges(2000)
        }},
        {name: "Wait for notation page to settle", func: function() {
            waitForNotationPage()
            api.testflow.seeChanges(1500)
        }},
        {name: "Verify 'Score view' was announced on score open", func: function() {
            var ann = api.accessibility.announcement()
            if (!ann || ann.length === 0) {
                api.testflow.fatal("Expected announcement after opening score, got: '" + ann + "'")
            }
            if (ann.indexOf("Score view") === -1) {
                api.testflow.fatal("Expected announcement to contain 'Score view', got: '" + ann + "'")
            }
        }},
        {name: "Tab to status bar — should NOT re-announce 'Score view'", func: function() {
            api.keyboard.key("Tab")
            api.testflow.seeChanges(1000)
            var ann = api.accessibility.announcement()
            if (ann && ann.indexOf("Score view") !== -1) {
                api.testflow.fatal("Should NOT re-announce 'Score view' when tabbing from score canvas to status bar, got: '" + ann + "'")
            }
        }},
        {name: "Return to score canvas — should announce 'Score view'", func: function() {
            // Capture the current announcement before the action that should emit a new one.
            var announcementBeforeReturn = api.accessibility.announcement()
            api.navigation.goToControl("NotationView", "ScoreView", "Score")
            api.testflow.seeChanges(1000)
            var ann = api.accessibility.announcement()
            if (!ann || ann.indexOf("Score view") === -1) {
                api.testflow.fatal("Expected 'Score view' announcement when returning to score canvas, got: '"
                                   + ann + "' (before return: '" + announcementBeforeReturn + "')")
            }
        }},
        {name: "F6 to next section — should NOT re-announce 'Score view'", func: function() {
            api.keyboard.key("F6")
            api.testflow.seeChanges(1000)
            var ann = api.accessibility.announcement()
            if (ann && ann.indexOf("Score view") !== -1) {
                api.testflow.fatal("Should NOT re-announce 'Score view' when F6-ing between sections, got: '" + ann + "'")
            }
        }}
    ]
};

function main()
{
    api.testflow.setInterval(500)
    api.testflow.runTestCase(testCase)
}
