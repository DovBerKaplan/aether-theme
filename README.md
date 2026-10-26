# Aether

A desktop layer for **KDE Plasma 6** (Wayland): a dark, blurred, rounded look, plus two small programs that replace the top panel and the notification banners.

| Part | What it is | Where |
|---|---|---|
| **Theme** | Color schemes (Glass = dark, Serenity = light, switching by time of day), Kvantum widget style, Plasma desktop theme, global themes, Konsole profile, wallpapers | `theme/` |
| **Island** | The top bar. Hidden until the pointer touches the top edge, then a full-width bar with a small notch (search, power). A click on the clock side opens a large panel: media, Wi-Fi, Bluetooth, sound, timer, volume, brightness | `components/island/` |
| **Toasts** | Notification cards that drop from the top edge. A separate program: it only listens, Plasma stays the notification server | `components/toasts/` |
| **Login** | SDDM login screen in the same material | `login/` |
| **System** | Windows-style keyboard shortcuts, touchpad gestures, panel layout, light/dark sync | `system/` |

Both components are Qt 6 / QML apps (C++ for the window and system bits) running as systemd **user services**. They draw with real KWin blur, so they need a Wayland session with KWin.

## Quick start

```bash
git clone <this repo> aether && cd aether
make install        # backs up your KDE settings first, then installs everything for your user
```

Prerequisites, build dependencies and what each step changes: **[docs/INSTALL.md](docs/INSTALL.md)**.
Undo: `make uninstall` (services) and `make restore` (KDE settings from the backup).

## Layout of the repository

```
components/   island/  toasts/  shared/AetherShared/   Qt apps and the QML module they share
theme/        generators/ (Python)  vendor/  icons/    the theme is *generated*; output goes to theme/generated/ (not in git)
login/        aether-lock/                              SDDM theme
plasmoids/    org.aether.appname/
system/       shortcuts/  gestures/  layout.js  ...      per-user desktop configuration
install/      install.sh  install-island.sh  backup.sh  restore.sh  ...
tools/        pointer-test.py                           a virtual mouse for UI tests
docs/         INSTALL, ARCHITECTURE, CONTRIBUTING, history/
```

`make help` lists every target. To understand how the pieces fit, read **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**; to work on the code, **[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md)**.

## Status

Personal project, used daily on KDE neon (Plasma 6.8, Wayland, one 1920x1080 screen). Known gaps: no app menus in the island (they return to each window), no tray icons of other apps, single-screen assumptions in a few places, Hebrew/English only tested.

## License

GPL-3.0-or-later. Third-party notices in [NOTICE](NOTICE).
