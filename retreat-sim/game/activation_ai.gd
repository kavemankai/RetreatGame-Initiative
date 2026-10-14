class_name ActivationAI
extends RefCounted
## Drives the enemy's activations through the shared resolver, one legal action at a time.
## It reuses SimAI's utility plan (fog view only) as a source of intent. Before each step it
## asks ActionResolver.problem() whether the step is still legal given what the team knows
## now; a stale step (a merc came into view, a target died) is dropped and the unit replans
## instead of submitting a refusal. Hard caps and a guaranteed END_TURN mean an activation
## can never spin. Overwatch orders are skipped until reactions exist (phase 4 of the plan).

const MAX_REPLANS := 3
const MAX_ACTIONS := 40

var rejected := 0  ## actions the resolver refused after the legality check: must stay zero
var rejections: Array[Dictionary] = []  ## what was refused and why: {unit, round, type, reason}
var dropped := 0   ## stale plan steps dropped before submission (not errors)

var _unit := -1
var _round := -1
var _replans := 0
var _actions := 0
var _pending: Array = []


## The next command for the active unit of `cs`. Always returns something legal to submit.
func next_action(cs: CombatState) -> CombatAction:
	var id := cs.active_id
	if id != _unit or cs.round_no != _round:
		_unit = id
		_round = cs.round_no
		_replans = 0
		_actions = 0
		_pending = []
	if _actions >= MAX_ACTIONS:
		return CombatAction.end_turn(id)
	while true:
		if _pending.is_empty():
			if _replans >= MAX_REPLANS or cs.ap_of(id) <= 0:
				return CombatAction.end_turn(id)
			_pending = _plan(cs, id)
			_replans += 1
			if _pending.is_empty():
				return CombatAction.end_turn(id)
		var candidate := _convert(cs, id, _pending.pop_front())
		if candidate == null:
			continue
		if ActionResolver.problem(cs, candidate) != "":
			dropped += 1
			_pending = []  # the plan is stale: think again with what we know now
			continue
		_actions += 1
		return candidate
	return CombatAction.end_turn(id)


## Tell the AI how its last command went. A refusal here is a bug (the legality check passed).
func report(action: CombatAction, result: ActionResult) -> void:
	if not result.success:
		rejected += 1
		rejections.append({"unit": action.actor_id, "round": _round, "type": action.type, "reason": result.reason})
		_pending = []


func _convert(cs: CombatState, id: int, a: SimAction) -> CombatAction:
	var u: SimUnit = cs.sim.units[id]
	match a.type:
		SimConst.ACTION_MOVE:
			return CombatAction.move_to(id, u.pos + a.dir)
		SimConst.ACTION_SHOOT:
			return CombatAction.shoot(id, a.target_id)
	return null


func _plan(cs: CombatState, id: int) -> Array:
	var live := {}
	for uid in cs.sim.units:
		var u: SimUnit = cs.sim.units[uid]
		if u.alive and u.team == cs.ai_team:
			live[uid] = {"free_at": u.available_ticks() - cs.ap_of(uid), "pos": u.pos}
	var plan := SimAI.plan_for(cs.sim, cs.ai_team, cs.profiles, cs.assignments, cs.objective, live)
	return (plan.orders.get(id, []) as Array).duplicate()
