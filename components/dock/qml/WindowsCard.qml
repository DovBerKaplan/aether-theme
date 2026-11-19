import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager
import org.kde.pipewire as KPipeWire
import AetherShared

// The window chooser: a left-click on a dock icon whose app owns several windows, a hover on any
// running one. One glass card, two tiles per row, each showing its window LIVE - ScreencastingRequest
// asks KWin for a stream of that window and PipeWireSourceItem renders it; a minimized window has
// no stream, so its tile keeps the app icon on a quiet chip. The tiles walk in with a short
// stagger, streams fade in as they connect, hover lifts a tile on the house spring, the active
// window wears the accent. A tile raises its window and folds the card; the X (or a middle-click)
// closes just that one. Dock.qml places the card and feeds `rows` live from the tasks model.
Item {
    id: card
    property bool on: false
    property string appName: ""
    property var icon: ""
    property int count: 0
    property var rows: []             // [{ mi, title, active, minimized, uuid, live }]
    signal pick(int mi)
    signal closeOne(int mi)

    // Only the opening counts for the stagger; a mid-session row rebuild replays nothing.
    property bool appearRunning: false
    onOnChanged: if (on) appearRunning = true
    Timer { interval: 600; running: card.appearRunning; onTriggered: card.appearRunning = false }

    readonly property int tileW: 168
    readonly property int imgH: 88
    readonly property int capH: 24
    readonly property int tileH: imgH + capH
    readonly property int cols: rows.length === 1 ? 1 : 2
    readonly property int maxRows: 2

    // The pointer is anywhere on the card: Dock keeps hover-opened previews alive while it is.
    readonly property bool hov: hovHandler.hovered
    HoverHandler { id: hovHandler }

    width: 8 + cols * tileW + (cols - 1) * 10 + 8
    height: head.height + 9 + rowsClip.height + 16
    Behavior on width { NumberAnimation { duration: Tokens.motion.duration.fast; easing.type: Tokens.motion.easing.enter } }

    visible: opacity > 0.01
    opacity: on ? 1 : 0
    scale: on ? 1 : 0.94
    Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }
    Behavior on scale { SpringAnimation { spring: 3.6; damping: 0.3; epsilon: 0.001 } }
    Behavior on height { NumberAnimation { duration: Tokens.motion.duration.fast; easing.type: Tokens.motion.easing.enter } }

    CardSurface { anchors.fill: parent; radius: Tokens.radius.lg }

    // Head: the app's icon and name, the count quiet on the right in mono.
    Item {
        id: head
        x: 8; y: 8
        width: parent.width - 16
        height: 40
        Kirigami.Icon {
            id: hIcon
            x: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 24; height: 24
            roundToIconSize: false
            source: card.icon
        }
        Text {
            x: hIcon.x + hIcon.width + 10
            anchors.verticalCenter: parent.verticalCenter
            width: head.width - x - countText.width - 22
            text: card.appName
            color: Theme.text
            elide: Text.ElideRight
            font.pixelSize: Tokens.type.body; font.family: Theme.font; font.weight: Font.Medium
        }
        Text {
            id: countText
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: card.count + (card.count === 1 ? " window" : " windows")
            color: Theme.subtext
            font.pixelSize: Tokens.type.caption; font.family: Theme.mono
        }
    }
    Rectangle {   // the head's hairline, the menu's separator
        x: 16; y: head.y + head.height + 4
        width: parent.width - 32; height: 1
        color: Theme.text; opacity: 0.08
    }

    Flickable {
        id: rowsClip
        x: 8
        y: head.y + head.height + 9
        width: parent.width - 16
        height: Math.min(tilesGrid.height, card.maxRows * card.tileH + (card.maxRows - 1) * 10)
        contentWidth: width
        contentHeight: tilesGrid.height
        interactive: tilesGrid.height > height
        clip: true

        Grid {
            id: tilesGrid
            columns: card.cols
            spacing: 10

            Repeater {
                model: card.rows
                delegate: Item {
                    id: tile
                    readonly property var it: modelData
                    readonly property bool hov: tma.containsMouse
                    width: card.tileW; height: card.tileH
                    opacity: card.on ? 1 : 0
                    transform: Translate {
                        y: card.on ? 0 : 12
                        Behavior on y {
                            SequentialAnimation {
                                PauseAnimation { duration: card.appearRunning ? index * 40 : 0 }
                                NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter }
                            }
                        }
                    }
                    Behavior on opacity {
                        SequentialAnimation {
                            PauseAnimation { duration: card.appearRunning ? index * 40 : 0 }
                            NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter }
                        }
                    }

                    Item {   // the preview: the window's still, rounded and lifted on hover
                        id: preview
                        width: parent.width; height: card.imgH
                        scale: tma.pressed ? 0.97 : (tile.hov ? 1.04 : 1)
                        Behavior on scale { SpringAnimation { spring: 4; damping: 0.45; mass: 0.6 } }

                        Rectangle {   // the chip under a stream that has not connected (or never will)
                            anchors.fill: parent
                            radius: Tokens.radius.sm
                            color: Theme.veil(Tokens.tint.faint)
                        }
                        TaskManager.ScreencastingRequest {   // a live stream of this very window
                            id: stream
                            uuid: card.on && tile.it.live ? tile.it.uuid : ""
                        }
                        KPipeWire.PipeWireSourceItem {
                            id: streamItem
                            anchors.fill: parent
                            nodeId: stream.nodeId
                            // The video item must stay visible to paint; the rounded corners come
                            // from its own layer's mask (MultiEffect as the layer's effect).
                            opacity: stream.nodeId > 0 ? 1 : 0
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: imgMask
                                maskThresholdMin: 0.5
                                maskSpreadAtMax: 1.0
                            }
                            Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.base } }
                        }
                        Kirigami.Icon {
                            anchors.centerIn: parent
                            width: 40; height: 40
                            source: card.icon
                            opacity: stream.nodeId > 0 ? 0 : (tile.it.live || tile.it.minimized ? 0.9 : 0.55)
                            Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.base } }
                        }
                        Rectangle {
                            id: imgMask
                            anchors.fill: parent
                            visible: false
                            layer.enabled: true
                            radius: Tokens.radius.sm
                            color: "white"
                        }
                        Rectangle {   // hairline rim, like every glass edge
                            anchors.fill: parent
                            radius: Tokens.radius.sm
                            color: "transparent"
                            border.color: Theme.rim
                            border.width: 1
                        }
                        Rectangle {   // the active window's accent
                            anchors.fill: parent
                            radius: Tokens.radius.sm
                            visible: tile.it.active
                            color: "transparent"
                            border.color: Theme.accent
                            border.width: 2
                        }
                    }
                    Item {   // caption: the title, the X on hover
                        x: 2; y: card.imgH + 3
                        width: parent.width - 4; height: card.capH
                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 26
                            text: tile.it.title !== "" ? tile.it.title : (tile.it.minimized ? "Minimized" : "Window")
                            color: tile.it.active ? Theme.text : Theme.subtext
                            elide: Text.ElideRight
                            font.pixelSize: Tokens.type.caption; font.family: Theme.font
                        }
                        Item {   // the X: closes this one window, only while the tile is hovered
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24; height: 24
                            opacity: tile.hov ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.fast } }
                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                color: xMa.containsMouse ? Tokens.palette.red200 : Theme.subtext
                                font.pixelSize: Tokens.type.body; font.family: Theme.font
                            }
                            MouseArea {
                                id: xMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: card.closeOne(tile.it.mi)
                            }
                        }
                    }

                    MouseArea {
                        id: tma
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.MiddleButton) card.closeOne(tile.it.mi)
                            else card.pick(tile.it.mi)
                        }
                    }
                }
            }
        }
    }
}
