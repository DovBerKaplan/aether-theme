#!/usr/bin/env python3
"""Generate AetherGlass / AetherSerenity Kvantum themes by recoloring WhiteSur.

WhiteSur (GPLv3, vinceliuice) provides the rounded, translucent SVG geometry;
we swap its palette for the Stitch "AetherOS" tokens.
"""
import re
import sys
from pathlib import Path

from tokens import load

SRC = Path(__file__).resolve().parents[1] / "vendor/whitesur-kvantum"
OUT = Path(__file__).resolve().parents[1] / "generated/kvantum"

_K = load()["kvantum"]
HACKS = _K.pop("hacks")
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
