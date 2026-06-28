/*
 * SPDX-License-Identifier: GPL-3.0-only
 * MuseScore-Studio-CLA-applies
 *
 * MuseScore Studio
 * Music Composition, Notation & Braille
 *
 * Copyright (C) 2021 MuseScore Limited and others
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 3 as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

var testCase = {
    name: "TC11: Command Palette opens dialog correctly",
    description: "Verify that running a dialog-opening command from the command palette keeps the target dialog open (transient parent + deferred dispatch regression)",
    steps: [
        {name: "Dismiss first launch setup dialog if present", func: function() {
            // On fresh installs (e.g. CI), a First Launch Setup dialog appears
            // and steals keyboard focus. Dismiss it before interacting.
            api.keyboard.key("Escape")
            api.testflow.seeChanges(500)
        }},
        {name: "Open command palette", func: function() {
            api.dispatcher.dispatch("command-palette")
            api.testflow.waitPopup()
            api.testflow.seeChanges(500)
        }},
        {name: "Type search for About dialog", func: function() {
            api.testflow.seeChanges(500)
            api.keyboard.text("about musescore")
            api.testflow.seeChanges(500)
        }},
        {name: "Trigger first result", func: function() {
            api.keyboard.key("Return")
            api.testflow.seeChanges(1000)
        }},
        {name: "Verify About dialog is open", func: function() {
            // URI registered in appshellmodule.cpp:76
            if (!api.interactive.isOpened("musescore://about/musescore")) {
                api.testflow.fatal("About dialog was not open after running command from palette")
            }
        }},
        {name: "Close About dialog and palette", func: function() {
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
