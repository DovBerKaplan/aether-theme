#!/usr/bin/env bash
# Install the AetherOS theme for the current user and apply it.
#   install.sh            install + apply Glass (dark) + panels/widgets + auto day/night
#   install.sh --no-layout   skip replacing panels/widgets
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GEN="$ROOT/theme/generated"
LAYOUT=1
[[ "${1:-}" == "--no-layout" ]] && LAYOUT=0

need() { command -v "$1" >/dev/null || { echo "missing: $1" >&2; exit 1; }; }
need kwriteconfig6; need qdbus6; need plasma-apply-lookandfeel

if [[ ! -e /usr/lib/x86_64-linux-gnu/qt6/plugins/styles/libkvantum.so ]]; then
  echo "warning: Kvantum for Qt6 not found; app windows will stay opaque (install qt6-style-kvantum)" >&2
fi

echo "== backup"; "$ROOT/install/backup.sh"

echo "== build"
python3 "$ROOT/theme/generators/build_colors.py"
python3 "$ROOT/theme/generators/build_kvantum.py"
python3 "$ROOT/theme/generators/build_desktoptheme.py"
python3 "$ROOT/theme/generators/build_lnf_konsole.py"
[[ -d "$GEN/wallpaper/AetherOS/contents/images_dark" ]] || python3 "$ROOT/theme/generators/gen_wallpaper.py"

echo "== copy files"
D="$HOME/.local/share"
mkdir -p "$D/color-schemes" "$D/plasma/desktoptheme" "$D/plasma/look-and-feel" "$D/wallpapers" \
         "$D/konsole" "$HOME/.config/Kvantum" "$HOME/.local/bin" "$HOME/.config/systemd/user"
cp "$GEN"/color-schemes/*.colors "$D/color-schemes/"
rm -rf "$D/plasma/desktoptheme/AetherGlass"; cp -r "$GEN/desktoptheme/AetherGlass" "$D/plasma/desktoptheme/"
for p in "$GEN"/look-and-feel/*; do rm -rf "$D/plasma/look-and-feel/$(basename "$p")"; cp -r "$p" "$D/plasma/look-and-feel/"; done
rm -rf "$D/wallpapers/AetherOS"; cp -r "$GEN/wallpaper/AetherOS" "$D/wallpapers/"
cp "$GEN"/konsole/*.colorscheme "$D/konsole/"
[[ -f "$D/konsole/Aether.profile" ]] || cp "$GEN/konsole/Aether.profile" "$D/konsole/"
for k in "$GEN"/kvantum/*; do rm -rf "$HOME/.config/Kvantum/$(basename "$k")"; cp -r "$k" "$HOME/.config/Kvantum/"; done
install -m 755 "$ROOT/system/aether-mode-sync" "$HOME/.local/bin/aether-mode-sync"
mkdir -p "$D/plasma/plasmoids" "$D/icons/hicolor/scalable/apps"
for p in org.aether.appname; do rm -rf "$D/plasma/plasmoids/$p"; cp -r "$ROOT/plasmoids/$p" "$D/plasma/plasmoids/"; done
cp "$ROOT"/theme/icons/*.svg "$D/icons/hicolor/scalable/apps/"

echo "== mode sync service"
cat > "$HOME/.config/systemd/user/aether-mode-sync.service" <<EOF
[Unit]
Description=Sync Kvantum, Konsole and GTK/browser apps with the AetherOS light/dark theme
# a theme switch rewrites kdeglobals many times in a second
StartLimitIntervalSec=0

[Service]
Type=oneshot
ExecStart=$HOME/.local/bin/aether-mode-sync
EOF
cat > "$HOME/.config/systemd/user/aether-mode-sync.path" <<EOF
[Unit]
Description=Watch kdeglobals for AetherOS theme switches
StartLimitIntervalSec=0

[Path]
PathChanged=$HOME/.config/kdeglobals

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now aether-mode-sync.path

echo "== fonts, KWin, desktops"
kwriteconfig6 --file kdeglobals --group General --key font "Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
kwriteconfig6 --file kdeglobals --group General --key menuFont "Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
kwriteconfig6 --file kdeglobals --group General --key toolBarFont "Inter,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
kwriteconfig6 --file kdeglobals --group General --key smallestReadableFont "Inter,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
kwriteconfig6 --file kdeglobals --group General --key fixed "JetBrainsMono Nerd Font,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
kwriteconfig6 --file kdeglobals --group WM --key activeFont "Inter,10,-1,5,600,0,0,0,0,0,0,0,0,0,0,1"
kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled true
kwriteconfig6 --file kwinrc --group Plugins --key contrastEnabled true
kwriteconfig6 --file kwinrc --group Effect-blur --key BlurStrength 14
# Light grain only: the surfaces should read as smooth blurred glass.
kwriteconfig6 --file kwinrc --group Effect-blur --key NoiseStrength 1
# Notifications are shown by the aether-toasts service (install-island.sh); the old KWin
# slide effect is gone, so KDE's own popup effects are back to their defaults.
kwriteconfig6 --file kwinrc --group Plugins --key aether_notification_slideEnabled --delete
kwriteconfig6 --file kwinrc --group Plugins --key fadingpopupsEnabled --delete
kwriteconfig6 --file kwinrc --group Plugins --key slidingnotificationsEnabled --delete
rm -rf "$D/kwin/effects/aether_notification_slide"
kwriteconfig6 --file plasmanotifyrc --group Notifications --key PopupPosition TopCenter
# No shrinking timer line on banners (phones don't have one).
kwriteconfig6 --file plasmanotifyrc --group Notifications --key ShowPopupTimeout false
# Urgent notifications bypass do-not-disturb by default, which made Plasma show its own banner next to ours.
kwriteconfig6 --file plasmanotifyrc --group Notifications --key CriticalInDndMode false
kwriteconfig6 --file kwinrc --group Desktops --key Number 4
kwriteconfig6 --file kwinrc --group Desktops --key Rows 1
for i in 1 2 3 4; do kwriteconfig6 --file kwinrc --group Desktops --key "Name_$i" "Workspace $i"; done
kwriteconfig6 --file konsolerc --group "Desktop Entry" --key DefaultProfile Aether.profile

echo "== automatic day/night"
kwriteconfig6 --file kdeglobals --group KDE --key DefaultDarkLookAndFeel org.aether.glass.desktop
kwriteconfig6 --file kdeglobals --group KDE --key DefaultLightLookAndFeel org.aether.serenity.desktop
kwriteconfig6 --file kdeglobals --group KDE --key AutomaticLookAndFeel true

echo "== apply Glass"
plasma-apply-lookandfeel -a org.aether.glass.desktop
plasma-apply-desktoptheme AetherGlass >/dev/null
"$HOME/.local/bin/aether-mode-sync" || true
qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true  # absent on some X11 builds

echo "== island, toasts, global menu"
"$ROOT/install/install-island.sh"
# Apps show their own menu bar again; the Aether Island has no app menus.
kwriteconfig6 --file kded6rc --group Module-appmenu --key autoload false
qdbus6 org.kde.kded6 /kded org.kde.kded6.unloadModule appmenu >/dev/null 2>&1 || true
python3 "$ROOT/system/shortcuts/windows-shortcuts.py" 2>&1 | grep -v 'ERROR:dbus\|Introspect' || true

if [[ $LAYOUT == 1 ]]; then
  echo "== panels + widgets"
  qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$(cat "$ROOT/system/layout.js")"
  # Wallpaper on every desktop
  qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
    "desktops().forEach(function(d){d.wallpaperPlugin='org.kde.image';d.currentConfigGroup=['Wallpaper','org.kde.image','General'];d.writeConfig('Image','file://$D/wallpapers/AetherOS');});"
fi

echo "Done. Log out and back in so every running app picks up Kvantum and the fonts."
