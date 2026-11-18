import QtQuick
import QtQuick.Shapes
import AetherShared

// The broom on a 30 x 30 grid, leaning like one in use. `swish` (degrees) swings the head around
// the top of the handle; the desk drives it for the sweeping strokes. tip() is where the bristles
// meet the floor, in this item's coordinates: the dust puffs start there.
Item {
    id: root
    property real swish: 0
    property color ink: Theme.text
    function tip() { return head.mapToItem(root, 15, 26); }
    width: 30
    height: 30

    Item {
        anchors.fill: parent
        transform: Rotation { origin.x: 15; origin.y: 15; angle: 32 }
        Item {
            id: head
            anchors.fill: parent
            transform: Rotation { origin.x: 15; origin.y: 2; angle: root.swish }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {                           // handle
                    strokeColor: root.ink; strokeWidth: 1.8; fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: 15; startY: 2
                    PathLine { x: 15; y: 13.5 }
                }
                ShapePath {                           // head: binding and the fanned brush
                    strokeColor: root.ink; strokeWidth: 1.8; fillColor: Qt.alpha(root.ink, 0.22)
                    joinStyle: ShapePath.RoundJoin; capStyle: ShapePath.RoundCap
                    startX: 10.5; startY: 14
                    PathLine { x: 19.5; y: 14 }
                    PathLine { x: 23; y: 26 }
                    PathLine { x: 7; y: 26 }
                    PathLine { x: 10.5; y: 14 }
                }
                ShapePath {                           // bristles
                    strokeColor: root.ink; strokeWidth: 1.4; fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: 12.6; startY: 19
                    PathLine { x: 11.8; y: 26 }
                    PathMove { x: 15; y: 19 }
                    PathLine { x: 15; y: 26 }
                    PathMove { x: 17.4; y: 19 }
                    PathLine { x: 18.2; y: 26 }
                }
            }
        }
    }
}
