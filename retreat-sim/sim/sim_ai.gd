class_name SimAI
extends RefCounted
## Utility-scoring enemy planner. Pure and deterministic.
##
## FAIRNESS: the AI is handed `SimVision.view_for(state, team)` and nothing
## else, so it cannot see hidden enemies or the opponent's orders.
##
## Per unit (in id order) it enumerates every tile reachable within the tick
## budget, and for each tile considers: stay, shoot the best visible target,
## or hold overwatch. Candidates are scored with integer weights from a
## SimAIProfile; ties go to the first candidate enumerated. Teammates
## coordinate by reserving destination tiles and by counting damage already
## planned against a target, so nobody overkills.

const NO_OBJECTIVE := Vector2i(-9999, -9999)
const FAR := 1 << 20          ## "no enemy" distance sentinel
const NEG_INF := -(1 << 40)   ## below any reachable score
const MAX_OVERWATCH_TILES := 5
const OBJECTIVE_FIELD_BUDGET := 1000       ## ticks: far more than any map needs
const UNREACHABLE_OBJECTIVE_PENALTY := 20  ## tiles added when the objective cannot be walked to


## `profiles`: name -> SimAIProfile (must contain "default").
## `assignments`: unit id -> profile name (optional).
## `objective`: tile the squad drifts toward while no enemy is visible.
## `live`: for mid-turn replans, unit id -> {"free_at": ticks already spoken
## for, "pos": where the unit will stand when its committed action ends}.
## `diag`: optional out-parameter; filled with unit id -> {"kind", "score", "tile", "options"}
## so a caller can log why each unit chose what it did (it never changes the plan).
static func plan_for(state: SimState, team: int, profiles: Dictionary, assignments: Dictionary = {}, objective: Vector2i = NO_OBJECTIVE, live: Dictionary = {}, diag: Dictionary = {}) -> SimPlan:
	var view := SimVision.view_for(state, team)
	var ctx := {
		"view": view,
		"team": team,
		"enemies": _enemies(view, team),
		"threat": {},          # tile -> {"open": int, "covered": int}
		"planned_damage": {},  # enemy id -> damage already planned this turn
		"reserved": {},        # tiles chosen as destinations by teammates
		"objective": objective,
		"live": live,
		"diag": diag,
	}
	var plan := SimPlan.new()
	var own: Array[int] = []
	for id in view.units:
		var u: SimUnit = view.units[id]
		if u.alive and u.team == team:
			own.append(id)
	own.sort()
	for id in own:
		var u: SimUnit = view.units[id]
		var name: String = assignments.get(id, "default")
		var profile := _profile_for(profiles, name)
		for a: SimAction in _plan_unit(ctx, u, profile):
			plan.add(id, a)
	return plan


## Named profile, else "default", else built-in weights; never fails.
static func _profile_for(profiles: Dictionary, name: String) -> SimAIProfile:
	var p: Variant = profiles.get(name, profiles.get("default"))
	return p if p is SimAIProfile else SimAIProfile.new()


static func _enemies(view: SimState, team: int) -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	var ids := view.units.keys()
	ids.sort()
	for id in ids:
		var u: SimUnit = view.units[id]
		if u.alive and u.team != team:
			out.append(u)
	return out


static func _plan_unit(ctx: Dictionary, u: SimUnit, prof: SimAIProfile) -> Array[SimAction]:
	var view: SimState = ctx["view"]
	var info: Dictionary = (ctx["live"] as Dictionary).get(u.id, {})
	var origin: Vector2i = info.get("pos", u.pos)
	ctx["range"] = u.max_range()
	ctx["beam"] = u.ignores_half_cover()
	var budget := u.available_ticks() - int(info.get("free_at", 0))
	var reach := SimPathing.reach(view, origin, u.id, budget)
	var dist: Dictionary = reach["dist"]
	var tiles: Array = dist.keys()
	tiles.sort_custom(SimPathing.tile_before)

	# Pass 1: positional score and best shot for every reachable tile.
	var best := {"score": NEG_INF}
	var stay_best := NEG_INF
	var shoot_best := NEG_INF
	var positional: Array[Dictionary] = []
	for t: Vector2i in tiles:
		if t != origin and (ctx["reserved"] as Dictionary).has(t):
			continue
		var cost: int = dist[t]
		# Walking costs a little (1 point per 2 ticks) so equal positions
		# resolve to the one that needs less movement.
		@warning_ignore("integer_division")
		var pos := _positional_score(ctx, t, prof) - cost / 2
		var entry := {"tile": t, "cost": cost, "pos": pos}
		positional.append(entry)
		stay_best = maxi(stay_best, pos)
		if pos > best["score"]:
			best = {"score": pos, "tile": t, "kind": "stay"}
		var remaining := budget - cost
		if remaining >= u.shot_ticks():
			var shot := _best_shot(ctx, u, t, prof)
			if not shot.is_empty():
				shoot_best = maxi(shoot_best, pos + int(shot["value"]))
			if not shot.is_empty() and pos + shot["value"] > best["score"]:
				best = {"score": pos + shot["value"], "tile": t, "kind": "shoot", "shot": shot}

	best = _consider_overwatch(ctx, u, prof, positional, best, budget)
	(ctx["diag"] as Dictionary)[u.id] = {"kind": best["kind"], "score": best["score"], "tile": best["tile"],
		"options": {"stay": stay_best, "shoot": shoot_best, "chosen": best["kind"]}}
	return _commit(ctx, u, reach, best)


## Pass 2: overwatch, evaluated only for the most promising positions (it is
## the costliest option to score). Returns the better of `best` and the
## best overwatch candidate.
static func _consider_overwatch(ctx: Dictionary, u: SimUnit, prof: SimAIProfile, positional: Array[Dictionary], best: Dictionary, budget: int) -> Dictionary:
	var grid: SimGrid = (ctx["view"] as SimState).grid
	var ranked := positional.duplicate()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["pos"] != b["pos"]:
			return a["pos"] > b["pos"]
		return SimPathing.tile_before(a["tile"], b["tile"]))
	for i in mini(MAX_OVERWATCH_TILES, ranked.size()):
		var e: Dictionary = ranked[i]
		var remaining := budget - int(e["cost"])
		if remaining < 1:
			continue
		var facing := _facing_for(ctx, e["tile"], u)
		var clear: int = (SimLos.cone_tiles(grid, e["tile"], facing, u.max_range())["clear"] as Array).size()
		# Value grows with cone size and with how long the watch is held.
		@warning_ignore("integer_division")
		var watch := (prof.w_watch * clear * remaining) / (4 * SimConst.TICKS_PER_TURN)
		if watch > 0 and e["pos"] + watch > best["score"]:
			best = {"score": e["pos"] + watch, "tile": e["tile"], "kind": "overwatch", "facing": facing, "hold": remaining}
	return best



static func _positional_score(ctx: Dictionary, tile: Vector2i, prof: SimAIProfile) -> int:
	var score := 0
	var enemies: Array[SimUnit] = ctx["enemies"]
	if not enemies.is_empty():
		var nearest := FAR
		for e in enemies:
			nearest = mini(nearest, SimLos.chebyshev(tile, e.pos))
		score -= prof.w_range * absi(nearest - prof.preferred_range)
	elif ctx["objective"] != NO_OBJECTIVE:
		score -= prof.w_objective * _objective_distance(ctx, tile)
	var threat := _threat_at(ctx, tile)
	score -= prof.w_exposed * int(threat["open"])
	score += prof.w_cover * int(threat["covered"])
	if prof.w_lane != 0:
		score += prof.w_lane * _lanes_at(ctx, tile)
	return score


## Walking distance, in tiles, from `tile` to the objective around walls and crates (units are
## ignored). The field is computed once per plan. A tile cut off from the objective falls back to
## straight-line distance plus a penalty.
static func _objective_distance(ctx: Dictionary, tile: Vector2i) -> int:
	if not ctx.has("objective_field"):
		var view: SimState = ctx["view"]
		var terrain_only := SimState.new(view.grid)
		ctx["objective_field"] = SimPathing.reach(terrain_only, ctx["objective"], -1, OBJECTIVE_FIELD_BUDGET)["dist"]
	var field: Dictionary = ctx["objective_field"]
	if field.has(tile):
		@warning_ignore("integer_division")
		return int(field[tile]) / SimConst.COST_ORTHO
	return SimLos.chebyshev(tile, ctx["objective"]) + UNREACHABLE_OBJECTIVE_PENALTY


## How many visible enemies (at most 2) this unit could hit from `tile` with a clear, uncovered
## line: a flanking position rewards moving to where a shot exists, not only shooting from it.
static func _lanes_at(ctx: Dictionary, tile: Vector2i) -> int:
	var view: SimState = ctx["view"]
	var reach_range: int = ctx["range"]
	var lanes := 0
	for e: SimUnit in ctx["enemies"]:
		if SimLos.chebyshev(tile, e.pos) <= reach_range and SimLos.can_shoot(view.grid, tile, e.pos) and (bool(ctx.get("beam", false)) or not SimLos.is_covered(view.grid, tile, e.pos)):
			lanes += 1
	return mini(lanes, 2)


## How many visible enemies could fire at `tile`, split by whether cover
## would block the shot. Cached per planning call.
static func _threat_at(ctx: Dictionary, tile: Vector2i) -> Dictionary:
	var cache: Dictionary = ctx["threat"]
	if cache.has(tile):
		return cache[tile]
	var view: SimState = ctx["view"]
	var open := 0
	var covered := 0
	for e: SimUnit in ctx["enemies"]:
		if SimLos.chebyshev(e.pos, tile) > e.max_range() or not SimLos.can_shoot(view.grid, e.pos, tile):
			continue
		if not e.ignores_half_cover() and SimLos.is_covered(view.grid, e.pos, tile):
			covered += 1
		else:
			open += 1
	cache[tile] = {"open": open, "covered": covered}
	return cache[tile]


## The most valuable shot available from `tile`, or {} if none would land.
## Value = (damage, capped at what the target has left after planned shots,
## plus a kill bonus) times the shot's hit chance. Ties keep the lower unit id (enemies are id-sorted).
static func _best_shot(ctx: Dictionary, u: SimUnit, tile: Vector2i, prof: SimAIProfile) -> Dictionary:
	var view: SimState = ctx["view"]
	var planned: Dictionary = ctx["planned_damage"]
	var best := {}
	for e: SimUnit in ctx["enemies"]:
		var d := SimLos.chebyshev(tile, e.pos)
		if d > u.max_range() or not SimLos.can_shoot(view.grid, tile, e.pos):
			continue
		if not u.ignores_half_cover() and SimLos.is_covered(view.grid, tile, e.pos):
			continue
		if u.is_area() and d < SimConst.AREA_MIN_RANGE:
			continue
		var hp_left: int = e.hp - int(planned.get(e.id, 0))
		if hp_left <= 0:
			continue
		var dmg := u.damage_at(d)
		var shots := u.burst_count()
		var chance := u.hit_chance_at(d)
		if shots > 1:
			chance = maxi(SimConst.HIT_MIN, chance - SimConst.BURST_ACCURACY_PENALTY)
		var eff := mini(dmg * shots, hp_left)
		var kills := dmg * shots >= hp_left
		# Expected value: a likelier shot is worth more (integer percent).
		var value := (prof.w_damage * eff + (prof.w_kill if kills else 0)) * chance / 100
		if u.is_area():
			value += _splash_value(view, u, e, dmg, chance, prof)
		if best.is_empty() or value > best["value"]:
			best = {"target": e.id, "eff": eff, "value": value}
	return best


## What a blast on `target` adds beyond the target itself: other enemies caught in it count for, and
## friends (the shooter's own side) count against twice as much. A merc who would shell their own
## squad scores worse than one who waits for a cleaner shot.
static func _splash_value(view: SimState, u: SimUnit, target: SimUnit, dmg: int, chance: int, prof: SimAIProfile) -> int:
	var total := 0
	for t in SimResolver.blast_tiles(view.grid, target.pos):
		if t == target.pos:
			continue
		var v := view.unit_at(t)
		if v == null:
			continue
		var worth := (prof.w_damage * mini(dmg, v.hp) + (prof.w_kill if dmg >= v.hp else 0)) * chance / 100
		total += worth if v.team != u.team else -2 * worth
	return total


## 8-way facing toward the nearest visible enemy, else the objective, else east.
static func _facing_for(ctx: Dictionary, from: Vector2i, u: SimUnit = null) -> Vector2i:
	var target := from + Vector2i.RIGHT
	var nearest := FAR
	for e: SimUnit in ctx["enemies"]:
		var d := SimLos.chebyshev(from, e.pos)
		if d < nearest:
			nearest = d
			target = e.pos
	if nearest == FAR and ctx["objective"] != NO_OBJECTIVE:
		target = ctx["objective"]
	if nearest == FAR and u != null and u.watch_dir != Vector2i.ZERO:
		return u.watch_dir  # a sentry keeps looking where the map points it
	var delta := target - from
	var ax := absi(delta.x)
	var ay := absi(delta.y)
	var fx := signi(delta.x) if 2 * ax >= ay else 0
	var fy := signi(delta.y) if 2 * ay >= ax else 0
	return Vector2i(fx, fy) if (fx != 0 or fy != 0) else Vector2i.RIGHT


## Turn the winning candidate into actions and record the side effects
## teammates need to know about (reserved tile, planned damage).
static func _commit(ctx: Dictionary, u: SimUnit, reach: Dictionary, best: Dictionary) -> Array[SimAction]:
	var actions: Array[SimAction] = []
	var tile: Vector2i = best["tile"]
	(ctx["reserved"] as Dictionary)[tile] = true
	actions.append_array(SimPathing.path_actions(SimPathing.path_to(reach, tile)))
	match best["kind"]:
		"shoot":
			var shot: Dictionary = best["shot"]
			actions.append(SimAction.shoot(shot["target"]))
			var planned: Dictionary = ctx["planned_damage"]
			planned[shot["target"]] = int(planned.get(shot["target"], 0)) + int(shot["eff"])
		"overwatch":
			actions.append(SimAction.overwatch(best["facing"], best["hold"]))
	return actions
