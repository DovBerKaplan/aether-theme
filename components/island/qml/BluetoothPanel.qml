import QtQuick
import AetherShared
import "."
import "BtIcons.js" as BtIcons

// Bluetooth panel (docs/PANELS-SPEC.md section 5): connected, saved and discoverable devices,
// inline pairing (confirm a code, type a PIN), and a detail page. Discovery and the pairing
// agent exist only while this panel does.
PanelScaffold {
    id: root
    property string page: ""
    signal pageRequested(string page)
    signal closeRequested()

    readonly property bool onDetail: page.indexOf("detail:") === 0
    readonly property string detailPath: onDetail ? page.substring(7) : ""
    readonly property var devs: bluetooth.devices
    readonly property var connected: devs.filter(d => d.paired && d.connected)
    readonly property var saved: devs.filter(d => d.paired && !d.connected)
    readonly property var nearby: devs.filter(d => !d.paired)
    readonly property var detailDev: devs.find(d => d.path === detailPath) || null
    onDetailDevChanged: if (onDetail && detailDev && renameField.text === "") renameField.text = detailDev.name
    property string errPath
    property string errText
    property int detailRssi: -1000   // raw dBm fetched by the timer below; -1000 = no answer yet
    onDetailPathChanged: detailRssi = -1000
    function rssiLevel(r) { return r > -55 ? 4 : r > -70 ? 3 : r > -85 ? 2 : 1 }
    // Raw RSSI for the detail page: the devices list only carries the quantized level, so this
    // asks the adapter again every few seconds while a connected device's page is open.
    Timer {
        running: root.onDetail && root.detailDev !== null && root.detailDev.connected
        interval: 3000
        repeat: true
        triggeredOnStart: true
        onTriggered: bluetooth.readRssi(root.detailPath)
    }

    title: onDetail ? (detailDev ? detailDev.name : I18n.tr("Device")) : I18n.tr("Bluetooth")
    subtitle: onDetail ? I18n.tr("Device details")
            : !bluetooth.available ? I18n.tr("No Bluetooth adapter")
            : !bluetooth.powered ? I18n.tr("Off")
            : connected.length > 0 ? I18n.f("%1 connected", connected[0].name + (connected.length > 1 ? " +" + (connected.length - 1) : ""))
            : I18n.f("Visible as “%1” while this panel is open", bluetooth.adapterName)
    busy: bluetooth.discovering || bluetooth.busy.length > 0
    headerTrailing: [ Switch { visible: !root.onDetail && bluetooth.available; checked: bluetooth.powered; onToggled: (c) => bluetooth.setPowered(c) } ]
    footerHeight: 44
    footer: [
        Item {
            anchors.fill: parent
            Button { kind: "text"; text: I18n.tr("Bluetooth settings ↗"); anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                onClicked: { bluetooth.openSettings(); root.closeRequested() } }
        }
    ]

    Component.onCompleted: bluetooth.setActive(true)
    Component.onDestruction: bluetooth.setActive(false)
    Connections {
        target: bluetooth
        function onOpFailed(path, text) { root.errPath = path; root.errText = text; errTimer.restart() }
        function onRssiRead(path, rssi) { if (path === root.detailPath) root.detailRssi = rssi }
    }
    Timer { id: errTimer; interval: 6000; onTriggered: root.errPath = "" }

    function stateOf(d) {
        if (errPath === d.path) return I18n.tr(errText)
        if (bluetooth.busy === d.path) return d.paired ? I18n.tr("Connecting…") : I18n.tr("Pairing…")
        if (tether.engaged && tether.routerAddress === d.address) return I18n.tr("Sharing internet")
        if (d.connected) return I18n.tr("Connected")
        return d.paired ? I18n.tr("Not connected") : I18n.tr("Tap to pair")
    }

    Item {   // list page
        width: parent.width
        height: visible ? listCol.implicitHeight : 0
        visible: !root.onDetail
        Column {
            id: listCol
            x: 22; width: parent.width - 44
            spacing: Tokens.space.xs

            Item {
                visible: !bluetooth.powered || !bluetooth.available
                width: parent.width; height: 150
                Column {
                    anchors.centerIn: parent
                    spacing: Tokens.space.md
                    Glyph { anchors.horizontalCenter: parent.horizontalCenter; name: "bluetooth-off"; size: 32; color: Theme.subtext }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: bluetooth.available ? I18n.tr("Bluetooth is off") : I18n.tr("No Bluetooth adapter found")
                        font { family: Theme.font; pixelSize: Tokens.type.body }
                        color: Theme.subtext
                    }
                    Button { visible: bluetooth.available; anchors.horizontalCenter: parent.horizontalCenter
                        kind: "filled"; text: I18n.tr("Turn on"); onClicked: bluetooth.setPowered(true) }
                }
            }

            // pairing in progress: one card that asks for exactly what the device wants
            Rectangle {
                id: pairCard
                readonly property var p: bluetooth.pairing
                readonly property string pname: p.name || ""
                readonly property string pkind: p.kind || ""
                readonly property string pcode: p.code || ""
                visible: bluetooth.powered && p.path !== undefined
                width: parent.width
                height: visible ? pairCol.height + 2 * Tokens.space.lg : 0
                radius: Tokens.radius.lg
                color: Theme.veil(Tokens.tint.subtle)
                Column {
                    id: pairCol
                    x: Tokens.space.lg; y: Tokens.space.lg
                    width: parent.width - 2 * Tokens.space.lg
                    spacing: Tokens.space.md
                    Text {
                        width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
                        text: pairCard.pkind === "confirm" ? I18n.f("Confirm that %1 shows this code", pairCard.pname)
                            : pairCard.pkind === "display" ? I18n.f("Type %1 on %2, then press Enter", pairCard.pcode, pairCard.pname)
                            : pairCard.pkind === "authorize" ? I18n.f("%1 wants to connect", pairCard.pname)
                            : I18n.f("Enter the code for %1", pairCard.pname)
                        font { family: Theme.font; pixelSize: Tokens.type.body }
                        color: Theme.text
                    }
                    Text {
                        visible: pairCard.pkind === "confirm"
                        text: pairCard.pcode
                        font { family: Theme.mono; pixelSize: Tokens.type.display; weight: Font.Medium }
                        color: Theme.text
                    }
                    TextField {
                        id: pinField
                        visible: pairCard.pkind === "pin" || pairCard.pkind === "passkey"
                        width: parent.width
                        placeholder: I18n.tr("Code")
                        onAccepted: if (text.length > 0) bluetooth.answerPin(text)
                    }
                    Row {
                        spacing: Tokens.space.sm
                        Button { visible: pairCard.pkind !== "display"; kind: "filled"
                            text: pairCard.pkind === "pin" || pairCard.pkind === "passkey" ? I18n.tr("Pair") : pairCard.pkind === "authorize" ? I18n.tr("Allow") : I18n.tr("Pair")
                            onClicked: pinField.visible ? bluetooth.answerPin(pinField.text) : bluetooth.answerConfirm(true) }
                        Button { kind: "text"; text: I18n.tr("Cancel"); onClicked: bluetooth.cancelPairing() }
                    }
                }
            }

            SectionLabel { visible: bluetooth.powered && root.connected.length > 0; width: parent.width; text: I18n.tr("Connected") }
            Repeater { model: bluetooth.powered ? root.connected : []; delegate: devRow }
            SectionLabel { visible: bluetooth.powered && root.saved.length > 0; width: parent.width; text: I18n.tr("Saved devices") }
            Repeater { model: bluetooth.powered ? root.saved : []; delegate: devRow }
            SectionLabel { visible: bluetooth.powered && root.nearby.length > 0; width: parent.width; text: I18n.tr("Pair new device") }
            Repeater { model: bluetooth.powered ? root.nearby : []; delegate: devRow }
            Text {
                visible: bluetooth.powered && root.nearby.length === 0 && bluetooth.discovering
                width: parent.width; height: 48
                verticalAlignment: Text.AlignVCenter
                text: I18n.tr("Looking for devices…")
                font { family: Theme.font; pixelSize: Tokens.type.label }
                color: Theme.subtext
            }
        }
    }
    Component {
        id: devRow
        ListRow {
            required property var modelData
            width: listCol.width
            title: modelData.name
            subtitle: root.stateOf(modelData)
            leadingGlyphSource: Qt.resolvedUrl("assets/glyphs/" + BtIcons.glyph(modelData.icon) + ".svg")
            enabled: bluetooth.busy.length === 0 || bluetooth.busy === modelData.path
            onClicked: modelData.paired ? bluetooth.toggleConnect(modelData.path) : bluetooth.pair(modelData.path)
            BatteryGlyph {      // the device's own battery, when it reports one
                visible: modelData.battery >= 0
                percent: modelData.battery
                anchors.verticalCenter: parent.verticalCenter
            }
            SignalBars {        // link quality, when the adapter reports it (mostly while discovering)
                visible: modelData.level >= 0
                level: modelData.level
                anchors.verticalCenter: parent.verticalCenter
            }
            Glyph {             // the fallback-router mark; lit while it is actually carrying the machine
                visible: tether.routerAddress === modelData.address
                name: "router"; size: 13
                color: tether.engaged ? Theme.text : Theme.subtext
                anchors.verticalCenter: parent.verticalCenter
            }
            Item {      // disconnect: an icon, never forgets the pairing
                visible: modelData.connected
                width: 32; height: 32
                Rectangle {
                    anchors.fill: parent; radius: 16
                    color: Theme.veil(dTap.pressed ? Tokens.tint.strong : dHover.hovered ? Tokens.tint.soft : Tokens.tint.subtle)
                }
                Glyph { anchors.centerIn: parent; name: "disconnect"; size: 15 }
                HoverHandler { id: dHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { id: dTap; onTapped: bluetooth.toggleConnect(modelData.path) }
            }
            Text {
                visible: modelData.paired
                text: "ⓘ"
                font { family: Theme.font; pixelSize: Tokens.type.title }
                color: Theme.subtext
                TapHandler { onTapped: root.pageRequested("detail:" + modelData.path) }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }
        }
    }

    Item {   // detail page
        width: parent.width
        height: visible ? detailCol.implicitHeight : 0
        visible: root.onDetail
        onVisibleChanged: if (!visible) renameField.text = ""
        Column {
            id: detailCol
            x: 22; width: parent.width - 44
            spacing: Tokens.space.xs
            ListRow {
                visible: root.detailDev !== null
                width: parent.width
                title: I18n.tr("Connect automatically")
                subtitle: root.detailDev && root.detailDev.paused ? I18n.tr("Paused until you connect it again") : I18n.tr("Reconnects by itself when it is in range")
                Switch { checked: root.detailDev ? root.detailDev.auto : true; onToggled: (c) => bluetooth.setAutoConnect(root.detailPath, c) }
            }
            ListRow {      // the fallback router: when the internet dies, this device carries the machine
                readonly property bool mine: root.detailDev !== null && tether.routerAddress !== "" && tether.routerAddress === root.detailDev.address
                visible: root.detailDev !== null && root.detailDev.paired
                width: parent.width
                title: I18n.tr("Fallback router")
                subtitle: mine && tether.engaged ? I18n.tr("Sharing internet")
                    : mine && tether.state === "unavailable" ? I18n.tr("Router unreachable")
                    : I18n.tr("Use this device's internet when Wi‑Fi has none")
                Switch {
                    checked: root.detailDev !== null && tether.routerAddress === root.detailDev.address
                    onToggled: (c) => tether.setRouter(root.detailDev ? root.detailDev.address : "", c)
                }
            }
            KeyValueRow { width: parent.width; key: I18n.tr("Status"); copyable: false
                value: root.detailDev ? (root.detailDev.connected ? I18n.tr("Connected") : I18n.tr("Not connected")) : "" }
            ListRow {      // the battery as a ring with the number inside, when the device reports one
                visible: root.detailDev && root.detailDev.battery >= 0
                width: parent.width
                title: I18n.tr("Battery")
                BatteryRing { percent: root.detailDev ? root.detailDev.battery : -1; anchors.verticalCenter: parent.verticalCenter }
            }
            ListRow {      // link quality: the same bars as the list, plus the raw reading
                visible: root.detailDev && root.detailDev.connected && root.detailRssi > -900
                width: parent.width
                title: I18n.tr("Signal")
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.space.sm
                    SignalBars { anchors.verticalCenter: parent.verticalCenter; level: root.rssiLevel(root.detailRssi) }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.detailRssi + " dBm"; textFormat: Text.PlainText
                        font { family: Theme.mono; pixelSize: Tokens.type.label }
                        color: Theme.subtext
                    }
                }
            }
            KeyValueRow { width: parent.width; key: I18n.tr("Type"); copyable: false
                value: root.detailDev ? I18n.tr(BtIcons.label(root.detailDev.icon)) : "" }
            KeyValueRow { width: parent.width; key: I18n.tr("Address"); value: root.detailDev ? root.detailDev.address : "" }
            Item { width: 1; height: Tokens.space.sm }
            Row {
                width: parent.width
                spacing: Tokens.space.sm
                TextField { id: renameField; width: parent.width - renameBtn.width - Tokens.space.sm; placeholder: I18n.tr("Name")
                    onAccepted: renameBtn.clicked() }
                Button { id: renameBtn; kind: "tonal"; text: I18n.tr("Rename"); anchors.verticalCenter: parent.verticalCenter
                    enabled: renameField.text.trim().length > 0
                    onClicked: bluetooth.rename(root.detailPath, renameField.text) }
            }
            Item { width: 1; height: Tokens.space.md }
            Button {
                id: forgetBtn
                property bool armed: false
                kind: "negative"
                text: armed ? I18n.tr("Tap again to forget") : I18n.tr("Forget device")
                onClicked: {
                    if (!armed) { armed = true; disarm.restart(); return }
                    bluetooth.forget(root.detailPath)
                    root.pageRequested("")
                }
                Timer { id: disarm; interval: 4000; onTriggered: forgetBtn.armed = false }
            }
        }
    }
}
