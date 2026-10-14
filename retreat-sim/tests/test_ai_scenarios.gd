extends TestBase
## Enemy AI quality on the activation engine: the plan's scenario list (open field, wall detour,
## cover stand-off, low AP, target disappears, unreachable target, coordination, fog), the
## diagnostics (decision log, counters, oscillation detector) and a small AI-vs-AI soak.

var story: Dictionary = StoryData.load_dir("res://data/story")["data"]


func profiles() -> Dictionary:
	return SimAIProfile.load_file(SimMatch.PROFILE_FILE)["profiles"]


## `units`: [id, team, pos, hp, speed, aim]. AI side is team 1; `roles`: id -> profile name.
func scene(units: Array, roles := {}, w := 20, h := 12) -> CombatState:
	var s := make_state(w, h)
	s.fixed_roll = -1  # real dice: scenarios should not depend on always-hit
	for u: Array in units:
		add_unit(s, u[0], u[1], u[2], u[3], u[4], u[5])
	var cs := CombatState.create(s)
	cs.profiles = profiles()
	cs.assignments = roles
	ActivationScheduler.start(cs)
	return cs


## Plays out one round: the AI side acts through `ai`; the other side just passes.
func play_round(cs: CombatState, ai: ActivationAI) -> void:
	var start := cs.round_no
	var guard := 0
	while not cs.is_over() and cs.round_no == start and guard < 500:
		guard += 1
		var u: SimUnit = cs.sim.units[cs.active_id]
		var action: CombatAction = ai.next_action(cs) if u.team == cs.ai_team else CombatAction.end_turn(cs.active_id)
		var r := ActionResolver.submit(cs, action)
		ai.report(action, r)


func dist(cs: CombatState, a: int, b: int) -> int:
	return SimLos.chebyshev(cs.sim.units[a].pos, cs.sim.units[b].pos)


func test_an_aggressor_advances_across_open_ground_every_round() -> void:
	var cs := scene([[1, 0, Vector2i(2, 5), 99, 5, 5], [200, 1, Vector2i(18, 5), 3, 5, 5]], {200: "aggressor"})
	var ai := ActivationAI.new(1)
	var last := dist(cs, 1, 200)
	var closed := 0
	for i in 3:
		play_round(cs, ai)
		var now := dist(cs, 1, 200)
		closed += int(now < last)
		last = now
	check(closed >= 2 and last <= 6, "it closed in %d rounds and is now %d tiles away" % [closed, last])
	check(cs.log.any(func(e: Dictionary) -> bool: return e["type"] == "shot" and e["unit"] == 200), "and it opened fire once in range")
	check(ai.rejected == 0 and ai.idle_activations == 0, "no refusals, no idle turn")


func test_a_patrol_walks_around_a_wall_to_reach_its_objective() -> void:
	var cs := scene([[1, 0, Vector2i(0, 11), 99, 1, 1], [200, 1, Vector2i(10, 5), 3, 5, 5]], {200: "aggressor"})
	for y in 9:  # a full wall down column 5|6 from the top, open at the bottom
		cs.sim.grid.set_edge(Vector2i(5, y), Vector2i(6, y), SimConst.EDGE_FULL)
	var ai := ActivationAI.new(1)
	for i in 9:
		play_round(cs, ai)
	check(cs.sim.units[200].pos.x <= 4, "it found the gap and got past the wall; it ended at %s" % [cs.sim.units[200].pos])
	check(ai.rejected == 0, "without a single refusal")


func test_a_cover_stand_off_is_broken_by_flanking() -> void:
	var cs := scene([[1, 0, Vector2i(4, 5), 99, 5, 5], [200, 1, Vector2i(9, 5), 3, 5, 5]], {200: "aggressor"})
	cs.sim.grid.set_edge(Vector2i(4, 5), Vector2i(5, 5), SimConst.EDGE_HALF)  # the squad merc is covered from the east
	var ai := ActivationAI.new(1)
	var shots := 0
	for i in 4:
		play_round(cs, ai)
	for e: Dictionary in cs.log:
		if e["type"] == "shot" and e["unit"] == 200 and e["result"] != "blocked":
			shots += 1
	check(shots >= 1, "the aggressor moved to a clear lane and fired (%d clear shots)" % shots)
	check(ai.idle_with_target == 0, "it never sat idle with a target in range")


func test_low_ap_never_buys_an_unaffordable_shot() -> void:
	var cs := scene([[1, 0, Vector2i(2, 5), 99, 1, 1], [200, 1, Vector2i(6, 5), 3, 9, 5]], {200: "aggressor"})
	check(cs.active_id == 200, "the enemy is up")
	cs.ap[200] = 3  # a shot costs 4
	var ai := ActivationAI.new(1)
	var acts := 0
	while cs.active_id == 200 and acts < 10:
		acts += 1
		var a := ai.next_action(cs)
		check(a.type != CombatAction.SHOOT, "no shot with 3 AP")
		var r := ActionResolver.submit(cs, a)
		ai.report(a, r)
		check(r.success, "and nothing it submits is refused")
	check(cs.active_id != 200, "the activation ends")


func test_a_stale_plan_step_is_dropped_not_submitted() -> void:
	var cs := scene([[1, 0, Vector2i(2, 5), 99, 1, 1], [200, 1, Vector2i(6, 5), 3, 9, 9]], {200: "aggressor"})
	var ai := ActivationAI.new(1)
	ai._unit = 200
	ai._round = cs.round_no
	ai._replans = 0
	ai._pending = [SimAction.shoot(999)]  # a target that does not exist (it died, say)
	var a := ai.next_action(cs)
	check(ai.dropped == 1, "the dead target's step was dropped, not sent")
	check(ActionResolver.problem(cs, a) == "", "what it returned instead is legal")


func test_an_unreachable_target_does_not_stall_or_spin() -> void:
	var cs := scene([[1, 0, Vector2i(12, 5), 99, 1, 1], [200, 1, Vector2i(5, 5), 3, 9, 9]], {200: "aggressor"})
	for pair in [[Vector2i(12, 4), Vector2i(12, 5)], [Vector2i(12, 6), Vector2i(12, 5)], [Vector2i(11, 5), Vector2i(12, 5)], [Vector2i(13, 5), Vector2i(12, 5)]]:
		cs.sim.grid.set_edge(pair[0], pair[1], SimConst.EDGE_FULL)  # the merc is walled into a cell
	var ai := ActivationAI.new(1)
	for i in 5:
		play_round(cs, ai)
	check(ai.rejected == 0 and ai.cap_hits == 0, "no refusals and no cap hit (%d, %d)" % [ai.rejected, ai.cap_hits])
	check(cs.sim.units[1].alive, "the merc is untouched behind its walls")


func test_two_aggressors_take_different_tiles_and_both_engage() -> void:
	var cs := scene([[1, 0, Vector2i(2, 5), 99, 1, 1], [200, 1, Vector2i(9, 5), 3, 9, 9], [201, 1, Vector2i(9, 6), 3, 8, 9]], {200: "aggressor", 201: "aggressor"})
	var ai := ActivationAI.new(1)
	play_round(cs, ai)
	check(cs.sim.units[200].pos != cs.sim.units[201].pos, "they do not stack on one tile")
	var shooters := {}
	for e: Dictionary in cs.log:
		if e["type"] == "shot":
			shooters[e["unit"]] = true
	check(shooters.size() == 2, "both opened fire in the same round: %s" % [shooters.keys()])


func test_the_ai_never_acts_on_units_it_cannot_see() -> void:
	var cs := scene([[1, 0, Vector2i(12, 5), 99, 1, 1], [200, 1, Vector2i(5, 5), 3, 9, 9]], {200: "guard"})
	cs.sim.units[200].sight_range = 3
	cs.sim.units[200].weapon_range = 9  # the merc is inside weapon range but outside sight
	var ai := ActivationAI.new(1)
	play_round(cs, ai)
	check(cs.log.filter(func(e: Dictionary) -> bool: return e["type"] == "shot").is_empty(), "no shot at a hidden unit")


func test_the_decision_log_and_counters_explain_each_activation() -> void:
	var cs := scene([[1, 0, Vector2i(2, 5), 99, 1, 1], [200, 1, Vector2i(9, 5), 3, 9, 9]], {200: "aggressor"})
	var ai := ActivationAI.new(1, true)
	play_round(cs, ai)
	var kinds: Array = ai.log.map(func(r: Dictionary) -> String: return r["kind"])
	check(kinds.has("plan") and kinds.has("act") and kinds.has("end"), "plan, act and end rows are logged: %s" % [kinds])
	var plan: Dictionary = ai.log[kinds.find("plan")]
	check(plan["intent"].has("options") and plan["intent"]["options"].has("stay") and plan["intent"]["options"].has("chosen"), "a plan row carries the planner's scores")
	var end: Dictionary = ai.log[kinds.rfind("end")]
	check(String(end["reason"]) != "" and ai.activations == 1 and ai.plans >= 1, "the end row says why; counters moved")
	check(ai.plan_ms_p95() >= 0.0 and ai.plan_usec.size() == ai.plans, "planning time is recorded for each plan")
	check(not ActivationAI.new(1).scout and not ActivationAI.new(1).keep_log, "scouting and logging are off by default")


func test_the_oscillation_detector_flags_a_to_b_to_a_to_b() -> void:
	var cs := scene([[1, 0, Vector2i(2, 5), 99, 1, 1], [200, 1, Vector2i(8, 5), 3, 9, 9]], {200: "aggressor"})
	var ai := ActivationAI.new(1, true)
	for tile in [Vector2i(8, 5), Vector2i(8, 6), Vector2i(8, 5), Vector2i(8, 6)]:
		cs.sim.units[200].pos = tile
		ai._track_trail(cs, 200)
	check(ai.oscillations == 1 and ai.log.any(func(r: Dictionary) -> bool: return r["kind"] == "oscillation"), "A-B-A-B with an enemy in view is counted and logged")
	var fresh := ActivationAI.new(1)
	for tile in [Vector2i(8, 5), Vector2i(9, 5), Vector2i(10, 5), Vector2i(11, 5)]:
		cs.sim.units[200].pos = tile
		fresh._track_trail(cs, 200)
	check(fresh.oscillations == 0, "steady progress is not an oscillation")


func test_same_seed_same_battle() -> void:
	var a := CombatSoak.run_battle(story, 3)
	var b := CombatSoak.run_battle(story, 3)
	for key in ["rounds", "winner", "commands", "shots", "hits", "squad_dead", "enemy_dead", "dropped"]:
		check(a[key] == b[key], "%s repeats (%s vs %s)" % [key, a[key], b[key]])


func test_a_small_ai_vs_ai_soak_is_clean() -> void:
	var finished := 0
	var bad: Array[String] = []
	for sd in 6:
		var r := CombatSoak.run_battle(story, sd)
		finished += int(r["finished"])
		if r["frozen"] or r["rejected"] > 0 or not (r["invariant_problems"] as Array).is_empty() or r["oscillations"] > 0:
			bad.append("seed %d: %s" % [sd, {"frozen": r["frozen"], "rej": r["rejected"], "inv": (r["invariant_problems"] as Array).slice(0, 2), "osc": r["oscillations"]}])
	check(bad.is_empty(), "no illegal action, invariant break, freeze or loop: %s" % [bad])
	check(finished == 6, "all six battles reach a result (%d)" % finished)


func test_every_act1_mission_plays_through_the_activation_engine() -> void:
	for mission in ["karsa_breakout", "the_weir", "pellam_dock", "orchard_ring"]:
		var r := CombatSoak.run_mission(story, mission, 0)
		check(r["finished"] and not r["frozen"], "%s reaches a result in %d rounds" % [mission, r["rounds"]])
		check(r["rejected"] == 0 and (r["invariant_problems"] as Array).is_empty(), "%s: no illegal action or broken invariant" % mission)
