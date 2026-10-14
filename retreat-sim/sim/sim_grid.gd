class_name SimGrid
extends RefCounted
## Tile grid with cover/walls stored on tile edges.
## Edge key: Vector3i(x, y, axis); axis 0 = edge between (x,y) and (x+1,y),
## axis 1 = edge between (x,y) and (x,y+1).

var width: int
var height: int
var blocked: Dictionary = {}
var edges: Dictionary = {}


func _init(p_width: int, p_height: int) -> void:
	width = p_width
	height = p_height


## Is `t` standing beside a wall edge or a blocked tile (a crate)? Used for the
## morale check's cover bonus; independent of any particular shooter.
func has_cover_nearby(t: Vector2i) -> bool:
	for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var n: Vector2i = t + d
		if is_blocked(n) or edge_between(t, n) != SimConst.EDGE_NONE:
			return true
	return false


func in_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < width and t.y < height


func set_blocked(t: Vector2i) -> void:
	blocked[t] = true


func is_blocked(t: Vector2i) -> bool:
	return blocked.has(t)


func set_edge(a: Vector2i, b: Vector2i, kind: int) -> void:
	edges[_edge_key(a, b)] = kind


func edge_between(a: Vector2i, b: Vector2i) -> int:
	return int(edges.get(_edge_key(a, b), SimConst.EDGE_NONE))


## True if a unit may cross from tile `p` into orthogonal neighbour `q`.
func orth_open(p: Vector2i, q: Vector2i) -> bool:
	return in_bounds(q) and not is_blocked(q) and edge_between(p, q) != SimConst.EDGE_FULL


## Movement: diagonals need BOTH L-shaped routes open (no corner cutting).
func can_step(p: Vector2i, q: Vector2i) -> bool:
	var d := q - p
	if d == Vector2i.ZERO or absi(d.x) > 1 or absi(d.y) > 1:
		return false
	if not in_bounds(q) or is_blocked(q):
		return false
	if d.x == 0 or d.y == 0:
		return orth_open(p, q)
	return _l_open(p, d, true) and _l_open(p, d, false)


## Sight/shots: a diagonal needs at least ONE L-shaped route open.
func can_pass_sight(p: Vector2i, q: Vector2i) -> bool:
	var d := q - p
	if d.x == 0 or d.y == 0:
		return orth_open(p, q)
	return _l_open(p, d, true) or _l_open(p, d, false)


func _l_open(p: Vector2i, d: Vector2i, x_first: bool) -> bool:
	var mid := p + (Vector2i(d.x, 0) if x_first else Vector2i(0, d.y))
	return orth_open(p, mid) and orth_open(mid, p + d)


func _edge_key(a: Vector2i, b: Vector2i) -> Vector3i:
	if b.x == a.x + 1 and b.y == a.y:
		return Vector3i(a.x, a.y, 0)
	if b.x == a.x - 1 and b.y == a.y:
		return Vector3i(b.x, b.y, 0)
	if b.y == a.y + 1 and b.x == a.x:
		return Vector3i(a.x, a.y, 1)
	if b.y == a.y - 1 and b.x == a.x:
		return Vector3i(b.x, b.y, 1)
	push_error("SimGrid edge requested between non-adjacent tiles %s and %s" % [a, b])
	return Vector3i(-1, -1, -1)
