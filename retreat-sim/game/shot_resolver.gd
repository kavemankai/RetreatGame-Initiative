class_name ShotResolver
extends RefCounted
## One shot and its morale check, resolved now with the shared hit rules and dice. Both the
## live-AP InitiativeMatch and the activation engine (ActionResolver) call this, so a shot
## can never resolve differently between them. It mutates `state` (hp, death, counters) and
## returns events; the caller applies the morale result to its own suppressed/broken books.


## `turn` and `tick` only seed the dice, so the same inputs always roll the same numbers.
static func fire(state: SimState, shooter: SimUnit, target_id: int, turn: int, tick: int, opener_ready: bool) -> Array:
	var target: SimUnit = state.units[target_id]
	var ev := {"type": "shot", "tick": tick, "unit": shooter.id, "target": target_id}
	ev.merge(SimResolver.evaluate_shot(state.grid, shooter, shooter.pos, target, opener_ready))
	var out: Array = [ev]
	if ev["result"] == "invalid":
		return out
	var fired_before := int(shooter.counters.get("shots_fired", 0))
	if ev["result"] == "hit":
		var roll: int = state.fixed_roll
		if roll < 0:
			roll = SimDice.d100(state.seed, turn, tick, shooter.id, SimConst.HIT_DIE_OFFSET + fired_before)
		ev["roll"] = roll
		if roll > int(ev["chance"]):
			ev["result"] = "miss"
			ev.erase("damage")
	shooter.bump("shots_fired")
	if ev["result"] != "hit":
		return out
	target.hp -= int(ev["damage"])
	target.bump("hits_taken")
	shooter.bump("hits_landed")
	if target.hp <= 0:
		target.alive = false
		shooter.bump("kills")
		out.append({"type": "death", "tick": tick, "unit": target.id, "killer": shooter.id})
	else:
		var m := morale(state, target, turn, tick)
		if not m.is_empty():
			out.append(m)
	return out


## A hit unit's morale check: {"type": "morale", "result": "steady"|"broken", ...}, or {} for drones.
static func morale(state: SimState, u: SimUnit, turn: int, tick: int) -> Dictionary:
	if u.is_drone:
		return {}
	var wounds := int(u.counters.get("hits_taken", 0))
	var need := u.morale + SimConst.MORALE_BONUS - wounds
	if state.grid.has_cover_nearby(u.pos):
		need += SimConst.MORALE_COVER_BONUS
		if u.gear_trait == "bracing":
			need += SimConst.BRACING_MORALE_BONUS
	var roll := SimDice.d10(state.seed, turn, tick, u.id, wounds)
	return {"type": "morale", "tick": tick, "unit": u.id, "roll": roll, "need": need, "result": "steady" if roll <= need else "broken"}
