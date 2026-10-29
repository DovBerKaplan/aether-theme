# ZCode RTL kit

ZCode (the Z.ai Electron desktop app, `/opt/ZCode`) has RTL UI logic but its
renderer opens LTR. The kit flips it to RTL and keeps it flipped:

- `zcode-rtl` — launch wrapper: `zcode --lang=he --remote-debugging-port=9223`.
  The port is loopback-only and lets the injector and inspector reach the
  renderer.
- `zcode-rtl-inject.mjs` — resident injector (systemd user service
  `zcode-rtl-inject`). Waits for a wrapped ZCode, then in every page window:
  sets `documentElement dir=rtl` and pushes `rtl.css`, re-applied on every
  navigation (`Page.addScriptToEvaluateOnNewDocument`) and guarded by a
  MutationObserver. Follows new windows, backs off while the app is closed.
  Reads its CSS from `~/.config/aether/zcode-rtl.css` (edit freely, no
  reinstall needed) or `ZCODE_RTL_CSS`.
- `zcode-rtl-apply.mjs` — manual live tweaks during development: `css <file>`,
  `flip`, `revert`, `js '<expr>'`.
- `zcode-rtl-inspect.mjs` — read-only DOM survey (Hebrew elements, computed
  directions, selectors).

## The desktop-file war (why the system patch is needed)

The app rewrites/removes `~/.local/share/applications/zcode.desktop` at
startup (Electron protocol registration), which eats any local override —
the next plain launch then runs without flags. The durable fix patches the
SYSTEM desktop file once (re-apply after app package updates):

```bash
sudo sed -i 's|^Exec=/opt/ZCode/zcode|Exec='"$HOME"'/.local/bin/zcode-rtl|' /usr/share/applications/zcode.desktop
```

Undo everything: `systemctl --user disable --now zcode-rtl-inject; rm
~/.local/bin/zcode-rtl*; rm ~/.config/aether/zcode-rtl.css
~/.config/systemd/user/zcode-rtl-inject.service`, revert the system desktop
file (keep a copy before patching), `kbuildsycoca6`.

Security note: the DevTools port binds to 127.0.0.1 only; anything running as
your user can control the app while the flag is on. Remove it from
`zcode-rtl` if that ever bothers you (the injector dies with it).
