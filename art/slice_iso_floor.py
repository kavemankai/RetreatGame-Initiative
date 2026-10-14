"""Slice art/style_test/iso_floor.png (3x3 sheet) into 64x32 diamond tiles
under retreat-sim/assets/tiles/floor_N.png. Run: python art/slice_iso_floor.py"""
from PIL import Image, ImageDraw
import os
import numpy as np

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(ROOT, "..", "retreat-sim", "assets", "tiles")
W, H = 64, 32
NAMES = ["plain", "riveted", "vent", "tread", "scuffed", "hatch", "cracked", "cable", "drain"]


def main() -> None:
    sheet = Image.open(os.path.join(ROOT, "style_test", "iso_floor.png")).convert("RGB")
    cw, ch = sheet.width // 3, sheet.height // 3
    mask = Image.new("L", (W * 4, H * 4), 0)
    ImageDraw.Draw(mask).polygon([(W * 2, 0), (W * 4 - 1, H * 2), (W * 2, H * 4 - 1), (0, H * 2)], fill=255)
    mask = mask.resize((W, H), Image.LANCZOS)
    for i, name in enumerate(NAMES):
        cell = sheet.crop(((i % 3) * cw, (i // 3) * ch, (i % 3 + 1) * cw, (i // 3 + 1) * ch))
        a = np.asarray(cell).astype(int)
        bg = a[2:6, 2:6].reshape(-1, 3).mean(0)
        diff = np.abs(a - bg).sum(2) > 24
        ys, xs = np.where(diff)
        box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
        tile = cell.crop(box).resize((W, H), Image.BOX).convert("RGBA")
        tile.putalpha(mask)
        tile.save(os.path.join(OUT, f"floor_{i}_{name}.png"))
        print(name, box)


if __name__ == "__main__":
    main()
