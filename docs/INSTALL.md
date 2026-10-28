# Installing Aether

## Requirements

- KDE Plasma 6 on **Wayland** with KWin (tested: KDE neon, Plasma 6.8). The island and toasts use layer-shell and KWin's blur protocol.
- Services/tools the island reads: PipeWire with `wpctl`, NetworkManager (`nmcli`), BlueZ (`bluetoothctl`), PowerDevil (brightness).
- Fonts: **Inter** and **JetBrainsMono Nerd Font** — `make install` fetches them
  automatically into `~/.local/share/fonts` (or run `make fonts`; already-present
  families are skipped). Icons: **Papirus** recommended.
- Python 3 with `Pillow` (wallpaper/texture generators) and `python3-dbus` + `PySide6` (shortcut tool).

## Build dependencies (island and toasts)

```bash
sudo apt install cmake ninja-build extra-cmake-modules \
  qt6-base-dev qt6-declarative-dev qt6-wayland-dev \
  kf6-kwindowsystem-dev liblayershellqtinterface-dev
```

(Package names are for KDE neon / Ubuntu 24.04; other distributions use equivalent `-devel` packages.)

## Install

```bash
make install
```

This, in order: backs up your KDE config (`backups/`), generates the theme, installs it into `~/.local/share` and `~/.config`, builds and starts the `aether-island` and `aether-toasts` user services, turns off the global menu, sets the Windows-style shortcuts, and replaces your panels with a bottom dock (the top bar is the island). **It changes your desktop layout**, so read `install/install.sh` first if that worries you.

Optional extras:

| Command | What it does | Notes |
|---|---|---|
| `make install-login` | Aether Lock login screen | needs sudo; revert with `sudo install/install-sddm.sh --revert` |
| `make install-gestures` | 3-finger touchpad gestures (libinput-gestures) | needs your user in the `input` group, then log out and in |

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

- `make uninstall`: stops and removes the services, brings back the global menu and Plasma's notification banners.
- `make restore`: restores KDE settings (panels, theme, fonts) from the latest backup in `backups/`.
- Shortcuts: `python3 system/shortcuts/windows-shortcuts.py --revert`.

## What `make install` touches

`~/.config` (kdeglobals, kwinrc, plasmanotifyrc, kded6rc, Kvantum, konsole, systemd user units), `~/.local/share` (color schemes, Plasma themes, wallpapers, plasmoid, icons), `~/.local/bin` (`aether-island`, `aether-toasts`, `aether-mode-sync`). Nothing outside your home directory except the optional login screen.
