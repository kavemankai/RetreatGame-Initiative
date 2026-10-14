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
## Returns {"result": "hit"|"blocked"|"invalid", "damage"?, "reason"?}.
## `opener_ready`: the shooter has not yet taken a shot this round (the opener trait's bonus).
static func evaluate_shot(grid: SimGrid, shooter: SimUnit, from: Vector2i, target: SimUnit, opener_ready: bool = false) -> Dictionary:
	var dist := SimLos.chebyshev(from, target.pos)
	if dist > shooter.max_range():
		return {"result": "invalid", "reason": "out_of_range"}
	if not SimLos.can_shoot(grid, from, target.pos):
		return {"result": "invalid", "reason": "no_los"}
	if SimLos.is_covered(grid, from, target.pos):
		return {"result": "blocked"}
	var chance := shooter.hit_chance_at(dist)
	if shooter.gear_trait == "bracing" and grid.has_cover_nearby(from):
		chance = mini(SimConst.HIT_MAX, chance + SimConst.BRACING_HIT_BONUS)
	if opener_ready and shooter.gear_trait == "opener":
		chance = mini(SimConst.HIT_MAX, chance + SimConst.OPENER_HIT_BONUS)
	return {"result": "hit", "damage": shooter.damage_at(dist), "chance": chance}
