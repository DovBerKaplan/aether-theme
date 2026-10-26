#!/usr/bin/env python3
"""Render the AetherOS ambient wallpaper (blurred color orbs) as a Plasma wallpaper package.

Mirrors the Stitch HTML background: three blurred circles over a base color,
with a dimming veil on top. images/ is the light (Serenity) variant and
images_dark/ the Glass one; Plasma 6 picks per color scheme.
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parents[1] / "generated/wallpaper/AetherOS"
SIZES = [(1920, 1080), (2560, 1440), (3840, 2160)]

# (cx, cy, radius) as fractions of width, color RGBA, blur as fraction of width
DARK = dict(base=(16, 19, 26), veil=(16, 19, 26, 90), orbs=[
    ((0.175, -0.04, 0.325), (0, 242, 254, 10), 0.07),
    ((1.0, 0.75, 0.30), (78, 29, 190, 22), 0.08),
    ((0.50, 1.05, 0.25), (0, 220, 230, 8), 0.075),
])
LIGHT = dict(base=(248, 249, 250), veil=(248, 249, 250, 70), orbs=[
    ((0.175, -0.04, 0.325), (214, 228, 244, 40), 0.07),
    ((1.15, 0.75, 0.30), (221, 227, 234, 40), 0.08),
    ((0.50, 1.05, 0.25), (193, 199, 206, 30), 0.075),
])


def render(spec: dict, w: int, h: int) -> Image.Image:
    img = Image.new("RGBA", (w, h), spec["base"] + (255,))
    for (cx, cy, r), color, blur in spec["orbs"]:
        # Transparent pixels carry the orb's RGB so blurring doesn't pull in black fringes.
        layer = Image.new("RGBA", (w, h), color[:3] + (0,))
        d = ImageDraw.Draw(layer)
        R = r * w
        d.ellipse((cx * w - R, cy * h - R, cx * w + R, cy * h + R), fill=color)
        img = Image.alpha_composite(img, layer.filter(ImageFilter.GaussianBlur(blur * w)))
    img = Image.alpha_composite(img, Image.new("RGBA", (w, h), spec["veil"]))
    # Fine grain avoids banding in the dark gradients.
    noise = Image.effect_noise((w, h), 6).convert("L")
    grain = Image.merge("RGBA", (noise, noise, noise, Image.new("L", (w, h), 6)))
    return Image.alpha_composite(img, grain).convert("RGB")


def main() -> None:
    for sub, spec in (("images", LIGHT), ("images_dark", DARK)):
        d = OUT / "contents" / sub
        d.mkdir(parents=True, exist_ok=True)
        for w, h in SIZES:
            render(spec, w, h).save(d / f"{w}x{h}.png", optimize=True)
            print("wrote", d / f"{w}x{h}.png")
    (OUT / "metadata.json").write_text(json.dumps({
        "KPlugin": {"Id": "AetherOS", "Name": "AetherOS Ambient",
                    "Authors": [{"Name": "DovBerKaplan"}], "License": "CC-BY-SA-4.0"}
    }, indent=2) + "\n")


if __name__ == "__main__":
    main()
