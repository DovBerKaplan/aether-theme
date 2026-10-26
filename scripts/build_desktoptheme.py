#!/usr/bin/env python3
"""Build the AetherGlass Plasma desktop theme from Breeze ("default").

Breeze's SVGs use ColorScheme-* classes, so the theme follows whichever color
scheme is active (Glass at night, Serenity by day). Panels, popups, widgets,
tooltips and dock items are then redrawn as rounded glass by build_frames.py.
"""
import gzip
import sys
import json
import re
import shutil
from pathlib import Path

SRC = Path("/usr/share/plasma/desktoptheme/default")
OUT = Path(__file__).resolve().parent.parent / "src/desktoptheme/AetherGlass"
GLASS_OPACITY = "0.92"
GLASS_FILES = [
    "translucent/widgets/panel-background.svgz",
    "translucent/widgets/background.svgz",
    "translucent/widgets/tooltip.svgz",
    "translucent/dialogs/background.svgz",
]


def main() -> None:
    if OUT.exists():
        shutil.rmtree(OUT)
    shutil.copytree(SRC, OUT)
    for rel in GLASS_FILES:
        path = OUT / rel
        svg = gzip.decompress(path.read_bytes()).decode()
        # Breeze draws the panel/dialog fill at 0.85 and the widget fill at 0.8.
        svg, n = re.subn(r"opacity:0\.85?\b", f"opacity:{GLASS_OPACITY}", svg)
        path.write_bytes(gzip.compress(svg.encode()))
        print(f"{rel}: {n} fills -> {GLASS_OPACITY}")
    (OUT / "metadata.json").write_text(json.dumps({
        "KPlugin": {
            "Id": "AetherGlass",
            "Name": "Aether Glass",
            "Description": "Liquid-glass Plasma style following the active color scheme",
            "Authors": [{"Name": "Dov Mador"}],
            "Version": "1.0",
            "License": "LGPL-2.0-or-later",
            "Category": "Plasma Theme",
        },
        "X-Plasma-API-Minimum-Version": "6.0",
    }, indent=2) + "\n")
    (OUT / "plasmarc").write_text(
        "[ContrastEffect]\nenabled=true\ncontrast=0.9\nintensity=1.0\nsaturation=1.0\n\n"
        "[BlurBehindEffect]\nenabled=true\n\n[AdaptiveTransparency]\nenabled=true\n"
    )
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import build_frames
    build_frames.build(OUT)
    print("built", OUT)


if __name__ == "__main__":
    main()
