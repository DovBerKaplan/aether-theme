import QtQuick
import AetherShared

// The round chevron that goes back one level - the same button in every panel header
// (PanelScaffold) and in the search bar. Points the other way in RTL.
Item {
    id: root
    signal activated()
    width: 40
    height: 40
    activeFocusOnTab: true
    Keys.onReturnPressed: root.activated()
    Keys.onSpacePressed: root.activated()
    Rectangle {
        anchors.fill: parent; radius: 20
        color: Qt.rgba(1, 1, 1, tap.pressed ? Tokens.material.tintAttention : hover.hovered ? Tokens.material.tintHover : 0)
        border { width: root.activeFocus ? 2 : 0; color: Theme.accent }
    }
    Text {
        anchors.centerIn: parent
        text: I18n.rtl ? "›" : "‹"
        font { family: Theme.font; pixelSize: Tokens.type.heading; weight: Font.Medium }
        color: Theme.text
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: tap; onTapped: root.activated() }
}
