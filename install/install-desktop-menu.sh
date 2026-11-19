#!/bin/bash
# The desktop's right click opens the desk's glass arrange panel.
#
# Two pieces, installed together:
#   1. the AetherBridge QML module - a one-call D-Bus shim - into the system Qt qml dir;
#   2. a small anchored patch into Folder View's QML (the desktop containment) that hands the
#      empty-desktop right click to the bridge. Shift keeps Plasma's own menu one click away.
#
# A plasma-desktop package update reverts the patch to stock (a safe fallback); re-run this
# script - it is idempotent.
#
#   sudo bash install/install-desktop-menu.sh             # apply
#   sudo bash install/install-desktop-menu.sh --restore   # back to stock
#
# The panel itself lives in aether-desk: rebuild/redeploy it with make components +
# install/install-island.sh (or install/install.sh) - this script does not touch it.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
QMLROOT="$(qmake6 -query QT_INSTALL_QML 2>/dev/null || echo /usr/lib/x86_64-linux-gnu/qt6/qml)"
MODDIR="$QMLROOT/AetherBridge"
FV=/usr/share/plasma/plasmoids/org.kde.desktopcontainment/contents/ui/FolderView.qml
BK="$REPO/backups/desktop-menu/FolderView.qml.orig"

[ "$(id -u)" = 0 ] || { echo "run with sudo (it writes into $QMLROOT and /usr/share/plasma)"; exit 1; }
[ -f "$FV" ] || { echo "FolderView.qml not found at $FV"; exit 1; }

if [ "${1:-}" = "--restore" ]; then
    [ -f "$BK" ] || { echo "no backup at $BK"; exit 1; }
    TMP="$(mktemp "$(dirname "$FV")/.FolderView.restore.XXXXXX")"
    cp "$BK" "$TMP"
    chmod 644 "$TMP"
    mv "$TMP" "$FV"
    rm -rf "$MODDIR"
    echo "restored stock Folder View and removed the bridge module"
    exit 0
fi

echo "== build AetherBridge"
# build outside the repo even under sudo, so no root-owned build tree lands in the checkout
BUILD="$(mktemp -d /tmp/aether-bridge-build.XXXXXX)"
cmake -S "$REPO/components/bridge" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build "$BUILD" >/dev/null

echo "== install the bridge module -> $MODDIR"
mkdir -p "$MODDIR"
for f in libaetherbridge.so qmldir aetherbridge.qmltypes; do
    TMP="$(mktemp "$MODDIR/.$f.XXXXXX")"
    cp "$BUILD/AetherBridge/$f" "$TMP"
    chmod 644 "$TMP"
    mv "$TMP" "$MODDIR/$f"
done
rm -rf "$BUILD"
# the generated qmldir marks the plugin optional; a required plugin fails loudly on a
# half-install instead of silently losing the right click
sed -i 's/^optional plugin /plugin /' "$MODDIR/qmldir"

echo "== patch FolderView.qml"
# keep one pristine copy of the stock file for --restore
mkdir -p "$(dirname "$BK")"
if [ ! -f "$BK" ]; then
    cp "$FV" "$BK"
    [ -n "${SUDO_USER:-}" ] && chown "${SUDO_USER}:" "$(dirname "$BK")" "$BK" || true
    echo "backed up stock FolderView.qml -> $BK"
fi

python3 - "$FV" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
if "AetherBridge" in s:
    print("already patched")
    sys.exit()

# 1. the import, right after QtQuick
s, n = re.subn(r"(import QtQuick\n)", r"\1import AetherBridge 1.0\n", s, count=1)
assert n == 1, "import anchor not found - FolderView.qml changed upstream?"

# 2. the empty-desktop right click: our panel on the plain click, Plasma's menu otherwise
pat = re.compile(
    r"(?P<i>[ \t]+)if \(!dir\.usedByContainment && !dir\.creatingNewItems\) \{\n"
    r"(?P<j>[ \t]+)dir\.openContextMenu\(main, mouse\.modifiers\);\n"
    r"[ \t]+mouse\.accepted = true;\n"
    r"[ \t]+\}")
rep = (
    "{i}if (!dir.creatingNewItems) {{\n"
    "{j}// Aether: on the desktop the plain right click opens the desk's glass arrange panel;\n"
    "{j}// Shift keeps Plasma's own menu one click away.\n"
    "{j}if (dir.usedByContainment && !(mouse.modifiers & Qt.ShiftModifier)) {{\n"
    "{j}    AetherBridge.openArrange(mouse.x, mouse.y);\n"
    "{j}    mouse.accepted = true;\n"
    "{j}}} else {{\n"
    "{j}    dir.openContextMenu(main, mouse.modifiers);\n"
    "{j}    mouse.accepted = true;\n"
    "{j}}}\n"
    "{i}}}")
s, n = pat.subn(lambda m: rep.format(i=m.group("i"), j=m.group("j")), s, count=1)
assert n == 1, "right-click anchor not found - FolderView.qml changed upstream?"

open(p, "w", encoding="utf-8").write(s)
print("patched")
PY

echo "== restart plasmashell"
if [ -n "${SUDO_USER:-}" ]; then
    sudo -u "$SUDO_USER" env "XDG_RUNTIME_DIR=/run/user/$(id -u "$SUDO_USER")" \
        systemctl --user restart plasma-plasmashell.service && echo "plasmashell restarted" || {
        echo "could not restart plasmashell; run as the user:"
        echo "  systemctl --user restart plasma-plasmashell"
    }
fi
echo "done - right-click the desktop; the panel needs the new aether-desk (install/install-island.sh)"
