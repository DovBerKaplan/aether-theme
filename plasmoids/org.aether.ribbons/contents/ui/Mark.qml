// The mark at the centre of every aether wallpaper. One source, here in the ribbons; install.sh copies
// it (and logos.js) into the other fields' packages. What it shows follows the `Mark` key, which the
// island's wallpaper panel writes:
//   ""            the distribution's logo (logos.js, from `Distro`), else the Aether mark
//   "none"        nothing - the field alone
//   "aether"      the crescent and spark of components/island/qml/assets/glyphs/logo.svg
//   "logo:<slug>" one logo from logos.js, whatever the distribution
//   "file:<path>" an image the user imported (the island keeps a copy under ~/.local/share/aether/marks)
// It breathes with the field, riding the wallpaper's own 10 Hz tick, so nothing repaints faster.
import QtQuick
import QtQuick.Shapes

import "logos.js" as Logos

Item {
    id: mark
    property string spec: ""
    property string distro: ""
    property color accent: "white"
    property real dark: 1
    property real time: 0

    readonly property string crescent: "M7.2 1.5a6.5 6.5 0 1 0 7.3 7.9A5.2 5.2 0 0 1 7.2 1.5zM12 1.2l.55 1.65L14.2 3.4l-1.65.55L12 5.6l-.55-1.65L9.8 3.4l1.65-.55z"
    readonly property string file: spec.indexOf("file:") === 0 ? spec.slice(5) : ""
    readonly property string path: spec === "none" || file ? ""
        : spec === "aether" ? crescent
        : spec.indexOf("logo:") === 0 ? (Logos.paths[spec.slice(5)] || crescent)
        : (Logos.pathFor(distro) || crescent)
    readonly property real units: path === crescent ? 16 : 24

    visible: spec !== "none"
    opacity: (dark > 0.5 ? 1 : 0.85) * (0.92 + 0.08 * Math.sin(time * 0.5))
    scale: 1 + 0.018 * Math.sin(time * 0.45 + 1.3)

    Shape {
        visible: mark.path !== ""
        width: mark.units; height: mark.units
        scale: mark.width / mark.units
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillRule: ShapePath.WindingFill
            fillColor: mark.dark > 0.5 ? mark.accent : Qt.darker(mark.accent, 1.3)
            PathSvg { path: mark.path }
        }
    }
    Image {
        visible: mark.file !== ""
        anchors.fill: parent
        source: mark.file ? "file://" + mark.file : ""
        sourceSize { width: Math.round(mark.width * 2); height: Math.round(mark.height * 2) }
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        asynchronous: true
    }
}
