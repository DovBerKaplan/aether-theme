#!/usr/bin/env bash
# Stop and remove the island + toasts services, bring back Plasma's own notification
# banners and the global menu. To get the Plasma top bar back, run install/restore.sh
# (it restores the panel layout from the latest backup) or system/layout.js with a top panel.
set -euo pipefail
# The clean-desktop toggle hides the desktop's icons with Folder View's filter: put the user's own
# filter back first, so no file stays hidden once aether-desk is gone.
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
desktops().forEach(function (d) {
    d.currentConfigGroup = ["General"];
    if (String(d.readConfig("aetherClean", "false")) === "true") {
        d.writeConfig("filterMode", parseInt(d.readConfig("aetherFilterMode", 0)) || 0);
        d.writeConfig("filterPattern", String(d.readConfig("aetherFilterPattern", "*")) || "*");
        d.writeConfig("aetherClean", "false");
    }
});' >/dev/null 2>&1 || true
systemctl --user disable --now aether-island.service aether-toasts.service aether-dock.service aether-console.service aether-lens.service aether-desk.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/aether-island.service" "$HOME/.config/systemd/user/aether-toasts.service" "$HOME/.config/systemd/user/aether-dock.service" "$HOME/.config/systemd/user/aether-console.service" "$HOME/.config/systemd/user/aether-lens.service" "$HOME/.config/systemd/user/aether-desk.service" "$HOME/.local/bin/aether-desk" \
      "$HOME/.local/share/applications/org.aether.lens.desktop" "$HOME/.local/share/applications/aether-lens.desktop" "$HOME/.local/bin/aether-lens" \
      "$HOME/.local/share/applications/org.aether.dock.desktop" "$HOME/.local/bin/aether-dock" \
      "$HOME/.local/share/applications/org.aether.console.desktop" "$HOME/.local/bin/aether-console" \
      "$HOME/.local/share/applications/aether-island-toggle.desktop" \
      "$HOME/.local/share/applications/aether-console-toggle.desktop" \
      "$HOME/.local/bin/aether-island" "$HOME/.local/bin/aether-toasts"
rm -rf "$HOME/.local/share/aether-island" "$HOME/.local/share/aether-toasts" "$HOME/.local/share/aether-dock" "$HOME/.local/share/aether-console" "$HOME/.local/share/aether-lens" "$HOME/.local/share/aether-desk"
systemctl --user daemon-reload
# The YouTube Music seat: KWin script and window rule
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript aether-media >/dev/null 2>&1 || true
rm -rf "$HOME/.local/share/kwin/scripts/aether-media"
kwriteconfig6 --file kwinrc --group Plugins --key aether-mediaEnabled --delete 2>/dev/null || true
python3 - "$HOME/.config/kwinrulesrc" <<'PY' || true
import configparser, sys
path = sys.argv[1]
cp = configparser.ConfigParser(interpolation=None, delimiters=("=",))
cp.optionxform = str
cp.read(path)
if cp.has_section("aether-media"):
    cp.remove_section("aether-media")
if cp.has_option("General", "Order"):
    order = [r for r in cp.get("General", "Order").split(",") if r and r != "aether-media"]
    cp.set("General", "Order", ",".join(order))
with open(path, "w") as f:
    cp.write(f, space_around_delimiters=False)
PY
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
# Global menu back
kwriteconfig6 --file kded6rc --group Module-appmenu --key autoload --delete 2>/dev/null || true
qdbus6 org.kde.kded6 /kded org.kde.kded6.loadModule appmenu >/dev/null 2>&1 || true
# Plasma's own notification banners back
kwriteconfig6 --file plasmanotifyrc --group Notifications --key CriticalInDndMode --delete 2>/dev/null || true
echo "Removed. Log out and back in so apps pick up the global menu again."
