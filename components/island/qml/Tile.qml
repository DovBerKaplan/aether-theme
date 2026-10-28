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
    property int size: 1

    readonly property var d: describe(tileId)
    implicitHeight: 68

    function pct(v) { return v + "%" }
    function describe(id) {
        switch (id) {
        case "wifi": return {
            glyph: system.network === "ethernet" ? "ethernet" : (system.wifiEnabled ? "wifi-3" : "wifi-off"),
            label: I18n.tr("Wi‑Fi"), sub: !system.wifiEnabled ? I18n.tr("Off") : (system.wifiName || I18n.tr("Not connected")),
            active: system.wifiEnabled, panel: "wifi", tap: () => system.toggleWifi() }
        case "bluetooth": return {
            glyph: system.bluetoothOn ? "bluetooth" : "bluetooth-off", label: I18n.tr("Bluetooth"),
            sub: !system.bluetoothOn ? I18n.tr("Off") : (system.bluetoothDevices > 0 ? I18n.f("%1 connected", system.bluetoothDevices) : I18n.tr("On")),
            active: system.bluetoothOn, panel: "bluetooth", tap: () => system.toggleBluetooth() }
        case "nightlight": return {
            glyph: "moon", label: I18n.tr("Night"), sub: displaySettings.nightEnabled ? I18n.tr("On") : I18n.tr("Off"),
            active: displaySettings.nightEnabled, panel: "display", tap: () => displaySettings.setNightEnabled(!displaySettings.nightEnabled) }
        case "darktheme": {      // names the mode you are in now; a tap goes to the other one
            const dk = displaySettings.dark
            return { glyph: dk ? "moon" : "sun", label: dk ? I18n.tr("Dark") : I18n.tr("Light"), sub: dk ? I18n.tr("Tap for light") : I18n.tr("Tap for dark"),
                active: !dk, panel: "display", tap: () => displaySettings.setDark(!displaySettings.dark) }
        }
        case "airplane": {
            const on = !system.wifiEnabled && !system.bluetoothOn
            return { glyph: "plane", label: I18n.tr("Airplane"), sub: on ? I18n.tr("On") : I18n.tr("Off"), active: on, panel: "",
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
            glyph: "coffee", label: I18n.tr("Awake"), sub: tiles.keepAwake ? I18n.tr("On") : I18n.tr("Off"),
            active: tiles.keepAwake, panel: "", tap: () => tiles.toggleKeepAwake() }
        case "micmute": return {
            glyph: tiles.micMuted ? "mic-off" : "mic", label: I18n.tr("Mic"), sub: tiles.micMuted ? I18n.tr("Muted") : I18n.tr("On"),
            active: !tiles.micMuted, panel: "sound", tap: () => tiles.toggleMic() }
        case "powersaver": return {
            glyph: "leaf", label: I18n.tr("Saver"), sub: power.profile === "power-saver" ? I18n.tr("On") : I18n.tr("Off"),
            active: power.profile === "power-saver", panel: "battery",
            tap: () => power.setProfile(power.profile === "power-saver" ? "balanced" : "power-saver") }
        case "screenshot": return {
            glyph: "camera", label: I18n.tr("Capture"), sub: I18n.tr("Area"), active: false, panel: "",
            tap: () => { tiles.screenshot(); host.closeRequested() } }
        case "record": return {
            glyph: "record", label: I18n.tr("Record"), sub: I18n.tr("Area"), active: false, panel: "",
            tap: () => { tiles.record(); host.closeRequested() } }
        }
        return { glyph: "", label: id, sub: "", active: false, panel: "", tap: () => {} }
    }

    ToggleChip {
        anchors.fill: parent
        enabled: !root.editing
        size: root.size
        glyph: root.d.glyph
        label: root.d.label
        sublabel: root.d.sub
        active: root.d.active
        hasPanel: root.d.panel.length > 0
        onTapped: root.d.tap()
        onPanelRequested: root.host.panelRequested(root.d.panel)
    }
}
