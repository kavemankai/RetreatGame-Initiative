extends TestBase
## Enemy AI: scoring, coordination, fairness, determinism.


func test_ai_profiles_load_from_data_file() -> void:
	var res := SimAIProfile.load_file("res://data/ai_profiles.json")
	check((res["errors"] as Array).is_empty(), "profile file loads with no errors: %s" % [res["errors"]])
	for name in ["default", "aggressor", "defender"]:
		check((res["profiles"] as Dictionary).has(name), "profile '%s' exists" % name)
	check(res["profiles"]["defender"].preferred_range > res["profiles"]["aggressor"].preferred_range, "defenders prefer a longer range than aggressors")


func test_ai_profile_validation_rejects_bad_input() -> void:
	check(not SimAIProfile.from_dict({"w_damage": 10, "bogus": 1})["errors"].is_empty(), "unknown key is rejected")
	check(not SimAIProfile.from_dict({"w_damage": 1.5})["errors"].is_empty(), "non-integer weight is rejected")
	check(not SimAIProfile.from_dict({"w_damage": "ten"})["errors"].is_empty(), "string weight is rejected")
	var ok := SimAIProfile.from_dict({"w_damage": 7})
	check(ok["errors"].is_empty() and ok["profile"].w_damage == 7 and ok["profile"].w_kill > 0, "partial dicts fill in defaults")


func test_ai_shoots_visible_enemy_in_range() -> void:
	var s := make_state()
	add_unit(s, 1, 1, Vector2i(8, 5))
	add_unit(s, 2, 0, Vector2i(4, 5))
	var p := SimAI.plan_for(s, 1, ai_profiles())
	check(actions_of(p, 1, "shoot").size() == 1 and actions_of(p, 1, "shoot")[0].target_id == 2, "AI shoots the visible enemy")


func test_ai_prefers_the_kill() -> void:
	var s := make_state()
	add_unit(s, 1, 1, Vector2i(8, 5))
	add_unit(s, 5, 0, Vector2i(4, 4), 1)
	add_unit(s, 6, 0, Vector2i(4, 6), 3)
	var p := SimAI.plan_for(s, 1, ai_profiles())
	var targets := actions_of(p, 1, "shoot").map(func(a: SimAction) -> int: return a.target_id)
	check(targets == [5], "AI targets the 1 hp enemy it can kill; got %s" % [targets])


func test_ai_does_not_overkill_a_doomed_target() -> void:
	var s := make_state()
	add_unit(s, 1, 1, Vector2i(8, 5))
	add_unit(s, 3, 1, Vector2i(8, 6))
	add_unit(s, 2, 0, Vector2i(4, 5), 1)
	var p := SimAI.plan_for(s, 1, ai_profiles())
	var total := actions_of(p, 1, "shoot").size() + actions_of(p, 3, "shoot").size()
	check(total == 1, "only one teammate shoots a 1 hp enemy; got %d shots" % total)


func test_ai_moves_to_cover_before_shooting() -> void:
	var s := make_state()
	s.grid.set_edge(Vector2i(4, 6), Vector2i(5, 6), SimConst.EDGE_HALF)
	add_unit(s, 1, 1, Vector2i(4, 5))
	add_unit(s, 2, 0, Vector2i(9, 5))
	var p := SimAI.plan_for(s, 1, ai_profiles())
	var acts: Array = p.orders[1]
	check(acts.size() == 2 and acts[0].type == "move" and acts[0].dir == Vector2i.DOWN and acts[1].type == "shoot", "AI steps into cover then shoots; got %s" % plan_sig(p))


func test_ai_advances_on_objective_when_no_enemy_visible() -> void:
	var s := make_state()
	add_unit(s, 1, 1, Vector2i(10, 5))
	var p := SimAI.plan_for(s, 1, ai_profiles(), {}, Vector2i(2, 5))
	var moves := actions_of(p, 1, "move")
	check(moves.size() >= 3, "AI marches toward the objective; got %s" % plan_sig(p))
	var pos := Vector2i(10, 5)
	for m: SimAction in moves:
		pos += m.dir
	check(SimLos.chebyshev(pos, Vector2i(2, 5)) < 8, "it ends closer to the objective than it started")
	check(p.validate(s).is_empty(), "the march is a legal plan")


func test_ai_defender_holds_overwatch_when_nothing_to_shoot() -> void:
	var s := make_state()
	var u := add_unit(s, 1, 1, Vector2i(10, 5))
	u.weapon_range = 2  # cannot reach anything this turn
	add_unit(s, 2, 0, Vector2i(2, 5))
	var holder := {"default": SimAIProfile.from_dict({"w_exposed": 10, "w_cover": 5, "preferred_range": 8, "w_range": 3, "w_objective": 0, "w_watch": 2})["profile"]}
	var p := SimAI.plan_for(s, 1, holder)
	var ow := actions_of(p, 1, "overwatch")
	check(ow.size() == 1 and ow[0].dir == Vector2i.LEFT, "defender holds overwatch facing the enemy; got %s" % plan_sig(p))


func test_ai_ignores_hidden_enemies_entirely() -> void:
	var with_a := hidden_enemy_scene(Vector2i(3, 5))
	var with_b := hidden_enemy_scene(Vector2i(3, 8))
	var without := hidden_enemy_scene(null)
	check(not SimVision.visible_unit_ids(with_a, 1).has(9), "setup: the 1 hp enemy really is hidden")
	check(SimLos.can_shoot(with_a.grid, Vector2i(8, 5), Vector2i(3, 5)) and SimLos.chebyshev(Vector2i(8, 5), Vector2i(3, 5)) <= with_a.units[1].max_range(), "setup: it is within weapon range and line of fire")
	var sig := plan_sig(SimAI.plan_for(without, 1, ai_profiles()))
	check(plan_sig(SimAI.plan_for(with_a, 1, ai_profiles())) == sig, "a hidden enemy in weapon range does not change the plan")
	check(plan_sig(SimAI.plan_for(with_b, 1, ai_profiles())) == sig, "nor does moving it elsewhere")
	for id in SimAI.plan_for(with_a, 1, ai_profiles()).orders:
		for act: SimAction in SimAI.plan_for(with_a, 1, ai_profiles()).orders[id]:
			check(act.target_id != 9, "AI never targets a hidden unit")


func test_ai_plans_are_legal_under_fog_fuzz() -> void:
	var profiles := ai_profiles()
	var bad := 0
	for i in 25:
		var s := make_state(12, 12)
		for e in 6:
			var a := Vector2i(_rnd(11), _rnd(11))
			var kind := SimConst.EDGE_FULL if _rnd(2) == 0 else SimConst.EDGE_HALF
			s.grid.set_edge(a, a + (Vector2i.RIGHT if _rnd(2) == 0 else Vector2i.DOWN), kind)
		var taken := {}
		for id in range(1, 7):
			var pos := Vector2i(_rnd(12), _rnd(12))
			while taken.has(pos):
				pos = Vector2i(_rnd(12), _rnd(12))
			taken[pos] = true
			add_unit(s, id, 0 if id <= 3 else 1, pos, 1 + _rnd(3), 2 + _rnd(6), 3 + _rnd(7), 3 + _rnd(6))
		for team in [0, 1]:
			var p := SimAI.plan_for(s, team, profiles, {}, Vector2i(_rnd(12), _rnd(12)))
			if not p.validate(s).is_empty() or not p.validate_fog(s).is_empty():
				bad += 1
				printerr("  fuzz %d team %d illegal: %s %s" % [i, team, p.validate(s), p.validate_fog(s)])
	check(bad == 0, "all 50 fuzzed AI plans pass validate and validate_fog")


func test_ai_is_deterministic() -> void:
	var sc := Scenarios.build(4)
	var p1 := SimAI.plan_for(sc["state"], 1, ai_profiles(), {}, Vector2i(1, 5))
	var p2 := SimAI.plan_for(sc["state"], 1, ai_profiles(), {}, Vector2i(1, 5))
	check(plan_sig(p1) == plan_sig(p2) and not plan_sig(p1).is_empty(), "same state => same non-empty plan")


func test_ai_vs_ai_match_runs_and_is_reproducible() -> void:
	var start: SimState = Scenarios.build(4)["state"]
	var a := Scenarios.play_ai_turns(start, 6)
	var b := Scenarios.play_ai_turns(start, 6)
	check(snapshot(a) == snapshot(b), "6 AI-vs-AI turns reproduce exactly")
	check(snapshot(a) != snapshot(start), "the match actually changes the board")
	check(start.turn == 0, "the starting state is not mutated")


func test_plan_merge_combines_orders() -> void:
	var a := plan_of(1, [SimAction.wait(2)])
	var b := plan_of(2, [SimAction.wait(3)])
	var m := a.merged(b)
	check(m.orders.size() == 2 and a.orders.size() == 1, "merged plan holds both sides; inputs untouched")


func test_shot_value_is_weighted_by_hit_chance() -> void:
	var s := make_state(20, 10)
	var shooter := add_unit(s, 1, 1, Vector2i(10, 5), 3, 5, 5)
	var far := add_unit(s, 5, 0, Vector2i(5, 5), 3)    # 5 tiles: low chance
	var near := add_unit(s, 6, 0, Vector2i(8, 5), 3)   # 2 tiles: high chance
	var prof: SimAIProfile = ai_profiles()["default"]
	var ctx := {"view": s, "planned_damage": {}, "enemies": [far, near]}
	var shot := SimAI._best_shot(ctx, shooter, shooter.pos, prof)
	check(shot["target"] == 6, "equal damage and hp: the closer, likelier shot wins; got %s" % [shot])
	var only_far := SimAI._best_shot({"view": s, "planned_damage": {}, "enemies": [far]}, shooter, shooter.pos, prof)
	var only_near := SimAI._best_shot({"view": s, "planned_damage": {}, "enemies": [near]}, shooter, shooter.pos, prof)
	check(only_near["value"] > only_far["value"], "the same shot is worth more at a higher chance")
	var scale := (prof.w_damage * 1 + 0) * shooter.hit_chance_at(5) / 100
	check(only_far["value"] == scale, "value is (damage weight) times chance in percent; got %d want %d" % [only_far["value"], scale])
