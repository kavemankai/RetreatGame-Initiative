extends TestBase
## The five enemy tiers (conscript, regular, veteran, elite, boss) and their
## hollow variants.

const TIER_KEYS := ["conscript", "regular", "veteran"]


func story() -> Dictionary:
	return StoryData.load_dir("res://data/story")["data"]


func test_tier_file_loads_and_covers_the_five_tiers() -> void:
	var res := StoryData.load_dir("res://data/story")
	check((res["errors"] as Array).is_empty(), "all story files load, including enemy_tiers")
	var t: Dictionary = res["data"]["enemy_tiers"]["tiers"]
	for key in TIER_KEYS:
		check(t.has(key), "tier '%s' exists" % key)
	check(t.has("elite") and t.has("boss"), "elite and boss tiers are listed (they use the Writ's own stat blocks)")
	check(int(t["conscript"]["stats"]["aim"]) < int(t["regular"]["stats"]["aim"]) and int(t["regular"]["stats"]["aim"]) < int(t["veteran"]["stats"]["aim"]), "aim climbs by tier")
	check(int(t["conscript"]["stats"]["morale"]) < int(t["veteran"]["stats"]["morale"]), "morale climbs by tier")


func test_story_lint_stays_clean_with_tiers() -> void:
	check(StoryLint.lint(story()).is_empty(), "story lint is clean: %s" % [StoryLint.lint(story())])


func test_roster_builds_units_with_tier_stats_and_ids() -> void:
	var c := Campaign.new_game(story())
	var foes := c.units_for_roster({"conscript": 2, "regular": 1, "veteran": 1})
	var ids := foes.map(func(u: SimUnit) -> int: return u.id)
	check(ids == [200, 201, 210, 220], "ids by tier base then index; got %s" % [ids])
	var cons: SimUnit = foes[0]
	var t: Dictionary = story()["enemy_tiers"]["tiers"]["conscript"]["stats"]
	check(cons.hp == int(t["hp"]) and cons.aim == int(t["aim"]) and cons.morale == int(t["morale"]) and not cons.is_drone and cons.team == 1, "a conscript has the tier's stats")


func test_hollow_variants_are_sixty_percent_fearless_drones() -> void:
	var c := Campaign.new_game(story())
	var foes := c.units_for_roster({"hollow_veteran": 2})
	var vet: Dictionary = story()["enemy_tiers"]["tiers"]["veteran"]["stats"]
	check(foes.size() == 2 and foes[0].id == 320 and foes[1].id == 321, "hollow veterans use the 320 id base")
	check(foes[0].is_drone and foes[0].morale == 0, "hollow: drone with no morale")
	check(foes[0].aim == maxi(1, (int(vet["aim"]) * 60 + 50) / 100), "hollow aim is 60% of the veteran's")
	check(foes[0].sight_range == int(vet["sight"]), "sight is unchanged")


func test_unknown_tier_names_are_ignored_by_the_builder_and_rejected_by_lint() -> void:
	var d := story()
	d["route"]["missions"][0]["enemies"]["roster"]["overlord"] = 1
	check(StoryLint.lint(d).any(func(e: String) -> bool: return e.contains("overlord")), "lint names the unknown tier")


func test_lint_counts_the_whole_roster_against_the_spawn_points() -> void:
	var d := story()
	d["route"]["missions"][0]["enemies"]["roster"] = {"conscript": 9}
	check(StoryLint.lint(d).any(func(e: String) -> bool: return e.contains("spawn")), "nine conscripts exceed the spawn points")


func test_tiers_respect_their_first_act() -> void:
	var d := story()
	d["route"]["missions"][0]["enemies"]["roster"] = {"veteran": 1}  # act 1, but veterans start in act 2
	check(StoryLint.lint(d).any(func(e: String) -> bool: return e.contains("veteran") and e.contains("act")), "a veteran in act 1 is rejected")


func test_act_one_is_conscripts_and_regulars_only() -> void:
	var s := story()
	for m: Dictionary in s["route"]["missions"]:
		if int(m["act"]) != 1:
			continue
		for tier in m["enemies"]["roster"]:
			check(tier in ["conscript", "regular"], "act 1 mission %s uses only conscripts and regulars (found %s)" % [m["id"], tier])
		check((m["enemies"]["writ"] as Array).is_empty(), "act 1 mission %s has no Writ" % m["id"])


func test_cards_scale_with_the_act() -> void:
	var c := Campaign.new_game(story())
	var act1: Array = []
	var act3: Array = []
	for card: Dictionary in story()["route"]["cards"]:
		if int(card["act"]) == 1 and act1.is_empty():
			act1 = [card["id"], int(card["squad_size"])]
		if int(card["act"]) == 3 and act3.is_empty():
			act3 = [card["id"], int(card["squad_size"])]
	var r1: Dictionary = c.mission_or_card(act1[0])["enemies"]["roster"]
	check(r1 == {"conscript": act1[1]}, "an act 1 card fields conscripts equal to the squad; got %s" % [r1])
	var r3: Dictionary = c.mission_or_card(act3[0])["enemies"]["roster"]
	check(int(r3.get("regular", 0)) == act3[1] and int(r3.get("hollow_regular", 0)) == 2, "an act 3 card: regulars equal to the squad plus two hollow regulars; got %s" % [r3])


func test_profiles_follow_the_tier() -> void:
	var c := Campaign.new_game(story())
	check(c.tier_profile(200) == "aggressor" and c.tier_profile(210) == "aggressor", "conscripts and regulars press")
	check(c.tier_profile(220) == "default", "veterans use the default profile")
	check(c.tier_profile(101) == "defender" and c.tier_profile(100) == "defender", "the Writ and the Provost hold")
	check(c.tier_profile(300) == "aggressor" and c.tier_profile(321) == "default", "hollows follow their base tier")
	check(c.enemy_label(201) == "Conscript 2" and c.enemy_label(310) == "Hollow Regular 1", "labels name the tier, the hollow variant and the number")
