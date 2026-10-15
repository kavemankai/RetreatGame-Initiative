extends TestBase
## Before and after a fight: the mission prep data and screen (stakes, rewards, squad pick, readiness) and
## the result, squad report and salvage screens, plus the order of the debrief chain.

var story: Dictionary = StoryData.load_dir("res://data/story")["data"]


func fresh() -> Campaign:
	return Campaign.new_game(story)


func button(root: Node, text: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b as Button
	return null


func all_text(root: Node) -> String:
	var parts: Array[String] = []
	for l in root.find_children("*", "Label", true, false):
		parts.append((l as Label).text)
	return " ".join(parts)


func nodes_of(root: Node, type_name: String) -> Array[Node]:
	var out: Array[Node] = []
	for child in root.get_children():
		if child.get_script() != null and (child.get_script() as Script).get_global_name() == type_name:
			out.append(child)
		out.append_array(nodes_of(child, type_name))
	return out


func prep(c: Campaign, id := "karsa_breakout", keep: Array = []) -> MissionPrepScreen:
	var screen := MissionPrepScreen.new().setup(c, id, "[i]briefing text[/i]", keep)
	TestBase.tree.root.add_child(screen)
	return screen


func row(slot: int, hits := 0, kills := 0, hits_taken := 0, alive := true) -> Dictionary:
	return {"slot": slot, "alive": alive, "shots": hits + 1, "hits": hits, "kills": kills, "hits_taken": hits_taken, "steps": 3}


func step_for(c: Campaign, id: String, success: bool, dead: Array, rows: Array) -> Dictionary:
	var before := {"procession": c.procession, "reserves": c.reserves}
	var o := {"success": success, "dead_slots": dead, "writ_dead": [], "squad_wiped": false, "units": rows}
	var report := c.complete_mission(id, success, dead, [], [], false, 0, rows)
	return {"t": "result", "id": id, "o": o, "report": report, "before": before, "withdrawn": false}


func test_prep_info_states_the_stakes_the_reward_and_who_is_there() -> void:
	var c := fresh()
	var m := c.mission_or_card("karsa_breakout")
	var info := UiModel.prep_info(c, "karsa_breakout")
	check(info["on_success"] == "Procession %s, Reserves %s" % [UiTheme.delta_text(int(m["on_success"]["procession"])), UiTheme.delta_text(int(m["on_success"]["reserves"]))], "the win stakes come from the mission data (%s)" % info["on_success"])
	check(info["on_failure"].contains("-300") and info["on_failure"].contains("-4"), "the loss stakes are shown plainly (%s)" % info["on_failure"])
	check(info["rewards"] == ["Scope"] or (info["rewards"] as Array).size() == 1, "one reward is previewed by its name (%s)" % [info["rewards"]])
	check(info["enemies"] == ["3 conscript"], "the known opposition is the briefing's tiers (%s)" % [info["enemies"]])
	check(info["objective"] == m["objective"]["text"] and info["squad_size"] == 3 and not info["orrick"], "objective, squad size and the Orrick flag")
	var card := UiModel.prep_info(c, "stranded_tug")
	check(card["is_card"] and card["name"] == "A Tug Adrift", "a contingency card is flagged as one")


func test_readiness_blocks_a_wrong_count_and_warns_about_a_missing_weapon() -> void:
	var c := fresh()
	check(UiModel.readiness(c, [1, 3], 3).any(func(w: Dictionary) -> bool: return w["level"] == "block"), "two of three chosen blocks Deploy")
	check(UiModel.readiness(c, [1, 3, 4], 3).filter(func(w: Dictionary) -> bool: return w["level"] == "block").is_empty(), "the right count does not block")
	var kit_free := UiModel.readiness(c, [1, 3, 4], 3).filter(func(w: Dictionary) -> bool: return w["level"] == "warn")
	check(kit_free.is_empty(), "the starting weapon means no weapon warning")
	check(c.unequip(1, "weapon") == "", "take Warden's weapon off")
	var warns := UiModel.readiness(c, [1, 3, 4], 3).filter(func(w: Dictionary) -> bool: return w["level"] == "warn")
	check(warns.size() == 1 and String(warns[0]["text"]) == "Warden has no weapon.", "now Warden is flagged (%s)" % [warns])
	var notes := UiModel.readiness(c, [3], 1).filter(func(w: Dictionary) -> bool: return w["level"] == "note")
	check(notes.any(func(w: Dictionary) -> bool: return String(w["text"]) == "Sable has no mod."), "an empty mod slot is only a note")


func test_hollows_are_never_warned_about_kit() -> void:
	var c := fresh()
	c.complete_mission("karsa_breakout", false, [1], [], [])
	check(c.slot_status(1) == "hollow", "Warden fell and a hollow stands in")
	check(UiModel.readiness(c, [1], 1).is_empty(), "a hollow carries no kit and draws no warning")


func test_the_default_squad_is_named_first_then_hollows() -> void:
	var c := fresh()
	c.complete_mission("karsa_breakout", false, [1], [], [])
	var squad := UiModel.default_squad(c, 3)
	check(squad.size() == 3 and not squad.has(1), "three picked, the hollow last (%s)" % [squad])
	check(UiModel.default_squad(c, 99).size() == c.available_slots().size(), "never more than are available")
	check(UiModel.squad_need(c, c.mission_or_card("pellam_dock")) == 4, "the mission's size when enough are left")


func test_the_prep_screen_shows_the_briefing_and_picks_a_squad_by_tapping() -> void:
	var c := fresh()
	var screen := prep(c)
	var text := all_text(screen)
	check(text.contains("Win:") and text.contains("Lose:") and text.contains("Known opposition: 3 conscript"), "the stakes and the opposition are on screen")
	check(screen.picked().size() == 3 and button(screen, "Deploy (3/3)") != null and not button(screen, "Deploy (3/3)").disabled, "a full default squad can deploy")
	var first: int = screen.picked()[0]
	screen.toggle(first)
	check(screen.picked().size() == 2 and button(screen, "Deploy (2/3)").disabled, "dropping one disables Deploy")
	var other := 0
	for slot in c.available_slots():
		if not screen.picked().has(slot):
			other = slot
			break
	screen.toggle(other)
	check(screen.picked().size() == 3, "picking another refills it")
	var extra := 0
	for slot in c.available_slots():
		if not screen.picked().has(slot):
			extra = slot
			break
	screen.toggle(extra)
	check(screen.picked().size() == 3, "a full squad refuses a fourth")
	screen.queue_free()


func test_deploy_sends_the_chosen_squad_and_the_buttons_ask_the_host() -> void:
	var c := fresh()
	var screen := prep(c, "karsa_breakout", [3, 4, 5])
	check(screen.picked() == [3, 4, 5], "a kept squad is restored")
	var got: Array = []
	screen.deploy.connect(func(slots: Array) -> void: got.append(slots))
	screen.loadout.connect(func() -> void: got.append("loadout"))
	screen.roster.connect(func() -> void: got.append("roster"))
	screen.back.connect(func() -> void: got.append("back"))
	for text in ["Deploy (3/3)", "Roster", "Back"]:
		var b := button(screen, text)
		check(b != null and b.custom_minimum_size.y >= UiTheme.MIN_TAP, "%s is there and big enough" % text)
		b.pressed.emit()
	for b in screen.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with("Loadout"):
			(b as Button).pressed.emit()
	check(got == [[3, 4, 5], "roster", "back", "loadout"], "each asks the host (%s)" % [got])
	var stale := prep(c, "karsa_breakout", [3, 99, 4, 5, 6])
	check(stale.picked() == [3, 4, 5], "a kept slot that is gone, or beyond the size, is dropped (%s)" % [stale.picked()])
	screen.queue_free()
	stale.queue_free()


func test_the_result_info_reports_resources_the_dead_and_each_merc() -> void:
	var c := fresh()
	var step := step_for(c, "karsa_breakout", true, [2], [row(1, 3, 1, 1), row(3, 2, 0, 0), row(2, 0, 0, 2, false)])
	var info := UiModel.result_info(c, step)
	check(info["verdict"] == "Complete" and info["won"], "a win is reported as one")
	var proc: Dictionary = info["deltas"][0]
	check(proc["label"] == "Procession" and proc["after"] == c.procession and proc["before"] == step["before"]["procession"], "before and after come from the step and the campaign")
	check(info["notes"].any(func(n: String) -> bool: return n.begins_with("Gran is dead")), "the dead merc is named by callsign, not as the hollow")
	var by_slot := {}
	for r: Dictionary in info["squad"]:
		by_slot[r["slot"]] = r
	check(by_slot[1]["outcome"] == "Hit 1 time" and by_slot[3]["outcome"] == "Unhurt" and by_slot[2]["outcome"] == "Fell", "each merc's outcome in words")
	check(by_slot[1]["xp_gained"] == c.xp_from_row(row(1, 3, 1, 1), true) and by_slot[2]["xp_gained"] == 0, "XP is shown for the living only")
	check(info["loot"] == ["scope"], "the salvage lists the reward")
	var lost := fresh()
	var failed := step_for(lost, "karsa_breakout", false, [], [row(1)])
	check(UiModel.result_info(lost, failed)["verdict"] == "Failed" and not UiModel.result_info(lost, failed)["won"], "a failure is reported as one")


func test_the_result_screen_lists_the_report_and_continues() -> void:
	var c := fresh()
	var step := step_for(c, "karsa_breakout", true, [2], [row(1, 3, 1, 1), row(3, 2, 0, 0), row(2, 0, 0, 2, false)])
	var screen := ResultScreen.new().setup(c, step)
	TestBase.tree.root.add_child(screen)
	var text := all_text(screen)
	check(text.contains("Complete") and text.contains("Procession") and text.contains("Reserves") and text.contains("Squad report"), "verdict, resources and the report heading")
	check(text.contains("Warden") and text.contains("Sable") and text.contains("Gran") and text.contains("Fell") and text.contains("Unhurt"), "a report row per merc")
	check(text.contains("+%d XP" % c.xp_from_row(row(1, 3, 1, 1), true)), "the XP earned is shown")
	var done := [false]
	screen.done.connect(func() -> void: done[0] = true)
	button(screen, "Continue").pressed.emit()
	check(done[0], "Continue finishes the step")
	screen.queue_free()


func test_the_salvage_screen_shows_each_find_and_offers_both_exits() -> void:
	var c := fresh()
	c.stash.append_array(["scope", "plate_carrier"])
	var screen := SalvageScreen.new().setup(c, ["scope", "plate_carrier"])
	TestBase.tree.root.add_child(screen)
	check(nodes_of(screen, "ItemCard").size() == 2 and screen.item_ids() == ["scope", "plate_carrier"], "a card per find")
	var got: Array[String] = []
	screen.equip_now.connect(func() -> void: got.append("equip"))
	screen.done.connect(func() -> void: got.append("stash"))
	button(screen, "Equip now").pressed.emit()
	button(screen, "To stash").pressed.emit()
	check(got == ["equip", "stash"], "Equip now and To stash each ask the host (%s)" % [got])
	screen.queue_free()


func test_the_chain_has_a_salvage_step_only_when_something_was_brought_back() -> void:
	var c := fresh()
	var step := step_for(c, "karsa_breakout", true, [], [row(1)])
	var chain := c.debrief_chain("karsa_breakout", step["o"], step["report"], step["before"], false)
	check(chain[1]["t"] == "salvage" and chain[1]["loot"] == ["scope"], "the reward becomes a salvage step right after the result")
	var lost := fresh()
	var failed := step_for(lost, "karsa_breakout", false, [], [row(1)])
	var kinds: Array = lost.debrief_chain("karsa_breakout", failed["o"], failed["report"], failed["before"], false).map(func(s: Dictionary) -> String: return s["t"])
	check(not kinds.has("salvage"), "a failure brings nothing back and has no salvage step (%s)" % [kinds])
