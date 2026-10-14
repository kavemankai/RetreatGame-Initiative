extends SceneTree
## Balance probe: plays every story mission AI-vs-AI (a fresh campaign each,
## the first available mercs as the squad) across many morale/hit seeds and
## prints wins, losses, timeouts and average deaths per mission and per act.
## The player side is the crude auto-AI, so read results as a regression
## gauge, not a measure of human play.
##   godot --headless --path . -s tools/balance_probe.gd
##   godot --headless --path . -s tools/balance_probe.gd -- --seeds=20 --mission=karsa_breakout

const DEFAULT_SEEDS := 40
const MAX_TURNS := 25  # real play has no turn limit; this only stops a stalemate


func _init() -> void:
	var seeds := DEFAULT_SEEDS
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.substr(8))
		elif a.begins_with("--mission="):
			only = a.substr(10)
	var story: Dictionary = StoryData.load_dir("res://data/story")["data"]
	var profiles: Dictionary = SimAIProfile.load_file("res://data/ai_profiles.json")["profiles"]
	var by_act := {}
	for m: Dictionary in story["route"]["missions"]:
		if only != "" and m["id"] != only:
			continue
		var r := _probe(story, profiles, m["id"], seeds)
		print("act %d %-18s win %3d%%  loss %2d  timeout %2d  deaths/run %.2f  enemy kills/run %.2f" % [
			int(m["act"]), m["id"], r["win"] * 100 / seeds, r["loss"], r["timeout"],
			float(r["p_dead"]) / seeds, float(r["e_dead"]) / seeds])
		var act: Dictionary = by_act.get(int(m["act"]), {"win": 0, "runs": 0, "dead": 0})
		act["win"] += r["win"]
		act["runs"] += seeds
		act["dead"] += r["p_dead"]
		by_act[int(m["act"])] = act
	for act in by_act:
		var a: Dictionary = by_act[act]
		print("ACT %d: %d%% wins, %.2f player deaths per mission" % [act, a["win"] * 100 / a["runs"], float(a["dead"]) / (a["runs"])])
	quit()


func _probe(story: Dictionary, profiles: Dictionary, id: String, seeds: int) -> Dictionary:
	var tally := {"win": 0, "loss": 0, "timeout": 0, "p_dead": 0, "e_dead": 0}
	for seed in range(1, seeds + 1):
		var c := Campaign.new_game(story)
		var m := c.mission_or_card(id)
		var slots: Array = c.available_slots().slice(0, int(m["squad_size"]))
		var mt := MissionBuilder.build(c, id, slots)
		mt.state.seed = seed
		mt.run.state.seed = seed
		var turns := 0
		while not mt.is_over() and turns < MAX_TURNS:
			turns += 1
			if mt.submit(SimAI.plan_for(mt.state, 0, profiles, {}, Vector2i(10, 5))) == null:
				break
		if not mt.is_over():
			tally["timeout"] += 1
		elif mt.winner == 0:
			tally["win"] += 1
		else:
			tally["loss"] += 1
		for uid in mt.state.units:
			var u: SimUnit = mt.state.units[uid]
			if not u.alive:
				tally["p_dead" if u.team == 0 else "e_dead"] += 1
	return tally
