pragma Singleton
import QtQuick

// Meaning on top of Tokens (generated from theme/tokens.toml): which token plays which role.
// The island is always a dark object, like a real notch, in both KDE colour schemes.
QtObject {
    property bool dark: true
    property real bodyAlpha: Tokens.material.islandBodyAlpha

    readonly property color text: Tokens.role.island.text
    readonly property color subtext: Tokens.role.island.textMuted
    readonly property color accent: Tokens.role.island.accent
    readonly property color chip: Tokens.role.island.chip
    readonly property color bodyTop: Qt.alpha(Tokens.role.island.bodyTop, bodyAlpha)
    readonly property color bodyBottom: Qt.alpha(Tokens.role.island.bodyBottom, bodyAlpha)
    readonly property color rim: Qt.rgba(1, 1, 1, Tokens.material.rimAlpha)
    readonly property color bevel: Qt.rgba(0, 0, 0, Tokens.material.bevelAlpha)
    readonly property url grain: Qt.resolvedUrl("assets/grain.png")
    readonly property string font: Tokens.font.family
    readonly property string mono: Tokens.font.mono
}
