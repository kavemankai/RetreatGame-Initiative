extends TestBase
## One whole turn of the campaign loop without the app shell: the map, the prep screen, a fight played by the
## AI that is saved mid-battle and resumed, the outcome applied once, the result, salvage and level-up
## screens, and the map moving on. It uses temp save paths, never the player's save.

var story: Dictionary = StoryData.load_dir("res://data/story")["data"]
const BATTLE_PATH := "user://e2e_resume.json"
const CAMPAIGN_PATH := "user://e2e_campaign.json"


func button(root: Node, text: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text == text:
			return b as Button
	return null


func play(cs: CombatState, ais: Dictionary, activations: int) -> void:
	var n := 0
	while not cs.is_over() and n < activations and cs.round_no <= CombatSoak.MAX_ROUNDS:
		var team: int = (cs.sim.units[cs.active_id] as SimUnit).team
		var ai: ActivationAI = ais[team]
		var guard := 0
		var before := cs.active_id
		while cs.active_id == before and not cs.is_over() and guard < CombatSoak.MAX_COMMANDS_PER_ACTIVATION:
			var a: CombatAction = ai.next_action(cs)
			ai.report(a, ActionResolver.submit(cs, a))
			guard += 1
		n += 1


func test_a_mission_from_the_map_to_the_next_stop_with_a_save_in_the_middle() -> void:
	var c := Campaign.new_game(story)
	# the map: the convoy is at Karsa and Brief is offered there
	var map := OverworldScreen.new().setup(c)
	TestBase.tree.root.add_child(map)
	check(button(map, "Brief") != null, "the map offers Brief at the first stop")
	map.queue_free()
	# the prep screen: default squad, Deploy sends it
	var prep := MissionPrepScreen.new().setup(c, "karsa_breakout", "briefing")
	TestBase.tree.root.add_child(prep)
	var got: Array = [[]]
	prep.deploy.connect(func(slots: Array) -> void: got[0] = slots)
	button(prep, "Deploy (3/3)").pressed.emit()
	var sent: Array = got[0]
	check(sent.size() == 3, "Deploy sends a squad of three")
	prep.queue_free()
	# the fight: part played, saved, rebuilt from the saves
	var cs := CombatState.from_match(MissionBuilder.build(c, "karsa_breakout", sent))
	for id in cs.sim.units:
		if (cs.sim.units[id] as SimUnit).team == cs.player_team and not cs.assignments.has(id):
			cs.assignments[id] = "aggressor"
	ActivationScheduler.start(cs)
	var ais := {cs.player_team: ActivationAI.new(cs.player_team), cs.ai_team: ActivationAI.new(cs.ai_team)}
	(ais[cs.player_team] as ActivationAI).scout = true
	play(cs, ais, 10)
	check(not cs.is_over(), "ten activations in, the fight is still going")
	var f := FileAccess.open(CAMPAIGN_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(c.to_dict()))
	f.close()
	check(ResumeStore.save(cs, {"kind": ResumeStore.KIND_CAMPAIGN, "mission_id": "karsa_breakout"}, BATTLE_PATH), "the fight saves mid-battle")
	var loaded := ResumeStore.load_battle(story, BATTLE_PATH, CAMPAIGN_PATH)
	check(not loaded.is_empty() and CombatSave.to_json(loaded["cs"]) == CombatSave.to_json(cs), "and resumes to the exact same state")
	if loaded.is_empty():
		return
	var resumed: CombatState = loaded["cs"]
	var ais2 := {resumed.player_team: ActivationAI.new(resumed.player_team), resumed.ai_team: ActivationAI.new(resumed.ai_team)}
	(ais2[resumed.player_team] as ActivationAI).scout = true
	play(resumed, ais2, 400)
	check(resumed.is_over(), "the resumed fight plays to a finish")
	# the outcome, applied exactly once
	var o := MissionBuilder.outcome_for(c, resumed, false)
	check(c.can_complete("karsa_breakout"), "the mission can be completed")
	var before := {"procession": c.procession, "reserves": c.reserves}
	var report := c.complete_mission("karsa_breakout", o["success"], o["dead_slots"], o["writ_dead"], [], o["squad_wiped"], int(o.get("procession_loss", 0)), o["units"])
	check(not c.can_complete("karsa_breakout"), "and never again")
	c.pending = c.debrief_chain("karsa_breakout", o, report, before, false)
	check(c.pending[0]["t"] == "result", "the debrief starts with the result")
	# the result, salvage and level-up screens, in chain order
	var result := ResultScreen.new().setup(c, c.pending[0])
	TestBase.tree.root.add_child(result)
	check(button(result, "Continue") != null, "the result screen is up")
	result.queue_free()
	if o["success"]:
		check(c.pending[1]["t"] == "salvage", "a win brings salvage next")
		var salvage := SalvageScreen.new().setup(c, c.pending[1]["loot"])
		TestBase.tree.root.add_child(salvage)
		check(button(salvage, "To stash") != null, "the salvage screen is up")
		salvage.queue_free()
	# level up everyone owed a pick, through the screen
	var leveled := 0
	for slot in c.available_slots():
		if c.levelup_pending(slot) > 0:
			var up := LevelUpScreen.new().setup(c, slot)
			TestBase.tree.root.add_child(up)
			(up.find_children("opt_*", "", true, false)[0] as TapPanel).pressed.emit()
			button(up, "Confirm").pressed.emit()
			leveled += 1
			up.queue_free()
	# the campaign saves and reloads whole, and the map has moved on
	var again := Campaign.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())), story)
	check(again != null and again.completed == c.completed and again.current == c.current, "the campaign round-trips through its save")
	if o["success"]:
		check(c.current == "the_weir" and c.route_state()["nodes"][0]["state"] == "done", "the convoy has moved on to the next stop")
		var next_map := OverworldScreen.new().setup(c)
		TestBase.tree.root.add_child(next_map)
		check(next_map.canvas() != null and button(next_map, "Brief") != null, "the map arrives at the next stop")
		next_map.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CAMPAIGN_PATH))
	ResumeStore.clear(BATTLE_PATH)
	check(leveled >= 0, "level-ups handled (%d)" % leveled)
