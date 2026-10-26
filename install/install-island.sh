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

for app in island toasts; do
  echo "== build $app"
  cmake -S "$ROOT/components/$app" -B "$ROOT/components/$app/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" >/dev/null
  cmake --build "$ROOT/components/$app/build"
  cmake --install "$ROOT/components/$app/build" >/dev/null
done

echo "== services"
mkdir -p "$HOME/.config/systemd/user" "$HOME/.local/share/applications"
for app in island toasts; do
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
# A launcher entry so a global shortcut (Win+N) can toggle the island over DBus.
cat > "$HOME/.local/share/applications/aether-island-toggle.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Aether Island
Exec=qdbus6 org.aether.Island /Island org.aether.Island.Toggle
NoDisplay=true
Icon=preferences-desktop
EOF
kbuildsycoca6 >/dev/null 2>&1 || true
systemctl --user daemon-reload
systemctl --user enable aether-island.service aether-toasts.service >/dev/null 2>&1

if [[ $NO_START == 0 ]]; then
  pkill -x aether-island 2>/dev/null || true
  pkill -x aether-toasts 2>/dev/null || true
  sleep 1
  systemctl --user restart aether-island.service aether-toasts.service
  sleep 2
  systemctl --user is-active aether-island.service aether-toasts.service
fi
echo "Installed. Quit with: systemctl --user stop aether-island aether-toasts"
