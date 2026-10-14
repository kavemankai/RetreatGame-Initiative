extends TestBase
## Per-mission terrain: every mission has a playable, themed map.


func story() -> Dictionary:
	return StoryData.load_dir("res://data/story")["data"]


func test_every_mission_has_a_playable_map() -> void:
	var s := story()
	var themes_used := {}
	for m: Dictionary in s["route"]["missions"]:
		var map := MapData.load_file(m["id"])
		check(map != null, "%s has a map file" % m["id"])
		if map == null:
			continue
		check(map.problem() == "", "%s is playable: %s" % [m["id"], map.problem()])
		check(map.width == int(m["map"]["size"][0]) and map.height == int(m["map"]["size"][1]), "%s matches the size in route.json" % m["id"])
		themes_used[map.theme] = true
	check(themes_used.size() == 12, "the twelve missions use twelve different themes; got %d" % themes_used.size())


func test_map_themes_follow_the_route_archetypes() -> void:
	for m: Dictionary in story()["route"]["missions"]:
		check(MapData.load_file(m["id"]).theme == m["map"]["archetype"], "%s: theme equals its archetype" % m["id"])


func test_validation_catches_bad_maps() -> void:
	var d := {"mission": "x", "theme": "station_deck", "size": [12, 10], "blocked": [], "v_walls": [], "h_walls": [],
		"player_spawns": [[1, 4], [1, 5], [2, 4], [2, 5]], "enemy_spawns": [[10, 4], [10, 5], [9, 4], [9, 5], [10, 3], [10, 6], [9, 3], [9, 6]], "objective": [1, 5]}
	check(MapData.from_dict(d).problem() == "", "the plain map is fine")
	var walled := d.duplicate(true)
	walled["v_walls"] = [[6, 0, 9, "full"]]
	check(MapData.from_dict(walled).problem().contains("reached"), "a wall that splits the map is caught")
	var blocked_spawn := d.duplicate(true)
	blocked_spawn["blocked"] = [[1, 4]]
	check(MapData.from_dict(blocked_spawn).problem().contains("blocked"), "a blocked spawn is caught")
	var themed := d.duplicate(true)
	themed["theme"] = "moon_base"
	check(MapData.from_dict(themed).problem().contains("theme"), "an unknown theme is caught")
	var dup := d.duplicate(true)
	dup["enemy_spawns"][0] = [1, 4]
	check(MapData.from_dict(dup).problem().contains("twice"), "a reused spawn tile is caught")
	var jam := d.duplicate(true)
	jam["blocked"] = MapData.from_dict(d).blocked.map(func(t): return [t.x, t.y])
	for x in 12:
		for y in [0, 1, 2, 7, 8, 9]:
			jam["blocked"].append([x, y])
	check(MapData.from_dict(jam).problem().contains("35%"), "a map that is mostly blocked is caught")


func test_walls_are_built_between_the_right_tiles() -> void:
	var d := {"mission": "x", "theme": "station_deck", "size": [12, 10], "blocked": [[3, 3]],
		"v_walls": [[6, 2, 3, "full"]], "h_walls": [[5, 1, 2, "half"]],
		"player_spawns": [], "enemy_spawns": [], "objective": [1, 5]}
	var g := MapData.from_dict(d).build_state().grid
	check(g.edge_between(Vector2i(5, 2), Vector2i(6, 2)) == SimConst.EDGE_FULL and g.edge_between(Vector2i(5, 3), Vector2i(6, 3)) == SimConst.EDGE_FULL, "a vertical wall at boundary 6 sits between columns 5 and 6")
	check(g.edge_between(Vector2i(1, 4), Vector2i(1, 5)) == SimConst.EDGE_HALF and g.edge_between(Vector2i(2, 4), Vector2i(2, 5)) == SimConst.EDGE_HALF, "a horizontal wall at boundary 5 sits between rows 4 and 5")
	check(g.is_blocked(Vector2i(3, 3)), "blocked tiles are blocked")
	check(g.edge_between(Vector2i(8, 8), Vector2i(9, 8)) == SimConst.EDGE_NONE, "elsewhere is open")


func test_missions_are_built_on_their_own_map() -> void:
	var c := Campaign.new_game(story())
	var m := MissionBuilder.build(c, "long_corridor", [1, 2, 3, 4])
	var map := MapData.load_file("long_corridor")
	check(m.state.grid.is_blocked(Vector2i(4, 4)) and m.state.grid.edge_between(Vector2i(0, 2), Vector2i(0, 3)) == SimConst.EDGE_FULL, "the corridor's walls and cover are in the match")
	for slot in [1, 2, 3, 4]:
		check(map.player_spawns.has(m.state.units[slot].pos), "slot %d starts on a player spawn" % slot)
	for id in m.state.units:
		var u: SimUnit = m.state.units[id]
		if u.team == 1:
			check(map.enemy_spawns.has(u.pos), "enemy %d starts on an enemy spawn" % id)
	var karsa := MissionBuilder.build(c, "karsa_breakout", [1, 2, 3])
	check(str(karsa.state.grid.edges) != str(m.state.grid.edges), "different missions get different terrain")
	check(MissionBuilder.theme_for(c, "long_corridor") == "hull_corridor", "the builder reports the mission's theme for the view")


func test_cards_borrow_a_map_by_act() -> void:
	var c := Campaign.new_game(story())
	check(MapData.load_for(c.story, "stranded_tug").mission == "the_weir", "an act 1 card plays on the Weir")
	check(MapData.load_for(c.story, "picket_line").mission == "cinder_market", "an act 2 card plays on Cinder Market")
	check(MapData.load_for(c.story, "dead_air").mission == "reliquary_lane", "an act 3 card plays on Reliquary Lane")
	check(MapData.load_for(c.story, "no_such_mission").mission == "karsa_breakout", "an unknown id falls back to Karsa")


func test_every_theme_has_its_full_art_and_the_board_uses_it() -> void:
	for theme in MapData.THEMES:
		var missing: Array[String] = []
		for file in ThemeArt.required_files():
			if not ResourceLoader.exists("res://assets/themes/%s/%s" % [theme, file]):
				missing.append(file)
		check(missing.is_empty(), "theme %s has all its art (missing %s)" % [theme, missing])
		check(ThemeArt.floors(theme).size() == ThemeArt.FLOOR_COUNT and ThemeArt.props(theme).size() == ThemeArt.PROP_COUNT, "%s loads nine floors and four props" % theme)
		check(ThemeArt.wall(theme, 0, SimConst.EDGE_FULL) != null and ThemeArt.wall(theme, 1, SimConst.EDGE_HALF) != null, "%s loads its walls" % theme)
	check(ThemeArt.floors("no_such_theme").size() == ThemeArt.FLOOR_COUNT, "an unknown theme falls back to the deck's art")
	check(ThemeArt.floors("wreck_field")[0] != ThemeArt.floors("station_deck")[0], "themes really differ")


func test_the_match_carries_its_theme_to_the_board() -> void:
	var c := Campaign.new_game(story())
	var m := MissionBuilder.build(c, "quiet_wards", [1, 2, 3, 4])
	check(m.theme == "hospital_hulk", "the match records the mission's theme")
	var board := BoardView.new()
	board.set_level_theme(m.theme)
	check(board.level_theme == "hospital_hulk", "the board switches theme")
	board.free()
	check(SimMatch.skirmish().theme == "station_deck", "a skirmish plays on the deck")


func test_every_wall_and_prop_is_at_the_canonical_scale() -> void:
	# The generator draws each piece at its own pixel scale; art/normalize_assets.py evens them
	# out so nothing looks tiny or huge. Sizes are in file pixels at a 128 px wide tile.
	for theme in MapData.THEMES:
		for file in ThemeArt.required_files():
			var prop := file.begins_with("crate_")
			if not (prop or file.begins_with("wall_")):
				continue
			var tex := load("res://assets/themes/%s/%s" % [theme, file]) as Texture2D
			var w := tex.get_width()
			var h := tex.get_height()
			var half := file.ends_with("_half.png")
			var max_h := 170 if prop else (96 if half else 160)
			var min_h := 60 if prop else (55 if half else 110)
			check(h <= max_h and h >= min_h, "%s/%s is %d px tall (want %d to %d; a merc is about 122 at this scale)" % [theme, file, h, min_h, max_h])
			if prop:
				check(w >= 85 and w <= 124, "%s/%s is %d px wide (a prop is about one tile, 120)" % [theme, file, w])
			else:
				check(w >= 55 and w <= 100, "%s/%s is %d px wide (a wall piece is about 96 at most)" % [theme, file, w])


func test_every_floor_tile_is_a_64_by_32_diamond() -> void:
	for theme in MapData.THEMES:
		for i in ThemeArt.FLOOR_COUNT:
			var tex := load("res://assets/themes/%s/floor_%d.png" % [theme, i]) as Texture2D
			check(tex.get_width() == 64 and tex.get_height() == 32, "%s/floor_%d is %dx%d (want 64x32)" % [theme, i, tex.get_width(), tex.get_height()])


func test_every_character_stands_at_the_same_height() -> void:
	# The slicer scales each set so the standing figure is 48 px of its 64 px frame.
	for key in UnitSprites.all_keys():
		var img := (load("res://assets/mercs/%s_idle0.png" % key) as Texture2D).get_image()
		var top := img.get_height()
		var bottom := 0
		for y in img.get_height():
			for x in img.get_width():
				if img.get_pixel(x, y).a > 0.16:
					top = mini(top, y)
					bottom = maxi(bottom, y + 1)
		var h := bottom - top
		check(h >= 38 and h <= 54, "%s stands %d px tall (target 48)" % [key, h])
