extends TestBase
## The loadout screens: roster hub, a merc's gear, the item picker with class-locked weapons and
## before/after changes, and the stash view. Driven the way a thumb drives them: tap a card, tap an item,
## press Equip.

var story: Dictionary = StoryData.load_dir("res://data/story")["data"]


func new_screen(c: Campaign) -> LoadoutScreen:
	var screen := LoadoutScreen.new().setup(c)
	TestBase.tree.root.add_child(screen)
	return screen


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


func all_text(root: Node) -> String:
	var parts: Array[String] = []
	for l in root.find_children("*", "Label", true, false):
		parts.append((l as Label).text)
	return " ".join(parts)


func card_for(screen: Node, item_name: String) -> ItemCard:
	for n in nodes_of(screen, "ItemCard"):
		for l in n.find_children("*", "Label", true, false):
			if (l as Label).text == item_name:
				return n as ItemCard
	return null


func test_the_hub_lists_the_roster_and_opens_a_merc() -> void:
	var c := Campaign.new_game(story)
	var screen := new_screen(c)
	check(nodes_of(screen, "MercCard").size() == c.available_slots().size(), "a card per available merc")
	check(button(screen, "Stash") != null and button(screen, "Back") != null, "Stash and Back buttons")
	var cards := nodes_of(screen, "MercCard")
	(cards[0] as MercCard).pressed.emit()
	check(screen.find_child("slot_armour", true, false) != null and screen.find_child("slot_weapon", true, false) != null and screen.find_child("slot_mod", true, false) != null, "a merc screen shows all three slots")
	check(all_text(screen).contains("Warden"), "for the merc that was tapped")
	screen.queue_free()


func test_the_merc_screen_shows_worn_items_and_stats() -> void:
	var c := Campaign.new_game(story)
	var screen := new_screen(c)
	screen.open_merc(1)
	var worn := nodes_of(screen, "ItemCard")
	check(worn.size() == 2, "armour and weapon are worn, the mod slot is empty (%d item cards)" % worn.size())
	check(card_for(screen, "Compact vest") != null and card_for(screen, "Service rifle") != null, "the vest and the service rifle")
	check(nodes_of(screen, "StatRow").size() == 6, "six stat rows")
	check(all_text(screen).contains("Empty"), "the empty slot says so")
	screen.queue_free()


func test_the_picker_offers_only_the_mercs_class_weapons_with_changes() -> void:
	var c := Campaign.new_game(story)
	c.stash.append_array(["assault_rifle", "carbine", "scatter_gun", "marksman_rifle", "scope"])
	var screen := new_screen(c)
	screen.open_picker(1, "weapon")  # Warden is a rifleman
	var offered := nodes_of(screen, "ItemCard")
	var names: Array[String] = []
	for n in offered:
		for l in n.find_children("*", "Label", true, false):
			names.append((l as Label).text)
	var joined := " ".join(names)
	check(joined.contains("Assault rifle") and not joined.contains("Short carbine") and not joined.contains("Marksman") and not joined.contains("scatter") and not joined.contains("Scatter"), "only the rifle line is offered to a rifleman: %s" % joined)
	check(joined.contains("range +1") and joined.contains("to hit +5"), "with what it would change")
	check(all_text(screen).contains("rifle"), "and a note on which class fits")
	screen.queue_free()


func test_equip_needs_a_choice_then_swaps_and_reports_the_change() -> void:
	var c := Campaign.new_game(story)
	c.stash.append("assault_rifle")
	var screen := new_screen(c)
	var changes := [0]
	screen.connect("changed", func() -> void: changes[0] += 1)
	screen.open_picker(1, "weapon")
	var equip := button(screen, "Equip")
	check(equip != null and equip.disabled, "Equip is disabled until something is chosen")
	card_for(screen, "Assault rifle").pressed.emit()
	equip = button(screen, "Equip")
	check(not equip.disabled, "choosing an item enables it")
	equip.pressed.emit()
	check(c.gear_of(1)["weapon"] == "assault_rifle" and c.stash.has("service_rifle") and not c.stash.has("assault_rifle"), "the rifle is swapped and the old one goes to the stash")
	check(changes[0] == 1, "the host was told once so it can save")
	check(screen.find_child("slot_weapon", true, false) != null and nodes_of(screen, "ItemCard").size() >= 2, "and it returns to the merc screen")
	screen.queue_free()


func test_take_off_returns_the_item_and_a_wrong_class_is_refused() -> void:
	var c := Campaign.new_game(story)
	c.stash.append("marksman_rifle")
	var screen := new_screen(c)
	screen.open_picker(1, "armour")
	var changes := [0]
	screen.connect("changed", func() -> void: changes[0] += 1)
	button(screen, "Take off").pressed.emit()
	check(c.gear_of(1)["armour"] == "" and c.stash.has("compact_vest") and changes[0] == 1, "take off puts the vest in the stash")
	screen.open_picker(1, "weapon")
	check(screen.try_equip(1, "marksman_rifle") != "" and c.gear_of(1)["weapon"] == "service_rifle", "forcing a sniper rifle onto a rifleman is refused")
	check(all_text(screen).to_lower().contains("sniper") or all_text(screen).to_lower().contains("marksman"), "and the refusal is shown")
	screen.queue_free()


func test_a_hollow_cannot_be_given_kit_and_says_so() -> void:
	var c := Campaign.new_game(story)
	c.complete_mission("karsa_breakout", true, [3], [], [])
	var screen := new_screen(c)
	for card in nodes_of(screen, "MercCard"):
		for l in card.find_children("*", "Label", true, false):
			if (l as Label).text == "HX-03":
				(card as MercCard).pressed.emit()
	check(screen.find_child("slot_weapon", true, false) == null and all_text(screen).to_lower().contains("hollow"), "tapping a hollow explains instead of opening a gear screen")
	screen.queue_free()


func test_the_stash_view_groups_items_and_back_steps_out() -> void:
	var c := Campaign.new_game(story)
	c.stash.append_array(["scope", "scope", "padded_jacket"])
	var screen := new_screen(c)
	button(screen, "Stash").pressed.emit()
	check(card_for(screen, "Salvaged scope") != null and all_text(screen).contains("x2"), "two scopes show as one card with x2")
	check(all_text(screen).contains("Warden") and all_text(screen).contains("Compact vest"), "and who wears what is listed")
	button(screen, "Back").pressed.emit()
	check(nodes_of(screen, "MercCard").size() == c.available_slots().size(), "Back returns to the hub")
	var backs := [0]
	screen.connect("back", func() -> void: backs[0] += 1)
	button(screen, "Back").pressed.emit()
	check(backs[0] == 1, "Back from the hub asks the host to leave")
	screen.queue_free()


func test_an_empty_stash_says_so() -> void:
	var c := Campaign.new_game(story)
	var screen := new_screen(c)
	screen.open_picker(1, "mod")
	check(all_text(screen).to_lower().contains("nothing in the stash"), "no items: a clear message, no cards")
	check(nodes_of(screen, "ItemCard").is_empty(), "and no item cards")
	screen.queue_free()


func test_tap_targets_are_large_on_every_view() -> void:
	var c := Campaign.new_game(story)
	c.stash.append("assault_rifle")
	var screen := new_screen(c)
	var views := [Callable(), func() -> void: screen.open_merc(1), func() -> void: screen.open_picker(1, "weapon")]
	for v in views:
		if v.is_valid():
			v.call()
		for b in screen.find_children("*", "Button", true, false):
			check((b as Button).custom_minimum_size.y >= UiTheme.MIN_TAP, "'%s' is at least %d px tall" % [(b as Button).text, UiTheme.MIN_TAP])
		for card in nodes_of(screen, "MercCard") + nodes_of(screen, "ItemCard"):
			check((card as Control).custom_minimum_size.y >= UiTheme.MIN_TAP, "a card is at least %d px tall" % UiTheme.MIN_TAP)
	screen.queue_free()
