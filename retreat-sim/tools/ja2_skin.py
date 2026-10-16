"""Builds the local JA2 placeholder art from a checkout of the 1.13 game data. Output goes to
retreat-sim/assets/ja2/ (git-ignored, never distributed; see docs/LICENSE_AUDIT.md).

    python tools/ja2_skin.py mercs   [--src C:/Users/kyler/JA2Assets/anims/RGM]
    python tools/ja2_skin.py items   [--data C:/Users/kyler/JA2Assets/gamedir/Data-1.13]

JA2 soldiers are layered (legs, torso, head, hands, shadow) in a fixed palette whose colours stand for
skin, hair, vest and trousers; the original engine recolours them. This does the same, per unit key, and
writes the frame set the board already expects: <key>_<frame>.png, 64x64, feet at y=60.
"""
import argparse
import colorsys
import os

from PIL import Image

from ja2_sti import Sti

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "ja2", "mercs")
LAYERS = ("shadow", "legs", "torso", "head", "hands")
# JA2 direction order: N, NE, E, SE, S, SW, W, NW
NE, SE, SW, NW = 1, 3, 5, 7
FRAME = 64
FEET_Y = 60

# key -> (skin, hair, vest, pants)
PALETTES = {
    "warden": ((198, 150, 110), (60, 40, 30), (92, 104, 72), (60, 66, 58)),
    "gran": ((170, 120, 90), (150, 150, 150), (110, 96, 70), (70, 72, 64)),
    "sable": ((120, 84, 62), (20, 20, 24), (60, 76, 96), (44, 50, 62)),
    "needle": ((226, 184, 150), (200, 150, 70), (130, 70, 60), (60, 58, 66)),
    "bulwark": ((150, 104, 78), (30, 24, 20), (84, 88, 94), (52, 56, 64)),
    "moth": ((214, 168, 130), (90, 60, 40), (120, 98, 60), (72, 70, 60)),
    "wren": ((236, 196, 164), (170, 90, 50), (70, 96, 100), (56, 62, 64)),
    "ghost": ((96, 70, 56), (16, 16, 20), (40, 46, 56), (30, 34, 42)),
    "clerk": ((220, 190, 160), (110, 110, 112), (150, 150, 156), (90, 90, 100)),
    "gavel": ((200, 160, 130), (40, 40, 44), (36, 40, 60), (30, 32, 46)),
    "seal": ((190, 150, 120), (60, 50, 40), (60, 90, 110), (40, 56, 70)),
    "notary": ((226, 196, 170), (190, 190, 190), (120, 110, 150), (70, 66, 90)),
    "surveyor": ((180, 140, 112), (80, 60, 44), (100, 120, 90), (60, 72, 58)),
    "usher": ((210, 170, 140), (30, 30, 34), (140, 110, 60), (60, 50, 40)),
    "conscript": ((205, 165, 130), (80, 60, 44), (118, 120, 128), (78, 80, 90)),
    "regular": ((196, 156, 124), (50, 40, 34), (76, 94, 118), (52, 62, 80)),
    "veteran": ((180, 140, 112), (40, 36, 34), (56, 70, 96), (40, 48, 68)),
    "hollow": ((150, 154, 164), (150, 154, 164), (120, 124, 134), (86, 90, 100)),
    "orrick": ((214, 188, 164), (170, 170, 176), (24, 28, 40), (20, 22, 32)),
}

# frame name -> (animation, direction, frame index within the direction)
def frame_plan(counts):
    plan = {"se": ("S_N_STD", SE, 0), "sw": ("S_N_STD", SW, 0), "ne": ("S_N_STD", NE, 0), "nw": ("S_N_STD", NW, 0),
            "idle0": ("S_N_STD", SE, 0), "idle1": ("S_N_STD", SE, counts["S_N_STD"] // 2),
            "walk0": ("S_N_WALK", SE, 2), "walk1": ("S_N_WALK", SE, 8),
            "aim": ("S_N_SHOT", SE, 0), "fire": ("S_N_SHOT", SE, 2),
            "hit": ("S_N_FALL", SE, 3), "fall": ("S_N_FALL", SE, 14),
            "dead": ("S_N_FALL", SE, counts["S_N_FALL"] - 1)}
    for i in range(6):
        plan["run_%d" % i] = ("S_N_RUN", SE, i * 2)
        plan["runn_%d" % i] = ("S_N_RUN", NE, i * 2)
    return plan


def recolour(img, pal):
    skin, hair, vest, pants = pal
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            v = max(r, g, b) / 255.0
            h, s, _ = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            if s < 0.3 or v < 0.12:
                continue  # greys and blacks (boots, belts) stay as drawn
            deg = h * 360.0
            if 40 <= deg < 85:
                px[x, y] = (0, 0, 0, 90)  # the yellow placeholder is the ground shadow
                continue
            if 85 <= deg < 165:
                t = pants
            elif 165 <= deg < 205:
                t = hair
            elif 205 <= deg < 262:
                t = vest
            elif 262 <= deg <= 345:
                t = skin
            else:
                continue
            k = 0.45 + 0.75 * v
            px[x, y] = (min(255, int(t[0] * k)), min(255, int(t[1] * k)), min(255, int(t[2] * k)), a)
    return img


def compose(stis, idx):
    """All layers of one frame, placed by their own offsets on a scratch canvas; returns (image, origin)."""
    canvas = Image.new("RGBA", (160, 160), (0, 0, 0, 0))
    ax, ay = 80, 100
    for layer in LAYERS:
        s = stis[layer]
        if idx >= len(s.frames):
            continue
        f = s.frames[idx]
        canvas.alpha_composite(s.image(idx), (ax + f["ox"], ay + f["oy"]))
    return canvas


def build_mercs(src):
    anims = {}
    for name in ("S_N_STD", "S_N_WALK", "S_N_SHOT", "S_N_RUN", "S_N_FALL"):
        anims[name] = {l: Sti(os.path.join(src, "%s_%s.sti" % (name, l))) for l in LAYERS}
    counts = {n: len(a["torso"].frames) // 8 for n, a in anims.items()}
    plan = frame_plan(counts)
    # one fixed placement for every frame: the standing frame's feet land at (32, FEET_Y)
    stand = compose(anims["S_N_STD"], SE * counts["S_N_STD"])
    box = stand.getbbox()
    dx = 32 - (box[0] + box[2]) // 2
    dy = FEET_Y - box[3]
    os.makedirs(OUT, exist_ok=True)
    raw = {}
    for name, (anim, direction, n) in plan.items():
        raw[name] = compose(anims[anim], direction * counts[anim] + n)
    for key, pal in PALETTES.items():
        for name, scratch in raw.items():
            frame = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
            frame.alpha_composite(scratch, (dx - 0, dy - 0), (0, 0, 160, 160)) if False else None
            shifted = Image.new("RGBA", (FRAME + 160, FRAME + 160), (0, 0, 0, 0))
            shifted.alpha_composite(scratch, (dx + 40, dy + 40))
            frame = shifted.crop((40, 40, 40 + FRAME, 40 + FRAME))
            recolour(frame, pal).save(os.path.join(OUT, "%s_%s.png" % (key, name)))
    print("wrote %d frames for %d units to %s" % (len(raw) * len(PALETTES), len(PALETTES), os.path.abspath(OUT)))


# our item id -> ("GUN"|"P1ITEM", JA2 number): picked by eye from contact sheets of the 1.13 BigItems
ITEM_ART = {
    "service_rifle": ("GUN", 135), "assault_rifle": ("GUN", 120), "designated_rifle": ("GUN", 123),
    "carbine": ("GUN", 109), "repeater": ("GUN", 169), "machine_pistol": ("GUN", 150),
    "hunting_rifle": ("GUN", 138), "marksman_rifle": ("GUN", 124), "seal_rifle": ("GUN", 133), "long_rifle": ("GUN", 162),
    "scatter_gun": ("GUN", 128), "breacher": ("GUN", 183), "riot_gun": ("GUN", 197),
    "support_rifle": ("GUN", 141), "heavy_rifle": ("GUN", 205), "minigun": ("GUN", 192),
    "grenade_launcher": ("GUN", 143), "frag_launcher": ("GUN", 142), "heavy_launcher": ("GUN", 154),
    "laser_rifle": ("GUN", 168), "focused_laser": ("GUN", 196), "pulse_laser": ("GUN", 199),
    "compact_vest": ("P1ITEM", 66), "mourning_cloak": ("P1ITEM", 96), "padded_jacket": ("P1ITEM", 116),
    "plate_carrier": ("P1ITEM", 64), "gavel_plate": ("P1ITEM", 177), "ablative_coat": ("P1ITEM", 117),
    "scope": ("P1ITEM", 155), "sprint_boots": ("P1ITEM", 189), "stanchion": ("P1ITEM", 162), "reflex_rig": ("P1ITEM", 194),
}


def _find(folder, prefix, number):
    for name in (("%s%02d" % (prefix, number)), ("%s%d" % (prefix, number))):
        for ext in (".STI", ".sti"):
            p = os.path.join(folder, name + ext)
            if os.path.exists(p):
                return p
    raise FileNotFoundError("%s%d" % (prefix, number))


def build_items(data):
    out = os.path.join(HERE, "..", "assets", "ja2", "items")
    os.makedirs(out, exist_ok=True)
    folder = os.path.join(data, "BigItems")
    for item_id, (prefix, number) in ITEM_ART.items():
        img = Sti(_find(folder, prefix, number)).image(0)
        box = img.getbbox()
        img.crop(box).save(os.path.join(out, item_id + ".png"))
    print("wrote %d item icons to %s" % (len(ITEM_ART), os.path.abspath(out)))


FACES = {"warden": "170", "gran": "183", "sable": "196", "needle": "175", "bulwark": "177", "moth": "224", "wren": "218", "ghost": "178"}


def build_faces(data):
    out = os.path.join(HERE, "..", "assets", "ja2", "faces")
    os.makedirs(out, exist_ok=True)
    for key, number in FACES.items():
        path = os.path.join(data, "faces", number + ".sti")
        if not os.path.exists(path):
            path = os.path.join(data, "faces", number + ".STI")
        Sti(path).image(0).save(os.path.join(out, key + ".png"))
    print("wrote %d portraits to %s" % (len(FACES), os.path.abspath(out)))


VOICE_SETS = ("169", "170", "171", "172")  # four merc voices from BattleSNDS; each has OK1, HIT1 and DYING
VOICES = {"voice_ok": "OK1", "voice_hit": "HIT1", "voice_dying": "DYING"}


def build_sounds(data):
    import shutil
    out = os.path.join(HERE, "..", "assets", "ja2", "audio")
    os.makedirs(out, exist_ok=True)
    src = os.path.join(data, "BattleSNDS")
    n = 0
    for name, suffix in VOICES.items():
        for i, who in enumerate(VOICE_SETS):
            shutil.copyfile(os.path.join(src, "%s_%s.wav" % (who, suffix)), os.path.join(out, "%s_%d.wav" % (name, i)))
            n += 1
    print("copied %d voice clips to %s" % (n, os.path.abspath(out)))


def _scaled(img, factor):
    return img.resize((round(img.width * factor), round(img.height * factor)), Image.NEAREST)


def build_theme(data):
    """One JA2 'snow' theme from tilesets/50: dirt floors, crates and brick walls, named like a game theme."""
    out = os.path.join(HERE, "..", "assets", "ja2", "themes", "ja2_snow")
    os.makedirs(out, exist_ok=True)
    src = os.path.join(data, "tilesets", "50")

    def open_(name):
        return Sti(os.path.join(src, name + ".STI"))

    dirt = open_("2_DRT1")
    for i in range(9):
        im = dirt.image(i)
        im.crop(im.getbbox()).resize((64, 32), Image.NEAREST).save(os.path.join(out, "floor_%d.png" % i))
    crates = open_("2CRATE")
    for i in range(4):
        im = crates.image(i + 1)
        _scaled(im.crop(im.getbbox()), 2.6).save(os.path.join(out, "crate_%d.png" % i))
    walls = open_("E_WALL2")
    base = walls.image(0)
    base = base.crop(base.getbbox())
    # the board's wall is about a tile wide; JA2 walls are tall, so squash them a little to keep units visible behind them
    base = base.resize((round(base.width * 3.2), round(base.height * 2.3)), Image.NEAREST)
    for z, full in ((0, base), (1, base.transpose(Image.FLIP_LEFT_RIGHT))):
        full.save(os.path.join(out, "wall_z%d_full.png" % z))
        full.crop((0, full.height // 2, full.width, full.height)).save(os.path.join(out, "wall_z%d_half.png" % z))
    print("wrote the ja2_snow theme to %s" % os.path.abspath(out))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("what", choices=["mercs", "items", "theme", "sounds", "faces", "all"])
    ap.add_argument("--src", default=r"C:\Users\kyler\JA2Assets\anims\RGM")
    ap.add_argument("--data", default=r"C:\Users\kyler\JA2Assets\gamedir\Data-1.13")
    a = ap.parse_args()
    if a.what == "mercs":
        build_mercs(a.src)
    elif a.what == "items":
        build_items(a.data)
    elif a.what == "theme":
        build_theme(a.data)
    elif a.what == "sounds":
        build_sounds(a.data)
    elif a.what == "faces":
        build_faces(a.data)
    else:
        build_mercs(a.src)
        build_items(a.data)
        build_theme(a.data)
        build_sounds(a.data)
        build_faces(a.data)
