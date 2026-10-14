class_name ActivationAI
extends RefCounted
## Drives one side's activations through the shared resolver, one legal action at a time.
## It reuses SimAI's utility plan (fog view only) as a source of intent. Before each step it
## asks ActionResolver.problem() whether the step is still legal given what the team knows
## now; a stale step (a unit came into view, a target died) is dropped and the unit replans
## instead of submitting a refusal. Hard caps and a guaranteed END_TURN mean an activation
## can never spin. An overwatch order arms the unit, which then holds (ends its activation).
##
## Diagnostics: counters for the soak, an oscillation detector, and (with keep_log) a decision
## log: one row per plan, step, drop and end, with the planner's scores and reason.

const MAX_REPLANS := 3
const MAX_ACTIONS := 40
const TRAIL := 4  ## end-of-activation tiles remembered per unit, to spot A-B-A-B shuffling

var team := 1
## A stand-in human for the soak: with this on, the objective is the nearest living enemy (it knows
## where to go). Never on for the AI under test.
var scout := false
var keep_log := false
var log: Array[Dictionary] = []

var rejected := 0  ## actions the resolver refused after the legality check: must stay zero
var rejections: Array[Dictionary] = []  ## what was refused and why: {unit, round, type, reason}
var dropped := 0   ## stale plan steps dropped before submission (not errors)
var activations := 0
var idle_activations := 0       ## ended with no action at all
var idle_with_target := 0       ## ...while an enemy was visible and in weapon range
var cap_hits := 0               ## ended because MAX_ACTIONS or MAX_REPLANS ran out
var oscillations := 0           ## A-B-A-B end-of-activation shuffles with an enemy in view
var plans := 0
var plan_usec: Array[int] = []  ## time of each SimAI plan, microseconds

var _unit := -1
var _round := -1
var _replans := 0
var _actions := 0
var _pending: Array = []
var _intent: Dictionary = {}
var _trails: Dictionary = {}  # unit id -> Array[Vector2i]


func _init(p_team: int = 1, p_keep_log: bool = false) -> void:
	team = p_team
	keep_log = p_keep_log


## The next command for the active unit of `cs`. Always returns something legal to submit.
func next_action(cs: CombatState) -> CombatAction:
	var id := cs.active_id
	if id != _unit or cs.round_no != _round:
		_begin_activation(cs, id)
	if cs.overwatch.has(id):
		return _end(cs, id, "armed")
	if _actions >= MAX_ACTIONS:
		cap_hits += 1
		return _end(cs, id, "action_cap")
	while true:
		if _pending.is_empty():
			if cs.ap_of(id) <= 0:
				return _end(cs, id, "no_ap")
			if _replans >= MAX_REPLANS:
				cap_hits += 1
				return _end(cs, id, "replan_cap")
			_pending = _plan(cs, id)
			_replans += 1
			if _pending.is_empty():
				return _end(cs, id, "no_plan")
		var candidate := _convert(cs, id, _pending.pop_front())
		if candidate == null:
			continue
		var why := ActionResolver.problem(cs, candidate)
		if why != "":
			dropped += 1
			_pending = []  # the plan is stale: think again with what we know now
			_note(cs, id, "drop", {"type": candidate.type, "reason": why})
			continue
		_actions += 1
		_note(cs, id, "act", {"type": candidate.type, "to": candidate.target_cell, "target": candidate.target_id, "ap": cs.ap_of(id)})
		return candidate
	return _end(cs, id, "unreachable")


## Tell the AI how its last command went. A refusal here is a bug (the legality check passed).
func report(action: CombatAction, result: ActionResult) -> void:
	if not result.success:
		rejected += 1
		rejections.append({"unit": action.actor_id, "round": _round, "type": action.type, "reason": result.reason})
		_pending = []


## p95 of the planning times in milliseconds (0 if nothing was planned).
func plan_ms_p95() -> float:
	if plan_usec.is_empty():
		return 0.0
	var sorted := plan_usec.duplicate()
	sorted.sort()
	return float(sorted[mini(sorted.size() - 1, int(ceil(sorted.size() * 0.95)) - 1)]) / 1000.0


# --- internals ----------------------------------------------------------------------------

func _begin_activation(cs: CombatState, id: int) -> void:
	_unit = id
	_round = cs.round_no
	_replans = 0
	_actions = 0
	_pending = []
	_intent = {}
	activations += 1


func _end(cs: CombatState, id: int, reason: String) -> CombatAction:
	if _actions == 0:
		idle_activations += 1
		if _target_in_range(cs, id):
			idle_with_target += 1
	_track_trail(cs, id)
	_note(cs, id, "end", {"reason": reason, "actions": _actions, "ap": cs.ap_of(id)})
	return CombatAction.end_turn(id)


## An enemy this unit can see and could shoot from where it stands.
func _target_in_range(cs: CombatState, id: int) -> bool:
	var u: SimUnit = cs.sim.units[id]
	for tid in SimVision.visible_unit_ids(cs.sim, team):
		var t: SimUnit = cs.sim.units[tid]
		if t.team != team and SimLos.chebyshev(u.pos, t.pos) <= u.max_range() and SimLos.can_shoot(cs.sim.grid, u.pos, t.pos):
			return true
	return false


## Counts a unit that keeps stepping between the same two tiles while an enemy is in view.
func _track_trail(cs: CombatState, id: int) -> void:
	var trail: Array = _trails.get(id, [])
	trail.append((cs.sim.units[id] as SimUnit).pos)
	if trail.size() > TRAIL:
		trail.pop_front()
	_trails[id] = trail
	if trail.size() == TRAIL and trail[0] == trail[2] and trail[1] == trail[3] and trail[0] != trail[1] and _any_visible_enemy(cs):
		oscillations += 1
		_note(cs, id, "oscillation", {"tiles": [trail[0], trail[1]]})


func _any_visible_enemy(cs: CombatState) -> bool:
	for tid in SimVision.visible_unit_ids(cs.sim, team):
		if (cs.sim.units[tid] as SimUnit).team != team:
			return true
	return false


func _convert(cs: CombatState, id: int, a: SimAction) -> CombatAction:
	var u: SimUnit = cs.sim.units[id]
	match a.type:
		SimConst.ACTION_MOVE:
			return CombatAction.move_to(id, u.pos + a.dir)
		SimConst.ACTION_SHOOT:
			return CombatAction.shoot(id, a.target_id)
		SimConst.ACTION_OVERWATCH:
			return CombatAction.overwatch(id, a.dir)
	return null


func _plan(cs: CombatState, id: int) -> Array:
	var live := {}
	for uid in cs.sim.units:
		var u: SimUnit = cs.sim.units[uid]
		if u.alive and u.team == team:
			live[uid] = {"free_at": u.available_ticks() - cs.ap_of(uid), "pos": u.pos}
	var diag := {}
	var started := Time.get_ticks_usec()
	var plan := SimAI.plan_for(cs.sim, team, cs.profiles, cs.assignments, _objective(cs, id), live, diag)
	plan_usec.append(Time.get_ticks_usec() - started)
	plans += 1
	_intent = diag.get(id, {})
	_note(cs, id, "plan", {"intent": _intent, "orders": (plan.orders.get(id, []) as Array).size(), "ap": cs.ap_of(id)})
	return (plan.orders.get(id, []) as Array).duplicate()


func _objective(cs: CombatState, id: int) -> Vector2i:
	if not scout:
		return cs.objective_for(team)
	var u: SimUnit = cs.sim.units[id]
	var best := cs.objective_for(team)
	var best_d := 1 << 20
	for oid in cs.sim.units:
		var o: SimUnit = cs.sim.units[oid]
		if o.alive and o.team != team and SimLos.chebyshev(u.pos, o.pos) < best_d:
			best_d = SimLos.chebyshev(u.pos, o.pos)
			best = o.pos
	return best


func _note(cs: CombatState, id: int, kind: String, data: Dictionary) -> void:
	if not keep_log:
		return
	var row := {"round": cs.round_no, "unit": id, "kind": kind}
	row.merge(data)
	log.append(row)
