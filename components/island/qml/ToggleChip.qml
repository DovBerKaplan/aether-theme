import QtQuick
import AetherShared

// Round toggle: filled with the accent colour when on, graphite when off.
Item {
    id: root
    property string glyph
    property string label
    property bool active: false
    signal tapped()

    height: 58
    Rectangle {
        anchors.fill: parent
        radius: 20
        color: root.active ? Theme.accent : Theme.chip
        opacity: tap.pressed ? 0.75 : 1
        Behavior on color { ColorAnimation { duration: 160 } }
        Behavior on opacity { NumberAnimation { duration: 80 } }
    }
    Column {
        anchors.centerIn: parent
        spacing: 4
        Glyph {
            anchors.horizontalCenter: parent.horizontalCenter
            name: root.glyph
            size: 18
            color: root.active ? "#00373a" : Theme.text
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.width - 14
            horizontalAlignment: Text.AlignHCenter
            text: root.label
            elide: Text.ElideRight
            font { family: Theme.font; pixelSize: 11; weight: Font.Medium }
            color: root.active ? "#00373a" : Theme.subtext
        }
    }
    TapHandler { id: tap; onTapped: root.tapped() }
}
