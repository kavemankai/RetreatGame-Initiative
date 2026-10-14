class_name Sandbox
extends RefCounted
## The test sandbox: one open map, four mercs whose stats and gear you set, and an enemy
## list you place yourself. A config is a plain Dictionary (never mutated; the edit helpers
## return a changed copy):
##   {"mercs": [{"slot", "stats": {hp,speed,aim,cqb,morale,sight}, "gear": {armour,weapon,mod}, "pos": Vector2i} x4],
##    "enemies": [{"kind", "hollow", "role", "pos": Vector2i}], "ruleset": "initiative" | "planned"}

const MAP := "proving_ground"
const SQUAD := 4
const MAX_ENEMIES := 12
const PLAYER_ZONE_X := 5  # mercs may start on columns 0..this
const STAT_KEYS: Array[String] = ["hp", "speed", "aim", "cqb", "morale", "sight"]
const STAT_RANGE := {"hp": [1, 8], "speed": [1, 10], "aim": [1, 10], "cqb": [0, 10], "morale": [0, 10], "sight": [3, 12]}
const ROLES: Array[String] = ["patrol", "guard", "sentry"]
const SENTRY_FACING := Vector2i(-1, 0)  # sentries watch west, toward the squad
const SINGLE_KINDS := ["provost", "officer_1", "officer_2", "officer_3", "officer_4", "officer_5", "officer_6"]


static func default_config(story: Dictionary) -> Dictionary:
	var c := Campaign.new_game(story)
	var map := MapData.load_file(MAP)
	var mercs: Array[Dictionary] = []
	for i in SQUAD:
		var slot := i + 1
		mercs.append({"slot": slot, "stats": c.slot_stats(slot), "gear": c.gear_of(slot), "pos": map.player_spawns[i]})
	var enemies: Array[Dictionary] = [
		{"kind": "conscript", "hollow": false, "role": "guard", "pos": Vector2i(16, 3)},
		{"kind": "conscript", "hollow": false, "role": "patrol", "pos": Vector2i(16, 12)},
		{"kind": "regular", "hollow": false, "role": "sentry", "pos": Vector2i(18, 7)},
		{"kind": "regular", "hollow": false, "role": "guard", "pos": Vector2i(14, 7)},
	]
	return {"mercs": mercs, "enemies": enemies, "ruleset": "initiative"}


## Every enemy you can place: [{key, label, stats, id_base, single}] (tiers, then the Writ, then the Provost).
static func enemy_kinds(story: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var tiers: Dictionary = story["enemy_tiers"]["tiers"]
	for key in tiers:
		var def: Dictionary = tiers[key]
		if def.has("stats"):
			out.append({"key": key, "label": def["name"], "stats": def["stats"], "id_base": int(def["id_base"]), "single": false})
	for o: Dictionary in story["writ"]["officers"]:
		out.append({"key": "officer_%d" % int(o["slot"]), "label": "%s (Writ)" % o["callsign"], "stats": o["stats"], "id_base": Campaign.WRIT_ID_BASE + int(o["slot"]), "single": true})
	out.append({"key": "provost", "label": "Provost Orrick", "stats": story["writ"]["provost"]["stats"], "id_base": Campaign.PROVOST_ID, "single": true})
	return out


static func kind_def(story: Dictionary, key: String) -> Dictionary:
	for k in enemy_kinds(story):
		if k["key"] == key:
			return k
	return {}


# --- editing (each returns a changed copy) ----------------------------------------------

static func with_stat(cfg: Dictionary, index: int, key: String, delta: int) -> Dictionary:
	var out := cfg.duplicate(true)
	var range_: Array = STAT_RANGE[key]
	var stats: Dictionary = out["mercs"][index]["stats"]
	stats[key] = clampi(int(stats[key]) + delta, int(range_[0]), int(range_[1]))
	return out


static func with_gear(cfg: Dictionary, index: int, slot: String, item_id: String) -> Dictionary:
	var out := cfg.duplicate(true)
	out["mercs"][index]["gear"][slot] = item_id
	return out


static func with_merc_pos(cfg: Dictionary, index: int, tile: Vector2i) -> Dictionary:
	var out := cfg.duplicate(true)
	out["mercs"][index]["pos"] = tile
	return out


static func with_enemy(cfg: Dictionary, enemy: Dictionary) -> Dictionary:
	var out := cfg.duplicate(true)
	out["enemies"].append(enemy)
	return out


static func without_enemy_at(cfg: Dictionary, tile: Vector2i) -> Dictionary:
	var out := cfg.duplicate(true)
	var kept: Array[Dictionary] = []
	for e: Dictionary in out["enemies"]:
		if e["pos"] != tile:
			kept.append(e)
	out["enemies"] = kept
	return out


static func without_enemies(cfg: Dictionary) -> Dictionary:
	var out := cfg.duplicate(true)
	out["enemies"] = [] as Array[Dictionary]
	return out


static func with_ruleset(cfg: Dictionary, ruleset: String) -> Dictionary:
	var out := cfg.duplicate(true)
	out["ruleset"] = ruleset
	return out


static func merc_at(cfg: Dictionary, tile: Vector2i) -> int:
	for i in cfg["mercs"].size():
		if cfg["mercs"][i]["pos"] == tile:
			return i
	return -1


static func enemy_at(cfg: Dictionary, tile: Vector2i) -> int:
	for i in cfg["enemies"].size():
		if cfg["enemies"][i]["pos"] == tile:
			return i
	return -1


## Why `tile` cannot take a new enemy of `key` ("" = fine).
static func placement_problem(story: Dictionary, cfg: Dictionary, map: MapData, tile: Vector2i, key: String) -> String:
	var state := map.build_state()
	if not state.grid.in_bounds(tile) or state.grid.is_blocked(tile):
		return "That tile is blocked."
	if merc_at(cfg, tile) >= 0 or enemy_at(cfg, tile) >= 0:
		return "Someone is already there."
	if cfg["enemies"].size() >= MAX_ENEMIES:
		return "At most %d enemies." % MAX_ENEMIES
	if tile.x <= PLAYER_ZONE_X:
		return "Too close to the squad's start."
	if SINGLE_KINDS.has(key):
		for e: Dictionary in cfg["enemies"]:
			if e["kind"] == key:
				return "Only one of those."
	return ""


static func merc_move_problem(cfg: Dictionary, map: MapData, tile: Vector2i) -> String:
	var state := map.build_state()
	if not state.grid.in_bounds(tile) or state.grid.is_blocked(tile):
		return "That tile is blocked."
	if tile.x > PLAYER_ZONE_X:
		return "The squad starts in the west (columns 0-%d)." % PLAYER_ZONE_X
	if merc_at(cfg, tile) >= 0:
		return "Someone is already there."
	return ""


static func problem(cfg: Dictionary) -> String:
	if cfg["enemies"].is_empty():
		return "Place at least one enemy."
	return ""


# --- building the match ---------------------------------------------------------------------

## A SimMatch for the config: the merc stats are the base, gear is folded on top.
static func build(story: Dictionary, cfg: Dictionary) -> SimMatch:
	var map := MapData.load_file(MAP)
	var state := map.build_state()
	state.seed = 20260101
	var items := {}
	for it: Dictionary in story["items"]["items"]:
		items[it["id"]] = it
	for m: Dictionary in cfg["mercs"]:
		var s: Dictionary = m["stats"]
		var u := SimUnit.make(int(m["slot"]), 0, m["pos"], int(s["hp"]), int(s["speed"]), int(s["aim"]), int(s["cqb"]))
		u.morale = int(s["morale"])
		u.sight_range = int(s["sight"])
		for slot in Campaign.GEAR_SLOTS:
			Campaign.apply_item(u, items.get(m["gear"][slot], {}))
		state.add_unit(u)
	var assignments := {}
	var used := {}
	var percent := int(story["world"]["hollowing"]["drone_percent"])
	var hollow_offset := int(story["enemy_tiers"]["hollow"]["id_base_offset"])
	for e: Dictionary in cfg["enemies"]:
		var kind := kind_def(story, e["kind"])
		var stats := {}
		for key in kind["stats"]:
			stats[key] = int(kind["stats"][key])
		var hollow: bool = e["hollow"]
		if hollow:
			stats = Campaign.drone_stats(stats, percent)
		var id: int = int(kind["id_base"]) + (hollow_offset if hollow and not kind["single"] else 0)
		while used.has(id):
			id += 1
		used[id] = true
		var u := SimUnit.make(id, 1, e["pos"], int(stats["hp"]), int(stats["speed"]), int(stats["aim"]), int(stats["cqb"]))
		u.morale = int(stats["morale"])
		u.sight_range = int(stats["sight"])
		u.is_drone = hollow
		if e["role"] == "sentry":
			u.watch_dir = SENTRY_FACING
		state.add_unit(u)
		assignments[id] = MissionBuilder.ROLE_PROFILES[e["role"]]
	var profiles: Dictionary = SimAIProfile.load_file(SimMatch.PROFILE_FILE)["profiles"]
	var built := SimMatch.new(state, 0, profiles, assignments)
	built.theme = map.theme
	return built


## Just the terrain and the units, for the setup screen's board.
static func preview_state(story: Dictionary, cfg: Dictionary) -> SimState:
	return build(story, cfg).state
