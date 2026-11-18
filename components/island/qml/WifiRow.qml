import QtQuick
import AetherShared
import "."

// One network. Tapping connects (saved/open), opens the password field (secured, new), or
// opens details (connected). The password field lives inside the row, so nothing else moves
// sideways. Progress and errors are written on the row that caused them.
Item {
    id: root
    required property var net            // one entry of network.networks
    property bool expanded: false
    property string errorKind
    property string errorText
    signal detailsRequested()
    signal expandRequested()
    signal collapseRequested()

    readonly property bool joining: network.connecting === net.ssid
    readonly property bool busy: network.connecting.length > 0
    readonly property string levelGlyph: net.level >= 3 ? "wifi-3" : net.level === 2 ? "wifi-2" : "wifi-1"
    width: parent ? parent.width : 360
    implicitHeight: row.height + (expanded ? entry.height + Tokens.space.sm : 0)
    Behavior on implicitHeight { NumberAnimation { duration: Tokens.motion.duration.base; easing.type: Tokens.motion.easing.enter } }
    height: implicitHeight
    clip: true
    opacity: net.inRange ? 1 : 0.6

    function focusField() { pw.forceFocus() }
    function showError(kind, text) {
        errorKind = kind; errorText = text
        if (kind === "password") { expandRequested(); pw.error = true; pw.errorText = I18n.tr(text); pw.shake() }
    }
    onExpandedChanged: if (expanded) { pw.text = ""; pw.error = false; focusTimer.restart() }
    Timer { id: focusTimer; interval: 60; onTriggered: pw.forceFocus() }

    ListRow {
        id: row
        width: parent.width
        leadingGlyphSource: Qt.resolvedUrl("assets/glyphs/" + root.levelGlyph + ".svg")
        title: root.net.ssid
        subtitle: root.joining ? I18n.tr(network.step)
                : root.errorKind.length > 0 && root.errorKind !== "password" ? I18n.tr(root.errorText)
                : root.net.needsPassword ? I18n.tr("Password needed")
                : !root.net.supported ? I18n.tr("Needs system settings")
                : !root.net.inRange ? I18n.tr("Out of range")
                : root.net.saved ? (root.net.autoconnect ? I18n.tr("Saved") : I18n.tr("Saved · manual"))
                : !root.net.secure ? I18n.tr("Open")
                : ""
        highlighted: root.expanded
        enabled: true   // taps while another network is joining get the "busy" message, not silence
        onClicked: {
            console.log("DIAG wifi tap", root.net.ssid, "saved=" + root.net.saved, "needsPw=" + root.net.needsPassword, "connected=" + root.net.connected, "secure=" + root.net.secure)   // TEMP: remove after debugging
            root.errorKind = ""
            if (root.net.connected) root.detailsRequested()
            else if (root.net.needsPassword) root.expandRequested()
            else if (!root.net.supported) network.openSettings()
            else if (root.net.saved || !root.net.secure) network.connectTo(root.net.ssid, "", true)
            else root.expanded ? root.collapseRequested() : root.expandRequested()
        }
        Glyph { visible: root.net.secure; name: "lock"; size: 12; color: Theme.subtext }
        Text {
            visible: root.net.band.length > 0 && root.net.band !== "2.4"
            text: root.net.band + "G"
            font { family: Theme.mono; pixelSize: Tokens.type.caption }
            color: Theme.subtext
        }
    }
    Column {
        id: entry
        y: row.height
        anchors { left: parent.left; leftMargin: Tokens.space.md + 36 + Tokens.space.md; right: parent.right; rightMargin: Tokens.space.md }
        spacing: Tokens.space.sm
        visible: root.expanded
        TextField {
            id: pw
            width: parent.width
            password: true
            placeholder: I18n.tr("Password")
            enabled: !root.joining
            onAccepted: connectBtn.clicked()
            onTextChanged: error = false
        }
        Row {
            layoutDirection: Qt.RightToLeft
            width: parent.width
            spacing: Tokens.space.sm
            Button {
                id: connectBtn
                kind: "filled"
                text: root.joining ? I18n.tr("Connecting…") : I18n.tr("Connect")
                enabled: pw.text.length >= 8 && !root.joining
                onClicked: if (enabled) network.connectTo(root.net.ssid, pw.text, true)
            }
            Button {
                kind: "text"
                text: I18n.tr("Cancel")
                onClicked: { if (root.joining) network.cancel(); root.collapseRequested() }
            }
        }
    }
    Connections {
        target: network
        function onConnected() { pw.text = ""; root.collapseRequested() }
    }
}
