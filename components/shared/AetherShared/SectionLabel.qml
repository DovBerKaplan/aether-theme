import QtQuick
import AetherShared

// Group heading inside a panel: small, quiet, sentence case.
Item {
    id: root
    property alias text: label.text
    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight + Tokens.space.sm
    Text {
        id: label
        width: parent.width
        textFormat: Text.PlainText
        elide: Text.ElideRight
        font { family: Theme.font; pixelSize: Tokens.type.caption; weight: Font.Medium; letterSpacing: 0.4 }
        color: Theme.subtext
    }
}
