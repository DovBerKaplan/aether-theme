import QtQuick
import AetherShared

// Five-bar equalizer on a common baseline. While music plays the bars follow the real
// loudness of five frequency bands (AudioLevels: ~20 updates/s, no capture when idle), so
// they move with the beat. If the audio tap is unavailable they fall back to a slow travelling
// ripple. Pausing eases everything down to a row of dots; resuming eases it back up.
Item {
    id: root
    property bool active: false
    property color barColor: Theme.accent
    property int barWidth: 3
    property int minHeight: 3
    property int maxHeight: 12

    readonly property int count: 5
    readonly property real gap: Math.max(2, barWidth - 1)
    // How far the wave is raised (0 = resting dots, 1 = full); eased, never snapped.
    property real level: active ? 1 : 0
    Behavior on level { NumberAnimation { duration: Tokens.motion.duration.slow; easing.type: Tokens.motion.easing.enter } }

    // Real audio when the tap delivers samples (context property set by the island; absent in tests).
    readonly property var audio: typeof audioLevels !== "undefined" ? audioLevels : null
    readonly property bool live: audio !== null && audio.available
    property bool holding: false
    onActiveChanged: {
        if (!audio || active === holding) return
        holding = active
        if (active) audio.acquire(); else audio.release()
    }
    Component.onCompleted: if (active && audio) { holding = true; audio.acquire() }
    Component.onDestruction: if (holding && audio) audio.release()

    // Fallback wave position, 0..2π (whole-number multiples of it, so the loop has no seam).
    property real phase: 0
    NumberAnimation on phase {
        running: !root.live && (root.active || root.level > 0.001)
        from: 0; to: 2 * Math.PI
        duration: Tokens.motion.duration.ambient * 3
        loops: Animation.Infinite
    }

    width: count * barWidth + (count - 1) * gap
    height: maxHeight

    readonly property var envelope: [0.55, 0.82, 1.0, 0.82, 0.55]

    Repeater {
        model: root.count
        Rectangle {
            required property int index
            // A ripple travelling across the bars (neighbours stay correlated), plus a faster
            // swell on top so it never looks like a loop.
            readonly property real wave: 0.65 * Math.sin(root.phase * 2 - index * 0.8)
                                       + 0.35 * Math.sin(root.phase * 3 + index * 0.5)
            readonly property real lift: (root.live ? root.audio.bands[index]
                                                    : root.envelope[index] * (0.5 + 0.5 * wave)) * root.level

            x: index * (root.barWidth + root.gap)
            width: root.barWidth
            height: root.minHeight + (root.maxHeight - root.minHeight) * lift
            anchors.bottom: parent.bottom
            radius: width / 2
            color: root.barColor
            opacity: 0.55 + 0.45 * root.envelope[index]
        }
    }
}
