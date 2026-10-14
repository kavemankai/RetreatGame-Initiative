extends TestBase
## Saving and resuming an encounter: exact round trip, identical continuation, mid-activation state,
## goal progress, waiting reinforcements, refusal of bad saves, and previews that change nothing.

var story: Dictionary = StoryData.load_dir("res://data/story")["data"]


func sandbox_cs(sd: int, enemies := 4) -> CombatState:
	var built := Sandbox.build(story, CombatSoak.config_for(story, sd, enemies))
	built.state.seed = sd
	return prepared(CombatState.from_match(built))


func prepared(cs: CombatState) -> CombatState:
	for id in cs.sim.units:
		if (cs.sim.units[id] as SimUnit).team == cs.player_team and not cs.assignments.has(id):
			cs.assignments[id] = "aggressor"
	ActivationScheduler.start(cs)
	return cs


func new_ais(cs: CombatState) -> Dictionary:
	var ais := {cs.player_team: ActivationAI.new(cs.player_team), cs.ai_team: ActivationAI.new(cs.ai_team)}
	(ais[cs.player_team] as ActivationAI).scout = true
	return ais


## Plays commands until `stop` says so (checked after each) or the fight ends.
func play(cs: CombatState, ais: Dictionary, stop: Callable = Callable()) -> void:
	var guard := 0
	while not cs.is_over() and cs.round_no <= 40 and guard < 4000:
		guard += 1
		var team: int = (cs.sim.units[cs.active_id] as SimUnit).team
		var a: CombatAction = (ais[team] as ActivationAI).next_action(cs)
		var r := ActionResolver.submit(cs, a)
		(ais[team] as ActivationAI).report(a, r)
		if not r.success:
			ActionResolver.submit(cs, CombatAction.end_turn(cs.active_id))
		if stop.is_valid() and stop.call(cs, a):
			return


func at_boundary(min_ledger: int) -> Callable:
	return func(cs: CombatState, a: CombatAction) -> bool: return a.type == CombatAction.END_TURN and cs.ledger.size() >= min_ledger and not cs.is_over()


func final_signature(cs: CombatState) -> String:
	var parts: Array[String] = ["w%d r%d c%d" % [cs.winner, cs.round_no, cs.clock]]
	var ids := cs.sim.units.keys()
	ids.sort()
	for id in ids:
		var u: SimUnit = cs.sim.units[id]
		parts.append("%d:%s:%d:%s" % [id, u.pos, u.hp, u.alive])
	return "|".join(parts)


func test_a_save_round_trips_exactly_through_json() -> void:
	var cs := sandbox_cs(4)
	play(cs, new_ais(cs), at_boundary(25))
	var text := CombatSave.to_json(cs)
	var back := CombatSave.from_json(text, cs.sim.grid)
	check(back != null, "the save loads")
	if back == null:
		return
	check(CombatSave.to_json(back) == text, "saving the restored state gives the same bytes")
	check(back.round_no == cs.round_no and back.active_id == cs.active_id and back.queue == cs.queue and back.clock == cs.clock, "round, active unit, queue and dice clock match")
	check(CombatInvariants.check(back).is_empty(), "invariants hold after restore")


func test_resuming_continues_exactly_as_the_original_would() -> void:
	for sd in [4, 6, 10]:
		var cs := sandbox_cs(sd)
		play(cs, new_ais(cs), at_boundary(20))
		var restored := CombatSave.from_json(CombatSave.to_json(cs), cs.sim.grid)
		check(restored != null, "seed %d: loads" % sd)
		if restored == null:
			continue
		play(cs, new_ais(cs))
		play(restored, new_ais(restored))
		check(cs.is_over() and restored.is_over(), "seed %d: both finish" % sd)
		check(final_signature(cs) == final_signature(restored), "seed %d: identical result\n  %s\n  %s" % [sd, final_signature(cs), final_signature(restored)])


func test_mid_activation_state_survives() -> void:
	var s := make_state(20, 12)
	add_unit(s, 1, 0, Vector2i(4, 5), 3, 9, 5)
	add_unit(s, 2, 0, Vector2i(4, 7), 3, 8, 5)
	add_unit(s, 200, 1, Vector2i(12, 5), 3, 4, 5)
	var cs := CombatState.create(s)
	ActivationScheduler.start(cs)
	ActionResolver.submit(cs, CombatAction.overwatch(1, Vector2i.RIGHT))
	ActionResolver.submit(cs, CombatAction.end_turn(1))
	ActionResolver.submit(cs, CombatAction.move_to(2, Vector2i(5, 7)))
	cs.suppressed[200] = true
	cs.broken[1] = true
	cs.fired[2] = true
	var back := CombatSave.from_json(CombatSave.to_json(cs), s.grid)
	check(back != null and back.active_id == 2 and back.ap_of(2) == cs.ap_of(2), "the active unit keeps its remaining AP")
	check(back.overwatch.get(1) == Vector2i.RIGHT, "armed overwatch is restored with its facing")
	check(back.suppressed.has(200) and back.broken.has(1) and back.fired.has(2), "suppressed, broken and fired flags survive")
	check(back.sim.fixed_roll == s.fixed_roll and back.sim.seed == s.seed, "the dice seed and test override survive")


func test_goal_progress_and_waiting_reinforcements_survive() -> void:
	var campaign := Campaign.new_game(story)
	var card: Dictionary = campaign.mission_or_card("pellam_dock")
	var slots: Array = campaign.available_slots().slice(0, int(card["squad_size"]))
	var built := MissionBuilder.build(campaign, "pellam_dock", slots)
	var cs := prepared(CombatState.from_match(built))
	check(not cs.reinforcements.is_empty() and cs.goal != null, "the mission has a goal and reinforcements due later")
	play(cs, new_ais(cs), func(c: CombatState, act: CombatAction) -> bool: return act.type == CombatAction.END_TURN and c.goal.rounds_done >= 1 and not c.is_over())
	check(cs.goal.rounds_done >= 1 and not cs.is_over(), "setup: saved after the goal has recorded progress (%d rounds)" % cs.goal.rounds_done)
	var fresh := MissionBuilder.build(campaign, "pellam_dock", slots)
	var back := CombatSave.from_json(CombatSave.to_json(cs), fresh.state.grid, fresh.goal)
	check(back != null, "the mission save loads")
	if back == null:
		return
	check(back.goal.progress() == cs.goal.progress(), "goal progress matches: %s" % [back.goal.progress()])
	check(back.reinforcements.size() == cs.reinforcements.size(), "the same reinforcements are still waiting")
	play(cs, new_ais(cs))
	play(back, new_ais(back))
	check(final_signature(cs) == final_signature(back), "the mission plays out identically after a resume")


func test_bad_saves_are_refused_not_half_loaded() -> void:
	var cs := sandbox_cs(4)
	var good := CombatSave.to_dict(cs)
	var wrong_version := good.duplicate(true)
	wrong_version["version"] = 99
	check(CombatSave.from_dict(wrong_version, cs.sim.grid) == null, "another version is refused")
	check(CombatSave.from_dict(good, SimGrid.new(5, 5)) == null, "a different map size is refused")
	var clash := good.duplicate(true)
	clash["units"][1]["pos"] = clash["units"][0]["pos"]
	check(CombatSave.from_dict(clash, cs.sim.grid) == null, "two units on one tile is refused")
	var negative := good.duplicate(true)
	negative["ap"] = [[int(good["active_id"]), -3]]
	check(CombatSave.from_dict(negative, cs.sim.grid) == null, "negative AP is refused")
	check(CombatSave.from_json("not json", cs.sim.grid) == null, "garbage is refused")
	check(CombatSave.from_dict(good, cs.sim.grid) != null, "the untouched save still loads")


func test_a_save_file_round_trips_on_disk() -> void:
	var cs := sandbox_cs(4)
	play(cs, new_ais(cs), at_boundary(10))
	var path := "user://combat_save_test.json"
	check(CombatSave.save_file(cs, path), "written")
	var back := CombatSave.load_file(path, cs.sim.grid)
	check(back != null and CombatSave.to_json(back) == CombatSave.to_json(cs), "read back identically")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(CombatSave.load_file(path, cs.sim.grid) == null, "a missing file is simply no save")


func test_previews_and_legality_checks_never_change_the_state() -> void:
	var cs := sandbox_cs(4)
	play(cs, new_ais(cs), at_boundary(12))
	var before := CombatSave.to_json(cs)
	var id := cs.active_id
	for tid in cs.sim.units:
		ActionResolver.preview_shot(cs, id, tid)
		ActionResolver.problem(cs, CombatAction.shoot(id, tid))
	for tile: Vector2i in ActionResolver.reach(cs, id):
		ActionResolver.problem(cs, CombatAction.move_to(id, tile))
	ActionResolver.problem(cs, CombatAction.overwatch(id, Vector2i.RIGHT))
	var am := ActivationMatch.new(cs)
	am.route_preview(id, Vector2i(6, 6))
	check(CombatSave.to_json(cs) == before, "previews, problem() and route_preview left no trace")
