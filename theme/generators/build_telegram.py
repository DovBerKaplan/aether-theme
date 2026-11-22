#!/usr/bin/env python3
"""Generate the Aethergram (Telegram Desktop fork) palettes: aether-dark / aether-light.tdesktop-palette.

Plain `key: #rrggbb[aa];` palettes (tdesktop takes one unzipped). Only the core keys are set; every
other key falls back through tdesktop's own palette chain (most end at windowBg / windowFg /
windowBgActive). The accent is the theme's cyan placeholder family, so aether-accent-sync recolours
it like the Kvantum and Aurorae themes, and lines marked `// on-accent` / `// on-deep` are re-inked
there by the fill's luma (dark ink on a bright fill, white on a dark one - Theme.qml's onAccent).

    build_telegram.py                 write into ~/.local/share/aether-apps/telegram (the templates)
    build_telegram.py --out DIR       ...or into DIR
    build_telegram.py --check         fail if a key is not in tdesktop's palette (offline: data/tdesktop_palette_keys.txt)
    build_telegram.py --refresh-keys  re-fetch that key list from upstream lib_ui
"""
import argparse
import re
import sys
import urllib.request
from pathlib import Path

from tokens import load

KEYS = Path(__file__).resolve().parent / "data/tdesktop_palette_keys.txt"
UPSTREAM = "https://raw.githubusercontent.com/desktop-app/lib_ui/master/ui/colors.palette"
OUT = Path.home() / ".local/share/aether-apps/telegram"

# The accent placeholders aether-accent-sync swaps for the island's colour (accent, hover, deep, ink).
ACCENT, HOVER, DEEP, INK = "#00f2fe", "#00dce6", "#00696f", "#00373a"
WHITE = "#ffffff"

T = load()
P = T["palette"]


def dark() -> list[tuple[str, str, str]]:
    """(key, colour, mark) - mark is "", "on-accent" or "on-deep"."""
    p = P
    return [
        # basic: the window is the glass body, the list beneath it its darker foot
        ("windowBg", p["ink-900"], ""),
        ("windowFg", p["fog-100"], ""),
        ("windowBgOver", p["ink-800"], ""),
        ("windowBgRipple", p["ink-700"], ""),
        ("windowFgOver", p["fog-100"], ""),
        ("windowSubTextFg", p["fog-500"], ""),
        ("windowSubTextFgOver", p["fog-300"], ""),
        ("windowBoldFg", p["fog-50"], ""),
        ("windowBoldFgOver", p["fog-50"], ""),
        ("windowBgActive", ACCENT, ""),
        ("windowFgActive", INK, "on-accent"),
        ("windowActiveTextFg", ACCENT, ""),
        ("windowShadowFg", "#000000", ""),
        ("windowShadowFgFallback", p["ink-950"], ""),
        ("shadowFg", "#00000030", ""),
        # buttons
        ("activeButtonBg", ACCENT, ""),
        ("activeButtonBgOver", HOVER, ""),
        ("activeButtonBgRipple", DEEP, ""),
        ("activeButtonFg", INK, "on-accent"),
        ("activeButtonFgOver", INK, "on-accent"),
        ("activeButtonSecondaryFg", INK + "b3", "on-accent"),
        ("activeLineFg", ACCENT, ""),
        ("activeLineFgError", p["red-200"], ""),
        ("lightButtonBg", p["ink-900"], ""),
        ("lightButtonBgOver", p["ink-800"], ""),
        ("lightButtonBgRipple", p["ink-700"], ""),
        ("lightButtonFg", ACCENT, ""),
        ("lightButtonFgOver", ACCENT, ""),
        ("attentionButtonFg", p["red-200"], ""),
        ("checkboxFg", p["fog-500"], ""),
        ("placeholderFg", p["fog-500"], ""),
        ("placeholderFgActive", p["fog-300"], ""),
        # menus: the island's raised glass, white-alpha rim
        ("menuBg", p["ink-750"], ""),
        ("menuBgOver", p["ink-600"], ""),
        ("menuBgRipple", p["graphite-800"], ""),
        ("menuIconFg", p["fog-300"], ""),
        ("menuIconFgOver", p["fog-100"], ""),
        ("menuSubmenuArrowFg", p["fog-500"], ""),
        ("menuFgDisabled", p["fog-500"], ""),
        ("menuSeparatorFg", "#ffffff17", ""),
        ("scrollBarBg", "#ffffff38", ""),
        ("scrollBarBgOver", "#ffffff5c", ""),
        # search field
        ("filterInputBorderFg", ACCENT, ""),
        ("filterInputActiveBg", p["ink-950"], ""),
        ("filterInputInactiveBg", p["ink-800"], ""),
        # own title bar (when the system one is off)
        ("titleBg", p["ink-850"], ""),
        ("titleBgActive", p["ink-850"], ""),
        ("titleFg", p["fog-500"], ""),
        ("titleFgActive", p["fog-100"], ""),
        ("titleButtonFg", p["fog-500"], ""),
        ("titleButtonBgOver", p["ink-700"], ""),
        ("titleButtonFgOver", p["fog-100"], ""),
        ("titleButtonCloseBgOver", p["red-700"], ""),
        ("titleButtonCloseFgOver", WHITE, ""),
        # folders strip
        ("sideBarBg", p["ink-950"], ""),
        ("sideBarBgActive", p["ink-800"], ""),
        ("sideBarBgRipple", p["ink-700"], ""),
        ("sideBarTextFg", p["fog-500"], ""),
        ("sideBarTextFgActive", ACCENT, ""),
        ("sideBarIconFg", p["fog-500"], ""),
        ("sideBarIconFgActive", ACCENT, ""),
        ("sideBarBadgeBg", ACCENT, ""),
        ("sideBarBadgeBgMuted", p["graphite-700"], ""),
        ("sideBarBadgeFg", INK, "on-accent"),
        # chat list
        ("dialogsBg", p["ink-850"], ""),
        ("dialogsNameFg", p["fog-100"], ""),
        ("dialogsChatIconFg", p["fog-100"], ""),
        ("dialogsDateFg", p["fog-500"], ""),
        ("dialogsTextFg", p["fog-500"], ""),
        ("dialogsTextFgService", p["fog-300"], ""),
        ("dialogsDraftFg", p["red-200"], ""),
        ("dialogsSendingIconFg", p["fog-500"], ""),
        ("dialogsSentIconFg", ACCENT, ""),
        ("dialogsUnreadBg", ACCENT, ""),
        ("dialogsUnreadBgMuted", p["graphite-700"], ""),
        ("dialogsUnreadFg", INK, "on-accent"),
        ("dialogsBgOver", p["ink-750"], ""),
        ("dialogsNameFgOver", p["fog-50"], ""),
        ("dialogsTextFgOver", p["fog-300"], ""),
        ("dialogsBgActive", DEEP, ""),
        ("dialogsNameFgActive", WHITE, "on-deep"),
        ("dialogsChatIconFgActive", WHITE, "on-deep"),
        ("dialogsDateFgActive", WHITE + "cc", "on-deep"),
        ("dialogsTextFgActive", WHITE + "cc", "on-deep"),
        ("dialogsTextFgServiceActive", WHITE, "on-deep"),
        ("dialogsDraftFgActive", WHITE, "on-deep"),
        ("dialogsSentIconFgActive", WHITE, "on-deep"),
        ("dialogsUnreadBgActive", WHITE, "on-deep"),
        ("dialogsUnreadFgActive", DEEP, ""),
        ("dialogsRippleBg", p["ink-700"], ""),
        ("dialogsRippleBgActive", INK, ""),
        # messages: incoming on the raised glass, outgoing in the deep accent
        ("msgInBg", p["ink-700"], ""),
        ("msgInBgSelected", p["ink-600"], ""),
        ("msgOutBg", DEEP, ""),
        ("msgOutBgSelected", INK, ""),
        ("msgInShadow", "#00000040", ""),
        ("msgOutShadow", "#00000040", ""),
        ("msgInServiceFg", ACCENT, ""),
        ("msgInServiceFgSelected", ACCENT, ""),
        ("msgOutServiceFg", WHITE, "on-deep"),
        ("msgOutServiceFgSelected", WHITE, "on-deep"),
        ("msgInDateFg", p["fog-500"], ""),
        ("msgOutDateFg", WHITE + "aa", "on-deep"),
        ("msgInReplyBarColor", ACCENT, ""),
        ("msgOutReplyBarColor", WHITE, "on-deep"),
        ("msgServiceBg", "#00000066", ""),
        ("msgServiceFg", WHITE, ""),
        ("historyTextInFg", p["fog-100"], ""),
        ("historyTextOutFg", WHITE, "on-deep"),
        ("historyLinkInFg", ACCENT, ""),
        ("historyLinkOutFg", WHITE, "on-deep"),
        ("historyOutIconFg", WHITE, "on-deep"),
        # composer
        ("historyComposeAreaBg", p["ink-850"], ""),
        ("historyComposeAreaFg", p["fog-100"], ""),
        ("historyComposeAreaFgService", p["fog-500"], ""),
        ("historyComposeIconFg", p["fog-500"], ""),
        ("historyComposeIconFgOver", ACCENT, ""),
        ("historySendIconFg", ACCENT, ""),
        ("historySendIconFgOver", HOVER, ""),
        ("historyComposeButtonBg", p["ink-850"], ""),
        ("historyComposeButtonBgOver", p["ink-750"], ""),
        ("historyComposeButtonBgRipple", p["ink-700"], ""),
    ]


def light() -> list[tuple[str, str, str]]:
    """Paper and graphite; the accent shows in its deep shade, which holds up on white."""
    p = P
    over = {
        "windowBg": p["paper-0"], "windowFg": p["graphite-950"], "windowBgOver": p["paper-100"],
        "windowBgRipple": p["fog-50"], "windowFgOver": p["graphite-950"], "windowSubTextFg": p["graphite-500"],
        "windowSubTextFgOver": p["graphite-700"], "windowBoldFg": p["graphite-900"], "windowBoldFgOver": p["graphite-900"],
        "windowBgActive": DEEP, "windowFgActive": WHITE, "windowActiveTextFg": DEEP,
        "windowShadowFgFallback": p["paper-100"], "shadowFg": "#00000018",
        "activeButtonBg": DEEP, "activeButtonBgOver": DEEP + "e6", "activeButtonBgRipple": INK,
        "activeButtonFg": WHITE, "activeButtonFgOver": WHITE, "activeButtonSecondaryFg": WHITE + "b3",
        "activeLineFg": DEEP, "activeLineFgError": p["red-700"],
        "lightButtonBg": p["paper-0"], "lightButtonBgOver": p["paper-100"], "lightButtonBgRipple": p["fog-50"],
        "lightButtonFg": DEEP, "lightButtonFgOver": DEEP, "attentionButtonFg": p["red-700"],
        "checkboxFg": p["graphite-500"], "placeholderFg": p["graphite-500"], "placeholderFgActive": p["graphite-700"],
        "menuBg": p["paper-0"], "menuBgOver": p["paper-100"], "menuBgRipple": p["fog-50"],
        "menuIconFg": p["graphite-500"], "menuIconFgOver": p["graphite-900"], "menuSubmenuArrowFg": p["graphite-500"],
        "menuFgDisabled": p["fog-500"], "menuSeparatorFg": "#0000001a",
        "scrollBarBg": "#0000003a", "scrollBarBgOver": "#0000005c",
        "filterInputBorderFg": DEEP, "filterInputActiveBg": p["paper-0"], "filterInputInactiveBg": p["paper-100"],
        "titleBg": p["paper-50"], "titleBgActive": p["paper-50"], "titleFg": p["graphite-500"],
        "titleFgActive": p["graphite-950"], "titleButtonFg": p["graphite-500"], "titleButtonBgOver": p["paper-100"],
        "titleButtonFgOver": p["graphite-950"],
        "sideBarBg": p["paper-100"], "sideBarBgActive": p["fog-50"], "sideBarBgRipple": p["fog-100"],
        "sideBarTextFg": p["graphite-500"], "sideBarTextFgActive": DEEP, "sideBarIconFg": p["graphite-500"],
        "sideBarIconFgActive": DEEP, "sideBarBadgeBg": DEEP, "sideBarBadgeBgMuted": p["fog-500"], "sideBarBadgeFg": WHITE,
        "dialogsBg": p["paper-50"], "dialogsNameFg": p["graphite-950"], "dialogsChatIconFg": p["graphite-950"],
        "dialogsDateFg": p["graphite-500"], "dialogsTextFg": p["graphite-500"], "dialogsTextFgService": p["graphite-700"],
        "dialogsDraftFg": p["red-700"], "dialogsSendingIconFg": p["fog-500"], "dialogsSentIconFg": DEEP,
        "dialogsUnreadBg": DEEP, "dialogsUnreadBgMuted": p["fog-500"], "dialogsUnreadFg": WHITE,
        "dialogsBgOver": p["paper-100"], "dialogsNameFgOver": p["graphite-950"], "dialogsTextFgOver": p["graphite-500"],
        "dialogsRippleBg": p["fog-50"],
        "msgInBg": p["paper-0"], "msgInBgSelected": p["fog-50"], "msgOutBg": ACCENT + "2e", "msgOutBgSelected": ACCENT + "4d",
        "msgInShadow": "#0000001f", "msgOutShadow": "#0000001f",
        "msgInServiceFg": DEEP, "msgInServiceFgSelected": DEEP, "msgOutServiceFg": DEEP, "msgOutServiceFgSelected": DEEP,
        "msgInDateFg": p["graphite-500"], "msgOutDateFg": p["graphite-500"],
        "msgInReplyBarColor": DEEP, "msgOutReplyBarColor": DEEP, "msgServiceBg": "#00000040",
        "historyTextInFg": p["graphite-950"], "historyTextOutFg": p["graphite-950"],
        "historyLinkInFg": DEEP, "historyLinkOutFg": DEEP, "historyOutIconFg": DEEP,
        "historyComposeAreaBg": p["paper-0"], "historyComposeAreaFg": p["graphite-950"],
        "historyComposeAreaFgService": p["graphite-500"], "historyComposeIconFg": p["graphite-500"],
        "historyComposeIconFgOver": DEEP, "historySendIconFg": DEEP, "historySendIconFgOver": DEEP + "e6",
        "historyComposeButtonBg": p["paper-0"], "historyComposeButtonBgOver": p["paper-100"],
        "historyComposeButtonBgRipple": p["fog-50"],
    }
    # Same keys as the dark palette; on light, anything on the deep accent wears the on-deep mark.
    rows = []
    for key, value, mark in dark():
        v = over.get(key, value)
        m = mark
        if mark == "on-accent":
            m = "on-deep"
        if key in ("msgOutServiceFg", "msgOutServiceFgSelected", "msgOutDateFg", "msgOutReplyBarColor",
                   "historyTextOutFg", "historyLinkOutFg", "historyOutIconFg"):
            m = ""   # the light outgoing bubble is a pale tint, not the deep fill
        rows.append((key, v, m))
    return rows


def render(name: str, rows) -> str:
    head = (f"// {name}: Aether for Aethergram (Telegram Desktop), generated by theme/generators/build_telegram.py.\n"
            "// The cyan is a placeholder: aether-accent-sync re-inks it to the island's accent.\n")
    return head + "".join(f"{k}: {v};" + (f" // {m}" if m else "") + "\n" for k, v, m in rows)


def known() -> set[str]:
    return {l.strip() for l in KEYS.read_text().splitlines() if l.strip() and not l.startswith("#")}


def refresh() -> None:
    text = urllib.request.urlopen(UPSTREAM, timeout=30).read().decode()
    keys = re.findall(r"^([A-Za-z][A-Za-z0-9_]*):", text, flags=re.M)
    KEYS.write_text("# Telegram Desktop palette keys, from desktop-app/lib_ui ui/colors.palette (master).\n"
                    "# Refresh: python3 theme/generators/build_telegram.py --refresh-keys\n" + "\n".join(keys) + "\n")
    print(f"{len(keys)} keys -> {KEYS}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, default=OUT)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--refresh-keys", action="store_true")
    a = ap.parse_args()
    if a.refresh_keys:
        refresh()
        return 0
    themes = {"aether-dark": dark(), "aether-light": light()}
    if a.check:
        keys, bad = known(), []
        for name, rows in themes.items():
            seen = set()
            for k, v, _ in rows:
                if k not in keys:
                    bad.append(f"{name}: unknown key {k}")
                if k in seen:
                    bad.append(f"{name}: duplicate key {k}")
                seen.add(k)
                if not re.fullmatch(r"#[0-9a-f]{6}([0-9a-f]{2})?", v):
                    bad.append(f"{name}: {k}: bad colour {v!r}")
        if bad:
            print("\n".join(bad), file=sys.stderr)
            return 1
        print(f"telegram palettes ok ({len(themes['aether-dark'])} keys, all known to tdesktop)")
        return 0
    a.out.mkdir(parents=True, exist_ok=True)
    for name, rows in themes.items():
        (a.out / f"{name}.tdesktop-palette").write_text(render(name, rows))
        print("built", a.out / f"{name}.tdesktop-palette")
    return 0


if __name__ == "__main__":
    sys.exit(main())
