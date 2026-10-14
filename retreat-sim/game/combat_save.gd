class_name CombatSave
extends RefCounted
## Saving and resuming an activation encounter. A save holds the round, the queue, who is active,
## every unit, AP, status and overwatch, the goal's progress, waiting reinforcements and the dice
## seed and clock, so the rest of the fight replays exactly as it would have. The map is not
## saved: the caller rebuilds the grid (and the goal) from the mission or sandbox and passes them
## in. History (the event log and AP ledger) is not saved; it is diagnostic, not rules state.
##
## Versioned: a save with another VERSION, a different map size, or a state that breaks an
## invariant is refused (from_dict returns null) and the encounter must be restarted instead.
## Saves are written to a throwaway file; nothing in the campaign save refers to them.

const VERSION := 1


static func to_dict(cs: CombatState) -> Dictionary:
	var ids: Array = cs.sim.units.keys()
	ids.sort()
	var units: Array[Dictionary] = []
	for id in ids:
		units.append((cs.sim.units[id] as SimUnit).to_dict())
	var waiting: Array[Dictionary] = []
	for r in cs.reinforcements:
		waiting.append({"round": int(r["round"]), "unit": (r["unit"] as SimUnit).to_dict()})
	var assign: Array = []
	for id in cs.assignments:
		assign.append([int(id), String(cs.assignments[id])])
	return {"version": VERSION, "grid": [cs.sim.grid.width, cs.sim.grid.height], "seed": cs.sim.seed, "fixed_roll": cs.sim.fixed_roll,
		"units": units, "player_team": cs.player_team, "ai_team": cs.ai_team, "phase": int(cs.phase), "round_no": cs.round_no,
		"active_id": cs.active_id, "winner": cs.winner, "clock": cs.clock, "order": cs.order.duplicate(true), "queue": cs.queue.duplicate(),
		"activations": _pairs(cs.activations), "ap": _pairs(cs.ap), "overwatch": _tile_pairs(cs.overwatch),
		"suppressed": _keys(cs.suppressed), "broken": _keys(cs.broken), "fired": _keys(cs.fired),
		"max_ap": cs.config.max_ap, "overwatch_cost": cs.config.overwatch_cost, "objective": [cs.objective.x, cs.objective.y],
		"assignments": assign, "goal": cs.goal.progress() if cs.goal != null else {}, "reinforcements": waiting, "notices": cs.notices.duplicate()}


## Rebuilds the encounter. `grid` is the map's grid and `goal` the mission's fresh goal (or null).
## Returns null (and says why in the error log) if the save cannot be trusted.
static func from_dict(d: Dictionary, grid: SimGrid, goal: SimGoal = null) -> CombatState:
	if int(d.get("version", -1)) != VERSION:
		push_error("CombatSave: unsupported version %s (need %d); restart the encounter" % [d.get("version"), VERSION])
		return null
	var size: Array = d.get("grid", [])
	if size.size() != 2 or int(size[0]) != grid.width or int(size[1]) != grid.height:
		push_error("CombatSave: the save is for a %s map, not %dx%d" % [size, grid.width, grid.height])
		return null
	var sim := SimState.new(grid)
	sim.seed = int(d["seed"])
	sim.fixed_roll = int(d["fixed_roll"])
	for ud: Dictionary in d["units"]:
		sim.add_unit(SimUnit.from_dict(ud))
	var config := CombatConfig.new()
	config.max_ap = int(d["max_ap"])
	config.overwatch_cost = int(d["overwatch_cost"])
	var cs := CombatState.create(sim, config)
	cs.player_team = int(d["player_team"])
	cs.ai_team = int(d["ai_team"])
	cs.phase = int(d["phase"]) as CombatState.Phase
	cs.round_no = int(d["round_no"])
	sim.turn = cs.round_no
	cs.active_id = int(d["active_id"])
	cs.winner = int(d["winner"])
	cs.clock = int(d["clock"])
	for e: Dictionary in d["order"]:
		cs.order.append({"id": int(e["id"]), "initiative": int(e["initiative"]), "tie": int(e["tie"])})
	for id in d["queue"]:
		cs.queue.append(int(id))
	for p: Array in d["activations"]:
		cs.activations[int(p[0])] = int(p[1])
	for p: Array in d["ap"]:
		cs.ap[int(p[0])] = int(p[1])
	for p: Array in d["overwatch"]:
		cs.overwatch[int(p[0])] = Vector2i(int(p[1]), int(p[2]))
	for id in d["suppressed"]:
		cs.suppressed[int(id)] = true
	for id in d["broken"]:
		cs.broken[int(id)] = true
	for id in d["fired"]:
		cs.fired[int(id)] = true
	var obj: Array = d["objective"]
	cs.objective = Vector2i(int(obj[0]), int(obj[1]))
	for p: Array in d["assignments"]:
		cs.assignments[int(p[0])] = String(p[1])
	cs.profiles = SimAIProfile.load_file(SimMatch.PROFILE_FILE)["profiles"]
	cs.goal = goal
	if goal != null:
		goal.restore_progress(d["goal"])
	for r: Dictionary in d["reinforcements"]:
		cs.reinforcements.append({"round": int(r["round"]), "unit": SimUnit.from_dict(r["unit"])})
	for n in d["notices"]:
		cs.notices.append(String(n))
	var problems := CombatInvariants.check(cs)
	if not problems.is_empty():
		push_error("CombatSave: the save breaks the rules (%s); restart the encounter" % problems[0])
		return null
	return cs


## The save as JSON text, and back (what goes to disk).
static func to_json(cs: CombatState) -> String:
	return JSON.stringify(to_dict(cs))


static func from_json(text: String, grid: SimGrid, goal: SimGoal = null) -> CombatState:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("CombatSave: the save is not valid JSON; restart the encounter")
		return null
	return from_dict(parsed, grid, goal)


static func save_file(cs: CombatState, path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("CombatSave: cannot write %s (error %d)" % [path, FileAccess.get_open_error()])
		return false
	f.store_string(to_json(cs))
	return true


static func load_file(path: String, grid: SimGrid, goal: SimGoal = null) -> CombatState:
	if not FileAccess.file_exists(path):
		return null
	return from_json(FileAccess.get_file_as_string(path), grid, goal)


static func _pairs(d: Dictionary) -> Array:
	var keys: Array = d.keys()
	keys.sort()
	return keys.map(func(k: Variant) -> Array: return [int(k), int(d[k])])


static func _tile_pairs(d: Dictionary) -> Array:
	var keys: Array = d.keys()
	keys.sort()
	return keys.map(func(k: Variant) -> Array: return [int(k), (d[k] as Vector2i).x, (d[k] as Vector2i).y])


static func _keys(d: Dictionary) -> Array:
	var keys: Array = d.keys()
	keys.sort()
	return keys
