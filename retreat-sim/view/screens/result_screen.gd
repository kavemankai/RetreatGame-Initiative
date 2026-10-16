class_name ResultScreen
extends VBoxContainer
## After a fight: the verdict, what it did to the Procession and Reserves (before, after, change), who died
## and the Writ's losses, then a report for each merc who deployed (how they fared, shots, hits, kills and
## the XP earned with a bar). Data comes from UiModel.result_info. `done` continues.

signal done

const COUNT_SECONDS := 0.8

var _info: Dictionary
var _delta_labels: Array[Label] = []
var _tween: Tween


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)


func setup(c: Campaign, step: Dictionary) -> ResultScreen:
	_info = UiModel.result_info(c, step)
	add_child(UiTheme.label(String(_info["title"]), 24))
	add_child(UiTheme.label(String(_info["verdict"]), UiTheme.FONT_TITLE + 4, UiTheme.COL_GOOD if _info["won"] else UiTheme.COL_BAD))
	var list := ScrollList.new()
	add_child(list)
	list.add_card(_deltas_panel())
	for note: String in _info["notes"]:
		list.add_card(_note(note, UiTheme.COL_TEXT))
	if not (_info["squad"] as Array).is_empty():
		list.add_card(UiTheme.label("Squad report", UiTheme.FONT_BODY, UiTheme.COL_AMBER))
	for row: Dictionary in _info["squad"]:
		list.add_card(_report_card(row))
	_start_count()
	var next := Button.new()
	next.text = "Continue"
	next.focus_mode = Control.FOCUS_NONE
	next.custom_minimum_size = Vector2(0, UiTheme.MIN_TAP)
	next.pressed.connect(func() -> void:
		finish_animation()
		done.emit())
	add_child(next)
	return self


func _deltas_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.COL_PANEL))
	var col := VBoxContainer.new()
	panel.add_child(col)
	for d: Dictionary in _info["deltas"]:
		var l := UiTheme.label("", UiTheme.FONT_BODY)
		_delta_labels.append(l)
		col.add_child(l)
		_set_delta(_delta_labels.size() - 1, int(d["before"]))
	return panel


## One resource line with the "after" figure at `shown` (the count-up passes through the values between).
func _set_delta(index: int, shown: int) -> void:
	var d: Dictionary = _info["deltas"][index]
	var change := int(d["after"]) - int(d["before"])
	var l := _delta_labels[index]
	l.text = "%s   %d  to  %d   (%s)" % [d["label"], int(d["before"]), shown, UiTheme.delta_text(change)]
	l.add_theme_color_override("font_color", UiTheme.COL_TEXT if change == 0 else UiTheme.delta_color(change > 0))


## The figures count from before to after over a moment, so a loss is seen as it lands.
func _start_count() -> void:
	_tween = create_tween().set_parallel(true)
	for i in _delta_labels.size():
		var d: Dictionary = _info["deltas"][i]
		_tween.tween_method(func(shown: int) -> void: _set_delta(i, shown), int(d["before"]), int(d["after"]), COUNT_SECONDS)


## Skips the animation to the final figures (a tap, and the tests).
func finish_animation() -> void:
	if _tween != null:
		_tween.kill()
	for i in _delta_labels.size():
		_set_delta(i, int((_info["deltas"][i] as Dictionary)["after"]))


func delta_texts() -> Array[String]:
	var out: Array[String] = []
	for l in _delta_labels:
		out.append(l.text)
	return out


func _report_card(row: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.COL_PANEL))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var name_label := UiTheme.label(String(row["name"]), UiTheme.FONT_BODY, UiTheme.COL_TEXT if row["alive"] else UiTheme.COL_BAD)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	head.add_child(UiTheme.chip(String(row["outcome"]), UiTheme.COL_MUTED if row["alive"] else UiTheme.COL_BAD))
	col.add_child(_note("Shots %d, hits %d, kills %d" % [int(row["shots"]), int(row["hits"]), int(row["kills"])], UiTheme.COL_MUTED))
	if int(row["xp_gained"]) > 0:
		var xp_line := "+%d XP" % int(row["xp_gained"])
		if row.get("leveled", false):
			xp_line += "   Level %d reached" % int(row["level"])
		col.add_child(_note(xp_line, UiTheme.COL_AMBER))
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 8)
		bar.show_percentage = false
		var floor_xp := int(row["xp_floor"])
		bar.max_value = maxf(1.0, float(int(row["xp_next"]) - floor_xp))
		bar.value = clampf(float(int(row["xp"]) - floor_xp), 0.0, bar.max_value)
		col.add_child(bar)
	return panel


func _note(text: String, color: Color = UiTheme.COL_MUTED) -> Label:
	var l := UiTheme.label(text, UiTheme.FONT_SMALL, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l
