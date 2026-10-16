class_name MissionPrepScreen
extends VBoxContainer
## Before a fight, one screen: the briefing (place, objective, what winning and losing cost, reward, who is
## known to be there, Orrick), then the squad to pick with a card each, readiness warnings, and Deploy.
## It changes nothing: `deploy(slots)`, `loadout`, `roster` and `back` ask the host to act.

signal deploy(slots: Array)
signal loadout
signal roster
signal back

var _c: Campaign
var _id := ""
var _briefing_bbcode := ""
var _picked: Array[int] = []
var _scroll: ScrollContainer


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)


## `briefing_bbcode` is the mission's briefing scene, already formatted by the host. `keep` is a squad chosen
## earlier (still-available slots only); empty gives the default squad.
func setup(c: Campaign, mission_id: String, briefing_bbcode: String, keep: Array = []) -> MissionPrepScreen:
	_c = c
	_id = mission_id
	_briefing_bbcode = briefing_bbcode
	var m := c.mission_or_card(mission_id)
	var need := UiModel.squad_need(c, m)
	var available := c.available_slots()
	_picked = []
	for slot in keep:
		if available.has(int(slot)) and _picked.size() < need:
			_picked.append(int(slot))
	if _picked.is_empty():
		_picked = UiModel.default_squad(c, need)
	_show()
	return self


func picked() -> Array[int]:
	return _picked.duplicate()


## Adds or removes a merc from the squad (what tapping their card does); a full squad refuses more.
func toggle(slot: int) -> void:
	var need := UiModel.squad_need(_c, _c.mission_or_card(_id))
	if _picked.has(slot):
		_picked.erase(slot)
	elif _picked.size() < need:
		_picked.append(slot)
	var keep := _scroll.scroll_vertical if _scroll != null else 0
	_show()
	_restore_scroll.call_deferred(keep)


func _restore_scroll(at: int) -> void:
	if _scroll != null:
		_scroll.scroll_vertical = at


func _show() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var info := UiModel.prep_info(_c, _id)
	var need := UiModel.squad_need(_c, _c.mission_or_card(_id))
	add_child(UiTheme.label(("Contingency: %s" % info["name"]) if info["is_card"] else ("Act %d: %s" % [info["act"], info["name"]]), 24))
	add_child(ResourceBar.new().setup(UiModel.resources_info(_c)))
	var list := ScrollList.new()
	_scroll = list
	add_child(list)
	list.add_card(_briefing_panel(info))
	list.add_card(_note("Choose %d for the squad. Hollows fight at 60%% of the soldier they replace and never lose their nerve." % need, UiTheme.COL_TEXT))
	for slot in _c.available_slots():
		var card := MercCard.new().setup(UiModel.merc_info(_c, slot, _picked.has(slot)))
		card.pressed.connect(toggle.bind(slot))
		list.add_card(card)
	var warnings := UiModel.readiness(_c, _picked, need)
	for w: Dictionary in warnings:
		if w["level"] != "block":
			add_child(_note(String(w["text"]), UiTheme.COL_BAD if w["level"] == "warn" else UiTheme.COL_MUTED))
	var go := _button("Deploy (%d/%d)" % [_picked.size(), need], func() -> void: deploy.emit(_picked.duplicate()), _picked.size() != need or need == 0)
	go.name = "deploy_button"
	add_child(go)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	row.add_child(_button("Loadout (%d)" % _c.stash.size(), loadout.emit, false, true))
	row.add_child(_button("Roster", roster.emit, false, true))
	row.add_child(_button("Back", back.emit, false, true))


func _briefing_panel(info: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.COL_PANEL, Color.TRANSPARENT, 0))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	col.add_child(_note("%s" % info["place"], UiTheme.COL_MUTED))
	var scene := RichTextLabel.new()
	scene.bbcode_enabled = true
	scene.fit_content = true
	scene.scroll_active = false
	scene.text = _briefing_bbcode
	col.add_child(scene)
	col.add_child(_note("Objective: %s" % info["objective"], UiTheme.COL_TEXT))
	col.add_child(_note("Win:  %s" % info["on_success"], UiTheme.COL_GOOD))
	col.add_child(_note("Lose: %s" % info["on_failure"], UiTheme.COL_BAD))
	if not (info["rewards"] as Array).is_empty():
		col.add_child(_note("Reward on a win: %s" % ", ".join(info["rewards"]), UiTheme.COL_AMBER))
	if not (info["enemies"] as Array).is_empty():
		col.add_child(_note("Known opposition: %s" % ", ".join(info["enemies"]), UiTheme.COL_TEXT))
	if info["orrick"]:
		col.add_child(_note("Orrick will be there.", UiTheme.COL_TEAL))
	return panel


func _button(text: String, action: Callable, disabled := false, expand := false) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, UiTheme.MIN_TAP)
	if expand:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(action)
	return b


func _note(text: String, color: Color = UiTheme.COL_MUTED) -> Label:
	var l := UiTheme.label(text, UiTheme.FONT_SMALL, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
