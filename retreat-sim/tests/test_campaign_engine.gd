extends TestBase
## Campaign missions on the activation engine: shot counters, the outcome the campaign needs
## (survivors and per-merc stats), the outcome surviving a campaign save, whole missions played
## in order by the AI, and resuming a campaign mission.

var story: Dictionary = StoryData.load_dir("res://data/story")["data"]


func squad_for(campaign: Campaign, mission_id: String) -> Array:
	var card: Dictionary = campaign.mission_or_card(mission_id)
	var named: Array[int] = []
	var hollow: Array[int] = []
	for slot in campaign.available_slots():
		(named if campaign.slot_status(slot) == "named" else hollow).append(slot)
	return (named + hollow).slice(0, mini(int(card["squad_size"]), campaign.available_slots().size()))


func test_shot_counters_record_hits_and_kills() -> void:
	var s := make_state(12, 12)
	var shooter := add_unit(s, 1, 0, Vector2i(2, 2), 3, 5, 5)
	var tough := add_unit(s, 2, 1, Vector2i(5, 2), 3, 5, 5)
	var weak := add_unit(s, 3, 1, Vector2i(5, 4), 1, 5, 5)
	ShotResolver.fire(s, shooter, tough.id, 1, 1, false)
	check(int(shooter.counters.get("hits_landed", 0)) == 1 and int(shooter.counters.get("kills", 0)) == 0, "a non-lethal hit counts as a hit, not a kill")
	ShotResolver.fire(s, shooter, weak.id, 1, 2, false)
	check(int(shooter.counters.get("hits_landed", 0)) == 2 and int(shooter.counters.get("kills", 0)) == 1, "a lethal hit counts as both")
	s.fixed_roll = 100  # always miss
	ShotResolver.fire(s, shooter, tough.id, 1, 3, false)
	check(int(shooter.counters.get("hits_landed", 0)) == 2 and int(shooter.counters.get("shots_fired", 0)) == 3, "a miss is a shot but not a hit")


func test_outcome_for_matches_the_planned_modes_outcome() -> void:
	var campaign := Campaign.new_game(story)
	var slots := squad_for(campaign, "pellam_dock")
	for withdrawn in [false, true]:
		var m := MissionBuilder.build(campaign, "pellam_dock", slots)
		var cs := CombatState.from_match(m)
		var dead_player := int(slots[0])
		var dead_enemy := -1
		for id in m.state.units:
			if m.state.units[id].team != 0 and dead_enemy < 0:
				dead_enemy = id
		for st: SimState in [m.state, cs.sim]:
			(st.units[dead_player] as SimUnit).alive = false
			(st.units[dead_enemy] as SimUnit).alive = false
		m.winner = 0
		cs.winner = 0
		cs.phase = CombatState.Phase.ENDED
		var a := MissionBuilder.outcome(campaign, m, withdrawn)
		var b := MissionBuilder.outcome_for(campaign, cs, withdrawn)
		check(b["success"] == (not withdrawn), "a win counts as success only if the squad did not withdraw (withdrawn=%s, success=%s)" % [withdrawn, b["success"]])
		for key in ["success", "dead_slots", "writ_dead", "squad_wiped", "procession_loss"]:
			check(a[key] == b[key], "withdrawn=%s: %s matches (%s vs %s)" % [withdrawn, key, a[key], b[key]])


func test_the_outcome_reports_survivors_and_per_merc_stats() -> void:
	var campaign := Campaign.new_game(story)
	var slots := squad_for(campaign, "karsa_breakout")
	var built := MissionBuilder.build(campaign, "karsa_breakout", slots)
	var r := CombatSoak.play_state(CombatState.from_match(built), 3)
	var cs: CombatState = r["cs"]
	check(cs.is_over(), "the mission finished")
	var o := MissionBuilder.outcome_for(campaign, cs, false)
	check(o["rounds"] == cs.round_no, "rounds are reported")
	var alive: Array[int] = []
	for id in slots:
		if cs.sim.units[id].alive:
			alive.append(int(id))
	check((o["survivors"] as Array) == alive, "survivors are the living squad members: %s vs %s" % [o["survivors"], alive])
	check((o["units"] as Array).size() == slots.size(), "one stats row per fielded merc")
	var kills := 0
	for row: Dictionary in o["units"]:
		for key in ["slot", "alive", "shots", "hits", "kills", "hits_taken", "steps"]:
			check(row.has(key), "row has %s" % key)
		kills += int(row["kills"])
	check(kills == int(r["enemy_dead"]), "squad kills add up to the enemy dead (%d vs %d)" % [kills, int(r["enemy_dead"])])


func test_the_outcome_survives_the_campaign_save() -> void:
	var campaign := Campaign.new_game(story)
	var slots := squad_for(campaign, "karsa_breakout")
	var r := CombatSoak.play_state(CombatState.from_match(MissionBuilder.build(campaign, "karsa_breakout", slots)), 3)
	var o := MissionBuilder.outcome_for(campaign, r["cs"], false)
	var before := {"procession": campaign.procession, "reserves": campaign.reserves}
	var report := campaign.complete_mission("karsa_breakout", o["success"], o["dead_slots"], o["writ_dead"], [], o["squad_wiped"], int(o.get("procession_loss", 0)))
	campaign.pending = [{"t": "result", "id": "karsa_breakout", "o": o, "report": report, "before": before, "withdrawn": false}]
	var text := JSON.stringify(campaign.to_dict())
	var parsed: Variant = JSON.parse_string(text)
	check(parsed is Dictionary and Campaign.save_problem(parsed) == "", "the saved campaign is valid with the richer outcome in its pending step")
	var back := Campaign.from_dict(parsed, story)
	check(back != null and back.pending.size() == 1 and (back.pending[0]["o"]["units"] as Array).size() == slots.size(), "and the stats come back")
	check(JSON.parse_string(JSON.stringify(back.to_dict())) == parsed, "and saving again gives the same content (JSON turns integers into floats on load, so compare parsed content, not bytes)")


func test_the_first_missions_play_through_in_order_on_the_activation_engine() -> void:
	var r := CombatSoak.run_campaign(story, 0, 4)
	check(r["missions_played"] == 4, "four missions were played (%d)" % r["missions_played"])
	check(r["problems"].is_empty(), "no illegal action, invariant break or lockup: %s" % [(r["problems"] as Array).slice(0, 3)])
	var c: Campaign = r["campaign"]
	check(c.completed.size() == 4 and c.current == "quiet_wards" and not c.over, "the route advanced to the next story mission: completed %d, now %s" % [c.completed.size(), c.current])
	for slot in c.available_slots():
		check(["named", "hollow"].has(c.slot_status(slot)), "slot %d has a playable status" % slot)


func test_a_resumed_campaign_mission_rebuilds_from_the_campaign_save() -> void:
	var path := "user://resume_test.json"
	var camp_path := "user://campaign_resume_test.json"
	ResumeStore.clear(path)
	var campaign := Campaign.new_game(story)
	var f := FileAccess.open(camp_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(campaign.to_dict()))
	f.close()
	var slots := squad_for(campaign, "karsa_breakout")
	var built := MissionBuilder.build(campaign, "karsa_breakout", slots)
	var cs := CombatState.from_match(built)
	for id in cs.sim.units:
		if (cs.sim.units[id] as SimUnit).team == cs.player_team and not cs.assignments.has(id):
			cs.assignments[id] = "aggressor"
	ActivationScheduler.start(cs)
	var ais := {cs.player_team: ActivationAI.new(cs.player_team), cs.ai_team: ActivationAI.new(cs.ai_team)}
	var guard := 0
	while not cs.is_over() and cs.ledger.size() < 12 and guard < 400:
		guard += 1
		var team: int = (cs.sim.units[cs.active_id] as SimUnit).team
		var a: CombatAction = (ais[team] as ActivationAI).next_action(cs)
		(ais[team] as ActivationAI).report(a, ActionResolver.submit(cs, a))
	check(ResumeStore.save(cs, {"kind": ResumeStore.KIND_CAMPAIGN, "mission_id": "karsa_breakout"}, path), "saved")
	check(String(ResumeStore.peek(path)["label"]).begins_with("Karsa Breakout"), "the label names the mission")
	var loaded := ResumeStore.load_battle(story, path, camp_path)
	check(not loaded.is_empty(), "it loads")
	if not loaded.is_empty():
		check(CombatSave.to_json(loaded["cs"]) == CombatSave.to_json(cs), "the exact state is back")
		check(loaded["campaign"] != null and (loaded["campaign"] as Campaign).current == campaign.current, "with the campaign it belongs to")
		check(ResumeStore.enter_session(story, path, camp_path) and Session.campaign != null and not Session.level_test and Session.mission_id == "karsa_breakout" and Session.resume_cs != null, "entering the session sets up a real campaign mission, not a level test")
		Session.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(camp_path))
	var missing := ResumeStore.load_battle(story, path, camp_path)
	check(missing.is_empty() and not FileAccess.file_exists(path), "without the campaign save there is nothing to resume, and the dead file is discarded")
	ResumeStore.clear(path)


func test_a_mission_that_is_already_complete_cannot_be_resumed() -> void:
	var path := "user://resume_test.json"
	var camp_path := "user://campaign_resume_test.json"
	var campaign := Campaign.new_game(story)
	var slots := squad_for(campaign, "karsa_breakout")
	var cs := CombatState.from_match(MissionBuilder.build(campaign, "karsa_breakout", slots))
	ActivationScheduler.start(cs)
	check(ResumeStore.save(cs, {"kind": ResumeStore.KIND_CAMPAIGN, "mission_id": "karsa_breakout"}, path), "saved a fight in progress")
	campaign.complete_mission("karsa_breakout", true, [], [], [])  # the campaign moved on (say, the outcome was already applied)
	var f := FileAccess.open(camp_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(campaign.to_dict()))
	f.close()
	check(ResumeStore.load_battle(story, path, camp_path).is_empty() and not FileAccess.file_exists(path), "the stale battle is discarded, so a mission can never be applied twice")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(camp_path))
	ResumeStore.clear(path)
