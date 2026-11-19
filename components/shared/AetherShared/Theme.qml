pragma Singleton
import QtQuick

// Meaning on top of Tokens (generated from theme/tokens.toml): which token plays which role.
// The island is always a dark object, like a real notch, in both KDE colour schemes - it never
// touches `dark`. The toasts bind `dark` to the system scheme, so their cards follow it with
// the dock's calibrated light material (white veil, cool grey hairline, less grain).
QtObject {
    property bool dark: true
    property real bodyAlpha: Tokens.material.islandBodyAlpha

    // The colour the user chose (island's Color panel), or "transparent" for the theme's own.
    property color accentOverride: "transparent"
    readonly property color accent: accentOverride.a > 0 ? accentOverride : (dark ? Tokens.role.island.accent : Tokens.role.light.accent)
    // Ink on top of the accent: dark on a light accent, white on a dark one.
    readonly property color onAccent: (0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b) > 0.5 ? Tokens.role.dark.textOnAccent : "#ffffff"
    property real accentTint: 0                       // the island sets 0.07; the toasts and the dock keep the plain glass

    // With a colour chosen the glass is *tinted by it*: a muted, dark body in the colour's hue with
    // light ink, the colour itself only in the active objects. Two settings, picked by the backdrop:
    // `dark` (the desktop under it is dark) gives a calm, dense body; otherwise (bright desktop) a
    // lighter, more see-through mint-like body. Without a chosen colour the old neutral glass stays.
    readonly property bool tinted: accentOverride.a > 0
    readonly property real hue: Math.max(0, accentOverride.hslHue)

    readonly property color text: tinted ? (dark ? Qt.hsla(hue, 0.17, 0.93, 1) : Qt.hsla(hue, 0.55, 0.97, 1))
                                        : dark ? Tokens.role.island.text : Qt.alpha(Tokens.role.light.text, 0.82)
    readonly property color subtext: tinted ? (dark ? Qt.hsla(hue, 0.12, 0.78, 0.85) : Qt.hsla(hue, 0.40, 0.88, 0.85))
                                            : dark ? Tokens.role.island.textMuted : Qt.alpha(Tokens.role.light.textMuted, 0.74)
    readonly property color chip: tinted ? (dark ? Qt.hsla(hue, 0.18, 0.67, 0.13) : Qt.hsla(hue, 0.62, 0.80, 0.18))
                                         : dark ? Tokens.role.island.chip : Qt.rgba(0, 0, 0, 0.07)
    readonly property color bodyTop: tinted ? (dark ? Qt.hsla(hue, 0.11, 0.25, 0.34) : Qt.hsla(hue, 0.25, 0.30, 0.30))
                                            : dark ? Qt.alpha(Qt.tint(Tokens.role.island.bodyTop, Qt.alpha(accent, accentTint)), bodyAlpha)
                                                   : Qt.rgba(0.95, 0.96, 0.99, bodyAlpha)
    readonly property color bodyBottom: tinted ? (dark ? Qt.hsla(hue, 0.11, 0.21, 0.34) : Qt.hsla(hue, 0.25, 0.26, 0.26))
                                               : dark ? Qt.alpha(Qt.tint(Tokens.role.island.bodyBottom, Qt.alpha(accent, accentTint * 1.4)), bodyAlpha)
                                                      : Qt.rgba(0.90, 0.92, 0.97, bodyAlpha * 0.8)
    readonly property color rim: tinted ? (dark ? Qt.hsla(hue, 0.18, 0.67, 0.26) : Qt.hsla(hue, 0.62, 0.80, 0.34))
                                        : dark ? Qt.rgba(1, 1, 1, Tokens.material.rimAlpha)
                                               : Qt.rgba(0.42, 0.48, 0.60, 0.28)   // cool grey hairline: shows on white and on dark
    // A translucent wash for hovers, chips and hairlines on the glass.
    function veil(a) {
        if (tinted) return dark ? Qt.hsla(hue, 0.22, 0.85, a) : Qt.hsla(hue, 0.60, 0.90, a)
        return dark ? Qt.rgba(1, 1, 1, a) : Qt.rgba(0.10, 0.12, 0.17, a)
    }
    // Solid-looking objects on the glass (active tiles, the play button, slider and progress fills):
    // one family, equally see-through. Tinted: the colour itself (pale mint on a bright desktop).
    readonly property color objectFill: tinted ? (dark ? Qt.alpha(accent, 0.78) : Qt.hsla(hue, 0.60, 0.82, 0.80))
                                               : dark ? Qt.rgba(1, 1, 1, 0.90) : Qt.rgba(0.04, 0.07, 0.06, 0.56)
    readonly property color objectFillHover: tinted ? (dark ? Qt.alpha(accent, 0.86) : Qt.hsla(hue, 0.60, 0.86, 0.88))
                                                    : dark ? Qt.rgba(1, 1, 1, 0.96) : Qt.rgba(0.04, 0.07, 0.06, 0.64)
    readonly property color objectFillPressed: tinted ? (dark ? Qt.alpha(accent, 0.68) : Qt.hsla(hue, 0.60, 0.78, 0.70))
                                                      : dark ? Qt.rgba(1, 1, 1, 0.80) : Qt.rgba(0.04, 0.07, 0.06, 0.50)
    readonly property color objectInk: tinted ? Qt.hsla(hue, 0.55, 0.10, 1) : (dark ? Tokens.role.dark.textOnAccent : "#ffffff")
    readonly property color accentFill: dark || tinted ? accent : Qt.alpha(accent, 0.72)
    readonly property color bevel: Qt.rgba(0, 0, 0, Tokens.material.bevelAlpha)
    readonly property url grain: Qt.resolvedUrl("assets/grain.png")
    readonly property string font: Tokens.font.family
    readonly property string mono: Tokens.font.mono
}
