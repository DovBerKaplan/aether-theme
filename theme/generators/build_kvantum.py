#!/usr/bin/env python3
"""Generate AetherGlass / AetherSerenity Kvantum themes by recoloring WhiteSur.

WhiteSur (GPLv3, vinceliuice) provides the rounded, translucent SVG geometry;
we swap its palette for the Stitch "AetherOS" tokens.
"""
import re
import sys
from pathlib import Path

from build_frames import corner_path, corner_ring
from tokens import load

SRC = Path(__file__).resolve().parents[1] / "vendor/whitesur-kvantum"
OUT = Path(__file__).resolve().parents[1] / "generated/kvantum"

T = load()
_K = T["kvantum"]
HACKS = _K.pop("hacks")
GENERAL = _K.pop("general")
# The glass IS this fade: Kvantum lowers the whole window's opacity over KWin's blur, and the
# frame's opaque SVG pieces fade with it. (The alpha byte inside window.color's hex is honoured
# by neither Kvantum nor Qt SVG - keep that hex opaque and let this key be the one translucency.)
GENERAL["reduce_window_opacity"] = str(round((1 - T["apps"]["chrome-alpha"]) * 100))
THEMES = _K


def set_keys(text: str, section: str, values: dict) -> str:
    m = re.search(rf"^\[{re.escape(section)}\]\n(.*?)(?=^\[|\Z)", text, re.S | re.M)
    if not m:
        sys.exit(f"section [{section}] missing")
    body = m.group(1)
    for k, v in values.items():
        pat = rf"^{re.escape(k)}=.*$"
        body = re.sub(pat, f"{k}={v}", body, flags=re.M) if re.search(pat, body, re.M) \
            else body.rstrip("\n") + f"\n{k}={v}\n"
    return text[: m.start(1)] + body + text[m.end(1):]


def window_frame(body: str, rim: str, rim_alpha: float) -> str:
    """The window's frame pieces, which WhiteSur leaves out (its window is a bare square): a flat top
    (the Aurorae titlebar sits on it), rounded bottom corners (apps.radius) and a hairline rim on the
    sides and the bottom, so the glass has one outline with the titlebar's. Drawn opaque - Kvantum
    fades the whole window by reduce_window_opacity."""
    r = int(T["apps"]["radius"])
    # Inside WhiteSur's canvas (200mm x 354mm, no viewBox - ~756 x 1338 px), in its empty right
    # strip (WhiteSur's pieces all end at x 697). Off-canvas pieces (x 4000+) render broken:
    # Kvantum/Qt draw them mis-measured - light bands and stretched ring stubs at window bottoms.
    x0, y0, e = 704, 0, 8
    xs = {"l": x0, "c": x0 + r, "r": x0 + r + e}
    ys = {"t": y0, "c": y0 + 1, "b": y0 + 1 + e}
    # The frame's pieces are drawn opaque: reduce_window_opacity fades the whole window - body
    # and frame alike - onto the blur, and they stay one glass.
    fill = f'fill="{body[:7]}"'
    line = f'fill="{rim}" fill-opacity="{rim_alpha}"'
    out = []
    for state in ("normal", "normal-inactive"):
        def piece(name, inner):
            out.append(f'<g id="window-{state}-{name}">{inner}</g>')

        def rect(x, y, w, h, style):
            return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" {style}/>'
        piece("topleft", rect(xs["l"], ys["t"], r, 1, fill))
        piece("top", rect(xs["c"], ys["t"], e, 1, fill))
        piece("topright", rect(xs["r"], ys["t"], r, 1, fill))
        piece("left", rect(xs["l"], ys["c"], r, e, fill) + rect(xs["l"], ys["c"], 1, e, line))
        piece("right", rect(xs["r"], ys["c"], r, e, fill) + rect(xs["r"] + r - 1, ys["c"], 1, e, line))
        piece("bottom", rect(xs["c"], ys["b"], e, r, fill) + rect(xs["c"], ys["b"] + r - 1, e, 1, line))
        for kind, cx in (("bottomleft", "l"), ("bottomright", "r")):
            x, y = xs[cx], ys["b"]
            piece(kind, f'<rect x="{x}" y="{y}" width="{r}" height="{r}" fill="#000" fill-opacity="0"/>'
                        f'<path d="{corner_path(kind, x, y, r)}" {fill}/><path d="{corner_ring(kind, x, y, r)}" {line}/>')
    return "".join(out)


def main() -> None:
    for name, t in THEMES.items():
        dest = OUT / name
        dest.mkdir(parents=True, exist_ok=True)
        svg = (SRC / f"{t['base']}.svg").read_text()
        for old, new in t["svg"].items():
            svg = re.sub(re.escape(old), new, svg, flags=re.I)
        dark = name == "AetherGlass"
        frame = window_frame(t["colors"]["window.color"], "#ffffff" if dark else "#1a1d20", 0.16 if dark else 0.12)
        svg = svg[: svg.rindex("</svg>")] + frame + "</svg>\n"
        (dest / f"{name}.svg").write_text(svg)
        cfg = (SRC / f"{t['base']}.kvconfig").read_text()
        cfg = set_keys(cfg, "%General", GENERAL)
        r = str(int(T["apps"]["radius"]))
        cfg = set_keys(cfg, "Window", {"frame.top": "1", "frame.bottom": r, "frame.left": r, "frame.right": r})
        # Toolbars are part of the one glass: no panel of their own, no line under them.
        cfg = set_keys(cfg, "Toolbar", {"interior": "false", "frame": "false"})
        # The glass lets a bright desktop through, so light text needs a dark halo to stay legible
        # over it (the adaptive-contrast stand-in: the halo carries the text over any backdrop).
        for section in ("ItemView", "MenuBarItem", "Menu", "StatusBar", "TitleBar"):
            cfg = set_keys(cfg, section, {"text.shadow": "true", "text.shadow.color": "#5e000000",
                                          "text.shadow.offset": "1"})
        # The view is the same sheet of glass as everything else: no panel, no bordered box
        # around Dolphin's file area (Dov's arrow) - its veil comes from [Colors:View] alone.
        cfg = set_keys(cfg, "ItemView", {"frame": "false"})
        cfg = set_keys(cfg, "GenericFrame", {"frame": "false", "interior": "false"})
        cfg = set_keys(cfg, "GeneralColors", t["colors"])
        cfg = set_keys(cfg, "Hacks", HACKS)
        (dest / f"{name}.kvconfig").write_text(cfg)
        print("built", dest)


if __name__ == "__main__":
    main()
