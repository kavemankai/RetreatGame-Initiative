"""Cut a character's three raw sheets (generated on flat magenta) into game frames.

Raw files:   art/sprites/raw/<key>_faces.png   (2x2 turnaround: se, sw, ne, nw)
             art/sprites/raw/<key>_actions.png (3x3: idle0 idle1 walk0 walk1 aim fire hit fall dead)
             art/sprites/raw/<key>_run.png     (3x2: run_0..run_5)   [optional]
             art/sprites/raw/<key>_runne.png   (3x2: runn_0..runn_5, running up-right) [optional]
Output:      retreat-sim/assets/mercs/<key>_<frame>.png  (64x64, feet on a shared baseline)

The magenta background is keyed out locally (free), with a fringe clean-up so
no pink halo is left. Run: python art/slice_character.py quill [more keys]
"""
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(ROOT, "sprites", "raw")
OUT = os.path.join(ROOT, "..", "retreat-sim", "assets", "mercs")
FRAME = 64
BASELINE = 60
STAND_H = 48
KEY = np.array([255, 0, 255], dtype=float)
HARD = 70    # colour distance below which a pixel is background
SOFT = 150   # above this it is fully foreground; in between it is feathered

FACES = ["se", "sw", "ne", "nw"]
ACTIONS = ["idle0", "idle1", "walk0", "walk1", "aim", "fire", "hit", "fall", "dead"]
RUN = [f"run_{i}" for i in range(6)]
RUNN = [f"runn_{i}" for i in range(6)]  # running away from the camera (up-right; up-left is mirrored)


def key_out(im: Image.Image) -> Image.Image:
    """Remove the magenta background and any pink fringe."""
    a = np.asarray(im.convert("RGB")).astype(float)
    dist = np.linalg.norm(a - KEY, axis=2)
    alpha = np.clip((dist - HARD) / (SOFT - HARD), 0.0, 1.0)
    # despill: where red and blue both exceed green, pull them toward green
    # The generator also tints the figure itself pink; amber and teal have blue or green
    # above red/blue, so pulling red and blue down toward green only removes the cast.
    spill = np.clip(np.minimum(a[:, :, 0], a[:, :, 2]) - a[:, :, 1], 0, None)
    for ch in (0, 2):
        a[:, :, ch] = a[:, :, ch] - spill * 0.9
    # drop near-transparent speckle so the silhouette is clean
    alpha = np.where(alpha < 0.35, 0.0, np.where(alpha > 0.65, 1.0, alpha))
    out = np.dstack([np.clip(a, 0, 255), alpha * 255]).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def stats(frames: list) -> tuple:
    """Per-channel mean and std of every opaque pixel in `frames`."""
    px = np.concatenate([np.asarray(f)[:, :, :3][np.asarray(f)[:, :, 3] > 200] for f in frames]).astype(float)
    return px.mean(axis=0), px.std(axis=0) + 1e-6


def match_colours(frames: list, ref: tuple) -> list:
    """Shift each sheet's colours to the turnaround sheet's, so the run and action
    sheets (which the generator renders duller or warmer) read as the same character."""
    mean, std = stats(frames)
    out = []
    for f in frames:
        a = np.asarray(f).astype(float)
        rgb = (a[:, :, :3] - mean) / std * ref[1] + ref[0]
        a[:, :, :3] = np.clip(rgb, 0, 255)
        out.append(Image.fromarray(a.astype(np.uint8), "RGBA"))
    return out


def cells(im: Image.Image, cols: int, rows: int) -> list:
    cw, ch = im.width // cols, im.height // rows
    return [im.crop((c * cw, r * ch, (c + 1) * cw, (r + 1) * ch)) for r in range(rows) for c in range(cols)]


def bbox(im: Image.Image):
    alpha = np.asarray(im)[:, :, 3] > 40
    ys, xs = np.where(alpha)
    if len(xs) == 0:
        return None
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def build(sheet: str, cols: int, rows: int, names: list, key: str, ref_colours=None) -> tuple:
    path = os.path.join(RAW, f"{key}_{sheet}.png")
    if not os.path.exists(path):
        return 0.0, ref_colours
    frames = [key_out(c) for c in cells(Image.open(path), cols, rows)]
    if ref_colours is None:
        ref_colours = stats(frames)
    else:
        frames = match_colours(frames, ref_colours)
    boxes = [bbox(f) for f in frames]
    heights = [b[3] - b[1] for b in boxes if b]
    # one scale per sheet from its standing figure (or the average for the run cycle)
    ref = sum(heights) / len(heights) if sheet == "run" else heights[0]
    scale = STAND_H / ref
    for f, b, name in zip(frames, boxes, names):
        if b is None:
            continue
        crop = f.crop(b)
        size = (max(1, round(crop.width * scale)), max(1, round(crop.height * scale)))
        crop = crop.resize(size, Image.BOX)
        canvas = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
        canvas.paste(crop, ((FRAME - crop.width) // 2, BASELINE - crop.height), crop)
        canvas.save(os.path.join(OUT, f"{key}_{name}.png"))
    return ref, ref_colours


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for key in sys.argv[1:]:
        ref, colours = build("faces", 2, 2, FACES, key)
        build("actions", 3, 3, ACTIONS, key, colours)
        build("run", 3, 2, RUN, key, colours)
        build("runne", 3, 2, RUNN, key, colours)
        print(key, "done", round(ref, 1))


if __name__ == "__main__":
    main()
