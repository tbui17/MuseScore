var NewScore = require("steps/NewScore.js")
var Home = require("steps/Home.js")

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
            NewScore.done()
            api.testflow.seeChanges(2000)
        }},
        {name: "Wait for notation page to settle", func: function() {
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
        {name: "Tab back to score canvas — should NOT re-announce 'Score view'", func: function() {
            api.keyboard.key("Tab")
            api.testflow.seeChanges(1000)
            var ann = api.accessibility.announcement()
            if (ann && ann.indexOf("Score view") !== -1) {
                api.testflow.fatal("Should NOT re-announce 'Score view' when tabbing back to score canvas, got: '" + ann + "'")
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
