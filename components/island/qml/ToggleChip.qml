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
    property var trail: ({})                  // a wider tile's far end: { kind: "chevron" | "signal" | "text" | "dot", level, text }
    signal tapped()
    signal panelRequested()

    readonly property bool small: size === 1
    readonly property color ink: Theme.objectInk
    readonly property int iconZone: 48        // a wide tile's icon area, the part that toggles

    Rectangle {
        id: body
        anchors.fill: parent
        radius: Math.round(Math.min(width, height) * 0.3)
        color: root.active ? (bodyTap.pressed ? Theme.objectFillPressed : bodyHover.hovered ? Theme.objectFillHover : Theme.objectFill)
                           : Theme.veil(bodyTap.pressed ? Tokens.tint.strong : bodyHover.hovered ? Tokens.tint.soft : Tokens.tint.subtle)
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
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 14 + 24 + 10; rightMargin: 12 + (trailing.visible ? trailing.width + 6 : 0) }
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

    Item {      // the far end of a wide tile: one quiet, glanceable detail, or a chevron that says "the text opens the panel"
        id: trailing
        readonly property string kind: root.trail.kind || ""
        visible: !root.small && kind.length > 0
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        width: kind === "signal" ? 20 : kind === "text" ? tText.implicitWidth : kind === "dot" ? 14 : 10
        height: 22
        readonly property color tone: root.active ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.7) : Theme.subtext
        Text {
            visible: trailing.kind === "chevron"
            anchors.centerIn: parent
            text: I18n.rtl ? "‹" : "›"
            font { family: Theme.font; pixelSize: Tokens.type.title }
            color: trailing.tone
        }
        SignalBars {
            visible: trailing.kind === "signal"
            level: root.trail.level === undefined ? -1 : root.trail.level
            color: root.active ? root.ink : Theme.text
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 3 }
        }
        Text {
            id: tText
            visible: trailing.kind === "text"
            anchors.centerIn: parent
            text: root.trail.text || ""; textFormat: Text.PlainText
            font { family: Theme.mono; pixelSize: Tokens.type.caption; weight: Font.Medium }
            color: trailing.tone
        }
        Rectangle {
            visible: trailing.kind === "dot"
            anchors.centerIn: parent
            width: root.trail.color !== undefined ? 14 : 8; height: width; radius: width / 2
            color: root.trail.color !== undefined ? root.trail.color : Tokens.role.island.negative
            border { width: root.trail.color !== undefined ? 1 : 0; color: Qt.rgba(1, 1, 1, 0.5) }
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
