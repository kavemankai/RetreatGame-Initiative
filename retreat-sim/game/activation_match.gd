class_name ActivationMatch
extends InitiativeMatch
## The activation engine (CombatState + ActionResolver) behind the same face as InitiativeMatch,
## so the existing touch screen drives it unchanged. Every command goes through
## ActionResolver.submit; this class only translates, plays the enemy's activations through
## ActivationAI, and returns playback "beats" like its parent. It is a bridge: it goes away
## when the legacy rulesets are retired.
##
## Differences a screen must know: the active unit is one merc, not a whole side; end_turn()
## ends that merc's activation and then plays every enemy activation until a merc is active
## again; there are no automatic interrupts, only armed one-shot overwatch (4 AP).

var cs: CombatState
var ai: ActivationAI
## Beats from the enemy activations played while start() ran (the enemy can win initiative).
var opening_beats: Array[Dictionary] = []
## The reason the last refused player command was refused ("" if it was accepted).
var last_reason := ""


static func make(m: SimMatch) -> ActivationMatch:
	return ActivationMatch.new(CombatState.from_match(m))


func _init(p_cs: CombatState) -> void:
	super._init(p_cs.sim, p_cs.profiles, p_cs.assignments, p_cs.objective)
	cs = p_cs
	ai = ActivationAI.new(cs.ai_team)
	cs.capture_beats = true
	theme = cs.theme
	goal = cs.goal
	player_team = cs.player_team
	ai_team = cs.ai_team
	ap = cs.ap
	watch = cs.overwatch


func start() -> void:
	for id in cs.sim.units:
		var u: SimUnit = cs.sim.units[id]
		if u.alive and u.team == ai_team and u.watch_dir != Vector2i.ZERO:
			cs.overwatch[id] = u.watch_dir  # sentries are already looking down their lane
	ActivationScheduler.start(cs)
	opening_beats = _run_enemy_activations()
	_sync()


# --- state, as the screen reads it ----------------------------------------------------

func _sync() -> void:
	state = cs.sim
	turn = cs.round_no
	winner = cs.winner
	notices = cs.notices
	var u: SimUnit = cs.sim.units.get(cs.active_id)
	active_team = u.team if u != null else player_team


func active_unit() -> int:
	return cs.active_id


func is_suppressed(id: int) -> bool:
	return cs.suppressed.has(id)


func is_broken(id: int) -> bool:
	return cs.broken.has(id)


func can_act(id: int) -> bool:
	return not cs.is_over() and id == cs.active_id and state.units.has(id) and state.units[id].alive


## The initiative strip: the active unit first, then those still to act this round. Enemies the
## player cannot see are left out, so the strip never reveals unseen units.
func strip() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if cs.is_over():
		return out
	var seen := SimVision.visible_unit_ids(cs.sim, player_team)
	var ids: Array[int] = [cs.active_id]
	ids.append_array(cs.queue)
	for id in ids:
		var u: SimUnit = cs.sim.units.get(id)
		if u == null or not u.alive or not seen.has(id):
			continue
		out.append({"id": id, "team": u.team, "active": id == cs.active_id})
	return out


func reach(id: int) -> Dictionary:
	return ActionResolver.reach(cs, id)


func shot_preview(id: int, target_id: int) -> Dictionary:
	return ActionResolver.preview_shot(cs, id, target_id)


func path_preview(id: int, tile: Vector2i) -> Array[Vector2i]:
	var u: SimUnit = cs.sim.units.get(id)
	if u == null or not can_act(id):
		return []
	var r := SimPathing.reach(SimVision.view_for(cs.sim, u.team), u.pos, id, cs.ap_of(id))
	return SimPathing.path_to(r, tile)


## The walk to `tile` with the running AP cost. A step carries "threats": the enemies the
## player can see whose overwatch cone and range cover it (they would fire as it arrives).
func route_preview(id: int, tile: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var u: SimUnit = cs.sim.units.get(id)
	var path := path_preview(id, tile)
	if u == null or path.size() < 2:
		return out
	var seen := SimVision.visible_unit_ids(cs.sim, player_team)
	var spent := 0
	for i in range(1, path.size()):
		spent += u.step_cost(path[i] - path[i - 1])
		var threats: Array[int] = []
		for d in ActionResolver.watchers_covering(cs, u, path[i]):
			if seen.has(d.id):
				threats.append(d.id)
		out.append({"tile": path[i], "cost": spent, "threats": threats})
	return out


# --- commands ---------------------------------------------------------------------------

func move(id: int, tile: Vector2i) -> Array[Dictionary]:
	return _player(CombatAction.move_to(id, tile))


func shoot(id: int, target_id: int) -> Array[Dictionary]:
	return _player(CombatAction.shoot(id, target_id))


func hold_watch(id: int, dir: Vector2i) -> Array[Dictionary]:
	return _player(CombatAction.overwatch(id, dir))


## Ends the active merc's activation, then plays enemy activations until a merc is active.
func end_turn() -> Array[Dictionary]:
	var beats: Array[Dictionary] = []
	if cs.is_over() or not _player_active():
		return beats
	var r := ActionResolver.submit(cs, CombatAction.end_turn(cs.active_id))
	beats.append_array(r.beats)
	beats.append_array(_run_enemy_activations())
	_sync()
	return beats


func _player(a: CombatAction) -> Array[Dictionary]:
	var r := ActionResolver.submit(cs, a)
	last_reason = r.reason
	_sync()
	return r.beats


func _player_active() -> bool:
	var u: SimUnit = cs.sim.units.get(cs.active_id)
	return u != null and u.team == player_team


## Plays enemy activations through the resolver until a player unit is active or the fight ends.
func _run_enemy_activations() -> Array[Dictionary]:
	var beats: Array[Dictionary] = []
	var guard := 0
	while not cs.is_over() and not _player_active() and guard < 2000:
		guard += 1
		var a := ai.next_action(cs)
		var r := ActionResolver.submit(cs, a)
		ai.report(a, r)
		beats.append_array(r.beats)
		if not r.success:
			var forced := ActionResolver.submit(cs, CombatAction.end_turn(cs.active_id))
			beats.append_array(forced.beats)
	return beats
