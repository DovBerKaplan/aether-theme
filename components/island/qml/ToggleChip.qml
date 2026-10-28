import QtQuick
import AetherShared

// A quick-settings tile: a rounded square "pebble" of one, two or three cells. One cell is the icon with its
// name under it; two and three are the icon with name and state beside it. Off is quiet glass; on is the whole
// pebble pale with dark ink - the accent never fills anything. A one-cell tile toggles on a tap and opens its
// panel on a long press or right click; a wider one toggles from its icon and opens the panel from its text.
Item {
    id: root
    property string glyph
    property string label
    property string sublabel
    property bool active: false
    property bool hasPanel: false
    property int size: 1                      // cells wide: 1, 2 or 3
    signal tapped()
    signal panelRequested()

    readonly property bool small: size === 1
    readonly property color ink: Tokens.role.dark.textOnAccent
    readonly property int iconZone: 48        // a wide tile's icon area, the part that toggles

    Rectangle {
        id: body
        anchors.fill: parent
        radius: Math.round(Math.min(width, height) * 0.3)
        color: root.active ? Qt.rgba(1, 1, 1, bodyTap.pressed ? 0.80 : bodyHover.hovered ? 0.96 : 0.90)
                           : Qt.rgba(1, 1, 1, bodyTap.pressed ? Tokens.tint.strong : bodyHover.hovered ? Tokens.tint.soft : Tokens.tint.subtle)
        scale: bodyTap.pressed ? 0.97 : 1
        Behavior on color { ColorAnimation { duration: Tokens.motion.duration.base } }
        Behavior on scale { NumberAnimation { duration: Tokens.motion.duration.micro } }
    }
    Glyph {
        id: icon
        name: root.glyph; size: 24
        color: root.active ? root.ink : Theme.text
        x: root.small ? (root.width - width) / 2 : (I18n.rtl ? root.width - width - 14 : 14)
        y: root.small ? Math.round(root.height * 0.2) : (root.height - height) / 2
    }
    Text {      // one cell: the name under the icon
        visible: root.small
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 4; rightMargin: 4; bottomMargin: Math.round(root.height * 0.13) }
        text: root.label; textFormat: Text.PlainText; elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
        font { family: Theme.font; pixelSize: Tokens.type.caption; weight: Font.Medium }
        color: root.active ? root.ink : Theme.text
    }
    Column {    // two or three cells: name and state beside the icon
        visible: !root.small
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14 + 24 + 10; rightMargin: 12 }
        Text {
            width: parent.width; text: root.label; textFormat: Text.PlainText; elide: Text.ElideRight; horizontalAlignment: Text.AlignLeft
            font { family: Theme.font; pixelSize: Tokens.type.label; weight: Font.Medium }
            color: root.active ? root.ink : Theme.text
        }
        Text {
            visible: root.sublabel.length > 0
            width: parent.width; text: root.sublabel; textFormat: Text.PlainText; elide: Text.ElideRight; horizontalAlignment: Text.AlignLeft
            font { family: Theme.font; pixelSize: Tokens.type.caption }
            color: root.active ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.65) : Theme.subtext
        }
    }

    HoverHandler { id: bodyHover; cursorShape: Qt.PointingHandCursor }
    // The tap: everywhere on a one-cell tile; the icon zone of a wider one (its text zone is below).
    Item {
        id: tapZone
        x: root.small || !I18n.rtl ? 0 : root.width - width
        width: root.small ? root.width : root.iconZone; height: root.height
        TapHandler { id: bodyTap; gesturePolicy: TapHandler.WithinBounds; onTapped: root.tapped() }
    }
    Item {
        visible: !root.small
        x: I18n.rtl ? 0 : root.iconZone
        width: root.width - root.iconZone; height: root.height
        TapHandler { gesturePolicy: TapHandler.WithinBounds; onTapped: root.hasPanel ? root.panelRequested() : root.tapped() }
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: if (root.hasPanel) root.panelRequested()
    }
    TapHandler {
        enabled: root.hasPanel && root.small
        longPressThreshold: 0.4
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onLongPressed: root.panelRequested()
    }
}
