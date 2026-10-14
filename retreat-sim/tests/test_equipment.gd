extends TestBase
## Equipment: three slots (armour, weapon, mod), the stash, rewards, and what
## each item does to a fielded unit.


func new_campaign() -> Campaign:
	return Campaign.new_game(StoryData.load_dir("res://data/story")["data"])


func test_item_data_loads_and_lint_is_clean() -> void:
	var res := StoryData.load_dir("res://data/story")
	check((res["errors"] as Array).is_empty(), "items.json loads with the other story files")
	check(StoryLint.lint(res["data"]).is_empty(), "story lint is clean with items: %s" % [StoryLint.lint(res["data"])])


func test_every_named_merc_starts_in_a_compact_vest() -> void:
	var c := new_campaign()
	for slot in c.available_slots():
		check(c.gear_of(slot)["armour"] == "compact_vest" and c.gear_of(slot)["weapon"] == "" and c.gear_of(slot)["mod"] == "", "slot %d: vest on, weapon and mod empty" % slot)
	check(c.stash.is_empty(), "the stash starts empty")


func test_fielded_units_carry_their_gear() -> void:
	var c := new_campaign()
	var base: Dictionary = c.slot_stats(1)
	var u := c.squad_units("karsa_breakout", [1])[0]
	check(u.hp == int(base["hp"]) + 1, "the vest adds a hit point")
	c.stash.append("carbine")
	c.stash.append("scope")
	c.stash.append("mourning_cloak")
	check(c.equip(1, "carbine") == "" and c.equip(1, "scope") == "" and c.equip(1, "mourning_cloak") == "", "equip from the stash")
	var g := c.squad_units("karsa_breakout", [1])[0]
	check(g.hp == int(base["hp"]), "swapping the vest for the cloak drops the vest's hit point")
	check(g.morale == int(base["morale"]) + 2, "the cloak adds morale")
	check(g.weapon_range == 6 - 1 + 1 and g.weapon_shot_ticks == 4 - 1 and g.hit_bonus == -5, "carbine and scope: range -1 +1, shots a tick faster, accuracy -5")
	check(g.sight_range == int(base["sight"]) + 2 and g.gear_trait == "scope", "scope: +2 sight and its trait")


func test_equip_rules_slot_stash_and_swapping() -> void:
	var c := new_campaign()
	check(c.equip(1, "carbine") != "", "you cannot equip what is not in the stash")
	c.stash.append("carbine")
	c.stash.append("marksman_rifle")
	check(c.equip(1, "nonsense") != "", "unknown item")
	check(c.equip(1, "carbine") == "" and not c.stash.has("carbine"), "equipping takes it from the stash")
	check(c.equip(1, "marksman_rifle") == "" and c.stash.has("carbine") and c.gear_of(1)["weapon"] == "marksman_rifle", "a swap returns the old weapon to the stash")
	check(c.unequip(1, "weapon") == "" and c.stash.has("marksman_rifle") and c.gear_of(1)["weapon"] == "", "unequip returns it")
	check(c.unequip(1, "weapon") != "", "nothing left to take off")
	c.stash.append("carbine")
	check(c.equip(11, "carbine") != "", "an absent slot has no kit to equip")
	check(c.unequip(1, "helmet") != "", "unknown slot name")


func test_death_returns_gear_and_the_hollow_fields_bare() -> void:
	var c := new_campaign()
	c.stash.append("scope")
	c.equip(1, "scope")
	var base := c.slot_stats(1)
	var report := c.complete_mission("karsa_breakout", true, [1], [], [])
	check(report["hollowed"] == [1], "setup: slot 1 hollowed")
	check(c.stash.has("compact_vest") and c.stash.has("scope"), "both items are back in the stash")
	var gear := c.gear_of(1)
	check(gear["armour"] == "" and gear["mod"] == "", "the hollow slot holds nothing")
	var u := c.squad_units("the_weir", [1])[0]
	check(u.is_drone and u.hp == Campaign.drone_stats(base, 60)["hp"] and u.gear_trait == "", "a hollow fields bare, at 60% of base stats")


func test_a_vacant_slot_also_returns_gear() -> void:
	var c := new_campaign()
	c.reserves = 0
	c.complete_mission("karsa_breakout", true, [2], [], [])
	check(c.slot_status(2) == "vacant" and c.stash.has("compact_vest"), "no reserves: the slot is vacant and the vest is stashed")


func test_rewards_go_to_the_stash_on_success_only() -> void:
	var c := new_campaign()
	var lost := c.complete_mission("karsa_breakout", false, [], [], [])
	check(c.stash.is_empty() and (lost["loot"] as Array).is_empty(), "a failed mission earns nothing")
	var c2 := new_campaign()
	var won := c2.complete_mission("karsa_breakout", true, [], [], [])
	check(c2.stash == ["carbine"] and won["loot"] == ["carbine"], "a win adds the mission's reward and reports it")


func test_officer_kills_drop_their_signature_item() -> void:
	var c := new_campaign()
	for id in ["karsa_breakout", "the_weir", "pellam_dock", "orchard_ring"]:
		c.complete_mission(id, true, [], [], [])
	var report := c.complete_mission("quiet_wards", true, [], ["gavel"], [])
	check(c.stash.has("gavel_plate") and (report["loot"] as Array).has("gavel_plate") and c.stash.has("plate_carrier"), "the officer's plate drops with the mission reward")


func test_stash_for_lists_one_slot_in_a_stable_order() -> void:
	var c := new_campaign()
	c.stash.append_array(["scope", "carbine", "mourning_cloak", "scatter_gun"])
	check(c.stash_for("weapon") == ["carbine", "scatter_gun"], "weapons only, sorted")
	check(c.stash_for("mod") == ["scope"] and c.stash_for("armour") == ["mourning_cloak"], "the other slots")


func test_save_round_trip_keeps_gear_and_stash_and_old_saves_migrate() -> void:
	var c := new_campaign()
	c.stash.append_array(["carbine", "scope"])
	c.equip(2, "carbine")
	var loaded := Campaign.from_dict(c.to_dict(), c.story)
	check(loaded != null and loaded.stash == c.stash and loaded.gear_of(2) == c.gear_of(2), "gear and stash survive a save")
	var old := c.to_dict()
	old["version"] = 1
	old.erase("stash")
	for key in old["roster"]:
		(old["roster"][key] as Dictionary).erase("gear")
	var migrated := Campaign.from_dict(old, c.story)
	check(migrated != null and migrated.gear_of(1)["armour"] == "compact_vest" and migrated.stash.is_empty(), "a v1 save loads with the standard vest on every named merc")
	check(Campaign.save_problem(c.to_dict()) == "", "the new save is valid")


func test_stats_are_clamped_to_sane_ranges() -> void:
	var c := new_campaign()
	c.stash.append_array(["plate_carrier", "gavel_plate"])
	c.equip(8, "gavel_plate")  # speed -2
	var u := c.squad_units("karsa_breakout", [8])[0]
	check(u.speed >= 1 and u.hp >= 1, "speed and hp never drop below 1")
	check(u.speed == maxi(1, int(c.slot_stats(8)["speed"]) - 2), "the penalty applies")


# --- what the traits do in the sim -------------------------------------------

func gear_unit(kind: String, id := 1, team := 0, pos := Vector2i(2, 5)) -> SimUnit:
	var u := SimUnit.make(id, team, pos, 3, 5, 5)
	u.gear_trait = kind
	return u


func test_sprinter_makes_diagonals_cost_the_same_as_straight_steps() -> void:
	var u := gear_unit("sprinter")
	var plain := gear_unit("")
	var diag := SimAction.move(Vector2i(1, 1))
	check(diag.cost(u) == SimConst.COST_ORTHO and diag.cost(plain) == SimConst.COST_DIAG, "diagonal move cost")
	var s := make_state(10, 10)
	s.add_unit(u)
	var reach := SimPathing.reach(s, u.pos, u.id, 20)
	check(int(reach["dist"][u.pos + Vector2i(1, 1)]) == SimConst.COST_ORTHO, "the path planner knows the cheaper diagonal")
	var steps: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, 0)]
	check(SimAction.move_fire(steps).cost(u) == SimAction.move_fire(steps).cost(plain) - 1, "Move and Fire pricing uses the same step cost")


func test_bracing_helps_the_owner_in_cover_only() -> void:
	var s := make_state(20, 10)
	s.fixed_roll = -1
	var shooter := add_unit(s, 1, 0, Vector2i(2, 5))
	var target := add_unit(s, 2, 1, Vector2i(6, 5))
	shooter.gear_trait = "bracing"
	var open: int = SimResolver.evaluate_shot(s.grid, shooter, shooter.pos, target)["chance"]
	s.grid.set_blocked(Vector2i(2, 4))
	var covered: int = SimResolver.evaluate_shot(s.grid, shooter, shooter.pos, target)["chance"]
	check(covered == open + 5, "+5 to hit when the owner stands beside cover")
	shooter.gear_trait = ""
	var plain: int = SimResolver.evaluate_shot(s.grid, shooter, shooter.pos, target)["chance"]
	check(plain == open, "without the trait the same shot has the open-ground chance")


func test_bracing_doubles_the_morale_cover_bonus() -> void:
	var s := make_state(20, 10)
	add_unit(s, 1, 0, Vector2i(2, 5), 3, 7)
	var target := add_unit(s, 2, 1, Vector2i(5, 5))
	s.grid.set_blocked(Vector2i(5, 4))
	var plain: int = events_of(SimResolver.resolve(s, plan_of(1, [SimAction.shoot(2)])), "morale")[0]["need"]
	target.gear_trait = "bracing"
	var braced: int = events_of(SimResolver.resolve(s, plan_of(1, [SimAction.shoot(2)])), "morale")[0]["need"]
	check(braced == plain + 1, "bracing makes cover worth +2 on the check instead of +1")


func test_opener_boosts_only_the_first_shot_of_a_round() -> void:
	var s := make_state(20, 10)
	s.fixed_roll = -1
	var shooter := add_unit(s, 1, 0, Vector2i(2, 5), 3, 7)
	add_unit(s, 2, 1, Vector2i(6, 5), 90)
	shooter.gear_trait = "opener"
	var r := SimResolver.resolve(s, plan_of(1, [SimAction.shoot(2), SimAction.shoot(2)]))
	var chances := events_of(r, "shot").map(func(e): return e["chance"])
	check(chances.size() == 2 and chances[0] == chances[1] + 15, "the first shot gets +15, the second does not; got %s" % [chances])
	var next := SimResolver.resolve(r.state, plan_of(1, [SimAction.shoot(2)]))
	check(events_of(next, "shot")[0]["chance"] == chances[0], "it is back at the start of the next round")


func test_issue_rifle_defaults_and_traits_clone() -> void:
	var u := SimUnit.make(1, 0, Vector2i.ZERO, 3, 5, 5)
	check(u.gear_trait == "" and u.hit_bonus == 0 and u.weapon_range == 6 and u.weapon_shot_ticks == 4 and u.damage == 1, "issue rifle defaults")
	var c := u.clone()
	u.gear_trait = "scope"
	check(u.clone().gear_trait == "scope" and c.gear_trait == "", "traits clone")


func test_lint_rejects_bad_item_data() -> void:
	var d: Dictionary = StoryData.load_dir("res://data/story")["data"]
	d["items"]["items"][0]["slot"] = "helmet"
	check(StoryLint.lint(d).any(func(e: String) -> bool: return e.contains("slot")), "unknown slot")
	d = StoryData.load_dir("res://data/story")["data"]
	for it: Dictionary in d["items"]["items"]:
		if it["slot"] == "mod":
			it["trait"] = "levitate"
			break
	check(StoryLint.lint(d).any(func(e: String) -> bool: return e.contains("levitate")), "unknown trait")
	d = StoryData.load_dir("res://data/story")["data"]
	d["route"]["missions"][0]["rewards"] = ["no_such_item"]
	check(StoryLint.lint(d).any(func(e: String) -> bool: return e.contains("no_such_item")), "dangling reward id")
	d = StoryData.load_dir("res://data/story")["data"]
	d["route"]["missions"][0]["rewards"] = ["heavy_rifle"]  # a tier 3 item in act 1
	check(StoryLint.lint(d).any(func(e: String) -> bool: return e.contains("heavy_rifle") and e.contains("act")), "an item cannot be found before its tier")
	d = StoryData.load_dir("res://data/story")["data"]
	d["items"]["drops"]["gavel"] = "ghost_item"
	check(StoryLint.lint(d).any(func(e: String) -> bool: return e.contains("ghost_item")), "dangling drop id")
	d = StoryData.load_dir("res://data/story")["data"]
	d["items"]["starting"]["armour"] = "carbine"
	check(StoryLint.lint(d).any(func(e: String) -> bool: return e.contains("starting")), "starting kit must match its slot")


func test_item_summary_describes_stats_and_traits() -> void:
	var c := new_campaign()
	check(c.item_summary("compact_vest") == "+1 hp", "vest: %s" % c.item_summary("compact_vest"))
	var carbine := c.item_summary("carbine")
	check(carbine.contains("-1 range") and carbine.contains("-1 AP per shot") and carbine.contains("-5% to hit"), "carbine: %s" % carbine)
	check(c.item_summary("scope").contains("+2 sight"), "a mod shows its trait text")
	check(c.item_summary("nope") == "", "unknown items have no summary")
