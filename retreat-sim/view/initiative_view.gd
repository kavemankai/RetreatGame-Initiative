class_name InitiativeView
extends Control
## The initiative ruleset on screen (see InitiativeMatch). You act live, one merc at a time:
## tap a merc, tap a tile (twice to confirm) to move, tap an enemy (twice) to shoot. Press
## End Turn and the enemy's turn plays back beat by beat; interrupts show as the shots they are.
##
## Scripted capture: godot --path . res://view/initiative.tscn -- --campaign=karsa_breakout \
##   --do="sel 1;move 3,9;end" --shot=out.png    (--do commands: sel ID | move X,Y | shoot ID | watch | end)

const SANDBOX_SCENE := "res://view/sandbox.tscn"
const MENU_SCENE := "res://view/campaign.tscn"
const MARGIN := 10
const BEAT_SECONDS := 0.28
const PORTRAIT_BOARD_ASPECT := 0.8
const TARGET_TILE_PX := 84.0
const FONT_PORTRAIT := 18
const FONT_LANDSCAPE := 16
const NO_TILE := Vector2i(-1, -1)
const COL_NEUTRAL := Color("d8dee9")
const COL_OK := Color("9be39b")
const COL_BAD := Color("ff9a8a")
const PATH_COLOR := Color("8fd0ff")
const EXPOSED_COLOR := Color("ff7a6a")

var _im: InitiativeMatch
var _sel := -1
var _pending := NO_TILE        # a first tap on a tile or an enemy, waiting to be confirmed
var _pending_is_shot := false
var _route_note := ""
var _queue: Array[Dictionary] = []  # beats still to play back
var _busy := false
var _overview := false
var _activation := false      # the activation engine (ActivationMatch) rather than live-AP turns
var _last_round := 0
var _resumed := false          # this battle was restored from the autosave
var _portrait := false

var _board: BoardView
var _main: BoxContainer
var _panel: VBoxContainer
var _title: Label
var _goal_label: Label
var _banner: Label
var _squad: BoxContainer
var _strip: InitiativeStrip
var _hint: Label
var _msg: Label
var _log: RichTextLabel
var _end_btn: Button
var _watch_btn: Button
var _map_btn: Button
var _mute_btn: Button
var _leave_btn: Button
var _withdraw_armed := false   # a first tap on Withdraw, waiting for the confirming second tap
var _sound: SoundBoard
var _timer: Timer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var args := _parse_args()
	if args.has("sandbox") and Session.current_match == null:
		_demo_sandbox()
	elif args.has("campaign") and Session.current_match == null:
		_demo_campaign(String(args["campaign"]), args.has("live"))
	if args.has("ruleset"):
		Session.ruleset = String(args["ruleset"])
	if args.has("resume") and Session.current_match == null:
		ResumeStore.enter_session(StoryData.load_dir("res://data/story")["data"])
	if Session.current_match == null:
		get_tree().change_scene_to_file("res://view/campaign.tscn")
		return
	_activation = Session.ruleset == "activation"
	var opening: Array[Dictionary] = []
	if _activation and Session.resume_cs != null:
		var restored := ActivationMatch.new(Session.resume_cs)
		Session.resume_cs = null
		restored.resume()
		_im = restored
		_resumed = true
		opening = restored.opening_beats
	elif _activation:
		var am := ActivationMatch.make(Session.current_match)
		if Session.sandbox:
			am.cs.config.max_ap = Sandbox.ap_of(Session.sandbox_cfg)
		_im = am
		_im.start()
		opening = am.opening_beats
	else:
		_im = InitiativeMatch.from_match(Session.current_match)
		_im.start()
	_build_ui()
	resized.connect(_apply_layout)
	_apply_layout()
	_board.set_level_theme(_im.theme)
	_sound.set_ambient(_im.theme)
	_sound.set_music(_act())
	if _resumed:
		_log_line("[color=#ffd479]Battle resumed at round %d.[/color]" % _im.turn)
	else:
		_log_line("[color=#ffd479]%s[/color]" % ("Round 1." if _activation else "Turn 1: your move."))
	_last_round = _im.turn
	_select_active()
	_refresh()
	_autosave()
	if not opening.is_empty():
		_play(opening, true)
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


func _demo_campaign(mission_id: String, live := false) -> void:
	var story: Dictionary = StoryData.load_dir("res://data/story")["data"]
	Session.reset()
	Session.campaign = Campaign.new_game(story)
	var m: Dictionary = Session.campaign.mission_or_card(mission_id)
	var slots: Array = Session.campaign.available_slots().slice(0, int(m["squad_size"]))
	Session.mission_id = mission_id
	Session.level_test = not live  # --live plays it as a real campaign mission (outcome goes to the campaign)
	Session.current_match = MissionBuilder.build(Session.campaign, mission_id, slots)


func _demo_sandbox() -> void:
	var story: Dictionary = StoryData.load_dir("res://data/story")["data"]
	var cfg := Sandbox.default_config(story)
	Session.reset()
	Session.sandbox_cfg = cfg
	Session.sandbox = true
	Session.level_test = true
	Session.campaign = Campaign.new_game(story)
	Session.mission_id = Sandbox.MAP
	Session.current_match = Sandbox.build(story, cfg)


func _act() -> int:
	if Session.in_campaign():
		return int(Session.campaign.mission_or_card(Session.mission_id).get("act", 1))
	return 1


# --- layout ----------------------------------------------------------------------------

func _build_ui() -> void:
	theme = Theme.new()
	_sound = SoundBoard.new()
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
	_main.add_child(_board)
	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 8)
	_main.add_child(_panel)

	var top := HBoxContainer.new()
	_panel.add_child(top)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	top.add_child(_title)
	_map_btn = _small_button("Map", _toggle_overview)
	_map_btn.toggle_mode = true
	top.add_child(_map_btn)
	_mute_btn = _small_button("", _toggle_mute)
	top.add_child(_mute_btn)
	_leave_btn = _small_button("Withdraw" if _is_campaign_mission() else "Leave", _leave)
	_leave_btn.custom_minimum_size = Vector2(88, 40)
	top.add_child(_leave_btn)
	_update_mute_label()

	_goal_label = Label.new()
	_goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_goal_label.add_theme_color_override("font_color", Color("ffd479"))
	_panel.add_child(_goal_label)
	_banner = Label.new()
	_banner.add_theme_font_size_override("font_size", 26)
	_banner.visible = false
	_panel.add_child(_banner)

	_strip = InitiativeStrip.new()
	_strip.visible = false
	_panel.add_child(_strip)
	_squad = BoxContainer.new()
	_panel.add_child(_squad)
	var tools := HBoxContainer.new()
	_panel.add_child(tools)
	_watch_btn = Button.new()
	_watch_btn.text = "Overwatch (%d AP)" % CombatConfig.load_file().overwatch_cost if _activation else "Overwatch (all AP)"
	_watch_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_watch_btn.focus_mode = Control.FOCUS_NONE
	_watch_btn.pressed.connect(_on_watch)
	tools.add_child(_watch_btn)

	_hint = Label.new()
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override("font_color", COL_NEUTRAL)
	_panel.add_child(_hint)
	_msg = Label.new()
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_msg)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size = Vector2(0, 60)
	_panel.add_child(_log)
	_end_btn = Button.new()
	_end_btn.text = "End Activation" if _activation else "End Turn"
	_end_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_end_btn.focus_mode = Control.FOCUS_NONE
	_end_btn.pressed.connect(_on_end_turn)
	_panel.add_child(_end_btn)

	_timer = Timer.new()
	_timer.wait_time = BEAT_SECONDS
	_timer.timeout.connect(_play_next_beat)
	add_child(_timer)


func _small_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(58, 40)
	b.pressed.connect(action)
	return b


func _apply_layout() -> void:
	if _board == null or _im == null:
		return
	_portrait = size.y > size.x
	_main.vertical = _portrait
	theme.default_font_size = FONT_PORTRAIT if _portrait else FONT_LANDSCAPE
	_squad.vertical = not _portrait
	if _portrait:
		var board_w := size.x - 2.0 * MARGIN
		_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_board.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_board.custom_minimum_size = Vector2(0, board_w * PORTRAIT_BOARD_ASPECT)
		_board.set_zoom(1.0 if _overview else _portrait_zoom(board_w, board_w * PORTRAIT_BOARD_ASPECT))
		_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_panel.custom_minimum_size = Vector2.ZERO
	else:
		_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_board.custom_minimum_size = Vector2(480, 360)
		_board.set_zoom(1.0)
		_panel.custom_minimum_size = Vector2(380, 0)


func _portrait_zoom(width: float, height: float) -> float:
	var g := _im.state.grid
	var fit := IsoProjection.new(g.width, g.height, Vector2(width, height))
	return maxf(1.0, TARGET_TILE_PX / (2.0 * fit.half_w))


func _toggle_overview() -> void:
	_overview = _map_btn.button_pressed
	_apply_layout()


func _toggle_mute() -> void:
	_sound.set_muted(not _sound.settings.muted)
	if not _sound.settings.muted:
		_sound.set_ambient(_im.theme)
		_sound.set_music(_act())
	_update_mute_label()


func _update_mute_label() -> void:
	_mute_btn.text = "Muted" if _sound.settings.muted else "Sound"


## A real campaign mission (not the level test or the sandbox): it ends by handing an outcome to the campaign.
func _is_campaign_mission() -> bool:
	return Session.campaign != null and Session.current_match != null and not Session.level_test


func _leave() -> void:
	if _is_campaign_mission() and not _im.is_over():
		if not _withdraw_armed:
			_withdraw_armed = true
			_leave_btn.text = "Sure?"
			_say("Tap Withdraw again to leave the field: the mission counts as failed and the survivors keep their lives.", false)
			return
		_finish_campaign_mission(true)
		return
	_timer.stop()
	var back := SANDBOX_SCENE if Session.sandbox else MENU_SCENE
	Session.reset()
	get_tree().change_scene_to_file(back)


## Hands the finished (or abandoned) mission to the campaign screen, which applies it exactly once.
func _finish_campaign_mission(withdrawn: bool) -> void:
	_timer.stop()
	if _activation:
		Session.pending_outcome = MissionBuilder.outcome_for(Session.campaign, (_im as ActivationMatch).cs, withdrawn)
	else:
		Session.pending_outcome = MissionBuilder.outcome_of(Session.campaign, _im.state, _im.player_team, _im.goal, _im.is_over() and _im.winner == _im.player_team, withdrawn)
	Session.withdrawn = withdrawn
	ResumeStore.clear()
	get_tree().change_scene_to_file("res://view/campaign.tscn")


# --- naming and logging ----------------------------------------------------------------

func _name_of(id: int) -> String:
	var u: SimUnit = _im.state.units.get(id)
	if u == null:
		return "u%d" % id
	if u.team != _im.player_team:
		return Session.campaign.enemy_label(id) if Session.in_campaign() else "Enemy %d" % id
	if u.is_drone:
		return Campaign.designation(id)
	if Session.in_campaign():
		for m: Dictionary in Session.campaign.story["cast"]["mercs"]:
			if int(m["slot"]) == id:
				return m["callsign"]
	return "u%d" % id


func _log_line(bb: String) -> void:
	_log.append_text(bb + "\n")


func _say(text: String, ok: bool = true, neutral: bool = false) -> void:
	_msg.text = text
	_msg.add_theme_color_override("font_color", COL_NEUTRAL if neutral else (COL_OK if ok else COL_BAD))


## The one autosave slot (see ResumeStore): after every command and when the app is paused.
## Activation-engine battles are saved (campaign missions, the level test and the sandbox); a finished fight clears it.
func _autosave() -> void:
	if _activation and Session.campaign != null and _im != null:
		var kind := ResumeStore.KIND_SANDBOX if Session.sandbox else (ResumeStore.KIND_CAMPAIGN if _is_campaign_mission() else ResumeStore.KIND_LEVEL_TEST)
		ResumeStore.save((_im as ActivationMatch).cs, {"kind": kind, "mission_id": Session.mission_id})


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_autosave()


## A short label for the initiative strip.
func _short_name(id: int) -> String:
	return _name_of(id).left(5)


func _describe(ev: Dictionary, fog: Dictionary) -> String:
	return ReplayModel.describe(ev, fog, _name_of).replace("[", "[lb]")


# --- input -------------------------------------------------------------------------------

func _on_tile_clicked(tile: Vector2i, button: int) -> void:
	if _busy or _im.is_over() or _im.active_team != _im.player_team:
		return
	if button == MOUSE_BUTTON_RIGHT:
		_clear_pending()
		_refresh()
		return
	var visible := SimVision.visible_unit_ids(_im.state, _im.player_team)
	var u: SimUnit = _im.state.unit_at(tile)
	if u != null and u.team == _im.player_team:
		_sel = u.id
		_clear_pending()
		_refresh()
		return
	if _sel < 0 or not _im.can_act(_sel):
		_say(_not_acting_text(), false)
		return
	if u != null and u.team != _im.player_team and visible.has(u.id):
		_tap_target(u)
		return
	_tap_tile(tile)


func _tap_target(enemy: SimUnit) -> void:
	var pv := _im.shot_preview(_sel, enemy.id)
	if pv["result"] == "invalid":
		_say("No shot: " + CombatReasons.text(String(pv["reason"])), false)
		return
	if _pending == enemy.pos and _pending_is_shot:
		_clear_pending()
		_play(_im.shoot(_sel, enemy.id))
		return
	_pending = enemy.pos
	_pending_is_shot = true
	var cost := int(pv["cost"])
	var left := _im.ap_of(_sel) - cost
	var range_ := SimLos.chebyshev(_im.state.units[_sel].pos, enemy.pos)
	if pv["result"] == "blocked":
		_say("%s: blocked by cover, range %d, %d AP (%d left). Tap again to fire anyway." % [_name_of(enemy.id), range_, cost, left], true, true)
	elif _im.ap_of(_sel) < cost:
		_say("Not enough AP: %d needed, %d left." % [cost, _im.ap_of(_sel)], false)
		_clear_pending()
	elif _im.is_suppressed(_sel):
		_say("Shaken: it cannot shoot this turn.", false)
		_clear_pending()
	else:
		_say("%s: %d%% to hit, %d damage, range %d, %d AP (%d left). Tap again to fire." % [_name_of(enemy.id), pv["chance"], pv["damage"], range_, cost, left], true, true)
	_refresh(false)


func _tap_tile(tile: Vector2i) -> void:
	var reach := _im.reach(_sel)
	if not reach.has(tile) or tile == _im.state.units[_sel].pos:
		_say(CombatReasons.text("unreachable"), false)
		_clear_pending()
		_refresh(false)
		return
	if _pending == tile and not _pending_is_shot:
		_clear_pending()
		_play(_im.move(_sel, tile))
		return
	_pending = tile
	_pending_is_shot = false
	_route_note = ""
	_refresh(false)
	_say("Move: %d AP (of %d).%s Tap again to go." % [reach[tile], _im.ap_of(_sel), _route_note], false, _route_note == "")


## Why the selected merc cannot be commanded right now.
func _not_acting_text() -> String:
	if _activation and _sel >= 0 and _im.state.units.has(_sel) and _im.state.units[_sel].alive:
		var acting: int = (_im as ActivationMatch).active_unit()
		var who := " %s acts now." % _name_of(acting) if acting >= 0 else ""
		return CombatReasons.text("not_your_activation") + who
	return "Select one of your mercs first."


## In the activation engine the merc whose activation it is is selected for you.
func _select_active() -> void:
	if not _activation or _im.is_over():
		return
	var acting: int = (_im as ActivationMatch).active_unit()
	var u: SimUnit = _im.state.units.get(acting)
	if u != null and u.team == _im.player_team:
		_sel = acting
		_clear_pending()


func _clear_pending() -> void:
	_pending = NO_TILE
	_pending_is_shot = false


func _on_watch() -> void:
	if _busy or _sel < 0 or not _im.can_act(_sel):
		return
	var u: SimUnit = _im.state.units[_sel]
	var dir := Vector2i.RIGHT
	var best := 1 << 20
	for id in SimVision.visible_unit_ids(_im.state, _im.player_team):
		var e: SimUnit = _im.state.units[id]
		if e.team != _im.player_team and SimLos.chebyshev(u.pos, e.pos) < best:
			best = SimLos.chebyshev(u.pos, e.pos)
			dir = Vector2i(signi(e.pos.x - u.pos.x), signi(e.pos.y - u.pos.y))
	if best == 1 << 20:  # nobody in view: watch toward the far side of the map
		dir = Vector2i(1 if u.pos.x < _im.state.grid.width / 2 else -1, 0)
	_clear_pending()
	var beats := _im.hold_watch(_sel, dir)
	if beats.is_empty():
		_say(CombatReasons.text((_im as ActivationMatch).last_reason) if _activation else "It cannot hold a watch now.", false)
		return
	_say("%s holds overwatch." % _name_of(_sel), true, true)
	_play(beats)


func _on_end_turn() -> void:
	if _busy or _im.is_over():
		return
	_clear_pending()
	if _activation:
		_log_line("[color=#8a93a0]-- %s ends its activation --[/color]" % _name_of((_im as ActivationMatch).active_unit()))
		_say("", true, true)
	else:
		_log_line("[color=#8a93a0]-- enemy turn --[/color]")
		_say("Enemy turn...", true, true)
	_play(_im.end_turn(), true)


# --- playback ------------------------------------------------------------------------------

var _ends_turn := false
var _enemy_events := 0  # enemy moves/shots in the beats being played
var _enemy_seen := 0    # how many of those the squad could actually see


func _play(beats: Array[Dictionary], ends_turn: bool = false) -> void:
	_autosave()  # the command has already been applied to the state
	_enemy_events = 0
	_enemy_seen = 0
	for b in beats:
		_enemy_events += _enemy_event_count(b["events"], b["state"])
	_queue = beats.duplicate()
	_ends_turn = ends_turn
	_busy = true
	_set_controls(false)
	if _queue.is_empty():
		_finish_playback()
		return
	_play_next_beat()
	_timer.start()


func _fog_for(state: SimState) -> Dictionary:
	var units := {}
	for id in SimVision.visible_unit_ids(state, _im.player_team):
		units[id] = true
	return {"tiles": SimVision.visible_tiles(state, _im.player_team), "units": units}


func _play_next_beat() -> void:
	if _queue.is_empty():
		_timer.stop()
		_finish_playback()
		return
	var beat: Dictionary = _queue.pop_front()
	var state: SimState = beat["state"]
	var fog := _fog_for(state)
	var shown: Array[Dictionary] = []
	_enemy_seen += _enemy_event_count(_visible_events(beat["events"], fog), state)
	for ev: Dictionary in beat["events"]:
		if ev["type"] in ["watch"] or ReplayModel.event_visible(ev, fog):
			shown.append(ev)
			if ev["type"] != "watch":
				_log_line("[color=#8a93a0]%s[/color]" % _describe(ev, fog))
	_board.set_overlay({})
	_board.show_frame(state, shown, [], fog)
	_board.record_tracers(shown, state, fog)
	_sound.play_events(shown)


## Events caused by enemy units (their moves and shots), counted without revealing where.
func _enemy_event_count(events: Array, state: SimState) -> int:
	var n := 0
	for ev: Dictionary in events:
		var u: SimUnit = state.units.get(int(ev.get("unit", -1)))
		if u != null and u.team != _im.player_team and ev["type"] in ["move", "shot", "watch"]:
			n += 1
	return n


func _visible_events(events: Array, fog: Dictionary) -> Array:
	return events.filter(func(ev: Dictionary) -> bool: return ev["type"] == "watch" or ReplayModel.event_visible(ev, fog))


func _finish_playback() -> void:
	if _activation and _enemy_events > 0 and _enemy_seen == 0:
		_log_line("[color=#8a93a0]The enemy acts out of sight.[/color]")
	_busy = false
	_set_controls(true)
	if _ends_turn and not _im.is_over():
		var extra := " ".join(_im.notices)
		if _activation:
			if _im.turn != _last_round:
				_log_line("[color=#ffd479]Round %d.[/color] %s" % [_im.turn, extra])
			_say(("%s acts. %s" % [_name_of((_im as ActivationMatch).active_unit()), extra]).strip_edges(), true, true)
		else:
			_log_line("[color=#ffd479]Turn %d: your move.[/color] %s" % [_im.turn, extra])
			_say(("Your move. " + extra).strip_edges(), true, true)
		_board.clear_tracers()
	_ends_turn = false
	_last_round = _im.turn
	_select_active()
	if _sel >= 0 and (not _im.state.units.has(_sel) or not _im.state.units[_sel].alive):
		_sel = -1
	_refresh()


func _set_controls(on: bool) -> void:
	_end_btn.disabled = not on or _im.is_over()
	_watch_btn.disabled = not on or _im.is_over()


# --- drawing ----------------------------------------------------------------------------------

func _refresh(redraw_board: bool = true) -> void:
	if _im == null or _busy:
		return
	var state := _im.state
	var fog := _fog_for(state)
	var overlay := {"selected": _sel, "paths": [], "shots": [], "reachable": {}, "pending": NO_TILE, "marks": [], "ghosts": []}
	if _sel >= 0 and _im.can_act(_sel):
		overlay["reachable"] = _im.reach(_sel)
		if _pending != NO_TILE and not _pending_is_shot:
			_add_route(overlay, _im.route_preview(_sel, _pending))
		if _pending != NO_TILE and _pending_is_shot:
			overlay["shots"].append({"from": state.units[_sel].pos, "to": _pending, "color": PlayOverlay.COL_FIRE})
			overlay["marks"].append({"tile": _pending, "text": _shot_mark(state), "lane": 0, "color": PlayOverlay.COL_FIRE})
		overlay["pending"] = _pending
	_board.set_overlay(overlay)
	_board.show_frame(state, [], _watch_cones(), fog)
	if _im.goal != null:
		_goal_label.text = "Goal: " + _im.goal.progress_text()
		_board.set_zones(_im.goal.zone_marks())
	else:
		_goal_label.text = ""
	_goal_label.visible = _goal_label.text != ""
	if _activation:
		var am := _im as ActivationMatch
		var acting := am.active_unit()
		_title.text = "Round %d" % _im.turn if acting < 0 else "Round %d  %s" % [_im.turn, _name_of(acting)]
		_strip.visible = not _im.is_over()
		if _strip.visible:
			_strip.show_order(_im.turn, am.strip(), _im.player_team, _short_name)
	else:
		_title.text = "Turn %d  %s" % [_im.turn, "your move" if _im.active_team == _im.player_team else "enemy"]
	_banner.visible = _im.is_over()
	if _im.is_over():
		ResumeStore.clear()
		_banner.text = "VICTORY" if _im.winner == _im.player_team else ("DRAW" if _im.winner == SimMatch.DRAW else "DEFEAT")
		_end_btn.text = "Continue"
		_end_btn.disabled = false
		if _end_btn.pressed.is_connected(_on_end_turn):
			_end_btn.pressed.disconnect(_on_end_turn)
			_end_btn.pressed.connect(_finish_campaign_mission.bind(false) if _is_campaign_mission() else _leave)
		_sound.play("stinger_win" if _im.winner == _im.player_team else "stinger_loss")
	_rebuild_squad()
	_hint.text = _hint_text()


## The shot summary drawn on the targeted tile: chance, damage and AP (or cover).
func _shot_mark(state: SimState) -> String:
	var target: SimUnit = state.unit_at(_pending)
	if target == null:
		return ""
	var pv := _im.shot_preview(_sel, target.id)
	if pv["result"] == "hit":
		return "%d%% | %d dmg | %d AP" % [pv["chance"], pv["damage"], pv["cost"]]
	return "COVER | %d AP" % int(pv.get("cost", 0))


## The route to the pending tile: blue where safe, red on steps where a visible enemy would
## shoot first, with the running AP cost at the end and a "!" on each exposed step.
func _add_route(overlay: Dictionary, route: Array[Dictionary]) -> void:
	if route.is_empty():
		return
	var prev: Vector2i = _im.state.units[_sel].pos
	var exposed := 0
	for step: Dictionary in route:
		var hot: bool = not (step["threats"] as Array).is_empty()
		overlay["paths"].append({"tiles": [prev, step["tile"]], "color": EXPOSED_COLOR if hot else PATH_COLOR, "dashed": true})
		if hot:
			exposed += 1
			overlay["marks"].append({"tile": step["tile"], "text": "! %d" % step["cost"], "lane": 0, "color": EXPOSED_COLOR})
		prev = step["tile"]
	var last: Dictionary = route[route.size() - 1]
	if (last["threats"] as Array).is_empty():
		overlay["marks"].append({"tile": last["tile"], "text": "%d AP" % last["cost"], "lane": 0})
	_route_note = "" if exposed == 0 else " %d step%s in enemy sight: they shoot first." % [exposed, "" if exposed == 1 else "s"]


## Overwatch cones of units the player can see (their own and visible enemies').
func _watch_cones() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var visible := SimVision.visible_unit_ids(_im.state, _im.player_team)
	for id in _im.watch:
		var u: SimUnit = _im.state.units.get(id)
		if u != null and u.alive and visible.has(id):
			out.append({"id": id, "dir": _im.watch[id], "spent": false, "pos": u.pos})
	return out


func _rebuild_squad() -> void:
	for child in _squad.get_children():
		_squad.remove_child(child)
		child.queue_free()
	for id in _im.state.units:
		var u: SimUnit = _im.state.units[id]
		if not u.alive or u.team != _im.player_team:
			continue
		var b := Button.new()
		var tag := ""
		if _im.is_broken(id):
			tag = " (down)"
		elif _im.is_suppressed(id):
			tag = " (no fire)"
		if _activation and tag == "" and id != (_im as ActivationMatch).active_unit():
			tag = " (waits)"
		b.text = "%s\n%d AP%s" % [_name_of(id), _im.ap_of(id), tag]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_pressed = id == _sel
		b.custom_minimum_size = Vector2(0, 56 if _portrait else 0)
		b.pressed.connect(_select.bind(id))
		_squad.add_child(b)


func _select(id: int) -> void:
	if _busy:
		return
	_sel = id
	_clear_pending()
	_refresh()


func _hint_text() -> String:
	if _im.is_over():
		return ""
	if _activation:
		if _sel < 0 or not _im.can_act(_sel):
			return "Units act one at a time in the order shown above. Tap a tile to move or an enemy to shoot, then End Activation."
		return "%s: %d AP. Move 2 per step (3 diagonal), shoot 4, overwatch 4 (one free shot at the first enemy to move in its cone). End Activation to pass." % [_name_of(_sel), _im.ap_of(_sel)]
	if _sel < 0:
		return "Tap a merc, then a tile to move or an enemy to shoot. Waiting units get one interrupt shot at anyone who steps into their sights first."
	return "%s: %d AP. Move 2 per step (3 diagonal), shoot 4." % [_name_of(_sel), _im.ap_of(_sel)]


# --- scripted capture ---------------------------------------------------------------------------

func _run_script(script: String) -> void:
	for raw in script.split(";"):
		var parts := raw.strip_edges().split(" ", false, 1)
		if parts.is_empty():
			continue
		var arg := parts[1] if parts.size() > 1 else ""
		match parts[0]:
			"sel":
				_select(int(arg))
			"preview":
				var pv := arg.split(",")
				_on_tile_clicked(Vector2i(int(pv[0]), int(pv[1])), MOUSE_BUTTON_LEFT)
			"move":
				var xy := arg.split(",")
				var tile := Vector2i(int(xy[0]), int(xy[1]))
				_on_tile_clicked(tile, MOUSE_BUTTON_LEFT)
				_on_tile_clicked(tile, MOUSE_BUTTON_LEFT)
				_drain()
			"shoot":
				var e: SimUnit = _im.state.units.get(int(arg))
				if e != null:
					_on_tile_clicked(e.pos, MOUSE_BUTTON_LEFT)
					_on_tile_clicked(e.pos, MOUSE_BUTTON_LEFT)
					_drain()
			"watch":
				_on_watch()
				_drain()
			"end":
				_on_end_turn()
				_drain()
			"withdraw":
				_leave()


## Plays every queued beat at once (scripts and screenshots do not wait on timers).
func _drain() -> void:
	while _busy:
		_timer.stop()
		_play_next_beat()


func _capture_and_quit(path: String) -> void:
	for i in 3:
		await get_tree().process_frame
	var err := get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit(0 if err == OK else 1)
