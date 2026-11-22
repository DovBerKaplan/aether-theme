# Theme bus

The desktop's theme on the session bus, both ways. Before it, the components only shared theme
state through files (`~/.config/aetherislandrc`, `kdeglobals`, the Plasma appletsrc), and anything
outside Aether that wanted to dress like the desktop had to parse them itself. Now the island
says what the theme is, tells clients when it changes, and takes requests back. The first client
is Aethergram (the Telegram Desktop fork). It works out all its colours from the system accent
and mode, and it publishes its own state back (see [Client side](#client-side-aethergram)).

The island owns the service (`components/island/src/ThemeBus.h`). It is only a voice: the state
still lives where it did before. TileStore holds the accent, wallpaper and language in
aetherislandrc, and the Display panel's DisplayModel holds the mode in kdeglobals.

| | |
|---|---|
| Service | `org.aether.Theme` |
| Object | `/Theme` |
| Interface | `org.aether.Theme1` |

```bash
qdbus6 org.aether.Theme /Theme org.aether.Theme1.Get
```

## The state map, `a{sv}`

`Get()` and the `Changed` signal carry the same map. Clients should ignore keys they don't know,
because new keys may be added under the same `version`. A change that breaks old clients will
raise `version`.

| Key | Type | Meaning |
|---|---|---|
| `version` | `i` | Map format, currently `1`. |
| `accent` | `s` | The resolved accent as `#rrggbb`. With a colour picked, it is `hsl(accentHue, accentSat, accentLight)`. Without one, it is the theme's own accent for the mode: `#00f2fe` in dark mode, `#1a1d20` in light mode (tokens `role.island.accent` / `role.light.accent`, the same rule as `Theme.qml`). Clients that only want one colour use this. |
| `accentHue` | `i` | 0..359, the island picker's hue. It is `183` when nothing is picked. |
| `accentSat` | `d` | HSL saturation, 0.15..1. |
| `accentLight` | `d` | HSL lightness, 0.25..0.80. |
| `accentSet` | `b` | `true` if the user picked a colour in the island, `false` if the theme's own is in use. |
| `mode` | `s` | `"dark"` or `"light"`, judged the same way as `mode_is_light()` in `system/aether-accent-sync`. kdeglobals `[General] ColorScheme == AetherSerenity` means light. If no scheme name is written and `[KDE] LookAndFeelPackage` is an `org.aether.*` package, the mode is light when the plain average of `[Colors:Window] BackgroundNormal` r,g,b is at least 128. Anything else is dark. |
| `wallpaper` | `s` | Style id: `ribbons`, `mist`, `aurora`, `ink` or `dune`, taken from aetherislandrc `[Wallpaper] Style` (`org.aether.X` → `X`). If no style is saved, it comes from `wallpaperplugin=` of the primary screen's desktop containment (`lastScreen=0`) in `plasma-org.kde.plasma.desktop-appletsrc`: `org.aether.X` → `X`, `org.kde.image` → `static`, anything else → `neutral`. |
| `language` | `s` | Interface language from aetherislandrc `[Interface] Language`: `"en"` or `"he"`. Hebrew is right-to-left. |

## Signal

`Changed(a{sv} state)` carries the full map, not a diff. The island emits it once things have
settled for about 150 ms, and only when the map really differs from the last one sent. A slider
drag sends one signal, not dozens.

It is emitted after:

- TileStore changes the accent, wallpaper or language (the island's own panels, or the methods below).
- kdeglobals changes (the mode).
- the appletsrc changes (the wallpaper when no style is saved).

Both files are replaced atomically on every write, so the island watches the new file again after
each replace. If a file is missing, it checks for it every 2 s.

## Methods (client → system)

| Method | Effect | Errors |
|---|---|---|
| `Get() → a{sv}` | Returns the current state. | |
| `SetAccent(s hex)` | Picks a colour, as if it was chosen in the island's Color panel. The value must be exactly `#rrggbb`. It is converted to the picker's coordinates (`QColor` HSL hue, lightness, saturation) and clamped to the picker's ranges (lightness 0.25..0.80, saturation 0.15..1, grey gets hue 0). So `accent` in the following `Changed` can differ a little from the request: `#ff8800` comes back as `#ff8800`, but `#ffffff` comes back as lightness 0.80. Everything that follows the picker follows this too: aetherislandrc, the system colour scheme and aether-accent-sync. | `org.freedesktop.DBus.Error.InvalidArgs` for anything that is not `#rrggbb` |
| `ResetAccent()` | Goes back to the theme's own accent (`accentSet = false`). | |
| `SetMode(s mode)` | `"dark"` or `"light"`. This is the island's Display panel switch: the colour scheme first, then the look-and-feel. A manual choice turns off automatic day/night switching. If the mode is already the requested one, nothing happens. | `InvalidArgs` for any other value |

```bash
qdbus6 org.aether.Theme /Theme org.aether.Theme1.SetAccent "#ff8800"
dbus-monitor "type='signal',interface='org.aether.Theme1'"
```

## When the service is absent

The island may not be running yet, may be restarting, or the client may be on another desktop.
Clients should watch for the name (`NameOwnerChanged` for `org.aether.Theme`) and fall back to
the files the bus is built from, using the same rules as above:

- `~/.config/aetherislandrc`: `[Appearance] AccentSet / AccentHue / AccentSat / AccentLight`, `[Interface] Language`, `[Wallpaper] Style`.
- `~/.config/kdeglobals`: the mode.
- `~/.config/plasma-org.kde.plasma.desktop-appletsrc`: the wallpaper when no style is saved.

All three files are written by atomic rename, so watch each file again after every change (or
watch the folder). Requests need the service. With the service absent, a client should not write
these files itself. aetherislandrc in particular belongs to the island.

## Client side (Aethergram)

The other direction is planned with the same pattern, so the island (and later the dock) can
show a client's state without polling it:

| | |
|---|---|
| Service | `io.github.dovberkaplan.Aethergram` |
| Object | `/Aether` |
| Interface | `org.aether.Client1` |

Properties (read-only):

| Property | Type | Meaning |
|---|---|---|
| `Unread` | `i` | Unread messages in non-muted chats. |
| `UnreadMuted` | `i` | Unread messages in muted chats. |
| `Mentions` | `i` | Unread mentions and replies. |
| `ActiveChat` | `s` | The chat that is open, `""` if none. |
| `Connected` | `b` | `true` when online and synced with Telegram. |

Signal `StateChanged(a{sv} state)` carries every property above (same names as keys) whenever one
changes, debounced like `Changed`.

Methods: `Show()` and `Hide()` raise or hide the main window, `OpenChat(s chat)` opens a chat by
peer id or @username, and `Compose()` starts a new message.

The client listens to `org.aether.Theme1.Changed` (or `Get()` at start), computes its whole palette
from `accent` and `mode`, and calls `SetAccent` / `SetMode` only when the user picks a theme there.

## Testing without touching the real desktop

`AETHER_ISLANDRC=<path>` aims the island's TileStore, and so the bus, at a copy of the rc. Run the
built island on a private bus with a sandbox `HOME`, so nothing writes to the real
aetherislandrc or kdeglobals and nothing reaches the real BlueZ or NetworkManager (the system
bus points nowhere):

```bash
dbus-run-session -- env DBUS_SYSTEM_BUS_ADDRESS=unix:path=/nonexistent HOME=/tmp/sb XDG_CONFIG_HOME=/tmp/sb/.config \
  AETHER_ISLANDRC=/tmp/sb/rc-copy AETHER_NO_LAYER=1 QT_QPA_PLATFORM=offscreen AETHER_PEAR_PATTERN=/nonexistent \
  components/island/build/aether-island
```
