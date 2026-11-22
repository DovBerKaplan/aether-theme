#!/usr/bin/env python3
# Fits the Nerd-Font distro glyphs (U+F300–U+F33F) to the size of the "@"
# and seats them in the blank span between the words of the prompt.
#
# The stock glyphs are drawn edge to edge and most bleed past their advance —
# the neon logo spills 2/3 of a cell into whatever follows, Kali's dragon a
# full cell — so no arrangement of spaces around them can ever make the gaps
# read even. Instead each glyph is scaled to carry the "@"'s visual mass and
# centred inside the blank span that the prompt opens between the last letter
# of the name (the "r" of "user", one space of seat before the mark) and the
# first letter of the host (the "d" of the hostname). The gaps to either word
# are then equal by construction, for every glyph alike.
#
# The prompt (system/aether-prompt.sh) gives the mark its seat with
# `${name}\u ${mark}\h` — one space before it, nothing after.
#
# Usage:  python3 tools/patch-distro-glyphs.py [font.ttf ...]
#         (no arguments: patches every JetBrainsMono*NerdFont*.ttf under
#          ~/.local/share/fonts)
# Each file is backed up once as <name>.orig; glyphs that already sit well are
# left untouched, so the script is safe to re-run.
import glob
import os
import shutil
import sys

from fontTools.ttLib import TTFont
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.misc.transform import Transform

RANGE = range(0xF300, 0xF340)          # the distro-logo block
BOX_H = 1.45                           # ink height, in cells — the "@"'s height
INK_GAP = 0.12                         # closest the ink may come to a letter
TOLERANCE = 0.02                       # glyphs already seated stay as-is

def default_fonts():
    home = os.path.expanduser("~/.local/share/fonts")
    pat = os.path.join(home, "**", "JetBrainsMono*NerdFont*.ttf")
    for f in glob.glob(pat, recursive=True):
        if "Italic" not in f and "Propo" not in f:
            yield f

def fit_file(path):
    font = TTFont(path)
    glyphset = font.getGlyphSet()
    glyf = font["glyf"]
    hmtx = font["hmtx"]
    cmap = font.getBestCmap()

    adv = hmtx[cmap[ord("r")]][0]      # one mono cell, in font units
    # the blank span the prompt opens around the mark, relative to its pen:
    bp = BoundsPen(glyphset); glyphset[cmap[ord("r")]].draw(bp)
    blank_l = bp.bounds[2] - 2 * adv   # "r" sits two cells left of the mark's pen
    bp = BoundsPen(glyphset); glyphset[cmap[ord("d")]].draw(bp)
    blank_r = adv + bp.bounds[0]       # "d" sits one cell right of it
    centre = (blank_l + blank_r) / 2
    room = blank_r - blank_l - 2 * INK_GAP * adv

    at = cmap.get(0x40)                # the "@" — the height reference
    at_cy = None
    if at is not None:
        bp = BoundsPen(glyphset); glyphset[at].draw(bp)
        if bp.bounds is not None:
            at_cy = (bp.bounds[1] + bp.bounds[3]) / 2

    changed = []
    for cp in RANGE:
        gname = cmap.get(cp)
        if gname is None:
            continue
        bp = BoundsPen(glyphset); glyphset[gname].draw(bp)
        if bp.bounds is None:
            continue
        x_min, y_min, x_max, y_max = bp.bounds
        if (x_min >= centre - room / 2 and x_max <= centre + room / 2
                and y_max - y_min <= BOX_H * adv):
            continue                   # already sits in its seat
        scale = min(room / (x_max - x_min), BOX_H * adv / (y_max - y_min))
        cy = at_cy if at_cy is not None else (y_min + y_max) / 2
        t = Transform(scale, 0, 0, scale,
                      centre - (x_min + x_max) / 2 * scale,
                      cy - (y_min + y_max) / 2 * scale)
        rec = RecordingPen()
        glyphset[gname].draw(TransformPen(rec, t))
        tp = TTGlyphPen(glyphset)
        rec.replay(tp)
        g = tp.glyph()
        glyf[gname] = g
        g.recalcBounds(glyf)
        hmtx[gname] = (adv, g.xMin)
        changed.append(gname)
    if changed:
        if not os.path.exists(path + ".orig"):
            shutil.copy2(path, path + ".orig")
        font.save(path)
    return changed

def main():
    files = sys.argv[1:] or list(default_fonts())
    if not files:
        sys.exit("no fonts found to patch")
    for path in files:
        changed = fit_file(path)
        name = os.path.basename(path)
        print(f"{name}: {len(changed)} glyphs fitted" if changed else f"{name}: already clean")

if __name__ == "__main__":
    main()
