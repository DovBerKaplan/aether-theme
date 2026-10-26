# Architecture

Aether has two kinds of parts: things that are **generated** into your desktop configuration (the theme) and **programs** that run (the island and toasts).

## Theme (generated)

`theme/generators/*.py` produce everything into `theme/generated/` (git-ignored). `install/install.sh` copies the result into the user's KDE directories.

| Generator | Produces | Reads |
|---|---|---|
| `build_colors.py` | `.colors` schemes AetherGlass (dark) / AetherSerenity (light) | Stitch design tokens, written in the file |
| `build_kvantum.py` | Kvantum widget themes | `theme/vendor/whitesur-kvantum` (geometry), recolored |
| `build_desktoptheme.py` + `build_frames.py` | Plasma desktop theme `AetherGlass` | Breeze `default` from `/usr/share/plasma/desktoptheme`; panel, popup, tooltip and dock frames are drawn from scratch |
| `build_lnf_konsole.py` | two Global Themes, Konsole color schemes and profile | |
| `gen_wallpaper.py`, `gen_lock_wallpaper.py` | wallpapers, login backgrounds | |
| `gen_grain.py` | the grain texture shared by the island and toasts | |

The generators are deterministic: running them twice gives the same bytes (gzip timestamps are pinned).

**Light/dark switching:** the two Global Themes are registered for KDE's automatic day/night. `system/aether-mode-sync` (a systemd path unit on `kdeglobals`) keeps Kvantum and Konsole in step with the active color scheme.

**Frames and blur:** KSvg builds panel and popup backgrounds from 9-slice SVGs. `build_frames.py` draws them with Bézier curves only (KSvg sizes arcs wrongly), uses filled shapes instead of strokes, and gives every frame zero insets so blur covers the whole shape.

## Island (`components/island`)

One layer-shell window (overlay layer, anchored to the top edge). Written in C++ (window, DBus, system data) and QML (everything visible).

```
IslandController (main.cpp)   window size, blur + input region, keyboard mode, DBus org.aether.Island
SystemInfo.h                  battery (sysfs), volume (wpctl), network (nmcli), Bluetooth (bluetoothctl), brightness (PowerDevil)
MediaController.h             MPRIS players over DBus
qml/Island.qml                state machine: hidden -> bar -> large, pointer logic, window sizing
qml/NotchSurface.qml          the silhouette and material (see below)
qml/LargeIsland.qml           rows: media, toggles, timer, sliders; height follows content
qml/TimerState.qml            one countdown shared by the large island and the bar
```

**One path, three uses.** `NotchSurface.qml` builds the outline (a strip along the top edge with a notch hanging from its middle, joined by concave shoulders) as a list of path commands. The same list is drawn by QML, sent to C++ as the **blur region**, and used as the **input region**. They cannot disagree.

**State and window size.** The window is as large as the current state needs: a 2 px hot strip (hidden), the bar height, or the whole screen (large, so a click outside can close it). It grows *before* the shape animates open and shrinks *after* it closes.

**DBus** `org.aether.Island /Island`: `Peek`, `Expand`, `Hide`, `Toggle`. A launcher entry binds Win+N / Win+A to `Toggle`.

## Toasts (`components/toasts`)

A second, independent program. It **monitors** `org.freedesktop.Notifications.Notify` (via `busctl monitor --json`), so Plasma remains the notification server and keeps the history and do-not-disturb. To avoid a second banner it holds an `Inhibit` while running, and takes it again whenever Plasma's server restarts. Critical notifications are shown by Plasma even when inhibited unless `CriticalInDndMode=false`, which `install.sh` sets. Stop the program and Plasma's banners return.

## Shared QML (`components/shared/AetherShared`)

`Theme` (colors, fonts, grain path) and `CardSurface` (the card material). Both programs `import AetherShared`; the install step copies the module to `~/.local/share/aether/shared`, and a development build finds it in the source tree.

## Installation flow

`install/install.sh` → backup → generate theme → copy files → `install-island.sh` (cmake build + install to `~/.local`, write user units) → windows-shortcuts → panel layout (`system/layout.js` through plasmashell scripting).
