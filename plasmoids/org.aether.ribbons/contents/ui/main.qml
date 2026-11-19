// Aether Ribbons: the desktop wallpaper. Everything is drawn at the screen's own size - the bands by a
// fragment shader, the mark from its SVG path - so it stays sharp at any resolution, and it repaints
// in the island's accent and the current mode the moment either changes.
import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

import "logos.js" as Logos

WallpaperItem {
    id: root

    readonly property string mode: root.configuration.Mode || "auto"
    readonly property bool isDark: mode === "dark" ? true : mode === "light" ? false
        : Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.backgroundColor) === Kirigami.ColorUtils.Dark
    // The distribution's logo in the centre (logos.js), else the Aether mark.
    readonly property string logo: Logos.pathFor(root.configuration.Distro)
    readonly property color accent: root.configuration.AccentColor ? root.configuration.AccentColor : Kirigami.Theme.highlightColor

    property color shownAccent: accent
    property real shownDark: isDark ? 1 : 0
    Behavior on shownAccent { ColorAnimation { duration: Kirigami.Units.veryLongDuration } }
    Behavior on shownDark { NumberAnimation { duration: Kirigami.Units.veryLongDuration; easing.type: Easing.InOutQuad } }
    onAccentChanged: root.accentColorChanged()

    // The slow sway: a few pixels a second at most, so 10 ticks a second already move it in sub-pixel
    // steps and keep the GPU mostly idle; the layer below means nothing else repaints, and while windows
    // cover the desktop the compositor stops asking for frames at all. Wrapped every ~28 h so the
    // shader's floats stay precise.
    readonly property bool animate: root.configuration.Animate !== false
    property real time: 0
    property real startedAt: Date.now()
    Timer {
        interval: 100
        repeat: true
        running: root.animate && root.visible
        onTriggered: root.time = ((Date.now() - root.startedAt) / 1000) % 100000
    }

    // Cached in a layer: plasmashell redraws the desktop window often, the wallpaper only when it changes.
    Item {
        anchors.fill: parent
        layer.enabled: true

        ShaderEffect {
            anchors.fill: parent
            fragmentShader: Qt.resolvedUrl("../shaders/ribbons.frag.qsb")
            property color accent: root.shownAccent
            property real dark: root.shownDark
            property real aspect: width / Math.max(1, height)
            property real px: 1 / Math.max(1, height)
            property real time: root.time
        }

        // The mark: the distribution's logo (24 units), or the crescent and spark of
        // components/island/qml/assets/glyphs/logo.svg (16 units). It breathes with the field,
        // riding the same 10 Hz tick, so nothing repaints faster than the shader.
        Item {
            id: mark
            readonly property real side: Math.round(root.height * 0.15)
            readonly property real units: root.logo ? 24 : 16
            width: side; height: side
            anchors.centerIn: parent
            opacity: (root.shownDark > 0.5 ? 1 : 0.85) * (0.92 + 0.08 * Math.sin(root.time * 0.5))
            scale: 1 + 0.018 * Math.sin(root.time * 0.45 + 1.3)

            Shape {
                width: mark.units; height: mark.units
                scale: mark.side / mark.units
                transformOrigin: Item.TopLeft
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: -1
                    fillRule: ShapePath.WindingFill
                    fillColor: root.shownDark > 0.5 ? root.shownAccent : Qt.darker(root.shownAccent, 1.3)
                    PathSvg { path: root.logo || "M7.2 1.5a6.5 6.5 0 1 0 7.3 7.9A5.2 5.2 0 0 1 7.2 1.5zM12 1.2l.55 1.65L14.2 3.4l-1.65.55L12 5.6l-.55-1.65L9.8 3.4l1.65-.55z" }
                }
            }
        }
    }
}
