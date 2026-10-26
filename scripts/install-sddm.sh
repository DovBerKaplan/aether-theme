#!/usr/bin/env bash
# Install the Aether Lock login screen (needs sudo).
#   sudo scripts/install-sddm.sh          install + make it the active SDDM theme
#   sudo scripts/install-sddm.sh --revert switch back to the previous theme
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST=/usr/share/sddm/themes/aether-lock
# System Settings writes the active theme here, and it is read after other conf.d files.
CONF=/etc/sddm.conf.d/kde_settings.conf
PREV=/etc/sddm.conf.d/.aether-lock-previous-theme

[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }
command -v kwriteconfig6 >/dev/null || { echo "missing kwriteconfig6" >&2; exit 1; }

current="$(kreadconfig6 --file "$CONF" --group Theme --key Current 2>/dev/null || true)"

if [[ "${1:-}" == "--revert" ]]; then
  prev="$(cat "$PREV" 2>/dev/null || echo breeze)"
  kwriteconfig6 --file "$CONF" --group Theme --key Current "$prev"
  echo "Reverted SDDM theme to: $prev"
  exit 0
fi

rm -rf "$DEST"
cp -r "$ROOT/src/sddm/aether-lock" "$DEST"
chmod -R a+rX "$DEST"
[[ "$current" != "aether-lock" && -n "$current" ]] && echo "$current" > "$PREV"
kwriteconfig6 --file "$CONF" --group Theme --key Current aether-lock
kwriteconfig6 --file "$CONF" --group Theme --key CursorTheme breeze_cursors
kwriteconfig6 --file "$CONF" --group Theme --key Font "Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
echo "Installed $DEST (previous theme: ${current:-none}). Active from the next login screen."
