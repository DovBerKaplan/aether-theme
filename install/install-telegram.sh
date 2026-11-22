#!/usr/bin/env bash
# Install Aethergram, the unofficial Telegram Desktop fork that wears the Aether palette, and dress it:
# the palettes and themes (palette + a chat background in the accent's hue) are generated, recoloured
# to the island's accent and the live ones put where the fork watches them (aether-accent-sync, and
# aether-mode-sync on every light/dark switch).
#   install-telegram.sh                         latest release of DovBerKaplan/aethergram (needs gh)
#   install-telegram.sh ~/aethergram/out/Release/Telegram   a local build
# No sudo.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
D="$HOME/.local/share"
OPT="$HOME/.local/opt/aethergram"
BIN="$OPT/Aethergram"
APPID=io.github.dovberkaplan.Aethergram
REPO=DovBerKaplan/aethergram
need() { command -v "$1" >/dev/null || { echo "missing $1" >&2; exit 1; }; }
need python3
python3 -c 'import PIL' 2>/dev/null || { echo "missing Pillow (python3-pil): it draws the chat background" >&2; exit 1; }

echo "== binary"
mkdir -p "$OPT" "$HOME/.local/bin" "$D/applications"
icon=telegram
if [[ $# -gt 0 ]]; then
  src="$1"
  [[ -f $src && -x $src ]] || { echo "not an executable: $src" >&2; exit 1; }
  # A source tree build: its icon sits in the tree, two levels above out/Release.
  art="$(cd "$(dirname "$src")/../.." && pwd)/Telegram/Resources/art/icon256.png"
  [[ -f $art ]] && install -Dm 644 "$art" "$OPT/aethergram.png" && icon="$OPT/aethergram.png"
else
  need gh
  dl="$(mktemp -d)"; trap 'rm -rf "$dl"' EXIT
  gh release download -R "$REPO" -D "$dl"
  for a in "$dl"/*.tar.* "$dl"/*.tgz; do [[ -f $a ]] && tar -xf "$a" -C "$dl"; done
  src="$(find "$dl" -type f \( -name Aethergram -o -name Telegram \) | head -n1)"
  [[ -n $src ]] || { echo "no Aethergram/Telegram binary in the latest $REPO release" >&2; exit 1; }
fi
install -m 755 "$src" "$BIN.new" && mv -f "$BIN.new" "$BIN"
ln -sfn "$BIN" "$HOME/.local/bin/aethergram"
echo "  $BIN"

echo "== desktop entry"
cat > "$D/applications/$APPID.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Aethergram
Comment=Unofficial Telegram client
Exec=$BIN -- %u
Icon=$icon
Terminal=false
Categories=Chat;Network;InstantMessaging;Qt;
MimeType=x-scheme-handler/tg;x-scheme-handler/tonsite;
Keywords=tg;chat;im;messaging;messenger;sms;telegram;
SingleMainWindow=true
X-KDE-Wayland-Interfaces=org_kde_kwin_blur
EOF
command -v update-desktop-database >/dev/null && update-desktop-database -q "$D/applications" || true

echo "== palettes and themes"
python3 "$ROOT/theme/generators/build_telegram.py"
install -m 755 "$ROOT/system/aether-accent-sync" "$HOME/.local/bin/aether-accent-sync"
install -m 755 "$ROOT/system/aether-mode-sync" "$HOME/.local/bin/aether-mode-sync"
"$HOME/.local/bin/aether-accent-sync"
echo "Aethergram is installed: run aethergram (or find it in the launcher)."
