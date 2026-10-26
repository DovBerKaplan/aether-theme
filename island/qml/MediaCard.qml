import QtQuick

// Now playing: artwork, title/artist, transport controls and a thin progress line.
Item {
    id: root
    height: 84

    Rectangle { anchors.fill: parent; radius: 22; color: Qt.rgba(1, 1, 1, 0.055) }

    Rectangle {
        id: art
        x: 12; anchors.verticalCenter: parent.verticalCenter
        width: 60; height: 60; radius: 14
        color: Theme.chip
        clip: true
        Image {
            anchors.fill: parent
            source: media.artUrl
            fillMode: Image.PreserveAspectCrop
            visible: status === Image.Ready
            asynchronous: true
        }
        Text {
            anchors.centerIn: parent
            visible: media.artUrl.length === 0
            text: "♪"
            color: Theme.subtext
            font.pixelSize: 24
        }
    }
    Column {
        anchors { left: art.right; leftMargin: 12; right: controls.left; rightMargin: 8; verticalCenter: parent.verticalCenter; verticalCenterOffset: -2 }
        spacing: 2
        Text {
            width: parent.width
            text: media.title || media.playerName
            elide: Text.ElideRight
            font { family: Theme.font; pixelSize: 14; weight: Font.DemiBold }
            color: Theme.text
        }
        Text {
            width: parent.width
            text: media.artist || media.playerName
            elide: Text.ElideRight
            font { family: Theme.font; pixelSize: 12 }
            color: Theme.subtext
        }
    }
    Row {
        id: controls
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter; verticalCenterOffset: -2 }
        spacing: 4
        Repeater {
            model: [{ g: "prev", a: 0 }, { g: "play", a: 1 }, { g: "next", a: 2 }]
            delegate: Item {
                required property var modelData
                width: 34; height: 34
                Glyph {
                    anchors.centerIn: parent
                    size: modelData.a === 1 ? 20 : 16
                    name: modelData.a === 1 ? (media.playing ? "pause" : "play") : modelData.g
                    opacity: ctl.pressed ? 0.6 : 1
                }
                TapHandler {
                    id: ctl
                    onTapped: modelData.a === 0 ? media.previous() : modelData.a === 1 ? media.playPause() : media.next()
                }
            }
        }
    }
    Rectangle {                         // progress line
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16; bottomMargin: 8 }
        height: 3; radius: 2
        color: Qt.rgba(1, 1, 1, 0.12)
        Rectangle { width: parent.width * media.progress; height: parent.height; radius: 2; color: Theme.accent }
    }
}
