/*
 * SPDX-License-Identifier: GPL-3.0-only
 * MuseScore-Studio-CLA-applies
 *
 * MuseScore Studio
 * Music Composition, Notation & Braille
 *
 * Copyright (C) 2026 MuseScore Limited and others
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 3
 * as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

var Score = require("steps/Score.js")

var testCase = {
    name: "TC13: Set tempo via command palette updates existing",
    description: "Verify set-tempo action announces correct BPM and does not error on repeat",
    steps: [
        {name: "Select first note", func: function() {
            Score.firstElement()
            api.testflow.seeChanges(500)
        }},
        {name: "Open command palette and search set tempo", func: function() {
            api.dispatcher.dispatch("command-palette")
            api.testflow.waitPopup()
            api.testflow.seeChanges(500)
            api.keyboard.text("set tempo")
            api.testflow.seeChanges(500)
        }},
        {name: "Trigger set tempo action", func: function() {
            api.keyboard.key("Return")
            api.testflow.seeChanges(1000)
        }},
        {name: "Verify TempoDialog is open", func: function() {
            if (!api.interactive.isOpened("musescore://notation/settempo")) {
                api.testflow.fatal("TempoDialog was not opened from command palette")
            }
        }},
        {name: "Set BPM to 120 and confirm", func: function() {
            // Clear field and type 120
            api.keyboard.text("120")
            api.testflow.seeChanges(500)
            api.keyboard.key("Return")
            api.testflow.seeChanges(1000)
        }},
        {name: "Verify tempo was set to 120", func: function() {
            var announcement = api.accessibility.currentName()
            if (announcement.indexOf("120") === -1) {
                api.testflow.fatal("Expected announcement to contain '120', got: " + announcement)
            }
        }},
        {name: "Select first note again", func: function() {
            Score.firstElement()
            api.testflow.seeChanges(500)
        }},
        {name: "Open command palette and search set tempo again", func: function() {
            api.dispatcher.dispatch("command-palette")
            api.testflow.waitPopup()
            api.testflow.seeChanges(500)
            api.keyboard.text("set tempo")
            api.testflow.seeChanges(500)
        }},
        {name: "Trigger set tempo action again", func: function() {
            api.keyboard.key("Return")
            api.testflow.seeChanges(1000)
        }},
        {name: "Verify TempoDialog is open again", func: function() {
            if (!api.interactive.isOpened("musescore://notation/settempo")) {
                api.testflow.fatal("TempoDialog was not opened on second call")
            }
        }},
        {name: "Set BPM to 140 and confirm", func: function() {
            api.keyboard.text("140")
            api.testflow.seeChanges(500)
            api.keyboard.key("Return")
            api.testflow.seeChanges(1000)
        }},
        {name: "Verify tempo was set to 140", func: function() {
            var announcement = api.accessibility.currentName()
            if (announcement.indexOf("140") === -1) {
                api.testflow.fatal("Expected announcement to contain '140', got: " + announcement)
            }
        }}
    ]
};

function main()
{
    api.testflow.setInterval(500)
    api.testflow.runTestCase(testCase)
}
