#!/usr/bin/env python3
"""Draw the Aurorae window decorations AetherGlass (dark) and AetherSerenity (light).

The titlebar is the app frame's glass: the same colour and alpha as the Kvantum window
(apps.chrome-alpha over KWin's blur, which Aurorae requests through the mask-* pieces), no line
under it, so it melts into the toolbar. Rounded top corners (apps.radius), a hairline rim, a
soft shadow in the padding, small round buttons. The accent appears as the dark theme's cyan
placeholder; system/aether-accent-sync swaps in the island's colour when it installs the theme.

Frame layout (Aurorae renders one FrameSvg over client + padding; only what lies outside the
client is shown): every corner tile is (P + r) square - P of shadow, then r of body - and the
edge tiles are as thick, so the four columns/rows line up.
"""
from pathlib import Path

from build_frames import Frame, corner_path, corner_ring, TINY
from tokens import load

T = load()
A, PAL, M = T["apps"], T["palette"], T["material"]
OUT = Path(__file__).resolve().parents[1] / "generated/aurorae"
ACCENT = PAL["cyan-400"]                      # placeholder, see system/aether-accent-sync

P = 24                                        # shadow padding
R = int(A["radius"])
S = P + R                                     # corner tile size
E = 8                                         # edge / centre tile length
BTN = int(A["button-size"])

VARIANTS = {
    "AetherGlass": dict(name="Aether Glass", body=PAL["ink-750"], rim=("#ffffff", M["rim-alpha"]),
                        text=PAL["fog-100"], text_inactive=PAL["fog-500"], shadow=0.38,
                        dot=("#ffffff", 0.16), glyph=PAL["fog-100"], negative="#ff6b6b"),
    "AetherSerenity": dict(name="Aether Serenity", body=PAL["paper-50"], rim=("#1a1d20", 0.10),
                           text=PAL["graphite-950"], text_inactive=PAL["graphite-500"], shadow=0.20,
                           dot=("#1a1d20", 0.10), glyph=PAL["graphite-900"], negative=PAL["red-700"]),
}


def rgb(h: str) -> str:
    return ",".join(str(int(h[i:i + 2], 16)) for i in (1, 3, 5))


class Shadow:
    """Gradients for the shadow, strongest at the window's edge and gone at the padding's edge."""

    def __init__(self, f: Frame, key: str, alpha: float):
        self.f, self.key, self.alpha = f, key, alpha
        f.defs = getattr(f, "defs", [])
        self.lin = {}
        for side, vec in {"t": (0, 1, 0, 0), "b": (0, 0, 0, 1), "l": (1, 0, 0, 0), "r": (0, 0, 1, 0)}.items():
            gid = f"{key}-lin-{side}"
            f.defs.append(f'<linearGradient id="{gid}" x1="{vec[0]}" y1="{vec[1]}" x2="{vec[2]}" y2="{vec[3]}">{self.stops(0)}</linearGradient>')
            self.lin[side] = f"url(#{gid})"

    def stops(self, start: float) -> str:
        a = self.alpha
        return (f'<stop offset="{start:g}" stop-color="#000" stop-opacity="{a}"/>'
                f'<stop offset="{start + (1 - start) * 0.4:g}" stop-color="#000" stop-opacity="{a * 0.3}"/>'
                '<stop offset="1" stop-color="#000" stop-opacity="0"/>')

    def radial(self, cx: float, cy: float, r: float, start: float) -> str:
        gid = f"{self.key}-rad-{len(self.f.defs)}"
        self.f.defs.append(f'<radialGradient id="{gid}" gradientUnits="userSpaceOnUse" cx="{cx}" cy="{cy}" r="{r}">'
                           f'{self.stops(start)}</radialGradient>')
        return f"url(#{gid})"


def decoration(f: Frame, prefix: str, v: dict, alpha: float, active: bool):
    sh = Shadow(f, prefix.rstrip("-"), v["shadow"] if active else v["shadow"] * 0.6)
    y0 = f.row(2 * S + E)
    x0 = 20
    xs = {"l": x0, "c": x0 + S, "r": x0 + S + E}
    ys = {"t": y0, "c": y0 + S, "b": y0 + S + E}
    body = f'fill="{v["body"]}" fill-opacity="{alpha}"'
    rim = f'fill="{v["rim"][0]}" fill-opacity="{v["rim"][1]}"'

    def g(name, inner, x, y):
        f.add(f'<g id="{prefix}{name}"><rect x="{x}" y="{y}" width="{S if name in CORNERS or name in ("left", "right") else E}" '
              f'height="{S if name in CORNERS or name in ("top", "bottom") else E}" {TINY}/>{inner}</g>')

    def rect(x, y, w, h, fill):
        return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" {fill}/>'

    # Top corners: a rounded body corner; the shadow is the rest of the tile (even-odd, so it never
    # lies under the translucent body), radial around the corner's circle.
    for kind, cx in (("topleft", "l"), ("topright", "r")):
        x, y = xs[cx], ys["t"]
        bx = x + P if kind == "topleft" else x            # the body's r x r corner tile
        ccx = x + S if kind == "topleft" else x           # centre of the corner's circle
        tile = f"M{x},{y} H{x + S} V{y + S} H{x} Z "
        fill = sh.radial(ccx, y + S, S, R / S)
        inner = f'<path d="{tile}{corner_path(kind, bx, y + P, R)}" fill-rule="evenodd" fill="{fill}"/>'
        inner += f'<path d="{corner_path(kind, bx, y + P, R)}" {body}/>'
        inner += f'<path d="{corner_ring(kind, bx, y + P, R)}" {rim}/>'
        g(kind, inner, x, y)
    # Bottom corners: the window's corner is square (no bottom border) and lies R into the tile;
    # the shadow wraps it: a side strip, a bottom strip and a radial quarter.
    x, y = xs["l"], ys["b"]
    g("bottomleft", rect(x, y, P, R, f'fill="{sh.lin["l"]}"') + rect(x + P, y + R, R, P, f'fill="{sh.lin["b"]}"')
      + rect(x, y + R, P, P, f'fill="{sh.radial(x + P, y + R, P, 0)}"'), x, y)
    x, y = xs["r"], ys["b"]
    g("bottomright", rect(x + R, y, P, R, f'fill="{sh.lin["r"]}"') + rect(x, y + R, R, P, f'fill="{sh.lin["b"]}"')
      + rect(x + R, y + R, P, P, f'fill="{sh.radial(x + R, y + R, P, 0)}"'), x, y)
    # Edges: shadow outside, body inside (the inside part only shows in the title row).
    g("top", rect(xs["c"], ys["t"], E, P, f'fill="{sh.lin["t"]}"') + rect(xs["c"], ys["t"] + P, E, R, body)
      + rect(xs["c"], ys["t"] + P, E, 1, rim), xs["c"], ys["t"])
    g("bottom", rect(xs["c"], ys["b"] + R, E, P, f'fill="{sh.lin["b"]}"'), xs["c"], ys["b"])
    g("left", rect(xs["l"], ys["c"], P, E, f'fill="{sh.lin["l"]}"') + rect(xs["l"] + P, ys["c"], R, E, body), xs["l"], ys["c"])
    g("right", rect(xs["r"] + R, ys["c"], P, E, f'fill="{sh.lin["r"]}"') + rect(xs["r"], ys["c"], R, E, body), xs["r"], ys["c"])
    g("center", rect(xs["c"], ys["c"], E, E, body), xs["c"], ys["c"])

    if active:  # the blur region: the body only, never the shadow
        mx = x0 + 2 * S + E + 60
        mxs = {"l": mx, "c": mx + S, "r": mx + S + E}
        solid = 'fill="#000"'
        for kind, cx in (("topleft", "l"), ("topright", "r")):
            x = mxs[cx]
            bx = x + P if kind == "topleft" else x
            f.add(f'<g id="mask-{kind}"><rect x="{x}" y="{ys["t"]}" width="{S}" height="{S}" {TINY}/>'
                  f'<path d="{corner_path(kind, bx, ys["t"] + P, R)}" {solid}/></g>')
        for kind, cx in (("bottomleft", "l"), ("bottomright", "r")):
            f.add(f'<rect id="mask-{kind}" x="{mxs[cx]}" y="{ys["b"]}" width="{S}" height="{S}" {TINY}/>')
        f.add(f'<g id="mask-top"><rect x="{mxs["c"]}" y="{ys["t"]}" width="{E}" height="{S}" {TINY}/>'
              f'{rect(mxs["c"], ys["t"] + P, E, R, solid)}</g>')
        f.add(f'<rect id="mask-bottom" x="{mxs["c"]}" y="{ys["b"]}" width="{E}" height="{S}" {TINY}/>')
        f.add(f'<g id="mask-left"><rect x="{mxs["l"]}" y="{ys["c"]}" width="{S}" height="{E}" {TINY}/>'
              f'{rect(mxs["l"] + P, ys["c"], R, E, solid)}</g>')
        f.add(f'<g id="mask-right"><rect x="{mxs["r"]}" y="{ys["c"]}" width="{S}" height="{E}" {TINY}/>'
              f'{rect(mxs["r"], ys["c"], R, E, solid)}</g>')
        f.add(f'<rect id="mask-center" x="{mxs["c"]}" y="{ys["c"]}" width="{E}" height="{E}" {solid}/>')


CORNERS = ("topleft", "topright", "bottomleft", "bottomright")


GLYPHS = {   # 16-unit glyphs, stroked, centred on (8, 8)
    "close": "M5.5 5.5L10.5 10.5M10.5 5.5L5.5 10.5",
    "minimize": "M5 8H11",
    "maximize": "M5.5 9.8L8 6.2L10.5 9.8",
    "restore": "M5.5 6.2L8 9.8L10.5 6.2",
    "alldesktops": "M8 5.5V10.5M5.5 8H10.5",
    "keepabove": "M5.5 9.5L8 7L10.5 9.5",
    "keepbelow": "M5.5 6.5L8 9L10.5 6.5",
}


def button(kind: str, v: dict) -> str:
    """One button file: a soft dot, the glyph shows on hover (calm at rest, like the island)."""
    s = 16
    hover_fill = v["negative"] if kind == "close" else ACCENT
    dot_c, dot_a = v["dot"]
    glyph = lambda color, a: (f'<path d="{GLYPHS[kind]}" stroke="{color}" stroke-opacity="{a}" stroke-width="1.5" '
                              f'stroke-linecap="round" stroke-linejoin="round" fill="none"/>')
    states = {
        "active-center": f'<circle cx="8" cy="8" r="6" fill="{dot_c}" fill-opacity="{dot_a}"/>' + glyph(v["glyph"], 0.85),
        "hover-center": f'<circle cx="8" cy="8" r="6.5" fill="{hover_fill}"/>' + glyph("#0b0e14", 0.9),
        "pressed-center": f'<circle cx="8" cy="8" r="6" fill="{hover_fill}" fill-opacity="0.75"/>' + glyph("#0b0e14", 0.9),
        "inactive-center": f'<circle cx="8" cy="8" r="6" fill="{dot_c}" fill-opacity="{dot_a * 0.7}"/>' + glyph(v["glyph"], 0.45),
        "hover-inactive-center": f'<circle cx="8" cy="8" r="6.5" fill="{hover_fill}"/>' + glyph("#0b0e14", 0.9),
        "deactivated-center": f'<circle cx="8" cy="8" r="6" fill="{dot_c}" fill-opacity="{dot_a * 0.5}"/>',
        "deactivated-inactive-center": f'<circle cx="8" cy="8" r="6" fill="{dot_c}" fill-opacity="{dot_a * 0.4}"/>',
    }
    parts = []
    for i, (sid, body) in enumerate(states.items()):
        x = i * (s + 4)
        parts.append(f'<g id="{sid}" transform="translate({x},0)"><rect width="{s}" height="{s}" {TINY}/>{body}</g>')
    w = len(states) * (s + 4)
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{s}" viewBox="0 0 {w} {s}">{"".join(parts)}</svg>'


def rc(v: dict) -> str:
    title_h = 20
    return f"""[General]
ActiveTextColor={rgb(v["text"])}
InactiveTextColor={rgb(v["text_inactive"])}
TitleAlignment=Center
TitleVerticalAlignment=Center
UseTextShadow=false
Shadow=true
Animation=150

[Layout]
BorderTop=0
BorderLeft=0
BorderRight=0
BorderBottom=0
TitleEdgeTop={P + 7}
TitleEdgeBottom=7
TitleEdgeLeft={P + 10}
TitleEdgeRight={P + 10}
TitleEdgeTopMaximized=7
TitleEdgeBottomMaximized=7
TitleEdgeLeftMaximized=10
TitleEdgeRightMaximized=10
TitleBorderLeft=8
TitleBorderRight=8
TitleHeight={title_h}
ButtonWidth={BTN + 2}
ButtonHeight={BTN + 2}
ButtonSpacing=6
ButtonMarginTop={(title_h - BTN - 2) // 2}
ExplicitButtonSpacer=8
PaddingTop={P}
PaddingBottom={P}
PaddingLeft={P}
PaddingRight={P}
"""


def main():
    for key, v in VARIANTS.items():
        d = OUT / key
        d.mkdir(parents=True, exist_ok=True)
        f = Frame()
        decoration(f, "decoration-", v, A["chrome-alpha"], True)
        decoration(f, "decoration-inactive-", v, A["chrome-alpha"], False)
        (d / "decoration.svg").write_text(f.render())
        for kind in GLYPHS:
            (d / f"{kind}.svg").write_text(button(kind, v))
        (d / f"{key}rc").write_text(rc(v))
        (d / "metadata.desktop").write_text(
            f"[Desktop Entry]\nName={v['name']}\nX-KDE-PluginInfo-Author=AetherOS\nX-KDE-PluginInfo-Name={key}\n"
            f"X-KDE-PluginInfo-Version=1.0\nX-KDE-PluginInfo-License=GPL_V3\nX-KDE-PluginInfo-EnabledByDefault=true\n")
        print("built", d)


if __name__ == "__main__":
    main()
