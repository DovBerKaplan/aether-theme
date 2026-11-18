import QtQuick
import QtQuick.Controls
import AetherShared

// The bottom search pill: type to search the web, or send the whole screen to Lens.
Rectangle {
    id: root
    implicitHeight: 56
    radius: 28
    color: Qt.rgba(Theme.bodyTop.r, Theme.bodyTop.g, Theme.bodyTop.b, 0.88)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.12)

    LensGlyph {
        id: mark
        anchors.verticalCenter: parent.verticalCenter
        x: 20
        size: 22
    }
    TextInput {
        id: input
        anchors.verticalCenter: parent.verticalCenter
        x: 56
        width: parent.width - 56 - 64
        clip: true
        color: Theme.text
        selectionColor: Tokens.role.lens.selection
        font.family: Theme.font
        font.pixelSize: 16
        horizontalAlignment: lens.isRtlText(text) || (text === "" && I18n.rtl) ? Text.AlignRight : Text.AlignLeft
        onAccepted: { if (text.trim() !== "") lens.searchText(text) }
        Text {
            visible: input.text === "" && !input.activeFocus
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: I18n.rtl ? Text.AlignRight : Text.AlignLeft
            text: I18n.tr("Search what's on your screen")
            color: Theme.subtext
            font: input.font
        }
    }
    GlassButton {
        anchors.verticalCenter: parent.verticalCenter
        x: parent.width - width - 6
        width: 44; height: 44

        icon: "view-fullscreen"
        onClicked: lens.searchImage(true)
    }
}
