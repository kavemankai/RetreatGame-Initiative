class_name SimGoal
extends RefCounted
## A mission's objective, checked at the end of every round. Pure and
## deterministic: it reads the board and its own counters, nothing else.
##
## Types (the `goal` dictionary in data/maps/<mission>.json):
##   hold          a merc ends a round on `zone` while `clear` holds no enemy
##   collect       a merc ends a round on each of `caches`, then every living merc is in `exit`
##   survive       live through `rounds` rounds; each enemy on `watch` at a round's end adds `penalty`
##   reach_return  a merc ends a round in each of `steps`, in order
## With no goal the match is the plain rout (last side standing).

const ZONE_KEYS: Array[String] = ["zone", "clear", "exit", "watch"]

var goal_type := ""
var won := false
var rounds_done := 0
var penalty_total := 0
var collected: Array[String] = []  # cache names, in the order they were taken
var step := 0                       # reach_return: steps completed

var _goal: Dictionary
var _zones: Dictionary  # name -> Array[Vector2i]


func _init(goal: Dictionary, zones: Dictionary) -> void:
	_goal = goal
	_zones = zones
	goal_type = String(goal.get("type", ""))


## Call once when a round ends. Returns notes for the log. Does nothing once won.
func round_end(state: SimState, player_team: int) -> Array[String]:
	var notes: Array[String] = []
	if goal_type == "" or won:
		return notes
	rounds_done += 1
	match goal_type:
		"hold":
			won = _any_player_on(state, player_team, _tiles(_goal["zone"])) and _count_enemies(state, player_team, _tiles(_goal["clear"])) == 0
		"collect":
			for cache: String in _goal["caches"]:
				if not collected.has(cache) and _any_player_on(state, player_team, _tiles(cache)):
					collected.append(cache)
					notes.append("%s recovered (%d of %d)." % [cache.capitalize(), collected.size(), (_goal["caches"] as Array).size()])
			won = collected.size() == (_goal["caches"] as Array).size() and _all_players_in(state, player_team, _tiles(_goal["exit"]))
		"survive":
			var n := _count_enemies(state, player_team, _tiles(_goal["watch"]))
			if n > 0:
				penalty_total += n * int(_goal["penalty"])
				notes.append("%d enemies reached the berths: -%d people." % [n, n * int(_goal["penalty"])])
			won = rounds_done >= int(_goal["rounds"]) and _any_player_alive(state, player_team)
		"reach_return":
			var steps: Array = _goal["steps"]
			if step < steps.size() and _any_player_on(state, player_team, _tiles(steps[step])):
				step += 1
				notes.append("%s reached." % String(steps[step - 1]).capitalize())
			won = step >= steps.size()
	return notes


func progress_text() -> String:
	match goal_type:
		"hold":
			return "Hold %s with the %s clear." % [String(_goal["zone"]).capitalize(), String(_goal["clear"]).capitalize()]
		"collect":
			var total: int = (_goal["caches"] as Array).size()
			var tail := " Then everyone to the %s." % String(_goal["exit"]).capitalize() if collected.size() == total else ""
			return "Caches: %d of %d.%s" % [collected.size(), total, tail]
		"survive":
			return "Hold %d rounds: %d of %d done. Lost: %d." % [int(_goal["rounds"]), rounds_done, int(_goal["rounds"]), penalty_total]
		"reach_return":
			var steps: Array = _goal["steps"]
			return "Reach the %s." % String(steps[mini(step, steps.size() - 1)]).capitalize() if step < steps.size() else "Done."
	return ""


## Zones to highlight on the board: [{"tiles", "kind": "objective" | "exit"}].
func zone_marks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match goal_type:
		"hold":
			out.append({"tiles": _tiles(_goal["zone"]), "kind": "objective"})
		"collect":
			for cache: String in _goal["caches"]:
				if not collected.has(cache):
					out.append({"tiles": _tiles(cache), "kind": "objective"})
			out.append({"tiles": _tiles(_goal["exit"]), "kind": "exit"})
		"survive":
			out.append({"tiles": _tiles(_goal["watch"]), "kind": "objective"})
		"reach_return":
			var steps: Array = _goal["steps"]
			for i in steps.size():
				out.append({"tiles": _tiles(steps[i]), "kind": "objective" if i == step else "exit"})
	return out


## Every zone name a goal refers to (for validation).
static func zone_names(goal: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for key in ZONE_KEYS:
		if goal.has(key):
			out.append(String(goal[key]))
	for key in ["caches", "steps"]:
		for n in goal.get(key, []):
			out.append(String(n))
	return out


func _tiles(name: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for t in _zones.get(name, []):
		out.append(t)
	return out


func _any_player_on(state: SimState, team: int, tiles: Array[Vector2i]) -> bool:
	for id in state.units:
		var u: SimUnit = state.units[id]
		if u.alive and u.team == team and tiles.has(u.pos):
			return true
	return false


func _all_players_in(state: SimState, team: int, tiles: Array[Vector2i]) -> bool:
	var any := false
	for id in state.units:
		var u: SimUnit = state.units[id]
		if u.alive and u.team == team:
			any = true
			if not tiles.has(u.pos):
				return false
	return any


func _any_player_alive(state: SimState, team: int) -> bool:
	for id in state.units:
		var u: SimUnit = state.units[id]
		if u.alive and u.team == team:
			return true
	return false


func _count_enemies(state: SimState, team: int, tiles: Array[Vector2i]) -> int:
	var n := 0
	for id in state.units:
		var u: SimUnit = state.units[id]
		if u.alive and u.team != team and tiles.has(u.pos):
			n += 1
	return n
