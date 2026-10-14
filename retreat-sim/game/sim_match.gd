class_name SimMatch
extends RefCounted
## The match loop. A turn is a run of TICKS_PER_TURN ticks (a SimTurn). Both
## sides plan at tick 0; once the run starts nothing stops it until the round
## ends (no checkpoints, no interrupts). Hits are handled inside the sim by
## the morale check, not by pausing.
##
## The AI plans at the start of a turn from its own fog view and never sees
## the player's orders. The player sees the current orders of enemies they
## can see. (pause()/apply_orders remain for tools and tests: a mid-turn
## replan keeps spent ticks spent and lets moves or shots under way finish.)

const NO_WINNER := -1
const DRAW := -2
const PROFILE_FILE := "res://data/ai_profiles.json"
const AI_OBJECTIVE := Vector2i(1, 5)
const PLAYABLE_SIGHT := 6
const SKIRMISH_AI_PROFILES := {4: "aggressor", 5: "aggressor", 6: "defender"}

## Reasons reported for each tick (for the log; none of them stop the run).
const REASON_SPOTTED := "spotted"
const REASON_HIT := "hit"
const REASON_IDLE := "idle"
const REASON_OVERWATCH := "overwatch"

var player_team: int
var ai_team: int
var profiles: Dictionary
var assignments: Dictionary
var objective: Vector2i
var turn := 1
## Visual theme of the terrain (a MapData theme); presentation only.
var theme := "station_deck"
## The mission goal (null = plain rout), what is waiting to arrive, and this round's messages.
var goal: SimGoal
var reinforcements: Array[Dictionary] = []  # {"round": int, "unit": SimUnit}
var notices: Array[String] = []
var winner := NO_WINNER
## The live turn; null once the match is over.
var run: SimTurn
## What the AI planned at the start of the current turn.
var ai_plan: SimPlan
var last_start: SimState
var last_plan: SimPlan
var last_result: SimResult
var last_error := ""

## The board right now (mid-turn it is the live run's state).
var state: SimState:
	get:
		return run.state if run != null else _state

var _state: SimState
var _turn_start: SimState


func _init(p_state: SimState, p_player_team: int = 0, p_profiles: Dictionary = {}, p_assignments: Dictionary = {}, p_objective: Vector2i = AI_OBJECTIVE) -> void:
	_state = p_state
	player_team = p_player_team
	ai_team = 1 - p_player_team
	profiles = p_profiles
	assignments = p_assignments
	objective = p_objective
	_check_winner()
	_begin_turn()


## The 3v3 skirmish map with shortened sight so fog matters.
static func skirmish(seed: int = 1) -> SimMatch:
	var s := Scenarios.skirmish_state()
	s.seed = seed
	for id in s.units:
		(s.units[id] as SimUnit).sight_range = PLAYABLE_SIGHT
	var loaded := SimAIProfile.load_file(PROFILE_FILE)
	return SimMatch.new(s, 0, loaded["profiles"], SKIRMISH_AI_PROFILES)


func is_over() -> bool:
	return winner != NO_WINNER


## The orders enemies the player can currently see are carrying out.
## Hidden enemies' orders are never included.
func enemy_intent() -> SimPlan:
	var out := SimPlan.new()
	if run == null:
		return out
	for id in SimVision.visible_unit_ids(state, player_team):
		if (state.units[id] as SimUnit).team == ai_team:
			for a: SimAction in run.remaining_actions(id):
				out.add(id, a)
	return out


## Replace the player's future orders: {unit id -> Array[SimAction]}. All or
## nothing. Returns "" or the reason it was refused.
func apply_orders(orders: Dictionary) -> String:
	last_error = ""
	if run == null:
		last_error = "The match is over."
		return last_error
	var plan := SimPlan.new()
	for id in orders:
		var u: SimUnit = state.units.get(id)
		if u == null or u.team != player_team:
			last_error = "unit %d is not yours" % id
			return last_error
		for a in orders[id]:
			plan.add(id, a)
	var fog_errors := plan.validate_fog(state)
	if not fog_errors.is_empty():
		last_error = "; ".join(fog_errors)
		return last_error
	for id in orders:
		var err := run.can_replace(id, orders[id])
		if err != "":
			last_error = err
			return err
	for id in orders:
		run.replace_orders(id, orders[id])
	return ""


## Resolve one tick. Returns {events, reasons, finished, tick, pause, idle};
## `pause` is true only when the round (or match) is over. `reasons` notes
## what happened (see REASON_*) for the log.
func step() -> Dictionary:
	if run == null:
		return {"events": [], "reasons": [], "finished": true, "tick": 0, "pause": true, "idle": true}
	var seen_before := SimVision.visible_unit_ids(state, player_team)
	var events := run.advance()
	var reasons := _pause_reasons(events, seen_before)
	_check_winner()
	var tick := run.tick
	var finished := run.is_finished() or is_over()
	var idle := not run.has_active_orders()
	if finished:
		_finish_run()
	return {"events": events, "reasons": reasons, "finished": finished, "tick": tick,
		"pause": finished, "idle": idle}


## The player has stopped the action: the AI re-decides from its own view.
func pause() -> void:
	if run == null or run.tick == 0 or run.is_finished():
		return
	var live := {}
	for id in state.units:
		var u: SimUnit = state.units[id]
		if u.alive and u.team == ai_team and not run.is_broken(id):
			live[id] = {"free_at": run.free_at(id), "pos": run.projected_pos(id)}
	var plan := SimAI.plan_for(state, ai_team, profiles, assignments, objective, live)
	for id in live:
		var orders: Array = plan.orders.get(id, [])
		# A plan that somehow does not fit must never leave stale orders behind.
		if run.replace_orders(id, orders) != "":
			run.replace_orders(id, [])


## Whole-turn convenience (tests, quick play): apply the orders, run to the end.
func submit(player_plan: SimPlan) -> SimResult:
	last_error = ""
	if is_over():
		last_error = "The match is over."
		return null
	var orders := {}
	for id in player_plan.orders:
		orders[id] = player_plan.orders[id]
	if apply_orders(orders) != "":
		return null
	var ai_orders := ai_plan
	var this_turn := turn
	while turn == this_turn and not is_over():
		step()
	last_plan = player_plan.merged(ai_orders)
	return last_result


func _pause_reasons(events: Array[Dictionary], seen_before: Array[int]) -> Array[String]:
	var out: Array[String] = []
	var seen_now := SimVision.visible_unit_ids(state, player_team)
	for id in seen_now:
		if not seen_before.has(id) and (state.units[id] as SimUnit).team == ai_team:
			out.append(REASON_SPOTTED)
			break
	for ev in events:
		if ev["type"] == "shot" and ev["result"] == "hit" and (state.units[ev["target"]] as SimUnit).team == player_team:
			out.append(REASON_HIT)
			break
	for id in run.last_idle:
		if (state.units[id] as SimUnit).team == player_team:
			out.append(REASON_IDLE)
			break
	for ev in events:
		if ev["type"] == "shot" and ev.get("overwatch", false) and _involves_player(ev, seen_now):
			out.append(REASON_OVERWATCH)
			break
	return out


func _involves_player(ev: Dictionary, seen: Array[int]) -> bool:
	for key in ["unit", "target"]:
		if (state.units[ev[key]] as SimUnit).team == player_team or seen.has(ev[key]):
			return true
	return false


func _finish_run() -> void:
	run.end_early()
	_state = run.state
	notices.clear()
	if goal != null:
		notices.append_array(goal.round_end(_state, player_team))
	last_result = run.result()
	last_plan = ai_plan
	last_start = _turn_start
	run = null
	turn += 1
	_check_winner()
	_begin_turn()


func _begin_turn() -> void:
	if is_over():
		run = null
		ai_plan = SimPlan.new()
		return
	_spawn_reinforcements()
	_turn_start = state
	ai_plan = SimAI.plan_for(state, ai_team, profiles, assignments, objective)
	run = SimTurn.new(state, ai_plan, true)


## Units whose round has come arrive on their tile, or the nearest free one.
func _spawn_reinforcements() -> void:
	var arrived := 0
	var rest: Array[Dictionary] = []
	for r in reinforcements:
		if int(r["round"]) > turn:
			rest.append(r)
			continue
		var u: SimUnit = r["unit"]
		u.pos = _free_tile_near(u.pos)
		_state.add_unit(u)
		arrived += 1
	reinforcements = rest
	if arrived > 0:
		notices.append("Reinforcements arrive (%d)." % arrived)


func _free_tile_near(tile: Vector2i) -> Vector2i:
	for radius in 6:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var t := tile + Vector2i(dx, dy)
				if _state.grid.in_bounds(t) and not _state.grid.is_blocked(t) and _state.unit_at(t) == null:
					return t
	return tile


func _check_winner() -> void:
	if goal != null and goal.won:
		winner = player_team
		return
	var mine := 0
	var theirs := 0
	for id in state.units:
		var u: SimUnit = state.units[id]
		if u.alive:
			if u.team == player_team:
				mine += 1
			else:
				theirs += 1
	if mine > 0 and theirs > 0:
		winner = NO_WINNER
	elif mine > 0:
		winner = player_team
	elif theirs > 0:
		winner = ai_team
	else:
		winner = DRAW
