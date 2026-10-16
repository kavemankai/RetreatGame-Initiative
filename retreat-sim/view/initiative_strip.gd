class_name InitiativeStrip
extends HBoxContainer
## The round label and the queue of who acts next: the active unit first and highlighted,
## then the rest of this round in order. Squad chips are blue, enemy chips red. It only
## displays; it never changes state.

const COL_SQUAD := Color("2f5d8a")
const COL_ENEMY := Color("8a3a33")
const COL_ACTIVE := Color("ffd479")
const MAX_CHIPS := 7
const CHIP_MIN := Vector2(66, 34)

var _round_label: Label
var _chips: HBoxContainer


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_round_label = Label.new()
	_round_label.add_theme_color_override("font_color", COL_ACTIVE)
	add_child(_round_label)
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 4)
	_chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_chips)


## `entries`: [{id, team, active}] in activation order; `name_of` turns an id into a short label.
func show_order(round_no: int, entries: Array[Dictionary], player_team: int, name_of: Callable) -> void:
	_round_label.text = "Round %d" % round_no
	for child in _chips.get_children():
		_chips.remove_child(child)
		child.queue_free()
	var shown := mini(entries.size(), MAX_CHIPS)
	for i in shown:
		_chips.add_child(_chip(entries[i], player_team, name_of))
	if entries.size() > MAX_CHIPS:
		var more := Label.new()
		more.text = "+%d" % (entries.size() - MAX_CHIPS)
		_chips.add_child(more)


func _chip(entry: Dictionary, player_team: int, name_of: Callable) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = CHIP_MIN
	var style := StyleBoxFlat.new()
	style.bg_color = COL_SQUAD if int(entry["team"]) == player_team else COL_ENEMY
	style.set_corner_radius_all(6)
	style.set_content_margin_all(4)
	if bool(entry["active"]):
		style.set_border_width_all(3)
		style.border_color = COL_ACTIVE
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = String(name_of.call(int(entry["id"])))
	label.clip_text = true
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(label)
	return panel
