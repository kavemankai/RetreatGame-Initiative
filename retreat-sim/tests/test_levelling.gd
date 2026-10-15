extends TestBase
## Levelling: XP from battle, five levels, three seeded stat offers weighted by class, caps, hollows,
## saves, the plain-words effect text, and the level-up and roster screens.

var story: Dictionary = StoryData.load_dir("res://data/story")["data"]


func campaign() -> Campaign:
	return Campaign.new_game(story)


func row(slot: int, hits := 0, kills := 0, hits_taken := 0, steps := 0, alive := true) -> Dictionary:
	return {"slot": slot, "alive": alive, "shots": hits, "hits": hits, "kills": kills, "hits_taken": hits_taken, "steps": steps}


func nodes_of(root: Node, type_name: String) -> Array[Node]:
	var out: Array[Node] = []
	for child in root.get_children():
		if child.get_script() != null and (child.get_script() as Script).get_global_name() == type_name:
			out.append(child)
		out.append_array(nodes_of(child, type_name))
	return out


func button(root: Node, text: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b as Button
	return null


func test_the_progression_data_is_valid_and_matches_the_agreed_caps() -> void:
	var p: Dictionary = story["progression"]
	check(StoryLint.lint(story).is_empty(), "the story lints clean with progression: %s" % [StoryLint.lint(story).slice(0, 3)])
	var levels: Array = (p["levels"] as Array).map(func(v: Variant) -> int: return int(v))
	var caps := {}
	for k in p["caps"]:
		caps[k] = int(p["caps"][k])
	check(levels == [6, 14, 24, 36] and caps == {"hp": 6, "speed": 10, "aim": 10, "cqb": 10, "morale": 10, "sight": 9}, "five levels and the agreed caps (%s, %s)" % [levels, caps])
	check(campaign().max_level() == 5, "the top level is 5")
	var bad: Dictionary = StoryData.load_dir("res://data/story")["data"].duplicate(true)
	bad["progression"]["levels"] = [6, 5]
	check(not StoryLint.lint(bad).is_empty(), "levels that do not rise are caught")
	var no_weight: Dictionary = StoryData.load_dir("res://data/story")["data"].duplicate(true)
	no_weight["progression"]["class_weights"].erase("beam")
	check(not StoryLint.lint(no_weight).is_empty(), "a class with no weights is caught")


func test_xp_from_a_mission_follows_the_table_and_its_caps() -> void:
	var c := campaign()
	check(c.xp_from_row(row(1, 3, 1, 1), true) == 2 + 2 + 3 + 3 + 1, "deploy 2, objective 2, 3 hits, a kill (3), a hit survived: 11")
	check(c.xp_from_row(row(1, 3, 1, 1), false) == 9, "no objective bonus on a failure")
	check(c.xp_from_row(row(1, 20, 0, 9), false) == 2 + 6 + 2, "hits cap at 6 and survived hits at 2")


func test_levels_arrive_at_the_thresholds_and_stop_at_five() -> void:
	var c := campaign()
	check(c.apply_xp(1, 5)["level_after"] == 1 and c.levelup_pending(1) == 0, "5 XP: still level 1")
	var r := c.apply_xp(1, 1)
	check(r["level_after"] == 2 and r["pending"] == 1 and c.xp_next(1) == 14, "6 XP: level 2 with one pick waiting; next at 14")
	check(c.apply_xp(1, 30)["level_after"] == 5 and c.levelup_pending(1) == 4, "a big jump pays every level in between")
	c.apply_xp(1, 500)
	check(c.level_of(1) == 5 and c.levelup_pending(1) == 4 and c.xp_next(1) == 36, "level 5 is the top")


func test_only_surviving_named_mercs_earn_xp_from_a_mission() -> void:
	var c := campaign()
	var rows := [row(1, 2, 1, 0, 10), row(2, 0, 0, 0, 0, false), row(3, 1, 0, 1, 4)]
	var report := c.complete_mission("karsa_breakout", true, [2], [], [], false, 0, rows)
	var paid := {}
	for x: Dictionary in report["xp"]:
		paid[int(x["slot"])] = x
	check(paid.has(1) and paid.has(3) and not paid.has(2), "the dead merc earns nothing")
	check(paid[1]["gained"] == c.xp_from_row(rows[0], true) and c.xp_of(1) == int(paid[1]["gained"]), "the survivor is paid the table amount")
	check(c.slot_status(2) == "hollow" and c.award_xp(2, row(2), true).is_empty(), "and a hollow never earns")
	var e: Dictionary = c._roster[1]
	check(int(e["hits"]) == 2 and int(e["kills"]) == 1 and int(e["steps"]) == 10 and int(e["missions"]) == 1, "use counters are kept for the offers")


func test_offers_are_seeded_distinct_capped_and_class_weighted() -> void:
	var c := campaign()
	c.apply_xp(3, 6)  # Sable, a sniper
	var a := c.levelup_offer(3)
	var b := c.levelup_offer(3)
	check(a == b and a.size() == 3, "asking twice gives the same three")
	var stats := a.map(func(o: Dictionary) -> String: return o["stat"])
	check(stats.size() == 3 and (stats as Array).size() == (stats as Array).filter(func(s: String) -> bool: return stats.count(s) == 1).size(), "three different stats")
	for o: Dictionary in a:
		check(o["to"] == o["from"] + 1, "each is a single step")
	var first_offers := {}
	var aim_count := 0
	var hp_count := 0
	for sd in 40:
		var d := campaign()
		d.campaign_seed = sd
		d.apply_xp(3, 6)
		var offer := d.levelup_offer(3)
		first_offers[str(offer)] = true
		for o: Dictionary in offer:
			aim_count += int(o["stat"] == "aim")
			hp_count += int(o["stat"] == "hp")
	check(first_offers.size() > 5, "different seeds give different offers (%d distinct)" % first_offers.size())
	check(aim_count > hp_count + 10, "a sniper is offered aim far more often than hp (%d vs %d)" % [aim_count, hp_count])
	var capped := campaign()
	capped.apply_xp(3, 6)
	capped._roster[3]["stats"]["aim"] = 10
	check(not capped.levelup_offer(3).any(func(o: Dictionary) -> bool: return o["stat"] == "aim"), "a stat at its cap is never offered")
	var needle := campaign()
	needle.apply_xp(4, 6)  # cqb 9 already gives the close-range bonus
	for sd in 20:
		needle.campaign_seed = sd
		check(not needle.levelup_offer(4).any(func(o: Dictionary) -> bool: return o["stat"] == "cqb"), "cqb beyond its threshold has no effect, so it is not offered (seed %d)" % sd)


func test_offers_depend_on_the_slot_and_on_picks_made() -> void:
	var slot_differs := 0
	var picks_differs := 0
	for sd in 40:
		var a := campaign()
		a.campaign_seed = sd
		a.apply_xp(1, 36)
		a.apply_xp(2, 36)  # Warden and Gran share the rifle class
		a._roster[2]["stats"] = (a._roster[1]["stats"] as Dictionary).duplicate()  # identical weights, so only the dice can differ
		if str(a.levelup_offer(1).map(func(o: Dictionary) -> String: return o["stat"])) != str(a.levelup_offer(2).map(func(o: Dictionary) -> String: return o["stat"])):
			slot_differs += 1
		var before := str(a.levelup_offer(1).map(func(o: Dictionary) -> String: return o["stat"]))
		a._roster[1]["picks"] = 1
		if str(a.levelup_offer(1).map(func(o: Dictionary) -> String: return o["stat"])) != before:
			picks_differs += 1
	check(slot_differs > 0, "same-class mercs are not dealt identical offers (%d of 40 seeds differ)" % slot_differs)
	check(picks_differs > 0, "the next pick is dealt from fresh dice (%d of 40 seeds differ)" % picks_differs)


func test_a_living_flag_gates_xp_even_when_the_merc_is_not_listed_dead() -> void:
	var c := campaign()
	var report := c.complete_mission("karsa_breakout", true, [], [], [], false, 0, [row(1, 2, 1, 0, 5, false)])
	check((report["xp"] as Array).is_empty() and c.xp_of(1) == 0, "a unit row that is not alive earns nothing")


func test_choosing_a_step_applies_it_once_and_refuses_the_rest() -> void:
	var c := campaign()
	check(c.choose_levelup(3, "aim") != "", "no level-up pending: refused")
	c.apply_xp(3, 6)
	var offer := c.levelup_offer(3)
	var stat: String = offer[0]["stat"]
	var before := int(c.slot_stats(3)[stat])
	var not_offered := ""
	for s in Campaign.STAT_KEYS:
		if not offer.any(func(o: Dictionary) -> bool: return o["stat"] == s):
			not_offered = s
	check(c.choose_levelup(3, not_offered) != "", "a step that was not offered is refused")
	check(c.choose_levelup(3, stat) == "" and int(c.slot_stats(3)[stat]) == before + 1 and c.levelup_pending(3) == 0, "the pick adds one and spends the level-up")
	check(c.choose_levelup(3, stat) != "", "and cannot be taken twice")


func test_a_fallen_merc_becomes_a_hollow_at_sixty_percent_of_their_levelled_stats() -> void:
	var c := campaign()
	c._roster[3]["stats"]["aim"] = 10
	c.complete_mission("karsa_breakout", true, [3], [], [])
	check(c.slot_status(3) == "hollow" and int(c.slot_stats(3)["aim"]) == 6, "aim 10 freezes at 6")


func test_levelling_survives_a_save_and_the_offer_does_not_reroll() -> void:
	var c := campaign()
	c.campaign_seed = 77
	c.award_xp(3, row(3, 4, 2, 1, 30), true)
	c.apply_xp(3, 10)
	var offer_before := c.levelup_offer(3)
	var text := JSON.stringify(c.to_dict())
	var loaded := Campaign.from_dict(JSON.parse_string(text), story)
	check(loaded != null and loaded.xp_of(3) == c.xp_of(3) and loaded.level_of(3) == c.level_of(3) and loaded.levelup_pending(3) == c.levelup_pending(3), "xp, level and pending survive")
	check(loaded.campaign_seed == 77 and loaded.levelup_offer(3) == offer_before, "the seed survives, so the same offer comes back")
	check(int(loaded._roster[3]["kills"]) == 2 and int(loaded._roster[3]["steps"]) == 30, "use counters survive")
	check(Campaign.save_problem(JSON.parse_string(text)) == "", "the save is valid")


func test_effect_text_uses_the_real_rules() -> void:
	check(UiModel.stat_effect_text("aim", 6, 7).contains("+7% to hit"), "aim: +7% to hit")
	check(UiModel.stat_effect_text("aim", 7, 8).contains("1 AP less"), "aim 8 makes shots cheaper")
	check(UiModel.stat_effect_text("aim", 8, 9).contains("+1 range"), "aim 9 adds a tile of range")
	check(UiModel.stat_effect_text("cqb", 5, 6).contains("+1 damage within 2 tiles"), "cqb 6 unlocks close-range damage")
	check(UiModel.stat_effect_text("speed", 5, 6).contains("+10 initiative") and UiModel.stat_effect_text("hp", 3, 4) == "+1 hit point", "speed and hp")
	check(UiModel.stat_effect_text("morale", 5, 6) != "" and UiModel.stat_effect_text("sight", 6, 7) != "", "morale and sight have text")


func test_merc_info_carries_level_fields_for_named_mercs_only() -> void:
	var c := campaign()
	c.apply_xp(1, 8)
	var info := UiModel.merc_info(c, 1)
	check(info["level"] == 2 and info["xp"] == 8 and info["xp_next"] == 14 and info["pending"] == 1, "level, xp, next mark and picks waiting")
	c.complete_mission("karsa_breakout", true, [1], [], [])
	check(not UiModel.merc_info(c, 1).has("level"), "a hollow shows no level")
	var card := MercCard.new().setup(UiModel.merc_info(campaign(), 1))
	TestBase.tree.root.add_child(card)
	check(card.find_children("*", "ProgressBar", true, false).any(func(b: Node) -> bool: return (b as Control).visible), "the XP bar is visible on a named merc's card")
	card.queue_free()


func test_the_level_up_screen_walks_through_each_pick() -> void:
	var c := campaign()
	c.apply_xp(3, 14)  # two level-ups
	var screen := LevelUpScreen.new().setup(c, 3)
	TestBase.tree.root.add_child(screen)
	var counts := {"done": 0, "chosen": 0}
	screen.connect("done", func() -> void: counts["done"] += 1)
	screen.connect("chosen", func() -> void: counts["chosen"] += 1)
	var options := nodes_of(screen, "TapPanel").filter(func(n: Node) -> bool: return (n.name as String).begins_with("opt_"))
	check(options.size() == 3 and button(screen, "Confirm").disabled, "three options and Confirm disabled until one is chosen")
	(options[0] as TapPanel).pressed.emit()
	check(not button(screen, "Confirm").disabled, "choosing enables Confirm")
	button(screen, "Confirm").pressed.emit()
	check(counts["chosen"] == 1 and counts["done"] == 0 and c.levelup_pending(3) == 1, "one pick made; the second offer is shown, not done yet")
	var second := nodes_of(screen, "TapPanel").filter(func(n: Node) -> bool: return (n.name as String).begins_with("opt_"))
	check(second.size() == 3, "the next offer appears")
	(second[1] as TapPanel).pressed.emit()
	button(screen, "Confirm").pressed.emit()
	check(counts["chosen"] == 2 and counts["done"] == 1 and c.levelup_pending(3) == 0, "after the last pick it is done")
	screen.queue_free()
	var empty := LevelUpScreen.new().setup(c, 3)
	TestBase.tree.root.add_child(empty)
	check(button(empty, "Continue") != null, "with nothing to spend it just continues")
	empty.queue_free()


func test_the_roster_screen_lists_details_and_offers_the_level_up() -> void:
	var c := campaign()
	c.apply_xp(3, 6)
	var screen := RosterScreen.new().setup(c)
	TestBase.tree.root.add_child(screen)
	check(nodes_of(screen, "MercCard").size() == c.available_slots().size(), "a card per available merc")
	var asked := [-1]
	screen.connect("open_levelup", func(slot: int) -> void: asked[0] = slot)
	screen.open_detail(3)
	var texts: Array[String] = []
	for l in screen.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	var joined := " ".join(texts)
	check(joined.contains("Marksman") and joined.contains("Level 2") and joined.contains("Missions 0"), "the detail names the class, level and counters")
	check(button(screen, "Level up (1 waiting)") != null, "a waiting pick gets a button")
	button(screen, "Level up (1 waiting)").pressed.emit()
	check(asked[0] == 3, "which asks the host for that merc's level-up")
	screen.open_detail(1)
	check(button(screen, "Level up (1 waiting)") == null, "and a merc with none has no button")
	screen.queue_free()


func test_the_debrief_chain_orders_result_levelups_rolls_and_scenes() -> void:
	var c := campaign()
	var rows := [row(1, 6, 2, 1, 20), row(3, 6, 2, 0, 20), row(2, 0, 0, 0, 0, false)]
	var before := {"procession": c.procession, "reserves": c.reserves}
	var o := {"success": true, "dead_slots": [2], "writ_dead": [], "squad_wiped": false, "units": rows}
	var report := c.complete_mission("karsa_breakout", true, [2], [], [], false, 0, rows)
	var chain := c.debrief_chain("karsa_breakout", o, report, before, false)
	var kinds: Array = chain.map(func(s: Dictionary) -> String: return s["t"])
	check(kinds == ["result", "levelup", "levelup", "roll", "debrief", "orrick"], "result, a level-up each for slots 1 and 3, the roll call for slot 2, then the scenes: %s" % [kinds])
	check(chain[1]["slot"] == 1 and chain[2]["slot"] == 3, "level-ups go in slot order")
	var text := JSON.stringify(chain)
	check(JSON.parse_string(text) is Array, "the chain is JSON-safe, so it can be saved in the campaign")
	var wiped := campaign()
	var wiped_report := wiped.complete_mission("karsa_breakout", false, [1, 2, 3, 4, 5, 6], [], [], true)
	check(wiped.debrief_chain("karsa_breakout", o, wiped_report, before, false).size() == 1, "a campaign that has ended gets only the result")
	var card := campaign()
	card.complete_mission("karsa_breakout", true, [], [], [])
	var card_report := card.complete_mission("stranded_tug", true, [], [], [], false, 0, [row(1, 6, 2, 0, 20)])
	var card_kinds: Array = card.debrief_chain("stranded_tug", o, card_report, before, false).map(func(s: Dictionary) -> String: return s["t"])
	check(not card_kinds.has("debrief") and not card_kinds.has("orrick") and card_kinds.has("levelup"), "a contingency card has no debrief or Orrick scene but can still level")
