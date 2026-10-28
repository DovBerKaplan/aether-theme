pragma Singleton
import QtQuick

// Meaning on top of Tokens (generated from theme/tokens.toml): which token plays which role.
// The island is always a dark object, like a real notch, in both KDE colour schemes - it never
// touches `dark`. The toasts bind `dark` to the system scheme, so their cards follow it with
// the dock's calibrated light material (white veil, cool grey hairline, less grain).
QtObject {
    property bool dark: true
    property real bodyAlpha: Tokens.material.islandBodyAlpha

    readonly property color text: dark ? Tokens.role.island.text : Tokens.role.light.text
    readonly property color subtext: dark ? Tokens.role.island.textMuted : Tokens.role.light.textMuted
    // The colour the user chose (island's Color panel), or "transparent" for the theme's own. It also tints the
    // glass a little - the whole island leans toward it without turning into it.
    property color accentOverride: "transparent"
    readonly property color accent: accentOverride.a > 0 ? accentOverride : (dark ? Tokens.role.island.accent : Tokens.role.light.accent)
    // Ink on top of the accent: dark on a light accent, white on a dark one.
    readonly property color onAccent: (0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b) > 0.5 ? Tokens.role.dark.textOnAccent : "#ffffff"
    property real accentTint: 0                       // the island sets 0.07; the toasts and the dock keep the plain glass
    readonly property color chip: dark ? Tokens.role.island.chip : Qt.rgba(0, 0, 0, 0.07)
    // Dark: the island's ink glass, tinted toward the accent. Light: the dock's white veil.
    readonly property color bodyTop: dark ? Qt.alpha(Qt.tint(Tokens.role.island.bodyTop, Qt.alpha(accent, accentTint)), bodyAlpha)
                                          : Qt.rgba(0.95, 0.96, 0.99, bodyAlpha)
    readonly property color bodyBottom: dark ? Qt.alpha(Qt.tint(Tokens.role.island.bodyBottom, Qt.alpha(accent, accentTint * 1.4)), bodyAlpha)
                                             : Qt.rgba(0.90, 0.92, 0.97, bodyAlpha * 0.8)
    readonly property color rim: dark ? Qt.rgba(1, 1, 1, Tokens.material.rimAlpha)
                                      : Qt.rgba(0.42, 0.48, 0.60, 0.28)   // cool grey hairline: shows on white and on dark
    readonly property color bevel: Qt.rgba(0, 0, 0, Tokens.material.bevelAlpha)
    readonly property url grain: Qt.resolvedUrl("assets/grain.png")
    readonly property string font: Tokens.font.family
    readonly property string mono: Tokens.font.mono
}
