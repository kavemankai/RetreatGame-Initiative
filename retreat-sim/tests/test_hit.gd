extends TestBase
## Hit chances: the formula, the seeded roll, misses.


func real_dice(s: SimState) -> SimState:
	s.fixed_roll = -1  # use the seeded dice, not the test hook TestBase installs
	return s


func duel_at(dist: int, aim_a := 5) -> SimState:
	var s := real_dice(make_state(20, 10))
	add_unit(s, 1, 0, Vector2i(2, 5), 5, 7, aim_a)
	add_unit(s, 2, 1, Vector2i(2 + dist, 5), 9, 5)
	return s


func test_chance_formula_values_and_clamps() -> void:
	var u := SimUnit.make(1, 0, Vector2i.ZERO, 3, 5, 5)
	check(u.hit_chance_at(2) == 70 and u.hit_chance_at(3) == 66, "aim 5: 70 up close, 66 at 3 tiles")
	u.aim = 9
	check(u.hit_chance_at(6) == 82, "aim 9 at 6 tiles is 82")
	u.aim = 3
	check(u.hit_chance_at(7) == 36, "aim 3 at 7 tiles is 36")
	u.aim = 1
	check(u.hit_chance_at(30) == SimConst.HIT_MIN, "never below the floor")
	u.aim = 99
	check(u.hit_chance_at(1) == SimConst.HIT_MAX, "never above the ceiling")
	u.aim = 5
	u.hit_bonus = 10
	check(u.hit_chance_at(2) == 80, "gear accuracy adds points")


func test_chance_rises_with_aim_and_falls_with_range() -> void:
	var u := SimUnit.make(1, 0, Vector2i.ZERO, 3, 5, 4)
	var last := 0
	var rises := true
	for aim in range(1, 10):
		u.aim = aim
		var c := u.hit_chance_at(4)
		rises = rises and c >= last
		last = c
	check(rises, "monotonic in aim")
	u.aim = 5
	var falls := true
	var prev := 100
	for d in range(1, 12):
		var c := u.hit_chance_at(d)
		falls = falls and c <= prev
		prev = c
	check(falls, "monotonic in distance")


func test_evaluate_shot_reports_the_chance_and_cover_lowers_it() -> void:
	var s := duel_at(3)
	var r := SimResolver.evaluate_shot(s.grid, s.units[1], s.units[1].pos, s.units[2])
	check(r["result"] == "hit" and r["chance"] == 66, "a clear line returns the chance")
	s.grid.set_edge(Vector2i(4, 5), Vector2i(5, 5), SimConst.EDGE_HALF)
	var covered := SimResolver.evaluate_shot(s.grid, s.units[1], s.units[1].pos, s.units[2])
	check(covered["result"] == "hit" and covered["cover"] == true and covered["chance"] == 66 - SimConst.COVER_HIT_PENALTY, "cover takes %d%% off the chance, it does not block (%s)" % [SimConst.COVER_HIT_PENALTY, covered])


func test_d100_is_stateless_in_range_and_covers_the_faces() -> void:
	check(SimDice.d100(3, 1, 2, 4, 1000) == SimDice.d100(3, 1, 2, 4, 1000), "same inputs, same roll")
	var lo := 100
	var hi := 1
	for i in 600:
		var v := SimDice.d100(7, 1, i % 20 + 1, i, 1000 + i)
		lo = mini(lo, v)
		hi = maxi(hi, v)
	check(lo >= 1 and hi <= 100 and lo <= 5 and hi >= 95, "1..100, using the whole range")


func test_hits_and_misses_follow_the_roll_and_misses_do_no_harm() -> void:
	var hits := 0
	var misses := 0
	for seed in range(1, 80):
		var s := duel_at(3)
		s.seed = seed
		var r := SimResolver.resolve(s, plan_of(1, [SimAction.shoot(2)]))
		var shot: Dictionary = events_of(r, "shot")[0]
		if shot["result"] == "hit":
			hits += 1
			check(r.state.units[2].hp == 8, "a hit does damage")
		else:
			misses += 1
			check(shot["result"] == "miss" and r.state.units[2].hp == 9, "a miss does none")
			check(events_of(r, "morale").is_empty(), "and causes no morale check")
	check(hits > 30 and misses > 10, "about two thirds land across seeds; hits %d misses %d" % [hits, misses])


func test_better_aim_hits_more_often() -> void:
	var good := 0
	var poor := 0
	for seed in range(1, 120):
		var a := duel_at(4, 9)
		a.seed = seed
		var b := duel_at(4, 2)
		b.seed = seed
		good += 1 if shots_result(a) == "hit" else 0
		poor += 1 if shots_result(b) == "hit" else 0
	check(good > poor + 20, "aim 9 clearly out-hits aim 2 (%d vs %d)" % [good, poor])


func shots_result(s: SimState) -> String:
	return events_of(SimResolver.resolve(s, plan_of(1, [SimAction.shoot(2)])), "shot")[0]["result"]


func test_a_miss_lets_the_slower_unit_return_fire() -> void:
	var found := false
	for seed in range(1, 80):
		var s := real_dice(make_state())
		s.seed = seed
		add_unit(s, 1, 0, Vector2i(2, 5), 3, 7, 1)  # poor aim: often misses
		add_unit(s, 2, 1, Vector2i(5, 5), 3, 5, 7)  # aim 7: still the usual 4-tick shot
		var p := SimPlan.new()
		p.add(1, SimAction.shoot(2))
		p.add(2, SimAction.shoot(1))
		var shots := events_of(SimResolver.resolve(s, p), "shot")
		if shots.size() == 2 and shots[0]["result"] == "miss" and shots[1]["unit"] == 2:
			found = true
			break
	check(found, "a miss from the faster unit leaves the slower one its shot")


func test_stepping_matches_resolve_with_hit_rolls() -> void:
	for seed in [1, 2, 3, 4, 5, 6]:
		var s := duel_at(4)
		s.seed = seed
		var p := plan_of(1, [SimAction.shoot(2), SimAction.shoot(2)])
		var once := SimResolver.resolve(s, p)
		var run := SimTurn.new(s, p)
		while not run.is_finished():
			run.advance()
		check(once.events == run.events and snapshot(once.state) == snapshot(run.state), "seed %d: stepped equals resolve" % seed)


func test_the_test_hook_forces_a_hit_and_clones() -> void:
	var s := make_state()
	check(s.fixed_roll == 1, "TestBase states roll a fixed 1: legacy tests keep guaranteed hits")
	check(s.clone().fixed_roll == 1, "the hook survives cloning")


func test_preview_text_shows_the_chance() -> void:
	var s := real_dice(make_state(20, 10))
	add_unit(s, 1, 0, Vector2i(2, 5), 3, 5, 5)
	add_unit(s, 2, 1, Vector2i(5, 5), 3, 5, 5)
	var game := SimMatch.new(s, 0, {})
	var ctl := PlayController.new(game)
	ctl.select(1)
	var msg := ctl.hover_info(Vector2i(5, 5))
	check(msg.contains("66%"), "the preview says the exact chance; got '%s'" % msg)


func test_a_miss_tracer_flies_past_the_target_and_stays() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(2, 5))
	add_unit(s, 2, 1, Vector2i(6, 5))
	var board := BoardView.new()
	var miss: Array[Dictionary] = [{"type": "shot", "tick": 4, "unit": 1, "target": 2, "result": "miss", "chance": 60, "roll": 90}]
	board.record_tracers(miss, s)
	var b: Vector2 = board._tracers[0]["b"]
	check(b.x > 6.5 and board._tracers[0]["result"] == "miss", "a miss ends beyond the target")
	board._advance(5.0)
	check(board.tracer_count() == 1, "and stays until the next Go")
	var none: Array[Dictionary] = []
	board.show_frame(s, miss, none)
	check(not board._pose.has(2), "a missed target does not flinch")
	board.free()


func test_cover_really_lowers_the_hit_rate_over_many_rolls() -> void:
	var open := duel_at(3)
	var covered := duel_at(3)
	covered.grid.set_edge(Vector2i(4, 5), Vector2i(5, 5), SimConst.EDGE_HALF)
	var open_hits := 0
	var covered_hits := 0
	for sd in 300:
		for pair in [[open, 0], [covered, 1]]:
			var s: SimState = pair[0]
			s.seed = sd
			s.units[2].hp = 50
			s.units[2].alive = true
			var ev := ShotResolver.fire(s, s.units[1], 2, 1, 1, false)
			if ev[0]["result"] == "hit":
				if pair[1] == 0:
					open_hits += 1
				else:
					covered_hits += 1
	check(open_hits > covered_hits + 300 * 20 / 100, "open %d/300 hits vs covered %d/300: cover costs about 30 points" % [open_hits, covered_hits])
	check(covered_hits > 0, "but a shot into cover still lands sometimes")
