import QtQuick
import AetherShared
import "."

// Wi-Fi panel (docs/PANELS-SPEC.md section 4). List page: the connected network on top, saved,
// then available networks; detail page: addresses, forget. Powered by the `network` model,
// which scans only while this panel exists.
PanelScaffold {
    id: root
    property string page: ""
    signal pageRequested(string page)
    signal closeRequested()

    readonly property bool on: network.wifiEnabled && network.available
    readonly property bool onDetail: page.indexOf("detail:") === 0
    readonly property string detailSsid: onDetail ? page.substring(7) : ""

    title: onDetail ? detailSsid : I18n.tr("Wi‑Fi")
    subtitle: onDetail ? I18n.tr("Network details")
            : !network.available ? I18n.tr("No Wi‑Fi adapter")
            : !network.wifiEnabled ? I18n.tr("Off")
            : network.restoring ? I18n.f("Back on %1", network.restoringTo)
            : network.connecting.length > 0 ? I18n.f("Connecting to %1", network.connecting)
            : network.activeSsid.length > 0 ? I18n.f(network.connectivity === "portal" ? "Sign in required · %1" : "Connected · %1", network.activeSsid)
            : I18n.tr("Not connected")
    busy: network.scanning || network.connecting.length > 0
    showBack: true
    headerTrailing: [ Switch { visible: !root.onDetail && network.available; checked: network.wifiEnabled; onToggled: (c) => network.setEnabled(c) } ]
    footerHeight: 44
    footer: [
        Item {
            anchors.fill: parent
            Button { kind: "text"; text: I18n.tr("Wi‑Fi settings ↗"); anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                onClicked: { network.openSettings(); root.closeRequested() } }
            Button { visible: root.on && !root.onDetail; kind: "text"; text: I18n.tr("Scan")
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                onClicked: network.requestScan() }
        }
    ]

    Component.onDestruction: network.setActive(false)

    // Ordering is frozen while the pointer is over the list: signal bars update in place,
    // rows only re-sort once the pointer leaves (nothing moves under a hand aiming at it).
    property var shown: []
    readonly property bool frozen: listHover.hovered || expandedSsid.length > 0 || network.connecting.length > 0
    property string expandedSsid: ""
    property string errSsid
    property string errKind
    property string errText
    function sync() {
        const fresh = network.networks
        if (!frozen || shown.length === 0) { shown = fresh; return }
        const bySsid = {}
        for (const n of fresh) bySsid[n.ssid] = n
        const merged = []
        for (const o of shown) if (bySsid[o.ssid]) { merged.push(bySsid[o.ssid]); delete bySsid[o.ssid] }
        for (const n of fresh) if (bySsid[n.ssid]) merged.push(n)
        shown = merged
    }
    Connections { target: network; function onNetworksChanged() { root.sync() } }
    onFrozenChanged: if (!frozen) sync()
    Component.onCompleted: { network.setActive(true); sync() }
    Connections {
        target: network
        function onConnectFailed(ssid, kind, text) {
            // text first, and kind reset, so a repeated "busy" still reaches the row's handler
            root.errSsid = ssid; root.errKind = ""; root.errText = text; root.errKind = kind
            if (kind === "password") root.expandedSsid = ssid
        }
        function onConnected() { root.errSsid = ""; root.expandedSsid = "" }
    }

    readonly property var active: shown.filter(n => n.connected)
    property bool showAllSaved: false
    readonly property var savedAll: shown.filter(n => n.saved && !n.connected)
    // In-range saved networks always show; out-of-range ones are capped at 3 (spec 4.1).
    readonly property var saved: {
        let far = 0
        return savedAll.filter(n => n.inRange || showAllSaved || ++far <= 3)
    }
    readonly property int hiddenSaved: savedAll.length - saved.length
    readonly property var others: shown.filter(n => !n.saved && !n.connected)

    Item {   // list page
        id: listPage
        width: parent.width
        height: visible ? listCol.implicitHeight : 0
        visible: !root.onDetail
        HoverHandler { id: listHover }
        Column {
            id: listCol
            x: 22; width: parent.width - 44
            spacing: Tokens.space.xs

            // empty / off states
            Item {
                visible: !root.on
                width: parent.width; height: 150
                Column {
                    anchors.centerIn: parent
                    spacing: Tokens.space.md
                    Glyph { anchors.horizontalCenter: parent.horizontalCenter; name: "wifi-off"; size: 32; color: Theme.subtext }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: network.available ? I18n.tr("Wi‑Fi is off") : I18n.tr("No Wi‑Fi adapter found")
                        font { family: Theme.font; pixelSize: Tokens.type.body }
                        color: Theme.subtext
                    }
                    Button { visible: network.available; anchors.horizontalCenter: parent.horizontalCenter
                        kind: "filled"; text: I18n.tr("Turn on"); onClicked: network.setEnabled(true) }
                }
            }

            // the connected network
            Repeater {
                model: root.on ? root.active : []
                delegate: Rectangle {
                    required property var modelData
                    width: listCol.width
                    height: heroCol.height + 2 * Tokens.space.lg
                    radius: Tokens.radius.lg
                    color: Theme.veil(Tokens.tint.subtle)
                    Item {      // disconnect: an icon next to the network you are on. Nothing is forgotten.
                        id: disc
                        anchors { right: parent.right; top: parent.top; rightMargin: Tokens.space.md; topMargin: Tokens.space.md }
                        width: 36; height: 36
                        Rectangle {
                            anchors.fill: parent; radius: 18
                            color: Theme.veil(discTap.pressed ? Tokens.tint.strong : discHover.hovered ? Tokens.tint.soft : Tokens.tint.subtle)
                            Behavior on color { ColorAnimation { duration: Tokens.motion.duration.micro } }
                        }
                        Glyph { anchors.centerIn: parent; name: "disconnect"; size: 16 }
                        HoverHandler { id: discHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { id: discTap; onTapped: network.disconnectActive() }
                        activeFocusOnTab: true
                        Keys.onReturnPressed: network.disconnectActive()
                        Keys.onSpacePressed: network.disconnectActive()
                    }
                    Column {
                        id: heroCol
                        x: Tokens.space.lg; y: Tokens.space.lg
                        width: parent.width - 2 * Tokens.space.lg
                        spacing: Tokens.space.md
                        Row {
                            spacing: Tokens.space.md
                            Glyph { name: modelData.level >= 3 ? "wifi-3" : modelData.level === 2 ? "wifi-2" : "wifi-1"; size: 22; anchors.verticalCenter: parent.verticalCenter }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: heroCol.width - 22 - Tokens.space.md - 44
                                Text {
                                    width: parent.width; horizontalAlignment: Text.AlignLeft; elide: Text.ElideRight
                                    text: modelData.ssid; textFormat: Text.PlainText
                                    font { family: Theme.font; pixelSize: Tokens.type.body; weight: Font.DemiBold }
                                    color: Theme.text
                                }
                                Text {
                                    width: parent.width; horizontalAlignment: Text.AlignLeft
                                    text: network.connectivity === "portal" ? I18n.tr("Sign in to network")
                                        : network.connectivity === "limited" ? I18n.tr("Connected, no internet")
                                        : I18n.tr("Connected") + (modelData.band ? " · " + I18n.ltr(modelData.band + " GHz") : "")
                                    font { family: Theme.font; pixelSize: Tokens.type.label }
                                    color: network.connectivity === "full" ? Theme.subtext : Tokens.role.island.negative
                                }
                            }
                        }
                        Row {
                            spacing: Tokens.space.sm
                            Button { visible: network.connectivity === "portal"; kind: "filled"; text: I18n.tr("Sign in")
                                onClicked: { network.openPortal(); root.closeRequested() } }
                            Button { kind: "tonal"; text: I18n.tr("Details"); onClicked: root.pageRequested("detail:" + modelData.ssid) }
                        }
                    }
                }
            }

            SectionLabel { visible: root.on && root.saved.length > 0; width: parent.width; text: I18n.tr("Saved networks") }
            Repeater { model: root.on ? root.saved : []; delegate: netRow }
            ListRow {
                visible: root.on && (root.hiddenSaved > 0 || root.showAllSaved && root.savedAll.some(n => !n.inRange))
                width: parent.width; height: 44
                title: root.showAllSaved ? I18n.tr("Show fewer") : I18n.f("Show all saved (%1)", root.savedAll.length)
                onClicked: root.showAllSaved = !root.showAllSaved
            }
            SectionLabel { visible: root.on && root.others.length > 0; width: parent.width; text: I18n.tr("Available") }
            Repeater { model: root.on ? root.others : []; delegate: netRow }
            Text {
                visible: root.on && root.shown.length === 0
                width: parent.width; height: 80
                horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                text: network.scanning ? I18n.tr("Looking for networks…") : I18n.tr("No networks found")
                font { family: Theme.font; pixelSize: Tokens.type.body }
                color: Theme.subtext
            }
        }
    }

    Component {
        id: netRow
        WifiRow {
            required property var modelData
            net: modelData
            width: listCol.width
            expanded: root.expandedSsid === modelData.ssid
            errorKind: root.errSsid === modelData.ssid ? root.errKind : ""
            errorText: root.errSsid === modelData.ssid ? root.errText : ""
            onDetailsRequested: root.pageRequested("detail:" + modelData.ssid)
            onExpandRequested: root.expandedSsid = modelData.ssid
            onCollapseRequested: if (root.expandedSsid === modelData.ssid) root.expandedSsid = ""
            Connections {
                target: root
                function onErrKindChanged() { if (root.errSsid === modelData.ssid) showError(root.errKind, root.errText) }
            }
        }
    }

    Item {   // detail page
        id: detailPage
        width: parent.width
        height: visible ? detailCol.implicitHeight : 0
        visible: root.onDetail
        property var rows: []
        onVisibleChanged: if (visible) rows = network.details(root.detailSsid)
        Timer { running: detailPage.visible; interval: 2000; repeat: true; onTriggered: detailPage.rows = network.details(root.detailSsid) }
        Column {
            id: detailCol
            x: 22; width: parent.width - 44
            spacing: Tokens.space.xs
            ListRow {
                readonly property var net: root.shown.find(n => n.ssid === root.detailSsid) || null
                visible: net !== null && net.saved
                width: detailCol.width
                title: I18n.tr("Connect automatically")
                subtitle: I18n.tr("Reconnects by itself when it is in range")
                Switch { checked: parent.net ? parent.net.autoconnect : true; onToggled: (c) => network.setAutoconnect(root.detailSsid, c) }
            }
            Repeater {
                model: detailPage.rows
                delegate: KeyValueRow { required property var modelData; width: detailCol.width; key: I18n.tr(modelData.key); value: modelData.value }
            }
            Item { width: 1; height: Tokens.space.md }
            Button {
                id: forgetBtn
                property bool armed: false
                visible: root.shown.some(n => n.ssid === root.detailSsid && n.saved)
                kind: "negative"
                text: armed ? I18n.tr("Tap again to forget") : I18n.tr("Forget network")
                onClicked: {
                    if (!armed) { armed = true; disarm.restart(); return }
                    network.forget(root.detailSsid)
                    root.pageRequested("")
                }
                Timer { id: disarm; interval: 4000; onTriggered: forgetBtn.armed = false }
            }
        }
    }
}
