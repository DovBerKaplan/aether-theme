import QtQuick
import AetherShared

// Indeterminate 2 px bar; fades out when not running.
Item {
    id: root
    property bool running: false
    implicitWidth: 200
    implicitHeight: 2
    clip: true
    opacity: running ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.base } }

    Rectangle {
        id: seg
        width: root.width * 0.3; height: parent.height; radius: height / 2
        color: Theme.accent
        SequentialAnimation on x {
            running: root.running || root.opacity > 0
            loops: Animation.Infinite
            NumberAnimation { from: -seg.width; to: root.width; duration: Tokens.motion.duration.ambient * 1.4; easing.type: Tokens.motion.easing.ambient }
        }
    }
}
