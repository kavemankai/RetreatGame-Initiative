class_name LevelUpScreen
extends VBoxContainer
## Spending a merc's earned level-ups: their card (XP bar, level), then the stat steps on offer, each
## showing the change and what it does in combat in plain words. Pick one, Confirm. If more level-ups are
## waiting the next offer follows. `chosen` fires after each pick (the host saves); `done` when none remain.

signal done
signal chosen

var _c: Campaign
var _slot := -1
var _selected := ""
var _message := ""


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)


func setup(c: Campaign, slot: int) -> LevelUpScreen:
	_c = c
	_slot = slot
	_show()
	return self


func _show() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var name := UiModel.merc_name(_c, _slot)
	if _c.levelup_pending(_slot) <= 0:
		add_child(UiTheme.label("%s has no level-up to spend." % name, UiTheme.FONT_BODY))
		add_child(_button("Continue", func() -> void: done.emit()))
		return
	add_child(UiTheme.label("%s: level %d" % [name, _c.level_of(_slot)], 26))
	add_child(MercCard.new().setup(UiModel.merc_info(_c, _slot)))
	var waiting := _c.levelup_pending(_slot)
	add_child(_note("Choose one stat step. It is permanent.%s" % ((" %d level-ups are waiting." % waiting) if waiting > 1 else "")))
	var list := ScrollList.new()
	add_child(list)
	for o: Dictionary in _c.levelup_offer(_slot):
		list.add_card(_option_card(o))
	if _message != "":
		add_child(_note(_message, UiTheme.COL_BAD))
	add_child(_button("Confirm", _confirm, _selected == ""))


func _option_card(o: Dictionary) -> TapPanel:
	var stat := String(o["stat"])
	var card := TapPanel.new()
	card.name = "opt_" + stat
	card.custom_minimum_size = Vector2(0, 80)
	var picked := stat == _selected
	card.add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.COL_PANEL_HI if picked else UiTheme.COL_PANEL, UiTheme.COL_AMBER if picked else Color.TRANSPARENT, 2))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	card.add_child(col)
	col.add_child(UiTheme.label("%s   %d  to  %d" % [UiModel.STAT_LABEL[stat], int(o["from"]), int(o["to"])], 20, UiTheme.COL_AMBER if picked else UiTheme.COL_TEXT))
	col.add_child(_note(UiModel.stat_effect_text(stat, int(o["from"]), int(o["to"])), UiTheme.COL_TEXT))
	UiTheme.ignore_mouse_inside(card)
	card.pressed.connect(_select.bind(stat))
	return card


func _select(stat: String) -> void:
	_selected = stat
	_message = ""
	_show()


func _confirm() -> void:
	var why := _c.choose_levelup(_slot, _selected)
	if why != "":
		_message = why
		_show()
		return
	_selected = ""
	_message = ""
	chosen.emit()
	if _c.levelup_pending(_slot) > 0:
		_show()
	else:
		done.emit()


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
