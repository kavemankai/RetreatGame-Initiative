"""Writes data/maps/proving_ground.json: the open test map for the sandbox (20x16).
Cover types: crates (block movement and sight), half walls (low cover), full walls (a small
compound with doorways and a window row), plus open ground to cross.     python tools/make_sandbox_map.py
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "data", "maps", "proving_ground.json")

crates = [
    [4, 2], [4, 3], [5, 3],            # NW stack
    [4, 12], [4, 13], [5, 12],         # SW stack
    [8, 7], [8, 8],                    # centre-west pair
    [14, 2], [15, 2],                  # north pair
    [14, 13], [15, 13], [15, 12],      # south stack
    [18, 4], [18, 11],                 # east edge singles
    [9, 14], [10, 1],                  # lone crates
]
v_walls = [
    [7, 4, 6, "half"], [7, 9, 11, "half"],          # low wall line west of centre (two runs, gap between)
    [12, 5, 5, "full"], [12, 8, 9, "full"],         # compound west wall (doorway rows 6-7)
    [17, 5, 6, "half"], [17, 8, 9, "half"],         # compound east: window-height wall
]
h_walls = [
    [5, 12, 13, "full"], [5, 15, 16, "full"],       # compound north wall (doorway at x=14)
    [10, 12, 13, "full"], [10, 15, 16, "full"],     # compound south wall (doorway at x=14)
    [3, 8, 11, "half"],                             # north barricade
    [13, 8, 11, "half"],                            # south barricade
    [7, 1, 2, "full"], [9, 1, 2, "full"],           # a short wall stub off the west edge
]
spawns_p = [[1, 6], [1, 7], [1, 8], [1, 9]]
spawns_e = [[16, 3], [16, 12], [14, 7], [18, 7], [18, 8], [15, 6], [15, 9], [13, 7], [19, 2], [19, 13], [10, 3], [10, 12]]

data = {
    "theme": "station_deck", "size": [20, 16],
    "note": "Open test map for the sandbox: crates, half walls and a compound. No goal: clear the enemies.",
    "player_spawns": spawns_p, "enemy_spawns": spawns_e,
    "blocked": crates, "v_walls": v_walls, "h_walls": h_walls,
    "objective": [18, 7],
}
with open(OUT, "w") as f:
    json.dump(data, f, indent=1)
print("wrote", OUT)
