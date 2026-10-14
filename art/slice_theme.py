"""Cut a level theme's raw sheets (generated on flat magenta) into game assets.

Raw files:  art/sprites/raw/theme_<name>_floor.png   3x3 diamond floor tiles
            art/sprites/raw/theme_<name>_walls.png   5 wall pieces (top row: z0 tall, corner, z1 tall; bottom row: z0 low, z1 low)
            art/sprites/raw/theme_<name>_props.png   4 props
Output:     retreat-sim/assets/themes/<name>/floor_0..8.png (64x32 diamonds),
            wall_z0_full / wall_corner / wall_z1_full / wall_z0_half / wall_z1_half .png, crate_0..3.png

Run: python art/slice_theme.py wreck_field [more themes]
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from slice_character import key_out  # noqa: E402  (shared magenta keying)

ROOT = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(ROOT, "sprites", "raw")
OUT = os.path.join(ROOT, "..", "retreat-sim", "assets", "themes")
W, H = 64, 32


def alpha_bbox(im: Image.Image):
    a = np.asarray(im)[:, :, 3] > 40
    ys, xs = np.where(a)
    return (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1) if len(xs) else None


def floors(theme: str, out: str) -> int:
    path = os.path.join(RAW, f"theme_{theme}_floor.png")
    if not os.path.exists(path):
        return 0
    sheet = Image.open(path).convert("RGB")
    cw, ch = sheet.width // 3, sheet.height // 3
    mask = Image.new("L", (W * 4, H * 4), 0)
    ImageDraw.Draw(mask).polygon([(W * 2, 0), (W * 4 - 1, H * 2), (W * 2, H * 4 - 1), (0, H * 2)], fill=255)
    mask = mask.resize((W, H), Image.LANCZOS)
    n = 0
    for i in range(9):
        cell = key_out(sheet.crop(((i % 3) * cw, (i // 3) * ch, (i % 3 + 1) * cw, (i // 3 + 1) * ch)))
        box = alpha_bbox(cell)
        if box is None:
            continue
        tile = cell.crop(box).resize((W, H), Image.BOX)
        tile.putalpha(mask)
        tile.save(os.path.join(out, f"floor_{i}.png"))
        n += 1
    return n


def pieces(path: str, min_size: int = 120) -> list:
    im = key_out(Image.open(path).convert("RGB"))
    mask = ndimage.binary_dilation(np.asarray(im)[:, :, 3] > 40, iterations=6)
    lab, _ = ndimage.label(mask)
    out = []
    for s_y, s_x in ndimage.find_objects(lab):
        if s_x.stop - s_x.start >= min_size and s_y.stop - s_y.start >= min_size * 0.5:
            piece = im.crop((s_x.start, s_y.start, s_x.stop, s_y.stop))
            out.append(((s_x.start + s_x.stop) / 2, (s_y.start + s_y.stop) / 2, piece))
    return out


def walls(theme: str, out: str) -> int:
    path = os.path.join(RAW, f"theme_{theme}_walls.png")
    if not os.path.exists(path):
        return 0
    found = pieces(path)
    if len(found) < 5:
        print(f"  {theme}: only {len(found)} wall pieces found")
        return 0
    found.sort(key=lambda p: p[1])           # top to bottom
    top = sorted(found[:-2], key=lambda p: p[0])[:3] if len(found) > 5 else sorted(found[:3], key=lambda p: p[0])
    low = sorted(found[-2:], key=lambda p: p[0])
    names = ["wall_z0_full", "wall_corner", "wall_z1_full", "wall_z0_half", "wall_z1_half"]
    for name, p in zip(names, top + low):
        p[2].save(os.path.join(out, name + ".png"))
    return 5


def props(theme: str, out: str) -> int:
    path = os.path.join(RAW, f"theme_{theme}_props.png")
    if not os.path.exists(path):
        return 0
    found = pieces(path, 100)
    found.sort(key=lambda p: (p[1] > Image.open(path).height / 2, p[0]))
    n = 0
    for i, p in enumerate(found[:4]):
        p[2].save(os.path.join(out, f"crate_{i}.png"))
        n += 1
    return n


def main() -> None:
    for theme in sys.argv[1:]:
        out = os.path.join(OUT, theme)
        os.makedirs(out, exist_ok=True)
        print(theme, "floors", floors(theme, out), "walls", walls(theme, out), "props", props(theme, out))


if __name__ == "__main__":
    main()
