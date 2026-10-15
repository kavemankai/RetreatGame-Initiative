class_name LoadoutScreen
extends VBoxContainer
## Changing a squad's kit, built from the UI kit. Four views: the roster (tap a merc), a merc's gear (stats
## with gear folded in and their three slots), the item picker (what is in the stash for that slot, a
## weapon only if it is of the merc's class, each with what it would change) and the stash itself.
## It changes only the Campaign (equip, unequip) and tells its host through `changed` so it can save and
## play a sound; `back` asks the host to leave.

signal back
signal done
signal changed

var _c: Campaign
var _slot := -1
var _kind := ""
var _selected := ""
var _message := ""


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)


func setup(c: Campaign) -> LoadoutScreen:
	_c = c
	_show_hub()
	return self


## Jump straight to one merc's gear (used by the demo and by shortcuts from other screens).
func open_merc(slot: int) -> void:
	_slot = slot
	_message = ""
	_show_merc()


## Jump straight to the stash view (the map's Stash button).
func open_stash() -> void:
	_show_stash()


func open_picker(slot: int, kind: String) -> void:
	_slot = slot
	_kind = kind
	_selected = ""
	_message = ""
	_show_picker()


## Puts a stash item on a merc. Returns "" or why not (and shows the reason). Tells the host on success.
func try_equip(slot: int, item_id: String) -> String:
	var why := _c.equip(slot, item_id)
	if why != "":
		_message = why
		_show_picker()
		return why
	_selected = ""
	_message = ""
	changed.emit()
	_slot = slot
	_show_merc()
	return ""


# --- views --------------------------------------------------------------------------------------

func _reset(title: String) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	add_child(UiTheme.label(title, 26))
	add_child(ResourceBar.new().setup(UiModel.resources_info(_c)))


func _button(text: String, action: Callable, disabled := false) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, UiTheme.MIN_TAP)
	b.pressed.connect(action)
	return b


func _note(text: String, color: Color = UiTheme.COL_MUTED) -> Label:
	var l := UiTheme.label(text, UiTheme.FONT_SMALL, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _show_hub() -> void:
	_reset("Loadout")
	add_child(_note("Tap a merc to change their kit. %d item%s in the stash." % [_c.stash.size(), "" if _c.stash.size() == 1 else "s"]))
	var list := ScrollList.new()
	add_child(list)
	for slot in _c.available_slots():
		var card := MercCard.new().setup(UiModel.merc_info(_c, slot))
		card.pressed.connect(_on_merc_tapped.bind(slot))
		list.add_card(card)
	if _message != "":
		add_child(_note(_message, UiTheme.COL_BAD))
	add_child(_button("Stash", _show_stash))
	add_child(_button("Back", func() -> void: back.emit()))


func _on_merc_tapped(slot: int) -> void:
	if _c.slot_status(slot) != "named":
		_message = "%s is a hollow. Hollows carry no kit; they fight bare." % UiModel.merc_name(_c, slot)
		_show_hub()
		return
	open_merc(slot)


func _show_merc() -> void:
	_message = ""
	_reset(UiModel.merc_name(_c, _slot))
	var info := UiModel.merc_info(_c, _slot)
	add_child(MercCard.new().setup(info))
	var list := ScrollList.new()
	add_child(list)
	for key in UiModel.STAT_ORDER:
		var d := int(info["stats"][key]) - int(info["base"][key])
		list.add_card(StatRow.new().setup(UiModel.STAT_LABEL[key], int(info["stats"][key]), int(UiModel.STAT_CAP[key]), d, d > 0))
	for kind in Campaign.GEAR_SLOTS:
		list.add_card(UiTheme.label(String(kind).capitalize(), UiTheme.FONT_BODY, UiTheme.COL_AMBER))
		list.add_card(_slot_card(kind))
	add_child(_button("Back", _show_hub))


func _slot_card(kind: String) -> Control:
	var id := String(_c.gear_of(_slot)[kind])
	var card: TapPanel
	if id != "":
		card = ItemCard.new().setup(UiModel.item_info(_c, id, 1))
	else:
		card = _empty_card(kind)
	card.name = "slot_" + kind
	card.pressed.connect(open_picker.bind(_slot, kind))
	return card


func _empty_card(kind: String) -> TapPanel:
	var card := TapPanel.new()
	card.custom_minimum_size = Vector2(0, 72)
	card.add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.COL_DEEP, UiTheme.COL_MUTED, 1))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	row.add_child(SlotGlyph.new(40).setup(kind, false, "", _c.class_of(_slot) if kind == "weapon" else ""))
	row.add_child(UiTheme.label("Empty %s slot. Tap to choose." % kind, UiTheme.FONT_BODY, UiTheme.COL_MUTED))
	UiTheme.ignore_mouse_inside(card)
	return card


func _show_picker() -> void:
	_reset("%s: %s" % [_kind.capitalize(), UiModel.merc_name(_c, _slot)])
	if _kind == "weapon":
		add_child(_note("%s carries %s weapons only." % [UiModel.merc_name(_c, _slot), _c.class_name_of(_c.class_of(_slot)).to_lower()]))
	var worn := String(_c.gear_of(_slot)[_kind])
	if worn != "":
		add_child(UiTheme.label("Worn", UiTheme.FONT_BODY, UiTheme.COL_AMBER))
		add_child(ItemCard.new().setup(UiModel.item_info(_c, worn, 1)))
	var list := ScrollList.new()
	add_child(list)
	var counts := {}
	for id in _c.stash_for(_kind, _slot):
		counts[id] = int(counts.get(id, 0)) + 1
	var ids: Array = counts.keys()
	ids.sort()
	if ids.is_empty():
		list.add_card(_note("Nothing in the stash for this slot."))
	for id in ids:
		var card := ItemCard.new().setup(UiModel.item_info(_c, String(id), int(counts[id]), _slot, _kind, String(id) == _selected))
		card.pressed.connect(_select.bind(String(id)))
		list.add_card(card)
	if _message != "":
		add_child(_note(_message, UiTheme.COL_BAD))
	add_child(_button("Equip", func() -> void: try_equip(_slot, _selected), _selected == ""))
	if worn != "":
		add_child(_button("Take off", _take_off))
	add_child(_button("Back", _show_merc))


func _select(id: String) -> void:
	_selected = id
	_message = ""
	_show_picker()


func _take_off() -> void:
	var why := _c.unequip(_slot, _kind)
	if why != "":
		_message = why
		_show_picker()
		return
	changed.emit()
	_show_merc()


func _show_stash() -> void:
	_reset("Stash")
	var list := ScrollList.new()
	add_child(list)
	var counts := {}
	for id in _c.stash:
		counts[id] = int(counts.get(id, 0)) + 1
	var ids: Array = counts.keys()
	ids.sort()
	if ids.is_empty():
		list.add_card(_note("The stash is empty. Missions pay out kit; a fallen merc's gear comes back here."))
	for id in ids:
		list.add_card(ItemCard.new().setup(UiModel.item_info(_c, String(id), int(counts[id]))))
	list.add_card(UiTheme.label("Worn", UiTheme.FONT_BODY, UiTheme.COL_AMBER))
	for slot in _c.available_slots():
		if _c.slot_status(slot) != "named":
			continue
		var g := _c.gear_of(slot)
		var names: Array[String] = []
		for kind in Campaign.GEAR_SLOTS:
			var id := String(g[kind])
			names.append(String(_c.item(id).get("name", "-")) if id != "" else "-")
		list.add_card(_note("%s: %s" % [UiModel.merc_name(_c, slot), " | ".join(names)], UiTheme.COL_TEXT))
	add_child(_button("Back", _show_hub))
