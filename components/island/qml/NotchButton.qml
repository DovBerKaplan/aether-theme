import QtQuick
import AetherShared

// Round icon button that lives inside the notch.
Item {
    id: root
    property string glyph
    signal tapped()
    width: 30
    height: 30

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Qt.rgba(1, 1, 1, tap.pressed ? Tokens.tint.strong : hover.hovered ? Tokens.tint.soft : Tokens.tint.faint)
        Behavior on color { ColorAnimation { duration: Tokens.motion.duration.fast } }
    }
    Glyph {
        anchors.centerIn: parent
        name: root.glyph
        size: 15
        color: Theme.text
        scale: tap.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: Tokens.motion.duration.micro } }
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: tap; onTapped: root.tapped() }
}
