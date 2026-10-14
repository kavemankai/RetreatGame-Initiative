"""Audits every game asset's scale against the tile and a merc, prints a table of outliers
and writes art/style_test/scale_chart.png (every theme's wall, barrier and props next to a
merc, at game scale with the tile diamond drawn).   python art/audit_scale.py

Game scale: a tile is 128 px wide (64 px tall diamond); a merc figure stands 48 px in its
64 px frame, drawn at 0.95 tile widths, i.e. ~122 px tall at that scale.
Expected sizes (px at that scale):
  floor      exactly 64x32 in the file (stretched to the tile)
  prop       width 85-124, height 60-170
  full wall  height 110-160, width 55-100        half wall  height 55-95
  character  standing figure height 38-54 px in its 64 px frame (48 is the target)
"""
import glob
import os

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(ROOT, "..", "retreat-sim", "assets")
THEMES = os.path.join(ASSETS, "themes")
MERCS = os.path.join(ASSETS, "mercs")
MERC_H = 122  # a standing merc at game scale


def bbox_h(im):
    a = np.asarray(im.convert("RGBA"))[:, :, 3] > 40
    rows = np.where(a.any(axis=1))[0]
    cols = np.where(a.any(axis=0))[0]
    return (rows.max() - rows.min() + 1, cols.max() - cols.min() + 1) if len(rows) else (0, 0)


def main():
    problems = []
    for theme in sorted(os.listdir(THEMES)):
        d = os.path.join(THEMES, theme)
        if not os.path.isdir(d):
            continue
        for f in sorted(glob.glob(os.path.join(d, "floor_*.png"))):
            if Image.open(f).size != (64, 32):
                problems.append(f"{theme}/{os.path.basename(f)} floor is {Image.open(f).size}, not 64x32")
        for f in sorted(glob.glob(os.path.join(d, "crate_*.png"))):
            h, w = bbox_h(Image.open(f))
            if not (85 <= w <= 124 and 60 <= h <= 170):
                problems.append(f"{theme}/{os.path.basename(f)} prop {w}x{h}")
        for f in sorted(glob.glob(os.path.join(d, "wall_*.png"))):
            h, w = bbox_h(Image.open(f))
            half = f.endswith("_half.png")
            ok = (55 <= h <= 95) if half else (110 <= h <= 160 and 55 <= w <= 100)
            if not ok:
                problems.append(f"{theme}/{os.path.basename(f)} {'half ' if half else 'full '}wall {w}x{h}")
    # characters
    keys = sorted({os.path.basename(f).rsplit("_", 1)[0] for f in glob.glob(os.path.join(MERCS, "*_se.png"))})
    heights = {}
    for k in keys:
        h, _ = bbox_h(Image.open(os.path.join(MERCS, f"{k}_idle0.png")))
        heights[k] = h
        if not 38 <= h <= 54:
            problems.append(f"character {k} stands {h}px (target 48)")
    print("characters (standing height px):", {k: heights[k] for k in keys})
    print("\n".join(problems) if problems else "no outliers")
    chart()
    return problems


def chart():
    themes = [t for t in sorted(os.listdir(THEMES)) if os.path.isdir(os.path.join(THEMES, t))]
    cell_w, cell_h = 1000, 230
    sheet = Image.new("RGBA", (cell_w, cell_h * len(themes)), (30, 32, 38, 255))
    d = ImageDraw.Draw(sheet)
    merc = Image.open(os.path.join(MERCS, "warden_se.png")).convert("RGBA")
    mk = MERC_H / 48.0
    merc = merc.resize((int(64 * mk), int(64 * mk)), Image.NEAREST)
    for r, theme in enumerate(themes):
        y0 = r * cell_h
        d.text((4, y0 + 2), theme, fill=(255, 255, 255, 255))
        base = y0 + cell_h - 28
        x = 20
        # a 128x64 tile diamond for reference
        d.polygon([(x + 64, base - 64 + 32), (x + 128, base), (x + 64, base + 32 - 32 + 32), (x, base)], outline=(120, 140, 160, 255))
        sheet.paste(merc, (x + 64 - merc.width // 2, base - int(merc.height * 0.94)), merc)
        x += 150
        files = [os.path.join(THEMES, theme, f) for f in ("wall_z0_full.png", "wall_z0_half.png", "crate_0.png", "crate_1.png", "crate_2.png", "crate_3.png")]
        for f in files:
            if not os.path.exists(f):
                continue
            im = Image.open(f).convert("RGBA")
            sheet.paste(im, (x, base + 8 - im.height), im)
            x += im.width + 28
    sheet.convert("RGB").save(os.path.join(ROOT, "style_test", "scale_chart.png"))


if __name__ == "__main__":
    main()
