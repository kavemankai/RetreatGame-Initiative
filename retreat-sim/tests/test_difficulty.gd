extends TestBase
## Difficulty: Standard changes nothing; Story gives the squad one more hit point and takes accuracy off the enemy,
## and the choice survives a save.

func story() -> Dictionary:
	return StoryData.load_dir("res://data/story")["data"]


func campaign_on(level: String) -> Campaign:
	var c := Campaign.new_game(story())
	check(c.set_difficulty(level), "%s is a known difficulty" % level)
	return c


func squad_of(c: Campaign) -> Array[SimUnit]:
	return c.squad_units("karsa_breakout", c.available_slots().slice(0, 3))


func test_a_new_campaign_is_standard() -> void:
	var c := Campaign.new_game(story())
	check(c.difficulty == "standard", "default difficulty (%s)" % c.difficulty)


func test_standard_leaves_every_stat_alone() -> void:
	var std := campaign_on("standard")
	var base := Campaign.new_game(story())
	var a := squad_of(std)
	var b := squad_of(base)
	for i in a.size():
		check(a[i].hp == b[i].hp and a[i].hit_bonus == b[i].hit_bonus, "standard squad unit %d matches the plain campaign" % i)
	for u in std.enemy_units("karsa_breakout"):
		check(u.hit_bonus == 0, "standard enemy %d has no accuracy change" % u.id)


func test_story_adds_a_hit_point_to_the_squad_and_takes_accuracy_from_enemies() -> void:
	var std := campaign_on("standard")
	var easy := campaign_on("story")
	var a := squad_of(std)
	var b := squad_of(easy)
	check(a.size() == b.size() and not a.is_empty(), "same squad size")
	for i in a.size():
		check(b[i].hp == a[i].hp + 1, "story squad unit %d has one more hp (%d vs %d)" % [i, b[i].hp, a[i].hp])
		check(b[i].team == 0, "squad stays on team 0")
	for id in ["the_weir", "mirror_gate", "vesper_threshold"]:
		var s := std.enemy_units(id)
		var e := easy.enemy_units(id)
		check(s.size() == e.size() and not s.is_empty(), "%s: same enemies" % id)
		for i in s.size():
			check(e[i].hit_bonus == s[i].hit_bonus + Campaign.DIFFICULTIES["story"]["enemy_hit"], "%s enemy %d: accuracy lowered" % [id, e[i].id])
			check(e[i].hp == s[i].hp, "%s enemy %d: hit points unchanged" % [id, e[i].id])


func test_tier_units_placed_by_a_map_also_get_the_change() -> void:
	var std := campaign_on("standard")
	var easy := campaign_on("story")
	var a := std.tier_unit("regular", 210, Vector2i(3, 3))
	var b := easy.tier_unit("regular", 210, Vector2i(3, 3))
	check(b.hit_bonus == a.hit_bonus + Campaign.DIFFICULTIES["story"]["enemy_hit"], "a map-placed regular is easier too")


func test_a_card_shows_the_hp_a_merc_will_field_with() -> void:
	var easy := campaign_on("story")
	var slot: int = easy.available_slots()[0]
	var eff := easy.effective_stats(slot)
	var u := easy.squad_units("karsa_breakout", [slot])[0]
	check(int(eff["hp"]) == u.hp, "the roster card's hp (%d) is the fielded hp (%d)" % [int(eff["hp"]), u.hp])


func test_the_choice_survives_a_save_and_an_old_save_is_standard() -> void:
	var easy := campaign_on("story")
	var d := easy.to_dict()
	check(d["difficulty"] == "story", "saved")
	var back := Campaign.from_dict(JSON.parse_string(JSON.stringify(d)), story())
	check(back != null and back.difficulty == "story", "loaded through JSON")
	d.erase("difficulty")
	var old := Campaign.from_dict(d, story())
	check(old != null and old.difficulty == "standard", "a save with no difficulty loads as standard")


func test_a_corrupt_difficulty_is_refused_with_a_reason() -> void:
	var d := Campaign.new_game(story()).to_dict()
	d["difficulty"] = "nightmare"
	check(Campaign.save_problem(d).contains("difficulty"), "unknown level named in the reason (%s)" % Campaign.save_problem(d))
	d["difficulty"] = 3
	check(Campaign.save_problem(d).contains("difficulty"), "wrong type named in the reason")
	check(Campaign.from_dict(d, story()) == null, "not loaded")


func test_an_unknown_level_cannot_be_set() -> void:
	var c := Campaign.new_game(story())
	check(not c.set_difficulty("easy_mode"), "unknown level refused")
	check(c.difficulty == "standard", "unchanged after a refusal")


func test_next_difficulty_cycles_through_every_level() -> void:
	var seen: Array[String] = []
	var level := "standard"
	for i in Campaign.DIFFICULTIES.size():
		seen.append(level)
		level = Campaign.next_difficulty(level)
	check(level == "standard" and seen.size() == Campaign.DIFFICULTIES.size(), "a full cycle returns to the start (%s)" % [seen])
