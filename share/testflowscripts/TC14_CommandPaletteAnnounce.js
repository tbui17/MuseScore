var testCase = {
    name: "TC14: Command palette arrow navigation announces result",
    description: "Verify arrow keys navigate palette results and screen reader announcement matches the selected item",
    steps: [
        {name: "Open command palette", func: function() {
            api.dispatcher.dispatch("command-palette")
            api.testflow.waitPopup()
            api.testflow.seeChanges(500)
        }},
        {name: "Type search", func: function() {
            // Flush any queued key events before typing
            api.testflow.seeChanges(300)
            api.keyboard.text("about musescore")
            api.testflow.seeChanges(1000)
        }},
        {name: "Navigate down — announce first result", func: function() {
            api.keyboard.key("Down")
            api.testflow.seeChanges(500)
            var ann = api.accessibility.announcement()
            if (!ann || ann.length === 0) {
                api.testflow.fatal("Expected announcement after Down arrow, got: '" + ann + "'")
            }
            if (ann.indexOf("About MuseScore") === -1) {
                api.testflow.fatal("Expected announcement to contain 'About MuseScore', got: '" + ann + "'")
            }
            if (ann.indexOf("1 of") === -1) {
                api.testflow.fatal("Expected announcement to contain position '1 of N', got: '" + ann + "'")
            }
        }},
        {name: "Run selected command", func: function() {
            api.keyboard.key("Return")
            api.testflow.seeChanges(1000)
        }},
        {name: "Verify About dialog opened", func: function() {
            if (!api.interactive.isOpened("musescore://about/musescore")) {
                api.testflow.fatal("About dialog was not open after navigating and running command from palette")
            }
        }},
        {name: "Close dialog", func: function() {
            api.keyboard.key("Escape")
            api.testflow.seeChanges(500)
        }}
    ]
};

function main()
{
    api.testflow.setInterval(500)
    api.testflow.runTestCase(testCase)
}
