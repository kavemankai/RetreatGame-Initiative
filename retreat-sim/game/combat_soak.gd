class_name CombatSoak
extends RefCounted
## Headless AI-vs-AI battles for the activation engine. Each seed builds a varied battle on the
## proving ground (random enemy kinds, roles, hollows and positions) or plays an Act 1 mission,
## runs an ActivationAI on each side, and checks CombatInvariants after every command. The numbers
## it returns are the plan's acceptance metrics: illegal actions, frozen turns, loops, idle turns,
## length, casualties, planning latency and AP/pacing telemetry.
##
## Options (all optional): {"ap": AP per activation, "enemies": enemy count, "keep_log": decision log}.

const MAX_ROUNDS := 40
const MAX_COMMANDS_PER_ACTIVATION := 80
const ENEMY_COUNTS: Array[int] = [4, 8]

var _rng := 1


## The sandbox config for `seed_`: the default squad against a seeded random enemy force of
## `enemies` units (0 = alternate 4 and 8 by seed).
static func config_for(story: Dictionary, seed_: int, enemies := 0) -> Dictionary:
	var soak := CombatSoak.new()
	soak._rng = seed_ * 7919 + 13
	var cfg := Sandbox.without_enemies(Sandbox.default_config(story))
	var map := MapData.load_file(Sandbox.MAP)
	var kinds: Array[Dictionary] = []
	for k in Sandbox.enemy_kinds(story):
		if not k["single"]:
			kinds.append(k)
	var want: int = enemies if enemies > 0 else ENEMY_COUNTS[seed_ % ENEMY_COUNTS.size()]
	var guard := 0
	while cfg["enemies"].size() < want and guard < 400:
		guard += 1
		var kind: Dictionary = kinds[soak._next(kinds.size())]
		var tile := Vector2i(Sandbox.PLAYER_ZONE_X + 1 + soak._next(map.build_state().grid.width - Sandbox.PLAYER_ZONE_X - 1), soak._next(map.build_state().grid.height))
		if Sandbox.placement_problem(story, cfg, map, tile, kind["key"]) != "":
			continue
		cfg = Sandbox.with_enemy(cfg, {"kind": kind["key"], "hollow": soak._next(4) == 0, "role": Sandbox.ROLES[soak._next(Sandbox.ROLES.size())], "pos": tile})
	return cfg


## Plays one sandbox battle to a result or a limit. Returns the metrics for it.
static func run_battle(story: Dictionary, seed_: int, keep_log := false, opts := {}) -> Dictionary:
	var built := Sandbox.build(story, config_for(story, seed_, int(opts.get("enemies", 0))))
	built.state.seed = seed_
	return _play(CombatState.from_match(built), seed_, keep_log, opts)


## Plays an Act 1 mission (its map, goal, roles and reinforcements) the same way.
static func run_mission(story: Dictionary, mission_id: String, seed_: int, keep_log := false, opts := {}) -> Dictionary:
	var campaign := Campaign.new_game(story)
	var card: Dictionary = campaign.mission_or_card(mission_id)
	var slots: Array = campaign.available_slots().slice(0, int(card["squad_size"]))
	var built := MissionBuilder.build(campaign, mission_id, slots)
	built.state.seed += seed_
	return _play(CombatState.from_match(built), seed_, keep_log, opts)


static func _play(cs: CombatState, seed_: int, keep_log: bool, opts: Dictionary) -> Dictionary:
	if opts.has("ap"):
		cs.config.max_ap = int(opts["ap"])
	var ais := {cs.player_team: ActivationAI.new(cs.player_team, keep_log), cs.ai_team: ActivationAI.new(cs.ai_team, keep_log)}
	(ais[cs.player_team] as ActivationAI).scout = true
	for id in cs.sim.units:  # the stand-in human is bold: it walks into sentries' ranges
		if (cs.sim.units[id] as SimUnit).team == cs.player_team and not cs.assignments.has(id):
			cs.assignments[id] = "aggressor"
	ActivationScheduler.start(cs)
	var start_counts := _alive(cs)
	var problems: Array[String] = []
	var commands := 0
	var frozen := false
	var first_round_dead := {}
	var in_activation := 0
	var last_active := -1
	var last_round := cs.round_no
	while not cs.is_over() and cs.round_no <= MAX_ROUNDS:
		var active := cs.active_id
		if active != last_active or cs.round_no != last_round:
			in_activation = 0
			last_active = active
			last_round = cs.round_no
		in_activation += 1
		if in_activation > MAX_COMMANDS_PER_ACTIVATION:
			frozen = true
			break
		var team: int = (cs.sim.units[active] as SimUnit).team
		var ai: ActivationAI = ais[team]
		var action := ai.next_action(cs)
		var result := ActionResolver.submit(cs, action)
		ai.report(action, result)
		commands += 1
		problems.append_array(CombatInvariants.check(cs))
		if not result.success:
			ActionResolver.submit(cs, CombatAction.end_turn(active))
		if cs.round_no >= 2 and first_round_dead.is_empty():
			first_round_dead = {"squad": start_counts[cs.player_team] - _alive(cs)[cs.player_team], "enemy": start_counts[cs.ai_team] - _alive(cs)[cs.ai_team]}
	return _summary(cs, ais, seed_, commands, frozen, problems, start_counts, first_round_dead)


static func _summary(cs: CombatState, ais: Dictionary, seed_: int, commands: int, frozen: bool, problems: Array[String], start_counts: Dictionary, first_round_dead: Dictionary) -> Dictionary:
	var out := {"seed": seed_, "enemies": start_counts[cs.ai_team], "rounds": cs.round_no, "winner": cs.winner, "finished": cs.is_over(),
		"commands": commands, "frozen": frozen, "invariant_problems": problems, "rejected": 0, "dropped": 0, "idle_with_target": 0,
		"oscillations": 0, "cap_hits": 0, "activations": 0, "idle_activations": 0, "plan_ms_p95": 0.0,
		"squad_dead": start_counts[cs.player_team] - _alive(cs)[cs.player_team],
		"enemy_dead": start_counts[cs.ai_team] - _alive(cs)[cs.ai_team], "first_round_dead": first_round_dead, "logs": [],
		"telemetry": CombatTelemetry.summarize(cs)}
	var tel: Dictionary = out["telemetry"]
	out["shots"] = tel["shots"]
	out["hits"] = tel["hits"]
	out["reactions"] = tel["reactions"]
	for team in ais:
		var ai: ActivationAI = ais[team]
		out["rejected"] += ai.rejected
		out["dropped"] += ai.dropped
		out["idle_with_target"] += ai.idle_with_target
		out["oscillations"] += ai.oscillations
		out["cap_hits"] += ai.cap_hits
		out["activations"] += ai.activations
		out["idle_activations"] += ai.idle_activations
		out["plan_ms_p95"] = maxf(out["plan_ms_p95"], ai.plan_ms_p95())
		(out["logs"] as Array).append_array(ai.log)
	return out


static func _alive(cs: CombatState) -> Dictionary:
	var out := {cs.player_team: 0, cs.ai_team: 0}
	for id in cs.sim.units:
		var u: SimUnit = cs.sim.units[id]
		if u.alive:
			out[u.team] += 1
	return out


func _next(n: int) -> int:
	_rng = (_rng * 1103515245 + 12345) & 0x7fffffff
	return (_rng >> 8) % n
