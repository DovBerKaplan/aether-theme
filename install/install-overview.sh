#!/bin/bash
# Install (or restore) the Aether-restyled KWin Overview delegate.
#
# The Overview's window tiles are QML loaded at runtime from the system path;
# the restyle is a single-file replacement that survives until a kwin package
# update reverts it to stock (safe fallback), then `make install-overview`
# re-applies it.
#
#   sudo bash install/install-overview.sh             # apply the restyle
#   sudo bash install/install-overview.sh --restore   # back to stock
#
# After either action restart the compositor:  kwin_wayland --replace
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SYS=/usr/lib/x86_64-linux-gnu/qt6/qml/org/kde/kwin/private/effects
SRC="$REPO/system/kwin-overview/WindowHeapDelegate.qml"
BK="$REPO/backups/kwin-overview/WindowHeapDelegate.qml.orig"

[ "$(id -u)" = 0 ] || { echo "run with sudo (it writes into $SYS)"; exit 1; }
[ -f "$SRC" ] || { echo "missing $SRC"; exit 1; }

if [ "${1:-}" = "--restore" ]; then
    [ -f "$BK" ] || { echo "no backup at $BK"; exit 1; }
    TMP="$(mktemp "$SYS/.WindowHeapDelegate.restore.XXXXXX")"
    cp "$BK" "$TMP"
    chmod 644 "$TMP"
    mv "$TMP" "$SYS/WindowHeapDelegate.qml"
    echo "restored stock delegate"
    exit 0
fi

# keep one pristine copy of the stock file for --restore
mkdir -p "$(dirname "$BK")"
if [ ! -f "$BK" ]; then
    cp "$SYS/WindowHeapDelegate.qml" "$BK"
    [ -n "${SUDO_USER:-}" ] && chown "${SUDO_USER}:" "$(dirname "$BK")" "$BK" || true
    echo "backed up stock delegate -> $BK"
fi

# ETXTBSY-safe deploy: stage next to the target, then rename over it
TMP="$(mktemp "$SYS/.WindowHeapDelegate.aether.XXXXXX")"
cp "$SRC" "$TMP"
chmod 644 "$TMP"
mv "$TMP" "$SYS/WindowHeapDelegate.qml"
echo "installed the Aether overview delegate"
echo "restart the compositor to load it:  kwin_wayland --replace"
