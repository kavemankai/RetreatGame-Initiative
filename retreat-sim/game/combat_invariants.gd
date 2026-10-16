class_name CombatInvariants
extends RefCounted
## The rules that must hold after every committed command (plan section 3.3). check()
## returns one message per violation; an empty array means the state is sound. Tests and
## the soak call it after every command.


static func check(cs: CombatState) -> Array[String]:
	var bad: Array[String] = []
	_activity(cs, bad)
	_ap(cs, bad)
	_activations(cs, bad)
	_dead(cs, bad)
	_occupancy(cs, bad)
	_ledger(cs, bad)
	return bad


static func _activity(cs: CombatState, bad: Array[String]) -> void:
	if cs.phase == CombatState.Phase.ENDED:
		if cs.active_id != -1:
			bad.append("encounter over but unit %d is still active" % cs.active_id)
		if cs.winner == CombatState.NO_WINNER:
			bad.append("encounter over with no winner")
		return
	if cs.phase != CombatState.Phase.AWAIT_COMMAND:
		return
	var u: SimUnit = cs.sim.units.get(cs.active_id)
	if u == null:
		bad.append("awaiting a command but active unit %d does not exist" % cs.active_id)
	elif not u.alive:
		bad.append("active unit %d is dead" % cs.active_id)
	if cs.queue.has(cs.active_id):
		bad.append("active unit %d is still in the queue" % cs.active_id)
	var seen := {}
	for id in cs.queue:
		if seen.has(id):
			bad.append("unit %d is queued twice" % id)
		seen[id] = true
		if cs.activations.has(id):
			bad.append("unit %d is queued after already activating" % id)
	if cs.winner != CombatState.NO_WINNER:
		bad.append("a winner is set but the encounter is still running")


static func _ap(cs: CombatState, bad: Array[String]) -> void:
	for id in cs.ap:
		var v := int(cs.ap[id])
		if v < 0 or v > cs.config.max_ap:
			bad.append("unit %d has AP %d outside 0..%d" % [id, v, cs.config.max_ap])
		if v > 0 and id != cs.active_id:
			bad.append("unit %d holds %d AP but is not the active unit" % [id, v])


static func _activations(cs: CombatState, bad: Array[String]) -> void:
	for id in cs.activations:
		if int(cs.activations[id]) > 1:
			bad.append("unit %d activated %d times in round %d" % [id, cs.activations[id], cs.round_no])


static func _dead(cs: CombatState, bad: Array[String]) -> void:
	for id in cs.overwatch:
		var u: SimUnit = cs.sim.units.get(id)
		if u == null or not u.alive:
			bad.append("dead unit %d is on overwatch" % id)


static func _occupancy(cs: CombatState, bad: Array[String]) -> void:
	var held := {}
	for id in cs.sim.units:
		var u: SimUnit = cs.sim.units[id]
		if not u.alive:
			continue
		if not cs.sim.grid.in_bounds(u.pos) or cs.sim.grid.is_blocked(u.pos):
			bad.append("unit %d stands on an illegal tile %s" % [id, u.pos])
		if held.has(u.pos):
			bad.append("units %d and %d share tile %s" % [held[u.pos], id, u.pos])
		held[u.pos] = id


static func _ledger(cs: CombatState, bad: Array[String]) -> void:
	for row in cs.ledger:
		if int(row["cost"]) < 0 or int(row["ap_before"]) - int(row["cost"]) != int(row["ap_after"]):
			bad.append("ledger row %d does not add up: %s" % [row["seq"], row])
