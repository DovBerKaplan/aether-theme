import QtQuick
import AetherShared

// Translate-screen mode: each recognised line is covered by a box in its own background colour
// carrying the translated text, so the screen reads as if it had been printed in the other language.
Item {
    id: root
    property var lines: []
    property bool busy: false
    Repeater {
        model: root.lines
        Rectangle {
            required property var modelData
            x: modelData.x - 3; y: modelData.y - 2
            width: modelData.w + 6; height: modelData.h + 4
            radius: 4
            color: modelData.bg
            visible: modelData.text !== ""
            Text {
                anchors.fill: parent; anchors.margins: 2
                text: modelData.text
                color: modelData.fg
                font.family: Theme.font
                font.pixelSize: Math.max(9, Math.round(modelData.fs))   // the original line height, shrunk to fit
                fontSizeMode: Text.Fit
                minimumPixelSize: 8
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
                // keep the side the original was set against
                horizontalAlignment: modelData.rtl ? Text.AlignRight : Text.AlignLeft
            }
        }
    }
}
