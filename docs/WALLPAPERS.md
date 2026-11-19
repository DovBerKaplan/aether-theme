# The Aether wallpapers

Five wallpaper plugins, one design line: each field is drawn by a fragment shader at the screen's
own resolution (no image anywhere), everything is derived from the island's accent, both a dark and
a light field exist and a mode switch fades between them, and the motion is slow ambient sine — a
few pixels a second, sub-pixel per tick.

| Package | Field | Motion |
|---|---|---|
| `org.aether.ribbons` | Two swooping bands of silk over a deep field; the distribution's logo (or the Aether mark) breathes at the centre | Seams wander, lights drift along them, a sheen crosses once a minute |
| `org.aether.mist` | Five banks of fog over a deep field | Banks roll and patch along themselves; the counter-bank drifts against them |
| `org.aether.aurora` | Three curtains of light hanging from the top; a faint pool where their light lands | Curtains sway on slow circles, rays drift inside them, hems rise and fall |
| `org.aether.ink` | Two ink masses billowing in still water; a breathing pool keeps the centre clear | A slow domain warp tears the edges; the pivots counter-drift |
| `org.aether.dune` | Four ridgelines under a deep sky; the nearest crest catches a fine edge of light | Traveling swells cross breathing ones, so shapes morph instead of sliding |

## The shared contract

Every wallpaper keeps the ribbons' engineering, in `plasmoids/org.aether.<style>/contents/`:

- **One clock**: a 100 ms `Timer` in `main.qml` is the only animation driver; `time` wraps every
  100000 s (~28 h) so the shader's floats stay precise; the timer runs only while
  `Animate` is on and the wallpaper is visible.
- **One layer**: the whole scene sits in `layer.enabled: true`, so plasmashell's frequent desktop
  redraws hit a cached texture; while windows cover the desktop the compositor stops asking for
  frames at all.
- **Bounded GPU work**: every loop trip count is a compile-time constant; nothing moves faster than
  a few pixels a second.
- **One accent**: `AccentColor` (written by `aether-accent-sync`; empty follows the system accent)
  is remapped by the shader's `hue()` helper — a muted accent still has to glow. Ink-750 and the
  rest of the token palette are the *island's* surfaces; the fields derive their own deep tones
  from the accent hue.
- **Two fields**: dark and light are both computed and mixed by `dark`, so a mode switch
  crossfades; `Mode` is written by `aether-mode-sync` (`auto` judges the scheme).
- **One pixel of dither** keeps the long gradients from banding.

Config keys (KConfigXT, `contents/config/main.xml`, group `General`): `AccentColor`, `Mode`,
`Animate` — and `Distro` on ribbons only (its centre wears the distribution's logo, see
`NOTICE`). The shaders compile with `qsb6 --glsl "100 es,120,150" --hlsl 50 --msl 12` at install
(`install/install.sh`) and as a `make check` gate.

## Choosing: the island's wallpaper panel

The island's **Wallpaper tile** opens a panel where every field previews through its own real
shader at card size (the compiled `.qsb` files ride the island install,
`share/aether-island/qml/assets/wallpapers/`), on one shared 10 Hz timer. A tap applies at once:
`TileStore::setWallpaper` (`components/island/src/TileStore.h`) writes `wallpaperPlugin` per
desktop through plasmashell's scripting API — no restart — then lets the two sync oneshots hand the
new field its accent and mode. The choice lives in `~/.config/aetherislandrc`
(`[Wallpaper] Style`, `[Wallpaper] Animate`; `install.sh` restores it on reinstall). The footer's
switch writes `Animate` into whichever aether wallpaper is active.

Both sync services match any `org.aether.*` wallpaper (not just the ribbons), so accent and mode
follow whichever field the desktop wears. `install.sh` sets the saved style on every desktop.

## Adding a style

1. Copy a package under `plasmoids/org.aether.<name>/` — `metadata.json`, the four-key (or
   three-key) `config/main.xml`, `ui/main.qml` (the shared skeleton: timer, layer, `ShaderEffect`,
   breathing crescent mark), `ui/config.qml`, and your `shaders/<name>.frag`.
2. Keep the contract above: constant loop counts, motion a function of `time` only, both fields,
   `hue()` from the accent, vignette, dither. Reserved GLSL words (`patch`…) trip the ES target.
3. Register it in three loops: `install/install.sh` (copy + compile + the style list),
   `Makefile`'s `check` gate, and `components/island/CMakeLists.txt` (the preview bakes).
4. Add its `{id, title, shader}` row to `TileStore::wallpapers()`, a Hebrew title in
   `components/shared/AetherShared/strings_he.js`, and the doc row above.
