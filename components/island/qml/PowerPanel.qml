import QtQuick
import AetherShared
import "."

// Power panel (docs/PANELS-SPEC.md section 9). Lock and sleep act at once; restart, shut down
// and log out take a deliberate second tap within 5 s, otherwise they cancel.
PanelScaffold {
    id: root
    property string page: ""
    signal pageRequested(string page)
    signal closeRequested()
    title: "Power"
    subtitle: "Tap twice to restart, shut down or log out"

    function g(n) { return Qt.resolvedUrl("assets/glyphs/" + n + ".svg") }
    Column {
        x: 22; width: parent.width - 44
        spacing: Tokens.space.md
        Item { width: 1; height: 1 }
        Row {
            spacing: Tokens.space.sm
            ConfirmTile { label: "Lock"; glyphSource: root.g("lock"); needsConfirm: false
                onActivated: { session.lock(); root.closeRequested() } }
            ConfirmTile { visible: session.canSleep; label: "Sleep"; glyphSource: root.g("moon"); needsConfirm: false
                onActivated: { root.closeRequested(); session.sleep() } }
            ConfirmTile { label: "Restart"; confirmLabel: "Tap to restart"; glyphSource: root.g("restart")
                onActivated: session.restart() }
            ConfirmTile { label: "Shut down"; confirmLabel: "Tap to shut down"; glyphSource: root.g("power")
                onActivated: session.shutDown() }
        }
        Row {
            spacing: Tokens.space.sm
            ConfirmTile { width: (parent.parent.width - Tokens.space.sm) / (session.canFirmware ? 2 : 1); height: 56
                label: "Log out"; confirmLabel: "Tap to log out"; glyphSource: root.g("logout")
                onActivated: session.logout() }
            ConfirmTile { visible: session.canFirmware; width: (parent.parent.width - Tokens.space.sm) / 2; height: 56
                label: "Firmware setup"; confirmLabel: "Tap to restart"; glyphSource: root.g("restart")
                onActivated: session.restartToFirmware() }
        }
        Item { width: 1; height: Tokens.space.sm }
    }
}
