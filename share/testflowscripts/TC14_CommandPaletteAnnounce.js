var testCase = {
    name: "TC14: Command palette arrow navigation announces result",
    description: "Verify result speech, empty-search navigation, and recovery without dispatching a stale command",
    steps: [
        {name: "Open command palette", func: function() {
            api.dispatcher.dispatch("command-palette")
            api.testflow.waitPopup()
            api.testflow.seeChanges(500)
        }},
        {name: "Type search", func: function() {
            // Flush any queued key events before typing.
            api.testflow.seeChanges(300)
            api.keyboard.text("about musescore")
            api.testflow.seeChanges(1000)
        }},
        {name: "Navigate down - announce first result", func: function() {
            api.keyboard.key("Down")
            api.testflow.seeChanges(500)
            var ann = api.accessibility.announcement()
            if (!ann || ann.indexOf("About MuseScore") === -1 || ann.indexOf("1 of") === -1) {
                api.testflow.fatal("Expected About MuseScore and position after Down, got: '" + ann + "'")
            }
        }},
        {name: "Filter to no matching commands", func: function() {
            api.keyboard.text(" zzznonexistentcommandzzz")
            api.testflow.seeChanges(1000)
        }},
        {name: "Navigate empty results - announce no matches", func: function() {
            // The previous announcement was a real result, so stale speech cannot pass.
            api.keyboard.key("Down")
            api.testflow.seeChanges(500)
            var ann = api.accessibility.announcement()
            if (ann !== "No matching commands") {
                api.testflow.fatal("Expected empty-result feedback after Down, got: '" + ann + "'")
            }
        }},
        {name: "Enter on empty results must not run stale selection", func: function() {
            api.keyboard.key("Return")
            api.testflow.seeChanges(500)
            if (api.interactive.isOpened("musescore://about/musescore")) {
                api.testflow.fatal("Enter dispatched the stale About command while results were empty")
            }
        }},
        {name: "Search remains reachable when results are empty", func: function() {
            if (!api.navigation.goToControl("CommandPaletteDialog", "CommandPaletteSearch", "CommandPaletteSearchField")) {
                api.testflow.fatal("Search navigation was disabled by an empty result list")
            }
            api.testflow.seeChanges(300)
            if (api.navigation.activePanel() !== "CommandPaletteSearch"
                    || api.navigation.activeControl() !== "CommandPaletteSearchField") {
                api.testflow.fatal("Search was found but could not become navigation-active")
            }
            // KeyboardApi accepts the modifier separately, not a combined Ctrl+A string.
            api.keyboard.key("A", "CTRL")
            api.keyboard.text("about musescore")
            api.testflow.seeChanges(1000)
        }},
        {name: "Recover results and navigate up", func: function() {
            api.keyboard.key("Up")
            api.testflow.seeChanges(500)
            var ann = api.accessibility.announcement()
            if (!ann || ann.indexOf("About MuseScore") === -1 || ann.indexOf("1 of") === -1) {
                api.testflow.fatal("Search did not recover from no matches: '" + ann + "'")
            }
        }},
        {name: "Filter again and verify empty Up feedback", func: function() {
            api.keyboard.text(" zzznonexistentcommandzzz")
            api.testflow.seeChanges(1000)
            api.keyboard.key("Up")
            api.testflow.seeChanges(500)
            var ann = api.accessibility.announcement()
            if (ann !== "No matching commands") {
                api.testflow.fatal("Expected empty-result feedback after Up, got: '" + ann + "'")
            }
        }},
        {name: "Restore executable search", func: function() {
            if (!api.navigation.goToControl("CommandPaletteDialog", "CommandPaletteSearch", "CommandPaletteSearchField")) {
                api.testflow.fatal("Search could not regain navigation after repeated filtering")
            }
            api.testflow.seeChanges(300)
            api.keyboard.key("A", "CTRL")
            api.keyboard.text("about musescore")
            api.testflow.seeChanges(1000)
        }},
        {name: "Run selected command", func: function() {
            api.keyboard.key("Return")
            api.testflow.seeChanges(1000)
        }},
        {name: "Verify About dialog opened", func: function() {
            if (!api.interactive.isOpened("musescore://about/musescore")) {
                api.testflow.fatal("About dialog was not open after recovering and running a palette command")
            }
        }},
        {name: "Close dialog", func: function() {
            api.keyboard.key("Escape")
            api.testflow.seeChanges(500)
        }},
        {name: "Reopen palette with an empty search result", func: function() {
            api.dispatcher.dispatch("command-palette")
            api.testflow.waitPopup()
            api.testflow.seeChanges(500)
            api.keyboard.text("zzznonexistentcommandzzz")
            api.testflow.seeChanges(1000)
            if (api.navigation.activeSection() !== "CommandPaletteDialog") {
                api.testflow.fatal("Palette did not retain navigation while showing no matches")
            }
        }},
        {name: "Escape closes an empty palette", func: function() {
            api.keyboard.key("Escape")
            api.testflow.seeChanges(500)
            if (api.navigation.activeSection() === "CommandPaletteDialog") {
                api.testflow.fatal("Escape left keyboard navigation trapped in the empty palette")
            }
        }}
    ]
};

function main()
{
    api.testflow.setInterval(500)
    api.testflow.runTestCase(testCase)
}
