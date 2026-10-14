class_name SimVision
extends RefCounted
## Fog of war. Pure functions over a SimState; the resolver stays omniscient.
## Vision is shared across a squad: a tile is visible if any living teammate
## is within its sight range and has a clear line (full walls block, half
## walls do not). Own living units are always visible to their team.
##
## Fog constrains PLANNING (what a team may know and target), not resolution.


## Set of tiles (Vector2i -> true) visible to `team`.
static func visible_tiles(state: SimState, team: int) -> Dictionary:
	var out := {}
	for id in state.units:
		var obs: SimUnit = state.units[id]
		if not obs.alive or obs.team != team:
			continue
		var r := obs.sight_range
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var t := obs.pos + Vector2i(dx, dy)
				if out.has(t) or not state.grid.in_bounds(t):
					continue
				if t == obs.pos or SimLos.can_see(state.grid, obs.pos, t):
					out[t] = true
	return out


## Ids of living units `team` can currently see: its own plus visible enemies.
static func visible_unit_ids(state: SimState, team: int) -> Array[int]:
	var tiles := visible_tiles(state, team)
	var ids: Array[int] = []
	for id in state.units:
		var u: SimUnit = state.units[id]
		if u.alive and (u.team == team or tiles.has(u.pos)):
			ids.append(id)
	ids.sort()
	return ids


## A copy of `state` containing only what `team` can see. This is what an
## AI planner or a player UI should be handed.
static func view_for(state: SimState, team: int) -> SimState:
	var visible := visible_unit_ids(state, team)
	var view := state.clone()
	for id in view.units.keys():
		if not visible.has(id):
			view.units.erase(id)
	return view


## The part of `plan` that `team` may see: its own orders plus the orders of
## visible enemies.
static func visible_orders(state: SimState, plan: SimPlan, team: int) -> SimPlan:
	var visible := visible_unit_ids(state, team)
	var out := SimPlan.new()
	for id in plan.orders:
		if visible.has(id):
			for a: SimAction in plan.orders[id]:
				out.add(id, a)
	return out


## What `team` may be shown for a tick that moved the board from `before` to
## `after`: anything visible at either end, so a unit that dies (or a squad
## wiped out) on that tick is still seen dying. Returns {"tiles", "units"}.
static func fog_between(before: SimState, after: SimState, team: int) -> Dictionary:
	var units := {}
	for id in visible_unit_ids(after, team):
		units[id] = true
	for id in visible_unit_ids(before, team):
		units[id] = true
	var tiles := visible_tiles(after, team)
	tiles.merge(visible_tiles(before, team))
	return {"tiles": tiles, "units": units}
