#!/usr/bin/env bash
# Build and install the island + toasts for the current user and run them as systemd user
# services (they start with the graphical session). No sudo needed.
#   install-island.sh            install and (re)start
#   install-island.sh --no-start install only
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX="$HOME/.local"
NO_START=0
[[ "${1:-}" == "--no-start" ]] && NO_START=1

for tool in cmake ninja; do
  command -v "$tool" >/dev/null || { echo "missing $tool (sudo apt install cmake ninja-build qt6-base-dev qt6-declarative-dev qt6-wayland-dev kf6-kwindowsystem-dev liblayershellqtinterface-dev extra-cmake-modules)" >&2; exit 1; }
done

for app in island toasts dock console lens desk; do
  echo "== build $app"
  cmake -S "$ROOT/components/$app" -B "$ROOT/components/$app/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" >/dev/null
  cmake --build "$ROOT/components/$app/build"
  cmake --install "$ROOT/components/$app/build" >/dev/null
done

echo "== kwin media seat"
# YouTube Music lives only inside the island: the aether-media KWin script owns its window
# (hides it from the moment it maps, seats it in the media panel on request). A window rule
# keeps it out of the taskbar, the switcher and the pager even before the script runs.
	KSCRIPTS="$HOME/.local/share/kwin/scripts"
	rm -rf "$KSCRIPTS/aether-media"
	mkdir -p "$KSCRIPTS"
	cp -r "$ROOT/components/island/kwin/aether-media" "$KSCRIPTS/"
	kwriteconfig6 --file kwinrc --group Plugins --key aether-mediaEnabled true
	# The console shelf's terminal seat (same handshake, matched by pid).
	rm -rf "$KSCRIPTS/aether-console-seat"
	cp -r "$ROOT/components/console/kwin/aether-console-seat" "$KSCRIPTS/"
	kwriteconfig6 --file kwinrc --group Plugins --key aether-console-seatEnabled true
R=(--file kwinrulesrc --group aether-media)
kwriteconfig6 "${R[@]}" --key Description "Aether media window (YouTube Music lives inside the island)"
for kv in wmclass=youtube-music wmclassmatch=2 types=1 above=true aboverule=2 \
          skiptaskbar=true skiptaskbarrule=2 skipswitcher=true skipswitcherrule=2 skippager=true skippagerrule=2; do
  kwriteconfig6 "${R[@]}" --key "${kv%%=*}" "${kv#*=}"
done
order=$(kreadconfig6 --file kwinrulesrc --group General --key Order)
[[ ",$order," == *",aether-media,"* ]] || kwriteconfig6 --file kwinrulesrc --group General --key Order "${order:+$order,}aether-media"
# The app must never map a window at login - the island asks for it when the panel opens.
PEAR_CFG="$HOME/.config/YouTube Music/config.json"
if [[ -f $PEAR_CFG ]]; then
  python3 - "$PEAR_CFG" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    cfg = json.load(f)
if cfg.setdefault("options", {}).get("appVisible") is not False:
    cfg["options"]["appVisible"] = False
    with open(path, "w") as f:
        json.dump(cfg, f, indent="\t", ensure_ascii=False)
PY
fi
qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start 2>/dev/null || true

echo "== services"
mkdir -p "$HOME/.config/systemd/user" "$HOME/.local/share/applications"
for app in island toasts dock console lens desk; do
  cat > "$HOME/.config/systemd/user/aether-$app.service" <<EOF
[Unit]
Description=Aether ${app^}
PartOf=graphical-session.target
After=graphical-session.target

[Service]
ExecStart=$PREFIX/bin/aether-$app
Restart=on-failure
RestartSec=2

[Install]
WantedBy=graphical-session.target
EOF
done
# KWin hands the window list to a client only if its desktop file (matched by executable) asks for it.
sed "s|@EXEC@|$PREFIX/bin/aether-dock|" "$ROOT/components/dock/org.aether.dock.desktop.in" > "$HOME/.local/share/applications/org.aether.dock.desktop"
sed "s|@EXEC@|$PREFIX/bin/aether-island|" "$ROOT/components/island/aether-island.desktop.in" > "$HOME/.local/share/applications/aether-island.desktop"
sed "s|@EXEC@|$PREFIX/bin/aether-toasts|" "$ROOT/components/toasts/org.aether.toasts.desktop.in" > "$HOME/.local/share/applications/org.aether.toasts.desktop"
sed "s|@EXEC@|$PREFIX/bin/aether-lens|" "$ROOT/components/lens/org.aether.lens.desktop.in" > "$HOME/.local/share/applications/org.aether.lens.desktop"
sed "s|@EXEC@|$PREFIX/bin/aether-console|" "$ROOT/components/console/org.aether.console.desktop.in" > "$HOME/.local/share/applications/org.aether.console.desktop"
# A launcher entry so a global shortcut (Win+N) can toggle the island over DBus.
cat > "$HOME/.local/share/applications/aether-island-toggle.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Aether Island
Exec=qdbus6 org.aether.Island /Island org.aether.Island.Toggle
NoDisplay=true
Icon=preferences-desktop
EOF
# Same for the console shelf (Win+C).
cat > "$HOME/.local/share/applications/aether-console-toggle.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Aether Console
Exec=qdbus6 org.aether.Console /Console org.aether.Console.Toggle
NoDisplay=true
Icon=utilities-terminal
EOF
# Win+G: Lens (circle to search).
cat > "$HOME/.local/share/applications/aether-lens.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Aether Lens
Exec=qdbus6 org.aether.Lens /Lens org.aether.Lens.Activate
NoDisplay=true
Icon=edit-find
EOF
kbuildsycoca6 >/dev/null 2>&1 || true
systemctl --user daemon-reload
systemctl --user enable aether-island.service aether-toasts.service aether-dock.service aether-console.service aether-lens.service aether-desk.service >/dev/null 2>&1

if [[ $NO_START == 0 ]]; then
  pkill -x aether-island 2>/dev/null || true
  pkill -x aether-toasts 2>/dev/null || true
  pkill -x aether-dock 2>/dev/null || true
  pkill -x aether-console 2>/dev/null || true
  pkill -x aether-lens 2>/dev/null || true
  pkill -x aether-desk 2>/dev/null || true
  sleep 1
  systemctl --user restart aether-island.service aether-toasts.service aether-dock.service aether-console.service aether-lens.service aether-desk.service
  sleep 2
  systemctl --user is-active aether-island.service aether-toasts.service aether-dock.service aether-console.service aether-lens.service aether-desk.service
fi
echo "Installed. Quit with: systemctl --user stop aether-island aether-toasts aether-dock aether-console aether-lens aether-desk"
