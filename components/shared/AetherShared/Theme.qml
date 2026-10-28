pragma Singleton
import QtQuick

// Meaning on top of Tokens (generated from theme/tokens.toml): which token plays which role.
// The island is always a dark object, like a real notch, in both KDE colour schemes.
QtObject {
    property bool dark: true
    property real bodyAlpha: Tokens.material.islandBodyAlpha

    readonly property color text: Tokens.role.island.text
    readonly property color subtext: Tokens.role.island.textMuted
    // The colour the user chose (island's Color panel), or "transparent" for the theme's own. It also tints the
    // glass a little - the whole island leans toward it without turning into it.
    property color accentOverride: "transparent"
    readonly property color accent: accentOverride.a > 0 ? accentOverride : Tokens.role.island.accent
    property real accentTint: 0                       // the island sets 0.07; the toasts and the dock keep the plain glass
    readonly property color chip: Tokens.role.island.chip
    readonly property color bodyTop: Qt.alpha(Qt.tint(Tokens.role.island.bodyTop, Qt.alpha(accent, accentTint)), bodyAlpha)
    readonly property color bodyBottom: Qt.alpha(Qt.tint(Tokens.role.island.bodyBottom, Qt.alpha(accent, accentTint * 1.4)), bodyAlpha)
    readonly property color rim: Qt.rgba(1, 1, 1, Tokens.material.rimAlpha)
    readonly property color bevel: Qt.rgba(0, 0, 0, Tokens.material.bevelAlpha)
    readonly property url grain: Qt.resolvedUrl("assets/grain.png")
    readonly property string font: Tokens.font.family
    readonly property string mono: Tokens.font.mono
}
