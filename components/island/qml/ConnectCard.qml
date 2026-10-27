import QtQuick
import AetherShared
import "."

// The KDE Connect widget in the large island's stack: one line about the selected device. Tapping it
// opens the Connect panel; the one quick action here (send the clipboard) is harmless and explicit.
// Loud things (ring) live in the panel behind a second tap. Message text never appears on the card.
Item {
    id: root
    signal openRequested(string target)      // "connect" or "connect:notifications"

    readonly property var d: connectModel.selected
    readonly property bool has: d.id !== undefined
    readonly property bool online: has && d.reachable
    readonly property var strangers: connectModel.devices.filter(x => !x.paired)
    readonly property int pairedCount: connectModel.devices.filter(x => x.paired).length
    function glyphFor(type) { return type === "phone" ? "phone" : type === "tablet" ? "tablet" : "desktop" }
    function linkName(link) { return link === "bluetooth" ? I18n.tr("Bluetooth") : I18n.tr("Wi‑Fi") }

    implicitHeight: 72
    opacity: has && !d.reachable ? 0.7 : 1
    Behavior on opacity { NumberAnimation { duration: Tokens.motion.duration.base } }

    Rectangle {      // card surface + hairline, like the media card
        anchors.fill: parent
        radius: Tokens.radius.xl
        color: Qt.rgba(1, 1, 1, tap.pressed ? Tokens.tint.subtle : hover.hovered ? Tokens.tint.faint * 1.6 : Tokens.tint.faint)
        border.color: Theme.rim
        Behavior on color { ColorAnimation { duration: Tokens.motion.duration.micro } }
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: tap; onTapped: root.openRequested("connect") }

    // ---- a device is selected ------------------------------------------------------------
    Item {
        anchors.fill: parent
        visible: root.has
        Rectangle {
            id: disc
            anchors { left: parent.left; leftMargin: Tokens.space.md; verticalCenter: parent.verticalCenter }
            width: 44; height: 44; radius: 22
            color: Theme.chip
            Glyph { anchors.centerIn: parent; name: root.glyphFor(root.d.type || ""); size: 20 }
        }
        Column {
            anchors { left: disc.right; leftMargin: Tokens.space.md; right: meta.left; rightMargin: Tokens.space.sm; verticalCenter: parent.verticalCenter }
            spacing: 1
            Text {
                width: parent.width; text: root.d.name || ""; textFormat: Text.PlainText; elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft
                font { family: Theme.font; pixelSize: Tokens.type.body; weight: Font.DemiBold }
                color: Theme.text
            }
            Text {
                width: parent.width; textFormat: Text.PlainText; elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft
                text: root.d.pairRequestedByPeer ? I18n.tr("Pairing request")
                    : root.online ? I18n.f("Connected · %1", root.linkName(root.d.link)) : I18n.tr("Offline")
                font { family: Theme.font; pixelSize: Tokens.type.label }
                color: root.d.pairRequestedByPeer ? Theme.accent : Theme.subtext
            }
        }
        Row {
            id: meta
            anchors { right: parent.right; rightMargin: Tokens.space.md; verticalCenter: parent.verticalCenter }
            spacing: Tokens.space.sm
            Column {      // network type over signal bars
                visible: root.online && root.d.network !== undefined && root.d.network.length > 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.d.network || ""; textFormat: Text.PlainText
                    font { family: Theme.mono; pixelSize: Tokens.type.caption }
                    color: Theme.subtext
                }
                SignalBars { anchors.horizontalCenter: parent.horizontalCenter; level: root.d.signal === undefined ? -1 : root.d.signal }
            }
            Item {        // the phone's notifications: a bell with the count, opens the list
                visible: root.online && root.d.notifications !== undefined && root.d.notifications > 0
                width: 34; height: 34
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    anchors.fill: parent; radius: 17
                    color: Qt.rgba(1, 1, 1, bellTap.pressed ? Tokens.tint.strong : bellHover.hovered ? Tokens.tint.soft : Tokens.tint.subtle)
                    Behavior on color { ColorAnimation { duration: Tokens.motion.duration.micro } }
                }
                Glyph { anchors.centerIn: parent; name: "bell"; size: 15 }
                Rectangle {      // the count: small, quiet - no message text on the card
                    anchors { right: parent.right; top: parent.top; rightMargin: -3; topMargin: -3 }
                    width: Math.max(16, cnt.implicitWidth + 8); height: 16; radius: 8
                    color: Theme.text
                    Text {
                        id: cnt; anchors.centerIn: parent
                        text: root.d.notifications > 99 ? "99+" : root.d.notifications
                        font { family: Theme.mono; pixelSize: Tokens.type.caption; weight: Font.Medium }
                        color: Tokens.role.dark.textOnAccent
                    }
                }
                HoverHandler { id: bellHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { id: bellTap; onTapped: root.openRequested("connect:notifications") }
            }
            Item {        // send clipboard
                visible: root.online && root.d.pluginState !== undefined && root.d.pluginState["kdeconnect_clipboard"] === true
                width: 34; height: 34
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    anchors.fill: parent; radius: 17
                    color: Qt.rgba(1, 1, 1, sendTap.pressed ? Tokens.tint.strong : sendHover.hovered ? Tokens.tint.soft : Tokens.tint.subtle)
                    Behavior on color { ColorAnimation { duration: Tokens.motion.duration.micro } }
                }
                Glyph { anchors.centerIn: parent; name: "send"; size: 15 }
                HoverHandler { id: sendHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { id: sendTap; onTapped: connectModel.sendClipboard(root.d.id) }
            }
            BatteryRing {
                visible: root.d.battery !== undefined && root.d.battery >= 0
                anchors.verticalCenter: parent.verticalCenter
                width: 40; height: 40
                percent: root.d.battery === undefined ? -1 : root.d.battery
                charging: root.d.charging === true
            }
        }
        Row {          // which device: one dot each, tap to move on
            visible: root.pairedCount > 1
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 5 }
            spacing: 5
            Repeater {
                model: connectModel.devices.filter(x => x.paired)
                delegate: Rectangle {
                    required property var modelData
                    width: modelData.id === connectModel.selectedId ? 12 : 4; height: 4; radius: 2
                    color: Theme.text
                    opacity: modelData.id === connectModel.selectedId ? 0.8 : 0.3
                    Behavior on width { NumberAnimation { duration: Tokens.motion.duration.fast; easing.type: Tokens.motion.easing.enter } }
                }
            }
            TapHandler { onTapped: connectModel.selectNext() }
        }
    }

    // ---- nothing paired ------------------------------------------------------------------
    Item {
        anchors.fill: parent
        visible: !root.has
        Rectangle {
            id: emptyDisc
            anchors { left: parent.left; leftMargin: Tokens.space.md; verticalCenter: parent.verticalCenter }
            width: 44; height: 44; radius: 22
            color: Theme.chip
            Glyph { anchors.centerIn: parent; name: "phone"; size: 20; opacity: 0.7 }
        }
        Column {
            anchors { left: emptyDisc.right; leftMargin: Tokens.space.md; right: parent.right; rightMargin: Tokens.space.md; verticalCenter: parent.verticalCenter }
            spacing: 1
            Text {
                width: parent.width; elide: Text.ElideRight; horizontalAlignment: Text.AlignLeft
                text: root.strangers.length > 0 ? I18n.f("Pair with %1", root.strangers[0].name) : I18n.tr("Connect your phone")
                textFormat: Text.PlainText
                font { family: Theme.font; pixelSize: Tokens.type.body; weight: Font.DemiBold }
                color: Theme.text
            }
            Text {
                width: parent.width; elide: Text.ElideRight; horizontalAlignment: Text.AlignLeft
                text: !connectModel.available ? I18n.tr("KDE Connect isn't running") : I18n.tr("Open KDE Connect on your phone to pair it")
                font { family: Theme.font; pixelSize: Tokens.type.label }
                color: Theme.subtext
            }
        }
    }
}
