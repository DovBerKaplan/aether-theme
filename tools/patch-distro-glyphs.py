#!/usr/bin/env python3
# Fits the Nerd-Font distro glyphs (U+F300–U+F33F) inside their own cell.
#
# The stock glyphs are drawn edge to edge and most bleed past their advance —
# the neon logo spills 2/3 of a cell into whatever follows, Kali's dragon a
# full cell — so no arrangement of spaces around them can ever make the gaps
# read even at letter distance. Fitting the ink inside the cell does: the
# glyph's own margins then ARE the gaps, equal by construction on both sides.
#
# Usage:  python3 tools/patch-distro-glyphs.py [font.ttf ...]
#         (no arguments: patches every JetBrainsMono*NerdFont*.ttf under
#          ~/.local/share/fonts)
# Each file is backed up once as <name>.orig; glyphs that already fit are left
# untouched, so the script is safe to re-run.
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
MARGIN = 0.12                          # breathing room each side, in cells
TOLERANCE = 0.04                       # glyphs already inside this stay as-is

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
    changed = []
    for cp in RANGE:
        gname = cmap.get(cp)
        if gname is None:
            continue
        pen = BoundsPen(glyphset)
        glyphset[gname].draw(pen)
        if pen.bounds is None:
            continue
        x_min, y_min, x_max, y_max = pen.bounds
        adv = hmtx[gname][0]
        if x_min >= TOLERANCE * adv and x_max <= adv - TOLERANCE * adv:
            continue                      # already inside its cell
        span = x_max - x_min
        scale = min(1.0, adv * (1 - 2 * MARGIN) / span)
        # uniform scale, centred in the cell horizontally
        dx = adv * MARGIN + (adv * (1 - 2 * MARGIN) - span * scale) / 2 - x_min * scale
        cy = (y_min + y_max) / 2          # keep the vertical position
        t = Transform(scale, 0, 0, scale, dx, cy - cy * scale)
        rec = RecordingPen()
        glyphset[gname].draw(TransformPen(rec, t))
        tp = TTGlyphPen(glyphset)
        rec.replay(tp)
        new_glyph = tp.glyph()
        glyf[gname] = new_glyph
        new_glyph.recalcBounds(glyf)
        hmtx[gname] = (adv, new_glyph.xMin)
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
