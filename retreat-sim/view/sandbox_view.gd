class_name SandboxView
extends Control
## Sandbox setup: set the four mercs' stats and gear, place the enemies on the open test map
## (tap a tile to place the chosen enemy, tap one to remove it), then start in either ruleset.
##
## Capture: godot --path . res://view/sandbox.tscn -- --tab=enemies --shot=out.png

const MARGIN := 10
const PORTRAIT_BOARD_ASPECT := 0.8
const FONT_PORTRAIT := 18
const FONT_LANDSCAPE := 16
const COL_OK := Color("9be39b")
const COL_BAD := Color("ff9a8a")
const COL_NEUTRAL := Color("d8dee9")
const INITIATIVE_SCENE := "res://view/initiative.tscn"
const PLAY_SCENE := "res://view/play.tscn"
const MENU_SCENE := "res://view/campaign.tscn"
const RULESET_LABEL := {
	"activation": "Ruleset: Activation (one unit at a time)",
	"initiative": "Ruleset: Initiative (live, AP)",
	"planned": "Ruleset: Planned (simultaneous)",
}
const GEAR_LABEL := {"armour": "Armour", "weapon": "Weapon", "mod": "Mod"}

var _story: Dictionary
var _map: MapData
var _cfg: Dictionary
var _tab := "squad"
var _moving := -1  # a merc picked on the board, waiting for a tile
var _kinds: Array[Dictionary] = []
var _kind_idx := 0
var _hollow := false
var _role_idx := 0
var _portrait := true

var _board: BoardView
var _main: BoxContainer
var _panel: VBoxContainer
var _content: VBoxContainer
var _msg: Label
var _tab_btns: Dictionary = {}
var _ruleset_btn: Button
var _ap_btn: Button
var _stat_labels: Dictionary = {}  # "index:key" -> Label
var _gear_notes: Dictionary = {}   # "index:slot" -> Label
var _sound: SoundBoard


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_story = StoryData.load_dir("res://data/story")["data"]
	_map = MapData.load_file(Sandbox.MAP)
	_kinds = Sandbox.enemy_kinds(_story)
	_cfg = Session.sandbox_cfg if not Session.sandbox_cfg.is_empty() else Sandbox.default_config(_story)
	var args := _parse_args()
	_tab = String(args.get("tab", "squad"))
	_build_ui()
	resized.connect(_apply_layout)
	_apply_layout()
	_show_tab(_tab)
	if args.has("shot"):
		_capture_and_quit(String(args["shot"]))


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out


# --- layout ---------------------------------------------------------------------------------

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
	_board.set_level_theme(_map.theme)
	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 6)
	_main.add_child(_panel)

	var top := HBoxContainer.new()
	_panel.add_child(top)
	var title := Label.new()
	title.text = "Sandbox: the proving ground"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	top.add_child(title)
	top.add_child(_button("Menu", _back, Vector2(70, 40)))

	var tabs := HBoxContainer.new()
	_panel.add_child(tabs)
	for t in ["squad", "enemies"]:
		var b := _button("Squad" if t == "squad" else "Enemies", _show_tab.bind(t), Vector2(0, 44))
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(b)
		_tab_btns[t] = b

	_msg = Label.new()
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.add_theme_color_override("font_color", COL_NEUTRAL)
	_panel.add_child(_msg)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	scroll.add_child(_content)

	_ap_btn = _button("", _cycle_ap, Vector2(0, 44))
	_panel.add_child(_ap_btn)
	_update_ap_label()
	_ruleset_btn = _button("", _toggle_ruleset, Vector2(0, 44))
	_panel.add_child(_ruleset_btn)
	_panel.add_child(_button("Start", _start, Vector2(0, 56)))


func _button(text: String, action: Callable, min_size: Vector2 = Vector2(48, 40)) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = min_size
	b.pressed.connect(action)
	return b


func _apply_layout() -> void:
	if _board == null:
		return
	_portrait = size.y > size.x
	_main.vertical = _portrait
	theme.default_font_size = FONT_PORTRAIT if _portrait else FONT_LANDSCAPE
	if _portrait:
		var w := size.x - 2.0 * MARGIN
		_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_board.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		_board.custom_minimum_size = Vector2(0, w * PORTRAIT_BOARD_ASPECT)
		_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_panel.custom_minimum_size = Vector2.ZERO
	else:
		_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_board.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_board.custom_minimum_size = Vector2(480, 360)
		_panel.custom_minimum_size = Vector2(400, 0)
	_board.set_zoom(1.0)


func _say(text: String, ok: bool = true) -> void:
	_msg.text = text
	_msg.add_theme_color_override("font_color", COL_OK if ok else COL_BAD)


func _callsign(slot: int) -> String:
	for m: Dictionary in _story["cast"]["mercs"]:
		if int(m["slot"]) == slot:
			return m["callsign"]
	return "Merc %d" % slot


# --- tabs ----------------------------------------------------------------------------------------

func _show_tab(tab: String) -> void:
	_tab = tab
	_moving = -1
	for t in _tab_btns:
		_tab_btns[t].button_pressed = t == tab
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()
	_stat_labels.clear()
	_gear_notes.clear()
	if tab == "squad":
		_say("Set stats and gear. Tap a merc on the map, then a tile in the west to move them.", true)
		_build_squad_page()
	else:
		_say("Pick an enemy below, then tap the map to place it. Tap a placed enemy to remove it.", true)
		_build_enemy_page()
	_ruleset_btn.text = RULESET_LABEL[_cfg["ruleset"]]
	_refresh_board()


func _build_squad_page() -> void:
	for i in Sandbox.SQUAD:
		var m: Dictionary = _cfg["mercs"][i]
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		_content.add_child(box)
		var head := Label.new()
		head.text = "%d. %s" % [i + 1, _callsign(int(m["slot"]))]
		head.add_theme_color_override("font_color", Color("ffd479"))
		box.add_child(head)
		var grid := GridContainer.new()
		grid.columns = 3
		box.add_child(grid)
		for key in Sandbox.STAT_KEYS:
			grid.add_child(_stat_cell(i, key))
		for slot in Campaign.GEAR_SLOTS:
			box.add_child(_gear_row(i, slot))
		_content.add_child(HSeparator.new())


func _stat_cell(index: int, key: String) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_button("-", _bump.bind(index, key, -1), Vector2(40, 40)))
	var l := Label.new()
	l.custom_minimum_size = Vector2(70, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(l)
	_stat_labels["%d:%s" % [index, key]] = l
	row.add_child(_button("+", _bump.bind(index, key, 1), Vector2(40, 40)))
	_set_stat_text(index, key)
	return row


func _set_stat_text(index: int, key: String) -> void:
	_stat_labels["%d:%s" % [index, key]].text = "%s %d" % [key.to_upper(), int(_cfg["mercs"][index]["stats"][key])]


func _bump(index: int, key: String, delta: int) -> void:
	_cfg = Sandbox.with_stat(_cfg, index, key, delta)
	_set_stat_text(index, key)


func _gear_row(index: int, slot: String) -> Control:
	var col := VBoxContainer.new()
	var opt := OptionButton.new()
	opt.focus_mode = Control.FOCUS_NONE
	opt.custom_minimum_size = Vector2(0, 40)
	opt.add_item("%s: none" % GEAR_LABEL[slot], 0)
	opt.set_item_metadata(0, "")
	var current: String = _cfg["mercs"][index]["gear"][slot]
	var ids: Array[String] = []
	for it: Dictionary in _story["items"]["items"]:
		if it["slot"] == slot:
			ids.append(it["id"])
			opt.add_item("%s: %s" % [GEAR_LABEL[slot], it["name"]], ids.size())
			opt.set_item_metadata(ids.size(), it["id"])
	for n in opt.item_count:
		if opt.get_item_metadata(n) == current:
			opt.select(n)
	opt.item_selected.connect(_on_gear.bind(opt, index, slot))
	col.add_child(opt)
	var note := Label.new()
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color("8a93a0"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(note)
	_gear_notes["%d:%s" % [index, slot]] = note
	_set_gear_note(index, slot)
	return col


func _item_summary(id: String) -> String:
	for it: Dictionary in _story["items"]["items"]:
		if it["id"] == id:
			var parts: Array[String] = []
			var st: Dictionary = it.get("stats", {})
			var labels := {"hp": "%+d hp", "morale": "%+d morale", "speed": "%+d speed", "range": "%+d range", "damage": "%+d damage", "shot_ticks": "%+d ticks per shot", "accuracy": "%+d%% to hit"}
			for key in labels:
				if st.has(key):
					parts.append(labels[key] % int(st[key]))
			if it.has("trait"):
				parts.append(String(_story["items"]["traits"].get(it["trait"], it["trait"])))
			return ", ".join(parts)
	return ""


func _set_gear_note(index: int, slot: String) -> void:
	_gear_notes["%d:%s" % [index, slot]].text = _item_summary(_cfg["mercs"][index]["gear"][slot])


func _on_gear(selected: int, opt: OptionButton, index: int, slot: String) -> void:
	_cfg = Sandbox.with_gear(_cfg, index, slot, String(opt.get_item_metadata(selected)))
	_set_gear_note(index, slot)


func _build_enemy_page() -> void:
	var kind_opt := OptionButton.new()
	kind_opt.focus_mode = Control.FOCUS_NONE
	kind_opt.custom_minimum_size = Vector2(0, 44)
	for k in _kinds:
		kind_opt.add_item(k["label"])
	kind_opt.select(_kind_idx)
	kind_opt.item_selected.connect(func(i: int) -> void:
		_kind_idx = i
		_update_kind_note())
	_content.add_child(kind_opt)
	var hollow := CheckBox.new()
	hollow.text = "Hollowed (60% stats, no morale, never breaks)"
	hollow.button_pressed = _hollow
	hollow.focus_mode = Control.FOCUS_NONE
	hollow.toggled.connect(func(on: bool) -> void:
		_hollow = on
		_update_kind_note())
	_content.add_child(hollow)
	var role_opt := OptionButton.new()
	role_opt.focus_mode = Control.FOCUS_NONE
	role_opt.custom_minimum_size = Vector2(0, 44)
	var role_text := {"patrol": "Role: patrol (pushes at you)", "guard": "Role: guard (holds its tile)", "sentry": "Role: sentry (overwatch, faces west)"}
	for r in Sandbox.ROLES:
		role_opt.add_item(role_text[r])
	role_opt.select(_role_idx)
	role_opt.item_selected.connect(func(i: int) -> void: _role_idx = i)
	_content.add_child(role_opt)
	_kind_note = Label.new()
	_kind_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_kind_note.add_theme_color_override("font_color", Color("8a93a0"))
	_content.add_child(_kind_note)
	_update_kind_note()
	var row := HBoxContainer.new()
	_content.add_child(row)
	var clear := _button("Clear all", _clear_enemies, Vector2(0, 44))
	clear.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(clear)
	_enemy_count = Label.new()
	_content.add_child(_enemy_count)
	_update_enemy_count()


var _kind_note: Label
var _enemy_count: Label


func _update_kind_note() -> void:
	if _kind_note == null:
		return
	var s: Dictionary = _kinds[_kind_idx]["stats"]
	if _hollow:
		s = Campaign.drone_stats(s, int(_story["world"]["hollowing"]["drone_percent"]))
	_kind_note.text = "HP %d  SPD %d  AIM %d  CQB %d  MORALE %d  SIGHT %d" % [int(s["hp"]), int(s["speed"]), int(s["aim"]), int(s["cqb"]), int(s["morale"]), int(s["sight"])]


func _update_enemy_count() -> void:
	if _enemy_count != null:
		_enemy_count.text = "%d / %d enemies placed" % [_cfg["enemies"].size(), Sandbox.MAX_ENEMIES]


func _clear_enemies() -> void:
	_cfg = Sandbox.without_enemies(_cfg)
	_update_enemy_count()
	_refresh_board()
	_say("All enemies removed. Place some before starting.", true)


# --- board ---------------------------------------------------------------------------------------

func _refresh_board() -> void:
	if _board == null:
		return
	var state := Sandbox.preview_state(_story, _cfg)
	_board.set_overlay({"selected": int(_cfg["mercs"][_moving]["slot"]) if _moving >= 0 else -1})
	_board.show_frame(state, [], [])


func _on_tile_clicked(tile: Vector2i, button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		_moving = -1
		_refresh_board()
		return
	if _tab == "squad":
		_click_squad(tile)
	else:
		_click_enemies(tile)


func _click_squad(tile: Vector2i) -> void:
	var hit := Sandbox.merc_at(_cfg, tile)
	if hit >= 0:
		_moving = hit
		_say("%s selected: tap a free tile in the west to move them." % _callsign(int(_cfg["mercs"][hit]["slot"])), true)
		_refresh_board()
		return
	if _moving < 0:
		_say("Tap one of your mercs first.", false)
		return
	var why := Sandbox.merc_move_problem(_cfg, _map, tile)
	if why != "":
		_say(why, false)
		return
	_cfg = Sandbox.with_merc_pos(_cfg, _moving, tile)
	_moving = -1
	_say("Moved.", true)
	_refresh_board()


func _click_enemies(tile: Vector2i) -> void:
	var existing := Sandbox.enemy_at(_cfg, tile)
	if existing >= 0:
		_cfg = Sandbox.without_enemy_at(_cfg, tile)
		_say("Removed.", true)
	else:
		var key: String = _kinds[_kind_idx]["key"]
		var why := Sandbox.placement_problem(_story, _cfg, _map, tile, key)
		if why != "":
			_say(why, false)
			return
		_cfg = Sandbox.with_enemy(_cfg, {"kind": key, "hollow": _hollow, "role": Sandbox.ROLES[_role_idx], "pos": tile})
		_say("Placed %s%s (%s)." % ["hollow " if _hollow else "", _kinds[_kind_idx]["label"], Sandbox.ROLES[_role_idx]], true)
	_update_enemy_count()
	_refresh_board()


# --- start / leave ----------------------------------------------------------------------------------

func _cycle_ap() -> void:
	_cfg = Sandbox.with_next_ap(_cfg)
	_update_ap_label()


func _update_ap_label() -> void:
	_ap_btn.text = "AP per activation: %d (tap to change; activation ruleset)" % Sandbox.ap_of(_cfg)


func _toggle_ruleset() -> void:
	_cfg = Sandbox.with_ruleset(_cfg, Session.next_ruleset(_cfg["ruleset"]))
	_ruleset_btn.text = RULESET_LABEL[_cfg["ruleset"]]


func _start() -> void:
	var why := Sandbox.problem(_cfg)
	if why != "":
		_say(why, false)
		return
	var cfg := _cfg
	Session.reset()
	Session.sandbox_cfg = cfg
	Session.sandbox = true
	Session.level_test = true
	Session.ruleset = cfg["ruleset"]
	Session.campaign = Campaign.new_game(_story)
	Session.mission_id = Sandbox.MAP
	Session.current_match = Sandbox.build(_story, cfg)
	get_tree().change_scene_to_file(PLAY_SCENE if Session.scene_ruleset_is_planned(cfg["ruleset"]) else INITIATIVE_SCENE)


func _back() -> void:
	Session.sandbox_cfg = _cfg
	get_tree().change_scene_to_file(MENU_SCENE)


func _capture_and_quit(path: String) -> void:
	for i in 3:
		await get_tree().process_frame
	var err := get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit(0 if err == OK else 1)
