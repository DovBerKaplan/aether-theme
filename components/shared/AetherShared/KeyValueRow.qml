import QtQuick
import AetherShared

// Detail line: quiet key, mono value. Click copies the value.
Item {
    id: root
    property string key
    property string value
    property bool copyable: true

    implicitWidth: 360
    implicitHeight: 36

    TextEdit { id: clip; visible: false }
    Timer { id: copied; interval: 1200 }

    Rectangle {
        anchors.fill: parent; radius: Tokens.radius.sm
        color: Qt.rgba(1, 1, 1, root.copyable && hover.hovered ? Tokens.material.tintHover : 0)
    }
    Text {
        id: k
        anchors { left: parent.left; leftMargin: Tokens.space.md; verticalCenter: parent.verticalCenter }
        text: root.key; textFormat: Text.PlainText
        font { family: Theme.font; pixelSize: Tokens.type.label }
        color: Theme.subtext
    }
    Text {
        anchors {
            left: k.right; leftMargin: Tokens.space.md
            right: parent.right; rightMargin: Tokens.space.md
            verticalCenter: parent.verticalCenter
        }
        horizontalAlignment: Text.AlignRight
        text: copied.running ? I18n.tr("Copied") : root.value; textFormat: Text.PlainText
        elide: Text.ElideMiddle
        font { family: Theme.mono; pixelSize: Tokens.type.label }
        color: copied.running ? Theme.accent : Theme.text
    }
    HoverHandler { id: hover; enabled: root.copyable; cursorShape: Qt.PointingHandCursor }
    TapHandler {
        enabled: root.copyable
        onTapped: { clip.text = root.value; clip.selectAll(); clip.copy(); copied.restart() }
    }
}
