import QtQuick
import AetherShared
import "."

// One pane of the split view: its own tab strip over the views of its tabs. Views stay alive
// while their tab is open (logs, scroll, folders keep their state); only the active one is
// shown and polls. A tab is picked up with a long press and dropped on any pane's edge (split)
// or centre (move here) - see Console.qml's drag state.
Item {
    id: pane
    property var shell
    property string gid

    readonly property var group: shell.groups[gid] || ({ tabIds: [], active: "" })
    // the model only changes with the pane's membership, never with the active tab
    property var tabIdList: []
    onGroupChanged: {
        const a = group.tabIds
        if (JSON.stringify(a) !== JSON.stringify(tabIdList)) tabIdList = a.slice()
    }
    Component.onCompleted: tabIdList = group.tabIds.slice()

    readonly property bool multi: shell.groupIds.length > 1
    readonly property bool focused: multi && shell.focusGroup === gid
    // the window's own buttons (refresh, close) live in the tab strip of the pane in the top-right corner
    readonly property bool topRight: y < 1 && x + width >= shell.areaW - 2
    readonly property real globalW: topRight ? 2 * 32 + 8 : 0
    readonly property bool showBar: true
    readonly property real barH: showBar ? 42 : 0
    readonly property bool dropHere: shell.dragTab !== "" && shell.dropGid === gid

    // the card behind a pane (only while split: a lone pane is the glass itself)
    Rectangle {
        anchors.fill: parent
        visible: pane.multi
        radius: 16
        color: Qt.rgba(0, 0, 0, 0.14)
        border { width: pane.focused ? 1.5 : 1; color: pane.focused ? Theme.accent : Theme.rim }
        opacity: pane.focused ? 1 : 0.9
        Behavior on border.color { ColorAnimation { duration: Tokens.motion.duration.fast } }
    }
    TapHandler { onTapped: shell.focusGroup = pane.gid }

    // ---- tab strip ----
    Item {
        id: bar
        width: parent.width; height: pane.barH
        visible: pane.showBar
        clip: true
        Flickable {
            anchors { fill: parent; leftMargin: pane.multi ? 8 : shell.rad * 0.6; rightMargin: (pane.multi ? 34 : shell.rad * 0.6) + pane.globalW }
            contentWidth: trow.width
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Row {
                id: trow
                height: bar.height
                spacing: 4
                Repeater {
                    model: pane.tabIdList
                    Item {
                        id: chip
                        required property string modelData
                        readonly property var t: shell.tabById(modelData) || ({ id: modelData, title: "", kind: "" })
                        readonly property bool active: pane.group.active === modelData
                        readonly property bool dragging: shell.dragTab === modelData
                        // equal padding on both sides; the close glyph keeps its slot
                        // (shown on hover/active) so tabs never jump in width
                        width: 12 + chipTitle.width + (modelData !== "home" ? 6 + 14 : 0) + 12
                        height: parent.height
                        opacity: dragging ? 0.35 : 1
                        Rectangle {
                            id: pill
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; verticalCenterOffset: -2 }
                            height: 28
                            radius: 9
                            color: chip.active ? Theme.chip
                                 : Qt.rgba(1, 1, 1, chipArea.containsMouse ? Tokens.material.tintHover : 0)
                            Behavior on color { ColorAnimation { duration: Tokens.motion.duration.fast } }
                        }
                        // the accent line rides the bar's bottom rule, not the pill
                        Rectangle {
                            anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                            width: parent.width - 16
                            height: 2; radius: 1
                            color: Theme.accent
                            opacity: chip.active ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.fast } }
                        }
                        Text {
                            id: chipTitle
                            x: 12
                            anchors.verticalCenter: pill.verticalCenter
                            width: Math.min(120, implicitWidth)
                            elide: Text.ElideRight
                            text: chip.t.title
                            font { family: Theme.font; pixelSize: Tokens.type.label; weight: chip.active ? Font.Medium : Font.Normal }
                            color: chip.active ? Theme.text : Theme.subtext
                        }
                        // the whole chip: tap = activate, long press = pick up and drag
                        MouseArea {
                            id: chipArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: shell.dragTab !== "" ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                            pressAndHoldInterval: 350
                            onClicked: shell.activateTab(pane.gid, chip.modelData)
                            onPressAndHold: (m) => shell.beginDrag(chip.modelData, mapToItem(shell, m.x, m.y))
                            onPositionChanged: (m) => { if (shell.dragTab === chip.modelData) shell.moveDrag(mapToItem(shell, m.x, m.y)) }
                            onReleased: if (shell.dragTab === chip.modelData) shell.endDrag()
                            onCanceled: if (shell.dragTab === chip.modelData) shell.cancelDrag()
                        }
                        Item {
                            visible: chip.modelData !== "home"
                            width: 14; height: 14
                            anchors { verticalCenter: pill.verticalCenter; left: chipTitle.right; leftMargin: 6 }
                            Rectangle {
                                anchors.fill: parent; radius: 4
                                color: Qt.rgba(1, 1, 1, closeHover.hovered ? Tokens.material.tintHover * 2 : 0)
                            }
                            Glyph {
                                anchors.centerIn: parent
                                name: "close"; size: 10
                                opacity: chip.active || chipArea.containsMouse ? 1 : 0
                                color: closeHover.hovered ? Theme.text : Theme.subtext
                            }
                            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: shell.closeTab(chip.modelData) }
                        }
                    }
                }
            }
        }
        // pane menu (split, equalize, maximize, close)
        Item {
            visible: pane.multi
            width: 28; height: 28
            anchors { right: parent.right; rightMargin: 6 + pane.globalW; verticalCenter: parent.verticalCenter; verticalCenterOffset: -2 }
            Rectangle {
                anchors.fill: parent; radius: 9
                color: Qt.rgba(1, 1, 1, menuHover.hovered || shell.menuGid === pane.gid ? Tokens.material.tintHover : 0)
            }
            Text {
                anchors.centerIn: parent
                text: "⋯"
                font { family: Theme.font; pixelSize: Tokens.type.heading; weight: Font.Medium }
                color: Theme.subtext
            }
            HoverHandler { id: menuHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: shell.openPaneMenu(pane.gid, parent.mapToItem(shell, 0, parent.height)) }
        }
        // global buttons: refresh the destinations, close the whole window
        Row {
            visible: pane.topRight
            anchors { right: parent.right; rightMargin: shell.rad * 0.4; verticalCenter: parent.verticalCenter; verticalCenterOffset: -2 }
            spacing: 4
            Item {
                width: 28; height: 28
                Rectangle { anchors.fill: parent; radius: 9; color: Qt.rgba(1, 1, 1, refreshHover.hovered ? Tokens.material.tintHover : 0) }
                Glyph {
                    anchors.centerIn: parent
                    name: "restart"; size: 14
                    color: refreshHover.hovered ? Theme.text : Theme.subtext
                    NumberAnimation on rotation {
                        from: 0; to: 360; duration: Tokens.motion.duration.ambient
                        running: discovery.busy; loops: Animation.Infinite
                    }
                }
                HoverHandler { id: refreshHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: discovery.refresh() }
            }
            Item {
                width: 28; height: 28
                Rectangle { anchors.fill: parent; radius: 9; color: Qt.rgba(1, 1, 1, shellCloseHover.hovered ? Tokens.material.tintHover : 0) }
                Glyph {
                    anchors.centerIn: parent
                    name: "close"; size: 14
                    color: shellCloseHover.hovered ? Theme.text : Theme.subtext
                }
                HoverHandler { id: shellCloseHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: shell.open = false }
            }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.rim; opacity: 0.4 }
    }

    // ---- views ----
    Item {
        id: body
        anchors { top: bar.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        clip: pane.multi
        LayoutMirroring.enabled: I18n.rtl
        LayoutMirroring.childrenInherit: true

        Repeater {
            model: pane.tabIdList
            Loader {
                id: ld
                required property string modelData
                readonly property var tabObj: shell.tabById(modelData)
                readonly property bool isActive: pane.group.active === modelData && pane.visible
                anchors.fill: parent
                visible: isActive
                opacity: visible ? 1 : 0
                sourceComponent: !tabObj ? null
                               : tabObj.kind === "home" ? homeC
                               : tabObj.kind === "card" ? cardC
                               : tabObj.kind === "files" ? filesC
                               : termC
                Component { id: homeC; HomeView { shell: pane.shell; tab: ld.tabObj; gid: pane.gid; active: ld.isActive } }
                Component { id: cardC; CardView { shell: pane.shell; tab: ld.tabObj; gid: pane.gid; active: ld.isActive } }
                Component { id: filesC; FilesView { shell: pane.shell; tab: ld.tabObj; gid: pane.gid; active: ld.isActive } }
                Component { id: termC; TermView { shell: pane.shell; tab: ld.tabObj; gid: pane.gid; active: ld.isActive } }
            }
        }
    }
}
