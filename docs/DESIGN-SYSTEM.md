# Design System — plan

Status: **steps 1–4 done (off-scale values snapped, review visually)** (2026-10-27): `theme/tokens.toml`, `tokens.py`, `build_tokens_qml.py`,
`make tokens`, `AetherShared.Tokens`. The four colour generators read `tokens.toml` (output byte-identical); `Theme.qml` and `CardSurface` read `Tokens` (values verified identical at runtime); steps 4–7 below are still a plan.

Goal: one place that says what Aether looks like, one file that holds every
design value, and a check that fails when someone hard-codes a value instead
of using it. Every component, generator and greeter reads from the same source,
so the island, toasts, dock, Plasma theme, Kvantum, Konsole and the lock screen
cannot drift apart.

---

## 1. The design line (what Aether is)

Read this before drawing anything. If a change breaks one of these, it is a
design change, not a code change — discuss it first.

1. **Glass, not paint.** Surfaces are blur + one neutral scrim + (sometimes) a
   1 px hairline rim. No glow, no halo, no drop shadow on translucent things,
   no background-contrast effect. Blur alone separates a surface from the
   wallpaper.
2. **The island is always dark.** Like a hardware notch, the island and its
   cards stay dark in both color schemes. Everything else follows the KDE
   scheme (Aether Glass dark / Aether Serenity light).
3. **Accent is rare.** Cyan (`#00f2fe`, dark) / graphite (`#1a1d20`, light) marks
   *the one thing that matters* — progress, active toggle, focus. Never a large
   fill, never a hover state.
4. **State lives in small details.** Hover, focus and attention are quiet
   neutral tints (8 % / 10 % / 14 %), dots and thin pills — not color fills.
5. **Material texture.** Dark surfaces carry the shared grain at ~2 % so they
   read as an object, not a flat rectangle.
6. **Calm type.** Inter for everything, JetBrains Mono for numbers that change
   (time, progress, percentages). Few sizes, weight does the hierarchy.
7. **Physical motion.** One continuous gesture (pull curtain), snap to stops,
   short ease-out for responses, slow sine for ambient loops. Overshoot only
   for a deliberate "press" feel.
8. **Geometry is modest.** Rounded, not bubbly: card corners 16–24, the dock
   pill 12, stadium only where an object is a true pill (sliders, progress).

---

## 2. Where we are (audit, 2026-10-27)

| Problem | Evidence |
|---|---|
| Design values live in ~10 places | Hex colors in `build_kvantum.py` (88), `build_colors.py` (42), `build_lnf_konsole.py` (38), `login/aether-lock/Main.qml` (10), `build_frames.py`, `Theme.qml`, `MediaCard.qml`, `ToggleChip.qml`, `TimerRow.qml`, `BatteryGlyph.qml`, dock plasmoid |
| Same role, different value | Primary text: `#eceef2` (Theme.qml) vs `#e1e2eb` (colors, login). Secondary text: `#8d939d` vs `#b9cacb`. Dark surface: `#1c1e24/#121418` (island) vs `#10131a/#0b0e14` (scheme) |
| No scales | 19 distinct `radius` values, 22 distinct durations (50–900 ms), 11 font sizes, 7 easing curves, ad-hoc `Qt.rgba(...)` in 9 QML files |
| Lock screen is an island | `login/aether-lock` re-declares its own palette (SDDM cannot import `AetherShared`) |
| Calibrated numbers are undocumented in code | dock scrim 0.28, frost 0.04, tint 8/10/14 % live only in `build_frames.py` and `DOCK-SPEC.md` |

`components/shared/AetherShared/Theme.qml` *exists* and is the right idea — it
just covers only colors for the island, and nothing upstream feeds it.

---

## 3. Target structure

```
theme/
  tokens.toml                ← THE source of truth (hand-edited, reviewed)
  generators/
    tokens.py                ← loader: tokens.load() → dict, used by every generator
    build_tokens_qml.py      ← writes the QML token singletons (committed, see §5)
    build_colors.py          ← reads tokens instead of its own PALETTES
    build_kvantum.py         ← reads tokens
    build_lnf_konsole.py     ← reads tokens
    build_frames.py          ← reads material.* tokens (scrim, frost, tints, radii)
components/shared/AetherShared/
  Tokens.qml                 ← GENERATED, committed: typed inline components, so qmllint/completion see every token
  Theme.qml                  ← hand-written: semantic roles on top of Tokens (dark/light switch)
  CardSurface.qml, ...       ← shared primitives (see §6)
login/aether-lock/components/
  Tokens.qml                 ← GENERATED copy (step 5: needs a qmldir there, which must also list GlassButton/GlassMenu/Icon)
tools/
  check-tokens.sh            ← lint: no literals outside the allowlist (see §7)
docs/
  DESIGN-SYSTEM.md           ← this file; §1 is the design line
```

Rule of thumb: **values go in `tokens.toml`, meaning goes in `Theme.qml`,
layout goes in components.**

---

## 4. Token tiers

Three tiers. Components may use tier 2 and 3, **never tier 1**.

### Tier 1 — primitives (raw values, no meaning)

```toml
[palette]
cyan-400   = "#00f2fe"
cyan-500   = "#00dce6"
cyan-900   = "#00373a"
ink-950    = "#0b0e14"
ink-900    = "#10131a"
ink-850    = "#121418"
ink-800    = "#191c22"
ink-750    = "#1c1e24"
ink-700    = "#1d2026"
ink-600    = "#2a2d34"
fog-500    = "#8d939d"
fog-300    = "#b9cacb"
fog-100    = "#e1e2eb"
fog-50     = "#eceef2"
paper-0    = "#ffffff"
paper-50   = "#f8f9fa"
paper-100  = "#f3f4f5"
graphite-900 = "#1a1d20"
graphite-700 = "#44474a"
graphite-500 = "#595f65"
red-200    = "#ffb4ab"
red-700    = "#ba1a1a"
amber-200  = "#ffd27a"
green-200  = "#7cf5c4"
green-700  = "#1e7d4f"
violet-200 = "#cdbdff"
```

### Tier 2 — semantic roles (per mode)

```toml
[role.dark]
text        = "fog-100"
text-muted  = "fog-300"
accent      = "cyan-400"
accent-hover= "cyan-500"
text-on-accent = "cyan-900"   # never "on-…": QML reads onX as a signal handler
surface     = "ink-900"
surface-sunken = "ink-950"
surface-raised = "ink-700"
negative    = "red-200"
warning     = "amber-200"
positive    = "green-200"

[role.light]
text        = "graphite-900"   # value from scheme: #191c1d → normalize to one
text-muted  = "graphite-500"
accent      = "graphite-900"
# ...

[role.island]                   # always dark (design line §1.2)
text        = "fog-50"
text-muted  = "fog-500"
body-top    = "ink-750"
body-bottom = "ink-850"
chip        = "ink-600"
```

**Decision needed before migrating:** the island's `fog-50/fog-500` vs the
scheme's `fog-100/fog-300`. Either keep both deliberately (island is denser,
higher-contrast) and document it here, or collapse to one pair.

### Tier 3 — component / material constants (calibrated numbers)

```toml
[material]
island-body-alpha = 0.75
rim-alpha         = 0.09     # white hairline on dark glass
bevel-alpha       = 0.35
grain-opacity     = 0.022
dock-scrim        = 0.28     # live-calibrated, see DOCK-SPEC.md
dock-frost        = 0.10     # what build_frames.py ships (DOCK-SPEC's 0.04 is stale)
tint-hover        = 0.08
tint-focus        = 0.10
tint-attention    = 0.14
```

### Scales (shared by every tier)

Collapsed from what the code uses today; every current value maps to its
nearest step.

```toml
[space]        # 4-pt grid
xs = 4
sm = 8
md = 12
lg = 16
xl = 24
xxl = 32

[radius]
hair  = 2      # bars, progress tracks (today 1, 1.5, 2, 3, 3.5)
xs    = 4      # (4, 6)
sm    = 8
md    = 12     # dock pill, chips (11, 12, 13, 14)
lg    = 16     # (15, 16, 18, 19)
xl    = 20     # (20, 22)
card  = 24     # toasts, cards
# "pill" is not a number: height / 2, computed in QML

[type]         # pixelSize; weight carries hierarchy
caption = 11   # (10, 11)
label   = 12
body    = 13   # (13, 14)
title   = 15   # (15, 16)
heading = 22   # (22, 24)
display = 28
clock   = 168  # lock screen only
family      = "Inter"
family-mono = "JetBrains Mono"

[motion.duration]   # ms
micro    = 90    # hover tint, press (50, 60, 70, 80, 90)
fast     = 120   # small state changes (110, 120, 140, 150)
base     = 180   # cards in/out, toggles (160, 180, 200)
slow     = 250   # crossfades, list reflow
morph    = 450   # island shape open/close (380, 400, 420, 450, 520)
ambient  = 900   # loops (eq bars, breathing)

[motion.easing]
enter    = "OutCubic"    # default for everything that responds
exit     = "InCubic"
ambient  = "InOutSine"
spring   = "OutBack"     # press-squish only; OutQuint/InOutQuad → enter
```

---

## 5. How tokens reach each consumer

| Consumer | Mechanism |
|---|---|
| Python generators | `from tokens import load; T = load()` — `tomllib` (stdlib, Python ≥ 3.11), resolves `role.*` references to hex |
| Island, toasts | `import AetherShared` → `Theme.text`, `Theme.radius.card`, `Theme.motion.fast`… `Tokens.qml` is generated, `Theme.qml` maps roles |
| Lock screen | generated `login/aether-lock/components/Tokens.qml` (same content); `Main.qml` drops its inline palette |
| Dock / plasmoids | Plasma theme colors via `Kirigami.Theme` (they must follow the scheme); calibrated numbers come through `build_frames.py` |
| C++ | none needed today; if one appears, generate a header the same way — never type a hex in C++ |

`Tokens.qml` files are **committed** (unlike `theme/generated/`) because the
island runs from the source tree with no generate step. `make tokens` rewrites
them; `make check` fails if they are stale.

---

## 6. Shared primitives

Anything drawn in two places becomes one component in `AetherShared`, so a
design tweak is one edit:

| Primitive | Today | Used by |
|---|---|---|
| `CardSurface` | *exists* | toasts; should also back `NotificationCard`, `MediaCard` |
| `GlassChip` | `ToggleChip`, `NotchButton` each draw their own | island toggles, buttons, lock buttons |
| `Hairline` | inline `Rectangle`s | separators, rims |
| `Tint` (hover/focus/attention states) | per-file `Qt.rgba` | every interactive element |
| `Label` / `MonoLabel` | `Text { font.family: Theme.font; pixelSize: 13 }` repeated | everything |
| `Motion` behaviors (`Behavior { NumberAnimation { duration: Theme.motion.fast; easing.type: … } }`) | repeated 60+ times | everything |

---

## 7. Guardrails (how conflicts are prevented)

1. **Lint** — `tools/check-tokens.sh`, run by `make check`:
   - no `#rrggbb` or `Qt.rgba(` in `*.qml` outside `Tokens.qml`;
   - no `pixelSize: <number>`, `radius: <number>`, `duration: <number>` in `*.qml`
     (allowed: `0`, expressions like `height / 2`);
   - no hex in `theme/generators/*.py` except `tokens.py`;
   - escape hatch: a trailing `// token-ok: <reason>` comment for genuine
     one-offs (artwork math, the 2 px hot strip).
2. **Staleness** — `make check` regenerates `Tokens.qml` into a temp dir and diffs.
3. **Review rule** — a PR that adds a token must say which §1 line it serves.
   A PR that changes a tier-3 number must link the calibration (screenshot or
   note in a spec doc).
4. **Naming** — tokens are `kebab-case` in TOML, `camelCase` in QML
   (`text-muted` → `Theme.textMuted`); roles describe *purpose*, never color
   (`accent`, not `cyan`).

---

## 8. Migration order

Each step is shippable and leaves the screen pixel-identical (except where a
§4 decision changes a value on purpose).

1. **Tokens file + loader.** Write `theme/tokens.toml` from today's values,
   `tokens.py`, `build_tokens_qml.py`, `make tokens`. No consumer changes yet.
2. **Generators.** `build_colors.py` → `build_lnf_konsole.py` → `build_kvantum.py`
   → `build_frames.py` read tokens. Verify: generated output byte-identical
   (generators are deterministic, so `diff -r` proves it).
3. **AetherShared.** `Theme.qml` becomes roles over `Tokens`; add scales
   (`radius`, `space`, `type`, `motion`).
4. **Island + toasts.** File by file, replace literals; extract the §6
   primitives as duplication shows up. Screenshot bar / large / expanded /
   toast before and after.
5. **Lock screen.** Generated `Tokens.qml`, drop inline palette.
6. **Turn on the lint** in `make check` (warnings in steps 1–5, error after).
7. **Update docs.** `ARCHITECTURE.md` gets a "Design tokens" section pointing
   here; `CONTRIBUTING.md` conventions gain "no literals — use tokens".

### Open decisions (owner)

- Island text pair vs scheme text pair (§4 tier 2) — keep both or unify?
- Light-mode primary text: `#191c1d` (scheme) vs `#1a1d20` (accent/lock) — unify?
- Should the dock follow the island's always-dark rule, or the scheme? (today:
  scheme)
