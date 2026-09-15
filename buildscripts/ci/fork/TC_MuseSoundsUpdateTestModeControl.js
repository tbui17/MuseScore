var NewScore = require("steps/NewScore.js")
var Home = require("steps/Home.js")

var RELEASE_DIALOG_URI = "musescore://musesounds/musesoundsreleaseinfo"
var NEW_SCORE_SECTION = "NewScoreDialog"
var NEW_SCORE_SELECT_PATH = "NewScoreDialog/SelectPanel/Select"
var NEW_SCORE_SCORE_LIST_PANEL = "ListView"
var NEW_SCORE_BOTTOM_PANEL = "BottomPanel"
var NEW_SCORE_DONE_PATH = "NewScoreDialog/BottomPanel/Done"
var NEW_SCORE_NAV_MAX_TABS = 32
var NEW_SCORE_NAV_SETTLE_MSEC = 100
var DIALOG_TIMEOUT_MSEC = 30000
var DIALOG_POLL_MSEC = 100
var DIALOG_SETTLE_MSEC = 750

function readActiveNavigationPath()
{
    var section = api.navigation.activeSection()
    var panel = api.navigation.activePanel()
    var control = api.navigation.activeControl()
    return {
        section: section,
        panel: panel,
        control: control,
        value: section + "/" + panel + "/" + control
    }
}

function failNewScoreNavigation(message, visitedPaths)
{
    api.testflow.fatal(message + "; visited paths: " + visitedPaths.join(" -> "))
}

function triggerEnabledDone(visitedPaths)
{
    var controls = api.navigation.controls(NEW_SCORE_SECTION, NEW_SCORE_BOTTOM_PANEL)
    var doneEnabled = false
    for (var i = 0; i < controls.length; ++i) {
        if (controls[i].name === "Done") {
            doneEnabled = controls[i].enabled
            break
        }
    }
    if (!doneEnabled) {
        failNewScoreNavigation("Done control is not enabled after instrument selection", visitedPaths)
    }
    if (!api.navigation.triggerControl(NEW_SCORE_SECTION, NEW_SCORE_BOTTOM_PANEL, "Done")) {
        failNewScoreNavigation("Enabled Done control could not be triggered", visitedPaths)
    }
}

function submitNewScoreDialog()
{
    var visitedPaths = []
    var selectActivated = false

    for (var i = 0; i < NEW_SCORE_NAV_MAX_TABS; ++i) {
        var current = readActiveNavigationPath()
        if (current.section !== NEW_SCORE_SECTION) {
            failNewScoreNavigation("Expected active section " + NEW_SCORE_SECTION
                                   + ", got " + current.value, visitedPaths)
        }
        if (current.value === NEW_SCORE_DONE_PATH) {
            triggerEnabledDone(visitedPaths)
            return
        }
        if (visitedPaths.indexOf(current.value) !== -1) {
            failNewScoreNavigation("Navigation cycle detected at " + current.value, visitedPaths)
        }
        visitedPaths.push(current.value)

        if (current.value === NEW_SCORE_SELECT_PATH) {
            if (selectActivated) {
                failNewScoreNavigation("Select control was activated more than once", visitedPaths)
            }
            selectActivated = true
            api.keyboard.key("Return")
            api.testflow.seeChanges(NEW_SCORE_NAV_SETTLE_MSEC)

            var afterSelect = readActiveNavigationPath()
            if (afterSelect.section !== NEW_SCORE_SECTION) {
                failNewScoreNavigation("Select left active section " + NEW_SCORE_SECTION
                                       + " at " + afterSelect.value, visitedPaths)
            }
            if (afterSelect.value === current.value) {
                api.keyboard.key("Tab")
                api.testflow.seeChanges(NEW_SCORE_NAV_SETTLE_MSEC)
                afterSelect = readActiveNavigationPath()
            }
            if (afterSelect.value === current.value) {
                failNewScoreNavigation("Select made no navigation progress at " + current.value, visitedPaths)
            }
            if (afterSelect.value !== NEW_SCORE_DONE_PATH
                    && afterSelect.panel !== NEW_SCORE_SCORE_LIST_PANEL
                    && afterSelect.panel !== NEW_SCORE_BOTTOM_PANEL) {
                failNewScoreNavigation("Select did not expose a populated score list or Done control; got "
                                       + afterSelect.value, visitedPaths)
            }
            if (afterSelect.panel === NEW_SCORE_SCORE_LIST_PANEL && !afterSelect.control) {
                failNewScoreNavigation("Select exposed an empty score list; got "
                                       + afterSelect.value, visitedPaths)
            }
            triggerEnabledDone(visitedPaths)
            return
        }

        api.keyboard.key("Tab")
        api.testflow.seeChanges(NEW_SCORE_NAV_SETTLE_MSEC)
        var next = readActiveNavigationPath()
        if (next.section !== NEW_SCORE_SECTION) {
            failNewScoreNavigation("Tab left active section " + NEW_SCORE_SECTION
                                   + " at " + next.value, visitedPaths)
        }
        if (next.value === current.value) {
            failNewScoreNavigation("Tab made no navigation progress at " + current.value, visitedPaths)
        }
        if (next.value !== NEW_SCORE_DONE_PATH && visitedPaths.indexOf(next.value) !== -1) {
            failNewScoreNavigation("Navigation cycle detected at " + next.value, visitedPaths)
        }
        if (next.value === NEW_SCORE_DONE_PATH) {
            triggerEnabledDone(visitedPaths)
            return
        }
    }

    failNewScoreNavigation("Select control was not reached within "
                           + NEW_SCORE_NAV_MAX_TABS + " Tab steps", visitedPaths)
}

function waitForDialogState(expectedOpen, timeoutMsec)
{
    var attempts = timeoutMsec / DIALOG_POLL_MSEC
    for (var i = 0; i < attempts; ++i) {
        if (api.interactive.isOpened(RELEASE_DIALOG_URI) === expectedOpen) {
            return
        }
        api.testflow.seeChanges(DIALOG_POLL_MSEC)
    }
    api.testflow.fatal("MuseSounds release dialog did not become "
                       + (expectedOpen ? "open" : "closed")
                       + " within " + timeoutMsec + " msec")
}

var testCase = {
    name: "Diagnostic control: MuseSounds update test mode dialog settles and closes",
    description: "Prove that MuseSounds update test mode bypasses the live feed and opens the identified release dialog, then close only that dialog.",
    steps: [
        {name: "Open a score to schedule the MuseSounds promotion", func: function() {
            api.dispatcher.dispatch("file-close")
            Home.goToHome()
            api.testflow.seeChanges(500)
            NewScore.openNewScoreDialog()
            NewScore.selectTab("instruments")
            NewScore.chooseInstrument("Keyboards", "Piano")
            api.testflow.seeChanges()
            submitNewScoreDialog()
        }},
        {name: "Observe the identified MuseSounds release dialog opening", func: function() {
            waitForDialogState(true, DIALOG_TIMEOUT_MSEC)
        }},
        {name: "Settle the identified MuseSounds release dialog", func: function() {
            api.testflow.seeChanges(DIALOG_SETTLE_MSEC)
            if (!api.interactive.isOpened(RELEASE_DIALOG_URI)) {
                api.testflow.fatal("MuseSounds release dialog closed before the settlement observation")
            }
        }},
        {name: "Close only the identified MuseSounds release dialog", func: function() {
            if (!api.interactive.isOpened(RELEASE_DIALOG_URI)) {
                api.testflow.fatal("MuseSounds release dialog was not open before targeted Escape")
            }
            api.keyboard.key("Escape")
            waitForDialogState(false, DIALOG_TIMEOUT_MSEC)
        }}
    ]
}

function main()
{
    api.testflow.setInterval(500)
    api.testflow.runTestCase(testCase)
}
