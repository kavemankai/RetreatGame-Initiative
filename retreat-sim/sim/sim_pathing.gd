class_name SimPathing
extends RefCounted
## Tick-cost pathfinding shared by the AI and the player's order entry.
## Pure and deterministic: ties resolve by (ticks, y, x).

const DIRS8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
]


static func tile_before(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)


static func step_cost(d: Vector2i, unit: SimUnit = null) -> int:
	if unit != null:
		return unit.step_cost(d)
	return SimConst.COST_DIAG if d.x != 0 and d.y != 0 else SimConst.COST_ORTHO


## Dijkstra from `from` over tick costs, limited to `budget` ticks. Tiles
## held by other living units in `view` (anyone but `mover_id`) are
## impassable. Returns {"dist": tile -> ticks, "prev": tile -> tile}.
static func reach(view: SimState, from: Vector2i, mover_id: int, budget: int) -> Dictionary:
	var occupied := {}
	for id in view.units:
		var o: SimUnit = view.units[id]
		if o.alive and o.id != mover_id:
			occupied[o.pos] = true
	var mover: SimUnit = view.units.get(mover_id)
	var dist := {from: 0}
	var prev := {}
	var open: Array[Vector2i] = [from]
	while not open.is_empty():
		var bi := 0
		for i in range(1, open.size()):
			if _closer(dist, open[i], open[bi]):
				bi = i
		var p: Vector2i = open[bi]
		open.remove_at(bi)
		for d in DIRS8:
			var q := p + d
			var cost: int = dist[p] + step_cost(d, mover)
			if cost > budget or occupied.has(q) or not view.grid.can_step(p, q):
				continue
			if dist.has(q) and dist[q] <= cost:
				continue
			dist[q] = cost
			prev[q] = p
			if not open.has(q):
				open.append(q)
	return {"dist": dist, "prev": prev}


## Tiles from the reach origin to `tile` inclusive; empty if unreachable.
static func path_to(r: Dictionary, tile: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	if not (r["dist"] as Dictionary).has(tile):
		return path
	path.append(tile)
	var prev: Dictionary = r["prev"]
	while prev.has(path[0]):
		path.push_front(prev[path[0]])
	return path


## Move actions that walk `path` (as returned by path_to).
static func path_actions(path: Array[Vector2i]) -> Array[SimAction]:
	var out: Array[SimAction] = []
	for i in range(1, path.size()):
		out.append(SimAction.move(path[i] - path[i - 1]))
	return out


static func _closer(dist: Dictionary, a: Vector2i, b: Vector2i) -> bool:
	if dist[a] != dist[b]:
		return dist[a] < dist[b]
	return tile_before(a, b)
