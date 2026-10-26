#!/usr/bin/env python3
"""Generate the two Global Theme (look-and-feel) packages and Konsole color schemes/profile."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "src"

VARIANTS = {
    "glass": dict(
        id="org.aether.glass.desktop", name="Aether Glass", scheme="AetherGlass",
        icons="Papirus-Dark", cursor="breeze_cursors", kvantum="AetherGlass",
        konsole=dict(
            bg="#0b0e14", fg="#e1e2eb", fg_intense="#ffffff", opacity="0.94",
            ansi=["#191c22", "#ff6b81", "#7cf5c4", "#ffd27a", "#4fa8ff", "#a98bff", "#00f2fe", "#c8ccd6"],
            bright=["#3a494b", "#ff8fa0", "#a3ffd9", "#ffe3a8", "#7cc0ff", "#cdbdff", "#6ff6ff", "#ffffff"],
        ),
    ),
    "serenity": dict(
        id="org.aether.serenity.desktop", name="Aether Serenity", scheme="AetherSerenity",
        icons="Papirus-Light", cursor="breeze_cursors", kvantum="AetherSerenity",
        konsole=dict(
            bg="#f8f9fa", fg="#191c1d", fg_intense="#000000", opacity="0.96",
            ansi=["#2e3132", "#ba1a1a", "#1e7d4f", "#8a6100", "#2a5d9f", "#6a4bb3", "#00696f", "#c5c6ca"],
            bright=["#595f65", "#d63b3b", "#2a9d63", "#a87700", "#3b78c4", "#8566d1", "#00838a", "#e1e3e4"],
        ),
    ),
}


def lnf(v: dict) -> None:
    d = ROOT / "look-and-feel" / v["id"]
    (d / "contents").mkdir(parents=True, exist_ok=True)
    (d / "metadata.json").write_text(json.dumps({
        "KPackageStructure": "Plasma/LookAndFeel",
        "KPlugin": {
            "Id": v["id"], "Name": v["name"],
            "Description": f"{v['name']} - AetherOS liquid glass desktop",
            "Authors": [{"Name": "DovBerKaplan"}], "License": "GPL-3.0-or-later",
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
        f"[kwinrc][org.kde.kdecoration2]\nlibrary=org.kde.breeze\ntheme=Breeze\n\n"
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
        "\n[General]\nName=Aether\nParent=FALLBACK/\nTerminalMargin=12\nTerminalCenter=false\n"
        "\n[Scrolling]\nScrollBarPosition=2\n"
        "\n[Terminal Features]\nBlinkingCursorEnabled=true\n"
        "\n[Cursor Options]\nCursorShape=1\n"
    )
    print("built look-and-feel + konsole")


if __name__ == "__main__":
    main()
