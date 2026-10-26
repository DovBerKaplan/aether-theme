#!/usr/bin/env python3
"""Generate KDE .colors schemes (AetherGlass dark, AetherSerenity light) from Stitch tokens."""
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "generated/color-schemes"

PALETTES = {
    "AetherGlass": dict(
        name="Aether Glass", window="#10131a", view="#0b0e14", alt="#191c22",
        button="#1d2026", header="#0b0e14", tooltip="#1d2026", fg="#e1e2eb",
        fg_inactive="#b9cacb", accent="#00f2fe", accent_hover="#00dce6",
        selection="#00dce6", selection_fg="#00373a", link="#00dce6", visited="#cdbdff",
        negative="#ffb4ab", neutral="#ffd27a", positive="#7cf5c4",
        complementary="#0b0e14", wm_active="#0b0e14", wm_inactive="#10131a",
    ),
    "AetherSerenity": dict(
        name="Aether Serenity", window="#f8f9fa", view="#ffffff", alt="#f3f4f5",
        button="#ffffff", header="#f3f4f5", tooltip="#ffffff", fg="#191c1d",
        fg_inactive="#595f65", accent="#1a1d20", accent_hover="#44474a",
        selection="#1a1d20", selection_fg="#ffffff", link="#1a1d20", visited="#595f65",
        negative="#ba1a1a", neutral="#8a6100", positive="#1e7d4f",
        complementary="#2e3132", wm_active="#f3f4f5", wm_inactive="#f8f9fa",
    ),
}


def rgb(h: str) -> str:
    h = h.lstrip("#")
    return ",".join(str(int(h[i:i + 2], 16)) for i in (0, 2, 4))


def section(p: dict, bg: str, alt: str, fg: str | None = None, fg_inactive: str | None = None) -> str:
    fg = fg or p["fg"]
    fg_inactive = fg_inactive or p["fg_inactive"]
    rows = {
        "BackgroundAlternate": alt, "BackgroundNormal": bg,
        "DecorationFocus": p["accent"], "DecorationHover": p["accent_hover"],
        "ForegroundActive": p["accent"], "ForegroundInactive": fg_inactive,
        "ForegroundLink": p["link"], "ForegroundNegative": p["negative"],
        "ForegroundNeutral": p["neutral"], "ForegroundNormal": fg,
        "ForegroundPositive": p["positive"], "ForegroundVisited": p["visited"],
    }
    return "\n".join(f"{k}={rgb(v)}" for k, v in rows.items())


def build(key: str, p: dict) -> str:
    comp_fg = "#e1e2eb"
    parts = [
        "[ColorEffects:Disabled]\nColor=56,56,56\nColorAmount=0\nColorEffect=0\n"
        "ContrastAmount=0.65\nContrastEffect=1\nIntensityAmount=0.1\nIntensityEffect=2",
        "[ColorEffects:Inactive]\nChangeSelectionColor=true\nColor=112,111,110\n"
        "ColorAmount=0.025\nColorEffect=2\nContrastAmount=0.1\nContrastEffect=2\n"
        "Enable=false\nIntensityAmount=0\nIntensityEffect=0",
        "[Colors:Button]\n" + section(p, p["button"], p["alt"]),
        "[Colors:Complementary]\n" + section(p, p["complementary"], p["complementary"], comp_fg, "#b9cacb"),
        "[Colors:Header]\n" + section(p, p["header"], p["alt"]),
        "[Colors:Header][Inactive]\n" + section(p, p["window"], p["alt"]),
        "[Colors:Selection]\n" + section(p, p["selection"], p["accent_hover"], p["selection_fg"], p["selection_fg"]),
        "[Colors:Tooltip]\n" + section(p, p["tooltip"], p["alt"]),
        "[Colors:View]\n" + section(p, p["view"], p["alt"]),
        "[Colors:Window]\n" + section(p, p["window"], p["alt"]),
        f"[General]\nColorScheme={key}\nName={p['name']}\nshadeSortColumn=true",
        "[KDE]\ncontrast=4",
        f"[WM]\nactiveBackground={rgb(p['wm_active'])}\nactiveBlend={rgb(p['fg'])}\n"
        f"activeForeground={rgb(p['fg'])}\ninactiveBackground={rgb(p['wm_inactive'])}\n"
        f"inactiveBlend={rgb(p['fg_inactive'])}\ninactiveForeground={rgb(p['fg_inactive'])}",
    ]
    return "\n\n".join(parts) + "\n"


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for key, p in PALETTES.items():
        (OUT / f"{key}.colors").write_text(build(key, p))
        print("built", OUT / f"{key}.colors")
