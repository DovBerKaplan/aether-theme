#!/usr/bin/env python3
"""Generate the two Global Theme (look-and-feel) packages and Konsole color schemes/profile."""
import json
from pathlib import Path

from tokens import load

ROOT = Path(__file__).resolve().parents[1] / "generated"

_META = {
    "glass": dict(id="org.aether.glass.desktop", name="Aether Glass", scheme="AetherGlass",
                  icons="Colloid-Dark", cursor="breeze_cursors", kvantum="AetherGlass"),
    "serenity": dict(id="org.aether.serenity.desktop", name="Aether Serenity", scheme="AetherSerenity",
                     icons="Colloid-Light", cursor="breeze_cursors", kvantum="AetherSerenity"),
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
        f"[kcminputrc][Mouse]\ncursorTheme={v['cursor']}\n\n"
        f"[kwinrc][org.kde.kdecoration2]\nlibrary=org.kde.kwin.aurorae\ntheme=__aurorae__svg__{v['scheme']}\nButtonsOnLeft=XAI\nButtonsOnRight=\n\n"
        f"[KSplash]\nTheme=org.kde.Breeze\n"
    )


def rgb(h: str) -> str:
    h = h.lstrip("#")
    return ",".join(str(int(h[i:i + 2], 16)) for i in (0, 2, 4))


def konsole_scheme(key: str, v: dict) -> None:
    k = v["konsole"]
    out = [f"[General]\nDescription={v['name']}\nOpacity={k['opacity']}\nBlur=true\nWallpaper=\n"]
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
