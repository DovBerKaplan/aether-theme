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

echo "== fonts"
# Non-fatal: a machine without network still installs, just with fallback fonts.
if ! "$ROOT/install/fonts.sh"; then
  echo "warning: font fetch failed; run 'make fonts' later or install Inter and" >&2
  echo "         JetBrainsMono Nerd Font by hand" >&2
fi

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

echo "== cursor"
# The pointer speaks the island's language too: rounded jelly glass, vendored
# Bibata Ice v2.0.7 (ful1e5, GPL-3.0 - see NOTICE). Writing kcminputrc is enough:
# KWin applies the theme live, and X apps inherit it at the next login.
if command -v xz >/dev/null 2>&1; then
  [[ -d "$D/icons/Bibata-Modern-Ice" ]] || tar -xJf "$ROOT/install/cursors/Bibata-Modern-Ice.tar.xz" -C "$D/icons/"
  kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme Bibata-Modern-Ice
else
  echo "warning: xz missing; the pointer stays Breeze (install xz-utils)" >&2
fi
install -m 755 "$ROOT/system/aether-mode-sync" "$HOME/.local/bin/aether-mode-sync"
install -m 755 "$ROOT/system/vibe/aether-vibe" "$HOME/.local/bin/aether-vibe"
install -m 755 "$ROOT/system/agents/aether-agent-run" "$HOME/.local/bin/aether-agent-run"
mkdir -p "$D/plasma/plasmoids" "$D/icons/hicolor/scalable/apps"
for p in org.aether.appname; do rm -rf "$D/plasma/plasmoids/$p"; cp -r "$ROOT/plasmoids/$p" "$D/plasma/plasmoids/"; done
# The desktop wallpaper is a wallpaper plugin drawn at the screen's size; its shader is compiled here.
W="$D/plasma/wallpapers/org.aether.ribbons"
rm -rf "$W"; mkdir -p "$D/plasma/wallpapers"; cp -r "$ROOT/plasmoids/org.aether.ribbons" "$W"
qsb6 --glsl "100 es,120,150" --hlsl 50 --msl 12 -o "$W/contents/shaders/ribbons.frag.qsb" "$W/contents/shaders/ribbons.frag"
cp "$ROOT"/theme/icons/*.svg "$D/icons/hicolor/scalable/apps/"
# Aether Sink: our own open/close animation, a scripted KWin effect.
mkdir -p "$D/kwin/effects"
rm -rf "$D/kwin/effects/aether-close"; cp -r "$ROOT/system/aether-close" "$D/kwin/effects/"

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
# a look-and-feel apply leaks ColorScheme into kdedefaults AFTER kdeglobals was written,
# so watching only kdeglobals can miss the poison; watch both and clean it whenever either moves
PathChanged=$HOME/.config/kdedefaults/kdeglobals

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now aether-mode-sync.path

echo "== direction rules"
"$ROOT/system/direction/install-direction.sh"

echo "== fonts, KWin, desktops"
kwriteconfig6 --file kdeglobals --group General --key font "Inter Display,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
kwriteconfig6 --file kdeglobals --group General --key menuFont "Inter Display,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
kwriteconfig6 --file kdeglobals --group General --key toolBarFont "Inter Display,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
kwriteconfig6 --file kdeglobals --group General --key smallestReadableFont "Inter Display,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
kwriteconfig6 --file kdeglobals --group General --key fixed "JetBrainsMono Nerd Font,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
kwriteconfig6 --file kdeglobals --group WM --key activeFont "Inter Display,10,-1,5,600,0,0,0,0,0,0,0,0,0,0,1"
kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled true
kwriteconfig6 --file kwinrc --group Plugins --key contrastEnabled true
kwriteconfig6 --file kwinrc --group Effect-blur --key BlurStrength 14
# Light grain only: the surfaces should read as smooth blurred glass.
kwriteconfig6 --file kwinrc --group Effect-blur --key NoiseStrength 1
# Windows move like the island: Aether Sink opens like Scale and dives the
# window into its taskbar seat on close, magic-lamp liquid minimize (Squash
# shares the exclusive "minimize" group, so it steps aside), and a jelly
# wobble while dragging - tuned toward the drag curtain's spring (3.6/0.22).
kwriteconfig6 --file kwinrc --group Plugins --key scaleEnabled false
kwriteconfig6 --file kwinrc --group Plugins --key aether-closeEnabled true
kwriteconfig6 --file kwinrc --group Plugins --key squashEnabled false
kwriteconfig6 --file kwinrc --group Plugins --key magiclampEnabled true
kwriteconfig6 --file kwinrc --group Plugins --key wobblywindowsEnabled true
kwriteconfig6 --file kwinrc --group Effect-wobblywindows --key Stiffness 10
kwriteconfig6 --file kwinrc --group Effect-wobblywindows --key Drag 5
kwriteconfig6 --file kwinrc --group Effect-wobblywindows --key MoveFactor 15
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

echo "== theme pair registered (time-of-day switching stays off until the island's Theme tile turns it on)"
kwriteconfig6 --file kdeglobals --group KDE --key DefaultDarkLookAndFeel org.aether.glass.desktop
kwriteconfig6 --file kdeglobals --group KDE --key DefaultLightLookAndFeel org.aether.serenity.desktop

echo "== apply Glass"
plasma-apply-lookandfeel -a org.aether.glass.desktop
plasma-apply-desktoptheme AetherGlass >/dev/null
"$HOME/.local/bin/aether-mode-sync" || true
qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true  # absent on some X11 builds

echo "== apps: Kvantum, titlebar, Konsole, GTK, Flatpaks, accent sync"
"$ROOT/install/install-apps.sh"

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
    "desktops().forEach(function(d){d.wallpaperPlugin='org.aether.ribbons';});"
  "$HOME/.local/bin/aether-accent-sync" >/dev/null 2>&1 || true   # hand the wallpaper the island's accent and the mode right away
  "$HOME/.local/bin/aether-mode-sync" >/dev/null 2>&1 || true
fi

echo "Done. Log out and back in so every running app picks up Kvantum and the fonts."
