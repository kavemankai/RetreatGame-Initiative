extends SceneTree
## Plays whole campaigns on the activation engine (the one the game ships) with the AI on both sides
## and reports how far each run gets. The stand-in squad never changes gear or levels up, so this is a
## floor for what a person can do, not a balance target.
##   godot --headless --path . -s tools/soak_activation_campaign.gd -- --runs=10 --difficulty=story
## Prints one line per run (missions played, ending state) and a summary. Exit 1 on an engine problem.


func _init() -> void:
	var runs := 6
	var difficulty := "standard"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--runs="):
			runs = int(a.substr(7))
		elif a.begins_with("--difficulty="):
			difficulty = a.substr(13)
	var story: Dictionary = StoryData.load_dir("res://data/story")["data"]
	var finished := 0
	var problems := 0
	var reasons := {}
	var mission_total := 0
	for run in runs:
		var r := CombatSoak.run_campaign(story, 1000 * (run + 1), 14, {"difficulty": difficulty})
		var c: Campaign = r["campaign"]
		mission_total += int(r["missions_played"])
		problems += (r["problems"] as Array).size()
		var state := "finished" if c.finished else ("over:" + c.over_reason if c.over else "unfinished")
		reasons[state] = int(reasons.get(state, 0)) + 1
		if c.finished:
			finished += 1
		print("run %d: %d missions, %s (procession %d, reserves %d)" % [run, r["missions_played"], state, c.procession, c.reserves])
		for p in r["problems"]:
			printerr("  problem: ", p)
	print("difficulty %s: %d of %d campaigns reached the ending | avg missions %.1f | %s | engine problems %d" % [difficulty, finished, runs, float(mission_total) / runs, reasons, problems])
	quit(1 if problems > 0 else 0)
