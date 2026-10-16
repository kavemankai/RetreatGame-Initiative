extends TestBase
## The initiative ruleset: action points, one merc at a time, JA2-style interrupts.


func new_match(w := 16, h := 12) -> InitiativeMatch:
	var s := make_state(w, h)
	return InitiativeMatch.new(s, SimAIProfile.load_file(SimMatch.PROFILE_FILE)["profiles"], {})


func mover(m: InitiativeMatch, id := 1, pos := Vector2i(2, 2), speed := 5, aim := 5) -> SimUnit:
	return add_unit(m.state, id, 0, pos, 3, speed, aim)


func foe(m: InitiativeMatch, id := 200, pos := Vector2i(10, 2), speed := 5, aim := 5) -> SimUnit:
	return add_unit(m.state, id, 1, pos, 3, speed, aim)


func events(beats: Array[Dictionary]) -> Array:
	var out: Array = []
	for b in beats:
		out.append_array(b["events"])
	return out


func test_a_turn_starts_with_a_full_ap_pool_for_the_active_side() -> void:
	var m := new_match()
	mover(m)
	foe(m)
	m.start()
	check(m.active_team == 0 and m.turn == 1, "the player moves first")
	check(m.ap_of(1) == SimConst.AP_PER_TURN, "a merc starts the turn with the round's ticks as AP")
	var stressed: SimUnit = m.state.units[1]
	stressed.stress_penalty = 4
	m.start()
	check(m.ap_of(1) == SimConst.AP_PER_TURN - 4, "stress still shortens the pool")


func test_moving_spends_ap_step_by_step_and_updates_the_board() -> void:
	var m := new_match()
	mover(m)
	foe(m, 200, Vector2i(14, 10))
	m.start()
	var beats := m.move(1, Vector2i(5, 2))
	check(m.state.units[1].pos == Vector2i(5, 2), "the merc arrives")
	check(m.ap_of(1) == SimConst.AP_PER_TURN - 3 * SimConst.COST_ORTHO, "three straight steps cost 6 AP")
	var moves := events(beats).filter(func(e): return e["type"] == "move")
	check(moves.size() == 3 and beats.size() == 3, "one beat per step, so the screen can animate it")
	check((beats[0]["state"] as SimState).units[1].pos == Vector2i(3, 2) and (beats[2]["state"] as SimState).units[1].pos == Vector2i(5, 2), "each beat carries the board as it stood")


func test_reach_and_move_respect_the_ap_left() -> void:
	var m := new_match()
	mover(m)
	foe(m, 200, Vector2i(14, 10))
	m.start()
	var reach := m.reach(1)
	check(reach.has(Vector2i(9, 2)) and not reach.has(Vector2i(10, 2)), "seven straight steps (14 AP) is the limit")
	check(m.move(1, Vector2i(14, 2)).is_empty() and m.state.units[1].pos == Vector2i(2, 2), "an unreachable tile does nothing")
	m.move(1, Vector2i(7, 2))
	check(not m.reach(1).has(Vector2i(10, 2)) and m.ap_of(1) == 4, "AP falls as the merc moves")


func test_shooting_costs_ap_and_follows_the_hit_rules() -> void:
	var m := new_match()
	mover(m, 1, Vector2i(2, 2), 5, 5)
	foe(m, 200, Vector2i(5, 2))
	m.start()
	var pv := m.shot_preview(1, 200)
	check(pv["result"] == "hit" and pv["chance"] == 66 and pv["cost"] == 4, "preview: 66% for 4 AP; got %s" % [pv])
	var beats := m.shoot(1, 200)
	check(m.ap_of(1) == SimConst.AP_PER_TURN - 4, "the shot costs its ticks in AP")
	check(m.state.units[200].hp == 2 and events(beats).any(func(e): return e["type"] == "shot" and e["result"] == "hit"), "a hit hurts (test dice always hit)")
	m.state.grid.set_edge(Vector2i(4, 2), Vector2i(5, 2), SimConst.EDGE_HALF)
	var covered := m.shoot(1, 200)
	check(events(covered).any(func(e): return e["type"] == "shot" and e["result"] == "hit"), "a shot into cover can still land (test dice always hit)")
	check(m.ap_of(1) == SimConst.AP_PER_TURN - 8 and m.state.units[200].hp == 1, "it cost its AP and hurt")
	check(m.shot_preview(1, 200)["chance"] == 66 - SimConst.COVER_HIT_PENALTY, "but the preview shows the lower chance")


func test_a_merc_cannot_shoot_without_ap_range_or_sight() -> void:
	var m := new_match()
	mover(m, 1, Vector2i(2, 2))
	foe(m, 200, Vector2i(14, 2))
	m.start()
	check(m.shoot(1, 200).is_empty(), "out of range: refused")
	m.state.units[1].pos = Vector2i(8, 2)
	m.ap[1] = 3
	check(m.shoot(1, 200).is_empty(), "3 AP is not enough for a 4 AP shot")


func test_a_quicker_defender_interrupts_the_first_sighting_and_stops_the_mover() -> void:
	var m := new_match()
	mover(m, 1, Vector2i(2, 2), 5, 5)
	var f := foe(m, 200, Vector2i(11, 2), 7, 6)  # quicker than the mover
	f.sight_range = 6
	m.start()
	var beats := m.move(1, Vector2i(9, 2))
	var shots := events(beats).filter(func(e): return e["type"] == "shot")
	check(shots.size() == 1 and shots[0]["unit"] == 200 and shots[0]["target"] == 1, "the foe interrupts with a shot")
	check(m.state.units[1].pos.x < 9, "the mover is stopped short of its destination: at %s" % [m.state.units[1].pos])
	var stopped_at: Vector2i = m.state.units[1].pos
	var again := events(m.move(1, Vector2i(9, 2)))
	check(again.filter(func(e): return e["type"] == "shot").is_empty(), "the same foe cannot interrupt the same merc again this turn")
	check(m.state.units[1].pos.x > stopped_at.x, "the mover carries on afterwards")


func test_a_slower_defender_cannot_interrupt() -> void:
	var m := new_match()
	mover(m, 1, Vector2i(2, 2), 8, 5)
	var f := foe(m, 200, Vector2i(11, 2), 2, 5)  # much slower
	f.sight_range = 6
	m.start()
	var beats := m.move(1, Vector2i(9, 2))
	check(events(beats).filter(func(e): return e["type"] == "shot").is_empty(), "no interrupt from a slower unit")
	check(m.state.units[1].pos == Vector2i(9, 2), "the mover walks on")


func test_interrupts_need_sight_and_a_reaction() -> void:
	var m := new_match()
	mover(m, 1, Vector2i(2, 2), 5, 5)
	foe(m, 200, Vector2i(11, 2), 7, 6)
	m.start()
	m.reaction[200] = 0
	check(events(m.move(1, Vector2i(8, 2))).filter(func(e): return e["type"] == "shot").is_empty(), "no reaction AP, no interrupt")
	var walled := new_match()
	mover(walled, 1, Vector2i(2, 2), 5, 5)
	foe(walled, 200, Vector2i(11, 2), 7, 6)
	walled.state.grid.set_blocked(Vector2i(9, 2))  # a crate in the way: no line
	walled.start()
	check(events(walled.move(1, Vector2i(8, 2))).filter(func(e): return e["type"] == "shot").is_empty(), "no line of sight, no interrupt")


func test_overwatch_shoots_anyone_who_moves_in_its_cone_not_only_new_sightings() -> void:
	var m := new_match()
	mover(m, 1, Vector2i(5, 2), 8, 5)
	foe(m, 200, Vector2i(11, 2), 2, 5)  # slow, so only a watch can fire
	m.state.units[200].sight_range = 8
	m.start()
	m.watch[200] = Vector2i(-1, 0)
	var beats := m.move(1, Vector2i(6, 2))
	check(events(beats).filter(func(e): return e["type"] == "shot" and e["unit"] == 200).size() == 1, "the watcher fires at a mover already in view")
	check(not m.watch.has(200), "the watch is spent")


func test_ending_the_turn_runs_the_enemy_then_refills_the_players() -> void:
	var m := new_match()
	mover(m, 1, Vector2i(5, 2), 5, 5)
	foe(m, 200, Vector2i(9, 2), 5, 5)
	m.start()
	m.move(1, Vector2i(5, 3))
	var beats := m.end_turn()
	check(not beats.is_empty() and events(beats).any(func(e): return e["unit"] == 200), "the enemy acted")
	check(m.turn == 2 and m.active_team == 0, "round 2, player to move")
	check(m.ap_of(1) == SimConst.AP_PER_TURN, "AP refilled")


func test_a_hit_triggers_morale_steady_cannot_shoot_broken_loses_ap() -> void:
	var m := new_match()
	mover(m, 1, Vector2i(2, 2))
	mover(m, 2, Vector2i(2, 4))
	var f := foe(m, 200, Vector2i(6, 2))
	var g := foe(m, 201, Vector2i(6, 4))
	f.morale = 99  # always steady
	g.morale = -99  # always broken
	m.start()
	m.shoot(1, 200)
	m.shoot(2, 201)
	check(m.is_suppressed(200) and not m.is_broken(200), "a steady unit is suppressed")
	check(m.is_broken(201), "a broken unit is broken")


func test_reinforcements_and_goals_work_in_this_mode_too() -> void:
	var m := new_match()
	mover(m, 1, Vector2i(14, 1))
	foe(m, 200, Vector2i(3, 3))
	m.goal = SimGoal.new({"type": "hold", "zone": "LOCK", "clear": "SPINE"}, {"LOCK": [Vector2i(14, 1)], "SPINE": [Vector2i(10, 1)]})
	var late := SimUnit.make(201, 1, Vector2i(8, 8), 3, 5, 4)
	m.reinforcements = [{"round": 2, "unit": late}]
	m.start()
	m.end_turn()
	check(m.winner == 0, "holding the lock to the end of the round wins")
	var m2 := new_match()
	mover(m2, 1, Vector2i(2, 2))
	foe(m2, 200, Vector2i(12, 10))
	m2.reinforcements = [{"round": 2, "unit": SimUnit.make(201, 1, Vector2i(8, 8), 3, 5, 4)}]
	m2.start()
	m2.end_turn()
	check(m2.state.units.has(201) and m2.notices.any(func(n): return String(n).to_lower().contains("reinforcement")), "reinforcements arrive at round 2")


func test_winning_by_elimination_ends_the_match_immediately() -> void:
	var m := new_match()
	mover(m, 1, Vector2i(2, 2))
	var f := foe(m, 200, Vector2i(5, 2))
	f.hp = 1
	m.start()
	m.shoot(1, 200)
	check(m.winner == 0 and not m.state.units[200].alive, "killing the last enemy wins")
	check(m.move(1, Vector2i(3, 2)).is_empty(), "no more actions once it is over")


func test_the_mode_is_deterministic_with_real_dice() -> void:
	var logs: Array = []
	for rep in 2:
		var m := new_match()
		m.state.fixed_roll = -1
		m.state.seed = 9
		mover(m, 1, Vector2i(2, 2), 5, 5)
		foe(m, 200, Vector2i(9, 2), 5, 5)
		m.start()
		var all: Array = []
		all.append_array(events(m.move(1, Vector2i(5, 2))))
		all.append_array(events(m.shoot(1, 200)) if m.shot_preview(1, 200)["result"] != "invalid" else [])
		all.append_array(events(m.end_turn()))
		logs.append(str(all))
	check(logs[0] == logs[1], "same inputs and seed, same events")


func test_reach_is_computed_on_the_fog_view_and_a_hidden_unit_blocks_the_move() -> void:
	var m := new_match()
	mover(m, 1, Vector2i(2, 2))
	var hidden := foe(m, 200, Vector2i(5, 2), 2, 5)  # slow, so it cannot interrupt as the merc bumps into it
	hidden.sight_range = 1
	m.state.units[1].sight_range = 2  # cannot see (5, 2) from (2, 2)
	m.start()
	check(m.reach(1).has(Vector2i(5, 2)), "the hidden foe's tile looks free to the player")
	var beats := m.move(1, Vector2i(6, 2))
	check(events(beats).any(func(e): return e["type"] == "move_blocked"), "walking into it stops the move")
	check(m.state.units[1].pos.x < 5, "and the merc did not pass through")


func test_from_match_carries_the_map_goal_roles_and_sentry_watches() -> void:
	var c := Campaign.new_game(StoryData.load_dir("res://data/story")["data"])
	var sm := MissionBuilder.build(c, "karsa_breakout", [1, 2, 3])
	var m := InitiativeMatch.from_match(sm)
	m.start()
	check(m.goal != null and m.theme == sm.theme and m.state.units.size() == sm.state.units.size(), "goal, theme and units carry over")
	var watching := 0
	for id in m.state.units:
		if m.watch.has(id):
			watching += 1
	check(watching == 1, "the Karsa sentry starts on watch")


func test_route_preview_shows_running_cost_and_steps_a_quicker_foe_would_shoot_first() -> void:
	var m := new_match(20, 8)
	mover(m, 1, Vector2i(2, 4), 4, 4).sight_range = 9
	foe(m, 200, Vector2i(11, 4), 8, 8).sight_range = 8
	m.start()
	var route := m.route_preview(1, Vector2i(6, 4))
	check(route.size() == 4 and int(route[3]["cost"]) == 4 * SimConst.COST_ORTHO, "the cost runs step by step")
	var first_threat := -1
	for i in route.size():
		if not (route[i]["threats"] as Array).is_empty():
			first_threat = i
			break
	check(first_threat >= 0 and route[first_threat]["threats"][0] == 200, "the foe is flagged where it gets its first clear shot")
	var slow := new_match(20, 8)
	mover(slow, 1, Vector2i(2, 4), 8, 8).sight_range = 9
	foe(slow, 200, Vector2i(11, 4), 2, 2).sight_range = 8
	slow.start()
	var safe := true
	for step in slow.route_preview(1, Vector2i(6, 4)):
		safe = safe and (step["threats"] as Array).is_empty()
	check(safe, "a slower foe never flags: it would not interrupt")


func test_route_preview_matches_what_move_does() -> void:
	var m := new_match(20, 8)
	mover(m, 1, Vector2i(2, 4), 4, 4).sight_range = 9
	foe(m, 200, Vector2i(11, 4), 8, 8).sight_range = 8
	m.start()
	var route := m.route_preview(1, Vector2i(6, 4))
	var flagged := -1
	for i in route.size():
		if not (route[i]["threats"] as Array).is_empty():
			flagged = i
			break
	m.move(1, Vector2i(6, 4))
	check(m.state.units[1].pos == route[flagged]["tile"] or not m.state.units[1].alive, "the mover halts on the step the preview flagged")


func test_a_unit_with_less_than_a_shot_of_ap_left_has_no_reaction_shot() -> void:
	var m := new_match(20, 8)
	mover(m, 1, Vector2i(2, 4), 4, 4).sight_range = 9
	var f := foe(m, 200, Vector2i(11, 4), 8, 8)
	f.sight_range = 8
	m.start()
	check(int(m.reaction.get(200, 0)) > 0, "the enemy starts fresh, so it can react on turn 1")
	# Spend the merc nearly dry, then pass: its side then has no reaction left at the enemy's turn.
	m.ap[1] = 3
	m.end_turn()
	check(m.turn == 2, "the turn passed")
	var dry := new_match(20, 8)
	mover(dry, 1, Vector2i(2, 4), 4, 4)
	foe(dry, 200, Vector2i(11, 4), 8, 8)
	dry.start()
	dry.ap[1] = 3
	dry._begin_turn(dry.ai_team)
	check(int(dry.reaction.get(1, 0)) == 0, "3 AP is less than a shot: no reaction")
	var ready := new_match(20, 8)
	mover(ready, 1, Vector2i(2, 4), 4, 4)
	foe(ready, 200, Vector2i(11, 4), 8, 8)
	ready.start()
	ready.ap[1] = 8
	ready._begin_turn(ready.ai_team)
	check(int(ready.reaction.get(1, 0)) == ready.state.units[1].shot_ticks(), "8 AP keeps its reaction shot")
