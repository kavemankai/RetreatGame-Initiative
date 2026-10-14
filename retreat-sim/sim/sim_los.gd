class_name SimLos
extends RefCounted
## Integer line of sight and binary cover.
## v0 uses canonical-direction Bresenham tile lines (symmetric); swap for
## shadowcasting later without changing the callers.


static func line_tiles(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [a]
	var dx := absi(b.x - a.x)
	var dy := absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx - dy
	var x := a.x
	var y := a.y
	while x != b.x or y != b.y:
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
		out.append(Vector2i(x, y))
	return out


## The line between two tiles, always walked from the canonical end (lower
## y, then lower x). Using one canonical direction makes line of sight and
## cover independent of who is shooting whom: a<->b share the same tiles.
static func canonical_line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	if b.y < a.y or (b.y == a.y and b.x < a.x):
		return line_tiles(b, a)
	return line_tiles(a, b)


## Can `from` fire at `to`? Symmetric: can_shoot(a, b) == can_shoot(b, a).
static func can_shoot(grid: SimGrid, from: Vector2i, to: Vector2i) -> bool:
	var tiles := canonical_line(from, to)
	for i in range(1, tiles.size()):
		if not grid.can_pass_sight(tiles[i - 1], tiles[i]):
			return false
	return true


## Mutual awareness (used for fog). Line of sight is symmetric.
static func can_see(grid: SimGrid, a: Vector2i, b: Vector2i) -> bool:
	return can_shoot(grid, a, b)


## Binary cover: the shot is blocked if a half-wall sits on the target's
## facing side (the final step of the line). Assumes can_shoot() is true.
static func is_covered(grid: SimGrid, from: Vector2i, to: Vector2i) -> bool:
	var tiles := canonical_line(from, to)
	if tiles.size() < 2:
		return false
	# The tile next to the target on the shooter's side of the line.
	var prev := tiles[tiles.size() - 2] if tiles[tiles.size() - 1] == to else tiles[1]
	var d := to - prev
	if d.x == 0 or d.y == 0:
		return grid.edge_between(prev, to) == SimConst.EDGE_HALF
	var side_x := grid.edge_between(to, to - Vector2i(d.x, 0))
	var side_y := grid.edge_between(to, to - Vector2i(0, d.y))
	return side_x == SimConst.EDGE_HALF or side_y == SimConst.EDGE_HALF


## Is `target` inside the 90-degree cone from `origin` along `facing`?
## Integer test of cos^2(angle) >= 1/2 with the boundary included.
static func in_cone(origin: Vector2i, facing: Vector2i, target: Vector2i) -> bool:
	var d := target - origin
	if d == Vector2i.ZERO or facing == Vector2i.ZERO:
		return false
	var dot := facing.x * d.x + facing.y * d.y
	if dot <= 0:
		return false
	return 2 * dot * dot >= facing.length_squared() * d.length_squared()


## Tiles inside a watcher's cone and range, split by whether the shooter can
## actually see them. Uses the same rule the resolver uses to trigger
## overwatch, so shading can never disagree with the sim.
## Returns {"clear": Array[Vector2i], "shadowed": Array[Vector2i]}.
static func cone_tiles(grid: SimGrid, origin: Vector2i, facing: Vector2i, max_range: int) -> Dictionary:
	var clear: Array[Vector2i] = []
	var shadowed: Array[Vector2i] = []
	for dy in range(-max_range, max_range + 1):
		for dx in range(-max_range, max_range + 1):
			var t := origin + Vector2i(dx, dy)
			if not grid.in_bounds(t) or grid.is_blocked(t) or not in_cone(origin, facing, t):
				continue
			if can_shoot(grid, origin, t):
				clear.append(t)
			else:
				shadowed.append(t)
	return {"clear": clear, "shadowed": shadowed}


static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
