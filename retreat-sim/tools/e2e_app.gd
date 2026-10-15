extends SceneTree
## Drives the real game scenes (view/campaign.tscn and view/initiative.tscn) the way a thumb would:
## new campaign, the map, Brief, the prep screen, Deploy, the fight scene loading, then a finished
## outcome handed back to the campaign scene, the result / salvage / level-up / roll-call chain pressed
## through, and the map at the next stop with the save on disk. It overwrites user://campaign.json, so
## run it with the real save backed up. Run: godot --path . -s tools/e2e_app.gd (not headless: it needs
## the scenes' renderer; --headless also works).

var failures := 0


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1


func frames(n: int = 6) -> void:
	for i in n:
		await process_frame


func button(text: String) -> Button:
	if current_scene == null:
		return null
	for b in current_scene.find_children("*", "Button", true, false):
		if (b as Button).text == text and (b as Button).is_visible_in_tree() and not (b as Button).disabled:
			return b as Button
	return null


func press(text: String) -> bool:
	var b := button(text)
	if b == null:
		return false
	b.pressed.emit()
	return true


## Presses the first enabled button whose text starts with `prefix` (the menu's label carries the difficulty).
func press_prefix(prefix: String) -> bool:
	for b in current_scene.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with(prefix) and (b as Button).is_visible_in_tree() and not (b as Button).disabled:
			(b as Button).pressed.emit()
			return true
	return false


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var scene: Node = (load("res://view/campaign.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	current_scene = scene
	await frames()
	Session.reset()
	check(press_prefix("New campaign") or press("Replace the save"), "the menu offers a new campaign")
	await frames()
	if button("Replace the save") != null:
		press("Replace the save")
		await frames()
	check(button("Brief") != null and button("Stash") != null, "the map is the hub, with Brief and Stash")
	check(Session.campaign != null and Session.campaign.current == "karsa_breakout", "a fresh campaign at Karsa")
	check(press("Brief"), "Brief opens the prep screen")
	await frames()
	check(button("Deploy (3/3)") != null, "the prep screen has a full default squad")
	check(press("Loadout (0)"), "the Loadout shortcut opens")
	await frames()
	check(press("Back"), "and returns to the prep screen")
	await frames()
	check(button("Deploy (3/3)") != null, "with the squad kept")
	check(press("Deploy (3/3)"), "Deploy")
	await frames(10)
	var path := current_scene.scene_file_path if current_scene != null else ""
	check(path == "res://view/initiative.tscn", "the fight scene loads (%s)" % path)
	check(Session.current_match != null and Session.mission_id == "karsa_breakout", "the mission is built for the fight")
	# a finished win handed back, as the fight screen does
	var c := Session.campaign
	Session.pending_outcome = {"success": true, "dead_slots": [], "writ_dead": [], "squad_wiped": false, "units": [
		{"slot": 1, "alive": true, "shots": 9, "hits": 6, "kills": 2, "hits_taken": 1, "steps": 12},
		{"slot": 3, "alive": true, "shots": 8, "hits": 7, "kills": 2, "hits_taken": 0, "steps": 6},
		{"slot": 5, "alive": true, "shots": 4, "hits": 3, "kills": 1, "hits_taken": 0, "steps": 2}]}
	change_scene_to_file("res://view/campaign.tscn")
	await frames(10)
	check(current_scene != null and current_scene.scene_file_path == "res://view/campaign.tscn", "back on the campaign scene")
	check(c.completed.has("karsa_breakout") and c.current == "the_weir", "the outcome was applied once and the convoy moved on")
	var steps := 0
	while steps < 30 and button("Brief") == null:
		steps += 1
		var opts := current_scene.find_children("opt_*", "TapPanel", true, false)
		if not opts.is_empty() and button("Confirm") == null:
			(opts[0] as TapPanel).pressed.emit()
			await frames(2)
			press("Confirm")
		elif button("Continue") != null:
			press("Continue")
		elif button("To stash") != null:
			press("To stash")
		elif button("Confirm") != null:
			press("Confirm")
		else:
			var names: Array[String] = []
			for b in current_scene.find_children("*", "Button", true, false):
				names.append((b as Button).text)
			print("stuck with buttons: ", names, " pending: ", c.pending.map(func(p: Dictionary) -> String: return p["t"]))
			break
		await frames(4)
	check(button("Brief") != null and button("Roster") != null, "the chain ended on the map (after %d presses)" % steps)
	check(c.pending.is_empty(), "no debrief step is left")
	var f := FileAccess.open("user://campaign.json", FileAccess.READ)
	var saved: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
	var reloaded: Campaign = Campaign.from_dict(saved, c.story) if typeof(saved) == TYPE_DICTIONARY else null
	check(reloaded != null and reloaded.completed.has("karsa_breakout") and reloaded.current == "the_weir", "the save on disk holds the finished mission")
	print("e2e_app: %d failed" % failures)
	quit(1 if failures > 0 else 0)
