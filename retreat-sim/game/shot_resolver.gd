class_name ShotResolver
extends RefCounted
## One shooting action and its consequences, resolved now with the shared hit rules and dice. Both the
## live-AP InitiativeMatch and the activation engine (ActionResolver) call this, so a shot can never
## resolve differently between them. It mutates `state` (hp, death, counters) and returns events; the
## caller applies the morale result to its own suppressed/broken books.
##
## Weapon traits (SimUnit.weapon_trait): a burst fires SimConst.BURST_COUNT shots in this one action
## (stopping when the target drops, one morale check at the end); an area weapon, on a hit, also hurts
## everyone on the eight tiles around the target that a full wall does not shut off, allies included
## ("splash" events). `single` fires one ordinary shot even with a burst weapon (reaction fire).


## `turn` and `tick` only seed the dice, so the same inputs always roll the same numbers.
static func fire(state: SimState, shooter: SimUnit, target_id: int, turn: int, tick: int, opener_ready: bool, single := false) -> Array:
	var target: SimUnit = state.units[target_id]
	var base := SimResolver.evaluate_shot(state.grid, shooter, shooter.pos, target, opener_ready, single)
	if base["result"] == "invalid":
		var bad := {"type": "shot", "tick": tick, "unit": shooter.id, "target": target_id}
		bad.merge(base)
		return [bad]
	var bullets := 1 if single else shooter.burst_count()
	var out: Array = []
	var landed := 0
	for i in bullets:
		if not target.alive:
			break
		var ev := {"type": "shot", "tick": tick, "unit": shooter.id, "target": target_id}
		ev.merge(base)
		if bullets > 1:
			ev["bullet"] = i
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
		out.append(ev)
		if ev["result"] != "hit":
			continue
		landed += 1
		_damage(state, shooter, target, int(ev["damage"]), out, tick)
		if shooter.is_area():
			_splash(state, shooter, target, int(ev["damage"]), turn, tick, out)
	if landed > 0 and target.alive:
		var m := morale(state, target, turn, tick)
		if not m.is_empty():
			out.append(m)
	return out


## Applies one hit's damage, its counters and a death event if it was lethal.
static func _damage(state: SimState, shooter: SimUnit, victim: SimUnit, dmg: int, out: Array, tick: int) -> void:
	victim.hp -= dmg
	victim.bump("hits_taken")
	var foe := victim.team != shooter.team
	if foe:
		shooter.bump("hits_landed")
	if victim.hp <= 0:
		victim.alive = false
		if foe:
			shooter.bump("kills")
		out.append({"type": "death", "tick": tick, "unit": victim.id, "killer": shooter.id})


## The blast around a landed area shot: every other unit on a reached tile takes the same damage.
static func _splash(state: SimState, shooter: SimUnit, target: SimUnit, dmg: int, turn: int, tick: int, out: Array) -> void:
	for t in SimResolver.blast_tiles(state.grid, target.pos):
		if t == target.pos:
			continue
		var victim := state.unit_at(t)
		if victim == null or victim.id == target.id:
			continue
		out.append({"type": "splash", "tick": tick, "unit": shooter.id, "target": victim.id, "damage": dmg, "center": target.pos})
		_damage(state, shooter, victim, dmg, out, tick)
		if victim.alive:
			var m := morale(state, victim, turn, tick)
			if not m.is_empty():
				out.append(m)


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
