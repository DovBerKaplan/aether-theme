import QtQuick
import QtQuick.Effects

// Same dark grain material as the notch, as a rounded card (toasts).
Item {
    id: root
    property real radius: Tokens.radius.card

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.bodyTop }
            GradientStop { position: 1.0; color: Theme.bodyBottom }
        }
        border.width: 1
        border.color: Theme.rim
    }
    Rectangle {
        id: mask
        anchors.fill: parent
        radius: root.radius
        visible: false
        layer.enabled: true
    }
    Image {
        id: grain
        anchors.fill: parent
        source: Theme.grain
        fillMode: Image.Tile
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: grain
        maskEnabled: true
        maskSource: mask
        // rougher grain on dark glass, almost none on the light veil (dock's calibration)
        opacity: Tokens.material.grainOpacity
    }
}
