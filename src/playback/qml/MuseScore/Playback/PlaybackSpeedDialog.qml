/*
 * SPDX-License-Identifier: GPL-3.0-only
 * MuseScore-Studio-CLA-applies
 *
 * MuseScore Studio
 * Music Composition & Notation
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
import QtQuick
import QtQuick.Layouts

import Muse.Ui
import Muse.UiComponents

StyledDialogView {
    id: root

    title: qsTrc("playback", "Playback speed")
    contentWidth: content.implicitWidth
    contentHeight: content.implicitHeight
    margins: 16

    modal: true

    property int speedPercent: 100

    ColumnLayout {
        id: content
        anchors.fill: parent
        spacing: 20

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            NavigationPanel {
                id: speedNavigationPanel
                name: "PlaybackSpeedNavigationPanel"
                enabled: content && content.enabled && content.visible
                section: root.navigationSection
                order: 1
                direction: NavigationPanel.Horizontal
            }

            StyledTextLabel {
                id: speedLabel
                Layout.fillWidth: true
                text: qsTrc("playback", "Speed:")
                font: ui.theme.bodyBoldFont
                horizontalAlignment: Text.AlignLeft
            }

            IncrementalPropertyControl {
                id: speedInputField

                Layout.alignment: Qt.AlignRight
                Layout.preferredWidth: 132

                navigation.name: "PlaybackSpeedInputField"
                navigation.panel: speedNavigationPanel
                navigation.order: 0
                navigation.accessible.name: speedLabel.text + " " + currentValue

                currentValue: root.speedPercent
                step: 5
                decimals: 0
                minValue: 10
                maxValue: 300
                measureUnitsSymbol: "%"

                onValueEdited: function(newValue) {
                    root.speedPercent = newValue
                }

                onAccepted: {
                    root.ret = { errcode: 0, value: root.speedPercent }
                    root.hide()
                }

                onEscaped: {
                    root.reject()
                }
            }
        }

        ButtonBox {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignRight | Qt.AlignBottom

            buttons: [ ButtonBoxModel.Cancel ]

            navigationPanel.section: root.navigationSection
            navigationPanel.order: 2

            FlatButton {
                text: qsTrc("global", "OK")
                buttonRole: ButtonBoxModel.AcceptRole
                buttonId: ButtonBoxModel.Ok
                accentButton: true

                onClicked: {
                    root.ret = { errcode: 0, value: root.speedPercent }
                    root.hide()
                }
            }

            onStandardButtonClicked: function(buttonId) {
                if (buttonId === ButtonBoxModel.Cancel) {
                    root.reject()
                }
            }
        }
    }
}
