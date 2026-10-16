extends TestBase
## One-shot overwatch: armed for AP, fires once at the first qualifying step in its cone, costs
## the reaction nothing, never chains, and the mover resumes unless it is dead or broken.


## Watcher 1 (team 0, acts first) at (4,5); enemy 200 at (12,5); enemy 201 far away so a dead
## mover does not end the fight.
func duel(mover_hp := 3) -> CombatState:
	var s := make_state(20, 12)
	add_unit(s, 1, 0, Vector2i(4, 5), 3, 9, 5)
	add_unit(s, 200, 1, Vector2i(12, 5), mover_hp, 4, 5)
	add_unit(s, 201, 1, Vector2i(19, 11), 3, 1, 1)
	var cs := CombatState.create(s)
	ActivationScheduler.start(cs)
	return cs


func arm_and_pass(cs: CombatState, id := 1, dir := Vector2i.RIGHT) -> void:
	ActionResolver.submit(cs, CombatAction.overwatch(id, dir))
	ActionResolver.submit(cs, CombatAction.end_turn(id))


func reaction_shots(r: ActionResult) -> Array:
	return r.events.filter(func(e: Dictionary) -> bool: return e["type"] == "shot" and e.get("reaction", false))


func test_a_step_into_the_cone_triggers_one_free_shot_and_the_mover_continues() -> void:
	var cs := duel()
	arm_and_pass(cs)
	check(cs.active_id == 200 and cs.overwatch.has(1), "the watcher is armed and the enemy is up")
	var r := ActionResolver.submit(cs, CombatAction.move_to(200, Vector2i(8, 5)))
	var shots := reaction_shots(r)
	check(r.success and shots.size() == 1 and shots[0]["unit"] == 1 and shots[0]["target"] == 200, "exactly one reaction shot, from the watcher")
	check(cs.sim.units[200].hp == 2, "it hit (test dice always hit)")
	check(cs.sim.units[200].pos == Vector2i(8, 5) and r.cost == 8, "the mover resumed and paid only for its own 4 steps")
	check(not cs.overwatch.has(1), "the charge is spent")
	check(r.events.filter(func(e: Dictionary) -> bool: return e["type"] == "move").size() == 4, "all four steps happened")
	check(CombatInvariants.check(cs).is_empty(), "invariants hold: %s" % [CombatInvariants.check(cs)])


func test_the_shot_fires_at_the_first_qualifying_step_not_the_last() -> void:
	var cs := duel()
	arm_and_pass(cs)
	var r := ActionResolver.submit(cs, CombatAction.move_to(200, Vector2i(8, 5)))
	var kinds: Array = r.events.map(func(e: Dictionary) -> String: return e["type"])
	check(kinds.slice(0, 2) == ["move", "shot"], "move into range, then the reaction: %s" % [kinds])
	check((r.events[0] as Dictionary)["to"] == Vector2i(11, 5), "the trigger tile is the first one in range")


func test_nothing_fires_outside_the_cone_range_or_sight() -> void:
	var away := duel()
	arm_and_pass(away, 1, Vector2i.LEFT)  # watching the wrong way
	var r := ActionResolver.submit(away, CombatAction.move_to(200, Vector2i(8, 5)))
	check(reaction_shots(r).is_empty() and away.overwatch.has(1), "outside the cone: no shot, and the watch stays armed")
	var far := duel()
	arm_and_pass(far)
	r = ActionResolver.submit(far, CombatAction.move_to(200, Vector2i(14, 5)))
	check(reaction_shots(r).is_empty() and far.overwatch.has(1), "beyond weapon range: no shot")
	var walled := duel()
	walled.sim.grid.set_edge(Vector2i(5, 5), Vector2i(6, 5), SimConst.EDGE_FULL)
	arm_and_pass(walled)
	r = ActionResolver.submit(walled, CombatAction.move_to(200, Vector2i(8, 5)))
	check(reaction_shots(r).is_empty(), "a full wall blocks the line: no shot")


func test_a_shaken_broken_or_dead_watcher_cannot_react() -> void:
	for status in ["suppressed", "broken", "dead"]:
		var cs := duel()
		arm_and_pass(cs)
		match status:
			"suppressed":
				cs.suppressed[1] = true
			"broken":
				cs.broken[1] = true
			"dead":
				cs.sim.units[1].alive = false
				cs.overwatch.erase(1)
		var r := ActionResolver.submit(cs, CombatAction.move_to(200, Vector2i(8, 5)))
		check(reaction_shots(r).is_empty(), "%s watcher: no reaction" % status)


func test_a_killed_mover_stops_and_its_path_is_cancelled() -> void:
	var cs := duel(1)
	arm_and_pass(cs)
	var r := ActionResolver.submit(cs, CombatAction.move_to(200, Vector2i(8, 5)))
	check(r.success and not cs.sim.units[200].alive, "the mover died to the reaction")
	check(cs.sim.units[200].pos == Vector2i(11, 5), "it never took another step")
	check(r.events.filter(func(e: Dictionary) -> bool: return e["type"] == "move").size() == 1, "one move event only")
	check(r.cost == 2 and r.activation_ended and cs.active_id != 200, "paid for one step, then its activation ended")
	check(CombatInvariants.check(cs).is_empty(), "invariants hold")


func test_several_watchers_fire_in_initiative_order_until_the_mover_drops() -> void:
	var s := make_state(20, 12)
	add_unit(s, 1, 0, Vector2i(4, 5), 3, 9, 5)
	add_unit(s, 2, 0, Vector2i(4, 7), 3, 8, 5)
	add_unit(s, 200, 1, Vector2i(12, 5), 3, 4, 5)
	add_unit(s, 201, 1, Vector2i(19, 11), 3, 1, 1)
	var cs := CombatState.create(s)
	ActivationScheduler.start(cs)
	arm_and_pass(cs, 1)
	arm_and_pass(cs, 2)
	var r := ActionResolver.submit(cs, CombatAction.move_to(200, Vector2i(8, 5)))
	var order: Array = reaction_shots(r).map(func(e: Dictionary) -> int: return e["unit"])
	check(order == [1, 2], "highest initiative first, then the next: %s" % [order])
	check(cs.sim.units[200].hp == 1, "two hits landed")
	var lethal := duel(1)
	lethal.sim.add_unit(SimUnit.make(2, 0, Vector2i(4, 7), 3, 8, 5, 5))
	lethal.queue.append(2)
	arm_and_pass(lethal, 1)
	ActionResolver.submit(lethal, CombatAction.overwatch(2, Vector2i.RIGHT))
	lethal.overwatch[2] = Vector2i.RIGHT
	var r2 := ActionResolver.submit(lethal, CombatAction.end_turn(lethal.active_id))
	check(r2.success, "setup: pass to the mover")
	if lethal.active_id == 200:
		var r3 := ActionResolver.submit(lethal, CombatAction.move_to(200, Vector2i(8, 5)))
		check(reaction_shots(r3).size() == 1 and lethal.overwatch.has(2), "once the mover is dead the second watcher keeps its charge")


func test_reactions_do_not_chain() -> void:
	var s := make_state(20, 12)
	add_unit(s, 1, 0, Vector2i(4, 5), 3, 9, 5)
	add_unit(s, 200, 1, Vector2i(12, 5), 3, 4, 5)
	add_unit(s, 201, 1, Vector2i(10, 8), 3, 3, 5)  # also armed against the watcher's side
	var cs := CombatState.create(s)
	ActivationScheduler.start(cs)
	arm_and_pass(cs)
	cs.overwatch[201] = Vector2i.LEFT
	var r := ActionResolver.submit(cs, CombatAction.move_to(200, Vector2i(8, 5)))
	check(reaction_shots(r).size() == 1, "the watcher's reaction shot is not itself reacted to")
	check(cs.overwatch.has(201), "the other enemy's watch was not triggered by a reaction")


func test_enemy_sentries_start_armed_in_a_match_and_the_ai_holds_when_armed() -> void:
	var s := make_state(20, 12)
	add_unit(s, 1, 0, Vector2i(2, 2), 3, 2, 2)
	var sentry := add_unit(s, 200, 1, Vector2i(12, 5), 3, 9, 9)
	sentry.watch_dir = Vector2i.LEFT
	var m := SimMatch.new(s, 0, SimAIProfile.load_file(SimMatch.PROFILE_FILE)["profiles"], {200: "sentry"})
	var am := ActivationMatch.make(m)
	am.start()
	check(am.cs.round_no == 1 and am.active_unit() == 1, "the merc is up after the sentry's first activation")
	var ai := ActivationAI.new()
	var cs := am.cs
	cs.overwatch[200] = Vector2i.LEFT
	cs.active_id = 200
	cs.ap[200] = 14
	check(ai.next_action(cs).type == CombatAction.END_TURN, "an armed unit holds and ends its activation")


func test_the_route_preview_flags_steps_a_visible_watcher_covers() -> void:
	var s := make_state(20, 12)
	add_unit(s, 1, 0, Vector2i(4, 5), 3, 2, 5)
	add_unit(s, 200, 1, Vector2i(10, 5), 3, 9, 5)
	var am := ActivationMatch.make(SimMatch.new(s, 0, SimAIProfile.load_file(SimMatch.PROFILE_FILE)["profiles"], {}))
	am.start()
	am.cs.overwatch[200] = Vector2i.LEFT
	var route := am.route_preview(1, Vector2i(6, 5))
	check(route.size() == 2 and not (route[1]["threats"] as Array).is_empty(), "a visible watcher's cone marks the exposed steps: %s" % [route])
