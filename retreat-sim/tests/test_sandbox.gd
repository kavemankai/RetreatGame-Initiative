extends TestBase
## The sandbox: an open map, editable mercs and gear, a placed enemy list.

var story: Dictionary = StoryData.load_dir("res://data/story")["data"]


func test_the_proving_ground_is_a_valid_open_map_with_every_cover_type() -> void:
	var map := MapData.load_file(Sandbox.MAP)
	check(map != null, "the map loads")
	check(map.problem(4, 8) == "", "the map validates: %s" % map.problem(4, 8))
	var s := map.build_state()
	var full := 0
	var half := 0
	for k in s.grid.edges:
		if s.grid.edges[k] == SimConst.EDGE_FULL:
			full += 1
		else:
			half += 1
	check(s.grid.blocked.size() >= 8 and full >= 4 and half >= 4, "crates, full walls and half walls are all present")


func test_default_config_builds_four_mercs_and_four_enemies() -> void:
	var cfg := Sandbox.default_config(story)
	var m := Sandbox.build(story, cfg)
	var mercs := 0
	var foes := 0
	for id in m.state.units:
		if m.state.units[id].team == 0:
			mercs += 1
		else:
			foes += 1
	check(mercs == 4 and foes == 4, "4 v 4 by default")
	check(Sandbox.problem(cfg) == "", "the default config can start")
	check(Sandbox.problem(Sandbox.without_enemies(cfg)) != "", "an empty enemy list cannot start")


func test_stat_edits_are_clamped_and_never_mutate_the_original() -> void:
	var cfg := Sandbox.default_config(story)
	var base_aim := int(cfg["mercs"][0]["stats"]["aim"])
	var up := Sandbox.with_stat(cfg, 0, "aim", 2)
	check(int(up["mercs"][0]["stats"]["aim"]) == base_aim + 2, "aim rises")
	check(int(cfg["mercs"][0]["stats"]["aim"]) == base_aim, "the original config is untouched")
	var top := Sandbox.with_stat(cfg, 0, "aim", 99)
	check(int(top["mercs"][0]["stats"]["aim"]) == 10, "stats clamp at their maximum")
	var floor_ := Sandbox.with_stat(cfg, 0, "hp", -99)
	check(int(floor_["mercs"][0]["stats"]["hp"]) == 1, "hp never drops below 1")


func test_gear_is_folded_onto_the_edited_base_stats() -> void:
	var cfg := Sandbox.with_gear(Sandbox.default_config(story), 1, "weapon", "marksman_rifle")
	cfg = Sandbox.with_gear(cfg, 1, "mod", "scope")
	cfg = Sandbox.with_gear(cfg, 1, "armour", "")
	var base: Dictionary = cfg["mercs"][1]["stats"]
	var u: SimUnit = Sandbox.build(story, cfg).state.units[int(cfg["mercs"][1]["slot"])]
	check(u.hp == int(base["hp"]), "no armour: base hp")
	check(u.weapon_range == 6 + 2 + SimConst.SCOPE_RANGE, "marksman rifle and scope extend range")
	check(u.gear_trait == "scope" and u.hit_bonus == 10, "trait and accuracy applied")
	check(u.sight_range == int(base["sight"]) + SimConst.SCOPE_SIGHT, "scope adds sight")


func test_placing_enemies_checks_tiles_and_singletons() -> void:
	var cfg := Sandbox.without_enemies(Sandbox.default_config(story))
	var map := MapData.load_file(Sandbox.MAP)
	check(Sandbox.placement_problem(story, cfg, map, Vector2i(12, 3), "conscript") == "", "an open tile accepts an enemy")
	check(Sandbox.placement_problem(story, cfg, map, Vector2i(4, 2), "conscript") != "", "a crate tile is refused")
	check(Sandbox.placement_problem(story, cfg, map, Vector2i(2, 8), "conscript") != "", "the squad's start zone is refused")
	cfg = Sandbox.with_enemy(cfg, {"kind": "provost", "hollow": false, "role": "guard", "pos": Vector2i(12, 3)})
	check(Sandbox.placement_problem(story, cfg, map, Vector2i(12, 3), "conscript") != "", "an occupied tile is refused")
	check(Sandbox.placement_problem(story, cfg, map, Vector2i(13, 3), "provost") != "", "the Provost can only be placed once")
	check(Sandbox.without_enemy_at(cfg, Vector2i(12, 3))["enemies"].is_empty(), "tapping an enemy removes it")


func test_hollow_and_repeated_kinds_get_unique_ids_and_drone_stats() -> void:
	var cfg := Sandbox.without_enemies(Sandbox.default_config(story))
	for i in 3:
		cfg = Sandbox.with_enemy(cfg, {"kind": "regular", "hollow": i == 2, "role": "patrol", "pos": Vector2i(12 + i, 3)})
	cfg = Sandbox.with_enemy(cfg, {"kind": "regular", "hollow": false, "role": "sentry", "pos": Vector2i(12, 9)})
	var m := Sandbox.build(story, cfg)
	check(m.state.units.size() == 8, "no unit id collided")
	var hollow: SimUnit = m.state.units[310]
	check(hollow.is_drone and hollow.morale == 0, "hollow regulars are drones at id 310")
	check(m.state.units[212].watch_dir == Sandbox.SENTRY_FACING, "a sentry starts on watch facing west")
	check(m.assignments[212] == "sentry" and m.assignments[210] == "aggressor", "roles map onto AI profiles")


func test_a_sandbox_match_plays_in_the_initiative_ruleset() -> void:
	var m := InitiativeMatch.from_match(Sandbox.build(story, Sandbox.default_config(story)))
	m.start()
	m.end_turn()
	check(m.turn == 2 and m.active_team == 0, "an enemy turn runs and the player moves again")
