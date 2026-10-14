"""Slice the background-removed Warden sheets into 64x64 sprite frames (feet on
a shared baseline, one scale per sheet) under retreat-sim/assets/mercs/.
Run: python art/slice_warden.py"""
from PIL import Image
import numpy as np
import os

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(ROOT, "..", "retreat-sim", "assets", "mercs")
FRAME = 64
BASELINE = 60
STAND_H = 48  # on-frame height of the standing figure


def cells(name: str, cols: int, rows: int) -> list[Image.Image]:
    im = Image.open(os.path.join(ROOT, "style_test", name)).convert("RGBA")
    cw, ch = im.width // cols, im.height // rows
    return [im.crop((c * cw, r * ch, (c + 1) * cw, (r + 1) * ch)) for r in range(rows) for c in range(cols)]


def bbox(im: Image.Image) -> tuple[int, int, int, int]:
    a = np.asarray(im)[:, :, 3] > 40
    ys, xs = np.where(a)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def build(sheet: str, cols: int, rows: int, names: list[str], prefix: str = "warden_") -> None:
    frames = cells(sheet, cols, rows)
    boxes = [bbox(f) for f in frames]
    # one scale per sheet, from the average figure height (frame 1 for the pose sheets)
    ref = sum(b[3] - b[1] for b in boxes) / len(boxes) if prefix.endswith("run_") else boxes[0][3] - boxes[0][1]
    scale = STAND_H / ref
    for f, b, name in zip(frames, boxes, names):
        crop = f.crop(b)
        size = (max(1, round(crop.width * scale)), max(1, round(crop.height * scale)))
        crop = crop.resize(size, Image.BOX)
        canvas = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
        canvas.paste(crop, ((FRAME - crop.width) // 2, BASELINE - crop.height), crop)
        canvas.save(os.path.join(OUT, f"{prefix}{name}.png"))


def main() -> None:
    build("iso_warden_facings_cut.png", 2, 2, ["se", "sw", "ne", "nw"])
    build("iso_warden_anim_cut.png", 3, 3, ["idle0", "idle1", "walk0", "walk1", "aim", "fire", "hit", "fall", "dead"])
    build("iso_warden_run_cut.png", 3, 2, [str(i) for i in range(6)], prefix="warden_run_")


if __name__ == "__main__":
    main()
