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
                        dot=("#ffffff", 0.14), glyph=PAL["fog-100"], negative="#ff6b6b"),
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
    # Bottom corners: the vertical mirror of the top corners. Measured on screen (probe tiles):
    # KWin anchors each bottom tile so the frame's bottom edge cuts it at row R - rows [0, R) are
    # the frame's last band inside (the client ends 4 px above the edge), rows [R, S) hang outside
    # as the shadow below the window. So the glass silhouette is the same r=R circle as at the
    # top, centred on the frame's bottom corner point, and the shadow wraps it.
    for kind, cx in (("bottomleft", "l"), ("bottomright", "r")):
        x, y = xs[cx], ys["b"]
        bx = x + P if kind == "bottomleft" else x            # the arc's r x r bbox, rows [0, R)
        ccx = x + S if kind == "bottomleft" else x + R       # the arc circle's centre
        tile = f"M{x},{y} H{x + S} V{y + S} H{x} Z "
        fill = sh.radial(ccx, y, S, R / S)
        inner = f'<path d="{tile}{corner_path(kind, bx, y, R)}" fill-rule="evenodd" fill="{fill}"/>'
        inner += f'<path d="{corner_path(kind, bx, y, R)}" {body}/>'
        inner += f'<path d="{corner_ring(kind, bx, y, R)}" {rim}/>'
        g(kind, inner, x, y)
    # Edges: shadow outside, body inside (the inside part only shows in the title row, and in the
    # bottom row band - see the corners above).
    g("top", rect(xs["c"], ys["t"], E, P, f'fill="{sh.lin["t"]}"') + rect(xs["c"], ys["t"] + P, E, R, body)
      + rect(xs["c"], ys["t"] + P, E, 1, rim), xs["c"], ys["t"])
    g("bottom", rect(xs["c"], ys["b"], E, R, body) + rect(xs["c"], ys["b"] + R - 1, E, 1, rim)
      + rect(xs["c"], ys["b"] + R, E, P, f'fill="{sh.lin["b"]}"'), xs["c"], ys["b"])
    g("left", rect(xs["l"], ys["c"], P, E, f'fill="{sh.lin["l"]}"') + rect(xs["l"] + P, ys["c"], R, E, body)
      + rect(xs["l"] + P, ys["c"], 1, E, rim), xs["l"], ys["c"])
    g("right", rect(xs["r"] + R, ys["c"], P, E, f'fill="{sh.lin["r"]}"') + rect(xs["r"], ys["c"], R, E, body)
      + rect(xs["r"] + R - 1, ys["c"], 1, E, rim), xs["r"], ys["c"])
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
            x = mxs[cx]
            bx = x + P if kind == "bottomleft" else x      # mirror of the top corner masks
            f.add(f'<g id="mask-{kind}"><rect x="{x}" y="{ys["b"]}" width="{S}" height="{S}" {TINY}/>'
                  f'<path d="{corner_path(kind, bx, ys["b"], R)}" {solid}/></g>')
        f.add(f'<g id="mask-top"><rect x="{mxs["c"]}" y="{ys["t"]}" width="{E}" height="{S}" {TINY}/>'
              f'{rect(mxs["c"], ys["t"] + P, E, R, solid)}</g>')
        f.add(f'<g id="mask-bottom"><rect x="{mxs["c"]}" y="{ys["b"]}" width="{E}" height="{S}" {TINY}/>'
              f'{rect(mxs["c"], ys["b"], E, R, solid)}</g>')
        f.add(f'<g id="mask-left"><rect x="{mxs["l"]}" y="{ys["c"]}" width="{S}" height="{E}" {TINY}/>'
              f'{rect(mxs["l"] + P, ys["c"], R, E, solid)}</g>')
        f.add(f'<g id="mask-right"><rect x="{mxs["r"]}" y="{ys["c"]}" width="{S}" height="{E}" {TINY}/>'
              f'{rect(mxs["r"], ys["c"], R, E, solid)}</g>')
        f.add(f'<rect id="mask-center" x="{mxs["c"]}" y="{ys["c"]}" width="{E}" height="{E}" {solid}/>')


CORNERS = ("topleft", "topright", "bottomleft", "bottomright")


GLYPHS = {   # 24-unit glyphs, stroked, centred on (12, 12)
    "close": "M9 9L15 15M15 9L9 15",
    "minimize": "M8.5 12H15.5",
    # maximise and restore alike: two overlapping squares, like the reference
    "maximize": "M10.5 9.5V9.2Q10.5 8.5 11.2 8.5H14.8Q15.5 8.5 15.5 9.2V12.8Q15.5 13.5 14.8 13.5H14.5"
                "M9.2 10.5H12.8Q13.5 10.5 13.5 11.2V14.8Q13.5 15.5 12.8 15.5H9.2Q8.5 15.5 8.5 14.8V11.2Q8.5 10.5 9.2 10.5Z",
    "alldesktops": "M12 8.5V15.5M8.5 12H15.5",
    "keepabove": "M8.5 13.5L12 10L15.5 13.5",
    "keepbelow": "M8.5 10.5L12 14L15.5 10.5",
}
GLYPHS["restore"] = GLYPHS["maximize"]


def button(kind: str, v: dict) -> str:
    """One button file: a grey glass circle with its glyph, always shown (the reference's header
    bar). Hover: close turns red, the others take the accent."""
    s = 24
    hover_fill = v["negative"] if kind == "close" else ACCENT
    dot_c, dot_a = v["dot"]
    glyph = lambda color, a: (f'<path d="{GLYPHS[kind]}" stroke="{color}" stroke-opacity="{a}" stroke-width="1.5" '
                              f'stroke-linecap="round" stroke-linejoin="round" fill="none"/>')
    circle = lambda fill, a, r=11: f'<circle cx="12" cy="12" r="{r}" fill="{fill}" fill-opacity="{a}"/>'
    states = {
        "active-center": circle(dot_c, dot_a) + glyph(v["glyph"], 0.9),
        "hover-center": circle(hover_fill, 1) + glyph("#0b0e14", 0.9),
        "pressed-center": circle(hover_fill, 0.75) + glyph("#0b0e14", 0.9),
        "inactive-center": circle(dot_c, dot_a * 0.6) + glyph(v["glyph"], 0.5),
        "hover-inactive-center": circle(hover_fill, 1) + glyph("#0b0e14", 0.9),
        "deactivated-center": circle(dot_c, dot_a * 0.5) + glyph(v["glyph"], 0.3),
        "deactivated-inactive-center": circle(dot_c, dot_a * 0.4) + glyph(v["glyph"], 0.25),
    }
    parts = []
    for i, (sid, body) in enumerate(states.items()):
        x = i * (s + 4)
        parts.append(f'<g id="{sid}" transform="translate({x},0)"><rect width="{s}" height="{s}" {TINY}/>{body}</g>')
    w = len(states) * (s + 4)
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{s}" viewBox="0 0 {w} {s}">{"".join(parts)}</svg>'


def rc(v: dict) -> str:
    title_h = 24                 # a header bar: 8 + 24 + 8 (the TitleEdge* sit inside the shadow's Padding*)
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
TitleEdgeTop=8
TitleEdgeBottom=8
TitleEdgeLeft=12
TitleEdgeRight=12
TitleEdgeTopMaximized=8
TitleEdgeBottomMaximized=8
TitleEdgeLeftMaximized=12
TitleEdgeRightMaximized=12
TitleBorderLeft=8
TitleBorderRight=8
TitleHeight={title_h}
ButtonWidth={BTN}
ButtonHeight={BTN}
ButtonSpacing=8
ButtonMarginTop={(title_h - BTN) // 2}
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
