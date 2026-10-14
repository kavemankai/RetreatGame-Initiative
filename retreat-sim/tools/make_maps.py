"""Writes data/maps/<mission>.json from compact layout specs, and prints each
map as ASCII so the layouts can be checked by eye.   python tools/make_maps.py

Coordinates: tiles are (x, y) with x 0..11 west to east and y 0..9 north to south.
  blocked      tiles nobody can enter or see through (crates, vats, hull)
  v_walls      [boundary_x, y0, y1, kind]: a wall between columns boundary_x-1 and boundary_x
  h_walls      [boundary_y, x0, x1, kind]: a wall between rows boundary_y-1 and boundary_y
  kind         "full" blocks sight and movement, "half" is cover you can see over
"""
import json
import os

W, H = 12, 10
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "maps")

PLAYER = [(1, 4), (1, 5), (2, 4), (2, 5)]
ENEMY = [(10, 4), (10, 5), (9, 4), (9, 5), (10, 3), (10, 6), (9, 3), (9, 6)]


def rect(x0, y0, x1, y1):
    return [(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)]


MAPS = {
    "quiet_wards": dict(
        theme="hospital_hulk", objective=(1, 5),
        blocked=[(3, 5), (8, 5), (5, 1), (5, 8)],
        v_walls=[[6, 4, 6, "half"]],
        h_walls=[[3, 2, 4, "full"], [3, 6, 9, "full"], [7, 2, 4, "full"], [7, 6, 9, "full"]],
    ),
    "anselm": dict(
        theme="foundry_hold", objective=(1, 5),
        blocked=[(4, 2), (4, 3), (7, 6), (7, 7), (5, 5), (6, 4), (9, 1), (9, 8)],
        v_walls=[[3, 6, 6, "half"], [8, 2, 3, "half"], [6, 7, 8, "full"]],
        h_walls=[[4, 3, 3, "half"], [6, 6, 8, "half"]],
    ),
    "cinder_market": dict(
        theme="market_concourse", objective=(1, 5),
        blocked=[(5, 3), (6, 6), (3, 8), (8, 1)],
        v_walls=[],
        h_walls=[[2, 3, 4, "half"], [2, 6, 7, "half"], [2, 9, 9, "half"], [5, 4, 5, "half"], [5, 7, 8, "half"],
                 [8, 2, 3, "half"], [8, 5, 6, "half"], [8, 8, 9, "half"]],
    ),
    "mirror_gate": dict(
        theme="gate_frame", objective=(1, 5),
        blocked=rect(0, 0, 11, 0) + rect(0, 9, 11, 9) + [(5, 3), (5, 6), (6, 3), (6, 6)],
        v_walls=[[8, 3, 3, "full"], [8, 6, 6, "full"], [8, 4, 5, "half"]],
        h_walls=[[4, 8, 9, "half"], [6, 8, 9, "half"]],
        player_spawns=[(1, 4), (1, 5), (2, 4), (2, 5)],
    ),
    "reliquary_lane": dict(
        theme="memorial_drift", objective=(10, 5),
        blocked=[(6, 2), (6, 3), (6, 6), (6, 7), (3, 4), (8, 5), (4, 8), (8, 1)],
        v_walls=[[5, 4, 5, "half"], [8, 2, 3, "half"], [8, 6, 7, "half"]],
        h_walls=[[4, 6, 7, "half"], [6, 6, 7, "half"]],
    ),
    "long_corridor": dict(
        theme="hull_corridor", objective=(1, 5),
        blocked=[(4, 4), (6, 5), (5, 6)],
        v_walls=[[8, 3, 3, "full"], [8, 6, 6, "full"], [8, 4, 5, "half"]],
        h_walls=[[3, 0, 11, "full"], [7, 0, 11, "full"]],
        player_spawns=[(1, 4), (1, 5), (2, 4), (2, 5)],
        enemy_spawns=[(9, 4), (9, 5), (10, 4), (10, 5), (9, 3), (9, 6), (10, 3), (10, 6)],
    ),
    "tamsins_rest": dict(
        theme="relay_station", objective=(1, 5),
        blocked=[(3, 1), (3, 2), (3, 7), (3, 8), (6, 3), (6, 4), (6, 5), (9, 2), (9, 7), (8, 8)],
        v_walls=[[7, 5, 8, "half"], [5, 1, 2, "full"], [5, 7, 9, "half"]],
        h_walls=[[3, 7, 8, "half"], [7, 4, 5, "half"]],
    ),
    "vesper_threshold": dict(
        theme="station_threshold", objective=(1, 5),
        blocked=[(5, 1), (5, 3), (5, 6), (5, 8), (7, 2), (7, 4), (7, 5), (7, 7)],
        v_walls=[[9, 2, 3, "full"], [9, 6, 7, "full"], [9, 4, 5, "half"], [3, 4, 5, "half"]],
        h_walls=[],
        enemy_spawns=[(10, 4), (10, 5), (10, 3), (10, 6), (8, 4), (8, 5), (8, 3), (8, 6)],
    ),
}


def build(name, spec):
    return {
        "mission": name, "theme": spec["theme"], "size": [W, H],
        "blocked": [list(t) for t in spec["blocked"]],
        "v_walls": spec["v_walls"], "h_walls": spec["h_walls"],
        "player_spawns": [list(t) for t in spec.get("player_spawns", PLAYER)],
        "enemy_spawns": [list(t) for t in spec.get("enemy_spawns", ENEMY)],
        "objective": list(spec["objective"]),
    }


def ascii_map(m):
    blocked = {tuple(t) for t in m["blocked"]}
    ps = {tuple(t) for t in m["player_spawns"]}
    es = {tuple(t) for t in m["enemy_spawns"]}
    vw = set()
    for x, y0, y1, k in m["v_walls"]:
        for y in range(y0, y1 + 1):
            vw.add((x, y, k))
    hw = set()
    for y, x0, x1, k in m["h_walls"]:
        for x in range(x0, x1 + 1):
            hw.add((x, y, k))
    rows = []
    for y in range(H):
        line = ""
        top = ""
        for x in range(W):
            hk = next((k for (hx, hy, k) in hw if hx == x and hy == y), None)
            top += ("==" if hk == "full" else "--" if hk == "half" else "  ")
            vk = next((k for (vx, vy, k) in vw if vx == x and vy == y), None)
            line += ("|" if vk == "full" else ":" if vk == "half" else " ")
            c = "#" if (x, y) in blocked else "P" if (x, y) in ps else "E" if (x, y) in es else "."
            line += c
        rows.append(top)
        rows.append(line)
    return "\n".join(rows)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, spec in MAPS.items():
        m = build(name, spec)
        with open(os.path.join(OUT, name + ".json"), "w", encoding="utf-8") as f:
            json.dump(m, f, indent=1)
            f.write("\n")
        print(f"== {name} ({m['theme']})")
        print(ascii_map(m))


if __name__ == "__main__":
    main()
