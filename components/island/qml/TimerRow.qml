import QtQuick
import AetherShared

// Presets while idle; remaining time with pause / cancel while running.
Item {
    id: root
    required property var timer
    height: 58

    Rectangle { anchors.fill: parent; radius: Tokens.radius.xl; color: Qt.rgba(1, 1, 1, Tokens.tint.faint) }

    // idle: presets
    Row {
        visible: !root.timer.active
        anchors.centerIn: parent
        spacing: 10
        Repeater {
            model: [1, 5, 10, 25]
            delegate: Rectangle {
                required property int modelData
                width: 88; height: 36; radius: Tokens.radius.lg
                color: presetTap.pressed ? Theme.accent : Theme.chip
                Behavior on color { ColorAnimation { duration: Tokens.motion.duration.micro } }
                Text {
                    anchors.centerIn: parent
                    text: modelData + " min"
                    font { family: Theme.font; pixelSize: Tokens.type.body; weight: Font.Medium }
                    color: presetTap.pressed ? Tokens.role.dark.textOnAccent : Theme.text
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
            font { family: Theme.mono; pixelSize: Tokens.type.heading; weight: Font.Medium }
            color: root.timer.running ? Theme.accent : Theme.subtext
        }
        Row {
            anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 10
            Rectangle {
                width: 38; height: 38; radius: Tokens.radius.xl; color: Theme.chip
                Glyph { anchors.centerIn: parent; name: root.timer.running ? "pause" : "play"; size: 16 }
                TapHandler { onTapped: root.timer.toggle() }
            }
            Rectangle {
                width: 38; height: 38; radius: Tokens.radius.xl; color: Theme.chip
                Glyph { anchors.centerIn: parent; name: "close"; size: 14 }
                TapHandler { onTapped: root.timer.cancel() }
            }
        }
    }
}
