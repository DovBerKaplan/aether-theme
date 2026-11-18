# Aether

A desktop layer for **KDE Plasma 6** (Wayland): a dark, blurred, rounded look, plus two small programs that replace the top panel and the notification banners.

| Part | What it is | Where |
|---|---|---|
| **Theme** | Color schemes (Glass = dark, Serenity = light, switching by time of day), Kvantum widget style, Plasma desktop theme, global themes, Konsole profile, wallpapers | `theme/` |
| **Island** | The top bar. Hidden until the pointer touches the top edge, then a full-width bar with a small notch (search, power). A click on the clock side opens a large panel: media, Wi-Fi, Bluetooth, sound, timer, volume, brightness | `components/island/` |
| **Dock** | The app bar, hidden until the pointer touches the bottom edge (horizontal pill) or the left edge (vertical pill). The island's dark glass, rim and grain; pinned and running apps with a quiet dot | `components/dock/` |
| **Toasts** | Notification cards that drop from the top edge. A separate program: it only listens, Plasma stays the notification server | `components/toasts/` |
| **Lens** | Circle to Search for the desktop: `Win+G`, or hold the dock's glass. Freezes the screen; circle or tap to search it on Google, send it to Google Lens, translate it (or the whole screen in place) or copy the text. OCR is local (tesseract, Hebrew + English) | `components/lens/` |
| **Login** | SDDM login screen in the same material | `login/` |
| **System** | Windows-style keyboard shortcuts, touchpad gestures, panel layout, light/dark sync | `system/` |
| **Direction** | Per-app RTL/LTR launch rules: run any app Hebrew-RTL or force English-LTR; dock, KRunner, xdg-open and Flatpak all honor the rules | `system/direction/` |

Both components are Qt 6 / QML apps (C++ for the window and system bits) running as systemd **user services**. They draw with real KWin blur, so they need a Wayland session with KWin.

## Quick start

```bash
git clone <this repo> aether && cd aether
make install        # backs up your KDE settings first, then installs everything for your user
```

Prerequisites, build dependencies and what each step changes: **[docs/INSTALL.md](docs/INSTALL.md)**.
Undo: `make uninstall` (services) and `make restore` (KDE settings from the backup).

## Direction rules

Every app launches exactly as the system launches it unless a rule says otherwise, so newly installed applications need nothing. A rule applies at the app's next launch.

```bash
make direction-install
aether-direction set dolphin rtl    # Hebrew UI, RTL layout (date/number formats stay en_IL)
aether-direction set kate ltr       # force English/LTR even if defaults change later
aether-direction unset dolphin      # back to system default
aether-direction doctor             # what is covered, how, and what can't be
```

Rules shadow the application's .desktop file through `~/.local/share/applications`, so KRunner, the dock, xdg-open and file associations all follow them; the original file is backed up and restored by `unset`. `sync` refreshes the overrides after an app update changes its launcher.

## Layout of the repository

```
components/   island/  toasts/  shared/AetherShared/   Qt apps and the QML module they share
theme/        generators/ (Python)  vendor/  icons/    the theme is *generated*; output goes to theme/generated/ (not in git)
login/        aether-lock/                              SDDM theme
plasmoids/    org.aether.appname/
system/       shortcuts/  gestures/  layout.js  ...      per-user desktop configuration
install/      install.sh  install-island.sh  backup.sh  restore.sh  ...
tools/        pointer-test.py                           a virtual mouse for UI tests
docs/         INSTALL, ARCHITECTURE, CONTRIBUTING, DOCK-SPEC, history/
```

`make help` lists every target. To understand how the pieces fit, read **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**; to work on the code, **[docs/CONTRIBUTING.md](docs/CONTRIBUTING.md)**.

## Status

Personal project, used daily on KDE neon (Plasma 6.8, Wayland, one 1920x1080 screen). Known gaps: no app menus in the island (they return to each window), no tray icons of other apps, single-screen assumptions in a few places, Hebrew/English only tested.

## Credits

Aether is a thin layer over KDE - almost everything hard is a ready-made project wearing the glass:

- **Plasma / KWin** — the desktop this lives in: blur through KWindowEffects, **KWin Custom Tiling** (`Win+Z` / `Win+T`) arranges the terminal windows and everything else on screen, and KWin scripting seats the console's terminals (a pattern proven by the island's media seat).
- **Konsole + tmux** — every terminal is a Konsole window wearing the Aether profile; tmux on each server (and locally) keeps sessions alive across drops, crashes and reboots.
- **OpenSSH** — ControlMaster multiplexing (one authenticated socket per host, so repeats are instant), BatchMode for the background pollers, and sftp batch mode driving the file browser.
- **Kate + KIO (kio_sftp) + Dolphin** — remote files open and save straight over `sftp://`, folders open in Dolphin, all from the shelf.
- **Docker CLI / kubectl** — container and pod discovery, start/stop actions, log streams and death events.
- **NetworkManager, KWallet, freedesktop notifications** — reachability, secrets and the toast pipeline.

Design references: the resting tab and pull-out drawer are an homage to the **OxygenOS Smart Sidebar**; the per-connection cards follow **MobaXterm**'s session panel and **Termius**' SFTP UX; the files explorer aims at **VS Code**'s Remote Explorer rather than a desktop file manager.

## License

GPL-3.0-or-later. Third-party notices in [NOTICE](NOTICE).
