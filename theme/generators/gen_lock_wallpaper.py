#!/usr/bin/env python3
"""Render the login-screen backgrounds: a soft "pearl" dome scene in the
LunariaOS / iPadOS spirit. pearl-day.png is silver-white, pearl-night.png is the Aether
Glass navy with a cyan rim light.
"""
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parents[2] / "login/aether-lock/backgrounds"
WALLPAPER = Path(__file__).resolve().parents[1] / "generated/wallpaper/AetherOS/contents"
W, H = 2560, 1440

SCENES = {
    "day": dict(top=(238, 241, 246), bottom=(196, 202, 214),
                shade=(120, 128, 146), light=(255, 255, 255), rim=(255, 255, 255)),
    "night": dict(top=(22, 26, 36), bottom=(11, 14, 20),
                  shade=(8, 10, 16), light=(46, 56, 76), rim=(0, 220, 230)),
}


def vgradient(top, bottom):
    g = Image.new("RGB", (1, H))
    for y in range(H):
        t = y / (H - 1)
        g.putpixel((0, y), tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    return g.resize((W, H))


def soft_ellipse(box, blur, scale=1.0):
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).ellipse(box, fill=int(255 * scale))
    return m.filter(ImageFilter.GaussianBlur(blur))


def tint(img, mask, color, strength):
    layer = Image.new("RGB", (W, H), color)
    return Image.composite(layer, img, mask.point(lambda v: int(v * strength)))


def render(s):
    img = vgradient(s["top"], s["bottom"])
    # Back dome: wide arch rising from the bottom, shaded on its upper edge.
    back = (-0.15 * W, 0.18 * H, 1.15 * W, 1.9 * H)
    img = tint(img, soft_ellipse(back, 90), s["shade"], 0.28)
    img = tint(img, soft_ellipse((back[0] + 60, back[1] + 70, back[2] - 60, back[3]), 120), s["light"], 0.55)
    # Front dome: brighter pearl, slightly lower, with a crisp rim.
    front = (0.12 * W, 0.52 * H, 0.88 * W, 1.75 * H)
    img = tint(img, soft_ellipse((front[0] - 40, front[1] - 50, front[2] + 40, front[3]), 70), s["shade"], 0.35)
    # Fill the dome with its own top-lit gradient so it reads as a 3D surface.
    shift = int(front[1])
    dome = Image.new("RGB", (W, H), s["light"])
    dome.paste(vgradient(s["light"], s["shade"]).resize((W, int(H * 1.1))), (0, shift))
    img = Image.composite(dome, img, soft_ellipse(front, 18).point(lambda v: int(v * 0.92)))
    rim = ImageChops.subtract(soft_ellipse(front, 3), soft_ellipse((front[0] + 14, front[1] + 14, front[2] - 14, front[3]), 10))
    img = tint(img, rim, s["rim"], 0.55)
    # Gentle side vignettes, like the folds in the LunariaOS wallpaper.
    for box in ((-0.35 * W, -0.2 * H, 0.18 * W, 1.2 * H), (0.82 * W, -0.2 * H, 1.35 * W, 1.2 * H)):
        img = tint(img, soft_ellipse(box, 160), s["shade"], 0.22)
    noise = Image.effect_noise((W, H), 5).convert("RGB")
    return Image.blend(img, noise, 0.02)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, s in SCENES.items():
        render(s).save(OUT / f"pearl-{name}.png", optimize=True)
        print("wrote", OUT / f"pearl-{name}.png")
    # The "aether" backgrounds reuse the desktop wallpaper, so the login screen matches it.
    import shutil
    for variant, sub in (("day", "images"), ("night", "images_dark")):
        src = WALLPAPER / sub / "2560x1440.png"
        if src.exists():
            shutil.copy(src, OUT / f"aether-{variant}.png")
            print("copied", OUT / f"aether-{variant}.png")


if __name__ == "__main__":
    main()
