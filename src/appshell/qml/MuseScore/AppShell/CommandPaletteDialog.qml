/*
 * SPDX-License-Identifier: GPL-3.0-only
 * MuseScore-Studio-CLA-applies
 */

import QtQuick
import QtQuick.Controls

import Muse.Ui
import Muse.UiComponents
import MuseScore.AppShell

StyledDialogView {
    id: root

    objectName: "CommandPaletteDialog"
    title: qsTrc("appshell/commandpalette", "Command palette")

    width: 640
    height: 420
    margins: 16
    frameless: true
    resizable: false
    closeOnEscape: true

    contentHeight: contentColumn.height + root.margins * 2

    function runSelection() {
        if (paletteModel.runSelected()) {
            root.accept()
        }
    }

    onOpened: {
        paletteModel.load()
        searchField.clear()
        searchField.ensureActiveFocus()
    }

    onNavigationActivateRequested: {
        searchField.navigation.requestActive()
    }

    CommandPaletteModel {
        id: paletteModel
    }

    Column {
        id: contentColumn

        width: parent.width
        spacing: 12

        SearchField {
            id: searchField

            objectName: "CommandPaletteSearchField"
            width: parent.width
            hint: qsTrc("appshell/commandpalette", "Search commands")
            accessible.name: hint

            navigation.panel: resultsList.navigation
            navigation.row: 0
            navigation.column: 0

            onSearchTextChanged: {
                paletteModel.searchText = searchText
            }

            onAccepted: {
                root.runSelection()
            }

            onEscaped: {
                root.reject()
            }

            Keys.onShortcutOverride: function(event) {
                if (event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                    event.accepted = true
                }
            }

            Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Down) {
                    paletteModel.moveSelection(1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Up) {
                    paletteModel.moveSelection(-1)
                    event.accepted = true
                }
            }
        }

        StyledTextLabel {
            id: countLabel

            width: parent.width
            text: paletteModel.resultCount === 1
                  ? qsTrc("appshell/commandpalette", "1 command")
                  : qsTrc("appshell/commandpalette", "%1 commands").arg(paletteModel.resultCount)
            color: ui.theme.fontSecondaryColor
            visible: paletteModel.resultCount > 0
            Accessible.name: text
        }

        StyledListView {
            id: resultsList

            objectName: "CommandPaletteResultsList"
            width: parent.width
            height: 310
            model: paletteModel
            visible: paletteModel.resultCount > 0
            currentIndex: paletteModel.selectedIndex
            accessible.name: qsTrc("appshell/commandpalette", "Command results")

            navigation.section: root.navigationSection
            navigation.direction: NavigationPanel.Vertical
            navigation.order: 1

            delegate: ListItemBlank {
                id: resultItem

                width: ListView.view.width
                isSelected: index === paletteModel.selectedIndex
                navigation.panel: resultsList.navigation
                navigation.row: index + 1
                navigation.column: 0
                navigation.accessible.name: qsTrc("appshell/commandpalette", "%1, %2 of %3")
                                            .arg(model.title)
                                            .arg(index + 1)
                                            .arg(paletteModel.resultCount)

                navigation.onActiveChanged: {
                    if (navigation.active) {
                        resultsList.positionViewAtIndex(index, ListView.Contain)
                    }
                }

                onClicked: {
                    paletteModel.selectedIndex = index
                    root.runSelection()
                }

                StyledTextLabel {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignVCenter
                    text: model.title
                    color: resultItem.isSelected ? ui.theme.accentColor : ui.theme.fontPrimaryColor
                }
            }
        }

        Connections {
            target: paletteModel
            function onSelectedIndexChanged() {
                if (paletteModel.selectedIndex >= 0) {
                    resultsList.positionViewAtIndex(paletteModel.selectedIndex, ListView.Contain)
                }
            }
        }

        StyledTextLabel {
            id: emptyStateLabel

            width: parent.width
            height: 72
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            text: paletteModel.emptyStateText
            color: ui.theme.fontSecondaryColor
            visible: paletteModel.resultCount === 0
            Accessible.name: text
        }
    }
}
