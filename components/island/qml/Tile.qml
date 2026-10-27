import QtQuick
import AetherShared
import "."

// One tile of the large island. `describe()` is the only place that knows what each tile id
// shows and does; it reads the existing models, so the tile follows them without polling.
Item {
    id: root
    required property string tileId
    required property var host           // the TileGrid: timer state and the signals back to the island
    property bool editing: false

    readonly property var d: describe(tileId)
    implicitHeight: 58

    function pct(v) { return v + "%" }
    function describe(id) {
        switch (id) {
        case "wifi": return {
            glyph: system.network === "ethernet" ? "ethernet" : (system.wifiEnabled ? "wifi-3" : "wifi-off"),
            label: "Wi‑Fi", sub: !system.wifiEnabled ? "Off" : (system.wifiName || "Not connected"),
            active: system.wifiEnabled, panel: "wifi", tap: () => system.toggleWifi() }
        case "bluetooth": return {
            glyph: system.bluetoothOn ? "bluetooth" : "bluetooth-off", label: "Bluetooth",
            sub: !system.bluetoothOn ? "Off" : (system.bluetoothDevices > 0 ? system.bluetoothDevices + " connected" : "On"),
            active: system.bluetoothOn, panel: "bluetooth", tap: () => system.toggleBluetooth() }
        case "nightlight": return {
            glyph: "moon", label: "Night", sub: displaySettings.nightEnabled ? "On" : "Off",
            active: displaySettings.nightEnabled, panel: "display", tap: () => displaySettings.setNightEnabled(!displaySettings.nightEnabled) }
        case "darktheme": return {
            glyph: "contrast", label: "Dark", sub: displaySettings.dark ? "On" : "Off",
            active: displaySettings.dark, panel: "display", tap: () => displaySettings.setDark(!displaySettings.dark) }
        case "airplane": {
            const on = !system.wifiEnabled && !system.bluetoothOn
            return { glyph: "plane", label: "Airplane", sub: on ? "On" : "Off", active: on, panel: "",
                tap: () => {
                    if (on) {     // back to how the radios were before
                        if (tiles.wifiBefore && !system.wifiEnabled) system.toggleWifi()
                        if (tiles.bluetoothBefore && !system.bluetoothOn) system.toggleBluetooth()
                    } else {
                        tiles.rememberRadios(system.wifiEnabled, system.bluetoothOn)
                        if (system.wifiEnabled) system.toggleWifi()
                        if (system.bluetoothOn) system.toggleBluetooth()
                    }
                } }
        }
        case "keepawake": return {
            glyph: "coffee", label: "Awake", sub: tiles.keepAwake ? "On" : "Off",
            active: tiles.keepAwake, panel: "", tap: () => tiles.toggleKeepAwake() }
        case "micmute": return {
            glyph: tiles.micMuted ? "mic-off" : "mic", label: "Mic", sub: tiles.micMuted ? "Muted" : "On",
            active: !tiles.micMuted, panel: "sound", tap: () => tiles.toggleMic() }
        case "powersaver": return {
            glyph: "leaf", label: "Saver", sub: power.profile === "power-saver" ? "On" : "Off",
            active: power.profile === "power-saver", panel: "battery",
            tap: () => power.setProfile(power.profile === "power-saver" ? "balanced" : "power-saver") }
        case "screenshot": return {
            glyph: "camera", label: "Capture", sub: "Area", active: false, panel: "",
            tap: () => { tiles.screenshot(); host.closeRequested() } }
        case "record": return {
            glyph: "record", label: "Record", sub: "Area", active: false, panel: "",
            tap: () => { tiles.record(); host.closeRequested() } }
        }
        return { glyph: "", label: id, sub: "", active: false, panel: "", tap: () => {} }
    }

    ToggleChip {
        anchors.fill: parent
        enabled: !root.editing
        glyph: root.d.glyph
        label: root.d.label
        sublabel: root.d.sub
        active: root.d.active
        hasPanel: root.d.panel.length > 0
        onTapped: root.d.tap()
        onPanelRequested: root.host.panelRequested(root.d.panel)
    }
}
