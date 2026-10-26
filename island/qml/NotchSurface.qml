import QtQuick
import QtQuick.Shapes
import QtQuick.Effects

// The island's silhouette and material - one parametric shape for every state.
//
//   strip   a bar flush with the top edge, `stripW` wide and `stripH` tall (the menu-bar part)
//   notch   a tab hanging from the middle, `notchW` wide down to `notchBottom`, with concave
//           shoulders where it meets the strip and rounded lower corners
//
// bar:    stripW = screen width, stripH = 30        (strip + notch, like a MacBook)
// large:  stripH = 0, so only the notch remains and it grows into the big island
// hidden: both retracted
//
// Material: dark translucent body (KWin blurs what is behind it) + fine grain + a thin rim on
// the sides/bottom only, so the top looks like it grows out of the screen.
Item {
    id: root
    property real winW: 1920
    property real stripW: 1920
    property real stripH: 30
    property real notchW: 232
    property real notchBottom: 38
    property real cornerR: 14
    property real shoulder: 10

    readonly property real k: 0.5523
    readonly property real cx: winW / 2
    readonly property real s: Math.max(0, Math.min(shoulder, (notchBottom - stripH) / 2))
    readonly property real rb: Math.max(0, Math.min(cornerR, notchW / 2, notchBottom - stripH - s))
    // The strip can never be narrower than the notch plus its shoulders.
    readonly property real sw: Math.max(stripW, notchW + 2 * s)
    width: winW
    height: notchBottom

    // Path commands: the single source for drawing, blur and the input region.
    readonly property var segments: {
        const x0 = cx - sw / 2, x1 = cx + sw / 2
        const nr = cx + notchW / 2, nl = cx - notchW / 2
        const Hb = stripH, B = notchBottom, K = k
        return [
            { t: "M", x: x0, y: 0 },
            { t: "L", x: x1, y: 0 },
            { t: "L", x: x1, y: Hb },
            { t: "L", x: nr + s, y: Hb },
            { t: "C", x1: nr + s - K * s, y1: Hb, x2: nr, y2: Hb + s - K * s, x: nr, y: Hb + s },
            { t: "L", x: nr, y: B - rb },
            { t: "C", x1: nr, y1: B - rb + K * rb, x2: nr - rb + K * rb, y2: B, x: nr - rb, y: B },
            { t: "L", x: nl + rb, y: B },
            { t: "C", x1: nl + rb - K * rb, y1: B, x2: nl, y2: B - rb + K * rb, x: nl, y: B - rb },
            { t: "L", x: nl, y: Hb + s },
            { t: "C", x1: nl, y1: Hb + s - K * s, x2: nl - s + K * s, y2: Hb, x: nl - s, y: Hb },
            { t: "L", x: x0, y: Hb }
        ]
    }
    function svg(cmds, close) {
        let d = ""
        for (const c of cmds) {
            if (c.t === "M") d += "M " + c.x + " " + c.y + " "
            else if (c.t === "L") d += "L " + c.x + " " + c.y + " "
            else d += "C " + c.x1 + " " + c.y1 + " " + c.x2 + " " + c.y2 + " " + c.x + " " + c.y + " "
        }
        return d + (close ? "Z" : "")
    }
    readonly property string outline: svg(segments, true)
    // Rim: everything except the top edge and the strip's cut ends.
    readonly property string rimPath: {
        const tail = segments.slice(3)
        return svg([{ t: "M", x: cx + sw / 2, y: stripH }].concat(tail), false)
    }

    // Dark body
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: 0; y2: root.notchBottom
                GradientStop { position: 0.0; color: Theme.bodyTop }
                GradientStop { position: 1.0; color: Theme.bodyBottom }
            }
            PathSvg { path: root.outline }
        }
    }

    // Fine grain, masked to the silhouette
    Shape {
        id: maskShape
        anchors.fill: parent
        visible: false
        layer.enabled: true
        ShapePath {
            strokeWidth: -1
            fillColor: "white"
            PathSvg { path: root.outline }
        }
    }
    Image {
        id: grain
        anchors.fill: parent
        source: "assets/grain.png"
        fillMode: Image.Tile
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: grain
        maskEnabled: true
        maskSource: maskShape
        opacity: 0.022
    }

    // Rim
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: "transparent"
            strokeColor: Theme.rim
            strokeWidth: 1
            PathSvg { path: root.rimPath }
        }
    }
}
