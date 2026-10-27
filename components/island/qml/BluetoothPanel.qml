import QtQuick
import AetherShared
import "."

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

    title: onDetail ? (detailDev ? detailDev.name : "Device") : "Bluetooth"
    subtitle: onDetail ? "Device details"
            : !bluetooth.available ? "No Bluetooth adapter"
            : !bluetooth.powered ? "Off"
            : connected.length > 0 ? connected[0].name + (connected.length > 1 ? " +" + (connected.length - 1) : "") + " connected"
            : "Visible as “" + bluetooth.adapterName + "” while this panel is open"
    busy: bluetooth.discovering || bluetooth.busy.length > 0
    headerTrailing: [ Switch { visible: !root.onDetail && bluetooth.available; checked: bluetooth.powered; onToggled: (c) => bluetooth.setPowered(c) } ]
    footerHeight: 44
    footer: [
        Item {
            anchors.fill: parent
            Button { kind: "text"; text: "Bluetooth settings ↗"; x: 14; anchors.verticalCenter: parent.verticalCenter
                onClicked: { bluetooth.openSettings(); root.closeRequested() } }
        }
    ]

    Component.onCompleted: bluetooth.setActive(true)
    Component.onDestruction: bluetooth.setActive(false)
    Connections {
        target: bluetooth
        function onOpFailed(path, text) { root.errPath = path; root.errText = text; errTimer.restart() }
    }
    Timer { id: errTimer; interval: 6000; onTriggered: root.errPath = "" }

    function stateOf(d) {
        if (errPath === d.path) return errText
        if (bluetooth.busy === d.path) return d.paired ? "Connecting…" : "Pairing…"
        if (d.connected) return d.battery >= 0 ? "Battery " + d.battery + "%" : "Connected"
        return d.paired ? "Not connected" : "Tap to pair"
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
                        text: bluetooth.available ? "Bluetooth is off" : "No Bluetooth adapter found"
                        font { family: Theme.font; pixelSize: Tokens.type.body }
                        color: Theme.subtext
                    }
                    Button { visible: bluetooth.available; anchors.horizontalCenter: parent.horizontalCenter
                        kind: "filled"; text: "Turn on"; onClicked: bluetooth.setPowered(true) }
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
                color: Qt.rgba(1, 1, 1, Tokens.tint.subtle)
                Column {
                    id: pairCol
                    x: Tokens.space.lg; y: Tokens.space.lg
                    width: parent.width - 2 * Tokens.space.lg
                    spacing: Tokens.space.md
                    Text {
                        width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
                        text: pairCard.pkind === "confirm" ? "Confirm that " + pairCard.pname + " shows this code"
                            : pairCard.pkind === "display" ? "Type " + pairCard.pcode + " on " + pairCard.pname + ", then press Enter"
                            : pairCard.pkind === "authorize" ? pairCard.pname + " wants to connect"
                            : "Enter the code for " + pairCard.pname
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
                        placeholder: "Code"
                        onAccepted: if (text.length > 0) bluetooth.answerPin(text)
                    }
                    Row {
                        spacing: Tokens.space.sm
                        Button { visible: pairCard.pkind !== "display"; kind: "filled"
                            text: pairCard.pkind === "pin" || pairCard.pkind === "passkey" ? "Pair" : pairCard.pkind === "authorize" ? "Allow" : "Pair"
                            onClicked: pinField.visible ? bluetooth.answerPin(pinField.text) : bluetooth.answerConfirm(true) }
                        Button { kind: "text"; text: "Cancel"; onClicked: bluetooth.cancelPairing() }
                    }
                }
            }

            SectionLabel { visible: bluetooth.powered && root.connected.length > 0; width: parent.width; text: "Connected" }
            Repeater { model: bluetooth.powered ? root.connected : []; delegate: devRow }
            SectionLabel { visible: bluetooth.powered && root.saved.length > 0; width: parent.width; text: "Saved devices" }
            Repeater { model: bluetooth.powered ? root.saved : []; delegate: devRow }
            SectionLabel { visible: bluetooth.powered && root.nearby.length > 0; width: parent.width; text: "Pair new device" }
            Repeater { model: bluetooth.powered ? root.nearby : []; delegate: devRow }
            Text {
                visible: bluetooth.powered && root.nearby.length === 0 && bluetooth.discovering
                width: parent.width; height: 48
                verticalAlignment: Text.AlignVCenter
                text: "Looking for devices…"
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
            leadingGlyphSource: Qt.resolvedUrl("assets/glyphs/bluetooth.svg")
            enabled: bluetooth.busy.length === 0 || bluetooth.busy === modelData.path
            onClicked: modelData.paired ? bluetooth.toggleConnect(modelData.path) : bluetooth.pair(modelData.path)
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
            KeyValueRow { width: parent.width; key: "Status"; copyable: false
                value: root.detailDev ? (root.detailDev.connected ? "Connected" : "Not connected") : "" }
            KeyValueRow { visible: root.detailDev && root.detailDev.battery >= 0; width: parent.width; key: "Battery"; copyable: false
                value: root.detailDev ? root.detailDev.battery + " %" : "" }
            KeyValueRow { width: parent.width; key: "Type"; copyable: false; value: root.detailDev ? root.detailDev.icon.replace("audio-", "").replace("input-", "") : "" }
            KeyValueRow { width: parent.width; key: "Address"; value: root.detailDev ? root.detailDev.address : "" }
            Item { width: 1; height: Tokens.space.sm }
            Row {
                width: parent.width
                spacing: Tokens.space.sm
                TextField { id: renameField; width: parent.width - renameBtn.width - Tokens.space.sm; placeholder: "Name"
                    onAccepted: renameBtn.clicked() }
                Button { id: renameBtn; kind: "tonal"; text: "Rename"; anchors.verticalCenter: parent.verticalCenter
                    enabled: renameField.text.trim().length > 0
                    onClicked: bluetooth.rename(root.detailPath, renameField.text) }
            }
            Item { width: 1; height: Tokens.space.md }
            Button {
                id: forgetBtn
                property bool armed: false
                kind: "negative"
                text: armed ? "Tap again to forget" : "Forget device"
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
