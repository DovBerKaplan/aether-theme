#!/usr/bin/env bash
# Install Mac-style 3-finger gestures (libinput-gestures) for the current user.
# Needs, once, as root:  sudo apt install libinput-tools && sudo usermod -aG input "$USER"
# then log out/in so the input group applies.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$HOME/.local/src/libinput-gestures"

command -v libinput >/dev/null || { echo "missing libinput (sudo apt install libinput-tools)" >&2; exit 1; }
[[ -d $SRC ]] || git clone -q --depth 1 https://github.com/bulletmark/libinput-gestures.git "$SRC"

install -Dm755 "$SRC/libinput-gestures" "$HOME/.local/bin/libinput-gestures"
install -Dm644 "$ROOT/system/gestures/libinput-gestures.conf" "$HOME/.config/libinput-gestures.conf"
mkdir -p "$HOME/.config/systemd/user"
sed "s|^ExecStart=.*|ExecStart=$HOME/.local/bin/libinput-gestures|" "$SRC/libinput-gestures.service" \
  > "$HOME/.config/systemd/user/libinput-gestures.service"
systemctl --user daemon-reload
systemctl --user enable libinput-gestures.service

if id -nG | tr ' ' '\n' | grep -qx input; then
  systemctl --user restart libinput-gestures.service
  echo "gestures running"
else
  echo "installed; it starts after you log out and back in (input group not active in this session yet)"
fi
