#!/usr/bin/env python3
"""Windows-style keyboard shortcuts for KDE Plasma 6 (Wayland or X11).

    windows-shortcuts.py            apply (saves the previous keys to backups/)
    windows-shortcuts.py --revert   restore the original keys (oldest backup)
    windows-shortcuts.py --list     print the mapping

Changes go through kglobalaccel's DBus API, so they take effect immediately and
survive restarts.
"""
import json
import subprocess
import sys
import time
from pathlib import Path

import dbus

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kglobal import bus, decode, encode, infos  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
BACKUPS = ROOT / "backups"
HOME = Path.home()

# (component, componentFriendly, action, actionFriendly, [keys], windows meaning)
MAP = [
    # Windows management
    ("kwin", "KWin", "Window Maximize", "Maximize Window", ["Meta+Up", "Meta+PgUp"], "Win+Up maximize"),
    ("kwin", "KWin", "Window Quick Tile Top", "Quick Tile Window to the Top", [], "free Win+Up"),
    ("kwin", "KWin", "Window Minimize", "Minimize Window", ["Meta+Down", "Meta+PgDown"], "Win+Down minimize"),
    ("kwin", "KWin", "Window Quick Tile Bottom", "Quick Tile Window to the Bottom", [], "free Win+Down"),
    ("kwin", "KWin", "Window Maximize Vertical", "Maximize Window Vertically", ["Meta+Shift+Up"], "Win+Shift+Up stretch"),
    ("kwin", "KWin", "Window Operations Menu", "Window Operations Menu", ["Alt+Space", "Alt+F3"], "Alt+Space window menu"),
    ("kwin", "KWin", "Overview", "Toggle Overview", ["Meta+Tab", "Meta+W"], "Win+Tab task view"),
    ("kwin", "KWin", "Walk Through Windows", "Walk Through Windows", ["Alt+Tab"], "Alt+Tab"),
    ("kwin", "KWin", "Walk Through Windows (Reverse)", "Walk Through Windows (Reverse)", ["Alt+Shift+Tab"], "Alt+Shift+Tab"),
    ("kwin", "KWin", "Show Desktop", "Peek at Desktop", ["Meta+D", "Meta+Comma"], "Win+D / Win+, desktop"),
    ("kwin", "KWin", "MinimizeAll", "Minimize all windows", ["Meta+M", "Meta+Shift+M"], "Win+M / Win+Shift+M"),
    ("kwin", "KWin", "view_zoom_in", "Zoom In", ["Meta+Plus", "Meta+Equal"], "Win+Plus magnifier"),
    ("kwin", "KWin", "view_zoom_out", "Zoom Out", ["Meta+Minus"], "Win+Minus magnifier"),
    ("kwin", "KWin", "view_actual_size", "Zoom to Actual Size", ["Meta+Esc", "Meta+0"], "Win+Esc exit magnifier"),
    # Ctrl+F1..F4 switch desktops in KDE but close tabs / open help in Windows apps.
    ("kwin", "KWin", "Switch to Desktop 1", "Switch to Desktop 1", [], "free Ctrl+F1"),
    ("kwin", "KWin", "Switch to Desktop 2", "Switch to Desktop 2", [], "free Ctrl+F2"),
    ("kwin", "KWin", "Switch to Desktop 3", "Switch to Desktop 3", [], "free Ctrl+F3"),
    ("kwin", "KWin", "Switch to Desktop 4", "Switch to Desktop 4", [], "free Ctrl+F4 (close tab)"),
    ("kwin", "KWin", "minimizeAllOthers", "Minimize all other windows", ["Meta+Home", "Meta+Shift+O"], "Win+Home minimize others"),
    ("kwin", "KWin", "Edit Tiles", "Toggle Tiles Editor", ["Meta+Z", "Meta+T"], "Win+Z snap layouts"),
    # Shell
    ("plasmashell", "plasmashell", "next activity", "Walk through activities", [], "free Win+A"),
    ("plasmashell", "plasmashell", "previous activity", "Walk through activities (Reverse)", [], "free Win+Shift+A"),
    ("plasmashell", "plasmashell", "manage activities", "Show Activity Switcher", [], "free Win+Q"),
    ("org.kde.krunner.desktop", "KRunner", "_launch", "KRunner", ["Meta+S", "Meta+Q", "Meta+R", "Alt+F2", "Search"], "Win+S/Q/R search & run"),
    ("org.kde.plasma.emojier.desktop", "Emoji Selector", "_launch", "Emoji Selector", ["Meta+Period", "Meta+Semicolon"], "Win+. / Win+; emoji"),
    # Screenshots (Snipping Tool)
    ("org.kde.spectacle.desktop", "Spectacle", "_launch", "Launch Spectacle", ["Print"], "PrtSc"),
    ("org.kde.spectacle.desktop", "Spectacle", "RectangularRegionScreenShot", "Capture Rectangular Region", ["Meta+Shift+S", "Meta+Shift+Print"], "Win+Shift+S snip"),
    ("org.kde.spectacle.desktop", "Spectacle", "FullScreenScreenShot", "Capture Entire Desktop", ["Meta+Print", "Shift+Print"], "Win+PrtSc"),
    ("org.kde.spectacle.desktop", "Spectacle", "ActiveWindowScreenShot", "Capture Active Window", ["Alt+Print"], "Alt+PrtSc"),
    ("org.kde.spectacle.desktop", "Spectacle", "RecordRegion", "Start/Stop Region Recording", ["Meta+Shift+R"], "free Win+R"),
    ("org.kde.spectacle.desktop", "Spectacle", "RecordScreen", "Start/Stop Screen Recording", ["Meta+Alt+R"], "Win+Alt+R record"),
    # Keyboard layout
    ("KDE Keyboard Layout Switcher", "Keyboard Layout Switcher", "Switch to Next Keyboard Layout", "Switch to Next Keyboard Layout", ["Meta+Space", "Meta+Alt+K"], "Win+Space layout"),
]

# Launchers that need a .desktop component (Ctrl+Shift+Esc etc.).
LAUNCHERS = [
    ("org.kde.plasma-systemmonitor.desktop", "System Monitor", ["Ctrl+Shift+Esc"], "Ctrl+Shift+Esc task manager"),
    ("systemsettings.desktop", "System Settings", ["Meta+I"], "Win+I settings"),
    ("org.kde.kinfocenter.desktop", "Info Center", ["Meta+Pause"], "Win+Pause system info"),
    ("aether-island-toggle.desktop", "Aether Island", ["Meta+N", "Meta+A"], "Win+N / Win+A open the island (controls)"),
    ("aether-console-toggle.desktop", "Aether Console", ["Meta+C"], "Win+C open the console shelf"),
    ("aether-new-desktop.desktop", "New Virtual Desktop", ["Meta+Ctrl+D"], "Win+Ctrl+D new desktop"),
    ("aether-close-desktop.desktop", "Close Virtual Desktop", ["Meta+Ctrl+F4"], "Win+Ctrl+F4 close desktop"),
]

VDESK = """#!/usr/bin/env bash
# Add / remove a virtual desktop (Win+Ctrl+D / Win+Ctrl+F4).
set -euo pipefail
K="qdbus6 org.kde.KWin /VirtualDesktopManager"
case "${1:-}" in
  add) n=$($K org.kde.KWin.VirtualDesktopManager.count); $K org.kde.KWin.VirtualDesktopManager.createDesktop "$n" "Workspace $((n+1))"
       sleep 0.2; qdbus6 org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut "Switch to Next Desktop" ;;
  remove) [[ $($K org.kde.KWin.VirtualDesktopManager.count) -gt 1 ]] && $K org.kde.KWin.VirtualDesktopManager.removeDesktop "$($K org.kde.KWin.VirtualDesktopManager.current)" ;;
esac
"""


def desktop_entry(name: str, arg: str) -> str:
    return (f"[Desktop Entry]\nType=Application\nName={name}\nExec={HOME}/.local/bin/aether-vdesk {arg}\n"
            f"Icon=virtual-desktops\nNoDisplay=true\n")


def action_id(comp, comp_friendly, action, friendly):
    return dbus.Array([comp, action, comp_friendly, friendly], signature="s")


def keys_arg(seqs):
    return dbus.Array([dbus.Struct([dbus.Array([dbus.Int32(encode(s))], signature="i")]) for s in seqs],
                      signature="(ai)")


def component_path(comp: str) -> str:
    return comp.replace(".", "_").replace("-", "_").replace(" ", "_")


def current_keys(comp: str, action: str):
    try:
        for s in infos(component_path(comp)):
            if str(s[0]) == action:
                return [decode(k) for k in s[6]]
    except dbus.DBusException:
        pass
    return None


def set_keys(ka, comp, comp_friendly, action, friendly, keys):
    aid = action_id(comp, comp_friendly, action, friendly)
    ka.doRegister(aid)
    # flags: SetPresent(2) | NoAutoloading(4) — store as the active user setting
    ka.setShortcutKeys(aid, keys_arg(keys), dbus.UInt32(2 | 4))
    ka.setForeignShortcutKeys(aid, keys_arg(keys))


def install_helpers():
    bin_dir = HOME / ".local/bin"
    apps = HOME / ".local/share/applications"
    bin_dir.mkdir(parents=True, exist_ok=True)
    apps.mkdir(parents=True, exist_ok=True)
    (bin_dir / "aether-vdesk").write_text(VDESK)
    (bin_dir / "aether-vdesk").chmod(0o755)
    (apps / "aether-new-desktop.desktop").write_text(desktop_entry("New Virtual Desktop", "add"))
    (apps / "aether-close-desktop.desktop").write_text(desktop_entry("Close Virtual Desktop", "remove"))
    subprocess.run(["kbuildsycoca6"], capture_output=True)
    # Win+M needs KWin's bundled "minimizeall" script.
    subprocess.run(["kwriteconfig6", "--file", "kwinrc", "--group", "Plugins", "--key", "minimizeallEnabled", "true"])
    subprocess.run(["qdbus6", "org.kde.KWin", "/KWin", "reconfigure"], capture_output=True)
    time.sleep(1.0)


def launcher_available(desktop: str) -> bool:
    return any((d / desktop).exists() for d in (Path("/usr/share/applications"), HOME / ".local/share/applications"))


def apply():
    install_helpers()
    _, ka = bus()
    saved, skipped = [], []
    for comp, cf, action, af, keys, why in MAP:
        before = current_keys(comp, action)
        if before is None and comp == "kwin":
            skipped.append(f"{action} ({why}): action not found")
            continue
        saved.append({"comp": comp, "cf": cf, "action": action, "af": af, "keys": before or []})
        set_keys(ka, comp, cf, action, af, keys)
    for desktop, name, keys, why in LAUNCHERS:
        if not launcher_available(desktop):
            skipped.append(f"{why}: {desktop} not installed")
            continue
        before = current_keys(desktop, "_launch")
        saved.append({"comp": desktop, "cf": name, "action": "_launch", "af": name, "keys": before or []})
        set_keys(ka, desktop, name, "_launch", name, keys)
    BACKUPS.mkdir(exist_ok=True)
    out = BACKUPS / f"shortcuts-{time.strftime('%Y%m%d-%H%M%S')}.json"
    out.write_text(json.dumps(saved, indent=1))
    print(f"applied {len(saved)} shortcuts; previous keys saved to {out}")
    for s in skipped:
        print("skipped:", s)


def revert():
    files = sorted(BACKUPS.glob("shortcuts-*.json"))
    if not files:
        sys.exit("no shortcut backup found")
    # The oldest backup holds the original KDE keys; later runs only saw our own mapping.
    _, ka = bus()
    for e in json.loads(files[0].read_text()):
        set_keys(ka, e["comp"], e["cf"], e["action"], e["af"], e["keys"])
    print("restored from", files[0])


if __name__ == "__main__":
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    if arg == "--revert":
        revert()
    elif arg == "--list":
        for *_, keys, why in MAP:
            print(f"{', '.join(keys) or '(none)':40} {why}")
        for _, _, keys, why in LAUNCHERS:
            print(f"{', '.join(keys):40} {why}")
    else:
        apply()
