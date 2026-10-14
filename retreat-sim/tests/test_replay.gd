extends TestBase
## Replay model and scenario sanity.


func test_replay_tick_zero_is_start() -> void:
	var sc := Scenarios.build(0)
	var r := SimResolver.resolve(sc["state"], sc["plan"])
	var m := ReplayModel.new(sc["state"], sc["plan"], r)
	check(snapshot(m.state_at(0)) == snapshot(sc["state"]), "tick 0 equals the starting state")


func test_replay_final_tick_matches_resolver_for_all_scenarios() -> void:
	for i in Scenarios.count():
		var sc := Scenarios.build(i)
		var r := SimResolver.resolve(sc["state"], sc["plan"])
		var m := ReplayModel.new(sc["state"], sc["plan"], r)
		check(snapshot(m.state_at(SimConst.TICKS_PER_TURN)) == snapshot(r.state), "scenario '%s': replay end == resolver state" % sc["name"])


func test_replay_intermediate_tick() -> void:
	var s := overwatch_scene()
	var p := mover_plan()
	var r := SimResolver.resolve(s, p)
	var m := ReplayModel.new(s, p, r)
	check(m.state_at(1).units[2].pos == Vector2i(0, 5), "before the first step completes the mover has not moved")
	check(m.state_at(2).units[2].pos == Vector2i(1, 5) and m.state_at(2).units[2].hp == 2, "tick 2: moved and shot")
	var types: Array = m.events_at(2).map(func(e): return e["type"])
	check(types == ["move", "shot", "morale"], "tick 2: move, overwatch shot, then the hit unit's morale check; got %s" % [types])


func test_replay_watchers_follow_hold_window_and_spent() -> void:
	var s := overwatch_scene()
	var p := mover_plan(3, 4)
	var r := SimResolver.resolve(s, p)
	var m := ReplayModel.new(s, p, r)
	var w1 := m.watchers_at(1)
	check(w1.size() == 1 and w1[0]["id"] == 1 and not w1[0]["spent"], "watch is active and unspent at tick 1")
	check(m.watchers_at(2)[0]["spent"], "watch is spent after it fired on tick 2")
	check(m.watchers_at(5).is_empty(), "no watch after the 4-tick hold ends")


func test_scenarios_produce_legal_plans() -> void:
	for i in Scenarios.count():
		var sc := Scenarios.build(i)
		var errs: Array[String] = sc["plan"].validate(sc["state"])
		check(errs.is_empty(), "scenario '%s' plan is legal %s" % [sc["name"], errs])


func test_replay_drops_the_cone_of_a_watcher_hit_into_suppression() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(2, 5), 3, 7)
	add_unit(s, 2, 1, Vector2i(5, 5), 3, 5)
	s.units[2].morale = 99
	var p := SimPlan.new()
	p.add(1, SimAction.shoot(2))
	p.add(2, SimAction.overwatch(Vector2i.DOWN, T))
	var m := ReplayModel.new(s, p, SimResolver.resolve(s, p))
	check(m.watchers_at(2).size() == 1, "the watch is up before the hit")
	check(m.watchers_at(10).is_empty(), "after the morale check the cone is gone")
