extends TestBase
## Isometric board projection: tile <-> screen, picking, edges, draw order.

const VIEW := Vector2(540, 600)


func test_centre_round_trips_to_the_same_tile() -> void:
	var iso := IsoProjection.new(12, 10, VIEW)
	var ok := true
	for y in 10:
		for x in 12:
			var t := Vector2i(x, y)
			ok = ok and iso.screen_to_tile(iso.tile_center(t)) == t
	check(ok, "every tile centre picks its own tile")


func test_points_inside_the_diamond_pick_the_tile() -> void:
	var iso := IsoProjection.new(8, 8, VIEW)
	var t := Vector2i(3, 4)
	var c := iso.tile_center(t)
	var near := Vector2(iso.half_w * 0.45, 0)
	check(iso.screen_to_tile(c + near) == t, "right of centre, inside the diamond")
	check(iso.screen_to_tile(c - near) == t, "left of centre, inside the diamond")
	check(iso.screen_to_tile(c + Vector2(0, iso.half_h * 0.45)) == t, "below centre, inside the diamond")
	check(iso.screen_to_tile(c + Vector2(iso.half_w * 1.1, 0)) != t, "past the right corner belongs to a neighbour")


func test_outside_the_board_picks_nothing() -> void:
	var iso := IsoProjection.new(8, 8, VIEW)
	check(iso.screen_to_tile(Vector2(-50, -50)) == IsoProjection.NO_TILE, "off-screen")
	check(iso.screen_to_tile(Vector2(2, 590)) == IsoProjection.NO_TILE, "empty corner of the view")


func test_board_is_fitted_and_centred() -> void:
	var iso := IsoProjection.new(12, 10, VIEW)
	var rect := iso.board_bounds()
	check(rect.position.x >= -0.5 and rect.end.x <= VIEW.x + 0.5, "fits the width")
	check(rect.position.y >= -0.5 and rect.end.y <= VIEW.y + 0.5, "fits the height")
	check(absf((rect.position.x + rect.end.x) * 0.5 - VIEW.x * 0.5) < 1.0, "centred horizontally")
	check(absf(iso.half_w - 2.0 * iso.half_h) < 0.001, "2:1 diamonds")


func test_diamond_corners_surround_the_centre() -> void:
	var iso := IsoProjection.new(6, 6, VIEW)
	var t := Vector2i(2, 2)
	var pts := iso.tile_corners(t)
	var c := iso.tile_center(t)
	check(pts.size() == 4, "four corners")
	check(pts[0].is_equal_approx(c + Vector2(0, -iso.half_h)), "top corner")
	check(pts[1].is_equal_approx(c + Vector2(iso.half_w, 0)), "right corner")
	check(pts[2].is_equal_approx(c + Vector2(0, iso.half_h)), "bottom corner")
	check(pts[3].is_equal_approx(c + Vector2(-iso.half_w, 0)), "left corner")


func test_edge_segments_follow_the_tile_sides() -> void:
	var iso := IsoProjection.new(6, 6, VIEW)
	var t := Vector2i(2, 3)
	var corners := iso.tile_corners(t)
	var east := iso.edge_segment(Vector3i(2, 3, 0))  # between (2,3) and (3,3)
	check(east[0].is_equal_approx(corners[1]) and east[1].is_equal_approx(corners[2]), "x-axis edge is the tile's lower-right side")
	var south := iso.edge_segment(Vector3i(2, 3, 1))  # between (2,3) and (2,4)
	check(south[0].is_equal_approx(corners[3]) and south[1].is_equal_approx(corners[2]), "y-axis edge is the tile's lower-left side")


func test_draw_order_is_back_to_front() -> void:
	var tiles: Array[Vector2i] = [Vector2i(3, 3), Vector2i(0, 0), Vector2i(2, 1), Vector2i(1, 2)]
	var ordered := IsoProjection.draw_order(tiles)
	check(ordered[0] == Vector2i(0, 0) and ordered[3] == Vector2i(3, 3), "far tile first, near tile last")
	var sums := ordered.map(func(t: Vector2i) -> int: return t.x + t.y)
	var sorted := sums.duplicate()
	sorted.sort()
	check(sums == sorted, "non-decreasing x+y")
	check(ordered[1].x <= ordered[2].x and ordered[1].x + ordered[1].y == ordered[2].x + ordered[2].y, "ties break by x for stability")


func test_floor_variant_is_stable_in_range_and_mostly_plain() -> void:
	var plain := 0
	var in_range := true
	for y in 10:
		for x in 12:
			var v := BoardView.floor_variant(Vector2i(x, y), 9)
			in_range = in_range and v >= 0 and v < 9
			check(v == BoardView.floor_variant(Vector2i(x, y), 9), "same tile, same art")
			plain += 1 if v == 0 else 0
	check(in_range, "variant index within the tile set")
	check(plain > 120 * 0.4 and plain < 120, "mostly plain plating with some variety")
	check(BoardView.floor_variant(Vector2i(5, 5), 1) == 0, "a one-tile set always returns it")


func test_facing_names_follow_the_screen_diagonals() -> void:
	check(IsoProjection.facing_name(Vector2i.RIGHT) == "se", "+x runs down-right")
	check(IsoProjection.facing_name(Vector2i.DOWN) == "sw", "+y runs down-left")
	check(IsoProjection.facing_name(Vector2i.LEFT) == "nw", "-x runs up-left")
	check(IsoProjection.facing_name(Vector2i.UP) == "ne", "-y runs up-right")
	check(IsoProjection.facing_name(Vector2i(5, -2)) == "se", "dominant axis wins")
	check(IsoProjection.facing_name(Vector2i(-1, 4)) == "sw", "dominant axis wins on y")
	check(IsoProjection.facing_name(Vector2i.ZERO) == "", "no direction, no facing")


func test_board_view_derives_facing_and_pose_from_events() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(3, 3))
	add_unit(s, 2, 1, Vector2i(3, 6))
	var board := BoardView.new()
	var none: Array[Dictionary] = []
	board.show_frame(s, none, none)
	check(board._facing_of(s.units[1]) == "se" and board._facing_of(s.units[2]) == "nw", "teams start facing each other across the board")
	var moved: Array[Dictionary] = [{"type": "move", "tick": 1, "unit": 1, "from": Vector2i(3, 2), "to": Vector2i(3, 3)}]
	s.units[1].pos = Vector2i(3, 2)
	board.show_frame(s, none, none)
	board._advance(1.0)  # settle on (3, 2) before the step under test
	s.units[1].pos = Vector2i(3, 3)
	board.show_frame(s, moved, none)
	check(board._facing_of(s.units[1]) == "sw", "moving +y faces down-left")
	check(board._merc_frame(s.units[1])["frame"].begins_with("run_"), "gliding toward the new tile shows a run frame")
	board._advance(1.0)
	check(not board._is_gliding(1), "the unit has arrived and stops walking")
	var shot: Array[Dictionary] = [{"type": "shot", "tick": 2, "unit": 1, "target": 2, "result": "hit"}]
	board.show_frame(s, shot, none)
	check(board._merc_frame(s.units[1])["frame"] == "fire", "the shooter shows the fire frame")
	check(board._facing_of(s.units[2]) == "ne", "a hit target turns toward the shooter")
	check(board._merc_frame(s.units[2])["frame"] == "ne", "front-only hit frames fall back to the turnaround sprite when the target faces away")
	check(board._merc_frame(s.units[1])["flip"], "west-facing action frames are mirrored")
	board.show_frame(s, none, none)
	check(board._merc_frame(s.units[1])["frame"] == "fire", "the fire frame holds after its event frame")
	board._advance(BoardView.POSE_HOLD + 0.05)
	check(board._merc_frame(s.units[1])["frame"] == "sw", "once the hold runs out the idle facing sprite returns")
	s.units[2].alive = false
	check(board._merc_frame(s.units[2])["frame"] == "dead", "dead units use the dead pose")
	board.free()


func test_units_glide_toward_their_tile_and_far_jumps_snap() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(2, 2))
	var board := BoardView.new()
	var none: Array[Dictionary] = []
	board.show_frame(s, none, none)
	s.units[1].pos = Vector2i(3, 2)
	board.show_frame(s, none, none)
	board._advance(0.05)
	var v: Vector2 = board._vis[1]
	check(v.x > 2.0 and v.x < 3.0 and v.y == 2.0, "partway along the step after a short delta")
	check(board.is_animating(), "animating while gliding")
	board._advance(1.0)
	check(board._vis[1] == Vector2(3, 2) and not board.is_animating(), "settles exactly on the tile and stops animating")
	s.units[1].pos = Vector2i(11, 9)
	board.show_frame(s, none, none)
	check(board._vis[1] == Vector2(11, 9), "a jump beyond the snap distance does not glide across the map")
	board.free()


func test_zoom_magnifies_around_the_focus_point() -> void:
	var fit := IsoProjection.new(12, 10, VIEW)
	var zoomed := IsoProjection.new(12, 10, VIEW, 2.0)
	check(absf(zoomed.half_w - fit.half_w * 2.0) < 0.001, "zoom 2 doubles the tile size")
	check(zoomed.grid_to_screen(Vector2(6, 5)).is_equal_approx(VIEW * 0.5), "the default focus (board centre) stays at the view centre")
	var focused := IsoProjection.new(12, 10, VIEW, 2.0, Vector2(2.5, 3.5))
	check(focused.grid_to_screen(Vector2(2.5, 3.5)).is_equal_approx(VIEW * 0.5), "a chosen focus point lands at the view centre")
	check(focused.screen_to_tile(VIEW * 0.5) == Vector2i(2, 3), "picking still inverts the zoomed, shifted mapping")
	var same := IsoProjection.new(12, 10, VIEW, 1.0, Vector2(6, 5))
	check(same.tile_center(Vector2i(4, 4)).is_equal_approx(fit.tile_center(Vector2i(4, 4))), "zoom 1 with the centre focus equals the plain fit")


func test_zoomed_board_pans_and_stays_inside_the_map() -> void:
	var s := make_state(12, 10)
	add_unit(s, 1, 0, Vector2i(2, 2))
	var board := BoardView.new()
	board.size = VIEW
	var none: Array[Dictionary] = []
	board.set_zoom(2.0)
	board.show_frame(s, none, none)
	var start := board._iso().screen_to_grid(VIEW * 0.5)
	check(start.distance_to(Vector2(2.5, 2.5)) < 0.01, "a zoomed board opens centred on the squad")
	board._pan_by(Vector2(80, 0))
	var moved := board._iso().screen_to_grid(VIEW * 0.5)
	check(moved.distance_to(start) > 0.5, "dragging moves the view")
	board._pan_by(Vector2(100000, 100000))
	var edge := board._iso().screen_to_grid(VIEW * 0.5)
	check(edge.x <= 12.001 and edge.y <= 10.001 and edge.x >= -0.001 and edge.y >= -0.001, "the focus never leaves the board")
	board.set_zoom(1.0)
	board.show_frame(s, none, none)
	check(board.tile_at(board._iso().tile_center(Vector2i(5, 5))) == Vector2i(5, 5), "unzoomed picking is back to the plain fit")
	board.free()


func test_runner_keeps_running_briefly_after_arriving() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(3, 2))
	var board := BoardView.new()
	var none: Array[Dictionary] = []
	board.show_frame(s, none, none)
	s.units[1].pos = Vector2i(3, 3)
	var moved: Array[Dictionary] = [{"type": "move", "tick": 1, "unit": 1, "from": Vector2i(3, 2), "to": Vector2i(3, 3)}]
	board.show_frame(s, moved, none)
	board._advance(1.0)  # arrived
	check(not board._is_running(1), "after a long wait the unit is at rest")
	board.show_frame(s, moved, none)
	check(board._is_running(1), "a fresh move keeps the run pose even when the glide has already finished")
	board._advance(BoardView.RUN_GRACE + 0.05)
	check(not board._is_running(1) and not board.is_animating(), "the run ends shortly after the last step")
	var seen := {}
	for i in 24:
		board._run_grace[1] = 1.0
		board._advance(1.0 / BoardView.RUN_FPS)
		seen[board._merc_frame(s.units[1])["frame"]] = true
	check(seen.size() == BoardView.RUN_FRAMES, "the full six-frame run cycle plays")
	board.free()


func test_tracers_persist_until_cleared_and_respect_cover_and_fog() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(2, 5))
	add_unit(s, 2, 1, Vector2i(6, 5))
	var board := BoardView.new()
	var hit: Array[Dictionary] = [{"type": "shot", "tick": 4, "unit": 1, "target": 2, "result": "hit", "damage": 1}]
	board.record_tracers(hit, s)
	var none: Array[Dictionary] = []
	board.show_frame(s, none, none)
	board._advance(5.0)
	check(board.tracer_count() == 1, "a tracer is still there long after its shot")
	check((board._tracers[0]["b"] as Vector2).is_equal_approx(Vector2(6.5, 5.5)), "a hit tracer reaches the target")
	var blocked: Array[Dictionary] = [{"type": "shot", "tick": 5, "unit": 1, "target": 2, "result": "blocked"}]
	board.record_tracers(blocked, s)
	check((board._tracers[1]["b"] as Vector2).is_equal_approx(Vector2(6.0, 5.5)), "a blocked tracer stops half a tile short, at the cover")
	var fog := {"tiles": {}, "units": {1: true}}
	board.record_tracers(hit, s, fog)
	var b: Vector2 = board._tracers[2]["b"]
	check(b.distance_to(Vector2(2.5, 5.5)) <= BoardView.TRACER_STUB + 0.001, "a hidden target only gets a short stub")
	var morale: Array[Dictionary] = [{"type": "morale", "tick": 4, "unit": 2, "roll": 3, "need": 4, "result": "steady"}]
	board.record_tracers(morale, s)
	check(board._status.get(2, "") == "steady", "a morale result marks the unit for the round")
	board.clear_tracers()
	check(board.tracer_count() == 0 and board._status.is_empty(), "the next Go clears tracers and status marks")
	board.free()


func test_morale_log_hides_the_roll_and_target_number() -> void:
	var ev := {"type": "morale", "tick": 4, "unit": 2, "roll": 3, "need": 7, "result": "steady"}
	var text := ReplayModel.describe(ev)
	check(text.contains("steady") and not text.contains("rolled") and not text.contains("needed") and not text.contains("7"), "the log says only steady or broken")


func test_sprite_keys_map_every_unit_kind() -> void:
	check(UnitSprites.key_for(1, 0, false) == "warden" and UnitSprites.key_for(12, 0, false) == "wren", "player slots map to their merc")
	check(UnitSprites.key_for(4, 0, true) == "hollow", "a hollowed player slot draws as a hollow")
	check(UnitSprites.key_for(200, 1, false) == "conscript" and UnitSprites.key_for(211, 1, false) == "regular" and UnitSprites.key_for(220, 1, false) == "veteran", "enemy tiers by id range")
	check(UnitSprites.key_for(300, 1, true) == "hollow" and UnitSprites.key_for(321, 1, true) == "hollow", "enemy hollows by id range")
	check(UnitSprites.key_for(101, 1, false) == "clerk" and UnitSprites.key_for(106, 1, false) == "usher" and UnitSprites.key_for(100, 1, false) == "orrick", "the Writ and the Provost")
	check(UnitSprites.key_for(5, 1, false) == "regular", "skirmish enemies (ids 4-6) fall back to the regular")
	check(UnitSprites.key_for(99, 0, false) == "warden", "an unknown player id falls back to the Warden")


func test_every_sprite_key_has_its_full_art() -> void:
	for key in UnitSprites.all_keys():
		var missing: Array[String] = []
		for frame in ["se", "sw", "ne", "nw", "idle0", "walk0", "walk1", "aim", "fire", "hit", "fall", "dead"]:
			if not ResourceLoader.exists("res://assets/mercs/%s_%s.png" % [key, frame]):
				missing.append(frame)
		check(missing.is_empty(), "%s has every pose (missing %s)" % [key, missing])


func test_a_missing_run_cycle_falls_back_to_walking() -> void:
	check(BoardView._merc_texture("no_such_set", "run_0") == null, "an unknown set has no run frame")
	var s := make_state()
	var clerk := add_unit(s, 101, 1, Vector2i(5, 5))
	var board := BoardView.new()
	var none: Array[Dictionary] = []
	board.show_frame(s, none, none)
	board._run_grace[101] = 1.0
	board._facing[101] = "se"
	check(String(board._merc_frame(clerk)["frame"]).begins_with("run_"), "the Writ run too now")
	board.free()


func test_north_facing_units_run_with_their_own_frames() -> void:
	var s := make_state()
	var warden := add_unit(s, 1, 0, Vector2i(5, 5))
	var board := BoardView.new()
	var none: Array[Dictionary] = []
	board.show_frame(s, none, none)
	board._run_grace[1] = 1.0
	board._facing[1] = "ne"
	var look: Dictionary = board._merc_frame(warden)
	check(String(look["frame"]).begins_with("runn_") and not look["flip"], "running up-right uses the away-from-camera cycle")
	board._facing[1] = "nw"
	look = board._merc_frame(warden)
	check(String(look["frame"]).begins_with("runn_") and look["flip"], "up-left is the same cycle mirrored")
	board._pose[1] = {"name": "fire", "left": 0.3}
	check(board._merc_frame(warden)["frame"] == "nw", "a unit firing while facing away shows its static sprite")
	board.free()


func test_every_sprite_set_has_all_run_cycles() -> void:
	for key in UnitSprites.all_keys():
		var missing: Array[String] = []
		for i in 6:
			for prefix in ["run_", "runn_"]:
				if not ResourceLoader.exists("res://assets/mercs/%s_%s%d.png" % [key, prefix, i]):
					missing.append("%s%d" % [prefix, i])
		check(missing.is_empty(), "%s has both run cycles (missing %s)" % [key, missing])
