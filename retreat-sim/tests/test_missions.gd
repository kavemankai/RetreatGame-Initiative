extends TestBase
## Turning campaign missions into playable matches, and match results back
## into campaign outcomes.


func new_campaign() -> Campaign:
	return Campaign.new_game(StoryData.load_dir("res://data/story")["data"])


func test_build_match_fields_the_chosen_squad_against_the_mission_enemies() -> void:
	var c := new_campaign()
	var m := MissionBuilder.build(c, "karsa_breakout", [1, 5, 8])
	var blue := m.state.units.values().filter(func(u): return u.team == 0)
	var red := m.state.units.values().filter(func(u): return u.team == 1)
	check(blue.size() == 3 and red.size() == 3, "3 mercs against 3 conscripts (a sentry, a patrol and a guard)")
	check(m.state.units.has(1) and m.state.units.has(5) and m.state.units.has(8), "unit ids are the slot numbers")
	check(m.state.units[8].cqb == 9 and m.state.units[1].sight_range == 6, "stats come from the cast (Needle's CQB 9, Warden's sight 6)")


func test_units_start_on_distinct_open_tiles() -> void:
	var c := new_campaign()
	for mission_id in ["karsa_breakout", "quiet_wards", "long_corridor", "vesper_threshold"]:
		var m := MissionBuilder.build(c, mission_id, [1, 2, 3, 4])
		var seen := {}
		for id in m.state.units:
			var u: SimUnit = m.state.units[id]
			check(not seen.has(u.pos) and m.state.grid.in_bounds(u.pos) and not m.state.grid.is_blocked(u.pos), "%s: unit %d has its own open tile" % [mission_id, id])
			seen[u.pos] = true


func test_hollow_slots_field_as_drones_with_frozen_stats() -> void:
	var c := new_campaign()
	c.complete_mission("karsa_breakout", true, [3], [], [])
	var m := MissionBuilder.build(c, "the_weir", [1, 3, 5])
	var moth: SimUnit = m.state.units[3]
	check(moth.is_drone and moth.morale == 0 and moth.aim == 3, "Moth's slot is now a drone at 60% of Moth's aim (5 -> 3)")
	check(not m.state.units[1].is_drone, "the others are unchanged")


func test_writ_officers_appear_and_hollow_ones_are_drones() -> void:
	var c := new_campaign()
	var m := MissionBuilder.build(c, "quiet_wards", [1, 2, 3, 4])
	check(m.state.units.has(101) and m.state.units.has(102), "Clerk and Gavel are on the field")
	check(not m.state.units[101].is_drone, "intact officers are people")
	c.complete_mission("quiet_wards", true, [], ["clerk"], [])
	var again := MissionBuilder.build(c, "quiet_wards", [1, 2, 3, 4])
	check(again.state.units[101].is_drone, "after Clerk is killed, the Bureau fields a hollow in her slot")


func test_orrick_is_on_the_field_when_the_mission_says_so() -> void:
	var c := new_campaign()
	var m := MissionBuilder.build(c, "long_corridor", [1, 2, 3, 4])
	check(m.state.units.has(Campaign.PROVOST_ID), "Orrick is present at the Long Corridor")
	check(not MissionBuilder.build(c, "karsa_breakout", [1, 2, 3]).state.units.has(Campaign.PROVOST_ID), "and not at Karsa")


func test_ai_profiles_differ_for_officers() -> void:
	var c := new_campaign()
	var m := MissionBuilder.build(c, "quiet_wards", [1, 2, 3, 4])
	check(m.assignments.get(101, "") == "defender" and m.assignments.get(200, "") == "aggressor", "officers hold, conscripts press")


func test_outcome_reads_dead_slots_and_writ_kills() -> void:
	var c := new_campaign()
	var m := MissionBuilder.build(c, "quiet_wards", [1, 2, 3, 4])
	m.run.state.units[2].alive = false
	m.run.state.units[101].alive = false
	var o := MissionBuilder.outcome(c, m, false)
	check(o["dead_slots"] == [2] and o["writ_dead"] == ["clerk"], "the dead are mapped back to slots and officer ids")
	check(o["success"] == false and o["squad_wiped"] == false, "no winner yet and the squad lives: not a success, not a wipe")


func test_outcome_for_a_win_a_wipe_and_a_withdrawal() -> void:
	var c := new_campaign()
	var won := MissionBuilder.build(c, "karsa_breakout", [1, 5, 8])
	for id in won.state.units.keys():
		if (won.state.units[id] as SimUnit).team == 1:
			won.run.state.units[id].alive = false
	won.step()
	check(MissionBuilder.outcome(c, won, false)["success"], "all enemies dead = success")
	var lost := MissionBuilder.build(c, "karsa_breakout", [1, 5, 8])
	for id in [1, 5, 8]:
		lost.run.state.units[id].alive = false
	lost.step()
	var o := MissionBuilder.outcome(c, lost, false)
	check(o["squad_wiped"] and not o["success"], "all mercs dead = squad wiped")
	var out := MissionBuilder.build(c, "karsa_breakout", [1, 5, 8])
	var w := MissionBuilder.outcome(c, out, true)
	check(not w["success"] and not w["squad_wiped"], "withdrawing is a failure with survivors")


func test_campaign_applies_an_outcome() -> void:
	var c := new_campaign()
	var o := {"success": true, "dead_slots": [4], "writ_dead": [], "squad_wiped": false}
	c.complete_mission("karsa_breakout", o["success"], o["dead_slots"], o["writ_dead"], [], o["squad_wiped"])
	check(c.slot_status(4) == "hollow" and c.current == "the_weir", "the campaign records the loss and moves on")


func test_a_whole_mission_can_be_played_by_the_ai_and_recorded() -> void:
	var c := new_campaign()
	var profiles := ai_profiles()
	var m := MissionBuilder.build(c, "karsa_breakout", [1, 5, 8])
	var turns := 0
	while not m.is_over() and turns < 12:
		turns += 1
		var plan := SimAI.plan_for(m.state, 0, profiles, {}, Vector2i(10, 5))
		if m.submit(plan) == null:
			check(false, "mission turn %d refused: %s" % [turns, m.last_error])
			break
	var o := MissionBuilder.outcome(c, m, not m.is_over())
	c.complete_mission("karsa_breakout", o["success"], o["dead_slots"], o["writ_dead"], [], o["squad_wiped"])
	check(c.completed.has("karsa_breakout") or c.over, "the mission is recorded (or the squad was lost)")
	check(c.reserves >= 0 and c.procession >= 0, "the economy never goes negative")


func test_session_holds_the_campaign_between_screens() -> void:
	Session.reset()
	check(Session.campaign == null and Session.current_match == null and not Session.in_campaign(), "a fresh session has nothing")
	Session.campaign = new_campaign()
	Session.current_match = MissionBuilder.build(Session.campaign, "karsa_breakout", [1, 5, 8])
	Session.mission_id = "karsa_breakout"
	check(Session.in_campaign(), "a campaign match marks the session as campaign play")
	Session.reset()
	check(not Session.in_campaign(), "reset clears it")


func test_mission_seed_is_stable_and_differs_between_missions() -> void:
	var story: Dictionary = StoryData.load_dir("res://data/story")["data"]
	var c := Campaign.new_game(story)
	check(MissionBuilder.mission_seed(c, "m1") != MissionBuilder.mission_seed(c, "m2"), "different missions give different seeds")
	check(MissionBuilder.mission_seed(c, "m1") == MissionBuilder.mission_seed(c, "m1"), "the same mission at the same point rolls the same")
	check(SimMatch.skirmish(3).state.seed == 3, "a skirmish carries its seed into the board")
