# Panels Spec — dedicated windows for the island's buttons

Status: **Phases 1-5 built** (2026-10-27): panel mode and frame, Wi-Fi, Bluetooth, Sound, Battery, Display, Power and Calendar (with Hebrew dates) panels, and the tile set with edit mode (`~/.config/aetherislandrc`). Changed from the plan after review: no timer in the Calendar, no Sound tile (the slider is enough), the timer is a small icon in the island header. Interface language (Hebrew/English, right-to-left layout, a button in the bar) is built too - see ARCHITECTURE.md. Not built: Do Not Disturb and Hotspot tiles.

The goal, in one sentence: every control in the island (Wi‑Fi, Bluetooth,
sound, brightness, battery, clock, power) opens its **own detail panel**. The
panels should work like the Quick Settings detail sheets on the owner's Android
17 tablet: connecting to a Wi‑Fi network takes two taps and a password, and you
never leave the island or see a KDE dialog.

Read [DESIGN-SYSTEM.md §1](DESIGN-SYSTEM.md) first: every rule there applies,
and nothing here overrides it.

---

## 1. Principles (what "Android-level" means here)

1. **One gesture deeper, never a new window.** A panel is the island itself,
   showing a different page. It has the same glass, the same 480 px width and
   r = 30 corners, and the same curtain. Nothing pops up beside it.
2. **Toggle and details are two separate targets.** Like an M3 Quick Settings
   tile, the *icon* toggles and the *label area* opens the panel. You can turn
   Wi‑Fi off without opening anything, and you can see networks without
   turning anything off.
3. **The common case takes ≤ 2 taps.** Some examples:
   - Connect to a saved network: chip label → network row.
   - Connect to a new network: chip label → row → password → Enter.
   - Switch audio to headphones: chip label → device row.
   - Shut down: power → Shut down → tap again.
4. **Show the state, never a spinner alone.** "Connecting…" names the step it
   is on: authenticating, getting an address, checking internet. Failures say
   what happened and what to do next, inline, on the row that failed.
5. **Optimistic but honest.** A tap reacts within 90 ms (a tint or a switch
   flip). If the system later disagrees, the UI rolls back with an inline
   message instead of silently snapping back.
6. **Event-driven.** Panels subscribe to D-Bus signals and never poll. The
   island keeps its ~0.1 % idle CPU. A scan runs only while a panel is open.
7. **Keyboard-complete.** Everything can be done without a mouse: Tab and the
   arrow keys move, Enter acts, Space toggles, Esc goes back one level.
8. **KDE stays the fallback, not the face.** Every panel ends with a quiet
   "… settings" link to the matching KCM for the 5 % of cases (802.1X
   certificates, codec tuning). The island never shows a KDE dialog in the
   common path.

---

## 2. Where panels live in the island

### 2.1 A new island mode: `panel`

```
hidden → bar → large ⇄ expanded
                 │
                 └─ panel (panelId, page)     ← new
```

- `mode: "panel"` plus `panelId` (`wifi`, `bluetooth`, `sound`, `display`,
  `battery`, `calendar`, `power`) and `page` (`list` or `detail:<key>`).
- **Width** stays at 480, the same as `large`, so the silhouette only grows or
  shrinks in height. That reads as the same object turning a page, not as a
  morph into a new one.
- **Height** is `min(panel.contentHeight, screenH − 120)` and follows content
  with the island's own spring. Lists taller than that scroll inside the panel;
  the header and footer stay pinned.
- **Window/input/blur** are unchanged: the window is full-screen as in `large`,
  and the one-path rule from ARCHITECTURE.md still holds.
- The **pull handle** stays at the bottom. Dragging up closes to `bar`. A tap
  goes back one level (detail → list → large).

### 2.2 Ways in

| From | Gesture | Opens |
|---|---|---|
| Large island chip | tap the **label area** (right ⅔ of the chip, marked by a `›` chevron) | that chip's panel |
| Large island chip | right-click, long-press 400 ms, or Shift+Enter | that chip's panel |
| Large island chip | tap the **icon circle** (left ⅓) | toggle only (today's behavior) |
| Volume slider | tap the speaker glyph at its left | `sound` |
| Brightness slider | tap the sun glyph | `display` |
| Large header | tap battery % or glyph | `battery` |
| Large header | tap the date or time | `calendar` |
| Bar | power button | `power` (replaces `LogoutPrompt`, §9) |
| Bar | tap the clock | `calendar` (straight from the bar: the island morphs bar → panel) |
| D-Bus | `OpenPanel(s id)` on `org.aether.Island` | any panel, e.g. bound to Meta+Shift+W (Wi‑Fi) |
| Toasts | "Connected to <ssid>" / "Headphones connected" toast tap | the related panel |

### 2.3 Ways out

- **Back** (header chevron, Esc, handle tap, mouse back button, Alt+Left) goes
  back one level: detail → list → `large`. If the panel was opened from the
  bar, it goes back to `bar`.
- **Close** (click outside, scroll up at the top of the list, drag the handle
  up, Meta+N) goes straight to `bar`.
- Leaving the pointer does **not** close a panel. Someone typing a password must
  never lose it because the mouse drifted off. The leave timer is disabled in
  `panel` mode; this is the same exception that media mode has while typing.

### 2.4 Motion

| Transition | Motion |
|---|---|
| large → panel | **Shared-axis X.** Large content slides 32 px left and fades out (`fast`, `exit`); panel content slides in from +32 px and fades in (`base`, `enter`, 40 ms delay). The glass height springs to the new height at the same time. |
| list → detail | Same shared-axis X, one level deeper. |
| back | Mirror image (content moves right). |
| bar → panel | The island's open morph (`morph` 450) straight to panel height. Content fades in after 60 % of the morph. |
| Row expands (password entry) | Row height animates (`base`, `enter`); rows below reflow (`slow`). No other row moves sideways. |
| Error | The field shakes 3 times at ±6 px over 240 ms (the only shake in the system), then the message fades in. |

Clip content to the silhouette exactly as `LargeIsland` does, so nothing draws
outside the glass mid-morph.

---

## 3. Panel anatomy (shared by all panels)

```
┌──────────────────────────────────────────────── 480 ─┐
│  ‹   Wi‑Fi                                  [●═══]  │  header 56
│      Connected · Home-5G                             │  (subtitle, optional)
│ ─────────────────────────────────────────────────── │  hairline, only when scrolled
│  HERO ZONE (current network / output / battery…)     │  0..1 hero card
│                                                       │
│  SECTION LABEL                                        │  caption, text-muted, 24 above
│  ┌ row ─────────────────────────────────────────────┐ │
│  │ ◉  Title                           trailing   › │ │  56 one-line / 64 two-line
│  └──────────────────────────────────────────────────┘ │
│  …                                                     │  scrolls
│ ─────────────────────────────────────────────────── │
│  Wi‑Fi settings  ↗                         Scan ⟳   │  footer 44, text buttons
│                      ▬▬▬▬                             │  handle
└──────────────────────────────────────────────────────┘
```

- **Padding:** the 22 px side padding matches `LargeIsland.pad`, and rows sit
  inside it with their own 12 px insets, giving 34 px from the glass edge to the
  text.
- **Header (56):** a back chevron (40×40 hit target), then the title (`title`
  15, DemiBold), then the master switch on the right. The subtitle (`label` 12,
  `subtext`) states the summary in words.
- **Hero card:** the one thing that matters right now (connected network,
  active output, battery state). It is a `CardSurface` at radius `lg` with
  16 px padding. It is the only place the accent may appear as more than a dot.
- **Section label:** `caption` 11, Medium, letter-spacing +0.4, `subtext`,
  sentence case ("Saved networks", not "SAVED NETWORKS").
- **Rows:** no row backgrounds at rest. Hover is a `tint-hover` (8 %) stadium
  inset by 4 px; press is `tint-attention` (14 %); keyboard focus is a 2 px
  `accent` ring at radius `md`. Rows in one group are separated by **air**
  (4 px), not by lines.
- **Footer (44):** a settings link on the left (opens the KCM, `↗` glyph,
  closes the island) and a context action on the right (Scan, Pair new…). Both
  are text buttons.
- **Empty states:** a centered 32 px glyph, one line of text, and one action.
  For example: "Wi‑Fi is off" with a [Turn on] button. They are never blank.

### 3.1 New shared primitives (`AetherShared` / island `qml/panel/`)

| Component | Purpose | Key specs |
|---|---|---|
| `PanelScaffold` | header + scrolling body + footer + clip; exposes `contentHeight` | header/footer pinned; hairline appears when `contentY > 0` |
| `PanelHeader` | back, title, subtitle, trailing slot | back hit 40×40 |
| `Switch` | M3-style switch | track 44×24 radius pill; thumb 16 → 20 when on, 24 while pressed; on = `accent` track + `textOnAccent` thumb; off = `chip` track + `subtext` thumb with a 1 px rim; flip `fast` `enter` |
| `ListRow` | leading glyph, title, subtitle, trailing slot, optional chevron | 56/64 high; leading glyph 20 in a 36 circle (`chip`); trailing items are right-aligned with 8 px gaps |
| `SectionLabel` | group heading | see above |
| `SegmentedControl` | 2–4 exclusive options (power profile, output type) | height 36, radius pill, selected = `chip` raised thumb that slides `base` |
| `TextField` | password / name entry | height 44, radius `md`, `surface-sunken` fill, 1 px rim; focus = 2 px accent ring; trailing reveal 👁 toggle; `type: password` uses `TextInput.Password` with no clipboard copy |
| `Button` | filled (accent), tonal (`chip`), text | height 36, radius pill, label `label` 12 DemiBold; filled appears once per screen at most |
| `LinearProgress` | indeterminate scan / connect bar | 2 px, `accent`, rides under the header; shown only while busy |
| `KeyValueRow` | detail pages (IP, MAC…) | key `subtext`, value `mono` 12; click copies the value and briefly shows "Copied" |
| `ConfirmTile` | destructive action that needs a second tap | §9 |
| `SignalGlyph` | Wi‑Fi strength 0–4 bars, plus a lock badge | existing `wifi-1..3` + new `wifi-0`, `wifi-4`, `lock` |

All values come from `Tokens`/`Theme`. None of the components may hard-code a
literal (DESIGN-SYSTEM.md §7).

### 3.2 Chip change in the large island

`ToggleChip` gets two zones:

```
┌────────────────────────────┐
│ (◉)  Wi‑Fi              ›  │   height 58, radius xl
│      Home-5G               │
└────────────────────────────┘
  └icon zone: toggles   └label zone: opens panel
```

- The icon sits in a 34 px circle. It turns `accent` when the chip is on,
  rather than the whole chip turning accent, which follows rule §1.3 ("accent is
  rare"). The chip body stays `chip` and gets a `tint-attention` wash when on.
- The labels become two lines: the name (`label` 12 Medium) and the state
  (`caption` 11, `subtext`).
- The four chips stay in **one row**. At 480 px with two-line labels, each chip
  is ~107 px wide, which is enough for "Wi‑Fi / Home‑5G" with an ellipsis. A
  later 2×2 or tile-pager layout is §11.

---

## 4. Wi‑Fi panel (`wifi`) — the flagship

### 4.1 List page

```
‹  Wi‑Fi                                         [●═══]
   Connected · Home-5G
═══════════════════════════════  (LinearProgress while scanning)
┌ HERO ──────────────────────────────────────────────┐
│  ▂▄▆█  Home-5G                              ⓘ      │
│        Connected · 5 GHz · 866 Mb/s                 │
│        [Share]  [Disconnect]                        │
└─────────────────────────────────────────────────────┘
Saved networks
  ▂▄▆_ 🔒 Office                  Saved          ⓘ
  ▂▄__ 🔒 Parents                 Out of range
Available
  ▂▄▆█ 🔒 Neighbor-WiFi
  ▂▄▆_    Cafe Free               Open
  ▂___ 🔒 HP-Printer-xyz
  + Add hidden network
Other
  ⇄  Ethernet                     Connected · 1 Gb/s   ›
  ⛨  VPN · Work                   [○═══]
  ✈  Airplane mode                [○═══]
──────────────────────────────────────────────────────
Wi‑Fi settings ↗                                 Scan ⟳
```

**Ordering rules** (stable, so rows do not jump while the user aims):
1. The **hero** is the active connection. If there is none, there is no hero
   and the list starts directly.
2. **Saved & in range**, by signal; then **saved & out of range** (dimmed to
   60 %, max 3, with "Show all saved (n)" after that).
3. **Available**: unsaved networks, by signal. Duplicate SSIDs (several APs, or
   2.4 and 5 GHz) merge into one row showing the strongest AP, with a band
   badge `5G`/`6G` in `caption` mono.
4. Hidden SSIDs (empty name) are never listed; "Add hidden network" covers
   them.
5. **Re-sort freeze:** while the pointer is over the list, or a row is
   expanded, new scan results update signal bars in place but do not reorder.
   Reordering happens once the pointer leaves, animated over `slow`.

**Row anatomy:** signal bars (`SignalGlyph`, 4 levels: >75, >50, >25, else),
a 10 px lock badge if secured, the SSID (`body` 13, elided in the middle), a
subtitle only when it carries information ("Saved", "Open", "Out of range",
"Wrong password last time", "No internet"), and a trailing `ⓘ` for saved
networks only.

**Scanning:** a scan starts when the panel opens (`RequestScan`), then
repeats every 10 s while the panel is open, and stops when it closes. The
`LinearProgress` shows only during an active scan and never for longer than
4 s. The footer "Scan ⟳" forces one; its glyph spins once.

### 4.2 Connecting — the inline flow

Tapping an **open** or **saved** network connects at once. The row's subtitle
walks through the real NetworkManager states:

| NM device state | Row subtitle | Visual |
|---|---|---|
| PREPARE / CONFIG | Connecting… | bars pulse (ambient sine, 900 ms) |
| NEED_AUTH | (opens the password field, see below) | |
| IP_CONFIG | Getting address… | |
| IP_CHECK / SECONDARIES | Checking internet… | |
| ACTIVATED | — | the row **lifts into the hero**: shared-element move, `slow` |
| FAILED | (reason) | inline error, see below |

Tapping a **secured, unsaved** network expands the row in place:

```
  ▂▄▆█ 🔒 Neighbor-WiFi
     ┌───────────────────────────────────────┐
     │ Password                          👁  │
     └───────────────────────────────────────┘
     ☐ Connect automatically            [Cancel] [Connect]
```

- The field takes focus immediately, and the island switches the layer-shell
  keyboard mode to `OnDemand` (the existing `island.setKeyboard(true)`). The
  mode goes back when the row collapses.
- **Connect** stays disabled until the password is long enough for its security
  type (WPA-PSK ≥ 8 characters, WEP 5/13/10/26). Enter submits.
- "Connect automatically" is **on** by default; the box exists only so it can
  be turned off.
- While connecting, the field locks, the button becomes "Connecting…" with a
  thin progress bar, and Cancel stays enabled (it deactivates and deletes the
  half-made profile).
- **Wrong password** (NM reason `NO_SECRETS` / `SUPPLICANT_DISCONNECT` during
  auth): the field shakes, then shows "Wrong password. Try again." in
  `negative`. The text stays selected so typing replaces it. The half-made
  profile is deleted, so a wrong password is never saved.
- **Other failures** show one line each, with no error codes:
  "Network didn't respond", "No IP address — try again or move closer",
  "Connected, but no internet".
- **Captive portal** (NM connectivity `PORTAL`): the hero subtitle says
  "Sign in to network" and shows a filled button **[Sign in]**. The button
  opens NetworkManager's connectivity-check URI (the portal intercepts it) in
  the default browser and closes the island.
- **WPA2/3-Enterprise (802.1X):** the row expands to Identity and Password,
  plus "Advanced ↗", which opens `kcmshell6 kcm_networkmanagement` for
  certificates. The common PEAP/MSCHAPv2 case (eduroam) works inline.
- **WPS / QR:** out of scope for v1; listed in §11.

**Secrets ownership.** The island sends the PSK in `AddAndActivateConnection`
settings, so no secret agent prompt appears and plasma-nm's KDE dialog never
shows for a network joined through the island. Storage follows the Plasma
default (`psk-flags = 1`, agent-owned, in KWallet) so plasma-nm and the island
see the same profile. **The password is never logged, never stored by the
island, and cleared from the QML field after the attempt.** See open decision
D1.

### 4.3 Network detail page (`detail:<uuid>`)

Opened from `ⓘ` on the hero or a saved row.

```
‹  Home-5G                                        
┌ HERO ──────────────────────────────────────────────┐
│  ▂▄▆█  Connected · Excellent signal (−48 dBm)      │
│        [ QR ]  Share this network                   │
└─────────────────────────────────────────────────────┘
  Connect automatically                         [●═══]
  Metered connection         Auto  [ Auto | Yes | No ]
  Private address (random MAC)  [ Per network | Device ]
Network details
  IP address                          192.168.1.34   ⧉
  Gateway                             192.168.1.1    ⧉
  DNS                                 1.1.1.1, 8.8.8.8
  Frequency                           5 GHz · ch 44
  Link speed                          866 Mb/s
  Security                            WPA3-Personal
  MAC address (this network)          a2:4f:…:19     ⧉
  IPv6                                fe80::…        ⧉
  [ Forget network ]            (text button, negative)
──────────────────────────────────────────────────────
Advanced settings ↗
```

- **Share:** shows a QR code (`WIFI:T:WPA;S:<ssid>;P:<psk>;;`) drawn in QML,
  plus the password, hidden behind 👁. Fetching the PSK (`GetSecrets`) may
  trigger a KWallet unlock. Both appear only after an explicit tap and disappear
  when the page closes.
- **Forget:** a `ConfirmTile`-style second tap ("Tap again to forget"), then
  the page goes back and the row moves to "Available".
- Rows are values while connected and are hidden when not connected. Static
  settings (auto-connect, metered, MAC) are always shown.

### 4.4 Master switch, airplane mode, Ethernet, VPN

- **Master switch off:** the list collapses into the empty state
  "Wi‑Fi is off" with [Turn on]. The hero and "Other" section stay.
- **Airplane mode** sets Wi‑Fi and Bluetooth off together (NM
  `WirelessEnabled` + BlueZ powered) and remembers the previous states for when
  it is turned off. It also shows as a tiny ✈ in the bar next to the clock.
- **Ethernet** row → detail page with the same `KeyValueRow`s.
- **VPN:** one row per NM VPN/WireGuard profile, each with its own switch;
  "Add VPN ↗" opens the KCM. Status in the subtitle.
- **Hotspot** (phase 3): a "Hotspot" row (switch + name/password detail) using
  NM's `ap` mode.

---

## 5. Bluetooth panel (`bluetooth`)

```
‹  Bluetooth                                     [●═══]
   Visible as “dovber-laptop” while this panel is open
Connected
  🎧 WH-1000XM5               Battery 80% ▮▮▮▯     ⓘ
Saved devices
  ⌨  MX Keys                  Not connected        ⓘ
  🖱 MX Master 3S              Not connected        ⓘ
Pair new device
  ═══════════════  (LinearProgress while discovering)
  📱 Pixel 9 Pro
  🔊 JBL Flip 6
  ?  Unknown device · 4C:…   (shown only after "Show unnamed")
──────────────────────────────────────────────────────
Bluetooth settings ↗                         Rename device
```

- **Tap a saved device** connects or disconnects it. The subtitle shows
  "Connecting…", then a battery level if the device reports one
  (`org.bluez.Battery1`).
- **Discovery** runs only while the panel is open and the "Pair new device"
  section is visible. The adapter is `Discoverable` only during that time (with
  the subtitle saying so). Discovery stops when the panel closes.
- **Pairing:** the island registers a BlueZ `Agent1`
  (`KeyboardDisplay` capability) only while the panel is open. Otherwise
  BlueDevil's agent keeps handling pairing as it does today. The pairing row
  expands inline:
  - *Numeric comparison:* "Confirm code **482 913** is shown on Pixel 9 Pro"
    with [Cancel] [Pair].
  - *Passkey entry:* "Type **0000** on MX Keys, then press Enter" with a live
    count of typed characters (`KeyboardDisplay` events).
  - *Legacy PIN:* a `TextField`.
  Success moves the device into "Connected" (shared-element move).
- **Device detail:** rename (alias), battery, type, address (copy), audio
  profile (`SegmentedControl` High quality (A2DP) | Headset (HFP), headphones
  only), "Use for audio" (sets it as the default sink), "Forget" (second-tap
  confirm).
- Icons come from BlueZ `Icon` (audio-headset, input-keyboard, phone…), mapped
  to the island's glyph set with a generic fallback.

---

## 6. Sound panel (`sound`)

```
‹  Sound                                         [ 🔇 ]
┌ HERO ──────────────────────────────────────────────┐
│  🔊 Speakers · Built-in                    72%      │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━○──────────          │
└─────────────────────────────────────────────────────┘
Output
  ◉ Speakers · Built-in
  ○ WH-1000XM5                       Bluetooth
  ○ HDMI · LG 27UL850                (hidden when unplugged)
Input
  🎤 Built-in microphone   ━━━━━━━○──── [🎤 mute]
     ▁▂▃▂▁  live level meter while panel is open
Apps
  🟥 YouTube Music         ━━━━━━━━━━○────       ›
  🟦 Firefox · playing     ━━━━━○────────        ›
──────────────────────────────────────────────────────
Sound settings ↗
```

- The **header trailing control** is a mute button, not a switch, because sound
  has no "off".
- **Output rows** are radio rows. Picking one makes it the default sink and
  moves all current streams to it, the way Android's output switcher does.
- **Per-app rows** appear only for streams that exist. The `›` opens a small
  detail page to route that app to a different output.
- **The mic level meter** (`EqBars`-style, 5 bars) runs only while the panel is
  open: a peak monitor on the source is created on open and destroyed on close.
- A **mic-in-use indicator** (any app recording) appears as a small amber dot
  in the bar, beside the clock. That follows §1.4: state lives in a dot. The
  indicator does not depend on this panel being open.

---

## 7. Display panel (`display`)

```
‹  Display
  ☀  ━━━━━━━━━━━━━━━━━━━━○───────────            68%
  Night Light                                    [●═══]
     Warmth  ━━━━━━━━━○──────     Sunset → Sunrise ›
  Dark theme                       [ Auto | Light | Dark ]
──────────────────────────────────────────────────────
Display settings ↗
```

- Night Light uses KWin's `org.kde.KWin.NightLight` (inhibit/uninhibit for
  the switch; temperature and mode via the KWin config, then reconfigure).
- Dark theme switches between the two Aether global themes (`lookandfeeltool`);
  "Auto" is KDE's day/night auto-switch. `aether-mode-sync` already follows
  that.
- External monitors (phase 3): one brightness slider each, through DDC/CI
  (PowerDevil already exposes them in Plasma 6).

---

## 8. Battery & power panel (`battery`)

```
‹  Battery
┌ HERO ──────────────────────────────────────────────┐
│  84%   ▮▮▮▮▮▮▮▮▯▯         Charging · full in 38 min │
│        (mono 28)          25 W                      │
└─────────────────────────────────────────────────────┘
Power mode
  [ Power saver | Balanced | Performance ]
  Balanced: good performance, normal battery life   (caption, explains choice)
  Limit charging to 80%                             [●═══]
  Battery health                                 92%
──────────────────────────────────────────────────────
Power settings ↗
```

- Data comes from UPower (`/org/freedesktop/UPower/devices/DisplayDevice`):
  percentage, state, TimeToFull/TimeToEmpty, EnergyRate, and capacity for
  health. These are signals, which replaces the 5 s sysfs poll.
- Power modes use `net.hadess.PowerProfiles` (`ActiveProfile`). A profile the
  hardware does not offer is hidden. "Performance degraded" (thermal) is shown
  as a caption.
- The charge limit uses PowerDevil's charge threshold (only where the hardware
  supports it; otherwise the row is hidden).
- **Low battery behavior** (cross-cutting): at 20 % and 10 % a toast appears
  with [Power saver]. At 5 % the bar's battery glyph turns `negative`.

---

## 9. Power panel (`power`) — replaces `LogoutPrompt`

The KDE logout prompt is the last full-screen KDE dialog left in the common
path. The bar's power button opens this panel instead:

```
‹  Power
  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
  │    🔒    │ │    ☾     │ │    ↻     │ │    ⏻     │   tiles 96×88, radius lg
  │   Lock   │ │  Sleep   │ │ Restart  │ │ Shut down│
  └──────────┘ └──────────┘ └──────────┘ └──────────┘
  Log out     ·     Switch user     ·     Restart to firmware
──────────────────────────────────────────────────────
```

- **Lock** and **Sleep** act on the first tap, because they are harmless and
  reversible.
- **Restart, Shut down and Log out** use a `ConfirmTile`. The first tap fills
  the tile's border as a 5 s countdown ring in `accent` and changes the label to
  "Tap to restart". A second tap acts; when the countdown ends the action
  **cancels** (not proceeds). This keeps an accidental click harmless without a
  modal dialog. Android's power menu works the same way: a second, deliberate
  touch.
- Shift+click acts immediately, for power users.
- If unsaved work blocks a session-end (`ksmserver` reports it), the panel
  lists the blocking apps and offers [Cancel] [Proceed anyway].
- **Backend:** `org.kde.Shutdown` (logout / logoutAndReboot /
  logoutAndShutdown, so apps can save) and `org.freedesktop.ScreenSaver` Lock;
  sleep through `org.freedesktop.login1` Suspend. "Restart to firmware" shows
  only if `CanRebootToFirmwareSetup` is yes.
- **Keyboard:** the panel opens with focus on Lock. Arrow keys move between
  tiles, and Enter runs the same two-step flow.

---

## 10. Calendar & clock panel (`calendar`)

```
‹  Tuesday, October 27
       ‹   October 2026   ›
  Su  Mo  Tu  We  Th  Fr  Sa
               1   2   3       (Hebrew calendar day as caption, optional)
  …   26 (27)  28  29  30  31
Timer · Alarm · Stopwatch       (SegmentedControl)
  [ existing TimerRow, full width ]
World clocks
  New York        10:41      −7 h
```

- Today is shown with a 1.5 px `accent` ring, not a fill.
- The month changes by scrolling or with ‹ › (shared-axis X, `base`).
- The timer moves here from the large island when the panel is open. The large
  island's timer chip and row stay as they are.
- Calendar events (Akonadi) are phase 3 and only if the owner uses a calendar
  account; otherwise this panel has no event list (§12, D4).

---

## 11. Phase 3+: more tiles

Once panels exist, the four chips can grow into an Android-style tile set.
The candidate tiles are: Do not disturb (pauses toasts; island history still
fills), Night Light, Dark theme, Airplane mode, Keep awake (inhibit sleep),
Screenshot (Spectacle region), Screen record, Hotspot, Power saver and
Microphone mute.

- Layout: 4 per row, 2 rows (8 tiles). Horizontal paging with dots if there
  are more. The large island grows by 68 px.
- **Edit mode:** tap ✎, drag tiles to reorder, drag in from an "Available"
  tray, then save to `~/.config/aetherislandrc`.
- Also later: Wi‑Fi QR join (camera) and WPS, an island-native search
  replacing KRunner, and a media output switcher inside the media card.

---

## 12. Backend architecture

Replace the polling `SystemInfo` with one event-driven model per panel, each
exposed to QML as a singleton context object. QML only reads properties and
calls slots.

| Model (C++) | Library / D-Bus | Replaces | Notes |
|---|---|---|---|
| `NetworkModel` | **KF6 NetworkManagerQt** | `nmcli` polls in `SystemInfo` | `QAbstractListModel` of networks (merged by SSID); `activeConnection`, `state`, `connectivity`; slots `connect(ssid, psk, autoconnect)`, `cancel()`, `forget(uuid)`, `requestScan()`, `setEnabled()`, `details(uuid)` |
| `BluetoothModel` | **KF6 BluezQt** | `bluetoothctl` polls | devices model; `startDiscovery()/stop`; pairing agent object (registered only while panel open) |
| `AudioModel` | **KF6 PulseAudioQt** (talks to PipeWire-pulse) | `wpctl` polls | sinks, sources, sink-inputs models; default sink; peak monitor on demand |
| `PowerModel` | UPower + `net.hadess.PowerProfiles` + PowerDevil D-Bus | sysfs battery poll | battery, profiles, charge limit |
| `DisplayModel` | PowerDevil brightness + `org.kde.KWin.NightLight` | brightness poll | |
| `SessionActions` | `org.kde.Shutdown`, `login1`, ScreenSaver | `openPowerMenu()` | |

- **Build:** add `KF6NetworkManagerQt`, `KF6BluezQt` and `KF6PulseAudioQt` to
  `components/island/CMakeLists.txt`. The runtime packages are already
  installed. `install-island.sh` must install the `-dev` packages:
  `libkf6networkmanagerqt-dev`, `libkf6bluezqt-dev`, `libkf6pulseaudioqt-dev`.
- **The idle cost stays ~0.1 %.** Scans, discovery and peak monitors run only
  while their panel is open. Everything else is signals.
- **Compatibility:** `SystemInfo`'s properties (used by bar glyphs and chips)
  become thin forwarders to the new models, so `Island.qml` and `LargeIsland`
  keep working throughout the migration.
- **Security boundaries:** passwords cross QML → C++ once, go into the NM
  settings map, and are then zeroed. They are never written to logs or to
  `notifications.json`. All D-Bus input (SSIDs, device names) is shown as plain
  text (`Text.PlainText`), never as rich text, so a hostile SSID cannot inject
  markup.
- **D-Bus additions** to `org.aether.Island`: `OpenPanel(s)` and
  `ClosePanel()`, plus a `panel` property, so toasts (§2.2) and shortcuts can
  target panels.

### File layout

```
components/island/
  src/
    NetworkModel.h/.cpp   BluetoothModel.h/.cpp   AudioModel.h/.cpp
    PowerModel.h          DisplayModel.h          SessionActions.h
  qml/panel/
    PanelHost.qml         ← mode "panel": shared-axis stack, back logic, height
    WifiPanel.qml  WifiDetail.qml  WifiRow.qml
    BluetoothPanel.qml  BluetoothDetail.qml
    SoundPanel.qml  DisplayPanel.qml  BatteryPanel.qml
    PowerPanel.qml  CalendarPanel.qml
components/shared/AetherShared/
    PanelScaffold.qml PanelHeader.qml Switch.qml ListRow.qml SectionLabel.qml
    SegmentedControl.qml TextField.qml Button.qml LinearProgress.qml
    KeyValueRow.qml ConfirmTile.qml
components/island/qml/assets/glyphs/   (new)
    wifi-0 wifi-4 lock info chevron-left chevron-right check
    plane vpn hotspot headphones keyboard mouse phone speaker mic mic-off
    moon restart logout user-switch qr copy edit battery-charging
```

Each file stays under 500 lines (project rule). `WifiPanel` is the biggest, so
the row and detail page are separate files from the start.

---

## 13. Delivery phases

Each phase can ship on its own and is verified live (screenshots in `docs/`,
the same as the dock).

| Phase | Scope | Done when |
|---|---|---|
| **1 — Frame** | `panel` mode + `PanelHost`, shared-axis motion, primitives (§3.1), two-zone chips, `OpenPanel` D-Bus; a placeholder panel | open/close/back works with mouse, keyboard and handle; idle CPU unchanged; no blur/input mismatch mid-morph |
| **2 — Wi‑Fi** | `NetworkModel` + full §4 (list, inline password, errors, captive portal, detail, forget, share QR, Ethernet, VPN, airplane mode) | joining a new WPA2 network takes chip → row → password → Enter with no KDE dialog; a wrong password shakes and isn't saved; `nmcli` polls removed |
| **3 — Bluetooth & Sound** | §5, §6 | pair headphones inline (numeric comparison) and route audio to them in two taps |
| **4 — Power, Battery, Display, Calendar** | §7–§10; `LogoutPrompt` retired | shut down = 2 deliberate taps; Esc never triggers a destructive action |
| **5 — Tiles** | §11 | edit mode persists across restarts |

### Test checklist (each panel)

- Mouse, keyboard only, and touchpad flick: open, act, back, close.
- Pointer leaves mid-typing: the panel stays and the text is kept.
- Radio off, no hardware (desktop without Bluetooth/battery): the panel or row
  is hidden, never broken.
- Toggle quickly 10 times: the state ends correct, with no stuck spinner.
- A 50+ network list scrolls smoothly; no reorder under the pointer.
- SSID with emoji, RTL (Hebrew) text, 32 bytes, or `<b>` markup: displayed
  literally and elided correctly.
- Light scheme active: the island is still dark (DESIGN-SYSTEM §1.2).
- `make check` token lint passes: no literals.

---

## 14. Open decisions (owner)

- **D1 — Wi‑Fi secrets:** use KWallet/agent-owned (the Plasma default, which
  may ask to unlock KWallet) or system-owned (stored by NetworkManager in
  root-only files, no wallet prompts, connects before login)? *Recommendation:
  system-owned for personal Wi‑Fi on a single-user laptop; it removes every
  wallet prompt.*
- **D2 — Chip split vs. whole-chip opens panel:** Android 12+ made the
  Internet tile open its panel on any tap. The plan keeps the split (icon =
  toggle, label = panel). Confirm.
- **D3 — Power panel second-tap timeout:** 5 s and cancel when it expires
  (safe), versus Android's "hold to power off".
- **D4 — Calendar events:** is there a calendar account to show (Google via
  Akonadi), or should the panel stay as a date and timer page?
- **D5 — Hebrew dates** in the calendar grid: on or off by default?
