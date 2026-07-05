var testCase = {
    name: "TC15: Region entry announces score view on focus",
    description: "Verify that Tabbing into the score view triggers a screen reader announcement containing 'Score view'",
    steps: [
        {name: "Wait for notation page to settle", func: function() {
            api.testflow.seeChanges(1500)
        }},
        {name: "Focus toolbar to establish deterministic starting context", func: function() {
            api.keyboard.key("Escape")
            api.testflow.seeChanges(500)
        }},
        {name: "Tab into score view — announce 'Score view'", func: function() {
            api.keyboard.key("Tab")
            api.testflow.seeChanges(1000)
            var ann = api.accessibility.announcement()
            if (!ann || ann.length === 0) {
                api.testflow.fatal("Expected announcement after Tab into score view, got: '" + ann + "'")
            }
            if (ann.indexOf("Score view") === -1) {
                api.testflow.fatal("Expected announcement to contain 'Score view', got: '" + ann + "'")
            }
        }}
    ]
};

function main()
{
    api.testflow.setInterval(500)
    api.testflow.runTestCase(testCase)
}
