#!/usr/bin/env bash
# Dress the ordinary apps in the Aether line: Kvantum for Qt/KDE apps (frosted frame, crisp content),
# the Aurorae titlebar, the colour schemes, Konsole, GTK (Breeze-GTK on our colours) and the KDE
# Flatpaks - then keep them on the island's accent (aether-accent-sync, on every aetherislandrc
# change) and on its light/dark mode (aether-mode-sync, on every kdeglobals change).
#   install-apps.sh          generate, install, apply
# Backs up the KDE config first (install/backup.sh). No sudo. Open apps restyle when restarted.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GEN="$ROOT/theme/generated"
D="$HOME/.local/share"
T="$D/aether-apps"            # the generated themes with the accent placeholder, see aether-accent-sync
need() { command -v "$1" >/dev/null || { echo "missing $1" >&2; exit 1; }; }
need kwriteconfig6; need kreadconfig6; need qdbus6; need python3

echo "== backup"
"$ROOT/install/backup.sh"

echo "== generate"
for g in build_colors build_kvantum build_aurorae build_lnf_konsole; do
  python3 "$ROOT/theme/generators/$g.py" >/dev/null
done

echo "== install"
mkdir -p "$T" "$D/color-schemes" "$D/konsole" "$D/plasma/look-and-feel" "$D/aurorae/themes" \
         "$HOME/.config/Kvantum" "$HOME/.local/bin" "$HOME/.config/systemd/user"
for kind in kvantum aurorae color-schemes; do
  rm -rf "${T:?}/$kind"; cp -r "$GEN/$kind" "$T/$kind"
done
cp "$GEN"/konsole/*-mark.png "$D/konsole/"
for f in "$GEN"/konsole/*.colorscheme; do sed "s|@MARK_DIR@|$D/konsole|" "$f" > "$D/konsole/$(basename "$f")"; done
[[ -f "$D/konsole/Aether.profile" ]] || cp "$GEN/konsole/Aether.profile" "$D/konsole/"
for p in "$GEN"/look-and-feel/*; do rm -rf "$D/plasma/look-and-feel/$(basename "$p")"; cp -r "$p" "$D/plasma/look-and-feel/"; done
install -m 755 "$ROOT/system/aether-mode-sync" "$HOME/.local/bin/aether-mode-sync"
install -m 755 "$ROOT/system/aether-accent-sync" "$HOME/.local/bin/aether-accent-sync"

echo "== accent sync service"
cat > "$HOME/.config/systemd/user/aether-accent-sync.service" <<EOF
[Unit]
Description=Carry the Aether Island's accent into Kvantum, the titlebar, Konsole and the colour schemes
StartLimitIntervalSec=0

[Service]
Type=oneshot
ExecStart=$HOME/.local/bin/aether-accent-sync
EOF
cat > "$HOME/.config/systemd/user/aether-accent-sync.path" <<EOF
[Unit]
Description=Watch the Aether Island's settings for accent changes
StartLimitIntervalSec=0

[Path]
PathChanged=$HOME/.config/aetherislandrc

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now aether-accent-sync.path >/dev/null 2>&1

echo "== Konsole: the terminal is content - near-opaque, blurred behind"
kwriteconfig6 --file konsolerc --group "Desktop Entry" --key DefaultProfile Aether.profile
kwriteconfig6 --file "$D/konsole/Aether.profile" --group General --key TerminalMargin 18

echo "== prompt: the two-line Aether prompt in bash"
install -Dm 644 "$ROOT/system/aether-prompt.sh" "$D/aether/prompt.sh"
grep -qs 'aether/prompt.sh' "$HOME/.bashrc" \
  || printf '\n# Aether prompt (install/install-apps.sh)\n[ -f "$HOME/.local/share/aether/prompt.sh" ] && . "$HOME/.local/share/aether/prompt.sh"\n' >> "$HOME/.bashrc"

echo "== titlebar: round buttons on the left, macOS order (close, minimize, maximize)"
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft XIA
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight ""

echo "== KDE Flatpaks (Dolphin, Konsole, Gwenview ...)"
# A sandboxed Qt app sees neither the host's Kvantum style nor its themes: the style comes from the
# org.kde.KStyle.Kvantum runtime extension, the themes through a read-only filesystem override.
if command -v flatpak >/dev/null; then
  apps=$(flatpak list --app --columns=application,runtime 2>/dev/null | awk '$2 ~ /^org\.kde\.Platform\// {print $1}')
  for app in $apps; do
    flatpak override --user --filesystem=xdg-config/Kvantum:ro --env=QT_STYLE_OVERRIDE=kvantum "$app"
    echo "  $app"
  done
  for branch in $(flatpak list --app --columns=runtime 2>/dev/null | sed -n 's|^org\.kde\.Platform/[^/]*/||p' | sort -u); do
    flatpak info org.kde.KStyle.Kvantum//"$branch" >/dev/null 2>&1 \
      || echo "  note: Flatpak apps on KDE runtime $branch need the Kvantum style: flatpak install --user flathub org.kde.KStyle.Kvantum//$branch"
  done
fi

echo "== apply"
"$HOME/.local/bin/aether-accent-sync"
"$HOME/.local/bin/aether-mode-sync" || true
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
echo "Apps are dressed. Restart open apps (or log out and in) to pick up Kvantum."
