#!/usr/bin/env bash
# ZCode RTL kit: install the launch wrapper, the resident CDP injector and a
# desktop override, so every launch — dock, launcher, zcode:// links — carries
# the flags and the RTL state re-applies itself in every renderer.
#
# IMPORTANT: the app rewrites ~/.local/share/applications/zcode.desktop at
# startup (Electron protocol registration), eating our override. The durable
# fix is patching the SYSTEM desktop file once (asks sudo — printed at the
# end). Nothing here touches a running instance: quit ZCode and launch it
# again for the kit to come up.
# Undo: systemctl --user disable --now zcode-rtl-inject; rm the files listed
# at the end of this script.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC=/usr/share/applications/zcode.desktop
DST="$HOME/.local/share/applications/zcode.desktop"
BIN="$HOME/.local/bin"

[[ -x /opt/ZCode/zcode ]] || { echo "missing /opt/ZCode/zcode" >&2; exit 1; }
[[ -f $SRC ]] || { echo "missing $SRC" >&2; exit 1; }

install -Dm755 "$ROOT/system/zcode-rtl/zcode-rtl" "$BIN/zcode-rtl"
install -Dm755 "$ROOT/system/zcode-rtl/zcode-rtl-inject.mjs" "$BIN/zcode-rtl-inject"
mkdir -p "$HOME/.config/aether"
install -Dm644 "$ROOT/system/zcode-rtl/rtl.css" "$HOME/.config/aether/zcode-rtl.css"
install -Dm755 "$ROOT/system/zcode-rtl/zcode-rtl-inspect.mjs" "$BIN/zcode-rtl-inspect.mjs"
install -Dm755 "$ROOT/system/zcode-rtl/zcode-rtl-apply.mjs" "$BIN/zcode-rtl-apply.mjs"

mkdir -p "$HOME/.config/systemd/user"
sed "s|^ExecStart=.*|ExecStart=$BIN/zcode-rtl-inject|" \
  "$ROOT/system/zcode-rtl/zcode-rtl-inject.service" > "$HOME/.config/systemd/user/zcode-rtl-inject.service"
systemctl --user daemon-reload
systemctl --user enable --now zcode-rtl-inject.service

# Local override (belt) — the app may eat it; the system patch below is braces.
if [[ ! -f $DST ]] || ! grep -q "zcode-rtl" "$DST" 2>/dev/null; then
  sed "s|^Exec=/opt/ZCode/zcode|Exec=$BIN/zcode-rtl|" "$SRC" > "$DST"
fi
command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 >/dev/null 2>&1 || true

echo "installed: wrapper, injector service (zcode-rtl-inject), override"
if grep -q "Exec=$BIN/zcode-rtl" "$SRC" 2>/dev/null; then
  echo "system desktop file: already patched"
else
  echo
  echo "== one-time durable fix (the app deletes our local override at startup) =="
  echo "run this once, then relaunch ZCode:"
  echo "  sudo sed -i 's|^Exec=/opt/ZCode/zcode|Exec=$BIN/zcode-rtl|' $SRC"
fi
