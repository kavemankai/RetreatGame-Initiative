class_name SimResolver
extends RefCounted
## Resolves a whole turn in one go: (state, plan) -> (new state, event log).
## The rules live in SimTurn; this is "advance until finished", so stepping a
## turn tick by tick and resolving it at once can never disagree.


static func resolve(start: SimState, plan: SimPlan) -> SimResult:
	var turn := SimTurn.new(start, plan)
	while not turn.is_finished():
		turn.advance()
	return turn.result()


## What a shot from tile `from` at `target` would do right now. Public so
## the order-entry preview and the resolver can never disagree.
## Returns {"result": "hit"|"invalid", "damage"?, "chance"?, "cover"? (the target is behind half cover: the chance already has the penalty), "burst"?, "area"?, "reason"?}.
## `opener_ready`: the shooter has not yet taken a shot this round (the opener trait's bonus).
## `single`: fire one ordinary shot even with a burst weapon (a reaction shot).
## Weapon traits: a beam ignores half cover and range falloff, an area weapon cannot fire at a
## target closer than SimConst.AREA_MIN_RANGE, a burst reports its shot count and a lower chance.
static func evaluate_shot(grid: SimGrid, shooter: SimUnit, from: Vector2i, target: SimUnit, opener_ready: bool = false, single: bool = false) -> Dictionary:
	var dist := SimLos.chebyshev(from, target.pos)
	if dist > shooter.max_range():
		return {"result": "invalid", "reason": "out_of_range"}
	if shooter.is_area() and dist < SimConst.AREA_MIN_RANGE:
		return {"result": "invalid", "reason": "too_close"}
	if not SimLos.can_shoot(grid, from, target.pos):
		return {"result": "invalid", "reason": "no_los"}
	var in_cover := not shooter.ignores_half_cover() and SimLos.is_covered(grid, from, target.pos)
	var chance := shooter.hit_chance_at(dist)
	if in_cover:
		chance = maxi(SimConst.HIT_MIN, chance - SimConst.COVER_HIT_PENALTY)
	if shooter.gear_trait == "bracing" and grid.has_cover_nearby(from):
		chance = mini(SimConst.HIT_MAX, chance + SimConst.BRACING_HIT_BONUS)
	if opener_ready and shooter.gear_trait == "opener":
		chance = mini(SimConst.HIT_MAX, chance + SimConst.OPENER_HIT_BONUS)
	var out := {"result": "hit", "damage": shooter.damage_at(dist), "chance": chance}
	if in_cover:
		out["cover"] = true
	if shooter.burst_count() > 1 and not single:
		out["burst"] = shooter.burst_count()
		out["chance"] = maxi(SimConst.HIT_MIN, chance - SimConst.BURST_ACCURACY_PENALTY)
	if shooter.is_area():
		out["area"] = true
	return out


## The tiles a blast centred on `center` reaches: the tile itself and the eight around it that a
## full wall does not shut off from the centre (and that are not solid terrain).
static func blast_tiles(grid: SimGrid, center: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [center]
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var t := center + Vector2i(dx, dy)
			if grid.in_bounds(t) and not grid.is_blocked(t) and grid.can_pass_sight(center, t):
				out.append(t)
	return out
