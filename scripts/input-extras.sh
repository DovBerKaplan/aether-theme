#!/usr/bin/env bash
# Input tweaks that sit beside windows-shortcuts.py:
#  - Alt+Shift switches keyboard layout (Windows habit)
#  - Touchpad: tap to click, regular (not natural) scrolling, two-finger click = right click
#  (Win+N / Win+A open the Aether Island: bound by windows-shortcuts.py)
set -euo pipefail

kwriteconfig6 --file kxkbrc --group Layout --key ResetOldOptions true
kwriteconfig6 --file kxkbrc --group Layout --key Options "grp:alt_shift_toggle"
dbus-send --session --type=signal /Layouts org.kde.keyboard.reloadConfig

# Every touchpad KWin knows about (Wayland); settings persist in kcminputrc.
python3 - <<'EOF'
import dbus, subprocess
b = dbus.SessionBus()
mgr = dbus.Interface(b.get_object("org.kde.KWin", "/org/kde/KWin/InputDevice"), "org.freedesktop.DBus.Properties")
for dev in mgr.Get("org.kde.KWin.InputDeviceManager", "devicesSysNames"):
    p = dbus.Interface(b.get_object("org.kde.KWin", f"/org/kde/KWin/InputDevice/{dev}"), "org.freedesktop.DBus.Properties")
    get = lambda k: p.Get("org.kde.KWin.InputDevice", k)
    if not get("touchpad"):
        continue
    for key, val in (("tapToClick", True), ("naturalScroll", False), ("scrollTwoFinger", True),
                     ("disableWhileTyping", True), ("clickMethodClickfinger", True)):
        p.Set("org.kde.KWin.InputDevice", key, dbus.Boolean(val))
    group = ["--group", "Libinput", "--group", str(get("vendor")), "--group", str(get("product")), "--group", str(get("name"))]
    for key, val in (("TapToClick", "true"), ("NaturalScroll", "false"), ("ClickMethod", "2")):
        subprocess.run(["kwriteconfig6", "--file", "kcminputrc", *group, "--key", key, val], check=True)
    print("touchpad configured:", get("name"))
EOF

echo "input extras applied"
