class_name ActivationScheduler
extends RefCounted
## Rounds and activations. Each round every living unit gets exactly one activation, in
## initiative order, whichever side it is on. Nothing here is driven by time: the queue only
## moves when a unit's activation ends (a command) or the encounter is over.

## A round with nobody left to activate and no winner is a bug; give up rather than spin.
const MAX_EMPTY_ROUNDS := 4


## Opens round 1 and activates the first unit.
static func start(cs: CombatState) -> void:
	cs.round_no = 0
	cs.active_id = -1
	_begin_round(cs)
	_activate_next(cs)


## Closes the active unit's activation (its unused AP expires) and activates the next one.
static func end_activation(cs: CombatState) -> void:
	if cs.active_id >= 0:
		cs.ap[cs.active_id] = 0
	cs.active_id = -1
	_activate_next(cs)


## Higher initiative first, then the higher seeded tie value, then the lower unit id.
static func initiative_of(u: SimUnit) -> int:
	return u.speed * 10 + u.aim


static func _begin_round(cs: CombatState) -> void:
	cs.round_no += 1
	cs.sim.turn = cs.round_no
	cs.activations.clear()
	_spawn_reinforcements(cs)
	cs.order.clear()
	for id in cs.sim.units:
		var u: SimUnit = cs.sim.units[id]
		if u.alive:
			var tie := SimDice.d100(cs.sim.seed, cs.round_no, 0, id, CombatState.TIE_DIE_OFFSET)
			cs.order.append({"id": id, "initiative": initiative_of(u), "tie": tie})
	cs.order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["initiative"] != b["initiative"]:
			return a["initiative"] > b["initiative"]
		if a["tie"] != b["tie"]:
			return a["tie"] > b["tie"]
		return a["id"] < b["id"])
	cs.queue.clear()
	for e: Dictionary in cs.order:
		cs.queue.append(int(e["id"]))
	cs.record([{"type": "round", "tick": cs.next_tick(), "round": cs.round_no, "order": cs.queue.duplicate()}])


static func _activate_next(cs: CombatState) -> void:
	var empty_rounds := 0
	while not cs.is_over():
		while not cs.queue.is_empty():
			var id: int = cs.queue.pop_front()
			var u: SimUnit = cs.sim.units.get(id)
			if u == null or not u.alive or cs.activations.has(id):
				continue
			_activate(cs, u)
			return
		if _end_round(cs):
			return
		empty_rounds += 1
		if empty_rounds > MAX_EMPTY_ROUNDS:
			push_error("ActivationScheduler: rounds with nobody to activate; ending the encounter as a draw")
			_finish(cs, CombatState.DRAW)
			return
		_begin_round(cs)


static func _activate(cs: CombatState, u: SimUnit) -> void:
	cs.active_id = u.id
	cs.activations[u.id] = int(cs.activations.get(u.id, 0)) + 1
	cs.ap[u.id] = cs.config.pool_for(u)
	cs.suppressed.erase(u.id)
	cs.broken.erase(u.id)
	cs.overwatch.erase(u.id)
	cs.fired.erase(u.id)
	cs.phase = CombatState.Phase.AWAIT_COMMAND
	cs.record([{"type": "activate", "tick": cs.next_tick(), "unit": u.id, "round": cs.round_no, "ap": cs.ap[u.id]}])


## Round-end bookkeeping. Returns true if that ended the encounter.
static func _end_round(cs: CombatState) -> bool:
	cs.notices.clear()
	if cs.goal != null:
		cs.notices.append_array(cs.goal.round_end(cs.sim, cs.player_team))
	var w := CombatState.winner_for(cs.sim, cs.goal, cs.player_team, cs.ai_team)
	if w != CombatState.NO_WINNER:
		_finish(cs, w)
		return true
	return false


## Stops the scheduler: nobody is active and no further activation will happen.
static func _finish(cs: CombatState, w: int) -> void:
	cs.winner = w
	cs.phase = CombatState.Phase.ENDED
	cs.active_id = -1
	for id in cs.ap:
		cs.ap[id] = 0
	cs.queue.clear()
	cs.overwatch.clear()


## Called by the resolver after any action that may have decided the encounter.
static func check_winner(cs: CombatState) -> void:
	var w := CombatState.winner_for(cs.sim, cs.goal, cs.player_team, cs.ai_team)
	if w != CombatState.NO_WINNER and not cs.is_over():
		_finish(cs, w)


## New units join at the start of the round they are due, never mid-round.
static func _spawn_reinforcements(cs: CombatState) -> void:
	var rest: Array[Dictionary] = []
	var arrived := 0
	for r in cs.reinforcements:
		if int(r["round"]) > cs.round_no:
			rest.append(r)
			continue
		var u: SimUnit = r["unit"]
		u.pos = _free_tile_near(cs.sim, u.pos)
		cs.sim.add_unit(u)
		cs.ap[u.id] = 0
		arrived += 1
	cs.reinforcements = rest
	if arrived > 0:
		cs.notices.append("Reinforcements arrive (%d)." % arrived)


static func _free_tile_near(state: SimState, tile: Vector2i) -> Vector2i:
	for radius in 6:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var t := tile + Vector2i(dx, dy)
				if state.grid.in_bounds(t) and not state.grid.is_blocked(t) and state.unit_at(t) == null:
					return t
	return tile
