class_name ReplayModel
extends RefCounted
## Rebuilds the board at any tick from the sim's event log. Read-only: it
## never calls the resolver itself, so the view shows exactly what the sim
## reported. Tick 0 is the starting position; tick 12 is the final state.

var start: SimState
var plan: SimPlan
var result: SimResult

const NEVER := 1 << 30  # "no such event" sentinel for _first_tick


func _init(p_start: SimState, p_plan: SimPlan, p_result: SimResult) -> void:
	start = p_start
	plan = p_plan
	result = p_result


func state_at(tick: int) -> SimState:
	var s := start.clone()
	for ev in result.events:
		if ev["tick"] > tick:
			break
		match ev["type"]:
			"move":
				(s.units[ev["unit"]] as SimUnit).pos = ev["to"]
			"shot":
				if ev["result"] == "hit":
					(s.units[ev["target"]] as SimUnit).hp -= int(ev["damage"])
			"death":
				(s.units[ev["unit"]] as SimUnit).alive = false
	return s


func events_at(tick: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for ev in result.events:
		if ev["tick"] == tick and ev["type"] != "turn_end":
			out.append(ev)
	return out


## What `team` can see at `tick`: {"tiles": Dictionary, "units": Dictionary}.
## Visibility is the union of the start and end of the tick, so a unit that
## dies (or a squad wiped out) this tick is still shown dying.
func fog_at(team: int, tick: int) -> Dictionary:
	return SimVision.fog_between(state_at(maxi(tick - 1, 0)), state_at(tick), team)


## An event is shown under fog if any participant (or the tiles of a move)
## is visible to the viewing team.
static func event_visible(ev: Dictionary, fog: Dictionary) -> bool:
	var tiles: Dictionary = fog["tiles"]
	var units: Dictionary = fog["units"]
	match ev["type"]:
		"move":
			return tiles.has(ev["from"]) or tiles.has(ev["to"])
		"move_blocked":
			return tiles.has(ev["at"]) or tiles.has(ev["to"])
		"shot":
			return units.has(ev["unit"]) or units.has(ev["target"])
	return units.has(ev["unit"])


## Overwatch windows active on `tick`, derived from the plan's timeline.
## Each entry: {id, dir, spent}. Dead or halted units are omitted.
func watchers_at(tick: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids := plan.orders.keys()
	ids.sort()
	for id: int in ids:
		var u: SimUnit = start.units.get(id)
		if u == null or _first_tick(id, "plan_rejected", "unit") < NEVER:
			continue
		var t := 1
		for a: SimAction in plan.orders[id]:
			var win_start := t
			var win_end := t + a.cost(u) - 1
			t = win_end + 1
			if win_end > u.available_ticks():
				break  # the resolver drops this action and everything after it
			if a.type != SimConst.ACTION_OVERWATCH or tick < win_start or tick > win_end:
				continue
			if _first_tick(id, "death", "unit") <= tick or _first_tick(id, "move_blocked", "unit") < win_start:
				continue
			if _first_tick(id, "morale", "unit") <= tick:
				continue  # hit: steady units lose their watch, broken ones all orders
			out.append({"id": id, "dir": a.dir, "spent": _fired_between(id, win_start, mini(tick, win_end))})
	return out


func _first_tick(unit_id: int, type: String, key: String) -> int:
	for ev in result.events:
		if ev["type"] == type and ev[key] == unit_id:
			return ev["tick"]
	return NEVER


func _fired_between(unit_id: int, from_tick: int, to_tick: int) -> bool:
	for ev in result.events:
		if ev["type"] == "shot" and ev["unit"] == unit_id and ev.get("overwatch", false) \
				and ev["result"] != "invalid" and ev["tick"] >= from_tick and ev["tick"] <= to_tick:
			return true
	return false


static func _who(id: int, fog: Dictionary, namer: Callable = Callable()) -> String:
	if fog.is_empty() or (fog["units"] as Dictionary).has(id):
		return namer.call(id) if namer.is_valid() else "u%d" % id
	return "unseen unit"


static func _where(t: Vector2i, fog: Dictionary) -> String:
	if fog.is_empty() or (fog["tiles"] as Dictionary).has(t):
		return str(t)
	return "?"


## Human-readable event text. With a fog dict, hidden unit ids and tiles
## are redacted so the log never leaks what the viewing team cannot see.
## `namer` (optional): id -> display name, e.g. callsigns in the campaign.
static func describe(ev: Dictionary, fog: Dictionary = {}, namer: Callable = Callable()) -> String:
	match ev["type"]:
		"move":
			return "%s moves %s -> %s" % [_who(ev["unit"], fog, namer), _where(ev["from"], fog), _where(ev["to"], fog)]
		"move_blocked":
			return "%s blocked (%s) at %s" % [_who(ev["unit"], fog, namer), ev["reason"], _where(ev["at"], fog)]
		"shot":
			var tag := " [overwatch]" if ev.get("overwatch", false) else ""
			var tail := ""
			if ev["result"] == "hit":
				tail = " for %d" % ev["damage"]
			elif ev["result"] == "invalid":
				tail = " (%s)" % ev["reason"]
			return "%s shoots %s: %s%s%s" % [_who(ev["unit"], fog, namer), _who(ev["target"], fog, namer), ev["result"], tail, tag]
		"death":
			return "%s dies (killed by %s)" % [_who(ev["unit"], fog, namer), _who(ev["killer"], fog, namer)]
		"cancelled":
			return "%s shot cancelled (%s)" % [_who(ev["unit"], fog, namer), ev["reason"]]
		"morale":
			# The roll and the target number stay hidden: morale is not shown to the player.
			var outcome := "steady: keeps moving, can't shoot" if ev["result"] == "steady" else "broken: stops"
			return "%s hit, %s" % [_who(ev["unit"], fog, namer), outcome]
		"plan_rejected":
			return "orders for %s rejected (%s)" % [_who(ev["unit"], fog, namer), ev["reason"]]
	return str(ev)
