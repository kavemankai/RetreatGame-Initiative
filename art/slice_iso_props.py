"""Slice the background-removed iso wall and crate sheets into sprites.
Run: python art/slice_iso_props.py   (needs numpy, scipy, Pillow)"""
from PIL import Image
import numpy as np
from scipy import ndimage
import os

ROOT = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.join(ROOT, "..", "retreat-sim", "assets", "themes", "station_deck")


def pieces(name: str, min_size: int = 150) -> list[Image.Image]:
    im = Image.open(os.path.join(ROOT, "style_test", name)).convert("RGBA")
    mask = ndimage.binary_dilation(np.asarray(im)[:, :, 3] > 40, iterations=6)
    lab, _ = ndimage.label(mask)
    out = []
    for s_y, s_x in ndimage.find_objects(lab):
        if s_x.stop - s_x.start >= min_size and s_y.stop - s_y.start >= min_size * 0.5:
            out.append((s_x.start, s_y.start, im.crop((s_x.start, s_y.start, s_x.stop, s_y.stop))))
    # left to right
    out.sort(key=lambda p: p[0])
    return [p[2] for p in out]


def main() -> None:
    walls = pieces("iso_walls_cut.png")
    assert len(walls) == 5, len(walls)
    corner = [w for w in walls if w.width < 320]
    tall = sorted((w for w in walls if w.width >= 320 and w.height > 450), key=lambda w: 0)
    low = [w for w in walls if w.width >= 320 and w.height <= 450]
    assert len(corner) == 1 and len(tall) == 2 and len(low) == 2, (len(corner), len(tall), len(low))
    # `pieces` returns left-to-right within a band; the left piece rises to the right
    # (runs down-left on screen = grid +y = edge z 0), the right one descends (z 1).
    named = {"wall_corner": corner[0], "wall_z0_full": tall[0], "wall_z1_full": tall[1],
             "wall_z0_half": low[0], "wall_z1_half": low[1]}
    for name, img in named.items():
        img.save(os.path.join(GAME, name + ".png"))
    crates = pieces("iso_crates_cut.png")
    assert len(crates) == 4, len(crates)
    for i, img in enumerate(crates):
        img.save(os.path.join(GAME, f"crate_{i}.png"))
    print("ok", {k: v.size for k, v in named.items()}, [im.size for im in crates])


if __name__ == "__main__":
    main()
