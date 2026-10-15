class_name KitGallery
extends VBoxContainer
## Every widget of the UI kit on one scrolling page, filled from a real Campaign: for checking the
## look on a device and in screenshots (`--demo=kit`). Later screens are built from the same parts.

signal back
signal done


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)


func setup(c: Campaign, show_mercs := true) -> KitGallery:
	add_child(UiTheme.label("UI kit", 26))
	add_child(ResourceBar.new().setup(UiModel.resources_info(c)))
	var list := ScrollList.new()
	add_child(list)
	if show_mercs:
		list.add_card(UiTheme.label("Mercs", UiTheme.FONT_BODY, UiTheme.COL_AMBER))
		var first := true
		for slot in c.available_slots():
			list.add_card(MercCard.new().setup(UiModel.merc_info(c, slot, first)))
			first = false
	list.add_card(UiTheme.label("Items in the stash (changes shown for the first merc)", UiTheme.FONT_BODY, UiTheme.COL_AMBER))
	var counts := {}
	for id in c.stash:
		counts[id] = int(counts.get(id, 0)) + 1
	var ids: Array = counts.keys()
	ids.sort()
	var slots := c.available_slots()
	for id in ids:
		var kind := String(c.item(id).get("slot", ""))
		list.add_card(ItemCard.new().setup(UiModel.item_info(c, id, int(counts[id]), slots[0] if not slots.is_empty() else -1, kind)))
	list.add_card(UiTheme.label("Stats (gear shown against base)", UiTheme.FONT_BODY, UiTheme.COL_AMBER))
	if not slots.is_empty():
		var base := c.slot_stats(slots[0])
		var eff := c.effective_stats(slots[0])
		for key in UiModel.STAT_ORDER:
			var d := int(eff[key]) - int(base[key])
			list.add_card(StatRow.new().setup(UiModel.STAT_LABEL[key], int(eff[key]), int(UiModel.STAT_CAP[key]), d, d > 0))
	list.add_card(UiTheme.label("Weapon classes (glyph, then name)", UiTheme.FONT_BODY, UiTheme.COL_AMBER))
	var classes := HFlowContainer.new()
	classes.add_theme_constant_override("h_separation", 14)
	classes.add_theme_constant_override("v_separation", 8)
	for cid in c.story["classes"]["classes"]:
		var cell := VBoxContainer.new()
		cell.add_child(SlotGlyph.new(48).setup("weapon", true, "", String(cid)))
		cell.add_child(UiTheme.label(c.class_name_of(String(cid)), UiTheme.FONT_SMALL, UiTheme.COL_MUTED))
		classes.add_child(cell)
	list.add_card(classes)
	var back_button := Button.new()
	back_button.text = "Back"
	back_button.focus_mode = Control.FOCUS_NONE
	back_button.custom_minimum_size = Vector2(0, UiTheme.MIN_TAP)
	back_button.pressed.connect(func() -> void: back.emit())
	add_child(back_button)
	return self
