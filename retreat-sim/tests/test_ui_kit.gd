extends TestBase
## The shared UI kit (view/ui): gear-included stats and equip deltas, the card data builders, tap-safe
## widgets, tap target sizes, narrow-screen fit and the gallery screen.

var story: Dictionary = StoryData.load_dir("res://data/story")["data"]


func campaign_with_gear() -> Campaign:
	var c := Campaign.new_game(story)
	c.stash.append_array(["scope", "marksman_rifle", "plate_carrier", "sprint_boots", "carbine"])
	c.equip(3, "scope")  # Sable, the Marksman
	c.equip(3, "marksman_rifle")
	c.equip(3, "plate_carrier")
	return c


func nodes_of(root: Node, type_name: String) -> Array[Node]:
	var out: Array[Node] = []
	for child in root.get_children():
		if child.get_script() != null and (child.get_script() as Script).get_global_name() == type_name:
			out.append(child)
		out.append_array(nodes_of(child, type_name))
	return out


func click(card: Control, down := Vector2(10, 10), up := Vector2(10, 10)) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = down
	card._gui_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = up
	card._gui_input(release)


func test_effective_stats_match_the_unit_a_mission_fields() -> void:
	var c := campaign_with_gear()
	for slot in [1, 2, 3]:
		var eff := c.effective_stats(slot)
		var u: SimUnit = c.squad_units("karsa_breakout", [slot])[0]
		check(eff["hp"] == u.hp and eff["speed"] == u.speed and eff["aim"] == u.aim and eff["cqb"] == u.cqb and eff["morale"] == u.morale, "slot %d: core stats match the fielded unit" % slot)
		check(eff["sight"] == u.sight_range and eff["range"] == u.max_range() and eff["damage"] == u.damage and eff["shot_cost"] == u.shot_ticks() and eff["to_hit"] == u.hit_bonus and eff["trait"] == u.gear_trait, "slot %d: sight, range, damage, shot cost, to-hit and trait match" % slot)
	check(c.effective_stats(3)["to_hit"] == 10 and c.effective_stats(3)["trait"] == "scope", "the loaded merc really carries the rifle's accuracy and the scope trait")


func test_a_hollow_shows_bare_stats() -> void:
	var c := Campaign.new_game(story)
	c.complete_mission("karsa_breakout", true, [3], [], [])
	check(c.slot_status(3) == "hollow", "setup: slot 3 is now a hollow")
	var eff := c.effective_stats(3)
	var u: SimUnit = c.squad_units("the_weir", [3])[0]
	check(eff["hp"] == u.hp and eff["aim"] == u.aim and eff["trait"] == "", "a hollow's card matches its fielded stats and carries no gear")


func test_equip_deltas_show_what_changes_and_which_way_is_better() -> void:
	var c := Campaign.new_game(story)
	c.stash.append_array(["plate_carrier", "marksman_rifle", "carbine", "scope"])
	var armour := c.equip_deltas(2, "armour", "plate_carrier")
	var by := {}
	for d: Dictionary in armour:
		by[d["stat"]] = d
	check(by.has("morale") and by["morale"]["delta"] == 1 and by["morale"]["better"], "plate carrier: +1 morale, better")
	check(by.has("speed") and by["speed"]["delta"] == -1 and not by["speed"]["better"], "plate carrier: -1 speed, worse")
	check(not by.has("hp"), "the vest already gives +1 hp, so hp is not listed")
	var rifle := c.equip_deltas(2, "weapon", "marksman_rifle")
	by.clear()
	for d: Dictionary in rifle:
		by[d["stat"]] = d
	check(by["range"]["delta"] == 2 and by["to_hit"]["delta"] == 10 and by["shot_cost"]["delta"] == 1 and not by["shot_cost"]["better"], "marksman rifle: +2 range, +10 to hit, one more AP per shot (worse)")
	var carbine := c.equip_deltas(2, "weapon", "carbine")
	by.clear()
	for d: Dictionary in carbine:
		by[d["stat"]] = d
	check(by["shot_cost"]["delta"] == -1 and by["shot_cost"]["better"], "carbine: a cheaper shot counts as better")
	var scope := c.equip_deltas(2, "mod", "scope")
	check(scope.any(func(d: Dictionary) -> bool: return d["stat"] == "trait" and d["to"] == "scope"), "a mod with a trait lists the trait")
	check(c.gear_of(2)["weapon"] == "service_rifle" and c.stash.size() == 4, "asking never changes the campaign")


func test_card_data_builders() -> void:
	var c := campaign_with_gear()
	var m := UiModel.merc_info(c, 1, true)
	check(m["slot"] == 1 and m["status"] == "named" and m["selected"] and m["name"] != "", "merc info: slot, status, selection and a callsign")
	check(m["stats"]["aim"] == c.effective_stats(1)["aim"] and m["base"]["hp"] == c.slot_stats(1)["hp"], "stats are gear-included, base stats are kept for comparison")
	check(String(m["gear_names"]["weapon"]) == "Marksman rifle" or String(m["gear_names"]["weapon"]) != "", "worn items are named")
	check(m["sprite_key"] == UnitSprites.key_for(1, 0, false), "the sprite key matches the sprite loader")
	var item := UiModel.item_info(c, "carbine", 1, 2, "weapon")
	check(item["name"] != "" and item["slot"] == "weapon" and item["summary"] == c.item_summary("carbine") and not (item["deltas"] as Array).is_empty(), "item info: name, slot, summary and deltas for a merc")
	var plain := UiModel.item_info(c, "carbine", 3)
	check(plain["count"] == 3 and (plain["deltas"] as Array).is_empty(), "without a merc there are no deltas, and the stash count is kept")
	var r := UiModel.resources_info(c)
	check(r["procession"] == c.procession and r["reserves"] == c.reserves and r["remembrance"] == c.remembrance, "resources match the campaign")
	var h := Campaign.new_game(story)
	h.complete_mission("karsa_breakout", true, [3], [], [])
	check(UiModel.merc_info(h, 3)["status"] == "hollow" and String(UiModel.merc_info(h, 3)["name"]).begins_with("HX-"), "a hollow card is named by its designation")


func test_cards_are_tappable_but_a_drag_is_not_a_tap() -> void:
	var c := campaign_with_gear()
	var merc := MercCard.new().setup(UiModel.merc_info(c, 1))
	var item := ItemCard.new().setup(UiModel.item_info(c, "carbine", 1))
	for card: Control in [merc, item]:
		var taps := [0]
		card.connect("pressed", func() -> void: taps[0] += 1)
		click(card)
		check(taps[0] == 1, "%s: a press and release on the spot is one tap" % card.get_script().get_global_name())
		click(card, Vector2(10, 10), Vector2(10, 90))
		check(taps[0] == 1, "%s: a press and release 80 px apart (a scroll drag) is not a tap" % card.get_script().get_global_name())
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = Vector2(10, 10)
		card._gui_input(press)
		var move := InputEventMouseMotion.new()
		move.position = Vector2(10, 60)
		card._gui_input(move)
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		release.position = Vector2(10, 12)
		card._gui_input(release)
		check(taps[0] == 1, "%s: dragging away and back is still not a tap" % card.get_script().get_global_name())
		check(card.mouse_filter == Control.MOUSE_FILTER_PASS, "events pass through so a ScrollContainer can scroll")
		card.free()


func test_widgets_show_the_data_and_keep_tap_targets_large() -> void:
	var c := campaign_with_gear()
	var merc := MercCard.new().setup(UiModel.merc_info(c, 3))
	TestBase.tree.root.add_child(merc)
	check(merc.custom_minimum_size.y >= UiTheme.MIN_TAP, "a merc card is at least %d px tall" % UiTheme.MIN_TAP)
	var texts: Array[String] = []
	for label in merc.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	var joined := " ".join(texts)
	for stat in ["HP", "SPD", "AIM", "CQB", "MOR", "SIGHT"]:
		check(joined.contains(stat), "the card shows %s" % stat)
	check(joined.contains(String(UiModel.merc_info(c, 3)["name"])), "and the callsign")
	var name_label: Label = null
	for label in merc.find_children("*", "Label", true, false):
		if (label as Label).text == String(UiModel.merc_info(c, 3)["name"]):
			name_label = label as Label
	check(name_label != null and name_label.clip_text == false and name_label.size_flags_horizontal & Control.SIZE_EXPAND != 0, "the callsign label is allowed to take width (it was once clipped to nothing)")
	check(nodes_of(merc, "SlotGlyph").size() == 3, "and one glyph per gear slot")
	var info := UiModel.merc_info(c, 3)
	var colors := {}
	for label in merc.find_children("*", "Label", true, false):
		colors[(label as Label).text] = (label as Label).get_theme_color("font_color")
	var speed_text := "SPD %d" % int(info["stats"]["speed"])
	var morale_text := "MOR %d" % int(info["stats"]["morale"])
	check(int(info["stats"]["speed"]) < int(info["base"]["speed"]) and colors[speed_text] == UiTheme.COL_BAD, "a stat gear lowers (speed, from the plate carrier) is red")
	check(int(info["stats"]["morale"]) > int(info["base"]["morale"]) and colors[morale_text] == UiTheme.COL_GOOD, "a stat gear raises (morale) is green")
	check(colors["AIM %d" % int(info["stats"]["aim"])] == UiTheme.COL_TEXT, "an unchanged stat keeps the normal colour")
	var item := ItemCard.new().setup(UiModel.item_info(c, "marksman_rifle", 2, 2, "weapon"))
	TestBase.tree.root.add_child(item)
	check(item.custom_minimum_size.y >= UiTheme.MIN_TAP, "an item card is at least %d px tall" % UiTheme.MIN_TAP)
	var item_texts: Array[String] = []
	for label in item.find_children("*", "Label", true, false):
		item_texts.append((label as Label).text)
	var item_joined := " ".join(item_texts)
	check(item_joined.contains("Marksman rifle") and item_joined.contains("x2") and item_joined.contains("+2"), "the item card shows the name, the stash count and the deltas: %s" % item_joined)
	var bar := ResourceBar.new().setup(UiModel.resources_info(c))
	TestBase.tree.root.add_child(bar)
	var bar_texts: Array[String] = []
	for label in bar.find_children("*", "Label", true, false):
		bar_texts.append((label as Label).text)
	check(" ".join(bar_texts).contains("6200") or " ".join(bar_texts).contains("6,200"), "the resource bar shows the Procession")
	merc.queue_free()
	item.queue_free()
	bar.queue_free()


func test_stat_row_and_pips() -> void:
	var row := StatRow.new().setup("AIM", 6, 10, 1)
	var pips: StatPips = nodes_of(row, "StatPips")[0] as StatPips
	check(pips.value == 6 and pips.maximum == 10, "pips hold the value and the cap")
	var texts: Array[String] = []
	for label in row.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	check(" ".join(texts).contains("AIM") and " ".join(texts).contains("6") and " ".join(texts).contains("+1"), "a stat row shows label, value and delta")
	check(UiTheme.delta_text(2) == "+2" and UiTheme.delta_text(-1) == "-1" and UiTheme.delta_text(0) == "0", "delta text carries its sign")
	row.free()


func test_the_scroll_list_scrolls_vertically_only() -> void:
	var list := ScrollList.new()
	for i in 20:
		list.add_card(Label.new())
	check(list.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "no sideways scrolling")
	check(list.card_count() == 20, "it holds its cards")
	list.clear_cards()
	check(list.card_count() == 0, "and clears them")
	list.free()


func test_the_kit_fits_a_narrow_phone() -> void:
	var c := campaign_with_gear()
	var widgets: Array[Control] = [MercCard.new().setup(UiModel.merc_info(c, 1)), ItemCard.new().setup(UiModel.item_info(c, "marksman_rifle", 2, 1, "weapon")), ResourceBar.new().setup(UiModel.resources_info(c))]
	for w in widgets:
		TestBase.tree.root.add_child(w)
		var narrowest := w.get_combined_minimum_size().x
		check(narrowest <= 332.0, "%s needs at most 332 px (a 360 px phone less margins), needs %.0f" % [w.get_script().get_global_name(), narrowest])
		w.queue_free()


func test_the_gallery_screen_builds_with_every_widget() -> void:
	var c := campaign_with_gear()
	var gallery := KitGallery.new().setup(c)
	TestBase.tree.root.add_child(gallery)
	check(nodes_of(gallery, "MercCard").size() == c.available_slots().size(), "a card per available merc")
	check(nodes_of(gallery, "ItemCard").size() >= 3, "sample item cards")
	check(nodes_of(gallery, "ResourceBar").size() == 1 and nodes_of(gallery, "StatRow").size() >= 6, "the resource bar and stat rows")
	var backs := [0]
	gallery.connect("back", func() -> void: backs[0] += 1)
	gallery.back.emit()
	check(backs[0] == 1, "it can ask its host to go back")
	gallery.queue_free()


func test_a_tall_phone_gives_the_extra_height_to_the_board() -> void:
	var w := 512.0
	check(InitiativeView.portrait_board_height(960.0, w) == maxf(960.0 - InitiativeView.PORTRAIT_PANEL_RESERVE, w * InitiativeView.PORTRAIT_BOARD_ASPECT), "a 540x960 screen keeps the board near its old size")
	check(InitiativeView.portrait_board_height(1200.0, w) > InitiativeView.portrait_board_height(960.0, w), "a taller screen makes the board taller")
	check(InitiativeView.portrait_board_height(3000.0, w) == w * InitiativeView.PORTRAIT_BOARD_MAX_ASPECT, "but never beyond the maximum")
	check(InitiativeView.portrait_board_height(500.0, w) == w * InitiativeView.PORTRAIT_BOARD_ASPECT, "and never below the minimum")
