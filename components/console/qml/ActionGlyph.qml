import QtQuick
import AetherShared
import "."

// A row-level lifecycle action: a quiet glyph revealed on hover. Destructive ones arm
// first - accent colour, a second tap within 2.5s executes - ConfirmTile's language
// in miniature.
Item {
    id: ag
    property string glyph
    property bool needsArm: false
    property bool armed: false
    signal act()
    width: 20; height: 28
    Rectangle {
        anchors.fill: parent; radius: 8
        color: Qt.rgba(1, 1, 1, seat.hovered ? Tokens.material.tintHover : 0)
    }
    Glyph {
        anchors.centerIn: parent
        name: ag.glyph; size: 13
        color: ag.armed ? Theme.accent : Theme.subtext
    }
    HoverHandler { id: seat; cursorShape: Qt.PointingHandCursor }
    TapHandler {
        onTapped: {
            if (!ag.needsArm || ag.armed) {
                ag.armed = false
                ag.act()
            } else {
                ag.armed = true
                armTimer.restart()
            }
        }
    }
    Timer { id: armTimer; interval: 2500; onTriggered: ag.armed = false }
}
