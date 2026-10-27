import QtQuick
import AetherShared
import "."

// KDE Connect panel, Overview (docs/WIDGETS-SPEC.md 3.2): which device, how it is doing, what you
// can do to it. Loud or irreversible actions (ring, unpair) arm on the first tap and act on the
// second, like the Power panel; nothing here runs on its own.
PanelScaffold {
    id: root
    property string page: ""
    signal pageRequested(string page)
    signal closeRequested()

    readonly property bool onNotifs: page === "notifications"
    readonly property bool onFiles: page === "files"
    readonly property var d: connectModel.selected
    readonly property bool has: d.id !== undefined
    readonly property bool online: has && d.reachable
    readonly property var paired: connectModel.devices.filter(x => x.paired)
    readonly property var strangers: connectModel.devices.filter(x => !x.paired)
    function glyphFor(type) { return type === "phone" ? "phone" : type === "tablet" ? "tablet" : "desktop" }
    function g(n) { return Qt.resolvedUrl("assets/glyphs/" + n + ".svg") }
    function linkName(link) { return link === "bluetooth" ? I18n.tr("Bluetooth") : I18n.tr("Wi‑Fi") }
    function on(key) { return has && d.pluginState !== undefined && d.pluginState[key] === true }
    readonly property var featureNames: ({
        kdeconnect_notifications: I18n.tr("Notifications"), kdeconnect_clipboard: I18n.tr("Clipboard"), kdeconnect_battery: I18n.tr("Battery"),
        kdeconnect_share: I18n.tr("Sharing"), kdeconnect_sftp: I18n.tr("Files"), kdeconnect_findmyphone: I18n.tr("Find my phone"),
        kdeconnect_ping: I18n.tr("Ping"), kdeconnect_sms: I18n.tr("Messages"), kdeconnect_mprisremote: I18n.tr("Phone media"),
        kdeconnect_telephony: I18n.tr("Calls"), kdeconnect_contacts: I18n.tr("Contacts"), kdeconnect_remotekeyboard: I18n.tr("Keyboard") })
    readonly property string feedback: {
        const a = connectModel.lastAction
        if (a.kind === undefined) return ""
        const n = a.device
        return a.kind === "files" ? I18n.f("Files sent to %1", n) : a.kind === "browse" ? I18n.f("Opening files on %1", n) : a.kind === "unmount" ? I18n.tr("Phone files disconnected")
             : a.kind === "ring" ? I18n.f("Ringing %1", n) : a.kind === "ping" ? I18n.f("Ping sent to %1", n)
             : a.kind === "clipboard" ? I18n.f("Clipboard sent to %1", n) : a.kind === "share" ? I18n.f("Sent to %1", n)
             : a.kind === "pairing" ? I18n.f("Pairing request sent to %1", n) : a.kind === "paired" ? I18n.f("Paired with %1", n)
             : a.kind === "reply" ? I18n.tr("Reply sent") : a.kind === "action" ? I18n.tr("Action sent") : a.kind === "dismiss-all" ? I18n.tr("Notifications cleared")
             : a.kind === "pairing-cancelled" ? I18n.tr("Pairing cancelled") : a.kind === "unpaired" ? I18n.f("Unpaired from %1", n) : ""
    }

    onOnFilesChanged: connectModel.watchFiles(onFiles)
    onOnNotifsChanged: connectModel.watchNotifications(onNotifs)
    Component.onCompleted: connectModel.watchNotifications(onNotifs)
    Component.onDestruction: { connectModel.watchNotifications(false); connectModel.watchFiles(false) }
    headerTrailing: [ Button { visible: root.onNotifs && connectModel.notifications.length > 0; kind: "text"; text: I18n.tr("Clear all"); onClicked: connectModel.clearNotifications(root.d.id) } ]

    title: onFiles ? I18n.tr("Files") : onNotifs ? I18n.tr("Notifications") : has ? d.name : I18n.tr("KDE Connect")
    subtitle: onNotifs || onFiles ? (has ? d.name : "") : !connectModel.available ? I18n.tr("KDE Connect isn't running")
            : !has ? I18n.tr("No paired device")
            : online ? I18n.f("Connected · %1", linkName(d.link)) : I18n.tr("Offline")
    footerHeight: 44
    footer: [
        Item {
            anchors.fill: parent
            Button { kind: "text"; text: I18n.tr("KDE Connect settings ↗"); anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                onClicked: { connectModel.openSettings(); root.closeRequested() } }
        }
    ]

    Column {      // ---- Notifications page --------------------------------------------------------
        visible: root.onNotifs
        x: 22; width: parent.width - 44
        spacing: Tokens.space.sm
        Repeater {
            model: root.onNotifs ? connectModel.notifications : []
            delegate: NotifRow { required property var modelData; n: modelData; deviceId: root.d.id; width: parent.width }
        }
        Item {
            visible: connectModel.notifications.length === 0
            width: parent.width; height: 150
            Column {
                anchors.centerIn: parent
                spacing: Tokens.space.md
                Glyph { anchors.horizontalCenter: parent.horizontalCenter; name: "bell"; size: 32; color: Theme.subtext }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: I18n.tr("No notifications")
                    font { family: Theme.font; pixelSize: Tokens.type.body }
                    color: Theme.subtext
                }
            }
        }
        Text {
            visible: root.feedback.length > 0
            width: parent.width; horizontalAlignment: Text.AlignLeft; wrapMode: Text.Wrap
            text: root.feedback; textFormat: Text.PlainText
            font { family: Theme.font; pixelSize: Tokens.type.label }
            color: Theme.subtext
        }
        Item { width: 1; height: Tokens.space.sm }
    }

    Column {      // ---- Files page ----------------------------------------------------------------
        visible: root.onFiles
        x: 22; width: parent.width - 44
        spacing: Tokens.space.sm
        Rectangle {      // drop zone
            width: parent.width; height: 96; radius: Tokens.radius.lg
            color: Qt.rgba(1, 1, 1, Tokens.tint.subtle)
            border { width: zone.dragging ? 2 : 1; color: zone.dragging ? Theme.accent : Theme.rim }
            Column {
                anchors.centerIn: parent
                spacing: Tokens.space.sm
                Glyph { anchors.horizontalCenter: parent.horizontalCenter; name: "send"; size: 22; color: Theme.subtext }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: I18n.tr("Drop files here to send them")
                    font { family: Theme.font; pixelSize: Tokens.type.label }
                    color: Theme.subtext
                }
            }
            DropTarget { id: zone; deviceId: root.online ? root.d.id : "" }
        }
        Button {
            visible: connectModel.canChooseFiles && root.online
            kind: "filled"; text: I18n.tr("Choose files…")
            onClicked: connectModel.chooseFiles(root.d.id)
        }
        ListRow {
            visible: root.online && root.on("kdeconnect_sftp")
            width: parent.width
            title: I18n.tr("Browse phone files")
            subtitle: connectModel.files.busy ? I18n.tr("Connecting…") : connectModel.files.mounted ? I18n.tr("Open in your file manager") : I18n.tr("Opens in your file manager")
            showChevron: !connectModel.files.mounted
            onClicked: connectModel.browseFiles(root.d.id)
            Button { visible: connectModel.files.mounted === true; kind: "text"; text: I18n.tr("Disconnect"); onClicked: connectModel.unmountFiles(root.d.id) }
        }
        SectionLabel { visible: connectModel.received.length > 0; width: parent.width; text: I18n.tr("Received") }
        Repeater {
            model: connectModel.received
            delegate: ListRow {
                required property var modelData
                width: parent.width
                leadingGlyphSource: root.g("folder")
                title: modelData.name
                subtitle: modelData.device
                onClicked: connectModel.openReceived(modelData.url)
                Item {
                    width: 32; height: 32
                    Rectangle {
                        anchors.fill: parent; radius: 16
                        color: Qt.rgba(1, 1, 1, shTap.pressed ? Tokens.tint.strong : shHover.hovered ? Tokens.tint.soft : Tokens.tint.subtle)
                    }
                    Glyph { anchors.centerIn: parent; name: "folder"; size: 15 }
                    HoverHandler { id: shHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: shTap; onTapped: connectModel.showReceived(modelData.url) }
                }
            }
        }
        Text {
            visible: root.feedback.length > 0
            width: parent.width; horizontalAlignment: Text.AlignLeft; wrapMode: Text.Wrap
            text: root.feedback; textFormat: Text.PlainText
            font { family: Theme.font; pixelSize: Tokens.type.label }
            color: Theme.subtext
        }
        Item { width: 1; height: Tokens.space.sm }
    }

    Column {      // ---- Overview -------------------------------------------------------------------
        visible: !root.onNotifs && !root.onFiles
        x: 22; width: parent.width - 44
        spacing: Tokens.space.xs

        // which device (only when there is a choice)
        Flow {
            visible: root.paired.length > 1
            width: parent.width
            spacing: Tokens.space.sm
            Repeater {
                model: root.paired
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool cur: modelData.id === connectModel.selectedId
                    height: 34; width: row.width + 2 * Tokens.space.md; radius: height / 2
                    color: cur ? Theme.chip : Qt.rgba(1, 1, 1, chipTap.pressed ? Tokens.tint.strong : chipHover.hovered ? Tokens.tint.soft : Tokens.tint.subtle)
                    border { width: cur ? 1 : 0; color: Theme.rim }
                    opacity: modelData.reachable ? 1 : 0.6
                    Row {
                        id: row
                        anchors.centerIn: parent
                        spacing: Tokens.space.sm
                        Glyph { name: root.glyphFor(modelData.type); size: 14; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: modelData.name; textFormat: Text.PlainText
                            font { family: Theme.font; pixelSize: Tokens.type.label; weight: Font.Medium }
                            color: Theme.text; anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: chipTap; onTapped: connectModel.select(modelData.id) }
                }
            }
        }

        // hero: the selected device
        Rectangle {
            visible: root.has
            width: parent.width; height: 92
            radius: Tokens.radius.lg
            color: Qt.rgba(1, 1, 1, Tokens.tint.subtle)
            Rectangle {
                id: disc
                anchors { left: parent.left; leftMargin: Tokens.space.lg; verticalCenter: parent.verticalCenter }
                width: 52; height: 52; radius: 26
                color: Theme.chip
                Glyph { anchors.centerIn: parent; name: root.glyphFor(root.d.type || ""); size: 24 }
            }
            Column {
                anchors { left: disc.right; leftMargin: Tokens.space.md; right: ring.left; rightMargin: Tokens.space.md; verticalCenter: parent.verticalCenter }
                spacing: 2
                Text {
                    width: parent.width; text: root.d.name || ""; textFormat: Text.PlainText; elide: Text.ElideRight; horizontalAlignment: Text.AlignLeft
                    font { family: Theme.font; pixelSize: Tokens.type.body; weight: Font.DemiBold }
                    color: Theme.text
                }
                Row {
                    spacing: Tokens.space.sm
                    visible: root.online && root.d.network !== undefined && root.d.network.length > 0
                    Text {
                        text: root.d.network || ""; textFormat: Text.PlainText
                        font { family: Theme.mono; pixelSize: Tokens.type.label }
                        color: Theme.subtext
                    }
                    SignalBars { level: root.d.signal === undefined ? -1 : root.d.signal; anchors.verticalCenter: parent.verticalCenter }
                }
                Text {
                    width: parent.width; elide: Text.ElideRight; horizontalAlignment: Text.AlignLeft
                    visible: root.d.notifications !== undefined && root.d.notifications > 0
                    text: I18n.f("%1 notifications", root.d.notifications)
                    font { family: Theme.font; pixelSize: Tokens.type.label }
                    color: Theme.subtext
                }
            }
            DropTarget { deviceId: root.online && root.on("kdeconnect_share") ? root.d.id : "" }
            BatteryRing {
                id: ring
                visible: root.d.battery !== undefined && root.d.battery >= 0
                anchors { right: parent.right; rightMargin: Tokens.space.lg; verticalCenter: parent.verticalCenter }
                width: 56; height: 56; ringWidth: 4
                percent: root.d.battery === undefined ? -1 : root.d.battery
                charging: root.d.charging === true
            }
        }

        ListRow {      // files: send, receive, browse
            visible: root.online && (root.on("kdeconnect_share") || root.on("kdeconnect_sftp"))
            width: parent.width
            title: I18n.tr("Files")
            subtitle: I18n.tr("Send, receive and browse")
            showChevron: true
            onClicked: root.pageRequested("files")
        }
        ListRow {      // the phone's notifications
            visible: root.online && root.on("kdeconnect_notifications")
            width: parent.width
            title: I18n.tr("Notifications")
            subtitle: root.d.notifications > 0 ? I18n.f("%1 notifications", root.d.notifications) : I18n.tr("No notifications")
            showChevron: true
            onClicked: root.pageRequested("notifications")
        }

        // pairing: someone asked, or a device is waiting to be paired
        Repeater {
            model: root.strangers
            delegate: Rectangle {
                required property var modelData
                width: parent.width
                height: pairCol.height + 2 * Tokens.space.lg
                radius: Tokens.radius.lg
                color: Qt.rgba(1, 1, 1, Tokens.tint.subtle)
                Column {
                    id: pairCol
                    x: Tokens.space.lg; y: Tokens.space.lg
                    width: parent.width - 2 * Tokens.space.lg
                    spacing: Tokens.space.md
                    Text {
                        width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText; horizontalAlignment: Text.AlignLeft
                        text: modelData.pairRequestedByPeer ? I18n.f("%1 wants to pair. Confirm that it shows this key", modelData.name)
                            : modelData.pairRequested ? I18n.f("Waiting for %1 to accept", modelData.name)
                            : I18n.f("%1 can be paired", modelData.name)
                        font { family: Theme.font; pixelSize: Tokens.type.body }
                        color: Theme.text
                    }
                    Text {
                        visible: modelData.pairRequestedByPeer || modelData.pairRequested
                        text: modelData.verificationKey
                        font { family: Theme.mono; pixelSize: Tokens.type.heading; weight: Font.Medium }
                        color: Theme.text
                    }
                    Row {
                        spacing: Tokens.space.sm
                        Button { visible: modelData.pairRequestedByPeer; kind: "filled"; text: I18n.tr("Pair"); onClicked: connectModel.acceptPairing(modelData.id) }
                        Button { visible: !modelData.pairRequestedByPeer && !modelData.pairRequested; kind: "filled"; text: I18n.tr("Pair"); onClicked: connectModel.requestPairing(modelData.id) }
                        Button { visible: modelData.pairRequestedByPeer || modelData.pairRequested; kind: "text"; text: I18n.tr("Decline"); onClicked: connectModel.cancelPairing(modelData.id) }
                    }
                }
            }
        }

        // the things you can do
        Item { visible: root.online; width: 1; height: Tokens.space.sm }
        Row {
            visible: root.online
            spacing: Tokens.space.sm
            ConfirmTile {
                visible: root.on("kdeconnect_findmyphone")
                label: I18n.tr("Ring"); confirmLabel: I18n.tr("Tap to ring"); glyphSource: root.g("ring")
                onActivated: connectModel.ring(root.d.id)
            }
            ConfirmTile {
                visible: root.on("kdeconnect_ping")
                label: I18n.tr("Ping"); glyphSource: root.g("bell"); needsConfirm: false
                onActivated: connectModel.ping(root.d.id)
            }
            ConfirmTile {
                visible: root.on("kdeconnect_clipboard")
                label: I18n.tr("Clipboard"); glyphSource: root.g("send"); needsConfirm: false
                onActivated: connectModel.sendClipboard(root.d.id)
            }
        }
        Row {
            visible: root.online && root.on("kdeconnect_share")
            width: parent.width
            spacing: Tokens.space.sm
            TextField {
                id: shareField
                width: parent.width - sendBtn.width - Tokens.space.sm
                placeholder: I18n.tr("Send a link or text")
                onAccepted: sendBtn.clicked()
            }
            Button {
                id: sendBtn
                kind: "tonal"; text: I18n.tr("Send")
                anchors.verticalCenter: parent.verticalCenter
                enabled: shareField.text.trim().length > 0
                onClicked: {
                    const t = shareField.text.trim()
                    if (/^(https?|ftp):\/\/\S+$/i.test(t)) connectModel.shareUrl(root.d.id, t); else connectModel.shareText(root.d.id, t)
                    shareField.text = ""
                }
            }
        }
        Text {
            visible: root.feedback.length > 0
            width: parent.width; topPadding: Tokens.space.xs; horizontalAlignment: Text.AlignLeft; wrapMode: Text.Wrap
            text: root.feedback; textFormat: Text.PlainText
            font { family: Theme.font; pixelSize: Tokens.type.label }
            color: Theme.subtext
        }

        // what the daemon may do with this device
        SectionLabel { visible: root.has; width: parent.width; text: I18n.tr("Features") }
        Repeater {
            model: root.has ? connectModel.plugins(root.d.id).concat([]) : []
            delegate: ListRow {
                required property var modelData
                width: parent.width
                height: 48
                title: root.featureNames[modelData.key] || modelData.key
                Switch { checked: modelData.enabled; onToggled: (c) => connectModel.setPluginEnabled(root.d.id, modelData.key, c) }
            }
        }
        Item { visible: root.has; width: 1; height: Tokens.space.sm }
        Button {
            id: unpairBtn
            visible: root.has
            property bool armed: false
            kind: "negative"
            text: armed ? I18n.tr("Tap again to unpair") : I18n.tr("Unpair")
            onClicked: {
                if (!armed) { armed = true; disarm.restart(); return }
                armed = false
                connectModel.unpair(root.d.id)
            }
            Timer { id: disarm; interval: 4000; onTriggered: unpairBtn.armed = false }
        }
        Item { width: 1; height: Tokens.space.sm }
    }
}
