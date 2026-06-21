/*
 * SPDX-License-Identifier: GPL-3.0-only
 * MuseScore-Studio-CLA-applies
 *
 * MuseScore Studio
 * Music Composition & Notation
 *
 * Copyright (C) 2026 MuseScore Limited and others
 *
 * This program is free software; you can redistribute it and/or modify
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

    property string dimension: "beat"
    property int positionValue: 1

    readonly property string dimensionLabel: {
        switch (dimension) {
        case "measure": return qsTrc("notation", "Measure number:")
        case "staff": return qsTrc("notation", "Staff number:")
        case "voice": return qsTrc("notation", "Voice number:")
        default: return qsTrc("notation", "Beat number:")
        }
    }

    title: {
        switch (dimension) {
        case "measure": return qsTrc("notation", "Go to measure")
        case "staff": return qsTrc("notation", "Go to staff")
        case "voice": return qsTrc("notation", "Go to voice")
        default: return qsTrc("notation", "Go to beat")
        }
    }

    contentWidth: content.implicitWidth
    contentHeight: content.implicitHeight
    margins: 16

    modal: true

    onNavigationActivateRequested: {
        inputField.navigation.requestActive()
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        spacing: 20

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            NavigationPanel {
                id: navPanel
                name: "GoToPositionNavigationPanel"
                enabled: content && content.enabled && content.visible
                section: root.navigationSection
                order: 1
                direction: NavigationPanel.Horizontal
            }

            StyledTextLabel {
                id: inputLabel
                Layout.fillWidth: true
                text: root.dimensionLabel
                font: ui.theme.bodyBoldFont
                horizontalAlignment: Text.AlignLeft
            }

            IncrementalPropertyControl {
                id: inputField

                Layout.alignment: Qt.AlignRight
                Layout.preferredWidth: 132

                navigation.name: "GoToPositionInputField"
                navigation.panel: navPanel
                navigation.order: 0
                navigation.accessible.name: inputLabel.text + " " + currentValue

                currentValue: root.positionValue
                step: 1
                decimals: 0
                minValue: 1
                maxValue: 999

                onValueEdited: function(newValue) {
                    root.positionValue = newValue
                }

                onAccepted: {
                    root.ret = { errcode: 0, value: root.positionValue }
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
                    root.ret = { errcode: 0, value: root.positionValue }
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
