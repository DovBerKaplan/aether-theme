# Widgets Spec — removable YouTube Music, and a KDE Connect widget

Status: **W1, C1, C2, C3 and C4 built** (2026-10-28): widget stack with edit mode, removable YouTube Music (closes Pear, disables autostart), and the KDE Connect device core - compact card, Overview panel (ring, ping, clipboard, share, features, pairing, unpair), fake backend (`AETHER_CONNECT_FAKE=1`); C2 adds the phone Notifications page (live list, dismiss, reply, the notification's own buttons, clear all, card badge) and keeps the plain forwarded copies out of the island history and off disk. C3 adds the Files page (Choose files via kdialog, browse/disconnect the phone storage, received files), drop targets on the card, the hero and a drop zone, and the island's `activity` mode with the file-received card. **Not verified:** a real drag from another app onto the card (no way to script one; "Choose files" is the sure path), and sending to a real phone. C4 adds the call card (ringing / in a call / missed; the daemon sends no "ended", so each state has its own time on screen and the card shows it too), the Phone media page (title, seek, volume, player choice, transport), and an opt-in low-battery alert; activities now update in place. **Not verified on a real phone:** an actual call, and phone media while something plays. C5 onward is still a plan. **Not yet verified on a real notification:** the daemon object's property names are read defensively and were checked only against the fake data.

Two requests, one mechanism:

1. The YouTube Music widget must be **removable** (and re-addable).
2. A **KDE Connect widget** with a very high level of integration with the owner's phones — control, not just status — in the island's design language.

Both need the large island to stop hard-coding "media card, then tiles" and become a small **widget stack** the user arranges in the same edit mode as the tiles. Read [DESIGN-SYSTEM.md §1](DESIGN-SYSTEM.md) and [PANELS-SPEC.md](PANELS-SPEC.md) first: the rules there (glass not paint, accent is rare, state in small details, panels instead of dialogs, event-driven, RTL + Hebrew) all apply.

---

## 1. What exists today (verified on this machine)

### 1.1 The YouTube Music widget is wired in four places

| Piece | Where | Effect when the widget is "removed" |
|---|---|---|
| The card | `MediaCard` in `LargeIsland.qml` (always present) | gone from the stack |
| "The bar becomes the app" mode | `Island.qml` `mode: "media"`, D-Bus `Media()`, art-tap → `searchRequested` | unreachable; `Media()` becomes a no-op |
| The app itself | Pear Desktop under `~/.local/opt/pear-desktop`, launched by `media.launch()` (`MediaController.h`), autostart `~/.config/autostart/pear-desktop.desktop` | **stopped**, autostart disabled (see D1) |
| Window placement | KWin script `aether-media` + window rule | stays installed, inert (it only matches the Pear window) |

`MediaController.h` also watches MPRIS (YouTube players only) and `AudioLevels.h` feeds the equalizer; both should be idle while the widget is off.

### 1.2 KDE Connect (kdeconnect 26.08, daemon on the session bus)

`kdeconnect-cli -l`: **OnePlus 15** (paired, reachable over LAN), **Pad 3** and **OnePlus Nord CE 3 Lite 5G** (paired, offline now).

Per device the daemon already exposes (object `/modules/kdeconnect/devices/<id>/...`):

| Plugin object | Useful API | Use in the widget |
|---|---|---|
| device | props `name type isReachable isPaired pairState statusIconName verificationKey reachableAddresses`; `requestPairing acceptPairing cancelPairing unpair setPluginEnabled loadedPlugins` | device switcher, pairing, plugin toggles |
| battery | `charge`, `isCharging`, signal `refreshed(bool,int)` | battery ring |
| connectivity_report | `cellularNetworkType`, `cellularNetworkStrength` | signal bars + "5G/LTE" |
| notifications | `activeNotifications()`, `sendAction`, `sendReply`, signals `notificationPosted/Updated/Removed/allNotificationsRemoved` | phone notifications with reply and actions |
| sms | `sendSms(addresses, text, attachments)`, `requestAllConversations`, `requestConversation`, `launchApp` | compose/send (reading: §5) |
| share | `shareText`, `shareUrl(s)`, `openFile`, signal `shareReceived` | send / receive |
| clipboard | `sendClipboard`, `isAutoShareDisabled` | push clipboard, auto-share switch |
| findmyphone | `ring()` | ring the phone |
| ping | `sendPing()`/`sendPing(msg)` | ping |
| mprisremote | `title artist album isPlaying position length volume canSeek`, `sendAction`, `seek` | control what the **phone** plays |
| sftp | `mountAndWait`, `mountPoint`, `getDirectories`, `unmount` | browse phone files |
| remotekeyboard / remotecontrol | `sendKeyPress`, `moveCursor`, `sendCommand` | type on / drive the phone |
| telephony | signal `callReceived(event, number, contact)` | incoming-call card |
| contacts | `synchronizeRemoteWithLocal`, signal `localCacheSynchronized` | caller / recipient names |
| daemon | `devices(onlyReachable, onlyPaired)`, `deviceNames`, signals `deviceAdded/Removed/VisibilityChanged/deviceListChanged`, `pairingRequests`, `selfId` | device list, pairing requests |

Also loaded: `runcommand`, `systemvolume`, `presenter`, `mousepad`, `digitizer`, `pausemusic`, `findthisdevice`, `shareinputdevicesremote` (phone-initiated; only exposed as on/off toggles).

Today phone notifications reach the island as plain **"KDE CONNECT"** cards (kdeconnectd forwards them to `org.freedesktop.Notifications`, the island's silent sink + toasts): no app icon, no reply, no actions.

---

## 2. The widget framework (shared by both requests)

### 2.1 Model
The large island's content becomes: header, **widget stack**, tile grid, sliders, (timer row), notifications.

- Registry (QML, `Widgets.qml` singleton or a `WidgetStore` section in `TileStore.h`): `{id, label, glyph, component, defaultOn, available}`.
  - `media` — YouTube Music card (`MediaCard`).
  - `connect` — KDE Connect card (new). `available` only while KDE Connect is installed; `defaultOn` only if at least one device is paired.
- Persistence, same file as the tiles: `~/.config/aetherislandrc` → `[Widgets] Order=media,connect`. Unknown ids dropped, duplicates dropped, missing file → defaults (existing behavior is preserved: today's users get `media`).
- Height is content-driven as now (`contentHeight` = header + stack + tiles + sliders); the glass springs to the new height. Removing a widget shrinks the island.

### 2.2 Edit mode (the pencil that already exists)
The pencil switches the **whole** large island to edit mode, not only the tiles:
- Each widget card shows a **minus badge** (remove) and can be **dragged** to reorder (same drag pattern as `TileGrid`: held item follows the pointer, drop slot outlined in accent, `ListModel.move` on release, an accepting `MouseArea` so a drop never reaches the close-outside area).
- Below the tiles' tray, an **"Available widgets"** tray lists the removed ones with a plus.
- Removing/adding takes effect immediately and is saved immediately (no "Save").
- Hebrew/RTL: badges and slots mirror through `I18n.rtl` like the tiles.

### 2.3 Removing the YouTube Music widget (what "remove" does)
1. Card hidden; `Media()` and the art-tap entry are no-ops; media mode cannot start.
2. `MediaController` stops watching MPRIS and `AudioLevels` stops (idle CPU back to baseline).
3. The Pear app is **closed** and its autostart entry is disabled (`Hidden=true`, file kept so re-adding is one tap) — decided (D1). "Removed" means **invisible and not running in the background** (owner, 2026-10-28):
   - the whole process tree is gone (not just the window): ask it to quit over MPRIS `Quit`, then `SIGTERM` the process group, then `SIGKILL` after 3 s — no hidden window, **no tray icon**, nothing playing unseen;
   - nothing relaunches it: autostart disabled, `media.launch()` and the `Media()` D-Bus method are no-ops, the KWin script has no window to seat;
   - `MediaController` stops watching MPRIS and `AudioLevels` stops capturing.
   Verified with `pgrep -f youtube-music` (empty), no `org.mpris.MediaPlayer2.*youtube*` / `pear*` name on the bus, no status-notifier item, and idle CPU/RAM back to the pre-widget baseline.
4. Re-adding restores 1–3 (and launches Pear again the next time it is needed, as today).
The KWin script and window rule stay installed; they do nothing without the Pear window.

---

## 3. The KDE Connect widget

### 3.1 The card (in the stack) — compact, 84 px like the media card

```
┌──────────────────────────────────────────────────────────┐
│  ▯  OnePlus 15                          ▂▄▆  5G   19 %  │   glass card, radius card
│     Connected · Wi‑Fi                                    │
│  ( ring )  ( send )  ( 💬 3 )  ( 🔔 5 )  ( files )   ›   │   quick actions, 34 px circles
└──────────────────────────────────────────────────────────┘
```
- Left: a phone/tablet glyph (from `type`), name, one status line (Connected · Wi‑Fi / Offline since 14:02 / Pairing request).
- Right: signal bars + network type, and the battery as a **ring** with mono numerals; a charging bolt is a small detail, **not** a colored fill. Accent is used only for the one thing that matters now (an incoming call, a pairing request, a received file) — rule §1.3.
- Quick actions: **ring**, **send** (clipboard / link), **messages** badge, **notifications** badge, **files**. Badges are small counters, no text preview on the card (privacy default, see §7).
- Tap the card → the Connect **panel** (§3.2). Long-press / right-click a quick action → its page.
- Several devices: the card shows the *selected* one (last reachable by default, then the saved choice); two small dots/chips switch devices inline. Offline devices are dimmed, never hidden.
- No paired device: "Connect your phone" with the one-line hint and a button that opens the pairing page.

### 3.2 The panel (`PanelHost` id `connect`, same frame as every other panel)
Pages (shared-axis X like the rest):

1. **Overview** — device switcher chips; hero card (name, type, link: LAN/Bluetooth/USB, battery ring, network); actions grid:
   Ring phone (two-tap, see §7) · Ping · Send clipboard · Share text/link (inline field) · Send files (§3.4) · Browse files · Messages · Notifications.
2. **Notifications** — the phone's notifications, newest first: app, title, text, time; **dismiss** (swipe/✕), **reply** inline when the notification offers it (`sendReply`), **action buttons** (`sendAction`). "Clear all". Updates live from the `notification*` signals; no polling.
3. **Messages** — compose-and-send to a contact or number (contacts from the synced cache), recent recipients; reading threads depends on §5. Incoming SMS already appear as notifications with a reply action, which covers the common case from page 2.
4. **Phone media** — what the phone is playing: title/artist/progress, play/pause/next/prev, seek, volume (`mprisremote`). Same look as the media card but marked as the phone's.
5. **Files** — mount via `sftp.mountAndWait`, then open the mount point in the file manager (`xdg-open`); list the phone's exposed folders (`getDirectories`); unmount button. Drag-and-drop sends (§3.4).
6. **Remote** — phone keyboard (a text field that types on the phone via `remotekeyboard`) and a trackpad area (`remotecontrol.moveCursor` / `sendCommand`) — only when the phone reports support.
7. **Settings** — per-device plugin switches (`setPluginEnabled`: notifications, clipboard auto-share, SMS, files, battery alerts…), "Auto-share clipboard" (`isAutoShareDisabled`), pairing key (`verificationKey`), **Unpair** (two-tap), "Open KDE Connect settings ↗" (`kcmshell6 kcm_kdeconnect`).

Pairing (any device the daemon lists as unpaired/visible, or a `pairingRequests` entry): an inline card like the Bluetooth one — "Confirm that OnePlus 15 shows this key **1512E695**" with Pair / Cancel (`requestPairing`, `acceptPairing`, `cancelPairing`).

### 3.3 Live activities (the island reacts, then gets out of the way)
The bar/large island grows a transient card, auto-dismissing:
- **Incoming / ongoing / missed call** (`telephony.callReceived(event, number, contact)`): caller name (or number), event, elapsed time while talking; the accent is allowed here. Actions are limited to what the plugin supports (dismiss; the pause-music behavior is the plugin's own). No answer-from-PC promise — the API does not offer it.
- **File received** (`share.shareReceived`): name + **Open** / **Show in folder**.
- **Pairing request** (see above).
- **Low phone battery** (optional, off by default): ≤20 % and not charging, at most once per 6 h per device.
Each respects Do-not-disturb-like behavior once that exists; until then they follow the toasts' rules (never cover the media panel; wait while the island is expanded and showing history).

### 3.4 Drag and drop (the Android-level nicety)
A `DropArea` on the card and on the Overview/Files pages: dropping files → `share.shareUrls`, dropping a URL → `shareUrl`, dropping text → `shareText`, with a progress line and a "Sent to OnePlus 15" confirmation. Must be verified to work on a layer-shell surface with drags from other Wayland clients (§8 risk R2).

### 3.5 Look and feel
Tokens only (`Theme`/`Tokens`), the shared primitives (`ListRow`, `Button`, `Switch`, `SegmentedControl`, `ConfirmTile`, `TextField`, `LinearProgress`), glass cards, grain, calm type, mono numerals for battery/time, hairline separators, `tint-hover/attention` states, shared-axis motion, short ease-out presses. New glyphs (`phone`, `tablet`, `ring`, `send`, `message`, `folder`, `signal-0..4`, `bolt`, `share`) in the existing monoline style. Everything through `I18n.tr`/`f` with Hebrew in `strings_he.js`; RTL mirrored; the phone's own text (names, messages) is shown as plain text and bidi-isolated where needed.

---

## 4. Backend — `components/island/src/ConnectModel.h` (new, header-only like the others)

Raw D-Bus on the **session** bus (`org.kde.kdeconnect`), no KDE Connect library (its headers are not needed and the daemon API above is enough). Note: the daemon's introspection has a duplicate-method bug, so use direct `QDBusMessage` calls, never `QDBusInterface` introspection.

- **Device list** (`QAbstractListModel` or `QVariantList` like `NetworkModel`): from `devices(false, false)` + `deviceNames`, kept fresh by `deviceAdded/Removed/VisibilityChanged/deviceListChanged`; per device: id, name, type, reachable, paired, pairState, link, battery, charging, cellular type/strength.
- **Selected device**: id persisted in `[Connect] Device=<id>`; default = last reachable. Plugin signals (battery, notifications, mprisremote, telephony, share, sftp) are subscribed **only for the selected/visible device** — event-driven, no polling; the idle cost stays ~0.1 %.
- **Invokables**: `ring`, `ping`, `sendClipboard`, `shareText/Url/Files`, `sendSms`, `requestAllConversations`, `notificationDismiss/Reply/Action`, `mediaAction/seek`, `mountFiles/openFiles/unmount`, `typeText/moveCursor/click`, `requestPairing/acceptPairing/cancelPairing/unpair`, `setPluginEnabled`, `openSettings`.
- **Notifications cache** (in memory only): ids from `activeNotifications()` + per-notification properties; never written to disk by the island.
- **Live activities** feed a small `ActivityQueue` in QML (`Island.qml`), one card at a time, FIFO with priority (call > pairing > file > battery).
- **De-duplication with the forwarded KDE Connect notifications**: kdeconnectd already posts a plain notification for each phone notification. With the widget on, those entries are **hidden from the island's history list** (matched by app name "KDE Connect"); the toasts still alert in real time (decision D3). The history file `~/.local/share/aether-island/notifications.json` must not store phone message bodies — exclude them from `NotificationStore`.
- **Fake backend for UI work and screenshots**: env `AETHER_CONNECT_FAKE=1` swaps the model's data source for a fixture (three devices, battery 19 %, 5 notifications, a call), so every screen can be built and verified without touching a phone.

---

## 5. SMS: what is and is not possible (to be settled by a spike)

The `sms` plugin object exposes only **requests** (`requestAllConversations`, `requestConversation`, `sendSms`, `launchApp`); I found **no D-Bus signal or property carrying conversation data** (KDE's own SMS app uses the plugin's data path directly). So:
- **Certain:** send an SMS (`sendSms`), reply to message notifications (`sendReply`), open the KDE Connect SMS app (`launchApp`).
- **Spike (needs the owner's OK, because it asks the phone to send message history to the PC):** call `requestAllConversations` while watching the bus for conversation signals on the sms/conversations objects. If data arrives, build the Messages list/threads on it; if not, Messages stays "compose + reply from notifications + open app". No guessing before the spike.

---

## 6. Phases (each shippable; each verified live like the panels)

| Phase | Scope | Done when |
|---|---|---|
| **W1 — widget framework** | Registry + `[Widgets]` persistence, `WidgetStack` in `LargeIsland`, edit mode for widgets (remove/reorder/add tray), YouTube Music **removal semantics** (§2.3), RTL/Hebrew | the YouTube Music card can be removed and re-added; Pear stops/starts; island height follows; idle CPU back to baseline when off; order survives restart |
| **C1 — device core** | `ConnectModel` (list, battery, connectivity, pairing, selection), compact card, Overview page: ring (two-tap), ping, send clipboard, share text/link, plugin switches, pairing card, fake backend | the card shows OnePlus 15 with its real battery/network; pairing card works with a fixture; switching devices works; no polling |
| **C2 — notifications** | Notifications page: live list, dismiss, reply, actions, clear all; history de-dup; no bodies persisted | replying to a phone notification from the island reaches the phone (owner-approved test) |
| **C3 — files & drop** | Browse (sftp), send files, drag-and-drop, file-received activity | a dropped file arrives on the phone; received files offer Open/Show in folder |
| **C4 — calls & phone media** | Call live activity, phone-media page, low-battery alert (off by default) | a (real or fixture) call shows and clears correctly |
| **C5 — messages & remote** | SMS spike → Messages page per its result; Remote keyboard/trackpad | Messages matches what the spike proved; typing on the phone works |

Every phase: `make`/install, screenshots in Hebrew and English, `docs/` updated.

---

## 7. Safety, privacy, and how this will be tested

- **Audible or visible effects on the phone are never triggered without the owner's explicit OK in that moment** — ring, ping, share, SMS, pairing, unpair. In the UI: ring/unpair are two-tap (`ConfirmTile` style, 5 s). In testing: read-only calls and the fake backend by default; real actions only when the owner agrees and the effect is stated first.
- **Privacy defaults:** the compact card shows counts, not message text; notification/SMS bodies live in memory only and are never logged; nothing about the phone is written to the journal beyond device name and event type.
- **Network:** nothing here touches Wi‑Fi/Bluetooth state; KDE Connect's own link handling is left alone (we do not toggle link providers).
- **No disruption while testing** (lesson from the Wi‑Fi work): no test may disconnect the owner's network or Bluetooth devices.

## 8. Risks

- **R1 SMS data** may not be readable (§5) → the Messages page degrades to send/reply/open-app.
- **R2 Drag-and-drop** onto a layer-shell surface may not receive drops from every client → fallback: a "Send file…" button using the portal file chooser, plus paste-to-send.
- **R3 Notification de-dup** matches on the app name "KDE Connect"; if KDE changes it, duplicates reappear (harmless).
- **R4 Daemon API drift** (the plugin objects are KDE-internal) → keep all calls inside `ConnectModel` with graceful "not available" states per plugin (`hasPlugin`/`loadedPlugins`).
- **R5 Island height**: stack + tiles + sliders can exceed small screens → the existing scroll/clip behavior of the expanded island applies; the compact card is capped at 84 px.

## 9. Files

New: `components/island/src/ConnectModel.h`, `components/island/qml/{ConnectCard,ConnectPanel,ConnectNotifications,ConnectFiles,ConnectMedia,ConnectRemote,ConnectSettings,ActivityCard,WidgetStack}.qml`, glyphs, `strings_he.js` entries.
Changed: `LargeIsland.qml` (widget stack + widget edit mode), `Island.qml` (activities, `Media()` guard, panel id `connect`), `PanelHost.qml` (route), `MediaController.h` (start/stop), `TileStore.h` (`[Widgets]`, `[Connect]`), `NotificationStore.h` (exclude phone bodies), `install/install-island.sh` (autostart toggle helpers), docs.

## 10. Open decisions (owner)

- **D1 — decided (2026-10-28):** removing the YouTube Music widget **closes Pear and disables its autostart**; re-adding restores both.
- **D2 — assumed (change anytime):** the card follows the **last reachable** device; the user can pin one.
- **D3 — assumed (change anytime):** keep the toast alerts and **hide the duplicate entries from the island history** while the widget is on.
- **D4 — still needs a yes at the moment it runs:** the SMS spike asks the phone for its message history once; it will be announced right before and report counts only, never text.
- **D5 — assumed (change anytime):** the incoming-call card is **on**; the low-battery alert is **off** until enabled.
