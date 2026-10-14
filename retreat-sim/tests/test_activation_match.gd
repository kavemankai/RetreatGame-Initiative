extends TestBase
## The bridge between the activation engine and the touch screen: ActivationMatch (the
## InitiativeMatch face), ActivationAI (enemy activations through the resolver), the strip data,
## reason wording and the ruleset plumbing.

var story: Dictionary = StoryData.load_dir("res://data/story")["data"]


func sandbox_match(sd := 5) -> ActivationMatch:
	var built := Sandbox.build(story, Sandbox.default_config(story))
	built.state.seed = sd
	var am := ActivationMatch.make(built)
	am.start()
	return am


func small_match(foe_pos := Vector2i(12, 8)) -> ActivationMatch:
	var s := make_state(16, 12)
	add_unit(s, 1, 0, Vector2i(2, 2), 99, 9, 5)  # sturdy: the always-hit test dice must not end the fight
	add_unit(s, 200, 1, foe_pos, 3, 4, 5)
	var m := SimMatch.new(s, 0, SimAIProfile.load_file(SimMatch.PROFILE_FILE)["profiles"], {})
	var am := ActivationMatch.make(m)
	am.start()
	return am


func test_start_leaves_a_player_unit_active_even_when_the_enemy_wins_initiative() -> void:
	var s := make_state(16, 12)
	add_unit(s, 1, 0, Vector2i(2, 2), 3, 2, 2)
	add_unit(s, 200, 1, Vector2i(12, 8), 3, 9, 9)
	var am := ActivationMatch.make(SimMatch.new(s, 0, SimAIProfile.load_file(SimMatch.PROFILE_FILE)["profiles"], {}))
	am.start()
	check(am.active_unit() == 1 and am.active_team == 0, "the fast enemy acted first; now the merc is up")
	check(not am.opening_beats.is_empty(), "and its activation is returned for playback")


func test_moves_return_one_beat_per_step_with_the_board_as_it_stood() -> void:
	var am := small_match()
	var beats := am.move(1, Vector2i(5, 2))
	check(beats.size() == 3 and am.state.units[1].pos == Vector2i(5, 2), "three steps, three beats")
	check((beats[0]["state"] as SimState).units[1].pos == Vector2i(3, 2) and (beats[2]["state"] as SimState).units[1].pos == Vector2i(5, 2), "each beat carries its own snapshot")
	check(am.ap_of(1) == SimConst.AP_PER_TURN - 6, "AP fell by 6")


func test_commands_for_a_unit_that_is_not_acting_are_refused_with_a_reason() -> void:
	var s := make_state(16, 12)
	add_unit(s, 1, 0, Vector2i(2, 2), 3, 9, 5)
	add_unit(s, 2, 0, Vector2i(2, 4), 3, 3, 5)
	add_unit(s, 200, 1, Vector2i(12, 8), 3, 6, 5)
	var am := ActivationMatch.make(SimMatch.new(s, 0, SimAIProfile.load_file(SimMatch.PROFILE_FILE)["profiles"], {}))
	am.start()
	check(am.active_unit() == 1 and not am.can_act(2), "merc 1 is up; merc 2 waits")
	check(am.move(2, Vector2i(4, 4)).is_empty() and am.last_reason == "not_your_activation", "an off-turn ally is refused")
	check(am.reach(2).is_empty(), "and has no reach overlay")
	check(am.ap_of(2) == 0, "and no AP")


func test_end_turn_plays_enemy_activations_and_hands_back_to_a_player_unit() -> void:
	var am := sandbox_match()
	var rounds_seen := {}
	for i in 12:
		if am.is_over():
			break
		am.end_turn()
		check(am.is_over() or am.state.units[am.active_unit()].team == am.player_team, "after End Activation a merc is active (or the fight is over)")
		check(CombatInvariants.check(am.cs).is_empty(), "invariants hold: %s" % [CombatInvariants.check(am.cs)])
		rounds_seen[am.turn] = true
	check(rounds_seen.size() >= 2, "rounds advance as units pass")
	check(am.ai.rejected == 0, "the enemy never submitted an illegal action (%d)" % am.ai.rejected)


func test_a_lone_enemy_acts_again_every_round() -> void:
	var am := small_match(Vector2i(14, 10))
	for i in 4:
		am.end_turn()
	var active_rounds := {}
	for row in am.cs.ledger:
		if int(row["actor"]) == 200 and row["type"] != CombatAction.END_TURN:
			active_rounds[int(row["round"])] = true
	check(active_rounds.size() >= 3, "the AI's per-activation caps reset each round; it acted in %d of 4 rounds" % active_rounds.size())


func test_headless_results_carry_no_snapshots_unless_a_view_asks() -> void:
	var s := make_state(16, 12)
	add_unit(s, 1, 0, Vector2i(2, 2), 3, 9, 5)
	add_unit(s, 200, 1, Vector2i(12, 8), 3, 4, 5)
	var cs := CombatState.create(s)
	ActivationScheduler.start(cs)
	var r := ActionResolver.submit(cs, CombatAction.move_to(1, Vector2i(4, 2)))
	check(r.success and r.beats.is_empty() and r.events.size() == 2, "events yes, beats no")
	cs.capture_beats = true
	r = ActionResolver.submit(cs, CombatAction.move_to(1, Vector2i(5, 2)))
	check(r.beats.size() == 1, "beats appear when asked")


func test_full_games_through_the_bridge_finish_cleanly() -> void:
	var finished := 0
	var problems: Array[String] = []
	for sd in 6:
		var am := sandbox_match(sd)
		var guard := 0
		while not am.is_over() and guard < 400 and am.turn <= 60:
			guard += 1
			_player_turn(am)
			problems.append_array(CombatInvariants.check(am.cs))
		if am.is_over():
			finished += 1
		problems.append_array(PackedStringArray(["seed %d: AI illegal actions %d" % [sd, am.ai.rejected]]) if am.ai.rejected > 0 else PackedStringArray())
	check(problems.is_empty(), "no invariant break or illegal AI action: %s" % [problems.slice(0, 4)])
	check(finished == 6, "every game reaches a result (%d of 6)" % finished)


## A small stand-in for a human: shoot what it can see, else close the distance, then pass.
func _player_turn(am: ActivationMatch) -> void:
	var id := am.active_unit()
	for guard in 10:
		if am.is_over() or am.active_unit() != id:
			return
		var u: SimUnit = am.state.units[id]
		var target := -1
		for tid in SimVision.visible_unit_ids(am.state, u.team):
			if am.state.units[tid].team != u.team:
				var pv := am.shot_preview(id, tid)
				if pv["result"] == "hit" and am.ap_of(id) >= int(pv["cost"]) and not am.is_suppressed(id):
					target = tid
					break
		if target >= 0:
			am.shoot(id, target)
			continue
		var flank := _flank_tile(am, u)
		if flank != u.pos:
			am.move(id, flank)
			continue
		var best := u.pos
		var best_d := 9999
		for tile: Vector2i in am.reach(id):
			for fid in am.state.units:
				var f: SimUnit = am.state.units[fid]
				if f.alive and f.team != u.team:
					var d := SimLos.chebyshev(tile, f.pos)
					if d < best_d:
						best_d = d
						best = tile
		if best == u.pos or am.is_broken(id):
			break
		am.move(id, best)
	am.end_turn()


## A reachable tile from which a visible enemy can be hit and the shot is still affordable.
func _flank_tile(am: ActivationMatch, u: SimUnit) -> Vector2i:
	var reach := am.reach(u.id)
	var tiles: Array = reach.keys()
	tiles.sort_custom(SimPathing.tile_before)
	for tile: Vector2i in tiles:
		if tile == u.pos or int(reach[tile]) + u.shot_ticks() > am.ap_of(u.id):
			continue
		for tid in SimVision.visible_unit_ids(am.state, u.team):
			var t: SimUnit = am.state.units[tid]
			if t.team != u.team and SimResolver.evaluate_shot(am.state.grid, u, tile, t)["result"] == "hit":
				return tile
	return u.pos


func test_the_strip_lists_the_active_unit_first_and_hides_unseen_enemies() -> void:
	var s := make_state(24, 12)
	add_unit(s, 1, 0, Vector2i(2, 2), 3, 9, 5)
	add_unit(s, 2, 0, Vector2i(2, 4), 3, 7, 5)
	add_unit(s, 200, 1, Vector2i(6, 2), 3, 6, 5)    # in sight
	add_unit(s, 201, 1, Vector2i(22, 10), 3, 5, 5)  # far outside sight
	var am := ActivationMatch.make(SimMatch.new(s, 0, SimAIProfile.load_file(SimMatch.PROFILE_FILE)["profiles"], {}))
	am.start()
	var ids: Array = am.strip().map(func(e: Dictionary) -> int: return e["id"])
	check(ids == [1, 2, 200], "active first, then the queue; the unseen enemy is not shown: %s" % [ids])
	check(am.strip()[0]["active"] and not am.strip()[1]["active"], "only the first is flagged active")


func test_reason_codes_have_player_wording() -> void:
	for code in ["not_enough_ap", "out_of_range", "no_los", "not_your_activation", "not_visible"]:
		check(CombatReasons.text(code) != code and CombatReasons.text(code).ends_with("."), "%s has its own sentence" % code)
	check(CombatReasons.text("something_new") == "Something New.", "unknown codes still read as words")


func test_ruleset_plumbing() -> void:
	check(Session.RULESETS == ["activation", "initiative", "planned"], "three rulesets")
	check(Session.next_ruleset("activation") == "initiative" and Session.next_ruleset("planned") == "activation", "the toggle cycles through all three")
	check(Session.scene_ruleset_is_planned("planned") and not Session.scene_ruleset_is_planned("activation") and not Session.scene_ruleset_is_planned("initiative"), "only planned uses the old screen")
	check(Sandbox.default_config(story)["ruleset"] == "activation", "the sandbox defaults to the activation engine")
	Session.reset()
	check(Session.ruleset == "activation", "so does a fresh session")
	for r in Session.RULESETS:
		check(Session.RULESET_LABEL.has(r), "%s has a label" % r)
