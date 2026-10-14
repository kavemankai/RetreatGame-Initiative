extends Control
## The campaign screen: menu, mission briefing and squad choice, then (after a
## mission) the result, roll calls, debrief, Orrick's transmission and the
## endings. Everything is a "page": text plus buttons.
##
## Scripted capture (testing):
##   godot --path . --resolution 540x960 -- --demo=debrief --advance=1 --shot=out.png
##   demos: menu | briefing | squad | loadout | debrief | wards | ending | over

const STORY_DIR := "res://data/story"
const SAVE_PATH := "user://campaign.json"
const PLAY_SCENE := "res://view/play.tscn"
const INITIATIVE_SCENE := "res://view/initiative.tscn"
const SANDBOX_SCENE := "res://view/sandbox.tscn"
const MARGIN := 14
const BUTTON_HEIGHT_PORTRAIT := 56
const FONT_PORTRAIT := 18
const FONT_LANDSCAPE := 16
const COL_NARRATOR := "#8a93a0"
const COL_ORRICK := "#7fd6d0"
const COL_HOLLOW := "#6f7885"
const SPEAKER_COLORS: Array[String] = ["#ffd479", "#8fd0ff", "#9be39b", "#ffa8a8", "#d0b0ff", "#ffbd80", "#a8e0ff", "#e8e8a0"]

var _story: Dictionary
var _picked: Array[int] = []
var _mission_id := ""   # the mission (or card) being briefed
var _title: Label
var _status: Label
var _text: RichTextLabel
var _buttons: GridContainer
var _footer: VBoxContainer
var _sound: SoundBoard
var _brief: Dictionary = {}  # title, body, mission of the briefing on screen
var _portrait := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var loaded := StoryData.load_dir(STORY_DIR)
	_story = loaded["data"]
	_sound = SoundBoard.new()  # before the UI so every button clicks
	add_child(_sound)
	_build_ui()
	resized.connect(_apply_layout)
	_apply_layout()
	if not (loaded["errors"] as Array).is_empty():
		_show("Story data error", "The story files could not be loaded:\n\n%s" % "\n".join(loaded["errors"]), [])
		return
	var args := _parse_args()
	if args.has("demo"):
		_run_demo(String(args["demo"]))
	elif Session.campaign != null and not Session.pending_outcome.is_empty():
		_apply_outcome()
	else:
		_menu()
	for i in int(args.get("advance", 0)):
		_advance()
	if args.has("shot"):
		_capture_and_quit(String(args["shot"]))


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out


# --- layout ---------------------------------------------------------------------------

func _build_ui() -> void:
	theme = Theme.new()
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, MARGIN)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 26)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_title)
	_status = Label.new()
	_status.add_theme_color_override("font_color", Color("8a93a0"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.scroll_active = true
	col.add_child(_text)
	_buttons = GridContainer.new()
	_buttons.add_theme_constant_override("h_separation", 8)
	_buttons.add_theme_constant_override("v_separation", 8)
	col.add_child(_buttons)
	_footer = VBoxContainer.new()
	_footer.add_theme_constant_override("separation", 8)
	col.add_child(_footer)


func _apply_layout() -> void:
	_portrait = size.y > size.x
	theme.default_font_size = FONT_PORTRAIT if _portrait else FONT_LANDSCAPE


func _show(title: String, bbcode: String, buttons: Array, status: String = "", columns: int = 1, footer: Array = []) -> void:
	_title.text = title
	_status.text = status
	_status.visible = status != ""
	_text.text = bbcode
	_text.scroll_to_line(0)
	_buttons.columns = columns
	_fill(_buttons, buttons, columns > 1)
	_fill(_footer, footer, false)


func _fill(box: Container, buttons: Array, expand: bool) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	for b: Dictionary in buttons:
		var btn := Button.new()
		btn.text = b["text"]
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(0, BUTTON_HEIGHT_PORTRAIT if _portrait else 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.disabled = b.get("disabled", false)
		btn.toggle_mode = b.get("toggle", false)
		btn.button_pressed = b.get("pressed", false)
		btn.pressed.connect(b["call"])
		box.add_child(btn)


## Show the next unfinished debrief step (they live in the save, so quitting
## between a mission and its roll calls loses nothing), else the briefing.
func _next() -> void:
	var c := Session.campaign
	if c == null:
		_menu()
		return
	while not c.pending.is_empty():
		var p := _page_for(c, c.pending[0])
		if not p.is_empty():
			_show(p["title"], p["bbcode"], p["buttons"], p.get("status", ""))
			return
		c.pending.pop_front()  # a step with nothing to show
	_briefing()


## Finish the current step, save, and move on.
func _advance() -> void:
	var c := Session.campaign
	if c != null and not c.pending.is_empty():
		c.pending.pop_front()
	_save()
	_next()


func _continue_button(text: String = "Continue") -> Array:
	return [{"text": text, "call": _advance}]


func _page_for(c: Campaign, d: Dictionary) -> Dictionary:
	match d["t"]:
		"result": return _result_page(c, d)
		"roll": return _roll_page(c, d)
		"roll_after": return _roll_after_page(c, d)
		"debrief": return _debrief_page(c, d)
		"orrick": return _orrick_page(c, d)
	return {}


func _resources(c: Campaign) -> String:
	return "Procession %d   Reserves %d   Remembrance %d" % [c.procession, c.reserves, c.remembrance]


# --- menu -------------------------------------------------------------------------------

func _menu(status: String = "") -> void:
	var tagline := "The war is over and nobody has told the army."
	var buttons: Array = []
	var resumable := ResumeStore.peek()
	if not resumable.is_empty():
		buttons.append({"text": "Resume battle: %s" % resumable["label"], "call": _resume_battle})
	buttons.append({"text": "New campaign", "call": _new_pressed})
	if FileAccess.file_exists(SAVE_PATH):
		buttons.append({"text": "Continue campaign", "call": _load_campaign})
	buttons.append({"text": "Quick skirmish", "call": _quick_skirmish})
	buttons.append({"text": "Act 1 level test", "call": _level_test_menu})
	buttons.append({"text": "Sandbox (set stats, gear, enemies)", "call": _open_sandbox})
	buttons.append({"text": "Sound: %s" % ("off" if _sound.settings.muted else "on"), "call": _toggle_sound})
	_show(_story["world"]["title"], "[i]%s[/i]\n\nYou command the 9th Rearguard, the last real people in a ghost army, escorting 6,200 civilians along the Reliquary Lanes toward a refuge that may not let you in.\n\nBehind you comes a courteous man who only wants you to be counted." % tagline, buttons, status)


const LEVEL_TEST_PITCH := {
	"karsa_breakout": "Karsa Breakout: the fire door. A sentry watches the door; find the vent.",
	"the_weir": "The Weir: the broken freighter. Three caches, one safe, then back to the tug.",
	"pellam_dock": "Pellam Dock: two gates. Hold the berths for 4 rounds; reinforcements on round 2.",
	"orchard_ring": "Orchard Ring: the greenhouse. Read the patrols, reach the hostages, get out.",
}


## Plays one of the four redesigned Act 1 maps on a throwaway campaign.
func _level_test_menu() -> void:
	var buttons: Array = []
	for id: String in LEVEL_TEST_PITCH:
		buttons.append({"text": LEVEL_TEST_PITCH[id], "call": _start_level_test.bind(id)})
	buttons.append({"text": "Ruleset: %s (tap to switch)" % Session.RULESET_LABEL[Session.ruleset], "call": _toggle_ruleset})
	_show("Act 1 level test", "Pick a map. Each uses the new layout, enemy roles and goal. Starting one replaces any battle you could resume.", buttons, "", 1, [{"text": "Back", "call": _menu}])


func _toggle_ruleset() -> void:
	Session.ruleset = Session.next_ruleset(Session.ruleset)
	_level_test_menu()


## Picks the battle up exactly where the autosave left it (no undo: it is the last committed action).
func _resume_battle() -> void:
	if not ResumeStore.enter_session(_story):
		_menu("That battle could not be resumed and was discarded.")
		return
	get_tree().change_scene_to_file(INITIATIVE_SCENE)


func _open_sandbox() -> void:
	get_tree().change_scene_to_file(SANDBOX_SCENE)


func _start_level_test(id: String) -> void:
	var ruleset := Session.ruleset
	Session.reset()
	Session.ruleset = ruleset
	var c := Campaign.new_game(_story)
	var m: Dictionary = c.mission_or_card(id)
	var slots: Array = c.available_slots().slice(0, int(m["squad_size"]))
	Session.campaign = c
	Session.mission_id = id
	Session.level_test = true
	Session.current_match = MissionBuilder.build(c, id, slots)
	get_tree().change_scene_to_file(PLAY_SCENE if Session.scene_ruleset_is_planned(ruleset) else INITIATIVE_SCENE)


func _toggle_sound() -> void:
	_sound.set_muted(not _sound.settings.muted)  # unmuting resumes whatever was playing
	_menu()


func _new_pressed() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_start_new()
		return
	_show("Start over?", "A saved campaign exists. Starting a new one replaces it.", [
		{"text": "Replace the save", "call": _start_new},
		{"text": "Keep it", "call": _menu},
	])


func _start_new() -> void:
	Session.reset()
	Session.campaign = Campaign.new_game(_story)
	_save()
	_briefing()


func _load_campaign() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
	var c: Campaign = Campaign.from_dict(parsed, _story) if typeof(parsed) == TYPE_DICTIONARY else null
	if c == null:
		var why: String = Campaign.save_problem(parsed) if typeof(parsed) == TYPE_DICTIONARY else "the file is not valid JSON"
		_show("The save could not be read", "It is damaged or from another version (%s).\n\nYour file has not been touched." % why, [
			{"text": "Back", "call": _menu},
			{"text": "Start a new campaign instead", "call": _new_pressed},
		])
		return
	Session.reset()
	Session.campaign = c
	_next()


func _quick_skirmish() -> void:
	Session.reset()
	get_tree().change_scene_to_file(PLAY_SCENE)


func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null and Session.campaign != null:
		f.store_string(JSON.stringify(Session.campaign.to_dict()))


# --- briefing and squad choice ----------------------------------------------------------

func _music_for_current() -> void:
	var c := Session.campaign
	if c != null and c.current != "":
		_sound.set_music(int(c.mission_or_card(c.current).get("act", 1)))


func _briefing() -> void:
	_music_for_current()
	var c := Session.campaign
	if c == null:
		_menu()
		return
	if c.over:
		_over_page()
		return
	if c.finished:
		_ending_page()
		return
	_mission_id = _mission_to_brief(c)
	var m := c.mission_or_card(_mission_id)
	var is_card := c.card(_mission_id).size() > 0
	var scene_id: String = ("card_" + _mission_id) if is_card else m["scenes"]["briefing"]
	var title := ("Contingency: %s" % m["name"]) if is_card else ("Act %d: %s" % [m["act"], m["name"]])
	var body := "[i]%s[/i]\n\n[b]Objective[/b]: %s\n\n%s" % [m.get("summary", ""), m["objective"]["text"], _scene_bbcode(scene_id)]
	_default_squad(c, m)
	_brief = {"title": title, "mission": m}
	_show(title, body, [{"text": "Choose squad", "call": _squad_choice}], _resources(c))


## A contingency card is offered once per act, after its second story mission;
## an offered card stays offered until it is played.
func _mission_to_brief(c: Campaign) -> String:
	if c.offered_card != "":
		return c.offered_card
	var m := c.mission_or_card(c.current)
	var act := int(m.get("act", 1))
	var per_act := int(_story["route"]["contingencies_per_act"])
	if c.completed_story_in_act(act) == 2 and c.drawn_for_act(act).size() < per_act:
		c.offered_card = c.draw_contingency(act, c.completed.size() * 31 + c.reserves)
		_save()
		if c.offered_card != "":
			return c.offered_card
	return c.current


## How many the squad takes: the mission's size, or everyone left if fewer.
func _squad_need(c: Campaign, m: Dictionary) -> int:
	return mini(int(m["squad_size"]), c.available_slots().size())


func _default_squad(c: Campaign, m: Dictionary) -> void:
	_picked.clear()
	var named: Array[int] = []
	var hollow: Array[int] = []
	for slot in c.available_slots():
		(named if c.slot_status(slot) == "named" else hollow).append(slot)
	for slot in named + hollow:
		if _picked.size() < _squad_need(c, m):
			_picked.append(slot)


func _squad_choice() -> void:
	var c := Session.campaign
	var m: Dictionary = _brief["mission"]
	var need := _squad_need(c, m)
	var grid: Array = []
	for slot in c.available_slots():
		grid.append({"text": ("* " if _picked.has(slot) else "") + _slot_label(c, slot), "toggle": true, "pressed": _picked.has(slot), "call": _toggle_slot.bind(slot)})
	var short := ""
	if need < int(m["squad_size"]):
		short = "\n\n[i]Only %d of you are left to send. The net reports the squad below strength; nobody is left to read the error.[/i]" % need
	var body := "[b]%s[/b]\n\n%s\n\nChoose [b]%d[/b] for the squad. Hollows fight at 60%% of the soldier they replace and never lose their nerve.%s" % [_brief["title"], m["objective"]["text"], need, short]
	_show("Squad", body, grid, _resources(c), 2, [
		{"text": "Deploy (%d/%d)" % [_picked.size(), need], "disabled": _picked.size() != need or need == 0, "call": _deploy},
		{"text": "Loadout (%d in the stash)" % c.stash.size(), "call": _loadout},
		{"text": "Back to briefing", "call": _briefing},
	])


# --- loadout ---------------------------------------------------------------------------------

func _gear_name(c: Campaign, id: String) -> String:
	return c.item(id).get("name", "-") if id != "" else "-"


## Everyone who can carry kit, with what they wear. Tap one to change it.
func _loadout() -> void:
	var c := Session.campaign
	var grid: Array = []
	for slot in c.available_slots():
		if c.slot_status(slot) != "named":
			continue
		var g := c.gear_of(slot)
		grid.append({"text": "%s\n%s | %s | %s" % [_slot_label(c, slot), _gear_name(c, g["armour"]), _gear_name(c, g["weapon"]), _gear_name(c, g["mod"])], "call": _loadout_merc.bind(slot)})
	var body := "[b]Loadout[/b]\n\nThree slots each: armour, weapon, mod. Anything you find goes in the stash. When a soldier dies, their kit comes back to it; a hollow takes nothing."
	_show("Loadout", body, grid, _resources(c), 1, [{"text": "Back to the squad", "call": _squad_choice}])


func _loadout_merc(slot: int) -> void:
	var c := Session.campaign
	var g := c.gear_of(slot)
	var lines: Array[String] = ["[b]%s[/b]" % _slot_label(c, slot), ""]
	var buttons: Array = []
	for kind in Campaign.GEAR_SLOTS:
		var id: String = g[kind]
		lines.append("%s: %s%s" % [kind.capitalize(), _gear_name(c, id), ("  (%s)" % c.item_summary(id)) if id != "" else ""])
		buttons.append({"text": "%s: %s" % [kind.capitalize(), _gear_name(c, id)], "call": _loadout_kind.bind(slot, kind)})
	_show("Loadout", "\n".join(lines), buttons, _resources(c), 1, [{"text": "Back", "call": _loadout}])


func _loadout_kind(slot: int, kind: String) -> void:
	var c := Session.campaign
	var worn: String = c.gear_of(slot)[kind]
	var buttons: Array = []
	for id in c.stash_for(kind):
		buttons.append({"text": "%s   %s" % [_gear_name(c, id), c.item_summary(id)], "call": _loadout_equip.bind(slot, id)})
	if worn != "":
		buttons.append({"text": "Take off %s" % _gear_name(c, worn), "call": _loadout_unequip.bind(slot, kind)})
	var body := "[b]%s: %s[/b]\n\n" % [kind.capitalize(), _slot_label(c, slot)]
	body += "Worn: %s\n" % (("%s  (%s)\n[i]%s[/i]" % [_gear_name(c, worn), c.item_summary(worn), c.item(worn).get("note", "")]) if worn != "" else "nothing")
	if buttons.is_empty():
		body += "\nNothing in the stash for this slot."
	_show("Loadout", body, buttons, _resources(c), 1, [{"text": "Back", "call": _loadout_merc.bind(slot)}])


func _loadout_equip(slot: int, id: String) -> void:
	Session.campaign.equip(slot, id)
	_sound.play("sfx_equip")
	_save()
	_loadout_merc(slot)


func _loadout_unequip(slot: int, kind: String) -> void:
	Session.campaign.unequip(slot, kind)
	_save()
	_loadout_merc(slot)


func _toggle_slot(slot: int) -> void:
	var need := _squad_need(Session.campaign, _brief["mission"])
	if _picked.has(slot):
		_picked.erase(slot)
	elif _picked.size() < need:
		_picked.append(slot)
	_squad_choice()


func _slot_label(c: Campaign, slot: int) -> String:
	if c.slot_status(slot) == "hollow":
		return "%s   (hollow)" % Campaign.designation(slot)
	for m: Dictionary in _story["cast"]["mercs"]:
		if int(m["slot"]) == slot:
			return m["callsign"]
	return "slot %d" % slot


func _deploy() -> void:
	var c := Session.campaign
	Session.mission_id = _mission_id
	Session.withdrawn = false
	Session.current_match = MissionBuilder.build(c, _mission_id, _picked.duplicate())
	get_tree().change_scene_to_file(PLAY_SCENE)


# --- after a mission ------------------------------------------------------------------------

## Apply a finished mission exactly once and queue its debrief steps in the
## campaign itself (so they survive quitting).
func _apply_outcome() -> void:
	var c := Session.campaign
	var o: Dictionary = Session.pending_outcome
	var id := Session.mission_id
	var withdrawn := Session.withdrawn
	Session.current_match = null
	Session.pending_outcome = {}
	Session.withdrawn = false
	if not c.can_complete(id):
		_next()  # already applied, or out of order: never apply twice
		return
	var before := {"procession": c.procession, "reserves": c.reserves}
	var report := c.complete_mission(id, o["success"], o["dead_slots"], o["writ_dead"], [], o["squad_wiped"], int(o.get("procession_loss", 0)))
	c.pending = [{"t": "result", "id": id, "o": o, "report": report, "before": before, "withdrawn": withdrawn}]
	if not c.over:
		for slot in report["fallen"]:
			c.pending.append({"t": "roll", "slot": slot, "vacant": (report["vacant"] as Array).has(slot)})
		if c.card(id).is_empty():
			c.pending.append({"t": "debrief", "mission": id, "deaths": (report["fallen"] as Array).size()})
			c.pending.append({"t": "orrick", "mission": id})
	_save()
	_next()


func _result_page(c: Campaign, d: Dictionary) -> Dictionary:
	var o: Dictionary = d["o"]
	var report: Dictionary = d["report"]
	var before: Dictionary = d["before"]
	var m := c.mission_or_card(d["id"])
	var verdict := "Withdrawn" if d["withdrawn"] else ("Complete" if o["success"] else "Failed")
	if o["squad_wiped"]:
		verdict = "The squad is lost"
	var lines: Array[String] = []
	lines.append("[b]%s[/b]" % verdict)
	lines.append("Procession %d (%+d)   Reserves %d (%+d)" % [c.procession, c.procession - int(before["procession"]), c.reserves, c.reserves - int(before["reserves"])])
	for slot in report["hollowed"]:
		lines.append("%s is dead. [color=%s]%s[/color] stands in the slot. One reserve spent." % [_callsign(int(slot)), COL_HOLLOW, Campaign.designation(int(slot))])
	for slot in report["refilled"]:
		lines.append("[color=%s]%s[/color] is replaced. One reserve spent." % [COL_HOLLOW, Campaign.designation(int(slot))])
	for slot in report["vacant"]:
		lines.append("%s is dead. Slot %02d stays empty; there is nothing left to send." % [_callsign(int(slot)), int(slot)])
	_sound.play("stinger_win" if o["success"] and not d["withdrawn"] else "stinger_loss")
	if not (report.get("loot", []) as Array).is_empty():
		_sound.play("sfx_loot", 1.2)
		var names: Array[String] = []
		for id in report["loot"]:
			names.append(String(c.item(id).get("name", id)))
		lines.append("[b]Salvage[/b]: %s. Equip it from the squad screen." % ", ".join(names))
	for wid in o["writ_dead"]:
		lines.append("[color=%s]The Writ[/color]: %s falls. The Bureau fills the slot with a hollow." % [COL_ORRICK, _speaker_name(wid)])
	if o["squad_wiped"]:
		lines.append("\n[i]No one is left to read the names.[/i]")
	return {"title": m.get("name", "Mission"), "bbcode": "\n\n".join(lines), "status": _resources(c), "buttons": _continue_button()}


func _roll_page(c: Campaign, d: Dictionary) -> Dictionary:
	var slot := int(d["slot"])
	var body := "[b]%s[/b], slot %02d, is dead. %s\n\n%s" % [_callsign(slot), slot, "The muster drop is already falling." if not d.get("vacant", false) else "There is nothing left to send.", _scene_bbcode("roll_call_prompt")]
	return {"title": "Roll Call", "bbcode": body, "status": _resources(c), "buttons": [
		{"text": "Read the name", "call": _roll_choice.bind(true)},
		{"text": "Say nothing", "call": _roll_choice.bind(false)},
	]}


func _roll_choice(read: bool) -> void:
	var c := Session.campaign
	var d: Dictionary = c.pending[0]
	if read:
		c.apply_choice("roll_call_prompt", "read_name")
	c.pending[0] = {"t": "roll_after", "slot": d["slot"], "read": read, "vacant": d.get("vacant", false)}
	_save()
	_next()


func _roll_after_page(c: Campaign, d: Dictionary) -> Dictionary:
	var body := _scene_bbcode("roll_call_read" if d["read"] else "roll_call_silent")
	if d.get("vacant", false):
		body += "\n\n[i]No muster drop comes. The slot stays empty.[/i]"
	else:
		body += "\n\n%s\n\n[color=%s]%s[/color]" % [_scene_bbcode("hollow_arrives"), COL_HOLLOW, Campaign.designation(int(d["slot"]))]
	return {"title": "Roll Call", "bbcode": body, "status": _resources(c), "buttons": _continue_button()}


func _debrief_page(c: Campaign, d: Dictionary) -> Dictionary:
	var m := c.mission_or_card(d["mission"])
	var scene := _scene(m["scenes"]["debrief"])
	if scene.get("when", "") == "first_death" and int(d["deaths"]) == 0:
		return {}
	var buttons: Array = []
	var choices: Array = scene.get("choices", [])
	if choices.is_empty():
		buttons = _continue_button()
	for ch: Dictionary in choices:
		buttons.append({"text": ch["text"], "call": _debrief_choice.bind(scene["id"], ch["id"])})
	return {"title": "Debrief: %s" % m["name"], "bbcode": _scene_bbcode(scene["id"]), "status": _resources(c), "buttons": buttons}


func _debrief_choice(scene_id: String, choice_id: String) -> void:
	Session.campaign.apply_choice(scene_id, choice_id)
	_advance()


## Orrick's transmission, stripped by how hollow his squad has become.
func _orrick_page(c: Campaign, d: Dictionary) -> Dictionary:
	var m := c.mission_or_card(d["mission"])
	if (m["enemies"]["writ"] as Array).is_empty() and not m["orrick_present"]:
		return {}
	var scenes: Array[String] = [c.orrick_scene()]
	if m["id"] == _story["route"]["finale"] and c.orrick_names_himself():
		scenes.append("orrick_true_name")
	var body := ""
	for sid in scenes:
		body += _scene_bbcode(sid) + "\n\n"
	var stage_name: String = _story["writ"]["stage_names"][c.writ_stage()]
	return {"title": "Transmission", "bbcode": body.strip_edges(), "status": "The Writ: %s" % stage_name, "buttons": _continue_button()}


func _over_page() -> void:
	var c := Session.campaign
	var text: String = {
		"squad_lost": "The whole squad fell on the field. No one is left to read the names, and the hollows stop one by one as the net goes quiet.",
		"no_one_left": "Every slot is empty. There is no one left to send, and the net reports an error that nobody is left to read.",
		"procession_lost": "The Procession is gone. There is no one left to protect, and no door left to reach.",
	}.get(c.over_reason, "The 9th Rearguard is gone.")
	_show("The 9th Rearguard is gone", "%s\n\n[i]Names read aloud: %d.[/i]" % [text, c.remembrance], [
		{"text": "Main menu", "call": _back_to_menu},
	], _resources(c))


func _ending_page() -> void:
	var c := Session.campaign
	var id := c.resolve_ending()
	c.ending = id
	_save()
	var e: Dictionary = {}
	for x: Dictionary in _story["world"]["endings"]:
		if x["id"] == id:
			e = x
	_show(e.get("name", "The End"), "%s\n\n[i]%s[/i]" % [_scene_bbcode(e.get("scene", "")), e.get("summary", "")], [
		{"text": "Main menu", "call": _back_to_menu},
	], "%s   Writ hollowed: %d/6" % [_resources(c), c.writ_stage()])


func _back_to_menu() -> void:
	Session.reset()
	_menu()


# --- text helpers --------------------------------------------------------------------------

func _scene(id: String) -> Dictionary:
	for s: Dictionary in _story["scenes"]["scenes"]:
		if s["id"] == id:
			return s
	return {}


func _scene_bbcode(id: String) -> String:
	var out: Array[String] = []
	for l: Dictionary in _scene(id).get("lines", []):
		var text := str(l["text"]).replace("[", "[lb]")
		match l["who"]:
			"narrator":
				out.append("[color=%s][i]%s[/i][/color]" % [COL_NARRATOR, text])
			"hollow":
				out.append("[color=%s]HOLLOW: %s[/color]" % [COL_HOLLOW, text])
			"orrick":
				out.append("[color=%s][b]Orrick[/b]: %s[/color]" % [COL_ORRICK, text])
			_:
				out.append("[color=%s][b]%s[/b][/color]: %s" % [_speaker_color(l["who"]), _speaker_name(l["who"]), text])
	return "\n\n".join(out)


func _speaker_name(who: String) -> String:
	if who == "keeper":
		return "Keeper"
	for m: Dictionary in _story["cast"]["mercs"]:
		if m["id"] == who:
			return m["callsign"]
	for o: Dictionary in _story["writ"]["officers"]:
		if o["id"] == who:
			return o["callsign"]
	return who


func _speaker_color(who: String) -> String:
	for m: Dictionary in _story["cast"]["mercs"]:
		if m["id"] == who:
			return SPEAKER_COLORS[int(m["slot"]) % SPEAKER_COLORS.size()]
	return COL_ORRICK


func _callsign(slot: int) -> String:
	for m: Dictionary in _story["cast"]["mercs"]:
		if int(m["slot"]) == slot:
			return m["callsign"]
	return "Slot %02d" % slot


# --- demos (screenshots) ---------------------------------------------------------------------

func _run_demo(name: String) -> void:
	match name:
		"briefing":
			_start_new()
		"squad":
			_start_new()
			_squad_choice()
		"loadout":
			_start_new()
			Session.campaign.stash.append_array(["carbine", "scope", "mourning_cloak"])
			_loadout_merc(1)
		"debrief":
			_start_new()
			_fake_outcome("karsa_breakout", {"success": true, "dead_slots": [5], "writ_dead": [], "squad_wiped": false})
		"wards":
			_start_new()
			for id in ["karsa_breakout", "the_weir", "pellam_dock", "orchard_ring"]:
				Session.campaign.complete_mission(id, true, [], [], [])
			_fake_outcome("quiet_wards", {"success": true, "dead_slots": [3, 7], "writ_dead": ["clerk"], "squad_wiped": false})
		"ending":
			_start_new()
			var c := Session.campaign
			c.remembrance = 11
			c.apply_choice("debrief_anselm", "destroy_vats")
			c.apply_choice("debrief_tamsins_rest", "open_the_roll")
			c.apply_choice("debrief_vesper_threshold", "read_the_roll")
			c.finished = true
			_ending_page()
		"over":
			_start_new()
			_fake_outcome("karsa_breakout", {"success": false, "dead_slots": [1, 5, 8], "writ_dead": [], "squad_wiped": true})
		_:
			_menu()


func _fake_outcome(id: String, outcome: Dictionary) -> void:
	Session.mission_id = id
	Session.pending_outcome = outcome
	_apply_outcome()


func _capture_and_quit(path: String) -> void:
	for i in 3:
		await get_tree().process_frame
	var err := get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit(0 if err == OK else 1)
