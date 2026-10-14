"""Draws a top-down block-out of every mission map (art/style_test/map_blockouts.png):
blocked tiles, full walls (solid), half walls (dashed), spawns and the objective.
   python art/make_blockouts.py"""
import json
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(ROOT, "..", "retreat-sim", "data")
T = 30
COLS = 3


def panel(m, title, sub):
    w, h = m["size"]
    img = Image.new("RGB", (w * T + 20, h * T + 64), (24, 27, 32))
    d = ImageDraw.Draw(img)
    d.text((10, 6), title, fill=(255, 255, 255))
    d.text((10, 22), sub, fill=(150, 160, 175))
    ox, oy = 10, 44
    for y in range(h):
        for x in range(w):
            c = (38, 42, 50) if (x + y) % 2 == 0 else (42, 46, 55)
            d.rectangle((ox + x * T, oy + y * T, ox + x * T + T - 1, oy + y * T + T - 1), fill=c)
    for x, y in m["blocked"]:
        d.rectangle((ox + x * T + 3, oy + y * T + 3, ox + x * T + T - 4, oy + y * T + T - 4), fill=(110, 116, 126), outline=(160, 166, 176))
    def line(a, b, kind):
        col = (240, 240, 245) if kind == "full" else (242, 177, 52)
        if kind == "full":
            d.line((a, b), fill=col, width=5)
        else:
            n = 4
            for i in range(0, n, 2):
                p = (a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n)
                q = (a[0] + (b[0] - a[0]) * (i + 1) / n, a[1] + (b[1] - a[1]) * (i + 1) / n)
                d.line((p, q), fill=col, width=4)
    for bx, y0, y1, kind in m["v_walls"]:
        for y in range(y0, y1 + 1):
            line((ox + bx * T, oy + y * T), (ox + bx * T, oy + y * T + T), kind)
    for by, x0, x1, kind in m["h_walls"]:
        for x in range(x0, x1 + 1):
            line((ox + x * T, oy + by * T), (ox + x * T + T, oy + by * T), kind)
    for x, y in m["player_spawns"]:
        d.ellipse((ox + x * T + 6, oy + y * T + 6, ox + x * T + T - 6, oy + y * T + T - 6), fill=(74, 163, 255))
    for x, y in m["enemy_spawns"]:
        d.ellipse((ox + x * T + 6, oy + y * T + 6, ox + x * T + T - 6, oy + y * T + T - 6), fill=(255, 97, 97))
    x, y = m["objective"]
    cx, cy = ox + x * T + T // 2, oy + y * T + T // 2
    d.polygon([(cx, cy - 10), (cx + 4, cy - 3), (cx + 11, cy - 3), (cx + 5, cy + 2), (cx + 7, cy + 10), (cx, cy + 5), (cx - 7, cy + 10), (cx - 5, cy + 2), (cx - 11, cy - 3), (cx - 4, cy - 3)], fill=(255, 212, 121))
    return img


def main():
    route = json.load(open(os.path.join(DATA, "story", "route.json"), encoding="utf-8"))
    panels = []
    for mi in route["missions"]:
        m = json.load(open(os.path.join(DATA, "maps", mi["id"] + ".json"), encoding="utf-8"))
        panels.append(panel(m, f"A{mi['act']}  {mi['name']}", f"{m['theme']} - {mi['objective']['type']}"))
    pw, ph = panels[0].size
    rows = (len(panels) + COLS - 1) // COLS
    legend = 34
    sheet = Image.new("RGB", (COLS * pw, rows * ph + legend), (24, 27, 32))
    d = ImageDraw.Draw(sheet)
    d.text((10, 10), "blue = your squad   red = enemy spawns   star = objective   solid white = full wall   dashed amber = half wall (cover)   grey = blocked", fill=(200, 205, 215))
    for i, p in enumerate(panels):
        sheet.paste(p, ((i % COLS) * pw, legend + (i // COLS) * ph))
    out = os.path.join(ROOT, "style_test", "map_blockouts.png")
    sheet.save(out)
    print(out, sheet.size)


if __name__ == "__main__":
    main()
