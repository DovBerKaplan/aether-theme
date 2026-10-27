import QtQuick
import AetherShared

// Four small bars; `level` is the daemon's 0-4 (or -1 = unknown, shown empty).
Row {
    property int level: -1
    spacing: 2
    Repeater {
        model: 4
        delegate: Rectangle {
            required property int index
            width: 3; height: 3 + index * 2; radius: 1
            anchors.bottom: parent ? parent.bottom : undefined
            color: Theme.text
            opacity: index < level ? 0.9 : 0.25
        }
    }
}
