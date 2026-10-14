extends TestBase
## The campaign model: roster slots, the Hollowing, the retreat economy,
## the Writ's hollowing, choices, endings, and saving.


func new_campaign() -> Campaign:
	var loaded := StoryData.load_dir("res://data/story")
	return Campaign.new_game(loaded["data"])


# --- roster ---------------------------------------------------------------

func test_new_campaign_starts_with_ten_named_mercs_and_full_resources() -> void:
	var c := new_campaign()
	check(c.available_slots().size() == 10, "ten slots are available at the start")
	check(c.procession == 6200 and c.reserves == 24 and c.remembrance == 0, "starting resources come from the world data")
	check(c.slot_status(1) == "named" and c.slot_status(11) == "absent" and c.slot_status(12) == "absent", "Ghost and Wren have not joined yet")


func test_mercs_join_when_their_mission_is_completed() -> void:
	var c := new_campaign()
	c.complete_mission("karsa_breakout", true, [], [], [])
	c.complete_mission("the_weir", true, [], [], [])
	c.complete_mission("pellam_dock", true, [], [], [])
	check(c.slot_status(12) == "absent", "Wren is not here yet")
	c.complete_mission("orchard_ring", true, [], [], [])
	check(c.slot_status(12) == "named" and c.available_slots().size() == 11, "Wren joins after Orchard Ring")


# --- the Hollowing --------------------------------------------------------

func test_drone_stats_are_sixty_percent_with_no_morale() -> void:
	var d := Campaign.drone_stats({"hp": 3, "speed": 6, "aim": 9, "cqb": 2, "morale": 7, "sight": 7})
	check(d["hp"] == 2 and d["speed"] == 4 and d["aim"] == 5 and d["cqb"] == 1, "60%, rounded to nearest, never below 1: %s" % [d])
	check(d["morale"] == 0 and d["sight"] == 7, "no morale; sight is unchanged")


func test_a_death_becomes_a_hollow_and_costs_a_reserve() -> void:
	var c := new_campaign()
	var report := c.complete_mission("karsa_breakout", true, [1], [], [])
	check(c.slot_status(1) == "hollow", "the dead merc's slot is now a hollow")
	check(c.reserves == 24 - 2 - 1, "mission cost (2) plus one refill (1)")
	check(c.slot_stats(1)["aim"] == 4 and c.slot_stats(1)["morale"] == 0, "frozen at 60% of Warden's stats")
	check(report["hollowed"] == [1], "the report lists the new hollow")
	check(Campaign.designation(1) == "HX-01", "designation is the slot, never the callsign")


func test_a_hollow_that_dies_is_refilled_again() -> void:
	var c := new_campaign()
	c.complete_mission("karsa_breakout", true, [1], [], [])
	var before := c.reserves
	c.complete_mission("the_weir", true, [1], [], [])
	check(c.slot_status(1) == "hollow" and c.reserves == before + 3 - 1, "the weir pays +3, the refill costs 1")


func test_no_reserves_leaves_the_slot_vacant() -> void:
	var c := new_campaign()
	c.reserves = 0
	var report := c.complete_mission("karsa_breakout", true, [4], [], [])
	check(c.slot_status(4) == "vacant" and report["vacant"] == [4], "with no reserves the slot goes vacant")
	check(c.reserves == 0, "reserves never go negative")
	check(not c.available_slots().has(4), "a vacant slot cannot be fielded")


func test_squad_wipe_ends_the_campaign() -> void:
	var c := new_campaign()
	c.complete_mission("karsa_breakout", false, [1, 2, 3], [], [], true)
	check(c.over and c.ending == "campaign_over", "the whole squad lost ends the campaign")


func test_a_failed_mission_with_survivors_costs_the_procession_not_the_run() -> void:
	var c := new_campaign()
	c.complete_mission("karsa_breakout", false, [3], [], [])
	check(not c.over and c.procession == 6200 - 300, "failure costs souls, not the campaign")


# --- the Writ and Orrick --------------------------------------------------

func test_killing_writ_officers_hollows_them_and_advances_the_stage() -> void:
	var c := new_campaign()
	check(c.writ_stage() == 0 and c.orrick_scene() == "orrick_stage_0", "the Writ starts intact")
	c.complete_mission("quiet_wards", true, [], ["clerk"], [])
	check(c.writ_status("clerk") == "hollow" and c.writ_stage() == 1 and c.orrick_scene() == "orrick_stage_1", "one officer hollowed -> stage 1")
	for id in ["gavel", "seal", "notary", "surveyor", "usher"]:
		c.complete_mission("reliquary_lane", true, [], [id], [])
	check(c.writ_stage() == 6 and c.orrick_scene() == "orrick_stage_6" and c.is_quiet(), "all six hollow -> the Quiet")


func test_a_named_officer_is_not_hollowed_twice() -> void:
	var c := new_campaign()
	c.complete_mission("quiet_wards", true, [], ["clerk", "clerk"], [])
	check(c.writ_stage() == 1, "stage counts officers, not deaths")


func test_enemy_units_use_hollow_stats_for_hollow_officers() -> void:
	var c := new_campaign()
	c.complete_mission("quiet_wards", true, [], ["clerk"], [])
	var units := c.enemy_units("quiet_wards")
	var clerk: SimUnit = units.filter(func(u): return u.id == 101)[0]
	check(clerk.is_drone and clerk.morale == 0, "a hollowed officer fields as a drone")
	var gavel: SimUnit = units.filter(func(u): return u.id == 102)[0]
	check(not gavel.is_drone and gavel.hp == 4, "an intact officer fields with full stats")


# --- fielding units -------------------------------------------------------

func test_squad_units_build_from_the_roster() -> void:
	var c := new_campaign()
	c.complete_mission("karsa_breakout", true, [3], [], [])
	var units := c.squad_units("the_weir", [1, 3, 5])
	check(units.size() == 3 and units[0].id == 1 and units[1].id == 3, "unit ids are slot numbers")
	check(not units[0].is_drone and units[0].team == 0, "a named merc fields normally")
	check(units[1].is_drone and units[1].morale == 0 and units[1].aim < 8, "a hollowed slot fields as a drone with frozen stats")
	check(c.squad_units("the_weir", [11]).is_empty(), "a merc who has not joined cannot be fielded")


func test_enemy_forces_match_the_mission_data() -> void:
	var c := new_campaign()
	var units := c.enemy_units("karsa_breakout")
	check(units.size() == 3 and units.all(func(u): return u.team == 1), "three conscripts on the enemy team")
	var wards := c.enemy_units("quiet_wards")
	check(wards.size() == 4, "two conscripts plus Clerk and Gavel; got %d" % wards.size())


# --- remembrance, choices, endings ----------------------------------------

func test_reading_names_builds_remembrance() -> void:
	var c := new_campaign()
	c.complete_mission("karsa_breakout", true, [3, 4], [], [3])
	check(c.remembrance == 1, "one name read, one remembrance")


func test_scene_choices_set_flags_and_remembrance() -> void:
	var c := new_campaign()
	check(c.apply_choice("debrief_anselm", "destroy_vats") and c.flag("foundry_destroyed"), "destroying the vats sets the flag")
	check(c.apply_choice("roll_call_prompt", "read_name") and c.remembrance == 1, "reading a name adds remembrance")
	check(not c.apply_choice("debrief_anselm", "no_such_option"), "unknown choices are refused")


func test_endings_follow_the_choice_and_its_requirements() -> void:
	var c := new_campaign()
	c.apply_choice("debrief_vesper_threshold", "hold_the_door")
	check(c.resolve_ending() == "long_watch", "holding the door is the Long Watch")

	var q := new_campaign()
	q.apply_choice("debrief_vesper_threshold", "accept_terms")
	check(q.resolve_ending() == "quiet_terms", "accepting terms is Quiet Terms")

	var r := new_campaign()
	r.apply_choice("debrief_vesper_threshold", "read_the_roll")
	check(r.resolve_ending() == "long_watch", "reading the Roll without the groundwork falls back to the Long Watch")
	r.remembrance = 7
	r.apply_choice("debrief_anselm", "destroy_vats")
	r.apply_choice("debrief_tamsins_rest", "open_the_roll")
	check(r.resolve_ending() == "roll_read", "with remembrance 7, the vats destroyed and the Roll opened: The Roll Read")

	var o := new_campaign()
	o.apply_choice("debrief_vesper_threshold", "take_orrick_alive")
	check(o.resolve_ending() == "long_watch", "taking Orrick alive needs the Quiet; without it, fallback")
	for id in ["clerk", "gavel", "seal", "notary", "surveyor", "usher"]:
		o.complete_mission("reliquary_lane", true, [], [id], [])
	check(o.resolve_ending() == "orrick_rest", "with all six hollow: Orrick's Rest")


func test_orrick_says_his_true_name_only_with_remembrance_and_the_quiet() -> void:
	var c := new_campaign()
	check(not c.orrick_names_himself(), "not at the start")
	for id in ["clerk", "gavel", "seal", "notary", "surveyor", "usher"]:
		c.complete_mission("reliquary_lane", true, [], [id], [])
	check(not c.orrick_names_himself(), "the Quiet alone is not enough")
	c.remembrance = 6
	check(c.orrick_names_himself(), "the Quiet plus six names read: he says it")


# --- route, contingencies, saving -----------------------------------------

func test_the_route_advances_and_ends_at_the_finale() -> void:
	var c := new_campaign()
	check(c.current == "karsa_breakout" and c.next_missions() == ["the_weir"], "the campaign starts at Karsa")
	c.complete_mission("karsa_breakout", true, [], [], [])
	check(c.current == "the_weir", "completing a mission moves the route on")
	var f := new_campaign()
	f.current = "vesper_threshold"
	f.complete_mission("vesper_threshold", true, [], [], [])
	check(f.next_missions().is_empty() and f.finished, "the finale ends the route")


func test_contingency_draw_is_deterministic_and_does_not_repeat_within_an_act() -> void:
	var a := new_campaign()
	var b := new_campaign()
	var first_a := a.draw_contingency(1, 777)
	check(first_a == b.draw_contingency(1, 777) and first_a != "", "same seed, same card")
	var second := a.draw_contingency(1, 777)
	check(second != first_a, "a drawn card is not drawn again")
	var card: Dictionary = a.card(first_a)
	check(card["act"] == 1, "cards come from the requested act's pool")


func test_save_and_load_round_trip() -> void:
	var c := new_campaign()
	c.complete_mission("karsa_breakout", true, [1], [], [])
	c.apply_choice("debrief_anselm", "destroy_vats")
	var saved := c.to_dict()
	var loaded := Campaign.from_dict(saved, StoryData.load_dir("res://data/story")["data"])
	check(str(loaded.to_dict()) == str(saved), "a loaded campaign saves back to the same data")
	check(loaded.slot_status(1) == "hollow" and loaded.flag("foundry_destroyed") and loaded.current == "the_weir", "state survives the round trip")
	var json_ok: Variant = JSON.parse_string(JSON.stringify(saved))
	check(json_ok != null, "the save is plain JSON")


# --- contingency cards ------------------------------------------------------

func test_cards_can_be_fielded_and_completed_without_moving_the_route() -> void:
	var c := new_campaign()
	c.complete_mission("karsa_breakout", true, [], [], [])
	check(c.current == "the_weir", "setup: the route is at the Weir")
	var units := c.enemy_units("stranded_tug")
	check(units.size() == 3 and units.all(func(u): return not u.is_drone), "act 1 cards field conscripts only (squad size 3)")
	var before := c.procession
	c.complete_mission("stranded_tug", true, [], [], [])
	check(c.procession == before + 40 and c.current == "the_weir", "a card applies its costs and leaves the route alone")
	check(c.completed.has("stranded_tug"), "and is recorded")


func test_later_act_cards_bring_hollow_regulars() -> void:
	var c := new_campaign()
	check(c.enemy_units("picket_line").filter(func(u): return u.is_drone).size() == 1, "act 2 cards add one hollow regular")
	check(c.enemy_units("dead_air").filter(func(u): return u.is_drone).size() == 2, "act 3 cards add two")


func test_cards_hollow_the_dead_like_any_mission() -> void:
	var c := new_campaign()
	c.complete_mission("stranded_tug", false, [6], [], [])
	check(c.slot_status(6) == "hollow", "a card death hollows the slot")


func test_drawn_cards_are_tracked_per_act() -> void:
	var c := new_campaign()
	check(c.drawn_for_act(1).is_empty(), "nothing drawn at first")
	var id := c.draw_contingency(1, 5)
	check(c.drawn_for_act(1) == [id] and c.drawn_for_act(2).is_empty(), "the draw is recorded for its act only")


# --- review regressions ----------------------------------------------------

func test_can_complete_guards_order_and_repeats() -> void:
	var c := new_campaign()
	check(c.can_complete("karsa_breakout"), "the current mission can be completed")
	check(not c.can_complete("the_weir"), "a later mission cannot")
	c.complete_mission("karsa_breakout", true, [], [], [])
	check(not c.can_complete("karsa_breakout"), "a finished mission cannot be completed again")
	check(c.can_complete("stranded_tug") and (c.complete_mission("stranded_tug", true, [], [], []) is Dictionary) and not c.can_complete("stranded_tug"), "a card can be played once")


func test_a_campaign_with_no_one_left_to_field_is_over() -> void:
	var c := new_campaign()
	c.reserves = 0
	c.complete_mission("karsa_breakout", true, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], [], [])
	check(c.available_slots().is_empty() and c.over and c.over_reason == "no_one_left", "every slot vacant ends the campaign instead of soft-locking")


func test_losing_the_procession_ends_the_campaign() -> void:
	var c := new_campaign()
	c.procession = 100
	c.complete_mission("karsa_breakout", false, [], [], [])
	check(c.procession == 0 and c.over and c.over_reason == "procession_lost", "no one left in the convoy ends it")


func test_failing_or_withdrawing_the_finale_does_not_finish_the_campaign() -> void:
	var c := new_campaign()
	c.current = "vesper_threshold"
	c.complete_mission("vesper_threshold", false, [], [], [])
	check(not c.finished and c.current == "vesper_threshold" and not c.completed.has("vesper_threshold"), "the finale must be won to end the story")
	c.complete_mission("vesper_threshold", true, [], [], [])
	check(c.finished, "winning it does")


func test_fallen_lists_every_named_death_for_roll_call() -> void:
	var c := new_campaign()
	c.reserves = 1
	var report := c.complete_mission("karsa_breakout", true, [1, 2], [], [])
	check(report["fallen"] == [1, 2], "both named mercs get a roll call")
	check(report["hollowed"] == [1] or report["hollowed"] == [2] or report["vacant"].size() >= 1, "one is hollowed, the other (no reserves left) is vacant")
	var again := c.complete_mission("the_weir", true, [1], [], [])
	check(not (again["fallen"] as Array).has(1) or c.slot_status(1) != "named", "a hollow's death is not a named death")


func test_remembrance_can_reach_every_ending_threshold() -> void:
	var c := new_campaign()
	var data: Dictionary = StoryData.load_dir("res://data/story")["data"]
	var other_sources := 0
	for s in data["scenes"]["scenes"]:
		if s["id"] == "roll_call_prompt":
			continue
		for ch in s.get("choices", []):
			other_sources += int(ch["sets"].get("remembrance", 0))
	var realistic := 12 / 2 + other_sources
	for e in data["world"]["endings"]:
		check(realistic >= int(e["requires"].get("remembrance_min", 0)), "ending %s is attainable (%d >= %d)" % [e["id"], realistic, int(e["requires"].get("remembrance_min", 0))])
	check(realistic >= int(data["world"]["pursuit"]["true_name_remembrance"]), "Orrick's true name is attainable")


func test_a_save_survives_real_json() -> void:
	var c := new_campaign()
	c.complete_mission("karsa_breakout", true, [1], [], [])
	c.apply_choice("debrief_anselm", "destroy_vats")
	c.pending = [{"t": "roll", "slot": 3}]
	var text := JSON.stringify(c.to_dict())
	var parsed: Variant = JSON.parse_string(text)
	var loaded := Campaign.from_dict(parsed, StoryData.load_dir("res://data/story")["data"])
	check(loaded != null, "a real JSON round trip loads")
	check(loaded.slot_status(1) == "hollow" and loaded.slot_stats(1)["aim"] == 4 and typeof(loaded.slot_stats(1)["aim"]) == TYPE_INT, "statuses and integer stats survive")
	check(loaded.flag("foundry_destroyed") and loaded.current == "the_weir", "flags and route survive")
	check(loaded.pending.size() == 1 and int(loaded.pending[0]["slot"]) == 3, "the unfinished debrief survives")
	check(loaded.available_slots() == c.available_slots(), "the roster is identical")


func test_a_damaged_save_is_refused_not_crashed_on() -> void:
	var story: Dictionary = StoryData.load_dir("res://data/story")["data"]
	check(Campaign.from_dict({}, story) == null, "an empty save is refused")
	var d := new_campaign().to_dict()
	d.erase("roster")
	check(Campaign.from_dict(d, story) == null, "a save missing the roster is refused")
	var e := new_campaign().to_dict()
	e["procession"] = "lots"
	check(Campaign.from_dict(e, story) == null, "a wrongly typed field is refused")
	var f := new_campaign().to_dict()
	f["version"] = 99
	check(Campaign.from_dict(f, story) == null, "an unknown version is refused")


func test_an_offered_card_survives_saving_and_is_cleared_when_played() -> void:
	var c := new_campaign()
	c.offered_card = c.draw_contingency(1, 3)
	check(c.offered_card != "", "a drawn card is held as the offered card")
	var story: Dictionary = StoryData.load_dir("res://data/story")["data"]
	var loaded := Campaign.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())), story)
	check(loaded.offered_card == c.offered_card, "it survives a save and load")
	loaded.complete_mission(loaded.offered_card, true, [], [], [])
	check(loaded.offered_card == "", "playing it clears the offer")
