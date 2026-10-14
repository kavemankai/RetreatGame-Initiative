extends Control
## Playable skirmish. Plan, press Go, and the round plays out all 20 ticks
## with no stops; then plan the next one. Shots leave tracers until the next Go,
## and hit units show their morale result (steady: no shooting; broken: halted).
##
## Responsive: a window taller than wide gets the phone PORTRAIT layout (board
## on top, thumb-sized controls below, two-tap commit); wider windows get the
## desktop layout. Touch input arrives as emulated mouse clicks.
##
## Keys: Enter/Space go - Backspace undo - O overwatch - Esc deselect
##       1-3 select - N new match - V replay viewer - T toggle two-tap - S speed
## Scripted capture: godot --path . -- --do="click 2,4;click 5,4;go;step 4" --shot=out.png
##   (add --touch=1 to force two-tap; use Godot's --resolution 540x960 for portrait)

const TICKS := SimConst.TICKS_PER_TURN
const PORTRAIT_BOARD_ASPECT := 0.8  # board height / width on a phone; the iso board is zoomed to fill it
const TARGET_TILE_PX := 84.0  # portrait: on-screen tile width the zoom aims for (a 12x10 map fits at 1.7x)
const SPEEDS: Array[float] = [0.55, 0.28, 0.12]
const SPEED_LABELS: Array[String] = ["1x", "2x", "4x"]
## Seconds per tick while nobody has orders: the run races to the next stop.
const IDLE_SECONDS := 0.04
const MARGIN := 10
const TOUCH_BUTTON_HEIGHT := 60
const CONFIRM_HEIGHT := 64
const FONT_PORTRAIT := 18
const FONT_LANDSCAPE := 16
const COL_OK := Color("9be39b")
const COL_BAD := Color("ff9a8a")
const COL_NEUTRAL := Color("d8dee9")

var _game: SimMatch
var _ctl: PlayController
var _running := false
var _sound: SoundBoard
var _mute_btn: Button
var _map_btn: Button
var _goal_label: Label
var _overview := false  # the Map button: show the whole board instead of the zoomed squad view
var _skirmish_seed := 0
var _speed := 0
var _portrait := false
var _two_tap := false

var _main: BoxContainer
var _panel: VBoxContainer
var _board: BoardView
var _title: Label
var _speed_btn: Button
var _new_btn: Button
var _banner: Label
var _squad: BoxContainer
var _hint: Label
var _msg: Label
var _legend: Label
var _go_btn: Button
var _overwatch_btn: Button
var _ms_btn: Button
var _timeline: TimelineBar
var _action_buttons: Array[Button] = []
var _log: RichTextLabel
var _timer: Timer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var args := _parse_args()
	_two_tap = DisplayServer.is_touchscreen_available() or args.get("touch", "0") == "1"
	if args.has("campaign") and not Session.in_campaign():
		_demo_campaign(String(args["campaign"]))
	_build_ui()
	resized.connect(_apply_layout)
	_new_match()
	_apply_layout()
	if args.has("do"):
		_run_script(String(args["do"]))
	if args.has("shot"):
		_capture_and_quit(String(args["shot"]))


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out


# --- layout ----------------------------------------------------------------

func _build_ui() -> void:
	theme = Theme.new()
	_sound = SoundBoard.new()  # first, so every button built after it clicks
	add_child(_sound)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, MARGIN)
	add_child(margin)
	_main = BoxContainer.new()
	_main.add_theme_constant_override("separation", 10)
	margin.add_child(_main)

	_board = BoardView.new()
	_board.tile_clicked.connect(_on_tile_clicked)
	_board.tile_hovered.connect(_on_tile_hovered)
	_main.add_child(_board)

	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 8)
	_main.add_child(_panel)
	_build_panel()

	_timer = Timer.new()
	_timer.wait_time = SPEEDS[0]
	_timer.timeout.connect(_do_tick)
	add_child(_timer)


func _build_panel() -> void:
	var top := HBoxContainer.new()
	_panel.add_child(top)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	top.add_child(_title)
	_speed_btn = _small_button(SPEED_LABELS[0], _cycle_speed)
	top.add_child(_speed_btn)
	_map_btn = _small_button("Map", _toggle_overview)
	_map_btn.toggle_mode = true
	_map_btn.custom_minimum_size = Vector2(56, 40)
	top.add_child(_map_btn)
	_mute_btn = _small_button("", _toggle_mute)
	_mute_btn.custom_minimum_size = Vector2(64, 40)
	top.add_child(_mute_btn)
	_update_mute_label()
	_new_btn = _small_button("New", _on_new_pressed)
	_new_btn.custom_minimum_size = Vector2(84, 40)
	top.add_child(_new_btn)
	top.add_child(_small_button("Menu", _open_menu))

	_goal_label = Label.new()
	_goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_goal_label.add_theme_color_override("font_color", Color("ffd479"))
	_goal_label.visible = false
	_panel.add_child(_goal_label)

	_banner = Label.new()
	_banner.add_theme_font_size_override("font_size", 26)
	_banner.visible = false
	_panel.add_child(_banner)

	_timeline = TimelineBar.new()
	_panel.add_child(_timeline)

	_squad = BoxContainer.new()
	_panel.add_child(_squad)

	var tools := HBoxContainer.new()
	_panel.add_child(tools)
	_overwatch_btn = _action_button("Overwatch", _toggle_overwatch)
	tools.add_child(_overwatch_btn)
	_ms_btn = _action_button("Move+Fire", _toggle_move_fire)
	tools.add_child(_ms_btn)
	tools.add_child(_action_button("Undo", _undo))
	tools.add_child(_action_button("Clear", _clear))

	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override("font_color", COL_NEUTRAL)
	_panel.add_child(_hint)
	_msg = Label.new()
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_msg)

	_legend = Label.new()
	_legend.text = "Click a merc, then a tile to move, an enemy to shoot. Press Go: the turn plays live and you can Pause any time to re-plan. Dashed red = enemy orders you can see."
	_legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_legend.add_theme_color_override("font_color", Color("8a93a0"))
	_panel.add_child(_legend)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size = Vector2(0, 60)
	_panel.add_child(_log)

	# Last, at the bottom edge: where a thumb rests on a phone.
	_go_btn = _action_button("Go", _toggle_run)
	_panel.add_child(_go_btn)


func _action_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	_action_buttons.append(b)
	return b


func _small_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(58, 40)
	b.pressed.connect(action)
	return b


## Portrait (taller than wide) gets the phone layout; otherwise desktop.
func _apply_layout() -> void:
	if _board == null or _game == null:
		return
	_portrait = size.y > size.x
	_main.vertical = _portrait
	theme.default_font_size = FONT_PORTRAIT if _portrait else FONT_LANDSCAPE
	_squad.vertical = not _portrait
	_legend.visible = not _portrait
	var grid := _game.state.grid
	if _portrait:
		var board_w := size.x - 2.0 * MARGIN
		_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_board.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_board.custom_minimum_size = Vector2(0, board_w * PORTRAIT_BOARD_ASPECT)
		_board.set_zoom(1.0 if _overview else _portrait_zoom(board_w, board_w * PORTRAIT_BOARD_ASPECT))
		_panel.custom_minimum_size = Vector2.ZERO
		_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_board.custom_minimum_size = Vector2(480, 360)
		_board.set_zoom(1.0)
		_panel.custom_minimum_size = Vector2(380, 0)
		_panel.size_flags_horizontal = Control.SIZE_FILL
	for b in _action_buttons:
		b.custom_minimum_size = Vector2(0, TOUCH_BUTTON_HEIGHT if _portrait else 0)
	_go_btn.custom_minimum_size = Vector2(0, CONFIRM_HEIGHT if _portrait else 44)
	_refresh_panel()


# --- match flow -------------------------------------------------------------

func _new_match() -> void:
	_skirmish_seed += 1  # each "New" skirmish rolls a fresh set of morale dice
	_game = Session.current_match if Session.in_campaign() else SimMatch.skirmish(_skirmish_seed)
	_ctl = PlayController.new(_game)
	_running = false
	if _board != null:
		_board.clear_tracers()
		_board.set_level_theme(_game.theme)
		_sound.set_ambient(_game.theme)
		_sound.set_music(_current_act())
	_timer.stop()
	_log.clear()
	_msg.text = ""
	_hint.text = ""
	_log_header()
	_apply_layout()
	_refresh()


## In a campaign mission "New" becomes "Withdraw": leave the field, keep the
## survivors, pay the failure cost.
func _on_new_pressed() -> void:
	if Session.in_campaign():
		Session.withdrawn = true
		_finish_campaign_mission()
	else:
		_new_match()


func _finish_campaign_mission() -> void:
	_timer.stop()
	if Session.level_test:  # a menu level test: no debrief, back to the menu (or the sandbox)
		var back := "res://view/sandbox.tscn" if Session.sandbox else "res://view/campaign.tscn"
		Session.reset()
		get_tree().change_scene_to_file(back)
		return
	Session.pending_outcome = MissionBuilder.outcome(Session.campaign, _game, Session.withdrawn)
	get_tree().change_scene_to_file("res://view/campaign.tscn")


func _open_menu() -> void:
	if Session.in_campaign():
		return  # mid-mission: use Withdraw
	Session.reset()
	get_tree().change_scene_to_file("res://view/campaign.tscn")


## Go: hand the orders to the run and start the clock. Once running, the
## round cannot be paused; it plays to the end.
func _toggle_run() -> void:
	if _game.is_over():
		if Session.in_campaign():
			_finish_campaign_mission()
		return
	if _running:
		return
	var err := _ctl.go()
	if err != "":
		_say(err, false)
		return
	_running = true
	_sound.play("ui_go")
	_board.clear_tracers()
	_msg.text = ""
	_hint.text = ""
	_timer.wait_time = SPEEDS[_speed]
	_board.glide_seconds = _timer.wait_time
	_timer.start()
	_refresh()


## One tick of the live turn: resolve it, draw it, and stop if something
## happened that deserves the player's attention.
func _do_tick() -> void:
	if _game.run == null:
		_stop_run("")
		return
	var prev := _game.state.clone()
	var turn_before := _game.turn
	var r := _game.step()
	var fog := SimVision.fog_between(prev, _game.state, _game.player_team)
	var events: Array[Dictionary] = []
	for ev: Dictionary in r["events"]:
		if ReplayModel.event_visible(ev, fog):
			events.append(ev)
			_log_event(r["tick"], ev, fog)
	_draw_tick(events, fog)
	if _game.turn != turn_before:
		_log_header()
	if _game.is_over():
		_stop_run("")
	elif r["finished"]:
		var extra := " ".join(_game.notices)
		_stop_run(("Turn over. " + extra).strip_edges() if extra != "" else "Turn over. Plan the next one.")
	else:
		# Nobody left to act: race ahead to the next stop.
		_timer.wait_time = IDLE_SECONDS if r["idle"] else SPEEDS[_speed]
		_board.glide_seconds = _timer.wait_time
		_refresh_panel()


## Hand control back: the AI replans, the planner is rebuilt from the run.
func _stop_run(message: String) -> void:
	_running = false
	if _game.is_over() and not Session.in_campaign():  # a campaign mission plays its stinger on the debrief
		_sound.play("stinger_win" if _game.winner == _game.player_team else "stinger_loss")
	_timer.stop()
	_ctl.pause()
	_refresh()
	if message != "":
		_say(message, true, true)


func _toggle_overview() -> void:
	_overview = _map_btn.button_pressed
	_apply_layout()


func _toggle_mute() -> void:
	_sound.set_muted(not _sound.settings.muted)
	if not _sound.settings.muted:
		_sound.set_ambient(_game.theme)
		_sound.set_music(_current_act())
	_update_mute_label()


func _update_mute_label() -> void:
	_mute_btn.text = "Muted" if _sound.settings.muted else "Sound"


## Zoom that keeps a tile about TARGET_TILE_PX wide on a phone, however big the map is.
func _portrait_zoom(width: float, height: float) -> float:
	var g := _game.state.grid
	var fit := IsoProjection.new(g.width, g.height, Vector2(width, height))
	return maxf(1.0, TARGET_TILE_PX / (2.0 * fit.half_w))


## The act of the mission being played (1 for a skirmish), for the music.
func _current_act() -> int:
	if Session.in_campaign():
		return int(Session.campaign.mission_or_card(Session.mission_id).get("act", 1))
	return 1


func _cycle_speed() -> void:
	_speed = (_speed + 1) % SPEEDS.size()
	_timer.wait_time = SPEEDS[_speed]
	_board.glide_seconds = _timer.wait_time
	_speed_btn.text = SPEED_LABELS[_speed]


# --- input -------------------------------------------------------------------

func _on_tile_clicked(tile: Vector2i, button: int) -> void:
	if _running or _game.is_over():
		return
	if button == MOUSE_BUTTON_RIGHT:
		_ctl.deselect()
		_refresh()
	elif button == MOUSE_BUTTON_LEFT:
		var res := _ctl.tap_tile(tile) if _two_tap else _ctl.click_tile(tile)
		_say(res["msg"], res["ok"], res.get("preview", false))
		_refresh()


func _on_tile_hovered(tile: Vector2i) -> void:
	if not _running and not _two_tap:
		_hint.text = _ctl.hover_info(tile) if tile != BoardView.NO_TILE else ""


func _toggle_overwatch() -> void:
	if _ctl.selected < 0:
		_say("Select a merc first.", false)
		return
	_ctl.set_mode(PlayController.MODE_NORMAL if _ctl.mode == PlayController.MODE_OVERWATCH else PlayController.MODE_OVERWATCH)
	_say("Pick the overwatch direction on the board." if _ctl.mode == PlayController.MODE_OVERWATCH else "", true)
	_refresh()


## Move+Fire: pick a destination; the merc walks there and takes a shot if one
## comes up on the way. The shot's ticks are reserved (and paid) either way.
func _toggle_move_fire() -> void:
	if _ctl.selected < 0:
		_say("Select a merc first.", false)
		return
	var on := _ctl.mode != PlayController.MODE_MOVE_FIRE
	_ctl.set_mode(PlayController.MODE_MOVE_FIRE if on else PlayController.MODE_NORMAL)
	_say("Pick where to go: the merc fires if a shot comes up on the way. A shot's ticks are reserved either way." if on else "", true)
	_refresh()


func _undo() -> void:
	_ctl.undo()
	_refresh()


func _clear() -> void:
	_ctl.clear()
	_refresh()


func _open_replay_viewer() -> void:
	get_tree().change_scene_to_file("res://view/replay.tscn")


## Callsign in a campaign (HX-nn for a hollow); a bare id in a skirmish.
func _label_for(u: SimUnit) -> String:
	if not Session.in_campaign():
		return "u%d" % u.id
	if u.is_drone:
		return Campaign.designation(u.id)
	for m: Dictionary in Session.campaign.story["cast"]["mercs"]:
		if int(m["slot"]) == u.id:
			return m["callsign"]
	return "u%d" % u.id


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: _toggle_run()
		KEY_BACKSPACE: _undo()
		KEY_O: _toggle_overwatch()
		KEY_M: _toggle_move_fire()
		KEY_S: _cycle_speed()
		KEY_ESCAPE:
			_ctl.deselect()
			_refresh()
		KEY_N:
			if not Session.in_campaign():
				_new_match()
		KEY_V: _open_replay_viewer()
		KEY_T:
			_two_tap = not _two_tap
			_say("Two-tap commit %s." % ("on" if _two_tap else "off"), true)
		_:
			var ids := _ctl.builder.own_unit_ids()
			var n: int = event.keycode - KEY_1
			if not _running and n >= 0 and n < ids.size():
				_ctl.select(ids[n])
				_refresh()


# --- drawing -----------------------------------------------------------------

func _refresh() -> void:
	if not _running:
		_draw_planning()
	_refresh_panel()


func _draw_planning() -> void:
	var d := PlayOverlay.build(_ctl)
	_board.set_overlay(d["overlay"])
	_board.show_frame(_game.state, [], d["watchers"], d["fog"])


func _draw_tick(events: Array[Dictionary], fog: Dictionary) -> void:
	var watchers: Array[Dictionary] = []
	if _game.run != null:
		for w in _game.run.watchers():
			if (fog["units"] as Dictionary).has(w["id"]):
				watchers.append(w)
	_board.set_overlay({})
	_board.record_tracers(events, _game.state, fog)
	_sound.play_events(events)
	_board.show_frame(_game.state, events, watchers, fog)


func _refresh_panel() -> void:
	if _ctl == null:
		return
	var tick: int = _game.run.tick if _game.run != null else TICKS
	var campaign := Session.in_campaign()
	_new_btn.text = "Withdraw" if campaign else "New"
	_new_btn.disabled = campaign and _game.is_over()
	if _game.is_over():
		_title.text = "Mission over" if campaign else "Match over"
	else:
		_title.text = "%sTurn %d  %d/%d%s" % ["" if _portrait else _mission_prefix(), _game.turn, tick, TICKS, "  (running)" if _running else ""]
	if _game.is_over():
		_go_btn.text = "Continue"
	elif _running:
		_go_btn.text = "Running..."
	else:
		_go_btn.text = "Go"
	_go_btn.disabled = (_game.is_over() and not campaign) or _running
	for b in _action_buttons:
		if b != _go_btn:
			b.disabled = _running or _game.is_over()
	_overwatch_btn.button_pressed = _ctl.mode == PlayController.MODE_OVERWATCH
	_ms_btn.button_pressed = _ctl.mode == PlayController.MODE_MOVE_FIRE
	_update_timeline(tick)
	_goal_label.visible = _game.goal != null
	if _game.goal != null:
		_goal_label.text = "Goal: " + _game.goal.progress_text()
		_board.set_zones(_game.goal.zone_marks())
	_banner.visible = _game.is_over()
	if _banner.visible:
		_banner.text = "VICTORY" if _game.winner == _game.player_team else ("DRAW" if _game.winner == SimMatch.DRAW else "DEFEAT")
	_rebuild_squad()


## The selected merc's schedule across the round (or everyone's idle bar).
func _update_timeline(tick: int) -> void:
	var sel := _ctl.selected
	var segments: Array = _ctl.builder.timeline(sel) if sel >= 0 else []
	var committed := tick
	if sel >= 0 and _game.run != null:
		committed = _game.run.free_at(sel)
	_timeline.set_data(segments, tick, TICKS, committed)


func _rebuild_squad() -> void:
	for child in _squad.get_children():
		child.queue_free()
	var b := _ctl.builder
	for id in b.own_unit_ids():
		var u: SimUnit = _game.state.units[id]
		var orders := b.entries_for(id).map(func(e: Dictionary) -> String: return String(e["kind"]).replace("move_fire", "move+fire"))
		var btn := Button.new()
		btn.text = _squad_text(u, b, orders)
		btn.toggle_mode = true
		btn.button_pressed = id == _ctl.selected
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 84 if _portrait else 0)
		btn.disabled = _running or _game.is_over()
		btn.pressed.connect(func(): _ctl.select(id); _refresh())
		_squad.add_child(btn)


## Display name for any unit id: callsigns for mercs and Writ officers.
func _name_of(id: int) -> String:
	if not Session.in_campaign():
		return "u%d" % id
	var u: SimUnit = _game.state.units.get(id)
	if id == Campaign.PROVOST_ID:
		return "Orrick"
	if id >= Campaign.FIRST_TIER_ID:
		return Session.campaign.enemy_label(id)
	if id > Campaign.WRIT_ID_BASE:
		for o: Dictionary in Session.campaign.story["writ"]["officers"]:
			if Campaign.WRIT_ID_BASE + int(o["slot"]) == id:
				return o["callsign"] if u == null or not u.is_drone else "%s (hollow)" % o["callsign"]
	return _label_for(u) if u != null else "u%d" % id


func _mission_prefix() -> String:
	if not Session.in_campaign():
		return ""
	var m := Session.campaign.mission_or_card(Session.mission_id)
	return "%s: " % m.get("name", "") if not m.is_empty() else ""


func _squad_text(u: SimUnit, b: PlanBuilder, orders: Array) -> String:
	var left := "%d ticks left" % maxi(b.ticks_left(u.id), 0)
	var hp := "#".repeat(maxi(u.hp, 0))
	var plan := ", ".join(orders)
	if _portrait:
		return "%s  %s\n%s\n%s" % [_label_for(u), hp, left, plan if plan != "" else "-"]
	return "%s   HP %s   %s   %s" % [_label_for(u), hp, left, plan]


func _say(text: String, ok: bool, preview: bool = false) -> void:
	_msg.text = text
	_msg.add_theme_color_override("font_color", COL_NEUTRAL if preview else (COL_OK if ok else COL_BAD))


## The log accumulates across the run: only what the player's side saw.
func _log_header() -> void:
	_log.append_text("[color=#ffd479]-- Turn %d --[/color]\n" % _game.turn)


func _log_event(tick: int, ev: Dictionary, fog: Dictionary) -> void:
	_log.append_text("[color=#8a93a0]t%d[/color]  %s\n" % [tick, ReplayModel.describe(ev, fog, _name_of).replace("[", "[lb]")])


# --- scripted capture (testing) ---------------------------------------------

func _run_script(script: String) -> void:
	for raw in script.split(";"):
		var parts := raw.strip_edges().split(" ", false, 1)
		if parts.is_empty():
			continue
		var arg := parts[1] if parts.size() > 1 else ""
		match parts[0]:
			"click", "tap":
				var xy := arg.split(",")
				_on_tile_clicked(Vector2i(int(xy[0]), int(xy[1])), MOUSE_BUTTON_LEFT)
			"right": _on_tile_clicked(Vector2i.ZERO, MOUSE_BUTTON_RIGHT)
			"ow": _toggle_overwatch()
			"mf": _toggle_move_fire()
			"undo": _undo()
			"go": _toggle_run()
			"step":
				for i in int(arg):
					if _running:
						_do_tick()
			"confirm":
				if _ctl.confirm() == null:
					_say(_game.last_error, false)
				_refresh()
			"hover": _on_tile_hovered(Vector2i(int(arg.split(",")[0]), int(arg.split(",")[1])))


## Screenshot/testing hook: start straight in a campaign mission.
func _demo_campaign(mission_id: String) -> void:
	var story: Dictionary = StoryData.load_dir("res://data/story")["data"]
	Session.reset()
	Session.campaign = Campaign.new_game(story)
	var m: Dictionary = Session.campaign.mission_or_card(mission_id)
	var slots: Array = Session.campaign.available_slots().slice(0, int(m["squad_size"]))
	Session.mission_id = mission_id
	Session.current_match = MissionBuilder.build(Session.campaign, mission_id, slots)


func _capture_and_quit(path: String) -> void:
	for i in 3:
		await get_tree().process_frame
	var err := get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit(0 if err == OK else 1)
