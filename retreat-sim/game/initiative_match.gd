class_name InitiativeMatch
extends RefCounted
## The initiative ruleset, a second way to play the same missions (Jagged Alliance style).
##
## - Turns are side by side: your whole squad acts, then the enemy's, then the round ends.
## - Each merc has action points (AP) each turn: the same tick costs as the planned mode (a
##   straight step 2, a diagonal 3, a shot 4), out of AP_PER_TURN. You act live, one merc at
##   a time, in any order, and each action happens now.
## - INTERRUPTS: when a unit of the waiting side first gets a clear shot at a mover (it could
##   not see it a step earlier), it may fire at once if its initiative is at least the
##   mover's. The mover stops where it is. Each defender gets one reaction shot per turn
##   (its reaction AP is a single shot) and one interrupt per mover.
## - OVERWATCH: a unit that holds a watch (costs all its AP) shoots the first enemy to move
##   inside its cone and in line of sight, whatever its initiative.
## - Shots, cover, hit chances, morale and gear use the same rules and dice as the planned mode.
##
## Every action returns "beats": [{"events": Array[Dictionary], "state": SimState}], one per
## step or shot, so a screen can play them back in order. The enemy's whole turn comes back
## the same way from end_turn().

const NO_WINNER := SimMatch.NO_WINNER
const DRAW := SimMatch.DRAW
const MAX_REPLANS := 2

var state: SimState
var player_team := 0
var ai_team := 1
var profiles: Dictionary
var assignments: Dictionary
var objective: Vector2i
var turn := 1
var active_team := 0
var winner := NO_WINNER
var theme := "station_deck"
var goal: SimGoal
var reinforcements: Array[Dictionary] = []
var notices: Array[String] = []
var ap: Dictionary = {}        # unit id -> action points left this turn (active side only)
var reaction: Dictionary = {}  # unit id -> reaction AP for the waiting side (one shot)
var watch: Dictionary = {}     # unit id -> facing of its overwatch

var _suppressed := {}  # steady after a hit: no shooting until its side's next turn
var _broken := {}      # broken after a hit: no AP until its side's next turn
var _reacted := {}     # "defender:mover" -> true, one interrupt per pair per turn
var _fired := {}       # unit id -> true once it has shot this turn (the opener trait)
var _clock := 0


func _init(p_state: SimState, p_profiles: Dictionary = {}, p_assignments: Dictionary = {}, p_objective: Vector2i = SimMatch.AI_OBJECTIVE) -> void:
	state = p_state
	profiles = p_profiles
	assignments = p_assignments
	objective = p_objective


## The same mission as a planned-mode SimMatch: its units, goal, reinforcements and roles.
static func from_match(m: SimMatch) -> InitiativeMatch:
	var im := InitiativeMatch.new(m.state.clone(), m.profiles, m.assignments, m.objective)
	im.theme = m.theme
	im.goal = m.goal
	im.reinforcements = m.reinforcements.duplicate()
	return im


static func initiative(u: SimUnit) -> int:
	return u.speed * 10 + u.aim - 3 * int(u.counters.get("hits_taken", 0))


func start() -> void:
	for id in state.units:
		ap[id] = _pool(state.units[id])  # the enemy begins fresh, so it can react to your first moves
	_begin_turn(player_team)
	for id in state.units:
		var u: SimUnit = state.units[id]
		if u.alive and u.team == ai_team and u.watch_dir != Vector2i.ZERO:
			watch[id] = u.watch_dir  # sentries are already looking down their lane


func is_over() -> bool:
	return winner != NO_WINNER


func ap_of(id: int) -> int:
	return int(ap.get(id, 0))


func is_suppressed(id: int) -> bool:
	return _suppressed.has(id)


func is_broken(id: int) -> bool:
	return _broken.has(id)


func can_act(id: int) -> bool:
	var u: SimUnit = state.units.get(id)
	return not is_over() and u != null and u.alive and u.team == active_team


## Tiles this unit can reach with its AP, as {tile: cost}, on its own side's view (hidden
## enemies are invisible to it, so the map never leaks where they stand).
func reach(id: int) -> Dictionary:
	var u: SimUnit = state.units.get(id)
	if u == null or not can_act(id) or ap_of(id) <= 0:
		return {}
	var view := SimVision.view_for(state, u.team)
	return SimPathing.reach(view, u.pos, id, ap_of(id))["dist"]


## What shooting `target_id` would do: {"result", "chance", "damage", "cost"} or {"result": "invalid", "reason"}.
func shot_preview(id: int, target_id: int) -> Dictionary:
	var u: SimUnit = state.units.get(id)
	var t: SimUnit = state.units.get(target_id)
	if u == null or t == null or not t.alive or t.team == u.team:
		return {"result": "invalid", "reason": "no_target"}
	if not SimVision.visible_unit_ids(state, u.team).has(target_id):
		return {"result": "invalid", "reason": "not_visible"}
	var r := SimResolver.evaluate_shot(state.grid, u, u.pos, t, not _fired.has(id))
	r["cost"] = u.shot_ticks()
	return r


## The tiles the unit would walk to reach `tile` (origin first), for drawing a preview.
func path_preview(id: int, tile: Vector2i) -> Array[Vector2i]:
	var u: SimUnit = state.units.get(id)
	if u == null or not can_act(id):
		return []
	var r := SimPathing.reach(SimVision.view_for(state, u.team), u.pos, id, ap_of(id))
	return SimPathing.path_to(r, tile)


## The walk to `tile` step by step: [{"tile", "cost" (AP spent so far), "threats" (visible
## enemy ids that would interrupt on arriving here)}], origin excluded. Only enemies the
## mover's side can see are considered, so it never reveals hidden ones.
func route_preview(id: int, tile: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var u: SimUnit = state.units.get(id)
	var path := path_preview(id, tile)
	if u == null or path.size() < 2:
		return out
	var seen := SimVision.visible_unit_ids(state, u.team)
	var spent := 0
	for i in range(1, path.size()):
		spent += u.step_cost(path[i] - path[i - 1])
		var threats: Array[int] = []
		for eid in seen:
			var d: SimUnit = state.units[eid]
			if d.team != u.team and _would_interrupt(d, u, path[i - 1], path[i]):
				threats.append(eid)
		out.append({"tile": path[i], "cost": spent, "threats": threats})
	return out


## Would `d` get a shot at `mover` stepping from `from` to `to` (see _interrupts)?
func _would_interrupt(d: SimUnit, mover: SimUnit, from: Vector2i, to: Vector2i) -> bool:
	if not d.alive or _suppressed.has(d.id) or _broken.has(d.id) or not _can_fire(d, to):
		return false
	if watch.has(d.id):
		return SimLos.in_cone(d.pos, watch[d.id], to)
	if _reacted.has("%d:%d" % [d.id, mover.id]) or int(reaction.get(d.id, 0)) < d.shot_ticks():
		return false
	return not _can_fire(d, from) and initiative(d) >= initiative(mover)


func move(id: int, tile: Vector2i) -> Array[Dictionary]:
	var beats: Array[Dictionary] = []
	if not can_act(id) or _broken.has(id) or ap_of(id) <= 0:
		return beats
	var u: SimUnit = state.units[id]
	var r := SimPathing.reach(SimVision.view_for(state, u.team), u.pos, id, ap_of(id))
	if tile == u.pos or not (r["dist"] as Dictionary).has(tile):
		return beats
	var path := SimPathing.path_to(r, tile)
	for i in range(1, path.size()):
		if _step_to(u, path[i], beats):
			break
	return beats


func shoot(id: int, target_id: int) -> Array[Dictionary]:
	var beats: Array[Dictionary] = []
	if not can_act(id) or _suppressed.has(id) or _broken.has(id):
		return beats
	var pv := shot_preview(id, target_id)
	if pv["result"] == "invalid" or ap_of(id) < int(pv["cost"]):
		return beats
	var u: SimUnit = state.units[id]
	ap[id] = ap_of(id) - int(pv["cost"])
	beats.append(_beat(_fire(u, target_id)))
	_check_winner()
	return beats


## Hold a watch facing `dir`: costs all remaining AP and lasts until this side's next turn.
func hold_watch(id: int, dir: Vector2i) -> Array[Dictionary]:
	var beats: Array[Dictionary] = []
	if not can_act(id) or ap_of(id) <= 0 or _suppressed.has(id) or _broken.has(id) or dir == Vector2i.ZERO:
		return beats
	watch[id] = dir
	ap[id] = 0
	beats.append(_beat([{"type": "watch", "tick": _next_tick(), "unit": id, "dir": dir}]))
	return beats


## Ends the player's turn, plays the enemy's, closes the round and opens the next one.
func end_turn() -> Array[Dictionary]:
	var beats: Array[Dictionary] = []
	if is_over() or active_team != player_team:
		return beats
	_begin_turn(ai_team)
	beats.append_array(_run_ai_turn())
	if is_over():
		return beats
	notices.clear()
	if goal != null:
		notices.append_array(goal.round_end(state, player_team))
	_check_winner()
	if is_over():
		return beats
	turn += 1
	_begin_turn(player_team)
	return beats


# --- internals ----------------------------------------------------------------------

func _next_tick() -> int:
	_clock += 1
	return _clock


func _beat(evs: Array) -> Dictionary:
	var typed: Array[Dictionary] = []
	for e in evs:
		typed.append(e)
	return {"events": typed, "state": state.clone()}


## A unit's AP pool for a turn: the standard pool less stress (drones ignore stress).
func _pool(u: SimUnit) -> int:
	return SimConst.AP_PER_TURN if u.is_drone else maxi(0, SimConst.AP_PER_TURN - u.stress_penalty)


func _begin_turn(team: int) -> void:
	active_team = team
	_reacted.clear()
	_fired.clear()
	if team == player_team:
		_spawn_reinforcements()
	for id in state.units:
		var u: SimUnit = state.units[id]
		if not u.alive:
			continue
		if u.team == team:
			ap[id] = _pool(u)
			_suppressed.erase(id)
			_broken.erase(id)
			watch.erase(id)
			reaction.erase(id)
		else:
			# A unit that spent itself dry on its own turn has nothing left to react with.
			reaction[id] = u.shot_ticks() if ap_of(id) >= u.shot_ticks() else 0
			ap[id] = 0


## One step of a path. Returns true if the unit must stop (blocked, interrupted, killed).
func _step_to(u: SimUnit, dest: Vector2i, beats: Array[Dictionary]) -> bool:
	var step := dest - u.pos
	var cost := u.step_cost(step)
	if cost > ap_of(u.id):
		return true
	if not state.grid.can_step(u.pos, dest) or state.unit_at(dest) != null:
		beats.append(_beat([{"type": "move_blocked", "tick": _next_tick(), "unit": u.id, "at": u.pos, "to": dest, "reason": "occupied"}]))
		return true
	var old := u.pos
	u.pos = dest
	ap[u.id] = ap_of(u.id) - cost
	u.bump("steps_moved")
	var evs: Array = [{"type": "move", "tick": _next_tick(), "unit": u.id, "from": old, "to": dest}]
	var stopped := _interrupts(u, old, evs)
	beats.append(_beat(evs))
	_check_winner()
	return stopped or not u.alive or is_over() or _broken.has(u.id)


func _can_fire(d: SimUnit, tile: Vector2i) -> bool:
	return d.alive and SimLos.chebyshev(d.pos, tile) <= mini(d.max_range(), d.sight_range) and SimLos.can_shoot(state.grid, d.pos, tile)


## The waiting side's reactions to `mover` having just stepped from `old_pos`. Appends the
## shot events to `evs`; returns true if any fired (an interrupt always halts the mover).
func _interrupts(mover: SimUnit, old_pos: Vector2i, evs: Array) -> bool:
	var cands: Array[SimUnit] = []
	var by_watch := {}
	for id in state.units:
		var d: SimUnit = state.units[id]
		if not d.alive or d.team == mover.team or _suppressed.has(id) or _broken.has(id):
			continue
		if watch.has(id):
			if SimLos.in_cone(d.pos, watch[id], mover.pos) and _can_fire(d, mover.pos):
				cands.append(d)
				by_watch[id] = true
			continue
		if _reacted.has("%d:%d" % [id, mover.id]) or int(reaction.get(id, 0)) < d.shot_ticks():
			continue
		if _can_fire(d, mover.pos) and not _can_fire(d, old_pos) and initiative(d) >= initiative(mover):
			cands.append(d)
	cands.sort_custom(func(a: SimUnit, b: SimUnit) -> bool:
		var ia := initiative(a)
		var ib := initiative(b)
		return ia > ib if ia != ib else a.id < b.id)
	var fired := false
	for d in cands:
		if not mover.alive or _suppressed.has(d.id) or _broken.has(d.id):
			continue
		_reacted["%d:%d" % [d.id, mover.id]] = true
		if by_watch.has(d.id):
			watch.erase(d.id)
		else:
			reaction[d.id] = int(reaction.get(d.id, 0)) - d.shot_ticks()
		evs.append_array(_fire(d, mover.id))
		fired = true
	return fired


## One shot, resolved now with the shared rules and dice (ShotResolver). Returns its events.
func _fire(shooter: SimUnit, target_id: int) -> Array:
	var opener_ready := not _fired.has(shooter.id)
	var out := ShotResolver.fire(state, shooter, target_id, turn, _next_tick(), opener_ready)
	_fired[shooter.id] = true
	for e: Dictionary in out:
		if e["type"] != "morale":
			continue
		if e["result"] == "steady":
			_suppressed[int(e["unit"])] = true
		else:
			_broken[int(e["unit"])] = true
			ap[int(e["unit"])] = 0
	return out


func _check_winner() -> void:
	winner = CombatState.winner_for(state, goal, player_team, ai_team)


func _spawn_reinforcements() -> void:
	var arrived := 0
	var rest: Array[Dictionary] = []
	for r in reinforcements:
		if int(r["round"]) > turn:
			rest.append(r)
			continue
		var u: SimUnit = r["unit"]
		u.pos = _free_tile_near(u.pos)
		state.add_unit(u)
		ap[u.id] = _pool(u)
		arrived += 1
	reinforcements = rest
	if arrived > 0:
		notices.append("Reinforcements arrive (%d)." % arrived)


func _free_tile_near(tile: Vector2i) -> Vector2i:
	for radius in 6:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var t := tile + Vector2i(dx, dy)
				if state.grid.in_bounds(t) and not state.grid.is_blocked(t) and state.unit_at(t) == null:
					return t
	return tile


# --- the enemy's turn -------------------------------------------------------------------

func _run_ai_turn() -> Array[Dictionary]:
	var beats: Array[Dictionary] = []
	var order: Array[int] = []
	for id in state.units:
		var u: SimUnit = state.units[id]
		if u.alive and u.team == ai_team:
			order.append(id)
	order.sort_custom(func(a: int, b: int) -> bool:
		var ia := initiative(state.units[a])
		var ib := initiative(state.units[b])
		return ia > ib if ia != ib else a < b)
	for id in order:
		var replans := 0
		while not is_over() and replans <= MAX_REPLANS:
			var u: SimUnit = state.units[id]
			if not u.alive or ap_of(id) <= 0 or _broken.has(id):
				break
			var actions := _plan_for(id)
			if actions.is_empty() or not _execute(id, actions, beats):
				break
			replans += 1  # something interrupted the plan: think again with what we now know
	return beats


func _plan_for(id: int) -> Array:
	var live := {}
	for uid in state.units:
		var u: SimUnit = state.units[uid]
		if u.alive and u.team == ai_team:
			live[uid] = {"free_at": u.available_ticks() - ap_of(uid), "pos": u.pos}
	var plan := SimAI.plan_for(state, ai_team, profiles, assignments, objective, live)
	return plan.orders.get(id, [])


## Plays one unit's planned actions. Returns true if the plan was cut short.
func _execute(id: int, actions: Array, beats: Array[Dictionary]) -> bool:
	var u: SimUnit = state.units[id]
	for a: SimAction in actions:
		match a.type:
			SimConst.ACTION_MOVE:
				if _step_to(u, u.pos + a.dir, beats):
					return true
			SimConst.ACTION_SHOOT:
				var cost := u.shot_ticks()
				if _suppressed.has(id) or ap_of(id) < cost or not shot_preview(id, a.target_id).get("result", "invalid") in ["hit", "blocked"]:
					continue
				ap[id] = ap_of(id) - cost
				beats.append(_beat(_fire(u, a.target_id)))
				_check_winner()
				if is_over() or not u.alive:
					return true
			SimConst.ACTION_OVERWATCH:
				if ap_of(id) > 0:
					watch[id] = a.dir
					ap[id] = 0
					beats.append(_beat([{"type": "watch", "tick": _next_tick(), "unit": id, "dir": a.dir}]))
	ap[id] = 0 if actions.is_empty() else ap_of(id)
	return false
