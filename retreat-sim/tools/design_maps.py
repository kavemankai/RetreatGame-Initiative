"""Act 1 map redesigns. Writes data/maps/<mission>.json (these four maps are owned by this script;
tools/make_maps.py owns the rest) and an
annotated top-down blockout per map to ../art/style_test/blockout_<mission>.png, plus a
combined sheet blockouts_act1.png.      python tools/design_maps.py

Draft format = the live map format plus:
  doors          [[boundary, a, b, "v"|"h", "closed"|"open"], ...]  an edge that is a wall
                 until opened (v: between columns boundary-1 and boundary, rows a..b)
  zones          {name: {"tiles": [[x, y], ...], "kind": "objective"|"exit"|"fog"|"lit"|"start"}}
  enemies        [[x, y, tier, role, note], ...]   role: sentry (overwatch a lane),
                 guard (hold a tile), patrol (walk a loop / push), picket (hold until seen)
  reinforcements [[x, y, tier, round], ...]       arrive at the start of that round
  labels         [[x, y, "TEXT"], ...]            landmark names for the blockout
  objective_rule a sentence: what wins the map (needs objective systems; see design doc)
"""
import json
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_JSON = os.path.join(HERE, "..", "data", "maps")  # the live map files
OUT_PNG = os.path.join(HERE, "..", "..", "art", "style_test")


def rect(x0, y0, x1, y1):
    return [[x, y] for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)]


def diag(x0, y0, n, thick=2):
    out = []
    for i in range(n):
        for t in range(thick):
            out.append([x0 + i + t, y0 + i])
    return out


MAPS = {
    # ---------------------------------------------------------------------------------------------
    "karsa_breakout": {
        "theme": "station_deck", "size": [16, 12],
        "objective_rule": "Reach THE LOCK with any merc and hold it to the end of a round with no enemy inside the North Spine.",
        "goal": {"type": "hold", "zone": "THE LOCK", "clear": "NORTH SPINE"},
        "player_spawns": [[1, 9], [2, 9], [1, 10], [2, 10]],
        "blocked": [[2, 3], [5, 1], [6, 9], [13, 7], [10, 9], [9, 0]],
        "v_walls": [[8, 0, 4, "full"], [8, 7, 9, "full"], [8, 11, 11, "full"],   # the bulkhead (door rows 5-6, vent row 10)
                    [5, 7, 11, "full"],                                          # tram bay east wall
                    [6, 4, 5, "half"], [11, 5, 6, "half"]],                      # cover facing the door, both sides
        "h_walls": [[7, 0, 1, "full"], [7, 3, 4, "full"],                         # tram bay north wall, gap at x=2
                    [3, 9, 12, "full"],                                           # North Spine south wall
                    [10, 13, 14, "half"], [5, 2, 3, "half"]],
        "doors": [[8, 5, 6, "v", "closed"]],
        "zones": {"THE LOCK": {"tiles": rect(14, 0, 15, 2), "kind": "objective"},
                  "NORTH SPINE": {"tiles": rect(9, 0, 13, 2), "kind": "lit"},
                  "TRAM BAY": {"tiles": rect(0, 8, 4, 11), "kind": "start"}},
        "enemies": [[11, 5, "conscript", "sentry", "overwatch on the fire door", [-1, 0]],
                    [13, 9, "conscript", "patrol", "walks the east hall"],
                    [15, 1, "conscript", "guard", "holds the lock"]],
        "reinforcements": [],
        "labels": [[0, 7, "TRAM BAY"], [8, 4, "FIRE DOOR"], [8, 10, "VENT"], [9, 1, "NORTH SPINE"], [14, 0, "LOCK"]],
        "enemy_spawns": [[11, 5], [13, 9], [15, 1], [12, 0], [14, 5], [15, 10], [11, 11], [15, 7]],
        "objective": [14, 1],
    },
    # ---------------------------------------------------------------------------------------------
    "the_weir": {
        "theme": "wreck_field", "size": [18, 14],
        "objective_rule": "Recover all three salvage caches (end a round on each), then get every living merc back to the TUG.",
        "goal": {"type": "collect", "caches": ["CACHE A", "CACHE B", "CACHE C"], "exit": "TUG"},
        "player_spawns": [[1, 1], [2, 1], [1, 2], [2, 2]],
        "blocked": [b for b in diag(5, 3, 9) if b not in ([9, 7], [10, 7])]          # the Broken Freighter, breach at row 7
                   + [[3, 6], [4, 6], [12, 1], [16, 8], [7, 12], [2, 8], [15, 6], [11, 13]],
        "v_walls": [[4, 9, 10, "half"], [15, 10, 11, "half"], [13, 3, 3, "half"]],
        "h_walls": [[5, 14, 15, "half"], [11, 11, 12, "half"], [9, 1, 2, "half"]],
        "doors": [],
        "zones": {"CACHE A": {"tiles": [[3, 10]], "kind": "objective"},
                  "CACHE B": {"tiles": [[15, 3]], "kind": "objective"},
                  "CACHE C": {"tiles": [[16, 12]], "kind": "objective"},
                  "TUG": {"tiles": rect(0, 0, 2, 2), "kind": "exit"},
                  "DRIFT FOG": {"tiles": rect(7, 0, 11, 3), "kind": "fog"}},
        "enemies": [[15, 4, "conscript", "guard", "sits on cache B"],
                    [15, 12, "conscript", "guard", "sits on cache C"],
                    [11, 7, "conscript", "patrol", "watches the breach"]],
        "reinforcements": [],
        "labels": [[0, 0, "TUG"], [6, 5, "BROKEN FREIGHTER"], [9, 7, "BREACH"], [3, 11, "A"], [15, 2, "B"], [16, 13, "C"], [8, 0, "DRIFT FOG"]],
        "enemy_spawns": [[15, 4], [15, 12], [11, 7], [16, 1], [17, 6], [12, 12], [10, 12], [17, 13]],
        "objective": [15, 3],
    },
    # ---------------------------------------------------------------------------------------------
    "pellam_dock": {
        "theme": "dock_ring", "size": [16, 14],
        "objective_rule": "Hold the TUG BERTHS for 4 rounds. Each enemy standing on a berth tile at a round's end costs the Procession 50 people.",
        "goal": {"type": "survive", "rounds": 4, "watch": "TUG BERTHS", "penalty": 50},
        "player_spawns": [[4, 12], [7, 11], [9, 12], [12, 11]],
        "blocked": rect(7, 6, 8, 7)                                               # gantry crane legs
                   + rect(3, 3, 4, 4) + rect(11, 3, 12, 4) + [[2, 7], [2, 8], [13, 7], [13, 8]]   # cargo stacks
                   + [[0, 13], [15, 13]],
        "v_walls": [[15, 0, 4, "full"], [15, 7, 13, "full"]],                     # east fence, EAST GATE rows 5-6
        "h_walls": [[1, 0, 6, "full"], [1, 9, 15, "full"],                        # north fence, NORTH GATE x 7-8
                    [11, 3, 4, "half"], [11, 6, 7, "half"], [11, 9, 10, "half"], [11, 12, 12, "half"],   # bollard line
                    [5, 5, 6, "half"], [5, 9, 10, "half"]],
        "doors": [],
        "zones": {"TUG BERTHS": {"tiles": rect(3, 11, 12, 13), "kind": "objective"},
                  "NORTH GATE": {"tiles": rect(7, 0, 8, 0), "kind": "lit"},
                  "EAST GATE": {"tiles": [[15, 5], [15, 6]], "kind": "lit"}},
        "enemies": [[7, 0, "conscript", "patrol", "pushes through the north gate"],
                    [8, 0, "conscript", "patrol", "pushes through the north gate"],
                    [5, 4, "conscript", "sentry", "overwatch down the west alley", [0, 1]]],
        "reinforcements": [[15, 5, "conscript", 2], [15, 6, "regular", 2]],
        "labels": [[6, 0, "NORTH GATE"], [14, 5, "EAST GATE (round 2)"], [6, 6, "GANTRY CRANE"], [3, 12, "TUG BERTHS"]],
        "enemy_spawns": [[7, 0], [8, 0], [5, 4], [15, 5], [15, 6], [10, 2], [12, 0], [14, 2]],
        "objective": [8, 12],
    },
    # ---------------------------------------------------------------------------------------------
    "orchard_ring": {
        "theme": "garden_deck", "size": [14, 14],
        "objective_rule": "Reach the hostages in the GREENHOUSE, then bring them out through the MAINTENANCE HATCH.",
        "goal": {"type": "reach_return", "steps": ["GREENHOUSE", "MAINTENANCE HATCH"]},
        "player_spawns": [[12, 0], [13, 0], [12, 1], [13, 1]],
        "blocked": [[x, 2] for x in range(3, 11) if x not in (6, 7)] + [[x, 11] for x in range(3, 11) if x not in (6, 7)]
                   + [[2, y] for y in range(3, 11) if y not in (6, 7)] + [[11, y] for y in range(3, 11) if y not in (6, 7)],
        "v_walls": [[5, 5, 8, "full"], [9, 5, 8, "full"]],                        # greenhouse glass, east/west
        "h_walls": [[5, 5, 5, "full"], [5, 7, 8, "full"],                         # north glass, door at x=6
                    [9, 5, 6, "full"], [9, 8, 8, "full"],                         # south glass, door at x=7
                    [4, 3, 4, "half"], [10, 9, 10, "half"]],
        "doors": [[5, 6, 6, "h", "open"], [9, 7, 7, "h", "open"]],
        "zones": {"GREENHOUSE": {"tiles": rect(5, 5, 8, 8), "kind": "objective"},
                  "MAINTENANCE HATCH": {"tiles": rect(12, 0, 13, 1), "kind": "exit"},
                  "GROW-LAMP LANE": {"tiles": [[x, y] for x in range(3, 11) for y in range(3, 11) if x in (3, 4, 9, 10) or y in (3, 4, 9, 10)], "kind": "lit"}},
        "enemies": [[6, 4, "conscript", "guard", "north greenhouse door"],
                    [7, 9, "conscript", "guard", "south greenhouse door"],
                    [3, 7, "regular", "patrol", "walks the inner ring, west"],
                    [10, 4, "regular", "patrol", "walks the inner ring, east"]],
        "reinforcements": [],
        "labels": [[11, 0, "HATCH"], [5, 5, "GREENHOUSE"], [3, 2, "PLANTER RING"], [3, 9, "GROW-LAMP LANE"]],
        "enemy_spawns": [[6, 4], [7, 9], [3, 7], [10, 4], [0, 13], [13, 13], [0, 6], [7, 13]],
        "objective": [6, 6],
    },
}

TILE = 34
COL = {"floor_a": (38, 42, 50), "floor_b": (42, 46, 55), "blocked": (110, 116, 126), "full": (240, 240, 245),
       "half": (242, 177, 52), "door": (180, 120, 70), "player": (74, 163, 255), "enemy": (255, 97, 97),
       "reinf": (255, 160, 160), "objective": (255, 212, 121, 70), "exit": (120, 220, 140, 70), "fog": (150, 160, 180, 60),
       "lit": (255, 200, 120, 34), "start": (74, 163, 255, 40)}
ROLE_LETTER = {"sentry": "S", "guard": "G", "patrol": "P", "picket": "K"}


def render(name, m):
    w, h = m["size"]
    ox, oy = 12, 58
    img = Image.new("RGB", (w * TILE + 24, h * TILE + 175), (24, 27, 32))  # RGB base so RGBA fills blend
    d = ImageDraw.Draw(img, "RGBA")
    d.text((12, 8), f"{name}   {w}x{h}   ({m['theme']})", fill=(255, 255, 255))
    d.text((12, 26), m["objective_rule"][:118], fill=(200, 205, 215))
    if len(m["objective_rule"]) > 118:
        d.text((12, 40), m["objective_rule"][118:], fill=(200, 205, 215))
    for y in range(h):
        for x in range(w):
            d.rectangle((ox + x * TILE, oy + y * TILE, ox + x * TILE + TILE - 1, oy + y * TILE + TILE - 1),
                        fill=COL["floor_a"] if (x + y) % 2 == 0 else COL["floor_b"])
    for zname, z in m["zones"].items():
        for x, y in z["tiles"]:
            d.rectangle((ox + x * TILE, oy + y * TILE, ox + x * TILE + TILE - 1, oy + y * TILE + TILE - 1), fill=COL[z["kind"]])
    for x, y in m["blocked"]:
        d.rectangle((ox + x * TILE + 3, oy + y * TILE + 3, ox + x * TILE + TILE - 4, oy + y * TILE + TILE - 4),
                    fill=COL["blocked"], outline=(165, 170, 180))

    def seg(a, b, kind):
        if kind == "full":
            d.line((a, b), fill=COL["full"], width=5)
        elif kind == "door":
            d.line((a, b), fill=COL["door"], width=7)
        else:
            for i in (0, 2):
                p = (a[0] + (b[0] - a[0]) * i / 4, a[1] + (b[1] - a[1]) * i / 4)
                q = (a[0] + (b[0] - a[0]) * (i + 1) / 4, a[1] + (b[1] - a[1]) * (i + 1) / 4)
                d.line((p, q), fill=COL["half"], width=4)

    for bx, y0, y1, k in m["v_walls"]:
        for y in range(y0, y1 + 1):
            seg((ox + bx * TILE, oy + y * TILE), (ox + bx * TILE, oy + y * TILE + TILE), k)
    for by, x0, x1, k in m["h_walls"]:
        for x in range(x0, x1 + 1):
            seg((ox + x * TILE, oy + by * TILE), (ox + x * TILE + TILE, oy + by * TILE), k)
    for b, a0, a1, axis, state in m["doors"]:
        for a in range(a0, a1 + 1):
            if axis == "v":
                seg((ox + b * TILE, oy + a * TILE + 4), (ox + b * TILE, oy + a * TILE + TILE - 4), "door")
            else:
                seg((ox + a * TILE + 4, oy + b * TILE), (ox + a * TILE + TILE - 4, oy + b * TILE), "door" if state == "closed" else "half")
    for x, y in m["player_spawns"]:
        d.ellipse((ox + x * TILE + 7, oy + y * TILE + 7, ox + x * TILE + TILE - 7, oy + y * TILE + TILE - 7), fill=COL["player"])
    for e in m["enemies"]:
        x, y, tier, role = e[0], e[1], e[2], e[3]
        d.ellipse((ox + x * TILE + 5, oy + y * TILE + 5, ox + x * TILE + TILE - 5, oy + y * TILE + TILE - 5), fill=COL["enemy"])
        d.text((ox + x * TILE + 12, oy + y * TILE + 9), ROLE_LETTER.get(role, "?"), fill=(20, 20, 20))
    for x, y, tier, rnd in m["reinforcements"]:
        d.ellipse((ox + x * TILE + 5, oy + y * TILE + 5, ox + x * TILE + TILE - 5, oy + y * TILE + TILE - 5), outline=COL["reinf"], width=3)
        d.text((ox + x * TILE + 9, oy + y * TILE + 9), f"R{rnd}", fill=COL["reinf"])
    for x, y, text in m["labels"]:
        d.text((ox + x * TILE + 2, oy + y * TILE + 2), text, fill=(255, 255, 255))
    # legend
    ly = oy + h * TILE + 10
    legend = ("blue = squad start   red S/G/P = enemy sentry/guard/patrol   ring R2 = arrives round 2   gold = objective   green = exit",
              "white = full wall   dashed amber = half wall (cover)   brown = closed door   grey = blocked   blue-grey = drift fog   warm tint = lit lane")
    d.text((12, ly), legend[0], fill=(190, 195, 205))
    d.text((12, ly + 16), legend[1], fill=(190, 195, 205))
    for i, e in enumerate(m["enemies"]):
        x, y, tier, role, note = e[0], e[1], e[2], e[3], e[4]
        d.text((12, ly + 40 + i * 15), f"{ROLE_LETTER[role]} {tier} at {x},{y}: {note}", fill=(255, 160, 160))
    return img


def main():
    os.makedirs(OUT_JSON, exist_ok=True)
    images = []
    for name, m in MAPS.items():
        doc = dict(m)
        doc["mission"] = name
        doc["enemy_defs"] = [{"pos": [e[0], e[1]], "tier": e[2], "role": e[3], "note": e[4], "facing": e[5] if len(e) > 5 else [0, 0]} for e in m["enemies"]]
        doc["reinforcement_defs"] = [{"pos": [r[0], r[1]], "tier": r[2], "round": r[3]} for r in m["reinforcements"]]
        doc["zone_defs"] = {k: z["tiles"] for k, z in m["zones"].items()}
        for k in ("enemies", "reinforcements", "zones"):
            doc.pop(k, None)
        with open(os.path.join(OUT_JSON, name + ".json"), "w", encoding="utf-8") as f:
            json.dump(doc, f, indent=1)
            f.write("\n")
        img = render(name, m)
        img.save(os.path.join(OUT_PNG, f"blockout_{name}.png"))
        images.append(img)
        print(name, m["size"])
    wmax = max(i.width for i in images)
    sheet = Image.new("RGB", (wmax * 2, sum(max(images[k].height, images[k + 1].height) for k in (0, 2))), (24, 27, 32))
    y = 0
    for k in (0, 2):
        sheet.paste(images[k], (0, y))
        sheet.paste(images[k + 1], (wmax, y))
        y += max(images[k].height, images[k + 1].height)
    sheet.save(os.path.join(OUT_PNG, "blockouts_act1.png"))


if __name__ == "__main__":
    main()
