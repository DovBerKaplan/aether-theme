pragma Singleton
import QtQuick

// The island is always a dark object, like a real notch, in both KDE colour schemes.
QtObject {
    property bool dark: true
    property real bodyAlpha: 0.75

    readonly property color text: "#eceef2"
    readonly property color subtext: "#8d939d"
    readonly property color accent: "#00f2fe"
    readonly property color chip: "#2a2d34"
    readonly property color bodyTop: Qt.rgba(0.110, 0.118, 0.141, bodyAlpha)      // #1c1e24
    readonly property color bodyBottom: Qt.rgba(0.071, 0.078, 0.094, bodyAlpha)   // #121418
    readonly property color rim: Qt.rgba(1, 1, 1, 0.09)
    readonly property color bevel: Qt.rgba(0, 0, 0, 0.35)
    readonly property url grain: Qt.resolvedUrl("assets/grain.png")
    readonly property string font: "Inter"
    readonly property string mono: "JetBrains Mono"
}
