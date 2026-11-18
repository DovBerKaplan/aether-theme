# Dock Spec — one-to-one with the Android 17 tablet taskbar

The goal, in one sentence: when you squint, the Aether dock should read as the
same object as the taskbar on the owner's Android 17 tablet (Material 3
Expressive) — a **floating glass pill of calm icons with a pinned|running
separator** — not as a "Plasma panel".

This document characterizes the reference, records what shipped, the decisions
taken along the way, and what is honestly left. Verified live against the
reference screenshot; see [dock-verification.png](dock-verification.png).

> **Final decision (2026-10-27, later):** the custom `org.aether.dock` task row
> was **retired** — over dark content its glass disappeared (icons floating on
> nothing) and the owner called it right. The dock is now **stock
> `org.kde.plasma.icontasks`** inside the same themed floating pill: KDE's own,
> maintained widget; the pill glass/scrim/frost remain the theme's job. The
> retired plasmoid itself is gone from the tree (`plasmoids/` today holds only
> `org.aether.appname`, the focused-app name widget). What that gives up
> vs the tablet: the pinned|running hairline and the dot/pill indicators —
> icontasks indicates running apps with its button states (`tasks.svgz`).

> **Rebuilt (2026-10-27, latest):** the dock is now the **`aether-dock` service**
> (`components/dock/`), no Plasma panel: two layer-shell surfaces built like the island, in the
> island's dark glass (rim + grain). It is **hidden at rest**; touching the **bottom** edge springs
> out a horizontal pill, touching the **left** edge a vertical one (one open at a time, ~180 ms to
> open, ~600 ms grace on leaving). Tasks come from `org.kde.taskmanager` (granted to the service
> by `org.aether.dock.desktop`, installed by `install-island.sh`); pinned apps first in pin order,
> then a hairline, then free windows; running = dot, focused = short pill. Pins live in
> `~/.config/aetherdockrc`; `qdbus6 org.aether.Dock /Dock org.aether.Dock.Show bottom|left` drives it.
> `system/layout.js` now only clears panels. Sections below describe the earlier panel versions.

---

## 1. The reference — the owner's Android 17 tablet taskbar

From the tablet reference screenshot (kept locally by the owner, not shipped;
pill zone rows ~2135–2325 of 3392×2400, pixel-profiled during calibration):

1. **Stadium silhouette.** Corner radius = half the bar's height, exactly.
   Floating clear of the screen edge, width fits the content (not full-width).
2. **One material rule.** Strong backdrop blur + one neutral scrim (~28 % the
   calibration landed on). No rim, no border, no drop shadow, no halo — blur
   alone separates the bar from the wallpaper.
3. **Pinned | running, with a separator.** The owner's tablet shows a thin
   vertical hairline with extra air on both sides between the pinned apps and
   the open-but-not-pinned apps. This is the one trait stock Plasma 6.8 cannot
   draw (verified against the icontasks binary).
4. **Even rhythm.** Equal gaps inside each group; icons ≈ 55–60 % of the bar's
   height with air above and below.
5. **Quiet indication.** A running app shows a small dot under its icon; the
   focused app's dot widens to a short pill. State lives in a 4 px detail, not
   in background fills.
6. **Physics motion.** Springy press-squish with a settle wobble (M3
   Expressive); hover is one tonal stadium layer and nothing else.

## 2. What ships today (all applied live)

| Piece | Value | Where |
|---|---|---|
| Pill geometry | height 56, radius 12 (modest corners — the owner took the full-stadium r=28 capsule off), floating, centered, `lengthMode: fit` | `system/layout.js` + `build_frames.py` |
| Material | scrim 0.28 (live-calibrated) + **frost 0.04** over KWin blur (strength 14); no rim, no shadow on translucent | `build_frames.py` → `panel-background.svgz` |
| Frost rationale | pure glass vanishes over dark windows; 0.04 white keeps the pill legible there and is imperceptible over bright wallpaper | same |
| Task row | **stock `org.kde.plasma.icontasks`** — KDE's own dock widget; pinned apps + running windows, its own hover/grouping/previews | `system/layout.js` |
| Pinned apps | curated (owner-delegated 2026-10-27): **ZCode, browser, VS Code, files, terminal**, usage-ordered. Settings unpinned (island search reaches it); media stays out of the dock — the `aether-media` KWin rule pins it to the island and skips the taskbar | `layout.js` + appletsrc |
| Indicators | icontasks button states via `tasks.svgz` (quiet tints: hover 8 %, focus 10 %, attention 14 %) | `build_frames.py` |
| Theme effects | `ContrastEffect` off (it read as glow), `BlurBehindEffect` on, `AdaptiveTransparency` off (a glass pill must not opacify when a window touches it) | `build_desktoptheme.py` → `plasmarc` |
| Panel config | `panelOpacity=2` (translucent), floating, thickness 56, `hiding = "WindowsGoBelow"` — apps open the **full screen height**, the dock floats on top of them | `layout.js`, `plasmashellrc [PlasmaViews][Panel N]` |
| Edge placement | any edge, live, launchers kept: `make dock-edge EDGE=left|right|top|bottom` | `system/dock-edge.sh` (retired with the panel era; the service dock's edges are bottom/left) |

The old `tasks.svgz` chip states remain in the theme for any stock task widget,
but the dock itself draws all its states (NoBackground applet).

## 3. Decisions taken (and why)

- **Always visible, not auto-hide.** Auto-hide hid the bar behind an exact
  bottom-edge hover and made it feel absent; `hiding: "none"` is the tablet's
  behavior. One word in `layout.js` flips it back.
- **Scrim 0.28, no heavier.** Live A/B against the reference: 0.86 and 0.73
  read as a flat dark strip ("not faded enough"), 0.18 too clear, 0.28 matches.
- **Frost 0.04.** Added 2026-10-27: over dark content the pure-glass pill
  disappeared (backdrop ~22 → glass ~17, i.e. darker than the wallpaper);
  frost lifts it to ~25–30 while staying invisible over bright content.
- **AdaptiveTransparency off** — deliberate, not leftover: adaptive mode
  swapped the pill to the near-black opaque variant whenever a maximized
  window touched it, which read as "the bar broke".
- **Custom plasmoid over forking icontasks** — the separator, dots and focused
  pill are not expressible in 9-slice frames or icontasks config; a thin QML
  row over the same `TaskManager.TasksModel` gets them without fighting the
  platform per Plasma release.

## 4. Operating notes (failure modes seen live)

- **"Apps don't open all the way" + a sensitive full-width strip at the bottom**
  — the panel was in AlwaysVisible mode, which reserves workspace (a Windows
  taskbar-style strut), so maximized windows stop ~56 px short and the leftover
  strip eats pointer events. Root cause of the long "dark rail" mystery (the
  owner diagnosed it). Fix: `hiding = "WindowsGoBelow"` in `layout.js`. The
  token must be the exact enum name — `"none"` is *invalid* and silently falls
  back to AlwaysVisible. Verified: KWin workarea 1920x1080 (was 1024), across
  restarts.
- **Pinned apps vanish after scripted panel edits/reinstall** — icontasks saves
  its empty init state over `launchers` written during scripted panel creation;
  capture the list first and re-apply it with the shell stopped. (A stale
  `ksycoca` can also hide launchers: `kbuildsycoca6 --noincremental`.)
- **A desktop-file id must match the installed app**: VS Code here is the
  flatpak `com.microsoft.VSCode.desktop`, not `code.desktop` — a wrong id
  simply never shows.
- **Theme changes look like no-ops**: Plasma caches SVG frames in
  `~/.cache/plasma_theme_AetherGlass.kcache` — clear it and restart
  plasmashell after installing a rebuilt theme.
- **Verifying while a fullscreen app runs**: screenshots then measure the app,
  not the desktop. Check the KWin workarea instead (`loadScript` + `start()`
  on `org.kde.KWin /Scripting`, print `workspace.clientArea(2, ...)`).
- **Bar hidden behind an app although everything else is right** — the window
  was flagged "keep above" at runtime (KWin scripting: `w.keepAbove === true`;
  window menu: Alt+F3 → More Actions → Keep Above). Such windows legitimately
  stack over the dock; clear the flag. Seen with zcode/chrome 2026-10-27 —
  clearing the flags made the glass bar appear over the maximized window
  (measured: pill 182 over content 244).

## 5. What is left (ideas, not promises)

Window grouping when one app has many windows, an audio-stream badge,
drag-to-reorder, transient shrink in fullscreen, M3 container-transform
launch. Explicitly out of scope: matching KWin's blur kernel to Android's
RenderEffect (close enough), and anything compositor-level.

## 6. Acceptance — the squint test

With the stock row: on a crop of just the bar the pill silhouette reads over
dark **and** bright content (frost 0.10 floor: measured +20 luminance over a
dark-24 backdrop; imperceptible change over bright), no rim/shadow/halo, icons
with air, launchers survive restarts. The separator/dots checks belonged to
the retired custom row — [dock-verification.png](dock-verification.png)
preserves that comparison; [dock-live.png](dock-live.png) is the live capture.
