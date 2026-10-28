import QtQuick
import AetherShared

// A round quick-settings tile, like Android's: the circle toggles, the label under it opens the detail
// panel (when `hasPanel`; a plain tap on the label of a tile without one toggles). Off is a quiet glass
// disc; on is a pale disc with the glyph in the accent - the accent stays small.
Item {
    id: root
    property string glyph
    property string label
    property string sublabel
    property bool active: false
    property bool hasPanel: false
    property bool wide: false                // 2 cells: a pill with the text beside the disc, instead of a disc with the text under it
    signal tapped()
    signal panelRequested()

    readonly property int disc: wide ? 38 : 38
    height: 70
    Rectangle {      // the pill behind a wide tile
        visible: root.wide
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
        height: 52; radius: 26
        color: Theme.chip
    }
    Rectangle {
        id: circle
        x: root.wide ? (I18n.rtl ? root.width - width - 10 : 10) : (root.width - width) / 2
        y: root.wide ? (root.height - height) / 2 : 0
        width: root.disc; height: root.disc; radius: root.disc / 2
        color: root.active ? Qt.rgba(1, 1, 1, iconTap.pressed ? 0.82 : iconHover.hovered ? 0.98 : 0.92)
                           : Qt.rgba(1, 1, 1, iconTap.pressed ? Tokens.tint.strong : iconHover.hovered ? Tokens.tint.soft : Tokens.tint.subtle)
        scale: iconTap.pressed ? 0.94 : 1
        Behavior on color { ColorAnimation { duration: Tokens.motion.duration.base } }
        Behavior on scale { NumberAnimation { duration: Tokens.motion.duration.micro } }
        Glyph {
            anchors.centerIn: parent
            name: root.glyph; size: 22
            color: root.active ? Theme.accent : Theme.text
        }
        HoverHandler { id: iconHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: iconTap; gesturePolicy: TapHandler.WithinBounds; onTapped: root.tapped() }
    }
    Item {
        id: labelZone
        readonly property real inset: 10 + root.disc + 8      // a wide tile's text starts after the disc, so the disc keeps its own taps
        x: root.wide && !I18n.rtl ? inset : 0
        y: root.wide ? 0 : circle.height + 3
        width: root.wide ? root.width - inset : root.width
        height: root.wide ? root.height : root.height - y
        Column {
            anchors { left: parent.left; right: parent.right; rightMargin: root.wide ? 12 : 0; leftMargin: 0 }
            y: root.wide ? (labelZone.height - height) / 2 : 0
            Text {
                width: parent.width; text: root.label; textFormat: Text.PlainText; elide: Text.ElideRight; horizontalAlignment: root.wide ? Text.AlignLeft : Text.AlignHCenter
                font { family: Theme.font; pixelSize: Tokens.type.label; weight: Font.Medium }
                color: Theme.text
                opacity: labelHover.hovered && root.hasPanel ? 1 : 0.92
            }
            Text {
                visible: root.sublabel.length > 0
                width: parent.width; text: root.sublabel; textFormat: Text.PlainText; elide: Text.ElideRight; horizontalAlignment: root.wide ? Text.AlignLeft : Text.AlignHCenter
                font { family: Theme.font; pixelSize: Tokens.type.caption }
                color: Theme.subtext
            }
        }
        HoverHandler { id: labelHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            id: labelTap
            gesturePolicy: TapHandler.WithinBounds
            onTapped: root.hasPanel ? root.panelRequested() : root.tapped()
        }
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: if (root.hasPanel) root.panelRequested()
    }
    TapHandler {
        enabled: root.hasPanel
        longPressThreshold: 0.4
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onLongPressed: root.panelRequested()
    }
}
