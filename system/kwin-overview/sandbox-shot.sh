#!/bin/bash
# Aether Overview design gate: shoot the KWin overview effect inside an
# isolated sandbox — Xvnc + kwin_x11 on a throwaway X display, wrapped in
# dbus-run-session (its own bus, its own HOME) — against either the stock
# WindowHeapDelegate or the Aether restyle (shadowed in via QML2_IMPORT_PATH,
# the system file is never touched).
#
# kwin_x11 composites straight into the X root, so a plain `import -window
# root` sees the overview, the theme and the restyle — unlike the
# aether-agent-run nested kwin_wayland, whose virtual output never hands
# frames to ScreenShot2.
#
#   sandbox-shot.sh stock|aether OUT_DIR
#
# Shots land in OUT_DIR: 0-opening, 1-rest, 2-hover-left, 3-hover-right.
set -euo pipefail
MODE="${1:?usage: sandbox-shot.sh stock|aether OUT_DIR}"
OUT="${2:?usage: sandbox-shot.sh stock|aether OUT_DIR}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"

# A throwaway HOME carrying copies of the real look (colors, desktop theme)
# so the sandbox kwin sees Aether without ever writing to the live config.
TH=/tmp/aether-ov-home
for i in 1 2 3; do
    rm -rf "$TH" /tmp/aether-ov-shadow 2>/dev/null && break
    sleep 2
done
mkdir -p "$TH/config" "$TH/cache" "$TH/local/share"
for f in kdeglobals kwinrc plasmarc plasma-org.kde.plasma.desktop-appletsrc; do
    cp "$HOME/.config/$f" "$TH/config/" 2>/dev/null || true
done
for d in color-schemes plasma icons; do
    ln -sfn "$HOME/.local/share/$d" "$TH/local/share/$d"
done

SYS=/usr/lib/x86_64-linux-gnu/qt6/qml/org/kde/kwin/private/effects
if [ "$MODE" = aether ]; then
    SHADOW=/tmp/aether-ov-shadow
    mkdir -p "$SHADOW/org/kde/kwin/private/effects"
    cp "$REPO/system/kwin-overview/WindowHeapDelegate.qml" \
        "$SHADOW/org/kde/kwin/private/effects/"
    cp "$SYS/WindowHeap.qml" "$SYS/qmldir" "$SYS/effectsplugin.qmltypes" \
        "$SYS/kde-qmlmodule.version" "$SHADOW/org/kde/kwin/private/effects/"
    ln -s "$SYS/libeffectsplugin.so" \
        "$SHADOW/org/kde/kwin/private/effects/libeffectsplugin.so"
    export QML2_IMPORT_PATH="$SHADOW"
    export QML_IMPORT_PATH="$SHADOW"
elif [ "$MODE" != stock ]; then
    echo "mode must be 'stock' or 'aether'" >&2
    exit 1
fi

export HOME="$TH"
export XDG_CONFIG_HOME="$TH/config"
export XDG_CACHE_HOME="$TH/cache"
export XDG_DATA_HOME="$TH/local/share"
export XTEST_PY=/tmp/aether-dev-venv/bin/python
export REPO
export QT_FORCE_STDERR_LOGGING=1
export QT_LOGGING_RULES="${QT_LOGGING_RULES_DEBUG:-qml*=true;kwin*=true}"

timeout 150 dbus-run-session -- bash -s -- "$OUT" <<'INNER' || echo "sandbox-shot: timed out or failed ($?)"
set -u
OUT="$1"
export DISPLAY=""
PIDS=()
XDISP=""

cleanup() {
    for p in "${PIDS[@]:-}"; do kill "$p" 2>/dev/null || true; done
    sleep 0.5
    if [ -n "$XDISP" ]; then
        rm -f "/tmp/.X11-unix/X$XDISP" "/tmp/.X$XDISP-lock" 2>/dev/null || true
    fi
}
trap cleanup EXIT

log() { echo "[inner] $*" >&2; }

# the lowest free X display number (filesystem AND abstract sockets)
used="$(ss -xl 2>/dev/null | grep -oE '/tmp/\.X11-unix/X[0-9]+' | awk -FX '{print $2}' | sort -u)"
for n in $(seq 60 89); do
    [ -e "/tmp/.X11-unix/X$n" ] || { echo "$used" | grep -qx "$n" || { XDISP="$n"; break; }; }
done
[ -n "$XDISP" ] || { log "no free X display"; exit 1; }
export DISPLAY=":$XDISP"

# a virtual X server with a real framebuffer — kwin_x11 composites into it
Xvnc "$DISPLAY" -geometry 1920x1080 -depth 24 -rfbport 0 -SecurityTypes None \
    -localhost yes >"$OUT/xvnc.log" 2>&1 & PIDS+=($!)
up=1
for i in $(seq 1 50); do
    if ss -xl 2>/dev/null | grep -q "/tmp/.X11-unix/X$XDISP"; then up=0; break; fi
    sleep 0.2
done
[ "$up" = 0 ] || { log "Xvnc did not come up (see xvnc.log)"; exit 1; }
log "Xvnc up on $DISPLAY"

# kwin_x11 becomes the compositor+WM of this display and paints the root
kwin_x11 --replace >"$OUT/kwin-x11.log" 2>&1 & PIDS+=($!)
sleep 5
log "kwin_x11 up: $(qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadedEffects 2>/dev/null | grep -c .) effects loaded"

# a small mixed desktop with crafted captions for the title-pill logic
xterm -title "Documents — Dolphin" -geometry 90x28+240+240 >/dev/null 2>&1 & PIDS+=($!)
sleep 1
xterm -title "New Tab - Google Chrome" -geometry 80x24+1050+160 >/dev/null 2>&1 & PIDS+=($!)
xmessage "hi there, a plain message window" -geometry 500x300+300+560 >/dev/null 2>&1 & PIDS+=($!)
xeyes -geometry 300x300+1180+430 >/dev/null 2>&1 & PIDS+=($!)
sleep 2

shot() { import -window root "$1"; }
active() { qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.activeEffects 2>/dev/null | tr '\n' ' '; }
log "invoking Overview"
qdbus6 org.kde.KWin /component/kwin org.kde.kglobalaccel.Component.invokeShortcut Overview >/dev/null 2>&1

sleep 0.4
shot "$OUT/0-opening.png"
sleep 1
log "active@1.4s: $(active)"
shot "$OUT/1-rest.png"

V="$XTEST_PY $REPO/tools/xtest-pointer.py --display $DISPLAY"
$V move 500 700; sleep 0.6; shot "$OUT/2-hover-left.png"
$V move 1400 650; sleep 0.6; shot "$OUT/3-hover-right.png"

log "cleanup"
qdbus6 org.kde.KWin /component/kwin org.kde.kglobalaccel.Component.invokeShortcut Overview >/dev/null 2>&1 || true
INNER

echo "sandbox-shot: $MODE shots in $OUT"
