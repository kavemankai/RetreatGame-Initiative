class_name BoardView
extends Control
## Draws one replay frame. Pure rendering: receives a state, this tick's
## events and the active overwatch cones, and never touches the sim.

const TEAM_COLORS: Array[Color] = [Color("4aa3ff"), Color("ff6161")]
const COL_BG := Color("14171c")
const COL_TILE_A := Color("1d2128")
const COL_TILE_B := Color("20252d")
const COL_BLOCKED := Color("3b3f47")
const COL_GRID := Color("2c323b")
const COL_FULL := Color("e8ecf2")
const COL_HALF := Color("f2b134")
const COL_HIT := Color("ff5a36")
const COL_BLOCK := Color("f2b134")
const COL_INVALID := Color("8a93a0")
const CONE_STEPS := 14
const DRAG_THRESHOLD := 12.0  # pixels a press must travel before it pans instead of taps
const SNAP_DISTANCE := 4.0  # farther than this (a seek, a new mission) and units jump instead
const POSE_HOLD := 0.3  # seconds fire and hit frames stay up
const RUN_FPS := 12.0
const RUN_FRAMES := 6
const RUN_GRACE := 0.2  # seconds a unit keeps running after a move, so back-to-back steps never blink to idle
const TRACER_GROW := 0.12  # seconds a new tracer takes to reach its target
const TRACER_STUB := 1.2  # tiles of tracer shown toward/from a unit hidden by fog
## Weapon looks: muzzle flash size (in tiles) and colour per class, the gap before each bullet of a
## burst, how wide a shotgun's pellets fan, and the beam colour.
const FLASH := {"rifle": [0.12, Color("ffd479")], "carbine": [0.10, Color("ffe2a8")], "sniper": [0.16, Color("ffffff")],
	"shotgun": [0.24, Color("ff9f43")], "heavy": [0.20, Color("ffc857")], "grenade": [0.18, Color("c9ccd1")], "beam": [0.11, Color("7fe8ff")]}
const BURST_STAGGER := 0.07
const SHOTGUN_FAN := 0.16
const BEAM_COLOR := Color("7fe8ff")
const BLAST_RADIUS := 0.85  # tiles
const MISS_OVERSHOOT := 0.6  # a miss flies this many tiles past its target
const COL_MISS := Color("9aa3ad")
const COVER_SHORT := 0.5  # a blocked tracer stops this many tiles short, at the cover
const FLOAT_SECONDS := 1.0
const COL_STEADY := Color("b8c0cc")
const COL_BROKEN := Color("ff5a4a")
const MERC_DIR := "res://assets/mercs/"
const MERC_HEIGHT := 0.95  # standing figure height as a multiple of the tile width
const MERC_FRAME := 64.0
const MERC_STAND_PX := 48.0  # figure height inside a MERC_FRAME frame
static var _merc_cache: Dictionary = {}
var _facing: Dictionary = {}  # unit id -> "se" | "sw" | "ne" | "nw"
var _pose: Dictionary = {}  # unit id -> {"name": "fire" | "hit", "left": seconds}
var _vis: Dictionary = {}  # unit id -> displayed grid position (floats), glides toward the sim tile
var _walk_clock := 0.0
var _zones: Array[Dictionary] = []  # goal zones to tint: {"tiles": Array[Vector2i], "kind": "objective" | "exit"}
## Shots of the current round, kept on screen until clear_tracers() (next Go).
## Each: {a, b (grid points), result, team, overwatch, age}.
var _tracers: Array[Dictionary] = []
var _status: Dictionary = {}  # unit id -> "steady" | "broken" for the rest of the round
var _floats: Array[Dictionary] = []  # {unit, text, color, left}
var _run_grace: Dictionary = {}  # unit id -> seconds of running left
## 1 shows the whole board; above 1 the view is magnified and can be dragged.
var zoom := 1.0
## Level theme whose floor, wall and prop art is drawn (see ThemeArt, MapData.THEMES).
var level_theme := ThemeArt.DEFAULT
var _art_floors: Array[Texture2D] = ThemeArt.floors(ThemeArt.DEFAULT)
var _art_props: Array[Texture2D] = ThemeArt.props(ThemeArt.DEFAULT)
var _art_walls: Dictionary = {}  # z * 2 + (1 if full else 0) -> Texture2D
var _focus := Vector2.ZERO
var _has_focus := false
var _press_at := Vector2.ZERO
var _dragged := false
## Seconds a one-tile step takes on screen; the play view sets it just under the tick pace.
var glide_seconds := 0.11
## Wall and prop sprites are normalised (art/normalize_assets.py) so a one-tile footprint is
## CANON_TILE_PX wide in the file; the board draws them at tile_width / CANON_TILE_PX.
const CANON_TILE_PX := 128.0
const WALL_SINK := 0.3  # how far a wall sprite's base sits below its edge line, in half-tile heights
signal tile_clicked(tile: Vector2i, button: int)
signal tile_hovered(tile: Vector2i)

const NO_TILE := Vector2i(-1, -1)
const COL_REACH := Color(0.45, 0.75, 1.0, 0.13)
const COL_PLAN := Color("8fd0ff")
const COL_FOG := Color(0.02, 0.03, 0.05, 0.66)
const COL_SHADOW := Color(0.0, 0.0, 0.0, 0.32)
const COL_WALL_FACE := Color("5d6068")

var _state: SimState
var _events: Array[Dictionary] = []
var _watchers: Array[Dictionary] = []
var _overlay: Dictionary = {}
var _hover := NO_TILE
var _iso_cache: IsoProjection
var _iso_cache_key: Array = []
var _fog: Dictionary = {}  # empty = no fog; else {"tiles", "units"} for the viewing team


func show_frame(state: SimState, events: Array[Dictionary], watchers: Array[Dictionary], fog: Dictionary = {}) -> void:
	_state = state
	_events = events
	_watchers = watchers
	_fog = fog
	_read_events(events)
	_sync_visuals()
	queue_redraw()


## Optional planning overlay (see PlayOverlay): {selected, reachable, hover,
## paths, shots, ghosts}. Empty = replay mode with no extras.
func set_overlay(overlay: Dictionary) -> void:
	_overlay = overlay
	queue_redraw()


## Adds a tracer for every shot in `events` and a status for every morale
## check, using unit positions in `state` (the board after that tick). Under
## fog a hidden end becomes a short stub so a tracer never gives a unit away.
## `settled`: rebuilding an earlier tick (replay scrubbing): no grow-in, no floats.
func record_tracers(events: Array[Dictionary], state: SimState, fog: Dictionary = {}, settled: bool = false) -> void:
	var seen: Dictionary = fog.get("units", {})
	for ev in events:
		if ev["type"] == "morale":
			_status[ev["unit"]] = ev["result"]
			if settled:
				continue
			var steady: bool = ev["result"] == "steady"
			_floats.append({"unit": ev["unit"], "text": "STEADY" if steady else "BROKEN", "color": COL_STEADY if steady else COL_BROKEN, "left": FLOAT_SECONDS})
			continue
		if ev["type"] != "shot" or ev["result"] == "invalid":
			continue
		var shooter: SimUnit = state.units[ev["unit"]]
		var a := Vector2(shooter.pos) + Vector2(0.5, 0.5)
		var b := Vector2((state.units[ev["target"]] as SimUnit).pos) + Vector2(0.5, 0.5)
		if not fog.is_empty() and not seen.has(ev["target"]):
			b = a + (b - a).normalized() * minf((b - a).length(), TRACER_STUB)
		elif not fog.is_empty() and not seen.has(ev["unit"]):
			a = b + (a - b).normalized() * minf((a - b).length(), TRACER_STUB)
		elif ev["result"] == "blocked" or (ev["result"] == "miss" and ev.get("cover", false)):
			b -= (b - a).normalized() * COVER_SHORT  # stopped by the cover
		elif ev["result"] == "miss":
			b += (b - a).normalized() * MISS_OVERSHOOT  # sails past the target
		var started := TRACER_GROW if settled else -BURST_STAGGER * float(int(ev.get("bullet", 0)))
		_tracers.append({"a": a, "b": b, "result": ev["result"], "team": shooter.team, "overwatch": ev.get("overwatch", false), "age": started, "klass": shooter.weapon_class, "cover": ev.get("cover", false)})
	queue_redraw()


func clear_tracers() -> void:
	_tracers.clear()
	_status.clear()
	_floats.clear()
	queue_redraw()


func tracer_count() -> int:
	return _tracers.size()


func tile_at(p: Vector2) -> Vector2i:
	if _state == null:
		return NO_TILE
	return _iso().screen_to_tile(p)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press_at = event.position
				_dragged = false
			elif not _dragged:
				_emit_click(event.position, event.button_index)
		elif event.pressed:
			_emit_click(event.position, event.button_index)
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT and zoom > 1.0:
			if _dragged or event.position.distance_to(_press_at) > DRAG_THRESHOLD:
				_dragged = true
				_pan_by(-event.relative)
			return
		var t := tile_at(event.position)
		if t != _hover:
			_hover = t
			tile_hovered.emit(t)
			queue_redraw()


func _emit_click(p: Vector2, button: int) -> void:
	var t := tile_at(p)
	if t != NO_TILE:
		tile_clicked.emit(t, button)


## Moves the view by a screen-space delta (dragging the map under a finger).
func _pan_by(screen_delta: Vector2) -> void:
	var iso := _iso()
	var here := iso.screen_to_grid(size * 0.5)
	var there := iso.screen_to_grid(size * 0.5 + screen_delta)
	focus_on(_focus + (there - here))


## Centres the view on a grid point, kept inside the board.
func focus_on(g: Vector2) -> void:
	_focus = Vector2(clampf(g.x, 0.0, _state.grid.width), clampf(g.y, 0.0, _state.grid.height)) if _state != null else g
	_has_focus = true
	queue_redraw()


func set_zones(zones: Array[Dictionary]) -> void:
	_zones = zones
	queue_redraw()


func set_level_theme(name: String) -> void:
	if name != level_theme:
		level_theme = name
		_art_floors = ThemeArt.floors(name)
		_art_props = ThemeArt.props(name)
		_art_walls.clear()
		queue_redraw()


func set_zoom(z: float) -> void:
	zoom = maxf(z, 1.0)
	queue_redraw()


func _squad_centre() -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for id in _state.units:
		var u: SimUnit = _state.units[id]
		if u.team == 0 and u.alive:
			sum += Vector2(u.pos) + Vector2(0.5, 0.5)
			n += 1
	return sum / n if n > 0 else Vector2(_state.grid.width, _state.grid.height) * 0.5


## Facing comes from the last move or shot; the pose lasts for the frame's events.
func _read_events(events: Array[Dictionary]) -> void:
	for ev in events:
		match ev["type"]:
			"move":
				_set_facing(ev["unit"], ev["to"] - ev["from"])
				_run_grace[ev["unit"]] = RUN_GRACE
			"shot":
				var shooter: SimUnit = _state.units[ev["unit"]]
				var target: SimUnit = _state.units[ev["target"]]
				_set_facing(ev["unit"], target.pos - shooter.pos)
				_pose[ev["unit"]] = {"name": "fire", "left": POSE_HOLD}
				if ev["result"] == "hit":
					_pose[ev["target"]] = {"name": "hit", "left": POSE_HOLD}
					_set_facing(ev["target"], shooter.pos - target.pos)  # turns to the shot


## Keeps a displayed position per unit; new or far-away units snap to the sim tile.
func _sync_visuals() -> void:
	for id in _state.units:
		var tile := Vector2((_state.units[id] as SimUnit).pos)
		if not _vis.has(id) or (_vis[id] as Vector2).distance_to(tile) > SNAP_DISTANCE:
			_vis[id] = tile


func is_animating() -> bool:
	if _state == null:
		return false
	for id in _vis:
		if _state.units.has(id) and (_vis[id] as Vector2) != Vector2((_state.units[id] as SimUnit).pos):
			return true
	if not _floats.is_empty() or _tracers.any(func(t: Dictionary) -> bool: return t["age"] < TRACER_GROW):
		return true
	return not _pose.is_empty() or not _run_grace.is_empty()


## Advances glides and pose timers by `delta` seconds. Driven by _process; tests call it directly.
func _advance(delta: float) -> void:
	if _state == null:
		return
	_walk_clock += delta
	for id in _vis:
		if _state.units.has(id):
			_vis[id] = (_vis[id] as Vector2).move_toward(Vector2((_state.units[id] as SimUnit).pos), delta / maxf(glide_seconds, 0.01))
	for t in _tracers:
		t["age"] += delta
	for f in _floats:
		f["left"] -= delta
	_floats = _floats.filter(func(f: Dictionary) -> bool: return f["left"] > 0.0)
	for id in _run_grace.keys():
		_run_grace[id] -= delta
		if _run_grace[id] <= 0.0:
			_run_grace.erase(id)
	for id in _pose.keys():
		_pose[id]["left"] -= delta
		if _pose[id]["left"] <= 0.0:
			_pose.erase(id)


func _is_running(id: int) -> bool:
	return _is_gliding(id) or _run_grace.has(id)


func _is_gliding(id: int) -> bool:
	return _vis.has(id) and _state.units.has(id) and (_vis[id] as Vector2) != Vector2((_state.units[id] as SimUnit).pos)


func _process(delta: float) -> void:
	if is_animating():
		_advance(delta)
		queue_redraw()


func _set_facing(id: int, dir: Vector2i) -> void:
	var name := IsoProjection.facing_name(dir)
	if name != "":
		_facing[id] = name


func _facing_of(u: SimUnit) -> String:
	return _facing.get(u.id, "se" if u.team == 0 else "nw")


static func _merc_texture(key: String, frame: String) -> Texture2D:
	var cache_key := "%s_%s" % [key, frame]
	if not _merc_cache.has(cache_key):
		var path := "%s%s.png" % [ArtSkin.merc_dir(), cache_key]
		_merc_cache[cache_key] = load(path) if ResourceLoader.exists(path) else null
	return _merc_cache[cache_key]


func _sprite_key(u: SimUnit) -> String:
	return UnitSprites.key_for(u.id, u.team, u.is_drone)


## Picks the sprite frame and whether to mirror it. The action frames face
## down-right, so they are mirrored for the west-facing diagonals; north
## facings fall back to the static turnaround sprite.
func _merc_frame(u: SimUnit) -> Dictionary:
	var facing := _facing_of(u)
	var west := facing == "sw" or facing == "nw"
	var front := facing == "se" or facing == "sw"
	var frame := facing
	if not u.alive:
		return {"frame": "dead", "flip": west}
	if not front and _is_running(u.id) and not _pose.has(u.id):
		var back := "runn_%d" % (int(_walk_clock * RUN_FPS) % RUN_FRAMES)  # running away from the camera
		if _merc_texture(_sprite_key(u), back) != null:
			return {"frame": back, "flip": west}
	if front:
		var pose: String = _pose[u.id]["name"] if _pose.has(u.id) else ""
		if pose != "":
			frame = pose
		elif _is_running(u.id):
			frame = "run_%d" % (int(_walk_clock * RUN_FPS) % RUN_FRAMES)
			if _merc_texture(_sprite_key(u), frame) == null:  # a set with no run cycle (the Writ) walks instead
				frame = "walk%d" % (int(_walk_clock * RUN_FPS * 0.5) % 2)
	return {"frame": frame, "flip": west and frame != facing}


func _tile_visible(t: Vector2i) -> bool:
	return _fog.is_empty() or (_fog["tiles"] as Dictionary).has(t)


func _unit_visible(id: int) -> bool:
	return _fog.is_empty() or (_fog["units"] as Dictionary).has(id)


func _iso() -> IsoProjection:
	if zoom <= 1.0:
		_has_focus = false
	elif not _has_focus:
		focus_on(_squad_centre())
	var key := [_state.grid.width, _state.grid.height, size, zoom, _focus if zoom > 1.0 else Vector2.ZERO]
	if _iso_cache == null or _iso_cache_key != key:
		_iso_cache = IsoProjection.new(_state.grid.width, _state.grid.height, size, zoom, _focus if zoom > 1.0 else Vector2(-1, -1))
		_iso_cache_key = key
	return _iso_cache


func _scale() -> float:
	return _iso().half_w * 2.0  # on-screen width of one tile, the unit for sprite sizes


func _center(t: Vector2i) -> Vector2:
	return _iso().tile_center(t)


func _poly(t: Vector2i) -> PackedVector2Array:
	return _iso().tile_corners(t)


func _fill(t: Vector2i, col: Color) -> void:
	draw_colored_polygon(_poly(t), col)


func _outline(t: Vector2i, col: Color, width: float) -> void:
	var pts := _poly(t)
	pts.append(pts[0])
	draw_polyline(pts, col, width)


func _all_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in _state.grid.height:
		for x in _state.grid.width:
			out.append(Vector2i(x, y))
	return out


func _draw() -> void:
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	if _state == null:
		return
	_draw_tiles()
	_draw_zones()
	_draw_cones()
	_draw_fog()
	_draw_reachable()
	_draw_events()
	_draw_tracers()
	_draw_plan_lines()
	_draw_ghosts_and_selection()
	_draw_standing()  # walls and units interleaved back to front
	_draw_marks()
	_draw_floats()


func _draw_tiles() -> void:
	var g := _state.grid
	var tex := _art_floors
	var iso := _iso()
	for t in IsoProjection.draw_order(_all_tiles()):
		if tex.is_empty():
			_fill(t, COL_TILE_A if (t.x + t.y) % 2 == 0 else COL_TILE_B)
		else:
			var c := iso.tile_center(t)
			draw_texture_rect(tex[0 if g.is_blocked(t) else floor_variant(t, tex.size())], Rect2(c - Vector2(iso.half_w, iso.half_h), Vector2(iso.half_w, iso.half_h) * 2.0), false)
		_outline(t, COL_GRID, 1.0)


## Which floor tile art a cell uses: mostly plain plating with sparse
## variety, stable per cell so the map never shimmers between frames.
static func floor_variant(t: Vector2i, count: int) -> int:
	var h := absi((t.x * 73856093) ^ (t.y * 19349663)) % 16
	if h < 9 or count <= 1:
		return 0
	return 1 + (h - 9) % (count - 1)


const COL_ZONE := {"objective": Color(1.0, 0.83, 0.47), "exit": Color(0.47, 0.86, 0.55)}


## Goal zones: a soft tint and a bright outline so the objective reads from across the map.
func _draw_zones() -> void:
	for z in _zones:
		var col: Color = COL_ZONE.get(z["kind"], COL_ZONE["objective"])
		for t: Vector2i in z["tiles"]:
			if _state.grid.in_bounds(t):
				_fill(t, Color(col, 0.2))
				_outline(t, Color(col, 0.75), 2.0)


func _draw_fog() -> void:
	if _fog.is_empty():
		return
	for t in _all_tiles():
		if not _tile_visible(t):
			_fill(t, COL_FOG)


## Walls and units share one painter's pass so a unit behind a wall is hidden by it.
func _draw_standing() -> void:
	var by_tile := {}
	for id in _state.units:
		var u: SimUnit = _state.units[id]
		by_tile[u.pos] = by_tile.get(u.pos, []) + [id]
	for t in IsoProjection.draw_order(_all_tiles()):
		if _state.grid.is_blocked(t):
			_draw_prop(t)
		for id: int in by_tile.get(t, []):
			_draw_unit(id)
		for z in 2:
			var kind: int = _state.grid.edges.get(Vector3i(t.x, t.y, z), SimConst.EDGE_NONE)
			if kind != SimConst.EDGE_NONE:
				_draw_wall(Vector3i(t.x, t.y, z), kind)


func _draw_prop(t: Vector2i) -> void:
	var props := _art_props
	if props.is_empty():
		return
	var tex := props[(t.x * 3 + t.y * 5) % props.size()]
	var k := _scale() / CANON_TILE_PX
	var w := tex.get_width() * k
	var h := tex.get_height() * k
	var base := _center(t) + Vector2(0, _iso().half_h * 1.1)
	draw_texture_rect(tex, Rect2(base - Vector2(w * 0.5, h), Vector2(w, h)), false)


func _draw_wall(key: Vector3i, kind: int) -> void:
	var seg := _iso().edge_segment(key)
	var slot: int = key.z * 2 + (1 if kind == SimConst.EDGE_FULL else 0)
	if not _art_walls.has(slot):
		_art_walls[slot] = ThemeArt.wall(level_theme, key.z, kind)
	var tex: Texture2D = _art_walls[slot]
	if tex != null:
		var k := _scale() / CANON_TILE_PX
		var w := tex.get_width() * k
		var h := tex.get_height() * k
		var base := (seg[0] + seg[1]) * 0.5 + Vector2(0, _iso().half_h * WALL_SINK)
		draw_texture_rect(tex, Rect2(base - Vector2(w * 0.5, h), Vector2(w, h)), false)
		return
	var h := _scale() * (0.5 if kind == SimConst.EDGE_FULL else 0.2)
	var up := Vector2(0, -h)
	var face := PackedVector2Array([seg[0], seg[1], seg[1] + up, seg[0] + up])
	if kind == SimConst.EDGE_FULL:
		draw_colored_polygon(face, COL_WALL_FACE)
		draw_line(seg[0] + up, seg[1] + up, COL_FULL, 3.0)
	else:
		draw_colored_polygon(face, Color(COL_HALF, 0.35))
		draw_line(seg[0] + up, seg[1] + up, COL_HALF, 2.5)


func _draw_cones() -> void:
	var iso := _iso()
	for w in _watchers:
		var u: SimUnit = _state.units[w["id"]]
		if not u.alive:
			continue
		var origin: Vector2i = w.get("pos", u.pos)
		var center := Vector2(origin) + Vector2(0.5, 0.5)
		var base := Vector2(w["dir"]).angle()
		var radius := float(u.max_range())
		var pts := PackedVector2Array([iso.grid_to_screen(center)])
		for i in CONE_STEPS + 1:
			var ang := base - PI / 4.0 + (PI / 2.0) * float(i) / CONE_STEPS
			pts.append(iso.grid_to_screen(center + Vector2.from_angle(ang) * radius))
		var col: Color = TEAM_COLORS[u.team % TEAM_COLORS.size()]
		var spent: bool = w["spent"]
		var tiles := SimLos.cone_tiles(_state.grid, origin, w["dir"], u.max_range())
		var tint := Color(col, 0.06 if spent else 0.16)
		for t: Vector2i in tiles["clear"]:
			_fill(t, tint)
		for t: Vector2i in tiles["shadowed"]:
			_fill(t, COL_SHADOW)
		draw_polyline(pts, Color(col, 0.25 if spent else 0.6), 1.5)


func _draw_events() -> void:
	for ev in _events:
		match ev["type"]:
			"move":
				var a := _center(ev["from"])
				var b := _center(ev["to"])
				if not _tile_visible(ev["to"]):
					b = a + (b - a) * 0.4
				elif not _tile_visible(ev["from"]):
					a = b + (a - b) * 0.4
				draw_line(a, b, Color(1, 1, 1, 0.55), 3.0)
				draw_circle(a, 4.0, Color(1, 1, 1, 0.55))
			"move_blocked":
				var p := _center(ev["at"])
				var q := _center(ev["to"])
				draw_line(p, p + (q - p) * 0.5, COL_BLOCK, 3.0)
				draw_circle(p + (q - p) * 0.5, 5.0, COL_BLOCK)


func _draw_tracers() -> void:
	var iso := _iso()
	for t in _tracers:
		var a := iso.grid_to_screen(t["a"])
		var full := iso.grid_to_screen(t["b"])
		var b := a.lerp(full, clampf(float(t["age"]) / TRACER_GROW, 0.0, 1.0))
		var col: Color = TEAM_COLORS[int(t["team"]) % TEAM_COLORS.size()]
		var klass := String(t.get("klass", "rifle"))
		_draw_flash(a, klass, float(t["age"]))
		if t["result"] == "hit":
			_draw_hit_line(a, b, full, col, klass)
			if b == full:
				draw_circle(b, _scale() * 0.09, COL_HIT)
				draw_arc(b, _scale() * 0.16, 0.0, TAU, 16, Color(COL_HIT, 0.7), 1.5)
				if klass == "grenade":
					draw_circle(b, _scale() * BLAST_RADIUS, Color(COL_HIT, 0.16))
					draw_arc(b, _scale() * BLAST_RADIUS, 0.0, TAU, 24, Color(COL_HIT, 0.8), 2.0)
		elif t["result"] == "miss" and t.get("cover", false):
			draw_dashed_line(a, b, Color(col, 0.55), 1.5, 5.0)  # the cover took it
			if b == full:
				draw_circle(b, _scale() * 0.05, COL_BLOCK)
		elif t["result"] == "miss":
			draw_line(a, b, Color(COL_MISS, 0.5), 1.2)
			if b == full:
				draw_arc(b, _scale() * 0.07, 0.0, TAU, 12, Color(COL_MISS, 0.6), 1.0)  # a small dust puff
		else:
			draw_dashed_line(a, b, Color(col, 0.55), 1.5, 5.0)
			if b == full:
				draw_circle(b, _scale() * 0.05, COL_BLOCK)
		if t["overwatch"]:
			draw_string(ThemeDB.fallback_font, (a + full) * 0.5 + Vector2(6, -6), "OW", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)


## A short bright flash at the muzzle, sized and coloured by class; it fades as the tracer grows.
func _draw_flash(a: Vector2, klass: String, age: float) -> void:
	if age < 0.0 or age > TRACER_GROW * 2.0:
		return
	var look: Array = FLASH.get(klass, FLASH["rifle"])
	var fade := 1.0 - age / (TRACER_GROW * 2.0)
	draw_circle(a, _scale() * float(look[0]), Color(look[1], 0.75 * fade))


## The line of a landed shot in the weapon's own style: a beam glows, a sniper's is thin and long, a
## shotgun fans out short pellets, a heavy gun's is thick, a grenade flies in an arc.
func _draw_hit_line(a: Vector2, b: Vector2, full: Vector2, col: Color, klass: String) -> void:
	match klass:
		"beam":
			draw_line(a, b, Color(BEAM_COLOR, 0.25), 8.0)
			draw_line(a, b, Color(BEAM_COLOR, 0.95), 3.0)
		"sniper":
			draw_line(a, b, Color(col, 0.2), 5.0)
			draw_line(a, b, Color(col, 0.95), 1.6)
		"shotgun":
			for angle in [-SHOTGUN_FAN, 0.0, SHOTGUN_FAN]:
				draw_line(a, a + (b - a).rotated(angle) * 0.85, Color(col, 0.85), 1.8)
		"heavy":
			draw_line(a, b, Color(col, 0.95), 4.0)
		"carbine":
			draw_line(a, b, Color(col, 0.8), 1.8)
		"grenade":
			var points := PackedVector2Array()
			var rise := (full - a).length() * 0.35
			for i in 15:
				var k := float(i) / 14.0
				points.append(a.lerp(b, k) + Vector2(0.0, -sin(k * PI) * rise))
			draw_polyline(points, Color(col, 0.9), 2.2)
		_:
			draw_line(a, b, Color(col, 0.9), 2.5)


func _draw_floats() -> void:
	for f in _floats:
		var u: SimUnit = _state.units.get(f["unit"])
		if u == null or not _unit_visible(u.id):
			continue
		var rise := (FLOAT_SECONDS - float(f["left"])) * _scale() * 0.4
		var p := _iso().grid_to_screen(_vis.get(u.id, Vector2(u.pos)) + Vector2(0.5, 0.5)) + Vector2(-28, -_scale() * 1.1 - rise)
		draw_string(ThemeDB.fallback_font, p, f["text"], HORIZONTAL_ALIGNMENT_CENTER, 56, 13, Color(f["color"], clampf(float(f["left"]) / FLOAT_SECONDS, 0.0, 1.0)))


## Steady: a grey pip with a slash (no shooting). Broken: a red bar (halted).
func _draw_status(id: int, tag: Vector2, r: float) -> void:
	var st: String = _status.get(id, "")
	if st == "":
		return
	var p := tag + Vector2(r * 1.3, 0)
	if st == "steady":
		draw_circle(p, r * 0.4, COL_STEADY)
		draw_line(p + Vector2(-r * 0.3, r * 0.3), p + Vector2(r * 0.3, -r * 0.3), Color.BLACK, 2.0)
	else:
		draw_rect(Rect2(p - Vector2(r * 0.45, r * 0.2), Vector2(r * 0.9, r * 0.4)), COL_BROKEN)


func _draw_unit(id: int) -> void:
	var u: SimUnit = _state.units[id]
	var col: Color = TEAM_COLORS[u.team % TEAM_COLORS.size()]
	if u.alive and not _unit_visible(id):
		return
	if not u.alive and not _tile_visible(u.pos):
		return
	var ground := _iso().grid_to_screen(_vis.get(id, Vector2(u.pos)) + Vector2(0.5, 0.5))
	var look := _merc_frame(u)
	if u.alive and _is_running(id) and look["frame"] == _facing_of(u):
		ground.y -= absf(sin(_walk_clock * RUN_FPS * 0.5 * PI)) * _scale() * 0.05  # north-facing runners bob in place
	var tex := _merc_texture(_sprite_key(u), look["frame"])
	var r := _scale() * 0.2
	if tex == null:
		_draw_disc_unit(u, ground, r, col)
		return
	if u.alive:
		_draw_ellipse(ground, Vector2(r * 1.1, r * 0.55), COL_SHADOW)
	var k := _scale() * MERC_HEIGHT / MERC_STAND_PX
	var side := MERC_FRAME * k
	var rect := Rect2(ground + Vector2(-side * 0.5, -side * 0.94 + _iso().half_h * 0.2), Vector2(side, side))
	if look["flip"]:
		rect = Rect2(rect.position + Vector2(side, 0), Vector2(-side, side))
	draw_texture_rect(tex, rect, false)  # each set carries its own palette; teams read from the number tag
	if not u.alive:
		return
	var tag := ground + Vector2(0, -side * 0.82)
	draw_circle(tag, r * 0.55, Color(0, 0, 0, 0.7))
	draw_string(ThemeDB.fallback_font, tag + Vector2(-r, r * 0.3), str(id), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 12, col)
	_draw_status(id, tag, r)
	_draw_hp_pips(u, ground, r)


func _draw_hp_pips(u: SimUnit, ground: Vector2, r: float) -> void:
	for i in u.hp:
		draw_rect(Rect2(ground + Vector2(-r + i * 8.0, r * 0.7), Vector2(6, 5)), Color("7be37b"))


func _draw_disc_unit(u: SimUnit, ground: Vector2, r: float, col: Color) -> void:
	var p := ground + Vector2(0, -r * 1.1)  # body floats above its tile
	_draw_ellipse(ground, Vector2(r * 1.1, r * 0.55), COL_SHADOW)
	if not u.alive:
		var gray := Color(0.5, 0.5, 0.55)
		draw_line(ground + Vector2(-r, -r * 0.5), ground + Vector2(r, r * 0.5), gray, 3.0)
		draw_line(ground + Vector2(-r, r * 0.5), ground + Vector2(r, -r * 0.5), gray, 3.0)
		return
	draw_circle(p, r, col)
	draw_arc(p, r, 0.0, TAU, 24, Color.WHITE, 1.5)
	draw_string(ThemeDB.fallback_font, p + Vector2(-r, 5), str(u.id), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 15, Color.BLACK)
	_draw_hp_pips(u, ground, r)


func _draw_ellipse(c: Vector2, radii: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		pts.append(c + Vector2(cos(TAU * i / 20.0) * radii.x, sin(TAU * i / 20.0) * radii.y))
	draw_colored_polygon(pts, col)


func _draw_reachable() -> void:
	for t: Vector2i in _overlay.get("reachable", {}):
		_fill(t, COL_REACH)
	var pend: Vector2i = _overlay.get("pending", NO_TILE)
	if pend != NO_TILE:
		_outline(pend, Color("ffd479"), 3.0)
	var h: Vector2i = _hover
	if not _overlay.is_empty() and h != NO_TILE:
		_outline(h, Color(1, 1, 1, 0.8), 2.0)


func _draw_plan_lines() -> void:
	for path: Dictionary in _overlay.get("paths", []):
		var pts := PackedVector2Array()
		for t: Vector2i in path["tiles"]:
			pts.append(_center(t))
		if pts.size() < 2:
			continue
		if path.get("dashed", false):
			for i in range(1, pts.size()):
				draw_dashed_line(pts[i - 1], pts[i], path["color"], 2.5, 6.0)
		else:
			draw_polyline(pts, path["color"], 3.0)
		draw_circle(pts[pts.size() - 1], 5.0, path["color"])
	for shot: Dictionary in _overlay.get("shots", []):
		var a := _center(shot["from"])
		var b := _center(shot["to"])
		draw_dashed_line(a, b, shot["color"], 2.5, 7.0)
		draw_arc(b, _scale() * 0.2, 0.0, TAU, 20, shot["color"], 2.0)


func _draw_ghosts_and_selection() -> void:
	var c := _scale()
	for g: Dictionary in _overlay.get("ghosts", []):
		var col: Color = TEAM_COLORS[int(g["team"]) % TEAM_COLORS.size()]
		var p := _center(g["tile"])
		draw_circle(p, c * 0.2, Color(col, 0.28))
		draw_arc(p, c * 0.2, 0.0, TAU, 20, col, 2.0)
		draw_string(ThemeDB.fallback_font, p + Vector2(-5, 5), str(g["id"]), HORIZONTAL_ALIGNMENT_CENTER, 10.0, 14, Color(1, 1, 1, 0.8))
	var sel: int = _overlay.get("selected", -1)
	if sel >= 0 and _state.units.has(sel):
		_outline((_state.units[sel] as SimUnit).pos, Color("ffd479"), 3.0)


## "t8" labels: the tick at which a queued action completes.
func _draw_marks() -> void:
	var font := ThemeDB.fallback_font
	var c := _scale()
	for m: Dictionary in _overlay.get("marks", []):
		var text: String = m["text"]
		var p := _center(m["tile"]) + Vector2(c * 0.1, -c * 0.4 + int(m["lane"]) * 15.0)
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_rect(Rect2(p + Vector2(-2, -11), Vector2(width + 5, 15)), Color(0, 0, 0, 0.72))
		draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, m.get("color", Color("ffd479")))
