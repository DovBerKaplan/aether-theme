import QtQuick
import AetherShared
import "."
import "BtIcons.js" as BtIcons

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
    // The first connected Bluetooth device that reports a battery level, else -1.
    readonly property int btBattery: {
        const l = bluetooth.devices
        for (let i = 0; i < l.length; ++i) if (l[i].connected && l[i].battery >= 0) return l[i].battery
        return -1
    }
    function describe(id) {
        switch (id) {
        case "wifi": return {
            glyph: system.network === "ethernet" ? "ethernet" : (system.wifiEnabled ? "wifi-3" : "wifi-off"),
            label: I18n.tr("Wi‑Fi"),
            sub: !system.wifiEnabled ? I18n.tr("Off")
                : tether.engaged ? I18n.f("via %1", tether.routerName)   // riding the fallback router right now
                : (system.wifiName || I18n.tr("Not connected")),
            active: system.wifiEnabled, panel: "wifi", tap: () => system.toggleWifi(),
            trail: system.wifiEnabled && system.network === "wifi" ? { kind: "signal", level: Math.max(1, Math.min(4, Math.ceil(system.wifiSignal / 25))) } : { kind: "chevron" } }
        case "bluetooth": {      // a lone connected device gives the tile its face: its glyph and name
            const conns = bluetooth.devices.filter(d => d.connected)
            const one = conns.length === 1 ? conns[0] : null
            const lvl = Math.max(-1, ...conns.map(d => d.level === undefined ? -1 : d.level))
            return {
                glyph: !system.bluetoothOn ? "bluetooth-off" : one ? BtIcons.glyph(one.icon) : "bluetooth",
                label: one ? one.name : I18n.tr("Bluetooth"),
                sub: !system.bluetoothOn ? I18n.tr("Off")
                    : one ? I18n.tr("Connected") : (conns.length > 0 ? I18n.f("%1 connected", conns.length) : I18n.tr("On")),
                active: system.bluetoothOn, panel: "bluetooth", tap: () => system.toggleBluetooth(),
                trail: btBattery >= 0 ? { kind: "text", text: btBattery + "%" }
                    : lvl > 0 ? { kind: "signal", level: lvl } : { kind: "chevron" } }
        }
        case "nightlight": return {
            glyph: "moon", label: I18n.tr("Night"), sub: displaySettings.nightEnabled ? I18n.tr("On") : I18n.tr("Off"),
            active: displaySettings.nightEnabled, panel: "display", tap: () => displaySettings.setNightEnabled(!displaySettings.nightEnabled),
            trail: displaySettings.nightEnabled ? { kind: "text", text: displaySettings.nightTemperature + "K" } : { kind: "chevron" } }
        case "darktheme": {      // dark -> light -> by hours -> dark; a mode picked by hand is never overridden by the clock
            const dk = displaySettings.dark, auto = displaySettings.autoTheme
            return {
                glyph: auto ? "sun-moon" : dk ? "moon" : "sun",
                label: auto ? I18n.tr("Auto") : dk ? I18n.tr("Dark") : I18n.tr("Light"),
                sub: auto ? I18n.tr("By hours") : dk ? I18n.tr("Tap for light") : I18n.tr("Tap for dark"),
                active: auto || !dk, panel: "display",
                tap: () => { if (auto) displaySettings.setDark(true); else if (dk) displaySettings.setDark(false); else displaySettings.setAutoTheme(true) },
                trail: { kind: "chevron" } }
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
        case "vibe": return {
            glyph: "vibe", label: I18n.tr("Vibe"), sub: tiles.vibeOn ? I18n.tr("Agents run") : I18n.tr("Off"),
            active: tiles.vibeOn, panel: "", tap: () => tiles.toggleVibe(),
            trail: tiles.vibeOn ? { kind: "dot" } : {} }
        case "lens": return {
            glyph: "lens", label: I18n.tr("Lens"), sub: tiles.lensOn ? I18n.tr("On") : I18n.tr("Off"),
            active: tiles.lensOn, panel: "", tap: () => tiles.toggleLens() }
        case "micmute": return {
            glyph: tiles.micMuted ? "mic-off" : "mic", label: I18n.tr("Mic"), sub: tiles.micMuted ? I18n.tr("Muted") : I18n.tr("On"),
            active: !tiles.micMuted, panel: "sound", tap: () => tiles.toggleMic(), trail: tiles.micMuted ? { kind: "dot" } : { kind: "chevron" } }
        case "powersaver": return {
            glyph: "leaf", label: I18n.tr("Saver"), sub: power.profile === "power-saver" ? I18n.tr("On") : I18n.tr("Off"),
            active: power.profile === "power-saver", panel: "battery",
            tap: () => power.setProfile(power.profile === "power-saver" ? "balanced" : "power-saver"),
            trail: { kind: "text", text: power.profile === "power-saver" ? I18n.tr("Saver") : power.profile === "performance" ? I18n.tr("Performance") : I18n.tr("Balanced") } }
        case "accent": return {
            glyph: "palette", label: I18n.tr("Color"), sub: I18n.tr("Accent"), active: false, panel: "color",
            tap: () => host.panelRequested("color"), trail: { kind: "dot", color: Theme.accent } }
        case "console": return {
            glyph: "terminal", label: I18n.tr("Console"), sub: tiles.consoleEarOn ? I18n.tr("Tab shown") : I18n.tr("Tab hidden"),
            active: tiles.consoleEarOn, panel: "", tap: () => tiles.toggleConsoleEar() }
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
        trail: root.d.trail || ({})
        glyph: root.d.glyph
        label: root.d.label
        sublabel: root.d.sub
        active: root.d.active
        hasPanel: root.d.panel.length > 0
        onTapped: root.d.tap()
        onPanelRequested: root.host.panelRequested(root.d.panel)
    }
}
