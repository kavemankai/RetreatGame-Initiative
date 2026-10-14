extends SceneTree
## Headless AI-vs-AI soak of the activation engine (see CombatSoak). Prints one summary and, with
## --verbose, one line per battle. Exits 1 if any battle breaks an invariant, submits an illegal
## action, freezes or fails to finish.
##   godot --headless --path . -s tools/soak_combat.gd -- --battles=100
##   godot --headless --path . -s tools/soak_combat.gd -- --battles=250 --first=500 --enemies=4
##   godot --headless --path . -s tools/soak_combat.gd -- --battles=40 --ap=10
##   godot --headless --path . -s tools/soak_combat.gd -- --battles=5 --mission=pellam_dock
## --weapons=id,id,id,id puts those weapons in the squad's four hands (try minigun,frag_launcher,laser_rifle,long_rifle).
## --enemies=N fixes the enemy count (default alternates 4 and 8); --ap=N overrides AP per
## activation; --mission=ID plays an Act 1 mission instead of a random sandbox battle.

const SUM_KEYS: Array[String] = ["rejected", "dropped", "idle_with_target", "oscillations", "cap_hits", "activations", "idle_activations",
	"rounds", "squad_dead", "enemy_dead"]
const TEL_KEYS: Array[String] = ["ap_offered", "ap_spent", "ap_forfeited", "shots", "hits", "reactions", "steps", "actions"]


func _init() -> void:
	var battles := 100
	var first := 0
	var verbose := false
	var mission := ""
	var opts := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--battles="):
			battles = int(a.substr(10))
		elif a.begins_with("--first="):
			first = int(a.substr(8))
		elif a.begins_with("--enemies="):
			opts["enemies"] = int(a.substr(10))
		elif a.begins_with("--ap="):
			opts["ap"] = int(a.substr(5))
		elif a.begins_with("--mission="):
			mission = a.substr(10)
		elif a.begins_with("--weapons="):
			opts["weapons"] = a.substr(10).split(",")
		elif a == "--verbose":
			verbose = true
	var story: Dictionary = StoryData.load_dir("res://data/story")["data"]
	var totals := {"finished": 0, "frozen": 0, "problems": 0, "squad_wins": 0, "first_round_squad_dead": 0, "first_round_enemy_dead": 0}
	for k in SUM_KEYS + TEL_KEYS:
		totals[k] = 0
	var worst_ms := 0.0
	var started := Time.get_ticks_msec()
	for i in battles:
		var r: Dictionary = CombatSoak.run_mission(story, mission, first + i, false, opts) if mission != "" else CombatSoak.run_battle(story, first + i, false, opts)
		totals["finished"] += int(r["finished"])
		totals["frozen"] += int(r["frozen"])
		totals["problems"] += (r["invariant_problems"] as Array).size()
		for k in SUM_KEYS:
			totals[k] += int(r[k])
		for k in TEL_KEYS:
			totals[k] += int((r["telemetry"] as Dictionary)[k])
		totals["squad_wins"] += int(r["winner"] == 0)
		totals["first_round_squad_dead"] += int(r["first_round_dead"].get("squad", 0))
		totals["first_round_enemy_dead"] += int(r["first_round_dead"].get("enemy", 0))
		worst_ms = maxf(worst_ms, r["plan_ms_p95"])
		if verbose or not r["finished"] or r["frozen"] or not (r["invariant_problems"] as Array).is_empty() or r["rejected"] > 0:
			print("seed %d: 4v%d winner %d rounds %d cmds %d dead %d/%d rej %d drop %d idle+tgt %d osc %d caps %d%s" % [r["seed"], r["enemies"], r["winner"], r["rounds"], r["commands"], r["squad_dead"], r["enemy_dead"], r["rejected"], r["dropped"], r["idle_with_target"], r["oscillations"], r["cap_hits"], " FROZEN" if r["frozen"] else ""])
	var n := float(battles)
	print("battles %d, finished %d, frozen %d, invariant problems %d, illegal actions %d" % [battles, totals["finished"], totals["frozen"], totals["problems"], totals["rejected"]])
	print("squad wins %d | avg rounds %.1f | avg dead squad %.2f enemy %.2f | first-round dead squad %.2f enemy %.2f" % [totals["squad_wins"], totals["rounds"] / n, totals["squad_dead"] / n, totals["enemy_dead"] / n, totals["first_round_squad_dead"] / n, totals["first_round_enemy_dead"] / n])
	print("activations %d | idle %d (%.0f%%) | idle with a target in range %d | stale steps dropped %d | oscillations %d | cap hits %d" % [totals["activations"], totals["idle_activations"], 100.0 * totals["idle_activations"] / maxf(1.0, totals["activations"]), totals["idle_with_target"], totals["dropped"], totals["oscillations"], totals["cap_hits"]])
	var acts := maxf(1.0, float(totals["activations"]))
	print("AP wasted %.0f%% | shots/activation %.2f | steps/activation %.2f | actions/activation %.2f | hit %.0f%% | reaction shots %d" % [100.0 * totals["ap_forfeited"] / maxf(1.0, totals["ap_offered"]), totals["shots"] / acts, totals["steps"] / acts, totals["actions"] / acts, 100.0 * totals["hits"] / maxf(1.0, totals["shots"]), totals["reactions"]])
	print("worst p95 plan %.1f ms | %.1f s" % [worst_ms, (Time.get_ticks_msec() - started) / 1000.0])
	var bad: bool = totals["finished"] != battles or totals["frozen"] > 0 or totals["problems"] > 0 or totals["rejected"] > 0
	quit(1 if bad else 0)
