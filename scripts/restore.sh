#!/usr/bin/env bash
# Restore a backup made by backup.sh (latest by default) and reload Plasma.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCHIVE="${1:-$(ls -t "$ROOT"/backups/kde-backup-*.tar.gz | head -1)}"
echo "Restoring $ARCHIVE"
systemctl --user disable --now aether-mode-sync.path 2>/dev/null || true
tar xzf "$ARCHIVE" -C "$HOME"
qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
kquitapp6 plasmashell 2>/dev/null || true
(setsid plasmashell >/dev/null 2>&1 &)
echo "Done. Log out and back in for every app to pick up the old style."
