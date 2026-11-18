# Architecture

Aether has two kinds of parts: things that are **generated** into your desktop configuration (the theme) and **programs** that run (the island, toasts, dock, console and lens).

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

**Light/dark switching:** off by default. The Theme tile cycles dark → light → by-hours; a mode picked by hand writes the scheme and turns KDE's `AutomaticLookAndFeel` off, so the clock never overrides a deliberate choice. The by-hours mode registers the two Global Themes as KDE's dark/light pair — KDE re-evaluates only at its next transition (verified: the key alone flips nothing), so the tile also applies the hour-appropriate scheme immediately, using Night Color's fixed times when set (else dusk 18:00 / dawn 06:00). `system/aether-mode-sync` (a systemd path unit on `kdeglobals`) keeps Kvantum and Konsole in step with the active color scheme.

**Frames and blur:** KSvg builds panel and popup backgrounds from 9-slice SVGs. `build_frames.py` draws them with Bézier curves only (KSvg sizes arcs wrongly), uses filled shapes instead of strokes, and gives every frame zero insets so blur covers the whole shape.

**The dock** (`components/dock/`, service `aether-dock`): two layer-shell surfaces (bottom, left), hidden at rest and revealed by touching their edge, in the island's material. Tasks come from `org.kde.taskmanager` (KWin grants the window list through `org.aether.dock.desktop`); the row is ordered in QML (pinned, hairline, free windows). Pins: `~/.config/aetherdockrc`. No Plasma panel exists; `system/layout.js` only clears them.

## Island (`components/island`)

One layer-shell window (overlay layer, anchored to the top edge). Written in C++ (window, DBus, system data) and QML (everything visible).

```
IslandController (main.cpp)   window size, blur + input region, keyboard mode, DBus org.aether.Island
SystemInfo.h                  battery (sysfs), volume (wpctl), network (nmcli), Bluetooth (bluetoothctl), brightness (PowerDevil)
MediaController.h             MPRIS players over DBus (metadata, progress, seek via SetPosition, Raise)
SearchEngine.h                the launcher engine: KRunner's own runner plugins loaded in-process (KF6::Runner), one ranked list
UsageIndex.h                  usage index: kactivitymanagerd stats, Chromium/Chrome history, .desktop scan — tier-first ranking
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

**The launcher.** The notch's search seat is a mode of the island (`qml/SearchHost.qml`): typing queries `SearchEngine.h`, which runs KRunner's own runner plugins in-process and merges them with `UsageIndex.h` — kactivitymanagerd statistics, a Chromium/Chrome history database and a `.desktop` scan — into one tier-ranked list (used-first apps, then calculator/file/bookmark results). Suggestions appear as you type, Enter launches, the island closes on run. Without kamd or a Chromium profile it quietly degrades to installed apps and math.

**Bluetooth tether failover** (`TetherController.h`). One paired device is marked "Fallback router" from its Bluetooth detail page; when NetworkManager loses the internet the island connects it over BlueZ (`Network1.Connect("nap")`) and activates the `phone-tether` NM profile on bnep0 — its route metric (50) sits below the wifi's (600), so traffic moves with no route surgery and no root. The real upstream is probed while riding; when it answers twice the tether drops and the wifi takes over by itself. Retries are silent (30 s → 5 min backoff); only successful transitions raise an activity card. Details and UI states in PANELS-SPEC.md §5.

**Media backend - YouTube Music only.** The song card is permanent (playing, paused or a resting 'Nothing playing' state) and is the entry to media mode: the island grows into a large panel whose middle is a seat for the Pear window (frameless, thin uniform bezel, no chrome above the app). The window is owned by a persistent KWin script, `components/island/kwin/aether-media` (installed as a KWin package and also loaded by the island when run from the source tree): it hides the window from the moment it maps, routes the tray icon or a second launch into the island instead of a floating window, and keeps it out of the taskbar, switcher and pager (with the `aether-media` window rule). The island fires two keyless global shortcuts over kglobalaccel (`Aether Media Show` / `Aether Media Hide`); the script answers through `org.aether.Island` (`mediaSeat`, `MediaWindowReady`, `MediaWindowMissing`, `MediaFocusLost`, `Media`). The window never moves, resizes or fades while shown - the glass does all the motion: the seat opens as frosted glass, clears once the window is ready and the spring has landed, and frosts over again before anything folds. It closes only deliberately (click outside, the handle, wheel up, Win+N, or another window taking focus), never on pointer-leave. Pear Desktop (the maintained fork of th-ch/youtube-music), unpacked under `~/.local/opt/pear-desktop` with `appVisible: false` — it needs no root, blocks ads client-side via its `adblocker` plugin and controls through `shortcuts` (MPRIS, polled asynchronously so a busy player can't stall the island). Config: `~/.config/YouTube Music/config.json`; autostart: `system/pear-desktop.desktop` → `~/.config/autostart/`.

## Toasts (`components/toasts`)

A second, independent program. It **monitors** `org.freedesktop.Notifications.Notify` (via `busctl monitor --json`). The notification server itself is the island: a silent `NotificationSink` in `main.cpp` owns `org.freedesktop.Notifications`, accepts every call and shows nothing - aether-toasts and the island's history are the only notification UI, so no third-party banner can ever appear. To avoid a second banner it holds an `Inhibit` while running, and takes it again whenever the server restarts. Critical notifications are shown by the server even when inhibited unless `CriticalInDndMode=false`, which `install.sh` sets. Stop the program and the server's banners return.

**Where cards land.** Before spawning a card the monitor asks the island over DBus (`org.aether.Island` `mode()`/`bottom()`): while the island's double bar is open, no card is spawned at all — the history list inside the island shows it there; otherwise the card drops just below the island's current glass edge (tab, island, or media panel), 10 px under it.

## Lens (`components/lens`)

A resident program (`aether-lens`, DBus `org.aether.Lens /Lens`: `Activate`, `Hide`, `Toggle`) that stays hidden until asked: `Win+G`, or a 500 ms hold on the dock's empty glass. `Activate` captures the screen through KWin's `ScreenShot2` (allowed by `X-KDE-DBUS-Restricted-Interfaces` in `org.aether.lens.desktop`, Spectacle as fallback), shows it in a full-screen layer-shell overlay, and runs `tesseract -l heb+eng` on it in the background so a tap on a word is instant. Drawing or tapping makes a selection; the sheet offers web search, Google Lens (a local HTML page posts the crop to lens.google.com), translation (Google's public web endpoint; the screen mode lays translated lines over the originals on the sampled background colour) and copy (`wl-copy`). Text features need `sudo apt install tesseract-ocr tesseract-ocr-heb`. A tap can also land on a whole UI element: `A11y.cpp/h` asks the AT-SPI accessibility bus for the exact rectangle under the point (toolkits that publish their widgets answer with real button/paragraph bounds), and `segmenter/lens_segment.py` — an optional, separate local process running MobileSAM via ultralytics — segments the object under the point on the frozen frame (model and pip packages are not installed by `make install`; see docs/INSTALL.md).

## Console (`components/console`)

The third piece of glass: a shelf that slides out from the right edge (`Win+C`, or the island's resting tab) holding terminals, files and servers. Sources: `ConsoleController.h` (DBus `org.aether.Console /Console`, window sizing, toggle), `Discovery.h` (SSH reachability polling and docker/podman/kubectl discovery over one ControlMaster connection per host), `Sftp.h` (the file browser: sftp batch mode over the same multiplexed socket), `SshConfig.h` (imports `~/.ssh/config` host entries), `SessionStore.h` (sessions in QSettings arrays — reading them needs the explicit `size=`), `Launcher.h` (a Konsole per terminal seat; tmux on the host, auto-installed over ssh when missing), `LogStream.h` (docker/kubectl/journalctl tails, ring-buffered). The QML is split into panes and cards (`Workspace.qml`, `Pane.qml`, `HomeView.qml`, `FilesView.qml`, …) around `SplitModel.js`, the split/pane tree — the one piece with a unit test (`tests/split-model.test.js`, run by `make check`). The terminal windows are Konsole windows seated in a hole in the shelf's glass by the KWin script `aether-console-seat` — the same pid-matched handshake as the island's media seat. Background life: reconnects, crash toasts and an orange status dot per host.

## Shared QML (`components/shared/AetherShared`)

`Theme` (colors, fonts, grain path) and `CardSurface` (the card material). Both programs `import AetherShared`; the install step copies the module to `~/.local/share/aether/shared`, and a development build finds it in the source tree.

## Installation flow

`install/install.sh` → backup → generate theme → copy files → `install-island.sh` (cmake build + install to `~/.local`, write user units) → windows-shortcuts → panel layout (`system/layout.js` through plasmashell scripting).

## Interface language

`AetherShared/I18n.qml` (singleton) holds the language (`lang`, saved in `~/.config/aetherislandrc` under `[Interface] Language`, set from the button in the bar) and two functions: `I18n.tr("English text")` and `I18n.f("%1 connected", n)`. The English text is the key and the fallback; Hebrew lives in `strings_he.js`. Both functions read `lang`, so every binding using them re-evaluates when it changes - no restart. To add a string: write it in QML as `I18n.tr("...")`, add the Hebrew to `strings_he.js`. To add a language: add it to `I18n.languages` and give it a dictionary. Text from the system (network and device names, notification content) is never translated.

Right-to-left: the island's root sets `LayoutMirroring` from `I18n.rtl`, so anchors, `Row`/`Grid`/`Flow` and text alignment mirror by themselves. Code that positions by explicit `x` (tile slots, switch thumb, slider fill, segmented thumb) flips on `I18n.rtl` itself; the media card and battery icon opt out and stay left-to-right. Inter has no Hebrew, so `main.cpp` substitutes Noto Sans Hebrew for it.

## Connections: switching, auto-connect, and what is never forgotten

The Wi-Fi and Bluetooth panels talk to NetworkManager and BlueZ directly over D-Bus (`NetworkModel.h`, `BluetoothModel.h`). Four rules hold everywhere:

1. **A failed switch never leaves you offline.** Before a join, `snapshotPrevious()` remembers the active connection; `failJoin()`, `cancel()` and the 30 s join timeout call `restorePrevious()`, which re-activates it. Switching to a network that is out of range is refused up front (`connectTo`). "Need auth" is normal for a split second while a stored password is fetched; if it lasts and the island has no password to give, it gives up after 4 s (`needAuthGaveUp`). For an automatic attempt that nobody started it waits 8 s, drops it so NetworkManager can try the next network, posts one toast and marks the row "Password needed".
2. **A failed attempt changes nothing that was saved.** A new password goes into a *new* profile created with `AddAndActivateConnection2` and `persist=memory`, copied from the old one's settings. Only when the connection works is it saved (`Save`) and the old profile deleted; on failure it is deleted and the saved profile was never touched. New and re-saved passwords are system-owned (`psk-flags 0`): no wallet, no prompt that may never appear. Passwords are never logged or put on a command line.
3. **Disconnecting is not forgetting.** The disconnect icon only disconnects (`disconnectActive`: it also drops the "put the old network back" memory). The saved profile, its password and a Bluetooth pairing stay; only the explicit two-tap "Forget" removes them. Nothing reconnects a network the user disconnected until they pick one.
4. **Known things connect by themselves, unless the user says otherwise.**
   - *Wi-Fi:* NetworkManager does the connecting. Once per start (`housekeeping`, a few seconds in) the island turns auto-connect on for any saved profile that has it off, except those the user turned off in the island (`[Network] ManualUuids` in `~/.config/aetherislandrc`), and re-saves wallet-owned passwords as system-owned (`migrateToSystemOwned`: read once while the wallet is open, written back, read back to verify, rolled back if the check fails). The per-network switch (`setAutoconnect`) uses `nmcli connection modify`, because a raw `Update` built from `GetSettings` would drop the password - `GetSettings` never returns secrets.
   - *Bluetooth:* an engine that runs whether or not the panel is open (`autoTick`, `attempt`). Every paired, unblocked device (`eligible`) reconnects, one at a time, unless its "Connect automatically" switch is off (`setAutoConnect`, `[Bluetooth] Manual` = addresses) or the user disconnected it (until they connect it again). A device that does not answer is retried after 30 s, 1 min, 2 min, then every 5 min. Adapter power-on, resume from sleep (`onSleep`, login1 `PrepareForSleep`) and a link that drops by itself start the schedule over. No background discovery: `Connect` pages the device itself. Each attempt logs one line to the journal (`bluetooth auto-connect: ...`).

Where to look: `connectTo`, `snapshotPrevious`, `restorePrevious`, `failJoin`, `needAuthGaveUp`, `housekeeping`, `migrateToSystemOwned`, `setAutoconnect` in `NetworkModel.h`; `autoTick`, `eligible`, `attempt`, `setAutoConnect`, `onSleep` in `BluetoothModel.h`.
