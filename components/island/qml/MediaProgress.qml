import QtQuick
import AetherShared

// Slim seek bar: mono time labels flanking a hairline track that thickens on
// hover. While dragging the local value wins; one seek fires on release.
Item {
    id: root
    property real fraction: 0
    property int lengthSec: 0
    property bool playing: false
    property bool canSeek: true
    signal seekRequested(real f)

    height: 20
    property bool dragging: false
    property real dragValue: 0
    readonly property real shown: dragging ? dragValue : fraction

    readonly property int timeW: lengthSec >= 3600 ? 48 : 34

    function fmt(s) {
        s = Math.max(0, Math.round(s))
        const h = Math.floor(s / 3600)
        const m = Math.floor((s % 3600) / 60)
        const sec = s % 60
        return (h > 0 ? h + ":" + (m < 10 ? "0" : "") + m : m) + ":" + (sec < 10 ? "0" : "") + sec
    }

    Text {
        id: elapsed
        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
        width: root.timeW
        text: root.fmt(root.shown * root.lengthSec)
        font { family: Theme.mono; pixelSize: Tokens.type.caption; weight: Font.Medium }
        color: Theme.subtext
    }
    Text {
        id: remaining
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        horizontalAlignment: Text.AlignRight
        width: root.timeW
        text: "-" + root.fmt((1 - root.shown) * root.lengthSec)
        font { family: Theme.mono; pixelSize: Tokens.type.caption; weight: Font.Medium }
        color: Theme.subtext
    }

    Item {
        id: trackArea
        anchors { left: elapsed.right; right: remaining.left; leftMargin: 10; rightMargin: 10; verticalCenter: parent.verticalCenter }
        height: 20

        Rectangle {
            id: track
            anchors.centerIn: parent
            width: parent.width
            height: area.containsMouse || root.dragging ? 5 : 3
            radius: height / 2
            color: Theme.veil(Tokens.tint.soft)
            Behavior on height { NumberAnimation { duration: Tokens.motion.duration.fast; easing.type: Tokens.motion.easing.enter } }
            Rectangle {
                width: Math.max(track.height, track.width * root.shown)
                height: parent.height
                radius: parent.radius
                color: Theme.accentFill
                Behavior on width {
                    enabled: !root.dragging
                    NumberAnimation { duration: root.playing ? 1100 : 0; easing.type: Easing.Linear }
                }
            }
        }
        Rectangle {
            id: knob
            y: trackArea.height / 2 - height / 2
            x: Math.max(0, Math.min(trackArea.width - width, trackArea.width * root.shown - width / 2))
            width: 12; height: 12; radius: Tokens.radius.sm
            color: "white"
            opacity: (area.containsMouse || root.dragging) && root.canSeek && root.lengthSec > 0 ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.fast } }
        }

        MouseArea {
            id: area
            anchors.fill: parent
            enabled: root.canSeek && root.lengthSec > 0
            hoverEnabled: true
            cursorShape: root.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor
            preventStealing: true
            function setFrom(mx) { root.dragValue = Math.max(0, Math.min(1, mx / width)) }
            onPressed: (m) => { root.dragging = true; setFrom(m.x) }
            onPositionChanged: (m) => { if (pressed) setFrom(m.x) }
            onReleased: { root.seekRequested(root.dragValue); root.dragging = false }
        }
    }
}
