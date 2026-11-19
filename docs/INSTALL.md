# Installing Aether

## Requirements

- KDE Plasma 6 on **Wayland** with KWin (tested: KDE neon, Plasma 6.8). All five
  programs draw with layer-shell and KWin's blur protocol — X11 will not work.
- Session tools the programs read: PipeWire with `wpctl`, NetworkManager
  (`nmcli`), BlueZ (`bluetoothctl`), PowerDevil (brightness), `qdbus6` (install
  and shortcuts), `kdialog`; `spectacle` is the fallback screen capture.
- Fonts: **Inter** and **JetBrainsMono Nerd Font** — `make install` fetches them
  automatically into `~/.local/share/fonts` (or run `make fonts`; already-present
  families are skipped). Icons: **Papirus** recommended.
- Python 3.11+ with `Pillow` (theme generators) and `python3-dbus` + `PySide6`
  (the Windows-style shortcut tool).
- `node`, only for `make check` (script syntax checks + the console split-model
  test).

## Build dependencies (all five programs)

```bash
sudo apt install cmake ninja-build extra-cmake-modules \
  qt6-base-dev qt6-declarative-dev qt6-wayland-dev \
  kf6-kwindowsystem-dev kf6-krunner-dev \
  liblayershellqtinterface-dev \
  libatspi2.0-dev libglib2.0-dev qt6-shadertools
```

(Package names are for KDE neon / Ubuntu 24.04; other distributions use
equivalent `-devel` packages. `kf6-krunner-dev` is the island's search engine;
`libatspi2.0-dev` is lens's element picking; `qt6-shadertools` (`qsb6`) compiles
the wallpaper's shader.)

## Install

```bash
make install
```

This, in order: backs up your KDE config (`backups/`), generates the theme and
installs it into `~/.local/share` and `~/.config`, installs the per-app
direction rules and the light/dark sync service, builds and starts **five** user
services — `aether-island`, `aether-toasts`, `aether-dock`, `aether-console`,
`aether-lens` (from now on they start with the graphical session) — turns off
the global menu, sets the Windows-style shortcuts, and removes your Plasma
panels (`system/layout.js`; the top bar is the island, the bottom/left dock is
the `aether-dock` service). The theme starts dark; time-of-day switching is
off until you turn it on from the island's Theme tile. **It changes your
desktop layout**, so read `install/install.sh` first if that worries you.

Keys you get: `Win+N` (island), `Win+C` (console shelf), `Win+G` (lens).

## Runtime dependencies, per component

Nothing crashes when a tool is missing — the table says what you lose.

| Component | Needs | Without it |
|---|---|---|
| Island | `wpctl`, `nmcli`, `bluetoothctl`, PowerDevil | the matching rows (volume, Wi-Fi, Bluetooth, brightness) go quiet |
| Island | `kdeconnect-cli` (KDE Connect) | the phone/card widget stays hidden |
| Island | KRunner plugins (in Plasma by default), `kactivitymanagerd`, a Chromium/Chrome profile | search still works (apps, calculations, files); fewer ranked results |
| Toasts, dock | a normal Plasma session (`org.kde.taskmanager`, notifications) | — |
| Console | `ssh` + `sftp`, `konsole`, `tmux` | the server shelf; tmux is auto-installed on the remote host (ssh + sudo) when missing |
| Console | `docker` or `podman`, `kubectl` | the containers/pods lists and their actions |
| Console | `kate`, `dolphin` | the "open file" / "open folder" actions |
| Lens | `tesseract-ocr tesseract-ocr-heb`, `wl-clipboard` | OCR and copy disabled (the UI says so and offers the install command) |
| Lens | the optional ML stack below | tap-to-segment disabled; circling, search, translate still work |

## Optional: lens tap-to-segment (MobileSAM)

Tap-to-object runs a resident local Python helper — a separate process, no
linking, never online at run time:

```bash
pip install ultralytics                       # pulls torch + opencv
mkdir -p ~/.local/share/aether-lens/models
wget -O ~/.local/share/aether-lens/models/mobile_sam.pt \
  https://github.com/ultralytics/assets/releases/download/v8.2.0/mobile_sam.pt
```

## Optional extras

| Command | What it does | Notes |
|---|---|---|
| `make install-login` | Aether Lock login screen | needs sudo; revert with `sudo install/install-sddm.sh --revert` |
| `make install-gestures` | 3-finger touchpad gestures (libinput-gestures) | needs your user in the `input` group, then log out and in |
| `make install-overview` | Glass restyle for the KWin Overview tiles | needs sudo; a kwin package update reverts it — run again (revert: `sudo install/install-overview.sh --restore`) |
| `make zcode-rtl-install` | RTL kit for the ZCode Electron app | only if you use that app |

## Optional: YouTube Music backend (no root needed)

The island's media card drives any MPRIS player. For YouTube Music with the real
recommendation algorithm and client-side ad blocking (works on a free account):

```bash
# unpack the official deb into your home (no sudo):
mkdir -p ~/.local/opt/pear-desktop
dpkg-deb -x youtube-music_<version>_amd64.deb ~/.local/opt/pear-desktop   # from pear-devs/pear-desktop releases
ln -sf ~/.local/opt/pear-desktop/opt/"YouTube Music"/youtube-music ~/.local/bin/pear-desktop
cp system/pear-desktop.desktop ~/.config/autostart/                       # starts with the session
~/.local/bin/pear-desktop --no-sandbox &                                  # --no-sandbox: unpacked Electron has no SUID helper
```

Then, inside the app: log in with your Google account and make sure the
**Ad blocker** and **Shortcuts** (media keys / MPRIS) plugins are enabled —
`~/.config/YouTube Music/config.json` → `plugins."adblocker"` / `"shortcuts"`.
The island picks the player up automatically. Unofficial client: ad blocking is
against YouTube's ToS and audio stays at the free tier's quality; if the blocker
breaks after a YouTube change, update the app or live with the ads.

## Undo

- `make uninstall`: stops and removes all five services, brings back the global
  menu and Plasma's notification banners.
- `make restore`: restores KDE settings (panels, theme, fonts) from the latest
  backup in `backups/`.
- Shortcuts: `python3 system/shortcuts/windows-shortcuts.py --revert`.

## What `make install` touches

`~/.config` (kdeglobals, kwinrc, kwinrulesrc, plasmanotifyrc, kded6rc,
Kvantum, konsole, systemd user units), `~/.local/share` (color schemes, Plasma
themes, look-and-feel, wallpapers, the `org.aether.appname` plasmoid, icons, the
programs' QML under `aether-*`), `~/.local/bin` (`aether-island`,
`aether-toasts`, `aether-dock`, `aether-console`, `aether-lens`,
`aether-mode-sync`, `aether-direction`, `aether-direction-run`, `aether-vibe`,
`aether-agent-run`). Nothing outside your home directory except the optional
login screen.
