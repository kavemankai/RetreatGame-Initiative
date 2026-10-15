extends TestBase
## The overworld: the map data and its lint, the pure route state, hit-testing taps, the sheet text (no
## spoilers beyond the next stop), and the screen driven by taps and presses.

var story: Dictionary = StoryData.load_dir("res://data/story")["data"]
const CANVAS := Vector2(540, 2100)


func fresh() -> Campaign:
	return Campaign.new_game(story)


func states(c: Campaign) -> Dictionary:
	var out := {}
	for n: Dictionary in c.route_state()["nodes"]:
		out[n["id"]] = n["state"]
	return out


func button(root: Node, text: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b as Button
	return null


func all_text(root: Node) -> String:
	var parts: Array[String] = []
	for l in root.find_children("*", "Label", true, false):
		parts.append((l as Label).text)
	return " ".join(parts)


func new_screen(c: Campaign) -> OverworldScreen:
	var screen := OverworldScreen.new().setup(c)
	TestBase.tree.root.add_child(screen)
	return screen


func test_the_map_lints_and_its_faults_are_caught() -> void:
	check(StoryLint.lint(story).is_empty(), "the story lints clean with the map: %s" % [StoryLint.lint(story).slice(0, 3)])
	var missing: Dictionary = StoryData.load_dir("res://data/story")["data"].duplicate(true)
	missing["map"]["nodes"].erase("anselm")
	check(StoryLint.lint(missing).any(func(e: String) -> bool: return e.contains("anselm")), "a mission with no node is caught")
	var stacked: Dictionary = StoryData.load_dir("res://data/story")["data"].duplicate(true)
	stacked["map"]["nodes"]["the_weir"] = stacked["map"]["nodes"]["karsa_breakout"]
	check(not StoryLint.lint(stacked).is_empty(), "two stops on one spot are caught")
	var outside: Dictionary = StoryData.load_dir("res://data/story")["data"].duplicate(true)
	outside["map"]["nodes"]["anselm"] = [1.5, 0.5]
	check(not StoryLint.lint(outside).is_empty(), "a node off the map is caught")
	var no_anchor: Dictionary = StoryData.load_dir("res://data/story")["data"].duplicate(true)
	no_anchor["map"]["card_anchors"].erase("2")
	check(not StoryLint.lint(no_anchor).is_empty(), "an act with no card anchor is caught")


func test_the_route_climbs_from_karsa_at_the_bottom_to_vesper_at_the_top() -> void:
	var nodes: Dictionary = story["map"]["nodes"]
	check(float(nodes["karsa_breakout"][1]) > float(nodes["vesper_threshold"][1]), "the first stop is below the last")
	var order: Array = (story["route"]["missions"] as Array).map(func(m: Dictionary) -> String: return m["id"])
	var rising := true
	for i in range(1, order.size()):
		rising = rising and float(nodes[order[i]][1]) < float(nodes[order[i - 1]][1])
	check(rising, "each stop sits above the one before it")


func test_route_state_follows_the_campaign() -> void:
	var c := fresh()
	var s := states(c)
	check(s["karsa_breakout"] == "current" and s["the_weir"] == "next" and s["pellam_dock"] == "far", "at the start: one current, one next, the rest far (%s)" % [s])
	c.complete_mission("karsa_breakout", true, [], [], [])
	s = states(c)
	check(s["karsa_breakout"] == "done" and s["the_weir"] == "current" and s["pellam_dock"] == "next" and s["orchard_ring"] == "far", "after one mission the convoy has moved on")
	check(c.route_state()["nodes"].size() == 12 and c.route_state()["cards"].is_empty(), "twelve stops and no cards yet")
	var drawn := c.draw_contingency(1, 3)
	var cards: Array = c.route_state()["cards"]
	check(cards.size() == 1 and cards[0]["id"] == drawn and cards[0]["state"] == "offered", "a drawn card is offered")
	c.complete_mission(drawn, true, [], [], [])
	check(c.route_state()["cards"][0]["state"] == "done", "a played card is done")


func test_route_state_through_a_whole_campaign_ends_with_everything_done() -> void:
	var c := fresh()
	for m: Dictionary in story["route"]["missions"]:
		c.complete_mission(m["id"], true, [], [], [])
	var done := 0
	for n: Dictionary in c.route_state()["nodes"]:
		done += int(n["state"] == "done")
	check(done == 12 and not states(c).values().has("current"), "all twelve done and no current stop")


func test_taps_land_on_the_nearest_node_and_on_cards() -> void:
	var c := fresh()
	var map: Dictionary = story["map"]
	var route := c.route_state()
	var at := MapLayout.node_point(map, "pellam_dock", CANVAS)
	check(MapLayout.hit_test(map, route, at, CANVAS) == {"kind": "node", "id": "pellam_dock"}, "a tap on a node hits it")
	check(MapLayout.hit_test(map, route, at + Vector2(MapLayout.HIT_RADIUS - 2.0, 0), CANVAS)["id"] == "pellam_dock", "just inside the radius still hits")
	check(MapLayout.hit_test(map, route, at + Vector2(MapLayout.HIT_RADIUS + 20.0, 0), CANVAS).is_empty(), "outside it hits nothing")
	check(MapLayout.node_point(map, "no_such_stop", CANVAS) == Vector2(-1, -1), "an unknown stop has no place")
	c.draw_contingency(1, 3)
	var card_at := MapLayout.card_point(map, 1, 0, CANVAS)
	var hit := MapLayout.hit_test(map, c.route_state(), card_at, CANVAS)
	check(hit["kind"] == "card", "a tap on a card diamond hits the card")


func test_the_sheet_names_the_current_stop_but_not_what_lies_beyond_the_next() -> void:
	var c := fresh()
	var now := UiModel.map_sheet(c, {"kind": "node", "id": "karsa_breakout"})
	check(now["title"] == "Karsa Breakout" and now["action"] == "brief", "the current stop can be briefed")
	var next := UiModel.map_sheet(c, {"kind": "node", "id": "the_weir"})
	check(next["action"] == "" and next["title"] != "Unknown ground", "the next stop is described but not briefed yet (%s)" % [next["title"]])
	var far := UiModel.map_sheet(c, {"kind": "node", "id": "vesper_threshold"})
	check(far["title"] == "Unknown ground" and " ".join(far["lines"]).find("Vesper") == -1, "a far stop is unknown ground and names nothing")
	c.complete_mission("karsa_breakout", true, [], [], [])
	check(UiModel.map_sheet(c, {"kind": "node", "id": "karsa_breakout"})["action"] == "", "a finished stop cannot be briefed again")


func test_the_screen_opens_on_the_current_stop_and_taps_change_the_sheet() -> void:
	var c := fresh()
	var screen := new_screen(c)
	check(button(screen, "Brief") != null, "the sheet opens on the current stop with a Brief button")
	check(all_text(screen).contains("Karsa Breakout"), "and names it")
	screen.select({"kind": "node", "id": "pellam_dock"})
	check(button(screen, "Brief") == null, "a far stop has no Brief button")
	screen.select({"kind": "node", "id": "the_weir"})
	check(all_text(screen).contains(String(c.mission_or_card("the_weir")["name"])), "tapping another stop shows it")
	screen.queue_free()


func test_brief_and_the_nav_buttons_ask_the_host() -> void:
	var c := fresh()
	var screen := new_screen(c)
	var got: Array[String] = []
	screen.brief.connect(func() -> void: got.append("brief"))
	screen.open_roster.connect(func() -> void: got.append("roster"))
	screen.open_loadout.connect(func() -> void: got.append("loadout"))
	screen.open_menu.connect(func() -> void: got.append("menu"))
	for text in ["Brief", "Roster", "Loadout", "Menu"]:
		var b := button(screen, text)
		check(b != null and b.custom_minimum_size.y >= UiTheme.MIN_TAP, "%s is there and big enough to tap" % text)
		if b != null:
			b.pressed.emit()
	check(got == ["brief", "roster", "loadout", "menu"], "each asks the host (%s)" % [got])
	screen.queue_free()


func test_the_canvas_takes_a_clean_tap_but_not_a_drag() -> void:
	var c := fresh()
	var screen := new_screen(c)
	var canvas := screen.canvas()
	canvas.size = CANVAS
	var seen: Array[Dictionary] = []
	canvas.tapped.connect(func(hit: Dictionary) -> void: seen.append(hit))
	var at := MapLayout.node_point(story["map"], "the_weir", CANVAS)
	for pos in [at, at + Vector2(20, 0)]:
		var down := InputEventMouseButton.new()
		down.button_index = MOUSE_BUTTON_LEFT
		down.position = at
		down.pressed = true
		canvas._gui_input(down)
		var up := InputEventMouseButton.new()
		up.button_index = MOUSE_BUTTON_LEFT
		up.position = pos
		up.pressed = false
		canvas._gui_input(up)
	check(seen.size() == 1 and seen[0]["id"] == "the_weir", "one tap registered; the release 20 px away was a drag (%s)" % [seen])
	screen.queue_free()


func test_the_canvas_draws_every_state_without_errors() -> void:
	var c := fresh()
	c.complete_mission("karsa_breakout", true, [], [], [])
	c.draw_contingency(1, 3)
	var screen := new_screen(c)
	screen.canvas().size = CANVAS
	screen.canvas().queue_redraw()
	check(screen.canvas().current_y() > 0.0, "the current stop has a place to scroll to")
	screen.queue_free()
