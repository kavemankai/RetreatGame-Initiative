class_name MapData
extends RefCounted
## A mission's terrain: walls, blocked tiles, spawn points and a visual theme,
## loaded from res://data/maps/<mission>.json (written by tools/make_maps.py).

const DIR := "res://data/maps/"
## Contingency cards have no map of their own: they reuse one per act.
const CARD_MAPS := {1: "the_weir", 2: "cinder_market", 3: "reliquary_lane"}
const FALLBACK := "karsa_breakout"
const ROLES: Array[String] = ["sentry", "guard", "patrol"]
const THEMES: Array[String] = [
	"station_deck", "wreck_field", "dock_ring", "garden_deck", "hospital_hulk", "foundry_hold",
	"market_concourse", "gate_frame", "memorial_drift", "hull_corridor", "relay_station", "station_threshold",
]

var mission := ""
var theme := "station_deck"
var width := 12
var height := 10
var blocked: Array[Vector2i] = []
var player_spawns: Array[Vector2i] = []
var enemy_spawns: Array[Vector2i] = []
## The player's goal tile, for display and for the validator. The AI does not use it: it always
## advances on the player's side (SimMatch.AI_OBJECTIVE).
var objective := Vector2i(1, 5)
var edges: Array = []  # [Vector2i a, Vector2i b, int kind]
## Per-unit enemy placement (optional): {"pos": Vector2i, "tier": String, "role": String, "facing": Vector2i, "note": String}.
## A map with enemy_defs places exactly these; one without falls back to the mission's roster on the spawn list.
var enemy_defs: Array[Dictionary] = []
var reinforcement_defs: Array[Dictionary] = []  # {"pos", "tier", "round"}
var zones: Dictionary = {}  # name -> Array[Vector2i]
var goal: Dictionary = {}   # see SimGoal; empty = plain rout


## The map for a mission id, or for a card (by its act) / the fallback.
static func load_for(story: Dictionary, mission_id: String) -> MapData:
	var name := mission_id
	if not _has_file(name):
		name = _card_map(story, mission_id)
	var m := load_file(name)
	if m == null:
		m = load_file(FALLBACK)
	if m == null:
		push_error("no map for %s and no fallback map" % mission_id)
		m = MapData.new()  # an empty open field rather than a crash
		m.player_spawns = [Vector2i(1, 4), Vector2i(1, 5), Vector2i(2, 4), Vector2i(2, 5)]
		m.enemy_spawns = [Vector2i(10, 4), Vector2i(10, 5), Vector2i(9, 4), Vector2i(9, 5), Vector2i(10, 3), Vector2i(10, 6), Vector2i(9, 3), Vector2i(9, 6)]
	return m


static func _card_map(story: Dictionary, card_id: String) -> String:
	for c: Dictionary in story.get("route", {}).get("cards", []):
		if c["id"] == card_id:
			return CARD_MAPS.get(int(c["act"]), FALLBACK)
	return FALLBACK


static func _has_file(name: String) -> bool:
	return FileAccess.file_exists("%s%s.json" % [DIR, name])


static func load_file(name: String) -> MapData:
	var f := FileAccess.open("%s%s.json" % [DIR, name], FileAccess.READ)
	if f == null:
		return null
	var d: Variant = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY or not (d as Dictionary).has("size"):
		push_error("map %s is not a valid map file" % name)
		return null
	return from_dict(d)


static func from_dict(d: Dictionary) -> MapData:
	var m := MapData.new()
	m.mission = String(d.get("mission", ""))
	m.theme = String(d.get("theme", "station_deck"))
	m.width = int(d["size"][0])
	m.height = int(d["size"][1])
	for t in d.get("blocked", []):
		m.blocked.append(Vector2i(int(t[0]), int(t[1])))
	for t in d.get("player_spawns", []):
		m.player_spawns.append(Vector2i(int(t[0]), int(t[1])))
	for t in d.get("enemy_spawns", []):
		m.enemy_spawns.append(Vector2i(int(t[0]), int(t[1])))
	var o: Array = d.get("objective", [1, 5])
	m.objective = Vector2i(int(o[0]), int(o[1]))
	for e: Dictionary in d.get("enemy_defs", []):
		m.enemy_defs.append({"pos": Vector2i(int(e["pos"][0]), int(e["pos"][1])), "tier": String(e["tier"]), "role": String(e["role"]),
			"facing": Vector2i(int(e.get("facing", [0, 0])[0]), int(e.get("facing", [0, 0])[1])), "note": String(e.get("note", ""))})
	for r: Dictionary in d.get("reinforcement_defs", []):
		m.reinforcement_defs.append({"pos": Vector2i(int(r["pos"][0]), int(r["pos"][1])), "tier": String(r["tier"]), "round": int(r["round"])})
	for name in d.get("zone_defs", {}):
		var list: Array[Vector2i] = []
		for t in d["zone_defs"][name]:
			list.append(Vector2i(int(t[0]), int(t[1])))
		m.zones[String(name)] = list
	m.goal = (d.get("goal", {}) as Dictionary).duplicate(true)
	for w in d.get("v_walls", []):  # [boundary_x, y0, y1, kind]: between columns x-1 and x
		for y in range(int(w[1]), int(w[2]) + 1):
			m.edges.append([Vector2i(int(w[0]) - 1, y), Vector2i(int(w[0]), y), _kind(String(w[3]))])
	for w in d.get("h_walls", []):  # [boundary_y, x0, x1, kind]: between rows y-1 and y
		for x in range(int(w[1]), int(w[2]) + 1):
			m.edges.append([Vector2i(x, int(w[0]) - 1), Vector2i(x, int(w[0])), _kind(String(w[3]))])
	return m


static func _kind(name: String) -> int:
	if name != "full" and name != "half":
		push_warning("unknown wall kind '%s', treated as half cover" % name)
	return SimConst.EDGE_FULL if name == "full" else SimConst.EDGE_HALF


## A fresh SimState holding just this terrain (no units).
func build_state() -> SimState:
	var s := SimState.new(SimGrid.new(width, height))
	for t in blocked:
		s.grid.set_blocked(t)
	for e: Array in edges:
		s.grid.set_edge(e[0], e[1], e[2])
	return s


## Why this map cannot be played ("" = fine): bounds, spawns, and a way across.
func problem(player_count: int = 4, enemy_count: int = 8) -> String:
	var s := build_state()
	if not THEMES.has(theme):
		return "unknown theme '%s'" % theme
	if player_spawns.size() < player_count or enemy_spawns.size() < enemy_count:
		return "needs %d player and %d enemy spawns" % [player_count, enemy_count]
	var seen := {}
	for t in player_spawns + enemy_spawns:
		if not s.grid.in_bounds(t) or s.grid.is_blocked(t):
			return "spawn %s is off the map or blocked" % [t]
		if seen.has(t):
			return "spawn %s is used twice" % [t]
		seen[t] = true
	if not s.grid.in_bounds(objective) or s.grid.is_blocked(objective):
		return "the objective %s is off the map or blocked" % [objective]
	if blocked.size() * 100 > width * height * 35:
		return "more than 35% of the map is blocked"
	for e: Dictionary in enemy_defs:
		if not s.grid.in_bounds(e["pos"]) or s.grid.is_blocked(e["pos"]):
			return "enemy at %s is off the map or blocked" % [e["pos"]]
		if not ROLES.has(e["role"]):
			return "unknown enemy role '%s'" % e["role"]
		if e["role"] == "sentry" and e["facing"] == Vector2i.ZERO:
			return "the sentry at %s needs a facing" % [e["pos"]]
	for r: Dictionary in reinforcement_defs:
		if not s.grid.in_bounds(r["pos"]) or s.grid.is_blocked(r["pos"]):
			return "reinforcement at %s is off the map or blocked" % [r["pos"]]
	for name in SimGoal.zone_names(goal):
		if not zones.has(name):
			return "the goal names a zone that does not exist: %s" % name
	for name in zones:
		for t: Vector2i in zones[name]:
			if not s.grid.in_bounds(t):
				return "zone %s has a tile off the map" % name
	if player_spawns.is_empty():
		return "no player spawns"
	var reach := _reachable(s.grid, player_spawns[0])
	for t in player_spawns + enemy_spawns + [objective]:
		if not reach.has(t):
			return "%s cannot be reached from the first player spawn" % [t]
	return ""


static func _reachable(grid: SimGrid, from: Vector2i) -> Dictionary:
	var seen := {from: true}
	var open: Array[Vector2i] = [from]
	while not open.is_empty():
		var p: Vector2i = open.pop_back()
		for d in SimPathing.DIRS8:
			var q: Vector2i = p + d
			if not seen.has(q) and grid.can_step(p, q):
				seen[q] = true
				open.append(q)
	return seen
