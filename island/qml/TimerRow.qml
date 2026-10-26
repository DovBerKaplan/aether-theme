import QtQuick

// Presets while idle; remaining time with pause / cancel while running.
Item {
    id: root
    required property var timer
    height: 58

    Rectangle { anchors.fill: parent; radius: 22; color: Qt.rgba(1, 1, 1, 0.055) }

    // idle: presets
    Row {
        visible: !root.timer.active
        anchors.centerIn: parent
        spacing: 10
        Repeater {
            model: [1, 5, 10, 25]
            delegate: Rectangle {
                required property int modelData
                width: 88; height: 36; radius: 18
                color: presetTap.pressed ? Theme.accent : Theme.chip
                Behavior on color { ColorAnimation { duration: 100 } }
                Text {
                    anchors.centerIn: parent
                    text: modelData + " min"
                    font { family: Theme.font; pixelSize: 13; weight: Font.Medium }
                    color: presetTap.pressed ? "#00373a" : Theme.text
                }
                TapHandler { id: presetTap; onTapped: root.timer.start(modelData * 60) }
            }
        }
    }
    // running
    Item {
        visible: root.timer.active
        anchors.fill: parent
        Text {
            x: 20; anchors.verticalCenter: parent.verticalCenter
            text: root.timer.text
            font { family: Theme.mono; pixelSize: 24; weight: Font.Medium }
            color: root.timer.running ? Theme.accent : Theme.subtext
        }
        Row {
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 10
            Rectangle {
                width: 38; height: 38; radius: 19; color: Theme.chip
                Glyph { anchors.centerIn: parent; name: root.timer.running ? "pause" : "play"; size: 16 }
                TapHandler { onTapped: root.timer.toggle() }
            }
            Rectangle {
                width: 38; height: 38; radius: 19; color: Theme.chip
                Glyph { anchors.centerIn: parent; name: "close"; size: 14 }
                TapHandler { onTapped: root.timer.cancel() }
            }
        }
    }
}
