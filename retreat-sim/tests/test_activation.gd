extends TestBase
## The activation engine: a round queue by initiative, one activation per unit per round,
## typed actions through one resolver, an AP ledger and invariants checked after every command.

var story: Dictionary = StoryData.load_dir("res://data/story")["data"]


func new_cs(units: Array, seed_ := 7) -> CombatState:
	var s := make_state(16, 12)
	s.seed = seed_
	for u: Array in units:  # [id, team, pos, speed, aim]
		add_unit(s, u[0], u[1], u[2], 3, u[3], u[4])
	var cs := CombatState.create(s)
	ActivationScheduler.start(cs)
	return cs


func sig(cs: CombatState) -> String:
	var parts: Array[String] = []
	for e: Dictionary in cs.log:
		parts.append(str(e))
	return "|".join(parts)


func test_config_loads_from_data_and_falls_back_to_defaults() -> void:
	var cfg := CombatConfig.load_file()
	check(cfg.max_ap == 14 and cfg.overwatch_cost == 4, "data/combat/ap_costs.json holds the AP budget and overwatch cost")
	var fallback := CombatConfig.load_file("res://data/combat/missing.json")
	check(fallback.max_ap == SimConst.AP_PER_TURN, "a missing file falls back to the built-in defaults")


func test_queue_is_sorted_by_initiative_across_teams() -> void:
	var cs := new_cs([[1, 0, Vector2i(1, 1), 5, 5], [2, 0, Vector2i(1, 3), 3, 5], [200, 1, Vector2i(12, 1), 7, 5], [201, 1, Vector2i(12, 3), 4, 5]])
	check(cs.round_no == 1 and cs.phase == CombatState.Phase.AWAIT_COMMAND, "round 1, awaiting a command")
	var seen: Array[int] = [cs.active_id]
	for i in 3:
		ActionResolver.submit(cs, CombatAction.end_turn(cs.active_id))
		seen.append(cs.active_id)
	check(seen == [200, 1, 201, 2], "enemy and squad interleave by speed*10+aim; got %s" % [seen])


func test_ties_break_on_a_seeded_value_then_unit_id_and_replay_identically() -> void:
	var firsts := {}
	for sd in 40:
		var a := new_cs([[1, 0, Vector2i(1, 1), 5, 5], [2, 0, Vector2i(1, 3), 5, 5], [200, 1, Vector2i(12, 1), 1, 1]], sd)
		var b := new_cs([[1, 0, Vector2i(1, 1), 5, 5], [2, 0, Vector2i(1, 3), 5, 5], [200, 1, Vector2i(12, 1), 1, 1]], sd)
		check(a.active_id == b.active_id, "same seed, same order (seed %d)" % sd)
		firsts[a.active_id] = true
	check(firsts.has(1) and firsts.has(2), "different seeds break the tie differently")


func test_each_unit_activates_once_per_round_then_the_next_round_begins() -> void:
	var cs := new_cs([[1, 0, Vector2i(1, 1), 5, 5], [2, 0, Vector2i(1, 3), 4, 5], [200, 1, Vector2i(12, 1), 6, 5]])
	var order: Array[int] = []
	for i in 3:
		order.append(cs.active_id)
		check(CombatInvariants.check(cs).is_empty(), "invariants hold mid-round: %s" % [CombatInvariants.check(cs)])
		ActionResolver.submit(cs, CombatAction.end_turn(cs.active_id))
	order.sort()
	check(order == [1, 2, 200], "all three acted exactly once")
	check(cs.round_no == 2, "then round 2 began")
	check(cs.activations.size() == 1 and int(cs.activations[cs.active_id]) == 1, "round 2 has one activation so far")


func test_a_unit_killed_before_its_turn_is_skipped() -> void:
	var cs := new_cs([[1, 0, Vector2i(1, 1), 9, 5], [2, 0, Vector2i(1, 3), 4, 5], [200, 1, Vector2i(12, 1), 6, 5]])
	check(cs.active_id == 1, "the fastest acts first")
	cs.sim.units[200].alive = false
	ActionResolver.submit(cs, CombatAction.end_turn(1))
	check(cs.active_id == 2, "the dead unit's slot is skipped")


func test_ap_refills_at_activation_and_expires_at_its_end() -> void:
	var cs := new_cs([[1, 0, Vector2i(1, 1), 9, 5], [200, 1, Vector2i(12, 1), 6, 5]])
	var pool := cs.config.max_ap
	check(cs.ap_of(1) == pool and cs.ap_of(200) == 0, "only the active unit holds AP")
	ActionResolver.submit(cs, CombatAction.move_to(1, Vector2i(3, 1)))
	check(cs.ap_of(1) == pool - 2 * SimConst.COST_ORTHO, "two steps spend 4 AP")
	ActionResolver.submit(cs, CombatAction.end_turn(1))
	check(cs.ap_of(1) == 0 and cs.ap_of(200) == pool, "unused AP expired; the next unit has a full pool")
	var s := make_state()
	var u := add_unit(s, 5, 0, Vector2i(1, 1), 3, 9, 5)
	add_unit(s, 6, 1, Vector2i(9, 9), 3, 1, 1)
	u.stress_penalty = 4
	var stressed := CombatState.create(s)
	ActivationScheduler.start(stressed)
	check(stressed.ap_of(5) == pool - 4, "stress still shortens the pool")


func test_rejected_actions_change_nothing_and_say_why() -> void:
	var cs := new_cs([[1, 0, Vector2i(1, 1), 9, 5], [2, 0, Vector2i(1, 3), 4, 5], [200, 1, Vector2i(7, 1), 6, 5]])
	var before := sig(cs)
	var ledger_before := cs.ledger.size()
	var snap := snapshot(cs.sim)
	var r := ActionResolver.submit(cs, CombatAction.move_to(2, Vector2i(2, 3)))
	check(not r.success and r.reason == "not_your_activation", "an off-turn ally cannot be commanded: %s" % r.reason)
	cs.ap[1] = 3
	r = ActionResolver.submit(cs, CombatAction.shoot(1, 200))
	check(not r.success and r.reason == "not_enough_ap", "3 AP cannot buy a 4 AP shot: %s" % r.reason)
	r = ActionResolver.submit(cs, CombatAction.move_to(1, Vector2i(5, 1)))
	check(not r.success and r.reason == "not_enough_ap", "a reachable-with-more-AP tile reports not_enough_ap: %s" % r.reason)
	r = ActionResolver.submit(cs, CombatAction.move_to(1, Vector2i(1, 1)))
	check(not r.success and r.reason == "unreachable", "standing still is not a move: %s" % r.reason)
	r = ActionResolver.submit(cs, CombatAction.overwatch(1, Vector2i.ZERO))
	check(not r.success and r.reason == "invalid_direction", "overwatch needs a facing")
	check(cs.ledger.size() == ledger_before and snapshot(cs.sim) == snap and sig(cs) == before, "no rejection left any trace")
	check(cs.ap_of(1) == 3, "and AP is exactly what it was")


func test_hidden_enemies_cannot_be_shot() -> void:
	var cs := new_cs([[1, 0, Vector2i(1, 1), 9, 5], [200, 1, Vector2i(9, 1), 6, 5]])
	cs.sim.units[1].sight_range = 3
	cs.sim.units[1].weapon_range = 9
	var r := ActionResolver.submit(cs, CombatAction.shoot(1, 200))
	check(not r.success and r.reason == "not_visible", "in weapon range but outside sight: refused; got %s" % r.reason)


func test_accepted_actions_post_a_ledger_that_adds_up() -> void:
	var cs := new_cs([[1, 0, Vector2i(2, 2), 9, 5], [200, 1, Vector2i(6, 2), 6, 5]])
	var pool := cs.config.max_ap
	var r := ActionResolver.submit(cs, CombatAction.shoot(1, 200))
	check(r.success and r.ap_before == pool and r.cost == 4 and r.ap_after == pool - 4, "shot: %d -> %d -> %d" % [r.ap_before, r.cost, r.ap_after])
	check(cs.sim.units[200].hp == 2, "test dice always hit")
	ActionResolver.submit(cs, CombatAction.overwatch(1, Vector2i.RIGHT))
	check(cs.ledger.size() == 2 and cs.ledger[1]["type"] == "overwatch", "each accepted action is one ledger entry")
	for e: Dictionary in cs.ledger:
		check(int(e["ap_before"]) - int(e["cost"]) == int(e["ap_after"]) and int(e["cost"]) >= 0, "ledger row adds up: %s" % [e])


func test_overwatch_costs_ap_is_not_refunded_and_expires_at_the_next_activation() -> void:
	var cs := new_cs([[1, 0, Vector2i(2, 2), 9, 5], [200, 1, Vector2i(12, 8), 6, 5]])
	var pool := cs.config.max_ap
	var r := ActionResolver.submit(cs, CombatAction.overwatch(1, Vector2i.RIGHT))
	check(r.success and r.cost == 4 and cs.ap_of(1) == pool - 4 and cs.overwatch.has(1), "armed for 4 AP")
	ActionResolver.submit(cs, CombatAction.end_turn(1))
	check(cs.overwatch.has(1), "it stays armed through the other side's activation")
	ActionResolver.submit(cs, CombatAction.end_turn(200))
	check(cs.active_id == 1 and not cs.overwatch.has(1) and cs.ap_of(1) == pool, "it expires when the owner's next activation begins, with no refund beyond the normal refill")


func test_the_last_enemy_dying_ends_the_encounter_cleanly() -> void:
	var cs := new_cs([[1, 0, Vector2i(2, 2), 9, 5], [2, 0, Vector2i(2, 4), 8, 5], [200, 1, Vector2i(6, 2), 6, 5]])
	cs.sim.units[200].hp = 1
	var r := ActionResolver.submit(cs, CombatAction.shoot(1, 200))
	check(r.success and cs.phase == CombatState.Phase.ENDED and cs.winner == 0, "victory ends the scheduler")
	check(cs.active_id == -1, "nobody is active afterwards")
	var late := ActionResolver.submit(cs, CombatAction.end_turn(2))
	check(not late.success and late.reason == "encounter_over", "no further command is accepted")
	check(CombatInvariants.check(cs).is_empty(), "invariants hold at the end")


func test_the_invariant_checker_catches_corruption() -> void:
	var cs := new_cs([[1, 0, Vector2i(2, 2), 9, 5], [200, 1, Vector2i(6, 2), 6, 5]])
	check(CombatInvariants.check(cs).is_empty(), "a fresh state is clean")
	cs.ap[1] = -1
	check(not CombatInvariants.check(cs).is_empty(), "negative AP is caught")
	cs.ap[1] = cs.config.max_ap + 1
	check(not CombatInvariants.check(cs).is_empty(), "AP over the pool is caught")
	cs.ap[1] = 5
	cs.activations[1] = 2
	check(not CombatInvariants.check(cs).is_empty(), "a double activation is caught")
	cs.activations[1] = 1
	cs.sim.units[200].pos = cs.sim.units[1].pos
	check(not CombatInvariants.check(cs).is_empty(), "two units on one tile is caught")
	cs.sim.units[200].pos = Vector2i(6, 2)
	cs.sim.units[1].alive = false
	check(not CombatInvariants.check(cs).is_empty(), "a dead active unit is caught")


func test_reinforcements_join_at_the_start_of_the_round_they_are_due() -> void:
	var s := make_state(16, 12)
	add_unit(s, 1, 0, Vector2i(2, 2), 3, 9, 5)
	add_unit(s, 200, 1, Vector2i(12, 8), 3, 6, 5)
	var cs := CombatState.create(s)
	var extra := SimUnit.make(201, 1, Vector2i(13, 9), 3, 5, 5, 5)
	cs.reinforcements.append({"round": 2, "unit": extra})
	ActivationScheduler.start(cs)
	check(not cs.sim.units.has(201), "not yet in round 1")
	ActionResolver.submit(cs, CombatAction.end_turn(cs.active_id))
	ActionResolver.submit(cs, CombatAction.end_turn(cs.active_id))
	check(cs.round_no == 2 and cs.sim.units.has(201), "present when round 2 begins")
	var ids: Array[int] = []
	for e: Dictionary in cs.order:
		ids.append(int(e["id"]))
	check(ids.has(201) and CombatInvariants.check(cs).is_empty(), "and it is in that round's queue")


func test_legacy_shot_resolution_is_shared_with_the_initiative_match() -> void:
	# Both engines call ShotResolver, so the same shot gives the same events and damage.
	var a := make_state(16, 12)
	add_unit(a, 1, 0, Vector2i(2, 2))
	add_unit(a, 200, 1, Vector2i(6, 2))
	var b := a.clone()
	var ev_a := ShotResolver.fire(a, a.units[1], 200, 1, 1, true)
	var m := InitiativeMatch.new(b)
	m.start()
	m.ap[1] = 14
	var ev_b: Array = []
	for beat in m.shoot(1, 200):
		ev_b.append_array(beat["events"])
	check(ev_a[0]["result"] == ev_b[0]["result"] and a.units[200].hp == m.state.units[200].hp, "same result and damage")


func scripted_fight(sd: int) -> Dictionary:
	var cfg := Sandbox.default_config(story)
	var built := Sandbox.build(story, cfg)
	built.state.seed = sd
	var cs := CombatState.from_match(built)
	ActivationScheduler.start(cs)
	var commands := 0
	var problems: Array[String] = []
	while cs.phase != CombatState.Phase.ENDED and commands < 4000 and cs.round_no <= 60:
		var act := _scripted_turn(cs, problems)
		commands += act
	return {"cs": cs, "commands": commands, "problems": problems}


## A simple deterministic policy: shoot something visible if affordable, else close the
## distance, else end the turn. Every command is checked by the invariant helper.
func _scripted_turn(cs: CombatState, problems: Array[String]) -> int:
	var id := cs.active_id
	var count := 0
	for guard in 12:
		var u: SimUnit = cs.sim.units[id]
		var visible := SimVision.visible_unit_ids(cs.sim, u.team)
		var best := -1
		for tid in visible:
			var t: SimUnit = cs.sim.units[tid]
			if t.team == u.team:
				continue
			var pv := ActionResolver.preview_shot(cs, id, tid)
			if pv["result"] == "hit" and cs.ap_of(id) >= int(pv["cost"]) and not cs.suppressed.has(id):
				best = tid
				break
		var act: CombatAction = null
		if best >= 0:
			act = CombatAction.shoot(id, best)
		else:
			var tile := _closest_reachable(cs, u)
			act = CombatAction.move_to(id, tile) if tile != u.pos else CombatAction.end_turn(id)
		var r := ActionResolver.submit(cs, act)
		count += 1
		var bad := CombatInvariants.check(cs)
		if not bad.is_empty():
			problems.append_array(bad)
		if not r.success:
			problems.append("scripted policy issued an illegal action: %s %s" % [act.type, r.reason])
			ActionResolver.submit(cs, CombatAction.end_turn(id))
			return count + 1
		if act.type == CombatAction.END_TURN or cs.phase == CombatState.Phase.ENDED or cs.active_id != id:
			return count
	ActionResolver.submit(cs, CombatAction.end_turn(id))
	return count + 1


func _closest_reachable(cs: CombatState, u: SimUnit) -> Vector2i:
	var foes: Array[SimUnit] = []
	for fid in cs.sim.units:
		var f: SimUnit = cs.sim.units[fid]
		if f.alive and f.team != u.team:
			foes.append(f)
	var best := u.pos
	var best_d := 9999
	var reach: Dictionary = SimPathing.reach(SimVision.view_for(cs.sim, u.team), u.pos, u.id, cs.ap_of(u.id))["dist"]
	for tile: Vector2i in reach:
		for f in foes:
			var d := SimLos.chebyshev(tile, f.pos)
			if d < best_d or (d == best_d and SimPathing.tile_before(tile, best)):
				best_d = d
				best = tile
	return best if best_d < _nearest(u, foes) else u.pos


func _nearest(u: SimUnit, foes: Array[SimUnit]) -> int:
	var d := 9999
	for f in foes:
		d = mini(d, SimLos.chebyshev(u.pos, f.pos))
	return d


func test_scripted_4v4_fights_finish_with_no_illegal_state_or_lockup() -> void:
	var finished := 0
	var problems: Array[String] = []
	for sd in 25:
		var res := scripted_fight(sd)
		var cs: CombatState = res["cs"]
		problems.append_array(res["problems"])
		if cs.phase == CombatState.Phase.ENDED:
			finished += 1
		else:
			problems.append("seed %d did not finish (round %d, %d commands)" % [sd, cs.round_no, res["commands"]])
	check(problems.is_empty(), "no illegal action, invariant break or lockup: %s" % [problems.slice(0, 5)])
	check(finished == 25, "all 25 seeded 4v4 fights reach a result; %d did" % finished)


func test_a_scripted_fight_replays_identically_from_the_same_seed() -> void:
	var a := scripted_fight(11)
	var b := scripted_fight(11)
	check(sig(a["cs"]) == sig(b["cs"]) and a["cs"].ledger == b["cs"].ledger, "same seed + same commands = same log and ledger")
	check(sig(a["cs"]) != sig(scripted_fight(12)["cs"]), "a different seed plays differently")
