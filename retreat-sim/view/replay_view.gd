extends Control
## Debug replay: pick a scenario, then step or play through the resolved turn.
## Keys: Esc back to the game, Space play/pause, Left/Right step, Home/End jump, 1-9 pick scenario, F cycle fog.
## Headless capture: godot --path . -- --scenario=4 --tick=8 --fog=0 --shot=out.png

const MAX_TICK := SimConst.TICKS_PER_TURN
const PLAY_SECONDS := 0.7

var _model: ReplayModel
var _tick := 0
var _board: BoardView
var _picker: OptionButton
var _note: Label
var _slider: HSlider
var _tick_label: Label
var _play_btn: Button
var _log: RichTextLabel
var _timer: Timer
var _syncing := false
var _fog_team := -1  # -1 = off, else the team whose view is shown
var _fog_picker: OptionButton


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	var args := _parse_args()
	_load_scenario(int(args.get("scenario", 0)))
	_set_fog(int(args.get("fog", -1)))
	_set_tick(int(args.get("tick", 0)))
	if args.has("shot"):
		_capture_and_quit(String(args["shot"]))


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	_board = BoardView.new()
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_board.custom_minimum_size = Vector2(480, 360)
	row.add_child(_board)

	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	panel.add_theme_constant_override("separation", 8)
	row.add_child(panel)

	_build_controls(panel)
	_build_scrubber(panel)
	_build_log(panel)

	_timer = Timer.new()
	_timer.wait_time = PLAY_SECONDS
	_timer.timeout.connect(_on_play_tick)
	add_child(_timer)


func _build_controls(panel: VBoxContainer) -> void:
	_picker = OptionButton.new()
	for i in Scenarios.count():
		_picker.add_item("%d. %s" % [i + 1, Scenarios.NAMES[i]], i)
	_picker.item_selected.connect(_on_scenario_selected)
	panel.add_child(_picker)

	_fog_picker = OptionButton.new()
	_fog_picker.add_item("Fog: off (omniscient)", 0)
	_fog_picker.add_item("Fog: view as Blue", 1)
	_fog_picker.add_item("Fog: view as Red", 2)
	_fog_picker.item_selected.connect(func(i: int): _set_fog(i - 1))
	panel.add_child(_fog_picker)

	_note = Label.new()
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(0, 54)
	panel.add_child(_note)

	var buttons := HBoxContainer.new()
	panel.add_child(buttons)
	buttons.add_child(_make_button("|<", func(): _set_tick(0)))
	buttons.add_child(_make_button("<", func(): _set_tick(_tick - 1)))
	_play_btn = _make_button("Play", _toggle_play)
	buttons.add_child(_play_btn)
	buttons.add_child(_make_button(">", func(): _set_tick(_tick + 1)))
	buttons.add_child(_make_button(">|", func(): _set_tick(MAX_TICK)))


func _build_scrubber(panel: VBoxContainer) -> void:
	_tick_label = Label.new()
	panel.add_child(_tick_label)
	_slider = HSlider.new()
	_slider.min_value = 0
	_slider.max_value = MAX_TICK
	_slider.step = 1
	_slider.value_changed.connect(func(v: float): if not _syncing: _set_tick(int(v)))
	panel.add_child(_slider)


func _build_log(panel: VBoxContainer) -> void:
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = false
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(_log)


func _make_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	return b


func _load_scenario(index: int) -> void:
	index = clampi(index, 0, Scenarios.count() - 1)
	var sc := Scenarios.build(index)
	var result := SimResolver.resolve(sc["state"], sc["plan"])
	_model = ReplayModel.new(sc["state"], sc["plan"], result)
	_picker.select(index)
	_note.text = sc["note"]
	_stop_play()
	_set_tick(0)


func _on_scenario_selected(index: int) -> void:
	_load_scenario(index)


func _set_fog(team: int) -> void:
	_fog_team = clampi(team, -1, 1)
	_fog_picker.select(_fog_team + 1)
	_set_tick(_tick)


func _fog_for(tick: int) -> Dictionary:
	return {} if _fog_team < 0 else _model.fog_at(_fog_team, tick)


func _visible_events(tick: int) -> Array[Dictionary]:
	var events := _model.events_at(tick)
	if _fog_team < 0:
		return events
	var fog := _fog_for(tick)
	return events.filter(func(ev: Dictionary) -> bool: return ReplayModel.event_visible(ev, fog))


func _set_tick(t: int) -> void:
	_tick = clampi(t, 0, MAX_TICK)
	var fog := _fog_for(_tick)
	var watchers := _model.watchers_at(_tick)
	if not fog.is_empty():
		watchers = watchers.filter(func(w: Dictionary) -> bool: return (fog["units"] as Dictionary).has(w["id"]))
	_board.clear_tracers()
	for past in range(1, _tick + 1):
		_board.record_tracers(_visible_events(past), _model.state_at(past), _fog_for(past), past < _tick)
	_board.show_frame(_model.state_at(_tick), _visible_events(_tick), watchers, fog)
	_tick_label.text = "Tick %d / %d" % [_tick, MAX_TICK]
	_syncing = true
	_slider.value = _tick
	_syncing = false
	_rebuild_log()


func _rebuild_log() -> void:
	var text := ""
	for t in range(0, MAX_TICK + 1):
		var evs := _visible_events(t)
		if evs.is_empty():
			continue
		var current := t == _tick
		var head_col := "#ffd479" if current else "#6f7885"
		text += "[color=%s][b]tick %d[/b][/color]\n" % [head_col, t]
		var fog := _fog_for(t)
		for ev in evs:
			var line := ReplayModel.describe(ev, fog).replace("[", "[lb]")
			text += "[color=%s]  %s[/color]\n" % ["#e8ecf2" if current else "#8a93a0", line]
	_log.text = text if text != "" else "[color=#8a93a0]No events.[/color]"


func _toggle_play() -> void:
	if _timer.is_stopped():
		if _tick >= MAX_TICK:
			_set_tick(0)
		_timer.start()
		_play_btn.text = "Pause"
	else:
		_stop_play()


func _stop_play() -> void:
	_timer.stop()
	_play_btn.text = "Play"


func _on_play_tick() -> void:
	if _tick >= MAX_TICK:
		_stop_play()
		return
	_set_tick(_tick + 1)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE: _toggle_play()
		KEY_RIGHT: _set_tick(_tick + 1)
		KEY_LEFT: _set_tick(_tick - 1)
		KEY_ESCAPE: get_tree().change_scene_to_file("res://view/play.tscn")
		KEY_F: _set_fog(-1 if _fog_team == 1 else _fog_team + 1)
		KEY_HOME: _set_tick(0)
		KEY_END: _set_tick(MAX_TICK)
		_:
			var n: int = event.keycode - KEY_1
			if n >= 0 and n < Scenarios.count():
				_load_scenario(n)


func _capture_and_quit(path: String) -> void:
	for i in 3:
		await get_tree().process_frame
	var err := get_viewport().get_texture().get_image().save_png(path)
	if err != OK:
		printerr("screenshot failed: ", err)
	get_tree().quit(0 if err == OK else 1)
