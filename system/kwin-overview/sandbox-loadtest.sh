#!/bin/bash
# Load-test for the Aether WindowHeapDelegate: boots the aether-agent-run
# sandbox (nested kwin_wayland, isolated dbus + HOME), opens the Overview
# through kglobalaccel and checks that the effect stays alive with zero QML
# errors — i.e. the restyled delegate compiles and instantiates cleanly.
# Pixel checking happens later, live.
#
#   sandbox-loadtest.sh        (aether shadow is always applied)
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SYS=/usr/lib/x86_64-linux-gnu/qt6/qml/org/kde/kwin/private/effects
RUN="${AETHER_AGENT_RUN:-$HOME/.local/bin/aether-agent-run}"

TH=/tmp/aether-ov-home
for i in 1 2 3; do rm -rf "$TH" /tmp/aether-ov-shadow 2>/dev/null && break; sleep 2; done
mkdir -p "$TH/config" "$TH/cache" "$TH/local/share"
for f in kdeglobals kwinrc plasmarc; do
    cp "$HOME/.config/$f" "$TH/config/" 2>/dev/null || true
done
for d in color-schemes plasma icons; do
    ln -sfn "$HOME/.local/share/$d" "$TH/local/share/$d"
done

SHADOW=/tmp/aether-ov-shadow
mkdir -p "$SHADOW/org/kde/kwin/private/effects"
cp "$REPO/system/kwin-overview/WindowHeapDelegate.qml" "$SHADOW/org/kde/kwin/private/effects/"
cp "$SYS/WindowHeap.qml" "$SYS/qmldir" "$SYS/effectsplugin.qmltypes" \
    "$SYS/kde-qmlmodule.version" "$SHADOW/org/kde/kwin/private/effects/"
ln -s "$SYS/libeffectsplugin.so" "$SHADOW/org/kde/kwin/private/effects/libeffectsplugin.so"

export HOME="$TH" XDG_CONFIG_HOME="$TH/config" XDG_CACHE_HOME="$TH/cache" \
    XDG_DATA_HOME="$TH/local/share"
export QML2_IMPORT_PATH="$SHADOW" QML_IMPORT_PATH="$SHADOW"
export QT_FORCE_STDERR_LOGGING=1 QT_LOGGING_RULES="qml*=true;kwin*=true"

timeout 90 dbus-run-session -- "$RUN" --name overview-loadtest \
    --resolution 1920x1080 -- bash -s <<'INNER' || echo "loadtest: timed out ($?)"
log() { echo "[inner] $*" >&2; }
xeyes -geometry 300x300+500+300 >/dev/null 2>&1 & P1=$!
xmessage "hello there" -geometry 500x300+800+400 >/dev/null 2>&1 & P2=$!
xterm -title "Editor — Kate" -geometry 80x24+200+500 >/dev/null 2>&1 & P3=$!
sleep 4
qdbus6 org.kde.KWin /kglobalaccel org.kde.KGlobalAccel.blockGlobalShortcuts false >/dev/null 2>&1
qdbus6 org.kde.KWin /component/kwin org.kde.kglobalaccel.Component.invokeShortcut Overview >/dev/null 2>&1
sleep 1.5
log "active: $(qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.activeEffects 2>&1 | tr '\n' ' ')"
sleep 3
log "active after 4.5s: $(qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.activeEffects 2>&1 | tr '\n' ' ')"
kill $P1 $P2 $P3 2>/dev/null || true
INNER

# QML errors from the nested kwin (its stdout is the newest agent kwin log)
L=$(ls -t /run/user/1000/aether-agents/*.kwin.log 2>/dev/null | head -1)
echo "--- QML errors:"
grep -aiE "qrc|\.qml:|TypeError|ReferenceError|SyntaxError|Cannot |is not a" "$L" 2>/dev/null | head -10 || echo "(none)"
echo "--- overview lifecycle:"
grep -a "overview" "$L" 2>/dev/null | head -5 || true
