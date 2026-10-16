extends TestBase
## The roster of eight and weapon classes: a class is a weapon type fixed per merc, each class has a
## line of weapons, and the data lint keeps the cast, classes and items consistent.

var story: Dictionary = StoryData.load_dir("res://data/story")["data"]

const ROSTER := {1: "rifle", 2: "rifle", 3: "sniper", 4: "shotgun", 5: "heavy", 6: "carbine", 7: "grenade", 8: "beam"}


func mutated(change: Callable) -> Array[String]:
	var d: Dictionary = StoryData.load_dir("res://data/story")["data"].duplicate(true)
	change.call(d)
	return StoryLint.lint(d)


func test_the_roster_is_eight_mercs_each_with_a_class() -> void:
	var mercs: Array = story["cast"]["mercs"]
	check(mercs.size() == 8, "eight mercs")
	for m: Dictionary in mercs:
		check(ROSTER[int(m["slot"])] == m["class"], "slot %d %s is a %s" % [m["slot"], m["id"], m["class"]])
	var starters := mercs.filter(func(m: Dictionary) -> bool: return m["start"])
	check(starters.size() == 6 and (mercs[6]["id"] == "wren" and mercs[6]["joins"] == "orchard_ring") and (mercs[7]["id"] == "ghost" and mercs[7]["joins"] == "cinder_market"), "six start; Wren joins at Orchard Ring and Ghost at Cinder Market")


func test_the_four_cut_mercs_are_gone_from_the_story() -> void:
	var ids: Array = story["cast"]["mercs"].map(func(m: Dictionary) -> String: return m["id"])
	for gone in ["quill", "static", "pilgrim", "tinker"]:
		check(not ids.has(gone), "%s is not in the cast" % gone)
	for s: Dictionary in story["scenes"]["scenes"]:
		for l: Dictionary in s["lines"]:
			check(not ["quill", "static", "pilgrim", "tinker"].has(l["who"]), "scene %s has no line from a cut merc" % s["id"])
		check(not (s["id"] as String).begins_with("camp_quill") and not (s["id"] as String).begins_with("camp_static") and not (s["id"] as String).begins_with("camp_pilgrim") and not (s["id"] as String).begins_with("camp_tinker"), "no camp scene about a cut merc: %s" % s["id"])
	check(StoryLint.lint(story).is_empty(), "the story still lints clean: %s" % [StoryLint.lint(story).slice(0, 3)])


func test_every_class_has_a_tier_one_base_weapon_and_a_full_line() -> void:
	var items := {}
	for it: Dictionary in story["items"]["items"]:
		items[it["id"]] = it
	for cid in story["classes"]["classes"]:
		var base: String = story["classes"]["classes"][cid]["base_item"]
		check(items[base]["class"] == cid and int(items[base]["tier"]) == 1, "%s: base weapon %s is tier 1 of the class" % [cid, base])
		var tiers := {}
		for it: Dictionary in story["items"]["items"]:
			if it["slot"] == "weapon" and it["class"] == cid:
				tiers[int(it["tier"])] = true
		check(tiers.has(1) and tiers.has(2) and tiers.has(3), "%s has weapons at tiers 1, 2 and 3 (%s)" % [cid, tiers.keys()])


func test_every_upgrade_weapon_can_actually_be_found() -> void:
	var found := {}
	for m: Dictionary in story["route"]["missions"]:
		for r in m["rewards"]:
			found[r] = true
	for officer in story["items"]["drops"]:
		found[story["items"]["drops"][officer]] = true
	for it: Dictionary in story["items"]["items"]:
		if it["slot"] != "weapon":
			continue
		var is_base: bool = story["classes"]["classes"][it["class"]]["base_item"] == it["id"]
		check(is_base or found.has(it["id"]), "%s is a base weapon or a reward or a drop" % it["id"])


func test_weapon_traits_belong_to_the_special_weapons() -> void:
	var by_id := {}
	for it: Dictionary in story["items"]["items"]:
		by_id[it["id"]] = it
	for id in ["laser_rifle", "focused_laser", "pulse_laser"]:
		check(by_id[id]["trait"] == "beam" and by_id[id]["class"] == "beam", "%s is a beam weapon" % id)
	for id in ["grenade_launcher", "frag_launcher", "heavy_launcher"]:
		check(by_id[id]["trait"] == "area" and by_id[id]["class"] == "grenade", "%s is an area weapon" % id)
	check(by_id["minigun"]["trait"] == "burst" and by_id["minigun"]["class"] == "heavy" and int(by_id["minigun"]["tier"]) == 3, "the minigun tops the heavy line with burst")
	for id in ["service_rifle", "carbine", "hunting_rifle", "scatter_gun", "support_rifle"]:
		check(not by_id[id].has("trait"), "%s carries no weapon trait" % id)


func test_a_class_is_fixed_for_a_merc_even_after_they_become_a_hollow() -> void:
	var c := Campaign.new_game(story)
	for slot in ROSTER:
		check(c.class_of(slot) == ROSTER[slot], "slot %d class" % slot)
	c.complete_mission("karsa_breakout", true, [3], [], [])
	check(c.slot_status(3) == "hollow" and c.class_of(3) == "sniper", "a hollowed sniper is still a sniper")
	check(c.class_name_of("sniper") == "Marksman" and c.class_name_of("beam") == "Laser gunner", "classes have display names")


func test_sprite_keys_cover_the_eight_slots_and_their_art_exists() -> void:
	for slot in ROSTER:
		var key := UnitSprites.key_for(slot, 0, false)
		check(ResourceLoader.exists("res://assets/mercs/%s_idle0.png" % key), "slot %d draws as %s and its art exists" % [slot, key])


func test_the_lint_enforces_classes_and_weapon_traits() -> void:
	check(not mutated(func(d: Dictionary) -> void: d["cast"]["mercs"][0]["class"] = "wizard").is_empty(), "a merc with an unknown class is caught")
	check(not mutated(func(d: Dictionary) -> void: d["items"]["items"][5]["class"] = "wizard").is_empty(), "a weapon with an unknown class is caught")
	check(not mutated(func(d: Dictionary) -> void: d["classes"]["classes"]["sniper"]["base_item"] = "marksman_rifle").is_empty(), "a base weapon above tier 1 is caught")
	check(not mutated(func(d: Dictionary) -> void: d["classes"]["classes"]["sniper"]["base_item"] = "scatter_gun").is_empty(), "a base weapon of another class is caught")
	var armour_with_trait := mutated(func(d: Dictionary) -> void: d["items"]["items"][0]["trait"] = "beam")
	check(not armour_with_trait.is_empty(), "a weapon trait on armour is caught")
	var mod_with_weapon_trait := mutated(func(d: Dictionary) -> void:
		for it: Dictionary in d["items"]["items"]:
			if it["id"] == "scope":
				it["trait"] = "beam")
	check(not mod_with_weapon_trait.is_empty(), "a weapon trait on a mod is caught")
	var weapon_with_mod_trait := mutated(func(d: Dictionary) -> void:
		for it: Dictionary in d["items"]["items"]:
			if it["id"] == "carbine":
				it["trait"] = "scope")
	check(not weapon_with_mod_trait.is_empty(), "a mod trait on a weapon is caught")
	var armour_with_class := mutated(func(d: Dictionary) -> void: d["items"]["items"][0]["class"] = "rifle")
	check(not armour_with_class.is_empty(), "a class on armour is caught")
