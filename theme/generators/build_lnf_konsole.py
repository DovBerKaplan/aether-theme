#!/usr/bin/env python3
"""Generate the two Global Theme (look-and-feel) packages and Konsole color schemes/profile."""
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

from tokens import load

ROOT = Path(__file__).resolve().parents[1] / "generated"

_META = {
    "glass": dict(id="org.aether.glass.desktop", name="Aether Glass", scheme="AetherGlass",
                  icons="Papirus-Dark", cursor="breeze_cursors", kvantum="AetherGlass"),
    "serenity": dict(id="org.aether.serenity.desktop", name="Aether Serenity", scheme="AetherSerenity",
                     icons="Papirus-Light", cursor="breeze_cursors", kvantum="AetherSerenity"),
}
VARIANTS = {
    key: dict(meta, konsole={a.replace("-", "_"): b for a, b in load()["terminal"][key].items()})
    for key, meta in _META.items()
}


def lnf(v: dict) -> None:
    d = ROOT / "look-and-feel" / v["id"]
    (d / "contents").mkdir(parents=True, exist_ok=True)
    (d / "metadata.json").write_text(json.dumps({
        "KPackageStructure": "Plasma/LookAndFeel",
        "KPlugin": {
            "Id": v["id"], "Name": v["name"],
            "Description": f"{v['name']} - AetherOS liquid glass desktop",
            "Authors": [{"Name": "Dov Mador"}], "License": "GPL-3.0-or-later",
            "Version": "1.0", "Category": "",
        },
        "X-Plasma-API-Minimum-Version": "6.0",
    }, indent=2) + "\n")
    (d / "contents/defaults").write_text(
        f"[kdeglobals][KDE]\nwidgetStyle=kvantum\n\n"
        f"[kdeglobals][General]\nColorScheme={v['scheme']}\n\n"
        f"[kdeglobals][Icons]\nTheme={v['icons']}\n\n"
        f"[plasmarc][Theme]\nname=AetherGlass\n\n"
        f"[Wallpaper]\nImage=AetherOS\n\n"
        f"[kcminputrc][Mouse]\ncursorTheme={v['cursor']}\n\n"
        f"[kwinrc][org.kde.kdecoration2]\nlibrary=org.kde.kwin.aurorae\ntheme=__aurorae__svg__{v['scheme']}\nButtonsOnLeft=XIA\nButtonsOnRight=\n\n"
        f"[KSplash]\nTheme=org.kde.Breeze\n"
    )


def rgb(h: str) -> str:
    h = h.lstrip("#")
    return ",".join(str(int(h[i:i + 2], 16)) for i in (0, 2, 4))


def _centres(p, q, r):
    """The two centres of a radius-r circle through p and q."""
    mx, my = (p[0] + q[0]) / 2, (p[1] + q[1]) / 2
    dx, dy = q[0] - p[0], q[1] - p[1]
    d = math.hypot(dx, dy)
    h = math.sqrt(max(0.0, r * r - d * d / 4))
    return [(mx - dy / d * h, my + dx / d * h), (mx + dy / d * h, my - dx / d * h)]


def mark(path: Path, ink: str, alpha: float) -> None:
    """The Aether mark (components/island/qml/assets/glyphs/logo.svg: a crescent and a spark) as a
    soft, blurred watermark centred on a wide transparent canvas - Konsole crops it to the window."""
    W, H, U = 1600, 1000, 22                      # canvas, and px per logo unit (the logo is 16 units)
    big = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(big)
    ox, oy = W / 2 - 8 * U, H / 2 - 8 * U
    at = lambda x, y: (ox + x * U, oy + y * U)
    p, q, mid = (7.2, 1.5), (14.5, 9.4), (8, 8)
    outer = min(_centres(p, q, 6.5), key=lambda c: math.dist(c, mid))
    inner = max(_centres(p, q, 5.2), key=lambda c: math.dist(c, mid))
    disk = lambda c, r, fill: d.ellipse([*at(c[0] - r, c[1] - r), *at(c[0] + r, c[1] + r)], fill=fill)
    disk(outer, 6.5, 255)
    disk(inner, 5.2, 0)
    spark = [(12, 1.2), (12.55, 2.85), (14.2, 3.4), (12.55, 3.95), (12, 5.6), (11.45, 3.95), (9.8, 3.4), (11.45, 2.85)]
    d.polygon([at(*pt) for pt in spark], fill=255)
    a = big.filter(ImageFilter.GaussianBlur(14)).point(lambda v: int(v * alpha))
    img = Image.new("RGBA", (W, H), tuple(int(ink[i:i + 2], 16) for i in (1, 3, 5)) + (0,))
    img.putalpha(a)
    img.save(path)


def konsole_scheme(key: str, v: dict) -> None:
    k = v["konsole"]
    # @MARK_DIR@ becomes the installed konsole folder (install/install-apps.sh): Konsole wants an absolute path.
    mark(ROOT / "konsole" / f"{v['scheme']}-mark.png", "#ffffff" if key == "glass" else "#1a1d20", k["mark"])
    out = [f"[General]\nDescription={v['name']}\nOpacity={k['opacity']}\nBlur=true\n"
           f"Wallpaper=@MARK_DIR@/{v['scheme']}-mark.png\nFillStyle=Crop\n"]
    out.append(f"[Background]\nColor={rgb(k['bg'])}\n")
    out.append(f"[BackgroundIntense]\nColor={rgb(k['bg'])}\n")
    out.append(f"[BackgroundFaint]\nColor={rgb(k['bg'])}\n")
    out.append(f"[Foreground]\nColor={rgb(k['fg'])}\n")
    out.append(f"[ForegroundIntense]\nColor={rgb(k['fg_intense'])}\n")
    out.append(f"[ForegroundFaint]\nColor={rgb(k['ansi'][7])}\n")
    for i, (n, b) in enumerate(zip(k["ansi"], k["bright"])):
        out.append(f"[Color{i}]\nColor={rgb(n)}\n")
        out.append(f"[Color{i}Intense]\nColor={rgb(b)}\n")
        out.append(f"[Color{i}Faint]\nColor={rgb(n)}\n")
    (ROOT / "konsole" / f"{v['scheme']}.colorscheme").write_text("\n".join(out))


def main() -> None:
    (ROOT / "konsole").mkdir(parents=True, exist_ok=True)
    for key, v in VARIANTS.items():
        lnf(v)
        konsole_scheme(key, v)
    (ROOT / "konsole/Aether.profile").write_text(
        "[Appearance]\nColorScheme=AetherGlass\nFont=JetBrainsMono Nerd Font,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1\n"
        "\n[General]\nName=Aether\nParent=FALLBACK/\nTerminalMargin=18\nTerminalCenter=false\n"
        "\n[Scrolling]\nScrollBarPosition=2\n"
        "\n[Terminal Features]\nBlinkingCursorEnabled=true\n"
        "\n[Cursor Options]\nCursorShape=1\n"
    )
    print("built look-and-feel + konsole")


if __name__ == "__main__":
    main()
