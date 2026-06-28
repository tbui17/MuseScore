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

var testCase = {
    name: "TC12: Playback speed dialog from command palette",
    description: "Verify playback-speed action opens dialog from command palette",
    steps: [
        {name: "Open command palette", func: function() {
            api.dispatcher.dispatch("command-palette")
            api.testflow.waitPopup()
            api.testflow.seeChanges(500)
        }},
        {name: "Type search for playback speed", func: function() {
            api.keyboard.text("playback speed")
            api.testflow.seeChanges(500)
        }},
        {name: "Trigger first result", func: function() {
            api.keyboard.key("Return")
            api.testflow.seeChanges(1000)
        }},
        {name: "Verify PlaybackSpeedDialog is open", func: function() {
            if (!api.interactive.isOpened("musescore://playback/speed")) {
                api.testflow.fatal("PlaybackSpeedDialog was not opened from command palette")
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
