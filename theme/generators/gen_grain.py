#!/usr/bin/env python3
"""Generate the tileable fine-grain texture used by the island's matte surface."""
import random
from pathlib import Path

from PIL import Image

OUT = Path(__file__).resolve().parents[2] / "components/shared/AetherShared/assets/grain.png"
SIZE = 192


def main() -> None:
    rnd = random.Random(11)
    img = Image.new("L", (SIZE, SIZE))
    # Mid-grey noise with slight clumping: one-pixel grains read as "soft-touch" material.
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            px[x, y] = min(255, max(0, int(rnd.gauss(128, 40))))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT, optimize=True)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
