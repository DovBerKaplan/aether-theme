// Aether: Folder View's desktop label, inked for the wallpaper under it. Plasma draws these white
// with a black shadow on any wallpaper; this one turns black (with a white halo) where the
// wallpaper is bright. Installed into a local copy of org.kde.desktopcontainment, where
// FolderItemDelegate uses it in place of PlasmaExtras.ShadowedLabel.
//
// The cost stays near nothing: the wallpaper under the label is rendered by the GPU into a 4x2
// texture (eight fragments of the wallpaper's own shader), refreshed every couple of seconds rather
// than every frame, and nothing comes back to the CPU - the ink is picked in the label's shader.
// Windows over the desktop do not count, because the wallpaper item is read, not the screen.
import QtQuick
import org.kde.plasma.extras as PlasmaExtras

PlasmaExtras.ShadowedLabel {
    id: label

    // Plasma's WallpaperItem: a child of the ContainmentItem, which the label sits inside (the
    // containment does not hand it out as a property). Looked for again whenever it is gone - a
    // wallpaper switch makes a new one.
    property Item wallpaper: null
    function findWallpaper() {
        for (let p = parent; p; p = p.parent) {
            for (const c of p.children) {
                if (String(c).startsWith("WallpaperItem")) {
                    return c;
                }
            }
        }
        return null;
    }

    function refresh() {
        if (!wallpaper) {
            wallpaper = findWallpaper();
        }
        if (!wallpaper || width <= 0 || height <= 0) {
            return;
        }
        sample.sourceRect = label.mapToItem(wallpaper, 0, 0, width, height);
        sample.scheduleUpdate();
        sample.seen = true;
    }

    ShaderEffectSource {
        id: sample
        property bool seen: false
        sourceItem: label.renderShadow ? label.wallpaper : null
        textureSize: Qt.size(4, 2)
        live: false
        hideSource: false
        smooth: true
        visible: false
    }
    Timer {
        // The wallpapers drift by a few pixels a second, so a slow refresh follows them.
        interval: 2000
        repeat: true
        triggeredOnStart: true
        running: label.renderShadow && label.visible
        onTriggered: label.refresh()
    }
    // The grid places its delegates after they are made, and moves them without telling the label:
    // a first aim once the icon has landed, then the slow refresh re-aims as it goes.
    Component.onCompleted: refreshSoon.restart()
    onWidthChanged: refreshSoon.restart()
    onHeightChanged: refreshSoon.restart()
    Timer {
        id: refreshSoon   // an icon moved or the grid changed: re-aim the sample once it settles
        interval: 250
        onTriggered: if (label.renderShadow) label.refresh()
    }

    layer.effect: ShaderEffect {
        readonly property Item backdrop: sample
        readonly property size texel: Qt.size(1 / Math.max(1, width), 1 / Math.max(1, height))
        readonly property real seen: sample.seen && label.wallpaper ? 1 : 0
        fragmentShader: Qt.resolvedUrl("ink.frag.qsb")
    }
}
