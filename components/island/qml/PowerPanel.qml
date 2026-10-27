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
    title: I18n.tr("Power")
    subtitle: I18n.tr("Tap twice to restart, shut down or log out")

    function g(n) { return Qt.resolvedUrl("assets/glyphs/" + n + ".svg") }
    Column {
        x: 22; width: parent.width - 44
        spacing: Tokens.space.md
        Item { width: 1; height: 1 }
        Row {
            spacing: Tokens.space.sm
            ConfirmTile { label: I18n.tr("Lock"); glyphSource: root.g("lock"); needsConfirm: false
                onActivated: { session.lock(); root.closeRequested() } }
            ConfirmTile { visible: session.canSleep; label: I18n.tr("Sleep"); glyphSource: root.g("moon"); needsConfirm: false
                onActivated: { root.closeRequested(); session.sleep() } }
            ConfirmTile { label: I18n.tr("Restart"); confirmLabel: I18n.tr("Tap to restart"); glyphSource: root.g("restart")
                onActivated: session.restart() }
            ConfirmTile { label: I18n.tr("Shut down"); confirmLabel: I18n.tr("Tap to shut down"); glyphSource: root.g("power")
                onActivated: session.shutDown() }
        }
        Row {
            spacing: Tokens.space.sm
            ConfirmTile { width: (parent.parent.width - Tokens.space.sm) / (session.canFirmware ? 2 : 1); height: 56
                label: I18n.tr("Log out"); confirmLabel: I18n.tr("Tap to log out"); glyphSource: root.g("logout")
                onActivated: session.logout() }
            ConfirmTile { visible: session.canFirmware; width: (parent.parent.width - Tokens.space.sm) / 2; height: 56
                label: I18n.tr("Firmware setup"); confirmLabel: I18n.tr("Tap to restart"); glyphSource: root.g("restart")
                onActivated: session.restartToFirmware() }
        }
        Item { width: 1; height: Tokens.space.sm }
    }
}
