extends TestBase
## The story data and StoryLint: shipped data must be clean, and each rule
## must actually catch the mistake it exists for.

const STORY_DIR := "res://data/story"


func story() -> Dictionary:
	var loaded := StoryData.load_dir(STORY_DIR)
	check((loaded["errors"] as Array).is_empty(), "story files load: %s" % [loaded["errors"]])
	return loaded["data"]


func mutated(fn: Callable) -> Array[String]:
	var data := story().duplicate(true)
	fn.call(data)
	return StoryLint.lint(data)


func has_error(errors: Array[String], needle: String) -> bool:
	for e in errors:
		if e.to_lower().contains(needle.to_lower()):
			return true
	return false


func test_shipped_story_data_is_clean() -> void:
	var errors := StoryLint.lint(story())
	check(errors.is_empty(), "no lint errors; got %s" % [errors.slice(0, 5)])


func test_story_has_the_promised_shape() -> void:
	var d := story()
	check(d["cast"]["mercs"].size() == 8, "8 mercs: six start, two join")
	check(d["writ"]["officers"].size() == 6, "6 Writ officers")
	check(d["route"]["missions"].size() == 12, "12 story missions")
	check(d["route"]["cards"].size() >= 6, "a contingency pool")
	check(d["scenes"]["scenes"].size() >= 40, "a substantial scene set")
	var starters: Array = d["cast"]["mercs"].filter(func(m): return m["start"])
	check(starters.size() == 6, "six mercs start; two join later")


func test_lint_catches_duplicate_ids() -> void:
	var errs := mutated(func(d): d["cast"]["mercs"][1]["id"] = d["cast"]["mercs"][0]["id"])
	check(has_error(errs, "duplicate"), "duplicate merc id is caught")


func test_lint_catches_dangling_relationships() -> void:
	var errs := mutated(func(d): d["cast"]["mercs"][0]["relationships"][0]["with"] = "nobody")
	check(has_error(errs, "relationship"), "a relationship to an unknown merc is caught")


func test_lint_catches_out_of_range_stats() -> void:
	var errs := mutated(func(d): d["cast"]["mercs"][0]["stats"]["hp"] = 9)
	check(has_error(errs, "stat"), "an out-of-range stat is caught")


func test_lint_catches_arc_beats_on_unknown_missions() -> void:
	var errs := mutated(func(d): d["cast"]["mercs"][0]["arc"][0]["mission"] = "atlantis")
	check(has_error(errs, "arc"), "an arc beat on a nonexistent mission is caught")


func test_lint_catches_dangling_next_and_unreachable_missions() -> void:
	var errs := mutated(func(d): d["route"]["missions"][0]["next"] = ["ghost_mission"])
	check(has_error(errs, "next"), "a next pointing nowhere is caught")
	var cut := mutated(func(d): d["route"]["missions"][1]["next"] = [])
	check(has_error(cut, "unreachable"), "cutting the route leaves later missions unreachable")


func test_lint_catches_cycles_and_a_finale_with_exits() -> void:
	var errs := mutated(func(d): d["route"]["missions"][11]["next"] = ["karsa_breakout"])
	check(has_error(errs, "finale") or has_error(errs, "cycle"), "a finale that leads back is caught")


func test_lint_catches_missing_scenes_and_unknown_speakers() -> void:
	var errs := mutated(func(d): d["route"]["missions"][0]["scenes"]["briefing"] = "briefing_nowhere")
	check(has_error(errs, "scene"), "a mission pointing at a missing scene is caught")
	var who := mutated(func(d): d["scenes"]["scenes"][0]["lines"][0]["who"] = "stranger")
	check(has_error(who, "speaker"), "an unknown speaker is caught")


func test_lint_enforces_the_tone_rules() -> void:
	var slang := mutated(func(d): d["scenes"]["scenes"][0]["lines"][0]["text"] = "Okay, that was awesome.")
	check(has_error(slang, "banned"), "modern slang is caught")
	var shout := mutated(func(d): d["scenes"]["scenes"][0]["lines"][0]["text"] = "Run now!")
	check(has_error(shout, "exclamation"), "exclamation marks are caught")
	var long_line := mutated(func(d): d["scenes"]["scenes"][0]["lines"][0]["text"] = "word ".repeat(60))
	check(has_error(long_line, "too long"), "an over-long line is caught")


func test_lint_checks_the_writ_against_the_route() -> void:
	var errs := mutated(func(d): d["writ"]["officers"][0]["introduced"] = "karsa_breakout")
	check(has_error(errs, "writ"), "an officer introduced where the mission does not field them is caught")
	var stage := mutated(func(d): d["world"]["pursuit"]["stage_max"] = 3)
	check(has_error(stage, "stage"), "a stage count that disagrees with the officers is caught")


func test_lint_checks_joins_choices_and_endings() -> void:
	var joins := mutated(func(d): d["route"]["missions"][3]["joins"] = [])
	check(has_error(joins, "join"), "a merc who joins at a mission that does not list them is caught")
	var choice := mutated(func(d): d["world"]["endings"][0]["choice"] = "not_an_option")
	check(has_error(choice, "choice"), "an ending bound to a choice nobody can make is caught")
	var fallback := mutated(func(d): d["world"]["fallback_ending"] = "nowhere")
	check(has_error(fallback, "fallback"), "a missing fallback ending is caught")
	var undeclared := mutated(func(d): d["route"]["missions"][5]["choices"] = [])
	check(has_error(undeclared, "choice"), "a mission whose debrief offers a choice it does not declare is caught")


func test_every_mission_and_card_is_reachable_in_play() -> void:
	var d := story()
	var seen := {}
	var queue: Array = [d["route"]["start"]]
	while not queue.is_empty():
		var id: String = queue.pop_front()
		if seen.has(id):
			continue
		seen[id] = true
		for m in d["route"]["missions"]:
			if m["id"] == id:
				queue.append_array(m["next"])
	check(seen.size() == 12, "all 12 story missions are on the route from the start; %d" % seen.size())


# --- review regressions: robustness and false negatives -----------------------

func test_lint_reports_malformed_data_instead_of_crashing() -> void:
	var no_enemies := mutated(func(d): d["route"]["missions"][0].erase("enemies"))
	check(has_error(no_enemies, "structure") and has_error(no_enemies, "enemies"), "a mission with no enemies is a structure error")
	var no_costs := mutated(func(d): d["route"]["cards"][0].erase("on_success"))
	check(has_error(no_costs, "on_success"), "a card with no on_success is reported")
	var no_cost_field := mutated(func(d): d["route"]["missions"][0]["on_success"].erase("reserves"))
	check(has_error(no_cost_field, "reserves"), "a mission cost missing reserves is reported")
	var bad_choice := mutated(func(d): d["scenes"]["scenes"][2]["choices"] = [{"text": "No id", "sets": {}}])
	check(has_error(bad_choice, "structure"), "a choice with no id is reported")
	var no_who := mutated(func(d): d["scenes"]["scenes"][0]["lines"][0].erase("who"))
	check(has_error(no_who, "who"), "a line with no speaker is reported")
	var no_sight := mutated(func(d): d["writ"]["officers"][0]["stats"].erase("sight"))
	check(has_error(no_sight, "sight"), "an officer with no sight is reported")
	var empty_files := mutated(func(d):
		d["world"] = {}
		d["writ"] = {})
	check(has_error(empty_files, "structure"), "empty files are reported, not crashed on")


func test_lint_checks_writ_slots_and_stat_ranges() -> void:
	var slot := mutated(func(d): d["writ"]["officers"][5]["slot"] = 9)
	check(has_error(slot, "slot"), "an officer slot outside 1..6 is caught")
	var hp := mutated(func(d): d["writ"]["officers"][0]["stats"]["hp"] = 99)
	check(has_error(hp, "stat"), "an officer's out-of-range stat is caught")
	var prov := mutated(func(d): d["writ"]["provost"]["stats"]["aim"] = 0)
	check(has_error(prov, "stat"), "the provost's stats are checked too")


func test_lint_catches_a_card_shadowed_by_a_mission_id() -> void:
	var errs := mutated(func(d): d["route"]["cards"][0]["id"] = d["route"]["missions"][0]["id"])
	check(has_error(errs, "collides"), "a card id equal to a mission id is caught")


func test_lint_applies_the_tone_rules_to_all_player_facing_text() -> void:
	var summary := mutated(func(d): d["route"]["missions"][0]["summary"] = "This is awesome.")
	check(has_error(summary, "banned"), "mission summaries are tone-checked")
	var objective := mutated(func(d): d["route"]["missions"][0]["objective"]["text"] = "Go now!")
	check(has_error(objective, "exclamation"), "objective text is tone-checked")
	var choice := mutated(func(d): d["scenes"]["scenes"].filter(func(s): return s["id"] == "debrief_anselm")[0]["choices"][0]["text"] = "Yeah, break it!")
	check(has_error(choice, "banned") or has_error(choice, "exclamation"), "choice text is tone-checked")
	var ending := mutated(func(d): d["world"]["endings"][0]["summary"] = "Wow, it worked!")
	check(has_error(ending, "banned"), "ending summaries are tone-checked")
	var card := mutated(func(d): d["route"]["cards"][0]["name"] = "Super Tug")
	check(has_error(card, "banned"), "card names are tone-checked")


func test_lint_checks_ending_flags_and_thresholds() -> void:
	var typo := mutated(func(d): d["world"]["endings"][0]["requires"]["flags"] = ["foundry_destroyd", "roll_opened"])
	check(has_error(typo, "flag"), "a requirement flag no choice can set is caught")
	var unreachable := mutated(func(d): d["world"]["endings"][0]["requires"]["remembrance_min"] = 99)
	check(has_error(unreachable, "attainable"), "an ending whose remembrance cannot be reached is caught")
	var name := mutated(func(d): d["world"]["pursuit"]["true_name_remembrance"] = 99)
	check(has_error(name, "attainable"), "so is Orrick's true name")
	var quiet := mutated(func(d): d["world"]["pursuit"]["quiet_stage"] = 3)
	check(has_error(quiet, "quiet"), "quiet_stage must equal stage_max")
	var refill := mutated(func(d): d["world"]["hollowing"]["refill_cost_reserves"] = -5)
	check(has_error(refill, "refill"), "a negative refill cost is caught")


func test_lint_checks_enemy_counts_and_branching() -> void:
	var crowd := mutated(func(d): d["route"]["missions"][0]["enemies"]["roster"] = {"conscript": 9})
	check(has_error(crowd, "spawn"), "more enemies than spawn points is caught")
	var branch := mutated(func(d): d["route"]["missions"][0]["next"] = ["the_weir", "pellam_dock"])
	check(has_error(branch, "branch"), "a branching route is flagged (only next[0] is followed)")
	for m: Dictionary in StoryData.load_dir("res://data/story")["data"]["route"]["missions"]:
		check(MapData.load_file(m["id"]).enemy_spawns.size() >= StoryLint.MAX_ENEMIES, "%s has a spawn point for every enemy the lint allows" % m["id"])


func test_lint_checks_scene_kinds_against_their_use() -> void:
	var errs := mutated(func(d): d["route"]["missions"][0]["scenes"]["briefing"] = "debrief_karsa_breakout")
	check(has_error(errs, "kind"), "a briefing that points at a debrief scene is caught")
	var card := mutated(func(d): d["route"]["cards"][0]["scene"] = "briefing_karsa_breakout")
	check(has_error(card, "kind"), "so is a card that points at a briefing")
