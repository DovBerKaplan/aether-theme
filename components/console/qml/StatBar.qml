import QtQuick
import AetherShared

// A value bar for the detail card: label left, mono value right, a quiet accent fill.
Column {
    id: sb
    property string label
    property real frac: 0
    property string value
    width: parent ? parent.width : 0
    spacing: Tokens.space.xs
    Item {
        width: parent.width; height: 16
        Text {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            text: sb.label; textFormat: Text.PlainText
            font { family: Theme.font; pixelSize: Tokens.type.label }
            color: Theme.subtext
        }
        Text {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: sb.value; textFormat: Text.PlainText
            font { family: Theme.mono; pixelSize: Tokens.type.label }
            color: Theme.text
        }
    }
    Rectangle {
        width: parent.width; height: 6; radius: 3
        color: Theme.chip
        Rectangle {
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: Math.max(0, Math.min(1, sb.frac)) * parent.width
            height: parent.height; radius: 3
            color: Theme.accent
            Behavior on width { NumberAnimation { duration: Tokens.motion.duration.slow; easing.type: Easing.OutCubic } }
        }
    }
}
