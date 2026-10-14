class_name IsoProjection
extends RefCounted
## Maps the integer sim grid onto a 2:1 isometric view. Pure maths: the sim
## stays on square tiles, only drawing and picking go through this.
## Grid +x runs down-right on screen, grid +y runs down-left.

const NO_TILE := Vector2i(-1, -1)

var grid_w: int
var grid_h: int
var half_w: float
var half_h: float
var _origin: Vector2  # screen position of grid point (0, 0): the board's top corner


## `zoom` 1 fits the whole board in `view`; above 1 it magnifies around the grid
## point `focus` (default: the board centre), which is drawn at the view centre.
func _init(w: int, h: int, view: Vector2, zoom := 1.0, focus := Vector2(-1, -1)) -> void:
	grid_w = w
	grid_h = h
	var span := float(w + h)
	half_w = minf(view.x / span, view.y / span * 2.0) * maxf(zoom, 0.1)
	half_h = half_w * 0.5
	var f := Vector2(w, h) * 0.5 if focus.x < 0.0 else focus
	_origin = view * 0.5 - Vector2((f.x - f.y) * half_w, (f.x + f.y) * half_h)


## Continuous grid point (tile corners are whole numbers) to screen.
func grid_to_screen(g: Vector2) -> Vector2:
	return _origin + Vector2((g.x - g.y) * half_w, (g.x + g.y) * half_h)


func screen_to_grid(p: Vector2) -> Vector2:
	var d := p - _origin
	var a := d.x / half_w
	var b := d.y / half_h
	return Vector2((a + b) * 0.5, (b - a) * 0.5)


func tile_center(t: Vector2i) -> Vector2:
	return grid_to_screen(Vector2(t) + Vector2(0.5, 0.5))


## Top, right, bottom, left.
func tile_corners(t: Vector2i) -> PackedVector2Array:
	var c := tile_center(t)
	return PackedVector2Array([
		c + Vector2(0, -half_h), c + Vector2(half_w, 0),
		c + Vector2(0, half_h), c + Vector2(-half_w, 0),
	])


func screen_to_tile(p: Vector2) -> Vector2i:
	var g := screen_to_grid(p)
	var t := Vector2i(floori(g.x), floori(g.y))
	return t if t.x >= 0 and t.y >= 0 and t.x < grid_w and t.y < grid_h else NO_TILE


## Edge keys follow SimGrid: z 0 = wall between (x,y) and (x+1,y), z 1 = between (x,y) and (x,y+1).
func edge_segment(key: Vector3i) -> PackedVector2Array:
	var x := float(key.x)
	var y := float(key.y)
	if key.z == 0:
		return PackedVector2Array([grid_to_screen(Vector2(x + 1, y)), grid_to_screen(Vector2(x + 1, y + 1))])
	return PackedVector2Array([grid_to_screen(Vector2(x, y + 1)), grid_to_screen(Vector2(x + 1, y + 1))])


func board_bounds() -> Rect2:
	var left := grid_to_screen(Vector2(0, grid_h))
	var right := grid_to_screen(Vector2(grid_w, 0))
	var bottom := grid_to_screen(Vector2(grid_w, grid_h))
	return Rect2(left.x, _origin.y, right.x - left.x, bottom.y - _origin.y)


## Back-to-front painter's order: far tiles (small x+y) first.
static func draw_order(tiles: Array[Vector2i]) -> Array[Vector2i]:
	var out := tiles.duplicate()
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var sa := a.x + a.y
		var sb := b.x + b.y
		return a.x < b.x if sa == sb else sa < sb)
	return out


## Which screen diagonal a grid step points along: +x down-right ("se"), +y
## down-left ("sw"), -x up-left ("nw"), -y up-right ("ne"). Picks the dominant
## axis; the zero vector has no facing and returns "".
static func facing_name(dir: Vector2i) -> String:
	if dir == Vector2i.ZERO:
		return ""
	if absi(dir.x) >= absi(dir.y):
		return "se" if dir.x > 0 else "nw"
	return "sw" if dir.y > 0 else "ne"
