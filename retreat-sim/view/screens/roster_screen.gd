class_name RosterScreen
extends VBoxContainer
## Everyone who can be sent out: a card each with class, level and an XP bar, and a detail view with the
## stats against their caps, class, XP, missions and kills, and a Level up button when picks are waiting.
## `open_levelup` asks the host to show the LevelUpScreen for that merc; `back` leaves.

signal back
signal done
signal open_levelup(slot: int)

var _c: Campaign


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)


func setup(c: Campaign) -> RosterScreen:
	_c = c
	_show_list()
	return self


func open_detail(slot: int) -> void:
	_show_detail(slot)


func _reset(title: String) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	add_child(UiTheme.label(title, 26))
	add_child(ResourceBar.new().setup(UiModel.resources_info(_c)))


func _show_list() -> void:
	_reset("Roster")
	var list := ScrollList.new()
	add_child(list)
	for slot in _c.available_slots():
		var card := MercCard.new().setup(UiModel.merc_info(_c, slot))
		card.pressed.connect(_show_detail.bind(slot))
		list.add_card(card)
	add_child(_button("Back", func() -> void: back.emit()))


func _show_detail(slot: int) -> void:
	_reset(UiModel.merc_name(_c, slot))
	var info := UiModel.merc_info(_c, slot)
	add_child(MercCard.new().setup(info))
	var list := ScrollList.new()
	add_child(list)
	for key in UiModel.STAT_ORDER:
		list.add_card(StatRow.new().setup(UiModel.STAT_LABEL[key], int(info["base"][key]), int(UiModel.STAT_CAP[key])))
	list.add_card(_note("Class: %s. %s" % [_c.class_name_of(_c.class_of(slot)), String(_c.story["classes"]["classes"][_c.class_of(slot)]["summary"])], UiTheme.COL_TEXT))
	if info["status"] == "named":
		var at_max := _c.level_of(slot) >= _c.max_level()
		list.add_card(_note("Level %d. XP %d%s." % [_c.level_of(slot), _c.xp_of(slot), "  (top level)" if at_max else " of %d for the next" % _c.xp_next(slot)], UiTheme.COL_TEXT))
		var e: Dictionary = _c._roster[slot]
		list.add_card(_note("Missions %d, kills %d." % [int(e["missions"]), int(e["kills"])], UiTheme.COL_TEXT))
	else:
		list.add_card(_note("A hollow: stats are frozen at 60% and it never levels.", UiTheme.COL_HOLLOW))
	if _c.levelup_pending(slot) > 0:
		add_child(_button("Level up (%d waiting)" % _c.levelup_pending(slot), func() -> void: open_levelup.emit(slot)))
	add_child(_button("Back", _show_list))


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, UiTheme.MIN_TAP)
	b.pressed.connect(action)
	return b


func _note(text: String, color: Color = UiTheme.COL_MUTED) -> Label:
	var l := UiTheme.label(text, UiTheme.FONT_SMALL, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
