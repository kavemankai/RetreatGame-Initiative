class_name ActionResolver
extends RefCounted
## The one place a CombatState changes. submit() validates a typed CombatAction against the
## active unit's AP, sight and the board, and only then resolves it, so a rejection leaves no
## trace. Every accepted action posts a ledger row (AP before, cost, AP after). problem() runs
## the same validation without changing anything, for previews and for the AI.
##
## Reasons a command is refused: encounter_over, not_ready, not_your_activation, dead_actor,
## broken, suppressed, no_target, not_visible, out_of_range, no_los, not_enough_ap,
## unreachable, invalid_direction, unknown_action.


static func submit(cs: CombatState, a: CombatAction) -> ActionResult:
	var why := problem(cs, a)
	if why != "":
		return ActionResult.rejected(why)
	var u: SimUnit = cs.sim.units[a.actor_id]
	match a.type:
		CombatAction.MOVE:
			return _move(cs, u, a)
		CombatAction.SHOOT:
			return _shoot(cs, u, a)
		CombatAction.OVERWATCH:
			return _overwatch(cs, u, a)
	return _end_turn(cs, u)


## Why `a` would be refused right now ("" if it would be accepted). Changes nothing.
static func problem(cs: CombatState, a: CombatAction) -> String:
	if cs.is_over():
		return "encounter_over"
	if cs.phase != CombatState.Phase.AWAIT_COMMAND:
		return "not_ready"
	if a.actor_id != cs.active_id:
		return "not_your_activation"
	var u: SimUnit = cs.sim.units.get(a.actor_id)
	if u == null or not u.alive:
		return "dead_actor"
	match a.type:
		CombatAction.MOVE:
			return _move_problem(cs, u, a)
		CombatAction.SHOOT:
			return _shoot_problem(cs, u, a)
		CombatAction.OVERWATCH:
			return _overwatch_problem(cs, u, a)
		CombatAction.END_TURN:
			return ""
	return "unknown_action"


## What shooting `target_id` would do for `id`: {"result", "chance", "damage", "cost"} or
## {"result": "invalid", "reason"}. Uses only what the shooter's side can see.
static func preview_shot(cs: CombatState, id: int, target_id: int) -> Dictionary:
	var u: SimUnit = cs.sim.units.get(id)
	var t: SimUnit = cs.sim.units.get(target_id)
	if u == null or t == null or not t.alive or t.team == u.team:
		return {"result": "invalid", "reason": "no_target"}
	if not SimVision.visible_unit_ids(cs.sim, u.team).has(target_id):
		return {"result": "invalid", "reason": "not_visible"}
	var r := SimResolver.evaluate_shot(cs.sim.grid, u, u.pos, t, not cs.fired.has(id))
	r["cost"] = u.shot_ticks()
	return r


## Tiles the active unit can reach with its AP, {tile: cost}, on its own side's view.
static func reach(cs: CombatState, id: int) -> Dictionary:
	var u: SimUnit = cs.sim.units.get(id)
	if u == null or id != cs.active_id or cs.ap_of(id) <= 0:
		return {}
	return SimPathing.reach(SimVision.view_for(cs.sim, u.team), u.pos, id, cs.ap_of(id))["dist"]


# --- validation ---------------------------------------------------------------------------

static func _status_problem(cs: CombatState, id: int, can_be_suppressed: bool) -> String:
	if cs.broken.has(id):
		return "broken"
	if can_be_suppressed and cs.suppressed.has(id):
		return "suppressed"
	return ""


static func _move_problem(cs: CombatState, u: SimUnit, a: CombatAction) -> String:
	var bad := _status_problem(cs, u.id, false)
	if bad != "":
		return bad
	if a.target_cell == u.pos:
		return "unreachable"
	var view := SimVision.view_for(cs.sim, u.team)
	var r := SimPathing.reach(view, u.pos, u.id, cs.ap_of(u.id))
	if (r["dist"] as Dictionary).has(a.target_cell):
		return ""
	var full := SimPathing.reach(view, u.pos, u.id, cs.config.max_ap)
	return "not_enough_ap" if (full["dist"] as Dictionary).has(a.target_cell) else "unreachable"


static func _shoot_problem(cs: CombatState, u: SimUnit, a: CombatAction) -> String:
	var bad := _status_problem(cs, u.id, true)
	if bad != "":
		return bad
	var pv := preview_shot(cs, u.id, a.target_id)
	if pv["result"] == "invalid":
		return String(pv["reason"])
	return "not_enough_ap" if cs.ap_of(u.id) < int(pv["cost"]) else ""


static func _overwatch_problem(cs: CombatState, u: SimUnit, a: CombatAction) -> String:
	if a.dir == Vector2i.ZERO:
		return "invalid_direction"
	var bad := _status_problem(cs, u.id, true)
	if bad != "":
		return bad
	return "not_enough_ap" if cs.ap_of(u.id) < cs.config.overwatch_cost else ""


# --- actions (each assumes problem() returned "") ----------------------------------------------

static func _move(cs: CombatState, u: SimUnit, a: CombatAction) -> ActionResult:
	var r := SimPathing.reach(SimVision.view_for(cs.sim, u.team), u.pos, u.id, cs.ap_of(u.id))
	var res := _begin(cs, u)
	# Revalidate every step against the live board, not just the preview.
	var path := SimPathing.path_to(r, a.target_cell)
	for i in range(1, path.size()):
		var dest := path[i]
		var cost := u.step_cost(dest - u.pos)
		if cost > cs.ap_of(u.id):
			break
		if not cs.sim.grid.can_step(u.pos, dest) or cs.sim.unit_at(dest) != null:
			_emit(cs, res, [{"type": "move_blocked", "tick": cs.next_tick(), "unit": u.id, "at": u.pos, "to": dest, "reason": "occupied"}])
			break
		var old := u.pos
		u.pos = dest
		_spend(cs, u, res, cost)
		u.bump("steps_moved")
		_emit(cs, res, [{"type": "move", "tick": cs.next_tick(), "unit": u.id, "from": old, "to": dest}])
		_react(cs, u, res)
		if not u.alive:
			break  # the rest of the path is cancelled; a broken mover has no AP left to continue
	return _finish(cs, u, a, res)


static func _shoot(cs: CombatState, u: SimUnit, a: CombatAction) -> ActionResult:
	var pv := preview_shot(cs, u.id, a.target_id)
	var res := _begin(cs, u)
	_spend(cs, u, res, int(pv["cost"]))
	var events := ShotResolver.fire(cs.sim, u, a.target_id, cs.round_no, cs.next_tick(), not cs.fired.has(u.id))
	cs.fired[u.id] = true
	for e: Dictionary in events:
		_apply_outcome(cs, e)
	_emit(cs, res, events)
	return _finish(cs, u, a, res)


static func _overwatch(cs: CombatState, u: SimUnit, a: CombatAction) -> ActionResult:
	var res := _begin(cs, u)
	_spend(cs, u, res, cs.config.overwatch_cost)
	cs.overwatch[u.id] = a.dir
	_emit(cs, res, [{"type": "watch", "tick": cs.next_tick(), "unit": u.id, "dir": a.dir}])
	return _finish(cs, u, a, res)


static func _end_turn(cs: CombatState, u: SimUnit) -> ActionResult:
	var res := _begin(cs, u)
	var forfeited := cs.ap_of(u.id)
	res.events.append({"type": "end_turn", "tick": cs.next_tick(), "unit": u.id, "forfeited": forfeited})
	_post(cs, u, CombatAction.END_TURN, res)
	cs.record(res.events)
	res.activation_ended = true
	ActivationScheduler.end_activation(cs)
	res.next_active = cs.active_id
	return res


# --- reactions ----------------------------------------------------------------------------

## Armed enemies of `mover` that would fire at it on `tile`: facing it (cone), in weapon range and
## sight, with a clear line, and neither shaken nor broken. Initiative order, then unit id.
static func watchers_covering(cs: CombatState, mover: SimUnit, tile: Vector2i) -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	for id in cs.overwatch:
		var d: SimUnit = cs.sim.units.get(id)
		if d == null or not d.alive or d.team == mover.team or cs.suppressed.has(id) or cs.broken.has(id):
			continue
		if SimLos.in_cone(d.pos, cs.overwatch[id], tile) and _can_fire(cs, d, tile):
			out.append(d)
	out.sort_custom(func(a: SimUnit, b: SimUnit) -> bool:
		var ia := ActivationScheduler.initiative_of(a)
		var ib := ActivationScheduler.initiative_of(b)
		return ia > ib if ia != ib else a.id < b.id)
	return out


static func _can_fire(cs: CombatState, d: SimUnit, tile: Vector2i) -> bool:
	return SimLos.chebyshev(d.pos, tile) <= mini(d.max_range(), d.sight_range) and SimLos.can_shoot(cs.sim.grid, d.pos, tile)


## One-shot overwatch: after the mover's step, each covering watcher fires once for free and its
## charge is spent. A reaction never triggers another (nothing listens to reaction shots).
static func _react(cs: CombatState, mover: SimUnit, res: ActionResult) -> void:
	for d in watchers_covering(cs, mover, mover.pos):
		if not mover.alive:
			return
		cs.overwatch.erase(d.id)
		var events := ShotResolver.fire(cs.sim, d, mover.id, cs.round_no, cs.next_tick(), not cs.fired.has(d.id), true)
		(events[0] as Dictionary)["reaction"] = true
		cs.fired[d.id] = true
		for e: Dictionary in events:
			_apply_outcome(cs, e)
		_emit(cs, res, events)


# --- bookkeeping --------------------------------------------------------------------------

static func _begin(cs: CombatState, u: SimUnit) -> ActionResult:
	var res := ActionResult.new()
	res.success = true
	res.ap_before = cs.ap_of(u.id)
	return res


## Adds events to the result and, for views, a playback beat with the board as it now stands.
static func _emit(cs: CombatState, res: ActionResult, events: Array) -> void:
	res.events.append_array(events)
	if cs.capture_beats:
		var typed: Array[Dictionary] = []
		for e: Dictionary in events:
			typed.append(e)
		res.beats.append({"events": typed, "state": cs.sim.clone()})


## Pays AP for the action. The ledger records what was paid, even if the unit is later killed
## (which zeroes its pool) before the action finishes.
static func _spend(cs: CombatState, u: SimUnit, res: ActionResult, amount: int) -> void:
	cs.ap[u.id] = cs.ap_of(u.id) - amount
	res.cost += amount


static func _post(cs: CombatState, u: SimUnit, type: String, res: ActionResult) -> void:
	res.ap_after = res.ap_before - res.cost
	cs.ledger.append({"seq": cs.ledger.size(), "round": cs.round_no, "actor": u.id, "type": type,
		"ap_before": res.ap_before, "cost": res.cost, "ap_after": res.ap_after})


## Common tail of an accepted move, shot or overwatch: ledger, log, winner, and the end of
## the activation if the actor did not survive its own action.
static func _finish(cs: CombatState, u: SimUnit, a: CombatAction, res: ActionResult) -> ActionResult:
	_post(cs, u, a.type, res)
	cs.record(res.events)
	ActivationScheduler.check_winner(cs)
	if not cs.is_over() and not u.alive:
		res.activation_ended = true
		ActivationScheduler.end_activation(cs)
	res.next_active = cs.active_id
	return res


## Applies a shot event's lasting effects to the engine's books (deaths, morale).
static func _apply_outcome(cs: CombatState, e: Dictionary) -> void:
	match e["type"]:
		"death":
			var id := int(e["unit"])
			cs.ap[id] = 0
			cs.overwatch.erase(id)
			cs.suppressed.erase(id)
			cs.broken.erase(id)
		"morale":
			var id := int(e["unit"])
			if e["result"] == "steady":
				cs.suppressed[id] = true
			else:
				cs.broken[id] = true
				cs.ap[id] = 0
