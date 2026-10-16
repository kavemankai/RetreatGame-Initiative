class_name MapCanvas
extends Control
## The overworld drawn in code: the route from Karsa Station (bottom) to Vesper Reach (top), done stops
## ticked, the current stop pulsing, the next stop named, everything beyond it in fog. Contingency cards
## are small diamonds. A clean tap emits `tapped` with the hit ({"kind", "id"}); drags pass to the scroll.

signal tapped(hit: Dictionary)

const TAP_SLOP := 12.0
const NODE_R := 16.0
const FOG := Color("0e0f12")

var _map: Dictionary
var _route: Dictionary
var _selected := ""
var _down := Vector2.ZERO
var _armed := false
var _time := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


func setup(map: Dictionary, route: Dictionary, canvas_height: float) -> MapCanvas:
	_map = map
	_route = route
	custom_minimum_size = Vector2(0, canvas_height)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_process(true)
	queue_redraw()
	return self


func select(id: String) -> void:
	_selected = id
	queue_redraw()


## Where the current stop sits, for scrolling it into view.
func current_y() -> float:
	for n: Dictionary in _route["nodes"]:
		if n["state"] == "current":
			return MapLayout.node_point(_map, n["id"], size).y
	return size.y


func hit_at(at: Vector2) -> Dictionary:
	return MapLayout.hit_test(_map, _route, at, size)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_down = button.position
			_armed = true
		else:
			if _armed and button.position.distance_to(_down) <= TAP_SLOP:
				var hit := hit_at(button.position)
				if not hit.is_empty():
					tapped.emit(hit)
			_armed = false
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _armed and motion.position.distance_to(_down) > TAP_SLOP:
		_armed = false


func _draw() -> void:
	if _route.is_empty():
		return
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.COL_DEEP)
	_draw_bands()
	var nodes: Array = _route["nodes"]
	_draw_route(nodes)
	for n: Dictionary in nodes:
		_draw_node(n)
	_draw_cards()


func _draw_bands() -> void:
	var font := ThemeDB.fallback_font
	for band: Dictionary in _map.get("act_bands", []):
		var y0 := float(band["y0"]) * size.y
		var y1 := float(band["y1"]) * size.y
		if int(band["act"]) % 2 == 0:
			draw_rect(Rect2(0, y0, size.x, y1 - y0), Color(1, 1, 1, 0.025))
		draw_string(font, Vector2(10, y1 - 8), "ACT %d" % int(band["act"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(UiTheme.COL_MUTED, 0.5))


func _draw_route(nodes: Array) -> void:
	for i in range(1, nodes.size()):
		var a: Vector2 = MapLayout.node_point(_map, nodes[i - 1]["id"], size)
		var b: Vector2 = MapLayout.node_point(_map, nodes[i]["id"], size)
		var to_state := String(nodes[i]["state"])
		var from_state := String(nodes[i - 1]["state"])
		if to_state == "done" or (to_state == "current" and from_state == "done"):
			draw_line(a, b, UiTheme.COL_AMBER, 4.0, true)
		elif to_state == "next":
			_dashed(a, b, Color(UiTheme.COL_AMBER, 0.7))
		else:
			_dashed(a, b, Color(UiTheme.COL_MUTED, 0.12))


func _dashed(a: Vector2, b: Vector2, color: Color) -> void:
	var length := a.distance_to(b)
	var dir := (b - a) / maxf(length, 1.0)
	var at := 0.0
	while at < length:
		draw_line(a + dir * at, a + dir * minf(at + 10.0, length), color, 3.0)
		at += 18.0


func _draw_node(n: Dictionary) -> void:
	var p := MapLayout.node_point(_map, n["id"], size)
	var state := String(n["state"])
	var font := ThemeDB.fallback_font
	var col := UiTheme.COL_MUTED
	var label := "?"
	match state:
		"done":
			col = UiTheme.COL_AMBER
			label = String(n["place"])
		"current":
			col = UiTheme.COL_AMBER
			label = String(n["place"])
			var pulse := 0.5 + 0.5 * sin(_time * 3.0)
			draw_circle(p, NODE_R + 6.0 + 6.0 * pulse, Color(UiTheme.COL_AMBER, 0.25 * (1.0 - pulse) + 0.1))
		"next":
			col = UiTheme.COL_TEXT
			label = String(n["place"])
		_:
			col = Color(UiTheme.COL_MUTED, 0.35)
	if state == "far":
		draw_circle(p, NODE_R - 4.0, FOG)
		draw_arc(p, NODE_R - 4.0, 0, TAU, 20, col, 2.0)
	else:
		draw_circle(p, NODE_R, UiTheme.COL_PANEL)
		draw_arc(p, NODE_R, 0, TAU, 28, col, 3.0)
	if state == "done":
		draw_line(p + Vector2(-6, 0), p + Vector2(-2, 5), col, 3.0)
		draw_line(p + Vector2(-2, 5), p + Vector2(7, -5), col, 3.0)
	if n["id"] == _selected:
		draw_arc(p, NODE_R + 5.0, 0, TAU, 28, UiTheme.COL_TEAL, 2.0)
	var x := p.x + NODE_R + 8.0 if p.x < size.x * 0.5 else p.x - NODE_R - 8.0
	var align := HORIZONTAL_ALIGNMENT_LEFT if p.x < size.x * 0.5 else HORIZONTAL_ALIGNMENT_RIGHT
	var w := 150.0
	var origin := Vector2(x if align == HORIZONTAL_ALIGNMENT_LEFT else x - w, p.y + 5.0)
	draw_string(font, origin, label, align, w, 15, col)


func _draw_cards() -> void:
	var per_act := {}
	for c: Dictionary in _route["cards"]:
		var act := int(c["act"])
		var index := int(per_act.get(act, 0))
		per_act[act] = index + 1
		var p := MapLayout.card_point(_map, act, index, size)
		if p.x < 0.0:
			continue
		var col := UiTheme.COL_TEAL if c["state"] == "offered" else Color(UiTheme.COL_MUTED, 0.6)
		var pts := PackedVector2Array([p + Vector2(0, -12), p + Vector2(12, 0), p + Vector2(0, 12), p + Vector2(-12, 0)])
		draw_colored_polygon(pts, Color(col, 0.25))
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), col, 2.0)
		if c["id"] == _selected:
			draw_arc(p, 18.0, 0, TAU, 24, UiTheme.COL_TEAL, 2.0)
