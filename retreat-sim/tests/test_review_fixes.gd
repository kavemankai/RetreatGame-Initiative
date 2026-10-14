extends TestBase
## Regressions from the hit-chance / tiers / equipment code review.


func story() -> Dictionary:
	return StoryData.load_dir("res://data/story")["data"]


func new_campaign() -> Campaign:
	return Campaign.new_game(story())


func test_opener_bonus_is_in_the_preview_until_a_shot_is_queued() -> void:
	var s := make_state(20, 10)
	var shooter := add_unit(s, 1, 0, Vector2i(2, 5), 3, 5, 5)
	var target := add_unit(s, 2, 1, Vector2i(6, 5), 3)
	shooter.gear_trait = "opener"
	var plain: int = SimResolver.evaluate_shot(s.grid, shooter, shooter.pos, target)["chance"]
	var ready: int = SimResolver.evaluate_shot(s.grid, shooter, shooter.pos, target, true)["chance"]
	check(ready == plain + SimConst.OPENER_HIT_BONUS, "the shared evaluation adds the opener bonus when the shooter is ready")
	var b := PlanBuilder.new(s, 0)
	check(int(b.shot_preview(1, 2)["chance"]) == ready, "the planning preview shows the first-shot chance")
	b.queue_shoot(1, 2)
	check(int(b.shot_preview(1, 2)["chance"]) == plain, "after one shot is queued the next preview drops the bonus")


func test_lint_catches_id_range_and_profile_mistakes_in_tiers() -> void:
	var d := story()
	d["enemy_tiers"]["hollow"]["id_base_offset"] = 10
	check(StoryLint.lint(d).any(func(e: String) -> bool: return e.contains("overlap")), "hollow ids that collide with other tiers are rejected")
	d = story()
	d["enemy_tiers"]["tiers"]["veteran"]["id_base"] = 5
	check(StoryLint.lint(d).any(func(e: String) -> bool: return e.contains("overlap") and e.contains("merc")), "tier ids inside the merc slots are rejected")
	d = story()
	d["enemy_tiers"]["tiers"]["regular"]["profile"] = "berserker"
	check(StoryLint.lint(d).any(func(e: String) -> bool: return e.contains("berserker")), "an unknown AI profile is rejected")
	d = story()
	d["items"]["slots"] = ["armour", "weapon", "mod", "boots"]
	check(StoryLint.lint(d).any(func(e: String) -> bool: return e.contains("slots")), "item slots must match the game's slots")


func test_save_problem_checks_gear_and_stash_shapes() -> void:
	var c := new_campaign()
	var d := c.to_dict()
	d["stash"] = "x"
	check(Campaign.save_problem(d) != "", "a stash that is not a list is refused")
	d = c.to_dict()
	d["stash"] = [1, null]
	check(Campaign.save_problem(d) != "", "a stash of non-strings is refused")
	d = c.to_dict()
	d["roster"]["1"]["gear"] = null
	check(Campaign.save_problem(d) != "", "gear that is not a dictionary is refused")
	check(Campaign.save_problem(c.to_dict()) == "", "a good save still loads")


func test_loading_drops_unknown_or_mismatched_item_ids() -> void:
	var c := new_campaign()
	var d := c.to_dict()
	d["stash"] = ["carbine", "retired_item"]
	d["roster"]["1"]["gear"] = {"armour": "carbine", "weapon": "gone_gun", "mod": "scope"}  # carbine is not armour
	var loaded := Campaign.from_dict(d, c.story)
	check(loaded != null and loaded.stash == ["carbine"], "unknown stash ids are dropped")
	var g := loaded.gear_of(1)
	check(g["armour"] == "" and g["weapon"] == "" and g["mod"] == "scope", "wrong-slot and unknown worn ids are dropped, good ones kept")


func test_a_hollow_officer_who_dies_again_drops_nothing() -> void:
	var c := new_campaign()
	for id in ["karsa_breakout", "the_weir", "pellam_dock", "orchard_ring"]:
		c.complete_mission(id, true, [], [], [])
	c.complete_mission("quiet_wards", true, [], ["gavel"], [])
	var plates := c.stash.count("gavel_plate")
	var again := c.complete_mission("anselm", true, [], ["gavel"], [])
	check(c.stash.count("gavel_plate") == plates and not (again["loot"] as Array).has("gavel_plate"), "the second kill does not drop the plate again")


func test_to_dict_does_not_alias_the_live_roster() -> void:
	var c := new_campaign()
	var d := c.to_dict()
	d["roster"]["1"]["stats"]["hp"] = 99
	check(int(c.slot_stats(1)["hp"]) != 99, "changing the dictionary does not change the campaign")


func test_enemy_labels_are_numbered_within_a_tier() -> void:
	var c := new_campaign()
	check(c.enemy_label(200) == "Conscript 1" and c.enemy_label(202) == "Conscript 3", "three conscripts read as 1, 2, 3")
	check(c.enemy_label(311) == "Hollow Regular 2", "hollow variants are numbered too")
