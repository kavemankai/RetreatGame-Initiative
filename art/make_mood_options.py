"""Render four mood options for the same board scene into art/mood_options.png.

Scene: a wall, a crate, a squad of visored mercs, one faceless grey hollow,
two enemies and a lantern. Run: python art/make_mood_options.py
"""
from PIL import Image, ImageDraw, ImageFont
import os

S = 2                      # pixel scale
TILE = 30 * S
PW, PH = 10 * TILE, 6 * TILE
GAP = 30 * S
LABEL_H = 64 * S

PALETTES = [
    {"name": "A. Cold and hushed", "sub": "Blue-grey; warm light is rare",
     "floor": ("#171d27", "#232c3a"), "wall": "#aab4c4", "crate": ("#3a4352", "#566176"),
     "squad": "#7fa6d6", "enemy": "#8a5a5a", "hollow": "#8b8f96", "visor": "#10151d",
     "lantern": "#e8b45a", "halo": 0.25, "fog": "#0b0e14"},
    {"name": "B. Muted, one accent per side", "sub": "Amber Compact, teal Hegemony",
     "floor": ("#1f2227", "#2b2e35"), "wall": "#8d8f94", "crate": ("#3a3c42", "#55585f"),
     "squad": "#d99a3d", "enemy": "#3fa7a0", "hollow": "#8b8f96", "visor": "#15171b",
     "lantern": "#d99a3d", "halo": 0.25, "fog": "#0e0f12"},
    {"name": "C. Rich and painterly", "sub": "Full colour, soft light, storybook",
     "floor": ("#2a2638", "#3a3550"), "wall": "#6c5f8a", "crate": ("#5a4a63", "#7d6a86"),
     "squad": "#f0c987", "enemy": "#c75b6b", "hollow": "#9a97a8", "visor": "#2a2030",
     "lantern": "#ffd27a", "halo": 0.22, "fog": "#171424"},
    {"name": "D. High contrast graphic", "sub": "Bold shapes; readable first",
     "floor": ("#101010", "#1c1c1c"), "wall": "#f2f2f2", "crate": ("#444444", "#8a8a8a"),
     "squad": "#ffffff", "enemy": "#ff3b30", "hollow": "#8a8a8a", "visor": "#101010",
     "lantern": "#ffd400", "halo": 0.25, "fog": "#000000"},
]


def mix(hex_a, hex_b, t):
    a = tuple(int(hex_a[i:i + 2], 16) for i in (1, 3, 5))
    b = tuple(int(hex_b[i:i + 2], 16) for i in (1, 3, 5))
    return tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(3))


def unit(d, cx, cy, color, visor=None):
    r = 10 * S
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=color, outline=(0, 0, 0), width=S)
    if visor:  # the mask: a dark band across the face
        d.rectangle((cx - 6 * S, cy - 2 * S, cx + 6 * S, cy + 2 * S), fill=visor)


def panel(p):
    img = Image.new("RGB", (PW, PH), p["floor"][0])
    d = ImageDraw.Draw(img, "RGBA")
    for ty in range(6):
        for tx in range(10):
            if (tx + ty) % 2 == 1:
                d.rectangle((tx * TILE, ty * TILE, (tx + 1) * TILE, (ty + 1) * TILE), fill=p["floor"][1])
    # fog of war on the far right, soft edged (a drifting-mist stand-in)
    fog = tuple(int(p["fog"][i:i + 2], 16) for i in (1, 3, 5))
    for tx in range(8, 10):
        for ty in range(6):
            d.rectangle((tx * TILE, ty * TILE, (tx + 1) * TILE, (ty + 1) * TILE), fill=fog + (150 if tx == 8 else 215,))
    d.rectangle((5 * TILE, 1 * TILE, 5 * TILE + 5 * S, 3 * TILE), fill=p["wall"])
    d.rectangle((4 * TILE, 3 * TILE, 5 * TILE, 4 * TILE), fill=p["crate"][0], outline=p["crate"][1], width=S)
    # planned path
    for k in range(0, 40, 9):
        x = 75 * S + k * S * 0.75
        y = 105 * S + k * S * 0.75
        d.rectangle((x, y, x + 4 * S, y + 4 * S), fill=p["squad"])
    for pos in ((45, 75), (45, 135), (75, 105)):
        unit(d, pos[0] * S, pos[1] * S, p["squad"], p["visor"])
    unit(d, 75 * S, 45 * S, p["hollow"])  # faceless uniform hollow
    for pos in ((240, 90), (255, 135)):
        unit(d, pos[0] * S, pos[1] * S, p["enemy"], p["visor"])
    # lantern with a flat halo
    lx, ly = 270 * S, 30 * S
    halo = Image.new("RGBA", (PW, PH), (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo)
    rr = 22 * S
    c = tuple(int(p["lantern"][i:i + 2], 16) for i in (1, 3, 5))
    hd.ellipse((lx - rr, ly - rr, lx + rr, ly + rr), fill=c + (int(255 * p["halo"]),))
    img = Image.alpha_composite(img.convert("RGBA"), halo).convert("RGB")
    d = ImageDraw.Draw(img)
    d.ellipse((lx - 6 * S, ly - 6 * S, lx + 6 * S, ly + 6 * S), fill=p["lantern"])
    return img


def main():
    font = ImageFont.load_default(size=22 * S)
    small = ImageFont.load_default(size=15 * S)
    W = 2 * PW + 3 * GAP
    H = 2 * (PH + LABEL_H) + 3 * GAP
    sheet = Image.new("RGB", (W, H), "#2b2b2b")
    d = ImageDraw.Draw(sheet)
    for i, p in enumerate(PALETTES):
        x = GAP + (i % 2) * (PW + GAP)
        y = GAP + (i // 2) * (PH + LABEL_H + GAP)
        sheet.paste(panel(p), (x, y))
        d.text((x, y + PH + 8 * S), p["name"], fill="#ffffff", font=font)
        d.text((x, y + PH + 36 * S), p["sub"], fill="#b8b8b8", font=small)
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mood_options.png")
    sheet.save(out)
    print(out, sheet.size)


if __name__ == "__main__":
    main()
