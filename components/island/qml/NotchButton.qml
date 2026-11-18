import QtQuick
import AetherShared

// Round icon button that lives inside the notch.
Item {
    id: root
    property string glyph
    signal tapped()
    width: 30
    height: 30

    Rectangle {   // the seat exists only under the pointer: at rest the tab is pure ink on glass
        anchors.fill: parent
        radius: width / 2
        color: Theme.veil(tap.pressed ? Tokens.tint.strong : hover.hovered ? Tokens.tint.soft : 0)
        Behavior on color { ColorAnimation { duration: Tokens.motion.duration.fast } }
    }
    Glyph {
        anchors.centerIn: parent
        name: root.glyph
        size: 15
        color: Theme.text
        scale: tap.pressed ? 0.92 : 1
        // the dock's own press spring: the tab presses with the system's jelly, not a flat tween
        Behavior on scale { SpringAnimation { spring: 4; damping: 0.45; mass: 0.6 } }
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: tap; onTapped: root.tapped() }
}
