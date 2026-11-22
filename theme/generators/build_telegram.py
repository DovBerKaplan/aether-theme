#!/usr/bin/env python3
"""Generate the Aethergram (Telegram Desktop fork) themes: aether-dark / aether-light, each as a plain
.tdesktop-palette and as a .tdesktop-theme (a zip of that palette and a chat background).

Plain `key: #rrggbb[aa];` palettes. The core keys and their hover / active / selected variants are set;
every other key falls back through tdesktop's own palette chain. The accent is the theme's cyan
placeholder family, so aether-accent-sync recolours it like the Kvantum and Aurorae themes, and the
marked lines are resolved there for the island's colour (see tg_fix in system/aether-accent-sync):
`// on-ROLE` an ink that reads on that fill, `// beside-ROLE #a #b` a fill that shares that ink, and
`// tint L S` a surface tinted by the chosen colour's hue. The background is drawn by the same code
(tg_background), so the templates here are what the sync writes when no colour is chosen.

    build_telegram.py                 write into ~/.local/share/aether-apps/telegram (the templates)
    build_telegram.py --out DIR       ...or into DIR
    build_telegram.py --check         fail on a key tdesktop does not know (offline: data/tdesktop_palette_keys.txt),
                                      or a text pair under 4.5:1 for any of the test accents, dark and light
    build_telegram.py --refresh-keys  re-fetch that key list from upstream lib_ui
"""
import argparse
import colorsys
import importlib.machinery
import importlib.util
import re
import sys
import urllib.request
from pathlib import Path

from tokens import load

HERE = Path(__file__).resolve().parent
KEYS = HERE / "data/tdesktop_palette_keys.txt"
UPSTREAM = "https://raw.githubusercontent.com/desktop-app/lib_ui/master/ui/colors.palette"
OUT = Path.home() / ".local/share/aether-apps/telegram"


def _sync():
    """system/aether-accent-sync as a module: the recolouring, marks and background live there."""
    path = str(HERE.parents[1] / "system/aether-accent-sync")
    loader = importlib.machinery.SourceFileLoader("aether_accent_sync", path)
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod


SYNC = _sync()

# The accent placeholders aether-accent-sync swaps for the island's colour (accent, hover, deep, ink).
ACCENT, HOVER, DEEP, INK = "#00f2fe", "#00dce6", "#00696f", "#00373a"
PLACEHOLDER = {"accent": ACCENT, "hover": HOVER, "deep": DEEP, "ink": INK}
PLACEHOLDER_HUE = 183 / 360   # the island's default AccentHue
WHITE = "#ffffff"
TEST_ACCENTS = ("#00f2fe", "#b97b75", "#1d3557", "#75b98c")   # bright cyan, a muted rose, a dark navy, a sage

T = load()
P = T["palette"]


def tint(token: str, s: float) -> tuple[str, str]:
    """A neutral surface that takes the chosen colour's hue at its own lightness (Theme.qml `tinted`)."""
    h = P[token]
    l = colorsys.rgb_to_hls(*(int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)))[1]
    return h, f"tint {l:.3f} {s}"


def tinted_up(token: str, dl: float, s: float) -> tuple[str, str]:
    """The same tint with its lightness raised by dl (a selected surface sits a touch higher)."""
    hue, l, _ = colorsys.rgb_to_hls(*(int(P[token][i:i + 2], 16) / 255 for i in (1, 3, 5)))
    l = min(max(l + dl, 0.0), 1.0)
    return hexl(hue * 360, l, s), f"tint {l:.3f} {s}"


def veil(hex: str, alpha: float, base: str, base_value: str) -> tuple[str, str]:
    """An opaque veil of `hex` at `alpha` over the final value of the `base` key: the mark is resolved
    in tg_fix after the tints, the value here is the same composite over the neutral base."""
    return over(hex + "%02x" % round(alpha * 255), base_value), f"veil {hex} {alpha} {base}"


def muted(role: str) -> str:
    """The muted badge fill beside a ROLE badge: pale under the dark ink, graphite under white."""
    return f"beside-{role} {P['fog-300']} {P['graphite-500']}"


def dark() -> list[tuple[str, str, str]]:
    """(key, colour, mark)."""
    p = P
    body, raised = 0.06, 0.08   # the tint's saturation: the glass body, the raised glass above it
    return [
        # basic: the window is the glass body, the list beneath it its darker foot
        ("windowBg", *tint("ink-900", body)),
        ("windowFg", p["fog-100"], ""),
        ("windowBgOver", *tint("ink-800", body)),
        ("windowBgRipple", *tint("ink-700", body)),
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
        ("shadowFg", "#00000000", ""),            # no hairlines: the shelves are separated by space
        ("boxDividerFg", "#00000000", ""),
        # buttons
        ("activeButtonBg", ACCENT, ""),
        ("activeButtonBgOver", HOVER, ""),
        ("activeButtonBgRipple", DEEP, ""),
        ("activeButtonFg", INK, "on-accent"),
        ("activeButtonFgOver", INK, "on-hover"),
        ("activeButtonSecondaryFg", INK + "b3", "on-accent"),
        ("activeButtonSecondaryFgOver", INK + "b3", "on-hover"),
        ("activeLineFg", ACCENT, ""),
        ("activeLineFgError", p["red-200"], ""),
        ("lightButtonBg", *tint("ink-900", body)),
        ("lightButtonBgOver", *tint("ink-800", body)),
        ("lightButtonBgRipple", *tint("ink-700", body)),
        ("lightButtonFg", ACCENT, ""),
        ("lightButtonFgOver", ACCENT, ""),
        ("attentionButtonFg", p["red-200"], ""),
        ("attentionButtonFgOver", p["red-200"], ""),
        ("checkboxFg", p["fog-500"], ""),
        ("placeholderFg", p["fog-500"], ""),
        ("placeholderFgActive", p["fog-300"], ""),
        # menus: the island's raised glass, white-alpha rim
        ("menuBg", *tint("ink-750", raised)),
        ("menuBgOver", *tint("ink-600", raised)),
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
        # the focused search field stays a soft chip (a little lighter), not a black hole
        ("filterInputActiveBg", *veil("#ffffff", 0.11, "dialogsBg", p["ink-850"])),
        # the bands that head search results are not slabs across the card
        ("searchedBarBg", "#00000000", ""),
        ("filterInputInactiveBg", *tint("ink-800", body)),
        # own title bar (when the system one is off)
        ("titleBg", *tint("ink-850", body)),
        ("titleBgActive", *tint("ink-850", body)),
        ("titleFg", p["fog-500"], ""),
        ("titleFgActive", p["fog-100"], ""),
        ("titleButtonFg", p["fog-500"], ""),
        ("titleButtonBgOver", *tint("ink-700", body)),
        ("titleButtonFgOver", p["fog-100"], ""),
        ("titleButtonFgActive", p["fog-300"], ""),
        ("titleButtonFgActiveOver", p["fog-100"], ""),
        ("titleButtonCloseBgOver", p["red-700"], ""),
        ("titleButtonCloseFgOver", WHITE, ""),
        # folders strip; tdesktop draws every badge here with the one sideBarBadgeFg
        ("sideBarBg", *tint("ink-950", body)),
        ("sideBarBgActive", *tint("ink-800", body)),
        ("sideBarBgRipple", *tint("ink-700", body)),
        ("sideBarTextFg", p["fog-500"], ""),
        ("sideBarTextFgActive", ACCENT, ""),
        ("sideBarIconFg", p["fog-500"], ""),
        ("sideBarIconFgActive", ACCENT, ""),
        ("sideBarBadgeBg", ACCENT, ""),
        ("sideBarBadgeBgActive", ACCENT, ""),
        ("sideBarBadgeBgMuted", p["fog-300"], muted("accent")),
        ("sideBarBadgeBgMutedActive", p["fog-300"], muted("accent")),
        ("sideBarBadgeFg", INK, "on-accent"),
        # chat list; the muted badge shares the plain badge's ink (no dialogsUnreadFgMuted)
        ("dialogsBg", *tint("ink-850", body)),
        ("dialogsNameFg", p["fog-100"], ""),
        ("dialogsChatIconFg", p["fog-100"], ""),
        ("dialogsDateFg", p["fog-500"], ""),
        ("dialogsTextFg", p["fog-500"], ""),
        ("dialogsTextFgService", p["fog-300"], ""),
        ("dialogsDraftFg", p["red-200"], ""),
        ("dialogsSendingIconFg", p["fog-500"], ""),
        ("dialogsSentIconFg", ACCENT, ""),
        ("dialogsUnreadBg", ACCENT, ""),
        ("dialogsUnreadBgMuted", p["fog-300"], muted("accent")),
        ("dialogsUnreadFg", INK, "on-accent"),
        ("dialogsBgOver", *veil("#ffffff", 0.07, "dialogsBg", p["ink-850"])),
        ("dialogsNameFgOver", p["fog-50"], ""),
        ("dialogsChatIconFgOver", p["fog-50"], ""),
        ("dialogsDateFgOver", p["fog-300"], ""),
        ("dialogsTextFgOver", p["fog-300"], ""),
        ("dialogsTextFgServiceOver", p["fog-100"], ""),
        ("dialogsDraftFgOver", p["red-200"], ""),
        ("dialogsSendingIconFgOver", p["fog-300"], ""),
        ("dialogsSentIconFgOver", ACCENT, ""),
        ("dialogsUnreadBgOver", HOVER, ""),
        ("dialogsUnreadBgMutedOver", p["fog-300"], muted("hover")),
        ("dialogsUnreadFgOver", INK, "on-hover"),
        # hover and selection are quiet veils over the list itself, not fills of their own
        ("dialogsBgActive", *veil("#ffffff", 0.14, "dialogsBg", p["ink-850"])),
        ("dialogsNameFgActive", p["fog-50"], ""),
        ("dialogsChatIconFgActive", p["fog-50"], ""),
        ("dialogsDateFgActive", p["fog-300"], ""),
        ("dialogsTextFgActive", p["fog-300"], ""),
        ("dialogsTextFgServiceActive", p["fog-300"], ""),
        ("dialogsDraftFgActive", p["red-200"], ""),
        ("dialogsSendingIconFgActive", p["fog-300"], ""),
        ("dialogsSentIconFgActive", ACCENT, ""),
        # the selected row stays the list's colour, so its badge stays the accent
        ("dialogsUnreadBgActive", ACCENT, ""),
        ("dialogsUnreadBgMutedActive", p["fog-300"], ""),
        ("dialogsUnreadFgActive", INK, "on-accent"),
        ("dialogsRippleBg", *tint("ink-700", body)),
        ("dialogsRippleBgActive", "#ffffff14", ""),
        # messages: incoming a neutral glass, outgoing a soft opaque tint of the accent
        ("msgInBg", *tint("ink-600", 0.06)),
        ("msgInBgSelected", *tinted_up("ink-600", 0.05, 0.06)),
        ("msgOutBg", hexl(PLACEHOLDER_HUE * 360, 0.24, 0.22), "tint 0.24 0.22"),
        ("msgOutBgSelected", hexl(PLACEHOLDER_HUE * 360, 0.29, 0.22), "tint 0.29 0.22"),
        *[(k, "#00000000", "") for k in ("msgInShadow", "msgInShadowSelected", "msgOutShadow", "msgOutShadowSelected")],
        ("msgInServiceFg", ACCENT, ""),
        ("msgInServiceFgSelected", ACCENT, ""),
        ("msgOutServiceFg", p["fog-300"], ""),
        ("msgOutServiceFgSelected", p["fog-300"], ""),
        ("msgInDateFg", p["fog-500"], ""),
        ("msgInDateFgSelected", p["fog-300"], ""),
        ("msgOutDateFg", p["fog-300"], ""),
        ("msgOutDateFgSelected", p["fog-300"], ""),
        ("msgInReplyBarColor", ACCENT, ""),
        ("msgInReplyBarSelColor", ACCENT, ""),
        ("msgOutReplyBarColor", ACCENT, ""),
        ("msgOutReplyBarSelColor", ACCENT, ""),
        ("msgServiceBg", "#2a2d34cc", ""),
        ("msgServiceBgSelected", "#ffffff24", ""),
        ("msgServiceFg", p["fog-300"], ""),
        ("msgInMonoFg", p["fog-300"], ""),
        ("msgInMonoFgSelected", p["fog-300"], ""),
        ("msgOutMonoFg", p["fog-300"], ""),
        ("msgOutMonoFgSelected", p["fog-300"], ""),
        ("historyTextInFg", p["fog-100"], ""),
        ("historyTextInFgSelected", p["fog-100"], ""),
        ("historyTextOutFg", p["fog-50"], ""),
        ("historyTextOutFgSelected", p["fog-50"], ""),
        ("historyLinkInFg", ACCENT, ""),
        ("historyLinkInFgSelected", ACCENT, ""),
        ("historyLinkOutFg", ACCENT, ""),
        ("historyLinkOutFgSelected", ACCENT, ""),
        ("historyFileNameInFg", p["fog-100"], ""),
        ("historyFileNameInFgSelected", p["fog-100"], ""),
        ("historyFileNameOutFg", p["fog-50"], ""),
        ("historyFileNameOutFgSelected", p["fog-50"], ""),
        ("historyOutIconFg", ACCENT, ""),
        ("historyOutIconFgSelected", ACCENT, ""),
        ("historySendingOutIconFg", p["fog-300"], ""),
        # sender names: eight hues evenly spaced from the accent's own, calm in both modes
        # (a "tint L S +D" mark: each name follows the live accent, turned 45 degrees per index)
        *[(f"historyPeer{i}NameFg{v}", hexl((PLACEHOLDER_HUE * 360 + 45 * (i - 1)) % 360, l, 0.40),
           f"tint {l} 0.40 +{45 * (i - 1)}")
          for i in range(1, 9) for v, l in (("", 0.72), ("Selected", 0.72))],
        # files: the download circle wears the accent on both bubbles now
        ("msgFileInBg", ACCENT, ""),
        ("msgFileInBgOver", HOVER, ""),
        ("msgFileInBgSelected", HOVER, ""),
        ("historyFileInIconFg", INK, "on-accent"),
        ("historyFileInIconFgSelected", INK, "on-hover"),
        ("msgFileOutBg", ACCENT, ""),
        ("msgFileOutBgSelected", HOVER, ""),
        ("historyFileOutIconFg", INK, "on-accent"),
        ("historyFileOutIconFgSelected", INK, "on-hover"),
        ("msgFileThumbLinkInFg", ACCENT, ""),
        ("msgFileThumbLinkInFgSelected", ACCENT, ""),
        ("msgFileThumbLinkOutFg", ACCENT, ""),
        ("msgFileThumbLinkOutFgSelected", ACCENT, ""),
        # shared files' squares: Telegram's four colours, calmed to the glass (white glyphs on them)
        *[(f"msgFile{i}{v}", hsl, "") for i, hue in enumerate((210, 150, 5, 38), 1)
          for v, hsl in (("Bg", hexl(hue, 0.42)), ("BgDark", hexl(hue, 0.36)), ("BgOver", hexl(hue, 0.33)),
                         ("BgSelected", hexl(hue, 0.30)))],
        # chat view
        *[(k, v, "") for k, v in (("historyScrollBarBg", "#ffffff38"), ("historyScrollBarBgOver", "#ffffff5c"),
                                  ("historyScrollBg", "#ffffff10"), ("historyScrollBgOver", "#ffffff1c"))],
        # selection and media overlays: white veils, never fills
        ("msgSelectOverlay", "#ffffff24", ""),
        ("msgStickerOverlay", "#ffffff2e", ""),
        ("msgDateImgBgSelected", "#00000066", ""),
        # the unread bar is just its text on the field
        ("historyUnreadBarBg", "#00000000", ""),
        ("historyUnreadBarBorder", "#00000000", ""),
        ("historyUnreadBarFg", p["fog-300"], ""),
        ("historyToDownBg", *tint("ink-750", raised)),
        ("historyToDownBgOver", *tint("ink-600", raised)),
        ("historyToDownBgRipple", *tint("ink-700", raised)),
        ("historyToDownFg", p["fog-300"], ""),
        ("historyToDownFgOver", p["fog-100"], ""),
        ("historyToDownShadow", "#00000040", ""),
        # composer
        # the chat header and the writing bar are glass over the backdrop, not opaque bands
        # the compose pill is glass the client paints itself; what lies on it brings no fill
        ("historyComposeAreaBg", "#00000000", ""),
        ("topBarBg", tint("ink-850", body)[0] + "d2", tint("ink-850", body)[1]),
        ("historyComposeAreaFg", p["fog-100"], ""),
        ("historyComposeAreaFgService", p["fog-500"], ""),
        ("historyComposeIconFg", p["fog-500"], ""),
        ("historyComposeIconFgOver", ACCENT, ""),
        ("historySendIconFg", ACCENT, ""),
        ("historySendIconFgOver", HOVER, ""),
        ("historyComposeButtonBg", *tint("ink-850", body)),
        ("historyComposeButtonBgOver", *tint("ink-750", body)),
        ("historyComposeButtonBgRipple", *tint("ink-700", body)),
    ]


def hexl(hue: float, l: float, s: float = 0.30) -> str:
    r, g, b = colorsys.hls_to_rgb(hue / 360, l, s)
    return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))


def light() -> list[tuple[str, str, str]]:
    """Paper and graphite; the accent shows in its deep shade, which holds up on white. A value given
    as a (colour, mark) pair keeps that mark; a bare colour takes the dark row's on-/beside- mark,
    moved onto the deep fill (the light badges and buttons are deep), and drops a tint."""
    p = P
    paper = 0.10   # the tint's saturation on paper
    fg = "graphite-950"
    over = {
        "windowBg": p["paper-0"], "windowFg": p[fg], "windowBgOver": p["paper-100"],
        "windowBgRipple": p["fog-50"], "windowFgOver": p[fg], "windowSubTextFg": p["graphite-500"],
        "windowSubTextFgOver": p["graphite-700"], "windowBoldFg": p["graphite-900"], "windowBoldFgOver": p["graphite-900"],
        "windowBgActive": DEEP, "windowFgActive": WHITE, "windowActiveTextFg": DEEP,
        "windowShadowFgFallback": p["paper-100"], "shadowFg": "#00000000", "boxDividerFg": "#00000000",
        "activeButtonBg": DEEP, "activeButtonBgOver": DEEP + "e6", "activeButtonBgRipple": INK,
        "activeButtonFg": WHITE, "activeButtonFgOver": WHITE, "activeButtonSecondaryFg": WHITE + "b3",
        "activeButtonSecondaryFgOver": WHITE + "b3",
        "activeLineFg": DEEP, "activeLineFgError": p["red-700"],
        "lightButtonBg": p["paper-0"], "lightButtonBgOver": p["paper-100"], "lightButtonBgRipple": p["fog-50"],
        "lightButtonFg": DEEP, "lightButtonFgOver": DEEP, "attentionButtonFg": p["red-700"],
        "attentionButtonFgOver": p["red-700"],
        "checkboxFg": p["graphite-500"], "placeholderFg": p["graphite-500"], "placeholderFgActive": p["graphite-700"],
        "menuBg": p["paper-0"], "menuBgOver": p["paper-100"], "menuBgRipple": p["fog-50"],
        "menuIconFg": p["graphite-500"], "menuIconFgOver": p["graphite-900"], "menuSubmenuArrowFg": p["graphite-500"],
        "menuFgDisabled": p["fog-500"], "menuSeparatorFg": "#0000001a",
        "scrollBarBg": "#0000003a", "scrollBarBgOver": "#0000005c",
        "filterInputBorderFg": DEEP, "searchedBarBg": "#00000000", "filterInputActiveBg": p["paper-0"], "filterInputInactiveBg": p["paper-100"],
        "titleBg": tint("paper-50", paper), "titleBgActive": tint("paper-50", paper), "titleFg": p["graphite-500"],
        "titleFgActive": p[fg], "titleButtonFg": p["graphite-500"], "titleButtonBgOver": p["paper-100"],
        "titleButtonFgOver": p[fg], "titleButtonFgActive": p["graphite-700"], "titleButtonFgActiveOver": p[fg],
        "sideBarBg": tint("paper-100", paper), "sideBarBgActive": p["fog-50"], "sideBarBgRipple": p["fog-100"],
        "sideBarTextFg": p["graphite-500"], "sideBarTextFgActive": DEEP, "sideBarIconFg": p["graphite-500"],
        "sideBarIconFgActive": DEEP, "sideBarBadgeBg": DEEP, "sideBarBadgeBgActive": DEEP,
        "sideBarBadgeBgMuted": p["graphite-500"], "sideBarBadgeBgMutedActive": p["graphite-500"], "sideBarBadgeFg": WHITE,
        "dialogsBg": tint("paper-50", paper), "dialogsNameFg": p[fg], "dialogsChatIconFg": p[fg],
        "dialogsDateFg": p["graphite-500"], "dialogsTextFg": p["graphite-500"], "dialogsTextFgService": p["graphite-700"],
        "dialogsDraftFg": p["red-700"], "dialogsSendingIconFg": p["fog-500"], "dialogsSentIconFg": DEEP,
        "dialogsUnreadBg": DEEP, "dialogsUnreadBgMuted": p["graphite-500"], "dialogsUnreadFg": WHITE,
        "dialogsBgOver": veil("#000000", 0.035, "dialogsBg", p["paper-50"]), "dialogsNameFgOver": p[fg],
        "dialogsChatIconFgOver": p[fg],
        "dialogsDateFgOver": p["graphite-700"], "dialogsTextFgOver": p["graphite-500"],
        "dialogsTextFgServiceOver": p["graphite-900"], "dialogsDraftFgOver": p["red-700"],
        "dialogsSendingIconFgOver": p["graphite-500"], "dialogsSentIconFgOver": DEEP,
        "dialogsUnreadBgOver": DEEP, "dialogsUnreadBgMutedOver": p["graphite-500"], "dialogsUnreadFgOver": WHITE,
        "dialogsRippleBg": p["fog-50"],
        # the quiet selection: a black veil over the paper list, its text the list's own
        "dialogsBgActive": veil("#000000", 0.06, "dialogsBg", p["paper-50"]),
        "dialogsNameFgActive": p[fg], "dialogsChatIconFgActive": p[fg],
        "dialogsDateFgActive": p["graphite-500"], "dialogsTextFgActive": p["graphite-500"],
        "dialogsTextFgServiceActive": p["graphite-500"], "dialogsDraftFgActive": p["red-700"],
        "dialogsSendingIconFgActive": p["graphite-500"], "dialogsSentIconFgActive": DEEP,
        "dialogsUnreadBgActive": DEEP, "dialogsUnreadBgMutedActive": p["graphite-500"],
        "dialogsUnreadFgActive": WHITE, "dialogsRippleBgActive": "#0000000f",
        # the outgoing bubble is a pale, opaque tint of the accent: dark ink on it, no on-deep marks
        "msgInBg": p["paper-0"], "msgInBgSelected": p["fog-50"],
        "msgOutBg": (hexl(PLACEHOLDER_HUE * 360, 0.90, 0.30), "tint 0.90 0.3"),
        "msgOutBgSelected": (hexl(PLACEHOLDER_HUE * 360, 0.84, 0.30), "tint 0.84 0.3"),
        "msgInShadow": "#00000000", "msgInShadowSelected": "#00000000",
        "msgOutShadow": "#00000000", "msgOutShadowSelected": "#00000000",
        "msgInServiceFg": DEEP, "msgInServiceFgSelected": DEEP,
        "msgInDateFg": p["graphite-500"], "msgInDateFgSelected": p["graphite-700"],
        "msgInReplyBarColor": DEEP, "msgInReplyBarSelColor": DEEP,
        "msgServiceBg": "#0000000f", "msgServiceBgSelected": "#00000018", "msgServiceFg": p["graphite-700"],
        "msgSelectOverlay": "#0000000f", "msgStickerOverlay": "#0000001a",
        "msgInMonoFg": p["graphite-700"], "msgInMonoFgSelected": p["graphite-700"],
        "historyTextInFg": p[fg], "historyTextInFgSelected": p[fg],
        "historyLinkInFg": DEEP, "historyLinkInFgSelected": DEEP,
        "historyFileNameInFg": p[fg], "historyFileNameInFgSelected": p[fg],
        "msgFileInBg": DEEP, "msgFileInBgOver": DEEP + "e6", "msgFileInBgSelected": DEEP,
        "historyFileInIconFg": WHITE, "historyFileInIconFgSelected": WHITE,
        "msgFileOutBg": (DEEP, ""), "msgFileOutBgSelected": (DEEP, ""),
        "historyFileOutIconFg": (WHITE, "on-deep"), "historyFileOutIconFgSelected": (WHITE, "on-deep"),
        "msgFileThumbLinkInFg": DEEP, "msgFileThumbLinkInFgSelected": DEEP,
        "historyScrollBarBg": "#0000003a", "historyScrollBarBgOver": "#0000005c",
        "historyScrollBg": "#00000010", "historyScrollBgOver": "#0000001c",
        "historyUnreadBarBg": "#00000000", "historyUnreadBarBorder": "#00000000",
        "historyUnreadBarFg": p["graphite-500"],
        "historyToDownBg": p["paper-0"], "historyToDownBgOver": p["paper-100"], "historyToDownBgRipple": p["fog-50"],
        "historyToDownFg": p["graphite-500"], "historyToDownFgOver": p["graphite-900"], "historyToDownShadow": "#0000001f",
        "historyComposeAreaBg": "#00000000", "topBarBg": p["paper-0"] + "d8", "historyComposeAreaFg": p[fg],
        "historyComposeAreaFgService": p["graphite-500"], "historyComposeIconFg": p["graphite-500"],
        "historyComposeIconFgOver": DEEP, "historySendIconFg": DEEP, "historySendIconFgOver": DEEP + "e6",
        "historyComposeButtonBg": p["paper-0"], "historyComposeButtonBgOver": p["paper-100"],
        "historyComposeButtonBgRipple": p["fog-50"],
        **{k: (DEEP, "") for k in ("msgOutServiceFg", "msgOutServiceFgSelected", "msgOutReplyBarColor",
                                   "msgOutReplyBarSelColor", "historyLinkOutFg", "historyLinkOutFgSelected",
                                   "historyOutIconFg", "historyOutIconFgSelected", "msgFileThumbLinkOutFg",
                                   "msgFileThumbLinkOutFgSelected")},
        **{k: (p[fg], "") for k in ("historyTextOutFg", "historyTextOutFgSelected", "historyFileNameOutFg",
                                    "historyFileNameOutFgSelected")},
        **{k: (p["graphite-500"], "") for k in ("msgOutDateFg", "msgOutDateFgSelected", "historySendingOutIconFg")},
        **{k: (p["graphite-700"], "") for k in ("msgOutMonoFg", "msgOutMonoFgSelected")},
        **{f"historyPeer{i}NameFg{v}": (hexl((PLACEHOLDER_HUE * 360 + 45 * (i - 1)) % 360, 0.36, 0.40),
                                        f"tint 0.36 0.40 +{45 * (i - 1)}")
           for i in range(1, 9) for v in ("", "Selected")},
    }
    rows = []
    for key, value, mark in dark():
        o = over.get(key, value)
        if isinstance(o, tuple):
            v, m = o
        else:
            v, m = o, mark
            if m.startswith("tint"):
                m = "" if key in over else m
            m = re.sub(r"^(on|beside)-(accent|hover)", r"\1-deep", m)
            if m.startswith("beside") and v not in m:
                m = ""   # a plain light value, not one of the pair
        rows.append((key, v, m))
    leaks = [k for k, v, m in rows if m.startswith("tint") and k not in over]
    assert not leaks, f"dark tinted surfaces without a light value: {leaks}"
    return rows


def render(name: str, rows) -> str:
    """The template: the marks resolved for the placeholder colours, the neutral surfaces left neutral."""
    head = (f"// {name}: Aether for Aethergram (Telegram Desktop), generated by theme/generators/build_telegram.py.\n"
            "// The cyan is a placeholder: aether-accent-sync re-inks it to the island's accent.\n")
    text = head + "".join(f"{k}: {v};" + (f" // {m}" if m else "") + "\n" for k, v, m in rows)
    return SYNC.tg_fix(text, PLACEHOLDER)


def parse(text: str) -> dict[str, str]:
    return dict(re.findall(r"^(\w+): (#[0-9a-fA-F]{6,8});", text, flags=re.M))


# The text the client draws, as (background, foreground) keys: badges, messages, the chat list, buttons.
PAIRS = [tuple(p.split("/")) for p in """
    dialogsUnreadBg/dialogsUnreadFg dialogsUnreadBgMuted/dialogsUnreadFg dialogsUnreadBgOver/dialogsUnreadFgOver
    dialogsUnreadBgMutedOver/dialogsUnreadFgOver dialogsUnreadBgActive/dialogsUnreadFgActive
    dialogsUnreadBgMutedActive/dialogsUnreadFgActive sideBarBadgeBg/sideBarBadgeFg sideBarBadgeBgMuted/sideBarBadgeFg
    sideBarBadgeBgActive/sideBarBadgeFg sideBarBadgeBgMutedActive/sideBarBadgeFg
    msgInBg/historyTextInFg msgInBgSelected/historyTextInFgSelected msgOutBg/historyTextOutFg
    msgOutBgSelected/historyTextOutFgSelected msgInBg/historyLinkInFg msgOutBg/historyLinkOutFg
    msgInBg/msgInServiceFg msgOutBg/msgOutServiceFg msgInBg/historyFileNameInFg msgOutBg/historyFileNameOutFg
    msgServiceBg/msgServiceFg historyUnreadBarBg/historyUnreadBarFg
    dialogsBg/dialogsNameFg dialogsBg/dialogsTextFg dialogsBgOver/dialogsNameFgOver dialogsBgOver/dialogsTextFgOver
    dialogsBgActive/dialogsNameFgActive dialogsBgActive/dialogsTextFgActive dialogsBgActive/dialogsDateFgActive
    activeButtonBg/activeButtonFg activeButtonBgOver/activeButtonFgOver lightButtonBg/lightButtonFg
    lightButtonBgOver/lightButtonFgOver windowBgActive/windowFgActive windowBg/windowFg windowBg/windowActiveTextFg
    menuBg/windowFg historyComposeAreaBg/historyComposeAreaFg""".split()]
MIN_CONTRAST = 4.5

# What each alpha fill actually sits on: the dialogs over the list, messages over their bubble (or the
# selected bubble over the plain one), the service chips and the unread bar over the field.
BASES = (("dialogs", "dialogsBg"), ("msgIn", "msgInBg"), ("msgOut", "msgOutBg"),
         ("msgService", "windowBg"), ("historyUnreadBar", "windowBg"))


def base_of(key: str) -> str:
    return next((base for prefix, base in BASES if key.startswith(prefix)), "windowBg")


def over(top: str, under: str) -> str:
    """#rrggbb[aa] composited onto an opaque #rrggbb."""
    a = int(top[7:9], 16) / 255 if len(top) == 9 else 1.0
    return "#" + "".join("%02x" % round(int(top[i:i + 2], 16) * a + int(under[i:i + 2], 16) * (1 - a))
                         for i in (1, 3, 5))


def contrast_failures(name: str, text: str) -> list[str]:
    pal, bad = parse(text), []
    for bg, fg in PAIRS:
        missing = [k for k in (bg, fg) if k not in pal]
        if missing:
            bad.append(f"{name}: {bg}/{fg}: not set ({', '.join(missing)})")
            continue
        b = over(pal[bg], pal[base_of(bg)])
        c = SYNC.contrast(over(pal[fg], b), b)
        if c < MIN_CONTRAST:
            bad.append(f"{name}: {bg} / {fg}: {c:.2f}:1 < {MIN_CONTRAST}")
    return bad


def accent_hls(h: str):
    """A #rrggbb accent as the island stores it, clamped the way aether-accent-sync reads it."""
    hue, l, s = colorsys.rgb_to_hls(*(int(h[i:i + 2], 16) / 255 for i in (1, 3, 5)))
    return round(hue * 360) % 360 / 360, min(max(l, 0.25), 0.8), min(max(s, 0.15), 1.0)


def known() -> set[str]:
    return {l.strip() for l in KEYS.read_text().splitlines() if l.strip() and not l.startswith("#")}


def refresh() -> None:
    text = urllib.request.urlopen(UPSTREAM, timeout=30).read().decode()
    keys = re.findall(r"^([A-Za-z][A-Za-z0-9_]*):", text, flags=re.M)
    KEYS.write_text("# Telegram Desktop palette keys, from desktop-app/lib_ui ui/colors.palette (master).\n"
                    "# Refresh: python3 theme/generators/build_telegram.py --refresh-keys\n" + "\n".join(keys) + "\n")
    print(f"{len(keys)} keys -> {KEYS}")


def check(themes: dict) -> int:
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
        template = render(name, rows)
        bad += contrast_failures(f"{name} (no accent)", template)
        for a in TEST_ACCENTS:
            hls = accent_hls(a)
            text = SYNC.tg_fix(template, SYNC.tg_colors(hls, name.endswith("light")), hls[0])
            bad += contrast_failures(f"{name} {a}", text)
    if bad:
        print("\n".join(bad), file=sys.stderr)
        return 1
    print(f"telegram palettes ok ({len(themes['aether-dark'])} keys, all known to tdesktop; "
          f"{len(PAIRS)} text pairs >= {MIN_CONTRAST}:1 for {', '.join(TEST_ACCENTS)}, dark and light)")
    return 0


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
        return check(themes)
    a.out.mkdir(parents=True, exist_ok=True)
    for name, rows in themes.items():
        palette = render(name, rows)
        (a.out / f"{name}.tdesktop-palette").write_text(palette)
        print("built", a.out / f"{name}.tdesktop-palette")
        light_mode = name.endswith("light")
        tag = f"aether background v2 hue={PLACEHOLDER_HUE:.4f} {'light' if light_mode else 'dark'}"
        theme = SYNC.tg_theme(palette, SYNC.tg_background(PLACEHOLDER_HUE, light_mode), tag)
        (a.out / f"{name}.tdesktop-theme").write_bytes(theme)
        print("built", a.out / f"{name}.tdesktop-theme")
    return 0


if __name__ == "__main__":
    sys.exit(main())
