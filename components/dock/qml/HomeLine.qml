import QtQuick
import AetherShared

// The dock's grab line. The moment it is pressed (`pressed`) it does what a phone's gesture pill
// does: stretches, thickens, brightens and lifts on a spring, and springs back with a wobble when
// let go. No colour: it stays the quiet stripe.
Item {
    id: root
    property bool horiz: true
    property color baseColor: "white"
    property real baseOpacity: 0.45
    property bool pressed: false
    readonly property real len: horiz ? width : height
    readonly property real th: horiz ? height : width

    Rectangle {
        id: pill
        anchors.centerIn: parent
        // eased on a spring, so it overshoots and wobbles back when released
        property real p: root.pressed ? 1 : 0
        Behavior on p { SpringAnimation { spring: 9; damping: 0.28; epsilon: 0.002 } }
        width: root.horiz ? root.len * (1 + 0.8 * p) : root.th * (1 + 1.5 * p)
        height: root.horiz ? root.th * (1 + 1.5 * p) : root.len * (1 + 0.8 * p)
        radius: Math.min(width, height) / 2
        color: root.baseColor
        // sits outside the glass, over whatever is behind the dock: a hairline of dark keeps it visible on white
        border.width: 1
        border.color: Qt.rgba(0, 0, 0, 0.32)
        opacity: root.baseOpacity + (1 - root.baseOpacity) * Math.max(0, Math.min(1, p))
        // lifts away from the screen edge, toward the dock
        transform: Translate {
            x: root.horiz ? 0 : 6 * pill.p
            y: root.horiz ? -6 * pill.p : 0
        }
    }
}
