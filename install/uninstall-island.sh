#!/usr/bin/env bash
# Stop and remove the island + toasts services, bring back Plasma's own notification
# banners and the global menu. To get the Plasma top bar back, run install/restore.sh
# (it restores the panel layout from the latest backup) or system/layout.js with a top panel.
set -euo pipefail
systemctl --user disable --now aether-island.service aether-toasts.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/aether-island.service" "$HOME/.config/systemd/user/aether-toasts.service" \
      "$HOME/.local/share/applications/aether-island-toggle.desktop" \
      "$HOME/.local/bin/aether-island" "$HOME/.local/bin/aether-toasts"
rm -rf "$HOME/.local/share/aether-island" "$HOME/.local/share/aether-toasts"
systemctl --user daemon-reload
# Global menu back
kwriteconfig6 --file kded6rc --group Module-appmenu --key autoload --delete 2>/dev/null || true
qdbus6 org.kde.kded6 /kded org.kde.kded6.loadModule appmenu >/dev/null 2>&1 || true
# Plasma's own notification banners back
kwriteconfig6 --file plasmanotifyrc --group Notifications --key CriticalInDndMode --delete 2>/dev/null || true
echo "Removed. Log out and back in so apps pick up the global menu again."
