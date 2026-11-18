import QtQuick
import QtQuick.Shapes
import AetherShared

// The folder, in two layers so the stand-ins can pass between them: part "back" is the back wall,
// its tab and a sheet of paper that rises as the folder opens; part "front" is the front flap, which
// tips toward the viewer (lower and wider at the top) as `open` goes 0 -> 1. The desk stacks the
// flying stand-ins between the two. Drawn on a 30 x 30 grid, duotone in the glyph's ink.
Item {
    id: root
    property string part: "back"         // "back" | "front"
    property real open: 0
    property color ink: Theme.text
    width: 30
    height: 30

    Shape {
        anchors.fill: parent
        visible: root.part === "back"
        preferredRendererType: Shape.CurveRenderer
        ShapePath {                                   // back wall with the tab
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: Qt.alpha(root.ink, 0.5)
            startX: 4; startY: 8.5
            PathQuad { x: 6; y: 6.5; controlX: 4; controlY: 6.5 }
            PathLine { x: 11.5; y: 6.5 }
            PathLine { x: 14; y: 9 }
            PathLine { x: 24; y: 9 }
            PathQuad { x: 26; y: 11; controlX: 26; controlY: 9 }
            PathLine { x: 26; y: 22.5 }
            PathQuad { x: 24; y: 24.5; controlX: 26; controlY: 24.5 }
            PathLine { x: 6; y: 24.5 }
            PathQuad { x: 4; y: 22.5; controlX: 4; controlY: 24.5 }
            PathLine { x: 4; y: 8.5 }
        }
        ShapePath {                                   // a sheet that peeks out as the folder opens
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: Qt.alpha(root.ink, 0.92)
            startX: 7.5; startY: 13 - root.open * 3.5
            PathLine { x: 22.5; y: 13 - root.open * 3.5 }
            PathLine { x: 22.5; y: 20 }
            PathLine { x: 7.5; y: 20 }
            PathLine { x: 7.5; y: 13 - root.open * 3.5 }
        }
    }
    Shape {
        anchors.fill: parent
        visible: root.part === "front"
        preferredRendererType: Shape.CurveRenderer
        ShapePath {                                   // the front flap
            readonly property real top: 12 + root.open * 5
            readonly property real flare: root.open * 2.5
            strokeColor: Qt.alpha(Qt.darker(root.ink, 1.6), 0.35)
            strokeWidth: 0.8
            joinStyle: ShapePath.RoundJoin
            fillColor: root.ink
            startX: 4 - flare; startY: top
            PathLine { x: 26 + root.open * 2.5; y: 12 + root.open * 5 }
            PathLine { x: 26; y: 22.5 }
            PathQuad { x: 24; y: 24.5; controlX: 26; controlY: 24.5 }
            PathLine { x: 6; y: 24.5 }
            PathQuad { x: 4; y: 22.5; controlX: 4; controlY: 24.5 }
            PathLine { x: 4 - root.open * 2.5; y: 12 + root.open * 5 }
        }
    }
}
