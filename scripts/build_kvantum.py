#!/usr/bin/env python3
"""Generate AetherGlass / AetherSerenity Kvantum themes by recoloring WhiteSur.

WhiteSur (GPLv3, vinceliuice) provides the rounded, translucent SVG geometry;
we swap its palette for the Stitch "AetherOS" tokens.
"""
import re
import sys
from pathlib import Path

SRC = Path.home() / ".config/Kvantum/WhiteSur"
OUT = Path(__file__).resolve().parent.parent / "src/kvantum"

THEMES = {
    "AetherGlass": {
        "base": "WhiteSurDark",
        "svg": {
            "#315bef": "#00dce6", "#5294e2": "#00f2fe", "#0e4bb4": "#00696f",
            "#333333": "#1d2026", "#2d2d2d": "#191c22", "#262626": "#10131a",
            "#31363b": "#272a31", "#4f4f4f": "#3a494b", "#656565": "#32353c",
            "#696969": "#3a494b", "#dfdfdf": "#e1e2eb", "#9d9d9d": "#849495",
        },
        "colors": {
            "window.color": "#10131a", "inactive.window.color": "#10131a",
            "base.color": "#0b0e14", "inactive.base.color": "#0b0e14",
            "alt.base.color": "#191c22", "inactive.alt.base.color": "#191c22",
            "button.color": "#272a31", "light.color": "#363940",
            "mid.light.color": "#32353c", "dark.color": "#0b0e14", "mid.color": "#1d2026",
            "highlight.color": "#00f2fe55", "inactive.highlight.color": "#00f2fe33",
            "text.color": "#e1e2eb", "inactive.text.color": "#b9cacb",
            "window.text.color": "#e1e2eb", "inactive.window.text.color": "#b9cacb",
            "button.text.color": "#e1e2eb", "disabled.text.color": "#849495",
            "tooltip.base.color": "#1d2026", "tooltip.text.color": "#e1e2eb",
            "highlight.text.color": "#e0fdff", "inactive.highlight.text.color": "#e1e2eb",
            "link.color": "#00dce6", "link.visited.color": "#cdbdff",
            "progress.indicator.text.color": "#00373a",
        },
    },
    "AetherSerenity": {
        "base": "WhiteSur",
        "svg": {
            "#0860f2": "#1a1d20", "#0e4bb4": "#44474a", "#b74aff": "#5c5f62",
            "#f5f5f5": "#f8f9fa", "#f2f2f2": "#f3f4f5", "#424242": "#2e3132",
        },
        "colors": {
            "window.color": "#f8f9fa", "inactive.window.color": "#f8f9fa",
            "base.color": "#ffffff", "inactive.base.color": "#ffffff",
            "alt.base.color": "#f3f4f5", "inactive.alt.base.color": "#f3f4f5",
            "button.color": "#ffffff", "light.color": "#ffffff",
            "mid.light.color": "#edeeef", "dark.color": "#c5c6ca", "mid.color": "#e1e3e4",
            "highlight.color": "#1a1d2026", "inactive.highlight.color": "#1a1d201a",
            "text.color": "#191c1d", "inactive.text.color": "#595f65",
            "window.text.color": "#191c1d", "inactive.window.text.color": "#595f65",
            "button.text.color": "#191c1d", "disabled.text.color": "#191c1d74",
            "tooltip.base.color": "#ffffff", "tooltip.text.color": "#191c1d",
            "highlight.text.color": "#191c1d", "inactive.highlight.text.color": "#2e3132",
            "link.color": "#1a1d20", "link.visited.color": "#595f65",
            "progress.indicator.text.color": "#ffffff",
        },
    },
}

HACKS = {
    "composite": "true", "translucent_windows": "true", "blurring": "true",
    "popup_blurring": "true", "reduce_window_opacity": "6",
    "reduce_menu_opacity": "4", "menu_blur_radius": "12",
}


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


def main() -> None:
    for name, t in THEMES.items():
        dest = OUT / name
        dest.mkdir(parents=True, exist_ok=True)
        svg = (SRC / f"{t['base']}.svg").read_text()
        for old, new in t["svg"].items():
            svg = re.sub(re.escape(old), new, svg, flags=re.I)
        (dest / f"{name}.svg").write_text(svg)
        cfg = (SRC / f"{t['base']}.kvconfig").read_text()
        cfg = set_keys(cfg, "GeneralColors", t["colors"])
        cfg = set_keys(cfg, "Hacks", HACKS)
        (dest / f"{name}.kvconfig").write_text(cfg)
        print("built", dest)


if __name__ == "__main__":
    main()
