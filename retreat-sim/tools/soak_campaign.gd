extends SceneTree
## Play whole campaigns with the AI on both sides and report how they end.
## Exercises missions, cards, roll calls, choices, the economy and endings
## without any UI.
##   godot --headless --path . -s tools/soak_campaign.gd
##   godot --headless --path . -s tools/soak_campaign.gd -- --runs=3 --max-turns=12
##   godot --headless --path . -s tools/soak_campaign.gd -- --scripted --runs=6
## --scripted skips combat and applies a fixed pattern of deaths and Writ
## kills, so every campaign path is exercised whatever the AI's strength.

const DEFAULT_RUNS := 2
const DEFAULT_MAX_TURNS := 10
const MAX_MISSIONS := 40

var _scripted := false


func _init() -> void:
	var runs := DEFAULT_RUNS
	var max_turns := DEFAULT_MAX_TURNS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--runs="):
			runs = int(a.substr(7))
		elif a.begins_with("--max-turns="):
			max_turns = int(a.substr(12))
		elif a == "--scripted":
			_scripted = true
	var story: Dictionary = StoryData.load_dir("res://data/story")["data"]
	var profiles: Dictionary = SimAIProfile.load_file("res://data/ai_profiles.json")["profiles"]
	var endings := {}
	var failures := 0
	for run in runs:
		var result := _play_campaign(story, profiles, max_turns, run)
		print("run %d: %s after %d missions | procession %d reserves %d remembrance %d writ %d/6" % [run, result["ending"], result["missions"], result["procession"], result["reserves"], result["remembrance"], result["writ"]])
		endings[result["ending"]] = int(endings.get(result["ending"], 0)) + 1
		failures += int(result["errors"])
	print("endings: ", endings)
	quit(1 if failures > 0 else 0)


func _play_campaign(story: Dictionary, profiles: Dictionary, max_turns: int, run: int) -> Dictionary:
	var c := Campaign.new_game(story)
	var errors := 0
	var missions := 0
	while not c.over and not c.finished and missions < MAX_MISSIONS:
		var id := _next_mission(c, run + missions)
		var m := c.mission_or_card(id)
		var slots := _squad(c, int(m["squad_size"]))
		var o: Dictionary
		if _scripted:
			o = _scripted_outcome(c, id, slots, missions)
		else:
			var match_ := MissionBuilder.build(c, id, slots)
			var turns := 0
			while not match_.is_over() and turns < max_turns:
				turns += 1
				var plan := SimAI.plan_for(match_.state, 0, profiles, {}, Vector2i(10, 5))
				if match_.submit(plan) == null:
					printerr("run %d mission %s turn %d refused: %s" % [run, id, turns, match_.last_error])
					errors += 1
					break
			o = MissionBuilder.outcome(c, match_, not match_.is_over())
		if not c.can_complete(id):
			printerr("run %d: cannot complete %s" % [run, id])
			errors += 1
			break
		var report := c.complete_mission(id, o["success"], o["dead_slots"], o["writ_dead"], [], o["squad_wiped"], int(o.get("procession_loss", 0)))
		_make_choices(c, id, report, run)
		missions += 1
	if c.finished:
		c.ending = c.resolve_ending()
	return {"ending": c.ending if c.ending != "" else "unfinished", "missions": missions, "procession": c.procession,
		"reserves": c.reserves, "remembrance": c.remembrance, "writ": c.writ_stage(), "errors": errors}


func _next_mission(c: Campaign, seed: int) -> String:
	if c.offered_card != "":
		return c.offered_card
	var m := c.mission_or_card(c.current)
	var act := int(m["act"])
	if c.completed_story_in_act(act) == 2 and c.drawn_for_act(act).size() < 1:
		c.offered_card = c.draw_contingency(act, seed)
		if c.offered_card != "":
			return c.offered_card
	return c.current


func _squad(c: Campaign, size: int) -> Array:
	var out: Array = []
	for slot in c.available_slots():
		if out.size() < mini(size, c.available_slots().size()):
			out.append(slot)
	return out


## The "player": reads every fallen name, destroys the vats, opens the Roll,
## and on odd runs reads the Roll at the door (else holds it).
func _make_choices(c: Campaign, id: String, report: Dictionary, run: int) -> void:
	for slot in report["fallen"]:
		c.apply_choice("roll_call_prompt", "read_name")
	match id:
		"anselm": c.apply_choice("debrief_anselm", "destroy_vats")
		"tamsins_rest": c.apply_choice("debrief_tamsins_rest", "open_the_roll")
		"reliquary_lane": c.apply_choice("debrief_reliquary_lane", "read_a_name")
		"vesper_threshold": c.apply_choice("debrief_vesper_threshold", "read_the_roll" if run % 2 == 1 else "hold_the_door")


## A won mission in which one fielded merc dies (rotating) and every Writ
## officer present falls. Deterministic.
func _scripted_outcome(c: Campaign, id: String, slots: Array, index: int) -> Dictionary:
	var m := c.mission_or_card(id)
	var dead: Array = []
	if not slots.is_empty():
		dead.append(slots[index % slots.size()])
	return {"success": true, "dead_slots": dead, "writ_dead": (m["enemies"]["writ"] as Array).duplicate(), "squad_wiped": false}
