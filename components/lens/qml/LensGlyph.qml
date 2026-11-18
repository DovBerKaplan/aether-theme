import QtQuick
import AetherShared
import QtQuick.Shapes

// The camera-lens mark: four open corners of a rounded square around a filled circle, with a
// small dot at the lower right - drawn here, so no brand artwork is shipped.
Shape {
    id: root
    property color color: Theme.text
    property real size: 22
    width: size; height: size
    preferredRendererType: Shape.CurveRenderer
    readonly property real s: size
    readonly property real t: size * 0.11
    readonly property real r: size * 0.28

    ShapePath {
        strokeColor: root.color
        strokeWidth: root.t
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        // top-left corner, open toward the middles of its sides
        startX: root.t / 2; startY: root.s * 0.42
        PathLine { x: root.t / 2; y: root.r }
        PathArc { x: root.r; y: root.t / 2; radiusX: root.r - root.t / 2; radiusY: root.r - root.t / 2 }
        PathLine { x: root.s * 0.42; y: root.t / 2 }
        PathMove { x: root.s * 0.58; y: root.t / 2 }
        PathLine { x: root.s - root.r; y: root.t / 2 }
        PathArc { x: root.s - root.t / 2; y: root.r; radiusX: root.r - root.t / 2; radiusY: root.r - root.t / 2 }
        PathLine { x: root.s - root.t / 2; y: root.s * 0.42 }
        PathMove { x: root.t / 2; y: root.s * 0.58 }
        PathLine { x: root.t / 2; y: root.s - root.r }
        PathArc { x: root.r; y: root.s - root.t / 2; radiusX: root.r - root.t / 2; radiusY: root.r - root.t / 2; direction: PathArc.Counterclockwise }
        PathLine { x: root.s * 0.42; y: root.s - root.t / 2 }
    }
    ShapePath {
        strokeColor: "transparent"
        fillColor: root.color
        PathAngleArc { centerX: root.s / 2; centerY: root.s / 2; radiusX: root.s * 0.17; radiusY: root.s * 0.17; startAngle: 0; sweepAngle: 360 }
        PathAngleArc { centerX: root.s * 0.80; centerY: root.s * 0.80; radiusX: root.s * 0.09; radiusY: root.s * 0.09; startAngle: 0; sweepAngle: 360 }
    }
}
