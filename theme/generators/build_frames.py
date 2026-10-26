#!/usr/bin/env python3
"""Draw the AetherGlass Plasma frame SVGs (9-slice) from scratch.

Every frame is a rounded glass rectangle: ColorScheme-Background fill at partial
opacity (KWin blurs what's behind it), a hairline ColorScheme-Text border, a
faint top highlight, mask-* pieces for the blur region and soft shadow-* pieces.
Colours come from the active colour scheme, so the same SVGs serve Glass (dark)
and Serenity (light).
"""
import gzip
from pathlib import Path

STYLE = """<style type="text/css" id="current-color-scheme">
.ColorScheme-Background { color:#10131a; }
.ColorScheme-Text { color:#e1e2eb; }
.ColorScheme-Highlight { color:#00f2fe; }
.ColorScheme-NegativeText { color:#ffb4ab; }
</style>"""
# Gives an element its bounding box without adding alpha (alpha would leak into the blur mask).
TINY = 'fill="#000" fill-opacity="0"'


class Frame:
    """Collects SVG elements for one 9-slice frame laid out on a private grid."""

    def __init__(self):
        self.parts = []
        self.cursor_y = 0

    def add(self, svg: str):
        self.parts.append(svg)

    def row(self, height: int) -> int:
        y = self.cursor_y
        self.cursor_y += height + 20
        return y

    def render(self) -> str:
        w = 2000
        h = self.cursor_y + 20
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
                f"{STYLE}<defs>{''.join(getattr(self, 'defs', []))}</defs>{''.join(self.parts)}</svg>")


K = 0.5523  # cubic Bezier constant for a quarter circle

# Per corner, in units of r from the tile origin: outer corner, arc start, arc end, interior point.
_CORNERS = {
    "topleft": ((0, 0), (0, 1), (1, 0), (1, 1)),
    "topright": ((1, 0), (0, 0), (1, 1), (0, 1)),
    "bottomright": ((1, 1), (1, 0), (0, 1), (0, 0)),
    "bottomleft": ((0, 1), (1, 1), (0, 0), (1, 0)),
}


def _quarter(kind, x, y, r, inset=0.0):
    """Quarter-circle as a cubic Bezier. Arcs ('A') are avoided on purpose: Qt sizes an
    element by the arc's whole circle, which made every corner tile twice too big.
    `inset` pulls the curve inward (for a hairline stroke drawn inside the edge)."""
    outer, a, b, inner = ((x + u * r, y + v * r) for u, v in _CORNERS[kind])

    def step(c, toward):
        return inset if toward > c else -inset if toward < c else 0

    def pull(pt):  # move the coordinate that sits on an outer edge inward
        return tuple(c + step(c, i) if c == o else c for c, o, i in zip(pt, outer, inner))

    o = (outer[0] + step(outer[0], inner[0]), outer[1] + step(outer[1], inner[1]))
    p0, p3 = pull(a), pull(b)
    p1 = (p0[0] + K * (o[0] - p0[0]), p0[1] + K * (o[1] - p0[1]))
    p2 = (p3[0] + K * (o[0] - p3[0]), p3[1] + K * (o[1] - p3[1]))
    return p0, p1, p2, p3, inner


def _fmt(p):
    return f"{p[0]:g},{p[1]:g}"


def corner_path(kind: str, x: float, y: float, r: float) -> str:
    p0, p1, p2, p3, inner = _quarter(kind, x, y, r)
    return f"M{_fmt(p0)} C{_fmt(p1)} {_fmt(p2)} {_fmt(p3)} L{_fmt(inner)} Z"


def corner_ring(kind: str, x: float, y: float, r: float, w: float = 1.0) -> str:
    """1px rim along the curve as a filled shape. Stroked paths can't be used: KSvg
    measures them wrongly, which shifted the edge tiles and left gaps by the corners."""
    a0, a1, a2, a3, _ = _quarter(kind, x, y, r)
    b0, b1, b2, b3, _ = _quarter(kind, x, y, r, inset=w)
    return (f"M{_fmt(a0)} C{_fmt(a1)} {_fmt(a2)} {_fmt(a3)} L{_fmt(b3)} "
            f"C{_fmt(b2)} {_fmt(b1)} {_fmt(b0)} Z")


def glass(f: Frame, prefix: str, r: int, opacity: float, margins, border=0.10, highlight=0.0,
          fill_class="ColorScheme-Background", shadow=0, mask=True, frost=0.0):
    """Add one prefixed frame (prefix '' or e.g. 'hover-')."""
    p = prefix
    e = 8                                    # edge/centre tile size
    y0 = f.row(2 * r + e)
    x0 = 20
    xs = {"l": x0, "c": x0 + r, "r": x0 + r + e}
    ys = {"t": y0, "c": y0 + r, "b": y0 + r + e}
    fill = f'class="{fill_class}" fill="currentColor" fill-opacity="{opacity}"'
    # Milky frost: a faint white veil over the tint, so blurred colours read as frosted glass.
    veil = f'fill="#ffffff" fill-opacity="{frost}"'
    line = f'class="ColorScheme-Text" fill="currentColor" fill-opacity="{border}"'
    hl = f'fill="#ffffff" fill-opacity="{highlight}"'

    def rim(x, y, w, h, style):  # hairline as a 1px filled rect (see corner_ring)
        return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" {style}/>'

    def g(name, body):
        f.add(f'<g id="{p}{name}">{body}</g>')

    for kind, (cx, cy) in {"topleft": ("l", "t"), "topright": ("r", "t"),
                           "bottomleft": ("l", "b"), "bottomright": ("r", "b")}.items():
        x, y = xs[cx], ys[cy]
        body = f'<rect x="{x}" y="{y}" width="{r}" height="{r}" {TINY}/>'
        body += f'<path d="{corner_path(kind, x, y, r)}" {fill}/>'
        if frost:
            body += f'<path d="{corner_path(kind, x, y, r)}" {veil}/>'
        if border:
            body += f'<path d="{corner_ring(kind, x, y, r)}" {line}/>'
        if highlight and kind.startswith("top"):
            body += f'<path d="{corner_ring(kind, x, y, r)}" {hl}/>'
        g(kind, body)

    def tile(x, y, w, h):  # tint + optional frost for an edge/centre tile
        out = f'<rect x="{x}" y="{y}" width="{w}" height="{h}" {fill}/>'
        return out + (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" {veil}/>' if frost else "")

    # Edges
    g("top", tile(xs["c"], ys["t"], e, r)
             + (rim(xs["c"], ys["t"], e, 1, line) if border else "")
             + (rim(xs["c"], ys["t"], e, 1, hl) if highlight else ""))
    g("bottom", tile(xs["c"], ys["b"], e, r)
                + (rim(xs["c"], ys["b"] + r - 1, e, 1, line) if border else ""))
    g("left", tile(xs["l"], ys["c"], r, e)
              + (rim(xs["l"], ys["c"], 1, e, line) if border else ""))
    g("right", tile(xs["r"], ys["c"], r, e)
               + (rim(xs["r"] + r - 1, ys["c"], 1, e, line) if border else ""))
    g("center", tile(xs["c"], ys["c"], e, e))

    # Content margins: hint element height/width = margin in px
    t, b, l, rr = margins
    hx = x0 + 2 * r + e + 40
    # Zero insets: blur/contrast cover the whole frame. Without these Plasma falls back to
    # the margins and only the centre gets blurred, leaving a lighter inner box.
    for i, side in enumerate(("top", "bottom", "left", "right")):
        w, h = (4, 1e-6) if side in ("top", "bottom") else (1e-6, 4)
        f.add(f'<rect id="{p}hint-{side}-inset" x="{hx + 50 + 6 * i}" y="{y0}" width="{w}" height="{h}" {TINY}/>')
    # Stretch (not tile) edges, otherwise anti-aliased tile seams show as stripes.
    f.add(f'<rect id="{p}hint-stretch-borders" x="{hx + 40}" y="{y0}" width="2" height="2" {TINY}/>')
    f.add(f'<rect id="{p}hint-top-margin" x="{hx}" y="{y0}" width="1" height="{t}" {TINY}/>')
    f.add(f'<rect id="{p}hint-bottom-margin" x="{hx + 4}" y="{y0}" width="1" height="{b}" {TINY}/>')
    f.add(f'<rect id="{p}hint-left-margin" x="{hx + 8}" y="{y0}" width="{l}" height="1" {TINY}/>')
    f.add(f'<rect id="{p}hint-right-margin" x="{hx + 8}" y="{y0 + 4}" width="{rr}" height="1" {TINY}/>')

    if mask:
        mx = hx + 80
        solid = 'fill="#000"'
        mxs = {"l": mx, "c": mx + r, "r": mx + r + e}
        for kind, (cx, cy) in {"topleft": ("l", "t"), "topright": ("r", "t"),
                               "bottomleft": ("l", "b"), "bottomright": ("r", "b")}.items():
            x, y = mxs[cx], ys[cy]
            f.add(f'<g id="{p}mask-{kind}"><rect x="{x}" y="{y}" width="{r}" height="{r}" {TINY}/>'
                  f'<path d="{corner_path(kind, x, y, r)}" {solid}/></g>')
        f.add(f'<rect id="{p}mask-top" x="{mxs["c"]}" y="{ys["t"]}" width="{e}" height="{r}" {solid}/>')
        f.add(f'<rect id="{p}mask-bottom" x="{mxs["c"]}" y="{ys["b"]}" width="{e}" height="{r}" {solid}/>')
        f.add(f'<rect id="{p}mask-left" x="{mxs["l"]}" y="{ys["c"]}" width="{r}" height="{e}" {solid}/>')
        f.add(f'<rect id="{p}mask-right" x="{mxs["r"]}" y="{ys["c"]}" width="{r}" height="{e}" {solid}/>')
        f.add(f'<rect id="{p}mask-center" x="{mxs["c"]}" y="{ys["c"]}" width="{e}" height="{e}" {solid}/>')

    if shadow:
        add_shadow(f, shadow, alpha=0.32)


def add_shadow(f: Frame, s: int, alpha: float):
    """Soft drop shadow tiles around the frame (outside only)."""
    f.defs = getattr(f, "defs", [])
    y0 = f.row(2 * s + 8)
    x0 = 20
    e = 8
    stops = (f'<stop offset="0" stop-color="#000" stop-opacity="{alpha}"/>'
             f'<stop offset="0.45" stop-color="#000" stop-opacity="{alpha * 0.35}"/>'
             f'<stop offset="1" stop-color="#000" stop-opacity="0"/>')
    tiles = {
        "topleft": (x0, y0, s, s, ("r", s, s)), "top": (x0 + s, y0, e, s, ("l", 0, 1, 0, 0)),
        "topright": (x0 + s + e, y0, s, s, ("r", 0, s)), "left": (x0, y0 + s, s, e, ("l", 1, 0, 0, 0)),
        "right": (x0 + s + e, y0 + s, s, e, ("l", 0, 0, 1, 0)), "bottomleft": (x0, y0 + s + e, s, s, ("r", s, 0)),
        "bottom": (x0 + s, y0 + s + e, e, s, ("l", 0, 0, 0, 1)), "bottomright": (x0 + s + e, y0 + s + e, s, s, ("r", 0, 0)),
    }
    for name, (x, y, w, h, grad) in tiles.items():
        gid = f"sh-{name}-{len(f.defs)}"
        if grad[0] == "r":
            cx, cy = x + grad[1], y + grad[2]
            f.defs.append(f'<radialGradient id="{gid}" gradientUnits="userSpaceOnUse" cx="{cx}" cy="{cy}" r="{s}">{stops}</radialGradient>')
        else:
            x1, y1, x2, y2 = grad[1:]
            f.defs.append(f'<linearGradient id="{gid}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">{stops}</linearGradient>')
        f.add(f'<rect id="shadow-{name}" x="{x}" y="{y}" width="{w}" height="{h}" fill="url(#{gid})"/>')
    f.add(f'<rect id="shadow-center" x="{x0 + s}" y="{y0 + s}" width="{e}" height="{e}" {TINY}/>')


def write(path: Path, frame: Frame):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(gzip.compress(frame.render().encode(), mtime=0))


def build(theme: Path):
    # Bars. Translucent variants are milky frosted glass: KWin blurs what's behind
    # (mask-* pieces), a semi-transparent tint sits on top, then a faint white frost.
    # Shadows only on the opaque variants: KWin also paints a Plasma shadow *under* a
    # translucent window, which showed as a dark band inside the glass edges.
    for rel, op, frost, sh in (("widgets/panel-background.svgz", 0.82, 0.0, 22),
                               ("translucent/widgets/panel-background.svgz", 0.92, 0.0, 0)):
        f = Frame()
        glass(f, "", 18, op, (6, 6, 10, 10), shadow=sh, frost=frost)
        # Top bar ("north-" is looked up first): edge-to-edge frosted strip, macOS
        # Tahoe proportions, no rim - just tint, frost and the blur behind it.
        glass(f, "north-", 2, op * 0.8, (2, 2, 10, 10), border=0.0, highlight=0.0, frost=frost)
        write(theme / rel, f)
    # Popups + notifications: frosted cards.
    for rel, op, frost, sh in (("dialogs/background.svgz", 0.94, 0.0, 28),
                               ("translucent/dialogs/background.svgz", 0.96, 0.0, 0)):
        f = Frame()
        glass(f, "", 22, op, (14, 14, 14, 14), shadow=sh, frost=frost)
        write(theme / rel, f)
    # Desktop widgets and tooltips.
    for rel, op, r, sh, frost in (("widgets/background.svgz", 0.9, 22, 18, 0.0),
                                  ("translucent/widgets/background.svgz", 0.92, 22, 0, 0.0),
                                  ("widgets/tooltip.svgz", 0.94, 14, 18, 0.0),
                                  ("translucent/widgets/tooltip.svgz", 0.95, 14, 0, 0.0)):
        f = Frame()
        glass(f, "", r, op, (12, 12, 14, 14) if r > 14 else (8, 8, 10, 10), shadow=sh, frost=frost)
        write(theme / rel, f)
    # Popup headers/footers (notification header, tray popups): no strip of their own,
    # the title just sits on the card's glass like an iOS banner.
    f = Frame()
    for pre in ("header-", "footer-"):
        glass(f, pre, 6, 0.0, (6, 6, 6, 6), border=0.0, highlight=0.0, mask=False)
    for side, (w, h) in {"top": (1, 6), "bottom": (1, 6), "left": (6, 1), "right": (6, 1)}.items():
        f.add(f'<rect id="hint-{side}-margin" x="{1900 + len(side)}" y="0" width="{w}" height="{h}" {TINY}/>')
    f.add(f'<rect id="hint-stretch-borders" x="1960" y="0" width="2" height="2" {TINY}/>')
    write(theme / "widgets/plasmoidheading.svgz", f)
    # Task manager items in the dock: soft rounded chips.
    f = Frame()
    glass(f, "normal-", 12, 0.0, (4, 4, 4, 4), border=0.0, highlight=0.0, mask=False)
    glass(f, "hover-", 12, 0.10, (4, 4, 4, 4), fill_class="ColorScheme-Text", border=0.08, highlight=0.08, mask=False)
    glass(f, "focus-", 12, 0.22, (4, 4, 4, 4), fill_class="ColorScheme-Highlight", border=0.0, highlight=0.12, mask=False)
    glass(f, "attention-", 12, 0.28, (4, 4, 4, 4), fill_class="ColorScheme-NegativeText", border=0.0, highlight=0.0, mask=False)
    glass(f, "minimized-", 12, 0.0, (4, 4, 4, 4), border=0.0, highlight=0.0, mask=False)
    glass(f, "progress-", 12, 0.25, (4, 4, 4, 4), fill_class="ColorScheme-Highlight", border=0.0, highlight=0.0, mask=False)
    write(theme / "widgets/tasks.svgz", f)
    # Workspace pager in the top bar: quiet pills, the current one tinted with the accent.
    f = Frame()
    glass(f, "normal-", 9, 0.06, (2, 2, 2, 2), fill_class="ColorScheme-Text", border=0.0, highlight=0.0, mask=False)
    glass(f, "hover-", 9, 0.14, (2, 2, 2, 2), fill_class="ColorScheme-Text", border=0.0, highlight=0.0, mask=False)
    glass(f, "active-", 9, 0.85, (2, 2, 2, 2), fill_class="ColorScheme-Highlight", border=0.0, highlight=0.15, mask=False)
    write(theme / "widgets/pager.svgz", f)
    print("frames drawn in", theme)


if __name__ == "__main__":
    import sys
    build(Path(sys.argv[1]) if len(sys.argv) > 1 else
          Path(__file__).resolve().parents[1] / "generated/desktoptheme/AetherGlass")
