// Aether Dune: the desktop wallpaper. Everything is drawn at the screen's own size - the ridgelines
// by a fragment shader, the mark from its SVG path (Mark.qml) - so it stays sharp at any resolution, and it
// repaints in the island's accent and the current mode the moment either changes.
import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

WallpaperItem {
    id: root

    readonly property string mode: root.configuration.Mode || "auto"
    readonly property bool isDark: mode === "dark" ? true : mode === "light" ? false
        : Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.backgroundColor) === Kirigami.ColorUtils.Dark
    readonly property color accent: root.configuration.AccentColor ? root.configuration.AccentColor : Kirigami.Theme.highlightColor

    property color shownAccent: accent
    property real shownDark: isDark ? 1 : 0
    Behavior on shownAccent { ColorAnimation { duration: Kirigami.Units.veryLongDuration } }
    Behavior on shownDark { NumberAnimation { duration: Kirigami.Units.veryLongDuration; easing.type: Easing.InOutQuad } }
    onAccentChanged: root.accentColorChanged()

    // The slow roll: a few pixels a second at most, so 10 ticks a second already move it in
    // sub-pixel steps and keep the GPU mostly idle; the layer below means nothing else repaints, and
    // while windows cover the desktop the compositor stops asking for frames at all. Wrapped every
    // ~28 h so the shader's floats stay precise.
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
            fragmentShader: Qt.resolvedUrl("../shaders/dune.frag.qsb")
            property color accent: root.shownAccent
            property real dark: root.shownDark
            property real aspect: width / Math.max(1, height)
            property real px: 1 / Math.max(1, height)
            property real time: root.time
        }

        // The mark: the distribution's logo, a chosen one, an imported image or nothing (Mark.qml).
        Mark {
            width: Math.round(root.height * 0.15); height: width
            anchors.centerIn: parent
            spec: root.configuration.Mark || ""
            distro: root.configuration.Distro || ""
            accent: root.shownAccent
            dark: root.shownDark
            time: root.time
        }
    }
}
