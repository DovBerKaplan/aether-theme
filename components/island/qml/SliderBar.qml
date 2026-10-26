import QtQuick
import AetherShared

// Thin pill slider. `value` is 0..1 from the system; while dragging the local value wins.
Item {
    id: root
    property real value: 0
    property color fillColor: Theme.text
    signal moved(real v)

    height: 26
    property bool dragging: false
    property real dragValue: 0
    readonly property real shown: dragging ? dragValue : value

    Rectangle {
        id: track
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
        height: 8; radius: 4
        color: Qt.rgba(1, 1, 1, 0.14)
        Rectangle {
            width: Math.max(track.height, track.width * root.shown)
            height: parent.height; radius: 4
            color: root.fillColor
            Behavior on width { enabled: !root.dragging; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
    }
    Rectangle {                       // knob, only while hovered or dragged
        x: Math.max(0, Math.min(track.width - width, track.width * root.shown - width / 2))
        anchors.verticalCenter: parent.verticalCenter
        width: 16; height: 16; radius: 8
        color: "white"
        opacity: area.containsMouse || root.dragging ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        function setFrom(mx) {
            root.dragValue = Math.max(0, Math.min(1, mx / width))
            throttle.pending = root.dragValue
            if (!throttle.running) { root.moved(root.dragValue); throttle.start() }
        }
        onPressed: (m) => { root.dragging = true; setFrom(m.x) }
        onPositionChanged: (m) => { if (pressed) setFrom(m.x) }
        onReleased: { root.moved(root.dragValue); root.dragging = false }
    }
    // Send at most ~20 updates per second while dragging
    Timer {
        id: throttle
        property real pending: 0
        interval: 50
        onTriggered: if (root.dragging) root.moved(pending)
    }
}
