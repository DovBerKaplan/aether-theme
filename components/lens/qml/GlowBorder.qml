import QtQuick
import AetherShared
import QtQuick.Shapes
import QtQuick.Effects

// The four-colour frame around the screen edge: a thin bright line with a soft halo inside it, the
// colours (blue, red, yellow, green, twice around) turning slowly. `strength` 0..1 fades it; `angle`
// turns it; `reveal` 0..1 grows it outward from (originX, originY) - the point on the screen edge
// where the dock's grab line was - and, run backwards, pulls it back in.
Item {
    id: root
    property real strength: 1
    property real thickness: 5        // the bright line at the very edge
    property real halo: 18            // the soft band behind it
    property real haloBlur: 30
    property real radius: 26
    property real angle: 0
    property real reveal: 1
    property real originX: width / 2
    property real originY: height
    // farthest corner, over the mask's solid fraction (0.7), so reveal = 1 covers everything
    readonly property real reach: Math.max(Math.hypot(originX, originY), Math.hypot(width - originX, originY),
                                           Math.hypot(originX, height - originY), Math.hypot(width - originX, height - originY)) / 0.7

    readonly property var colors: [Tokens.role.lens.ringBlue, Tokens.role.lens.ringRed, Tokens.role.lens.ringYellow, Tokens.role.lens.ringGreen]

    component Ring: Shape {
        id: ringShape
        property real band: 3
        anchors.fill: parent
        visible: false
        layer.enabled: true
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillRule: ShapePath.OddEvenFill
            fillGradient: ConicalGradient {
                centerX: root.width / 2
                centerY: root.height / 2
                angle: root.angle
                GradientStop { position: 0.000; color: root.colors[0] }
                GradientStop { position: 0.125; color: root.colors[1] }
                GradientStop { position: 0.250; color: root.colors[2] }
                GradientStop { position: 0.375; color: root.colors[3] }
                GradientStop { position: 0.500; color: root.colors[0] }
                GradientStop { position: 0.625; color: root.colors[1] }
                GradientStop { position: 0.750; color: root.colors[2] }
                GradientStop { position: 0.875; color: root.colors[3] }
                GradientStop { position: 1.000; color: root.colors[0] }
            }
            PathRectangle { x: -2; y: -2; width: root.width + 4; height: root.height + 4 }
            PathRectangle {
                x: ringShape.band; y: ringShape.band
                width: root.width - 2 * ringShape.band; height: root.height - 2 * ringShape.band
                radius: root.radius
            }
        }
    }
    // Four rings of growing width, each blurred as wide as it is thick and laid over the last: their
    // sum is a long, smooth tail - brightest at the edge, easing out over ~90 px - not a band.
    Ring { id: ringA; band: root.thickness }
    Ring { id: ringB; band: 14 }
    Ring { id: ringC; band: 34 }
    Ring { id: ringD; band: 62 }

    // where it grows from: a disc spreading out of the origin point
    Item {
        id: revealMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Shape {
            anchors.fill: parent
            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: root.originX; centerY: root.originY
                    focalX: root.originX; focalY: root.originY
                    centerRadius: Math.max(1, root.reveal * root.reach)
                    GradientStop { position: 0.0; color: "white" }
                    GradientStop { position: 0.7; color: "white" }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                PathRectangle { x: 0; y: 0; width: root.width; height: root.height }
            }
        }
    }

    component Layer: MultiEffect {
        property real amount: 1
        property real spread: 20
        anchors.fill: parent
        maskEnabled: true
        maskSource: revealMask
        visible: root.reveal > 0.001
        blurEnabled: true
        blur: 1
        blurMax: spread
        opacity: root.strength * amount
    }
    Layer { source: ringD; spread: 84; amount: 0.38 }
    Layer { source: ringC; spread: 46; amount: 0.55 }
    Layer { source: ringB; spread: 22; amount: 0.8 }
    Layer { source: ringA; spread: 6; amount: 1 }
}
