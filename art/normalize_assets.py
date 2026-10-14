"""Rescales every theme's wall and prop sprite to one canonical size. The generator draws each
piece at its own pixel scale, so without this a market stall can come out half the size of a
cargo stack.

Size = the sprite's full width (an isometric prop or wall piece is as wide as its footprint at
its widest, so this tracks the footprint without being fooled by the pointed base tip).
Canonical sizes are in sprite pixels at a 128 px wide tile (the game draws at tile_width/128).
A merc stands about 122 px tall at that scale, so heights are capped relative to it:
  props   width 120 px, at most 168 px tall   (just under a tile, up to ~1.4 mercs high)
  walls   width  96 px, at most 150 px tall (full) or 84 px tall (half barriers)
The scale is the smaller of the width match and the height cap.

Run after slicing (python art/slice_theme.py <themes>; python art/slice_iso_props.py):
    python art/normalize_assets.py
Not idempotent on already-normalised files only in the sense of tiny resampling blur;
re-slice from the raw sheets first when in doubt.
"""
import glob
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__))
THEMES = os.path.join(ROOT, "..", "retreat-sim", "assets", "themes")
PROP_FOOTPRINT = 120
PROP_MAX_HEIGHT = 168
WALL_FOOTPRINT = 96
WALL_MAX_HEIGHT = 150
HALF_WALL_MAX_HEIGHT = 84
BOTTOM_FRACTION = 0.12


def footprint_width(im: Image.Image) -> int:
    """The widest the sprite gets, in pixels."""
    a = np.asarray(im)[:, :, 3] > 40
    cols = np.where(a.any(axis=0))[0]
    return int(cols.max() - cols.min() + 1) if len(cols) else 0


def normalise(path: str, target: int, max_height: int) -> tuple:
    im = Image.open(path).convert("RGBA")
    fw = footprint_width(im)
    if fw == 0:
        return (0, 0)
    k = min(target / fw, max_height / im.height)
    if abs(k - 1.0) < 0.02:
        return (fw, fw)
    out = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.BOX if k < 1 else Image.NEAREST)
    out.save(path)
    return (fw, footprint_width(out))


def main() -> None:
    import sys
    only = sys.argv[1:]  # optional: just these themes (re-sliced ones), so others are not resampled twice
    for theme in sorted(os.listdir(THEMES)):
        if only and theme not in only:
            continue
        d = os.path.join(THEMES, theme)
        if not os.path.isdir(d):
            continue
        sizes = []
        for f in sorted(glob.glob(os.path.join(d, "crate_*.png"))):
            sizes.append(normalise(f, PROP_FOOTPRINT, PROP_MAX_HEIGHT))
        for f in sorted(glob.glob(os.path.join(d, "wall_*.png"))):
            sizes.append(normalise(f, WALL_FOOTPRINT, HALF_WALL_MAX_HEIGHT if f.endswith("_half.png") else WALL_MAX_HEIGHT))
        print(theme, [f"{a}->{b}" for a, b in sizes])


if __name__ == "__main__":
    main()
