import QtQuick
import AetherShared

// The translate mark, in the shape every phone knows: two overlapping rounded squares, one
// carrying a Hebrew letter, the other a Latin one. `cut` is the colour behind the glyph (so the
// back square's letter reads as punched out).
Item {
    id: root
    property color color: Theme.text
    property color cut: "#1c1e24"
    property real size: 22
    width: size; height: size

    readonly property real sq: size * 0.64
    readonly property real r: size * 0.13

    Rectangle {   // back square: filled, with the Hebrew letter punched out
        x: 0; y: 0; width: root.sq; height: root.sq; radius: root.r
        color: root.color
        Text {
            anchors.centerIn: parent
            text: "א"
            font.family: Theme.font; font.weight: Font.Bold
            font.pixelSize: root.size * 0.46
            color: root.cut
        }
    }
    Rectangle {   // front square: outlined in the background colour's gap, with the Latin letter
        x: root.size - root.sq; y: root.size - root.sq; width: root.sq; height: root.sq; radius: root.r
        color: root.cut
        border.width: Math.max(1.2, root.size * 0.07)
        border.color: root.color
        Text {
            anchors.centerIn: parent
            text: "A"
            font.family: Theme.font; font.weight: Font.Bold
            font.pixelSize: root.size * 0.44
            color: root.color
        }
    }
}
