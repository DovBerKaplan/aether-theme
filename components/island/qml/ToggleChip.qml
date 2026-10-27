import QtQuick
import AetherShared

// Two-zone tile, like an Android Quick Settings tile: the icon circle toggles, the label
// area opens the detail panel (when `hasPanel`). Only the icon turns accent when on.
Item {
    id: root
    property string glyph
    property string label
    property string sublabel
    property bool active: false
    property bool hasPanel: false
    signal tapped()
    signal panelRequested()

    height: 58
    Rectangle {
        anchors.fill: parent
        radius: Tokens.radius.xl
        color: Theme.chip
        Rectangle {
            anchors.fill: parent; radius: parent.radius
            color: Qt.rgba(1, 1, 1, labelTap.pressed ? Tokens.material.tintAttention
                                  : labelHover.hovered && root.hasPanel ? Tokens.material.tintHover
                                  : root.active ? Tokens.tint.faint : 0)
            Behavior on color { ColorAnimation { duration: Tokens.motion.duration.micro } }
        }
    }
    Item {
        id: iconZone
        x: 6; width: 36; height: parent.height
        Rectangle {
            id: circle
            anchors.centerIn: parent
            width: 30; height: 30; radius: 15
            color: root.active ? Theme.accent : Qt.rgba(1, 1, 1, iconTap.pressed ? Tokens.tint.strong : iconHover.hovered ? Tokens.tint.soft : Tokens.tint.subtle)
            scale: iconTap.pressed ? 0.92 : 1
            Behavior on color { ColorAnimation { duration: Tokens.motion.duration.base } }
            Behavior on scale { NumberAnimation { duration: Tokens.motion.duration.micro } }
        }
        Glyph {
            anchors.centerIn: parent
            name: root.glyph; size: 16
            color: root.active ? Tokens.role.dark.textOnAccent : Theme.text
        }
        HoverHandler { id: iconHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: iconTap; gesturePolicy: TapHandler.WithinBounds; onTapped: root.tapped() }
    }
    Item {
        id: labelZone
        anchors { left: iconZone.right; right: parent.right; top: parent.top; bottom: parent.bottom }
        Column {
            anchors { left: parent.left; right: parent.right; rightMargin: Tokens.space.xs; verticalCenter: parent.verticalCenter }
            Text {
                width: parent.width; text: root.label; textFormat: Text.PlainText; elide: Text.ElideRight
                font { family: Theme.font; pixelSize: Tokens.type.label; weight: Font.Medium }
                color: Theme.text
            }
            Text {
                visible: root.sublabel.length > 0
                width: parent.width; text: root.sublabel; textFormat: Text.PlainText; elide: Text.ElideRight
                font { family: Theme.font; pixelSize: Tokens.type.caption }
                color: Theme.subtext
            }
        }
        Text {
            id: chevron
            visible: root.hasPanel
            opacity: labelHover.hovered ? 1 : 0
            rightPadding: Tokens.space.sm
            Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.fast } }
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: "›"
            font { family: Theme.font; pixelSize: Tokens.type.title }
            color: Theme.subtext
        }
        HoverHandler { id: labelHover; cursorShape: Qt.PointingHandCursor }
        // Long-press anywhere on the chip also opens the panel; a plain tap on a chip
        // without one falls back to toggling.
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
