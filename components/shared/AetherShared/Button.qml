import QtQuick
import AetherShared

// Pill button. kind: "filled" (accent, once per screen), "tonal", "text", "negative".
Item {
    id: root
    property string text
    property string kind: "tonal"
    signal clicked()

    implicitWidth: label.implicitWidth + 2 * Tokens.space.lg
    implicitHeight: 36
    activeFocusOnTab: true
    opacity: enabled ? 1 : 0.4
    scale: tap.pressed ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: Tokens.motion.duration.micro } }
    Keys.onReturnPressed: clicked()
    Keys.onSpacePressed: clicked()

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.kind === "filled" ? Theme.accent : root.kind === "tonal" ? Theme.chip : "transparent"
        border { width: root.activeFocus ? 2 : 0; color: Theme.accent }
        Rectangle {
            anchors.fill: parent; radius: parent.radius
            color: Qt.rgba(1, 1, 1, tap.pressed ? Tokens.material.tintAttention : hover.hovered ? Tokens.material.tintHover : 0)
            Behavior on color { ColorAnimation { duration: Tokens.motion.duration.micro } }
        }
    }
    Text {
        id: label
        anchors.centerIn: parent
        text: root.text; textFormat: Text.PlainText
        font { family: Theme.font; pixelSize: Tokens.type.label; weight: Font.DemiBold }
        color: root.kind === "filled" ? Tokens.role.dark.textOnAccent
             : root.kind === "negative" ? Tokens.role.island.negative : Theme.text
    }
    HoverHandler { id: hover; enabled: root.enabled; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: tap; enabled: root.enabled; onTapped: root.clicked() }
}
