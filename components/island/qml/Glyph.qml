import QtQuick
import AetherShared
import QtQuick.Effects

// Monochrome glyph from assets/glyphs, tinted at runtime.
Item {
    id: root
    property string name
    property color color: Theme.text
    property int size: 16
    property real stroke: 2.5             // the line weight in screen pixels - the same for every glyph at every size
    implicitWidth: size
    implicitHeight: size
    width: size
    height: size

    Image {
        id: img
        anchors.fill: parent
        source: root.name ? glyphs.file(Qt.resolvedUrl("assets/glyphs/" + root.name + ".svg"), root.size, root.stroke) : ""
        sourceSize: Qt.size(root.size * 3, root.size * 3)
        visible: false
    }
    MultiEffect {
        anchors.fill: img
        source: img
        colorization: 1.0
        colorizationColor: root.color
    }
}
