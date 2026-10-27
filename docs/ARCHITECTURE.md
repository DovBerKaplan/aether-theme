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

**The dock** (`components/dock/`, service `aether-dock`): two layer-shell surfaces (bottom, left), hidden at rest and revealed by touching their edge, in the island's material. Tasks come from `org.kde.taskmanager` (KWin grants the window list through `org.aether.dock.desktop`); the row is ordered in QML (pinned, hairline, free windows). Pins: `~/.config/aetherdockrc`. No Plasma panel exists; `system/layout.js` only clears them.

## Island (`components/island`)

One layer-shell window (overlay layer, anchored to the top edge). Written in C++ (window, DBus, system data) and QML (everything visible).

```
IslandController (main.cpp)   window size, blur + input region, keyboard mode, DBus org.aether.Island
SystemInfo.h                  battery (sysfs), volume (wpctl), network (nmcli), Bluetooth (bluetoothctl), brightness (PowerDevil)
MediaController.h             MPRIS players over DBus (metadata, progress, seek via SetPosition, Raise)
NotificationStore.h           watches Notify (like the toasts, without the Inhibit), keeps the last 30 in ~/.local/share/aether-island/notifications.json
qml/Island.qml                state machine: hidden -> bar -> large -> expanded, the pull curtain, pointer logic, window sizing
qml/NotchSurface.qml          the silhouette and material (see below)
qml/LargeIsland.qml           rows: media, toggles, timer, sliders; height follows content; the handle reports pull gestures
qml/NotificationList.qml      the expanded island's notification history (header, cards, empty state)
qml/NotificationCard.qml      one history entry: quieter than a toast, dismisses on click
qml/MediaCard.qml             now-playing card: artwork crossfade, ambient wash, hero transport
qml/MediaProgress.qml         slim seek bar: hover-grow track, mono time labels, drag-to-seek
qml/EqBars.qml                three-bar equalizer (dances while playing, fallback artwork)
qml/TimerState.qml            one countdown shared by the large island and the bar
```

**One path, three uses.** `NotchSurface.qml` builds the outline (a strip along the top edge with a notch hanging from its middle, joined by concave shoulders) as a list of path commands. The same list is drawn by QML, sent to C++ as the **blur region**, and used as the **input region**. They cannot disagree.

**State and window size.** The window is as large as the current state needs: a 2 px hot strip (hidden), the bar height, or the whole screen (large and expanded, so a click outside can close it). It grows *before* the shape animates open and shrinks *after* it closes.

**The pull curtain.** The three visible levels are one continuous gesture: dragging the handle (or the tab itself) moves the island's height 1:1 with the pointer and snaps on release to the nearest stop - bar, large, expanded - with completion from 30% of the way or a flick, so the full distance never has to be dragged. Holding the handle 350 ms opens the expanded island directly. The blur/input layout is event-driven (no polling timer): an idle island costs ~0.1% CPU.

**DBus** `org.aether.Island /Island`: `Peek`, `Expand`, `Pull`, `Hide`, `Toggle`. A launcher entry binds Win+N / Win+A to `Toggle`.

**Media backend - YouTube Music only.** The song card is permanent (playing, paused or a resting 'Nothing playing' state) and is the entry to media mode: the island grows into a large panel whose middle is a seat for the Pear window (frameless, thin uniform bezel, no chrome above the app). The window is owned by a persistent KWin script, `components/island/kwin/aether-media` (installed as a KWin package and also loaded by the island when run from the source tree): it hides the window from the moment it maps, routes the tray icon or a second launch into the island instead of a floating window, and keeps it out of the taskbar, switcher and pager (with the `aether-media` window rule). The island fires two keyless global shortcuts over kglobalaccel (`Aether Media Show` / `Aether Media Hide`); the script answers through `org.aether.Island` (`mediaSeat`, `MediaWindowReady`, `MediaWindowMissing`, `MediaFocusLost`, `Media`). The window never moves, resizes or fades while shown - the glass does all the motion: the seat opens as frosted glass, clears once the window is ready and the spring has landed, and frosts over again before anything folds. It closes only deliberately (click outside, the handle, wheel up, Win+N, or another window taking focus), never on pointer-leave. Pear Desktop (the maintained fork of th-ch/youtube-music), unpacked under `~/.local/opt/pear-desktop` with `appVisible: false` — it needs no root, blocks ads client-side via its `adblocker` plugin and controls through `shortcuts` (MPRIS, polled asynchronously so a busy player can't stall the island). Config: `~/.config/YouTube Music/config.json`; autostart: `system/pear-desktop.desktop` → `~/.config/autostart/`.

## Toasts (`components/toasts`)

A second, independent program. It **monitors** `org.freedesktop.Notifications.Notify` (via `busctl monitor --json`). The notification server itself is the island: a silent `NotificationSink` in `main.cpp` owns `org.freedesktop.Notifications`, accepts every call and shows nothing - aether-toasts and the island's history are the only notification UI, so no third-party banner can ever appear. To avoid a second banner it holds an `Inhibit` while running, and takes it again whenever the server restarts. Critical notifications are shown by the server even when inhibited unless `CriticalInDndMode=false`, which `install.sh` sets. Stop the program and the server's banners return.

**Where cards land.** Before spawning a card the monitor asks the island over DBus (`org.aether.Island` `mode()`/`bottom()`): while the island's double bar is open, no card is spawned at all — the history list inside the island shows it there; otherwise the card drops just below the island's current glass edge (tab, island, or media panel), 10 px under it.

## Shared QML (`components/shared/AetherShared`)

`Theme` (colors, fonts, grain path) and `CardSurface` (the card material). Both programs `import AetherShared`; the install step copies the module to `~/.local/share/aether/shared`, and a development build finds it in the source tree.

## Installation flow

`install/install.sh` → backup → generate theme → copy files → `install-island.sh` (cmake build + install to `~/.local`, write user units) → windows-shortcuts → panel layout (`system/layout.js` through plasmashell scripting).

## Interface language

`AetherShared/I18n.qml` (singleton) holds the language (`lang`, saved in `~/.config/aetherislandrc` under `[Interface] Language`, set from the button in the bar) and two functions: `I18n.tr("English text")` and `I18n.f("%1 connected", n)`. The English text is the key and the fallback; Hebrew lives in `strings_he.js`. Both functions read `lang`, so every binding using them re-evaluates when it changes - no restart. To add a string: write it in QML as `I18n.tr("...")`, add the Hebrew to `strings_he.js`. To add a language: add it to `I18n.languages` and give it a dictionary. Text from the system (network and device names, notification content) is never translated.

Right-to-left: the island's root sets `LayoutMirroring` from `I18n.rtl`, so anchors, `Row`/`Grid`/`Flow` and text alignment mirror by themselves. Code that positions by explicit `x` (tile slots, switch thumb, slider fill, segmented thumb) flips on `I18n.rtl` itself; the media card and battery icon opt out and stay left-to-right. Inter has no Hebrew, so `main.cpp` substitutes Noto Sans Hebrew for it.
