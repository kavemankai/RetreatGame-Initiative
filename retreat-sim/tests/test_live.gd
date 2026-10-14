extends TestBase
## Live (pausable) turns: fog diffs, AI replanning, the match run, order entry
## mid-turn, and the controller around them.


## Blue u1 (2,5) u2 (2,7); red u3 (8,5) visible at start, u4 (11,9) hidden.
func live_state() -> SimState:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(2, 5), 3, 6)
	add_unit(s, 2, 0, Vector2i(2, 7), 3, 5)
	add_unit(s, 3, 1, Vector2i(8, 5), 3, 4)
	add_unit(s, 4, 1, Vector2i(11, 9), 3, 3)
	return s


func live_match(s: SimState = null) -> SimMatch:
	return SimMatch.new(s if s != null else live_state(), 0, ai_profiles())


func moves(n: int, dir: Vector2i = Vector2i.RIGHT) -> Array[SimAction]:
	var out: Array[SimAction] = []
	for i in n:
		out.append(SimAction.move(dir))
	return out


# --- vision diffs and turn tweaks -----------------------------------------

func test_fog_between_unions_start_and_end() -> void:
	var before := live_state()
	var after := before.clone()
	after.units[3].alive = false
	after.units[3].pos = Vector2i(8, 5)
	var fog := SimVision.fog_between(before, after, 0)
	check(fog["units"].has(3), "a unit visible at the start of the tick is still shown when it dies")
	check(fog["tiles"].has(Vector2i(8, 5)), "and its tile")
	check(not fog["units"].has(4), "a unit hidden at both ends stays hidden")


func test_can_replace_validates_without_applying() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 5))
	var turn := SimTurn.new(s, plan_of(1, moves(2)))
	check(turn.can_replace(1, moves(full_steps() + 1)) != "", "too many ticks is reported")
	check(turn.can_replace(1, moves(2)) == "", "a legal queue passes")
	check(turn.remaining_actions(1).size() == 2, "and nothing was changed by checking")


func test_remaining_hold_is_normalised_to_the_ticks_left() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(5, 5))
	var turn := SimTurn.new(s, plan_of(1, [SimAction.overwatch(Vector2i.LEFT, 12)]))
	for i in 5:
		turn.advance()
	var rest := turn.remaining_actions(1)
	check(rest.size() == 1 and rest[0].type == "overwatch" and rest[0].wait_ticks == 7, "an overwatch 5 ticks in has 7 left, not 12")


# --- AI replanning ---------------------------------------------------------

func test_ai_replan_respects_budget_and_position() -> void:
	var s := make_state()
	add_unit(s, 1, 1, Vector2i(1, 5))
	var live := {1: {"free_at": 6, "pos": Vector2i(10, 5)}}
	var p := SimAI.plan_for(s, 1, ai_profiles(), {}, Vector2i(11, 5), live)
	var total := 0
	for a: SimAction in p.orders.get(1, []):
		total += a.cost(s.units[1])
	check(total <= 6, "only 6 ticks remain, plan uses %d" % total)
	check(actions_of(p, 1, "move").size() <= 1, "planned from (10,5): at most one step to reach the objective at (11,5)")


# --- the match run ---------------------------------------------------------

func test_match_starts_a_live_run() -> void:
	var m := live_match()
	check(m.run != null and m.run.tick == 0 and m.state == m.run.state, "a turn is a live run at tick 0")
	check(not m.ai_plan.orders.is_empty(), "the AI planned at the turn start")


func test_match_step_advances_one_tick() -> void:
	var m := live_match()
	var r := m.step()
	check(m.run.tick == 1 and r["finished"] == false and r.has("events") and r.has("reasons"), "one tick per step")


func test_pause_reason_spotted() -> void:
	var s := live_state()
	s.units[1].sight_range = 3
	s.units[2].sight_range = 3
	s.units[3].pos = Vector2i(7, 5)  # 5 away: hidden
	var m := live_match(s)
	m.run.replace_orders(3, moves(3, Vector2i.LEFT))
	var seen_at := -1
	for i in 6:
		var r := m.step()
		if r["reasons"].has("spotted"):
			seen_at = m.run.tick
			break
	check(seen_at == 4, "the enemy steps into view on tick 4; spotted at %d" % seen_at)


func test_pause_reason_hit() -> void:
	var m := live_match()
	m.run.replace_orders(3, [SimAction.shoot(1)])
	var hit_tick := -1
	for i in 6:
		if m.step()["reasons"].has("hit"):
			hit_tick = m.run.tick
			break
	check(hit_tick == 4, "your merc is hit on tick 4; got %d" % hit_tick)


func test_pause_reason_idle() -> void:
	var m := live_match()
	m.run.replace_orders(1, moves(1))
	m.run.replace_orders(3, [])
	var first := m.step()
	check(not first["reasons"].has("idle"), "tick 1: the step is still in progress")
	check(m.step()["reasons"].has("idle"), "tick 2: the merc's last order finished, so it is flagged idle")


func test_pause_reason_overwatch() -> void:
	var m := live_match()
	m.run.replace_orders(3, [SimAction.overwatch(Vector2i.LEFT, 10)])
	m.run.replace_orders(1, moves(3))
	var got := false
	for i in 4:
		got = got or m.step()["reasons"].has("overwatch")
	check(got, "walking into an enemy overwatch cone pauses the action")


func test_pause_replans_the_ai_from_its_own_view() -> void:
	var m := live_match()
	m.run.replace_orders(3, [])
	m.step()
	m.step()
	m.pause()
	check(not m.run.remaining_actions(3).is_empty(), "after a pause the AI has fresh orders for u3")
	for a in m.run.remaining_actions(4):
		check(a.type != "shoot" or a.target_id == 1 or a.target_id == 2, "u4's replanned shots only target mercs it can see")


func test_apply_orders_is_all_or_nothing() -> void:
	var m := live_match()
	var good := moves(2)
	var bad := moves(full_steps() + 1, Vector2i.DOWN)
	var err := m.apply_orders({1: good, 2: bad})
	check(err != "", "one illegal queue rejects the whole batch")
	check(m.run.remaining_actions(1).size() == 0, "u1's queue was not applied")
	check(m.apply_orders({1: good}) == "" and m.run.remaining_actions(1).size() == 2, "a legal batch applies")


func test_apply_orders_enforces_fog_and_ownership() -> void:
	var m := live_match()
	check(m.apply_orders({1: [SimAction.shoot(4)]}) != "", "a shot at an unseen enemy is refused")
	check(m.apply_orders({3: moves(1)}) != "", "you cannot order enemy units")
	check(m.apply_orders({1: [SimAction.shoot(3)]}) == "", "a visible enemy is fine")


func test_run_ends_early_when_a_side_is_wiped_out() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(2, 5), 3, 9)
	add_unit(s, 3, 1, Vector2i(5, 5), 1, 1)
	var m := live_match(s)
	m.apply_orders({1: [SimAction.shoot(3)]})
	m.run.replace_orders(3, [])
	for i in 4:
		m.step()
	check(m.is_over() and m.winner == 0 and m.run == null, "killing the last enemy ends the match mid-turn")
	check(m.turn == 2, "and the turn counter moved on")


func test_finishing_a_turn_starts_the_next_run() -> void:
	var m := live_match()
	var r := {}
	for i in T:
		r = m.step()
	check(r["finished"] and m.turn == 2 and m.run != null and m.run.tick == 0, "the last tick completes the turn and opens turn 2 at tick 0")


func test_enemy_intent_follows_live_replans() -> void:
	var m := live_match()
	m.run.replace_orders(3, moves(2, Vector2i.LEFT))
	var intent := m.enemy_intent()
	check(intent.orders.has(3) and intent.orders[3].size() == 2, "intent shows the visible enemy's current orders")
	check(not intent.orders.has(4), "never a hidden one")


func test_submit_still_resolves_a_whole_turn() -> void:
	var m := live_match()
	var r := m.submit(SimPlan.new())
	check(r != null and m.turn == 2 and m.run != null and m.run.tick == 0, "submit = apply orders, run to the end")


func test_soak_live_matches_with_pauses_and_replans_are_reproducible() -> void:
	var finals: Array = []
	for rep in 2:
		var m := SimMatch.skirmish()
		var profiles := ai_profiles()
		var guard := 0
		while not m.is_over() and guard < 400:
			guard += 1
			var r := m.step()
			if not (r["reasons"] as Array).is_empty() or m.run == null or m.run.tick % 3 == 0:
				if m.run == null:
					continue
				m.pause()
				var live := {}
				for id in m.run.state.units:
					var u: SimUnit = m.run.state.units[id]
					if u.alive and u.team == 0 and not m.run.is_broken(id):
						live[id] = {"free_at": m.run.free_at(id), "pos": m.run.projected_pos(id)}
				var plan := SimAI.plan_for(m.run.state, 0, profiles, {}, Vector2i(10, 5), live)
				for id in plan.orders.keys():
					if m.run.is_broken(id):
						plan.orders.erase(id)  # broken mercs hold until the round ends
				var err := m.apply_orders(plan.orders)
				if err != "":
					check(false, "rep %d: AI-as-player orders refused: %s" % [rep, err])
					break
		finals.append(snapshot(m.state))
		check(m.turn > 1, "rep %d played %d turns" % [rep, m.turn])
	check(finals[0] == finals[1], "live matches with pauses and replans are reproducible")


# --- order entry mid-turn --------------------------------------------------

func test_builder_without_a_run_is_unchanged() -> void:
	var b := PlanBuilder.new(live_state(), 0)
	check(b.ticks_left(1) == T and b.projected_pos(1) == Vector2i(2, 5), "tick 0 behaves exactly as before")


func test_builder_mid_turn_starts_after_the_committed_action() -> void:
	var s := live_state()
	var turn := SimTurn.new(s, plan_of(1, moves(3)))
	turn.advance()  # first step in progress, finishes tick 2
	var b := PlanBuilder.new(turn.state, 0, turn)
	check(b.ticks_left(1) == T - 2 - 4, "turn - 2 committed - 4 for the two queued steps")
	check(b.projected_pos(1) == Vector2i(5, 5), "queued steps are seeded as an entry; projected end (5,5)")
	b.undo(1)
	check(b.ticks_left(1) == T - 2 and b.projected_pos(1) == Vector2i(3, 5), "undo removes the seeded steps; the position is where the committed step ends")


func test_builder_new_moves_chain_from_the_committed_position() -> void:
	var s := live_state()
	var turn := SimTurn.new(s, plan_of(1, moves(1)))
	turn.advance()
	var b := PlanBuilder.new(turn.state, 0, turn)
	b.undo(1)
	check(b.queue_move(1, Vector2i(3, 7)) == "", "a path is found from (3,5), not from (2,5)")
	check(b.ticks_used(1) == 4, "(3,5)->(3,7) is 2 steps = 4 ticks")


func test_builder_orders_apply_back_to_the_run() -> void:
	var s := live_state()
	var turn := SimTurn.new(s, plan_of(1, moves(3)))
	turn.advance()
	var b := PlanBuilder.new(turn.state, 0, turn)
	b.undo(1)
	b.queue_move(1, Vector2i(3, 7))
	check(turn.replace_orders(1, b.orders_for(1)) == "", "the builder's orders fit the run")
	while not turn.is_finished():
		turn.advance()
	check(turn.state.units[1].pos == Vector2i(3, 7), "the merc finishes its committed step and then walks to (3,7)")


func test_builder_seeds_a_running_overwatch_with_its_remaining_hold() -> void:
	var s := live_state()
	var turn := SimTurn.new(s, plan_of(1, [SimAction.overwatch(Vector2i.RIGHT, T)]))
	for i in 4:
		turn.advance()
	var b := PlanBuilder.new(turn.state, 0, turn)
	check(b.ticks_left(1) == 0 and b.entries_for(1)[0]["kind"] == "overwatch", "the watch uses every remaining tick")
	b.undo(1)
	check(b.ticks_left(1) == T - 4, "cancelling it frees them")


# --- controller around a live run ------------------------------------------

func test_controller_pause_and_go() -> void:
	var m := live_match()
	var c := PlayController.new(m)
	c.select(1)
	c.click_tile(Vector2i(4, 5))
	check(c.go() == "" and m.run.remaining_actions(1).size() == 2, "go() hands the planned orders to the run without ticking")
	check(m.run.tick == 0, "no time has passed")
	m.step()
	m.step()
	c.pause()
	check(c.selected == -1 and c.builder.entries_for(1).size() <= 1, "pausing rebuilds the planner from the live run")


func test_controller_confirm_still_runs_the_whole_turn() -> void:
	var c := PlayController.new(live_match())
	c.select(1)
	c.click_tile(Vector2i(8, 5))
	var r := c.confirm()
	check(r != null and c.game.turn == 2 and c.game.run.tick == 0, "confirm = go + run to the end")


# --- review regressions ----------------------------------------------------

func test_early_finish_closes_the_turn_log() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(2, 5), 3, 9)
	add_unit(s, 3, 1, Vector2i(5, 5), 1, 1)
	var m := live_match(s)
	m.apply_orders({1: [SimAction.shoot(3)]})
	m.run.replace_orders(3, [])
	for i in 4:
		m.step()
	check(m.last_result.events.back()["type"] == "turn_end", "an early finish still ends the log with turn_end")


func test_stale_seeded_shots_do_not_block_resume() -> void:
	var m := live_match()
	m.run.replace_orders(1, [SimAction.shoot(3)])
	m.run.state.units[3].alive = false
	var c := PlayController.new(m)
	check(c.builder.entries_for(1).is_empty(), "a queued shot at a dead target is dropped when seeding")
	check(c.go() == "", "so Resume is not refused")


func test_pause_never_leaves_the_ai_with_stale_orders() -> void:
	var m := live_match()
	m.step()
	m.step()
	m.pause()
	for id in [3, 4]:
		var left := 0
		for a: SimAction in m.run.remaining_actions(id):
			left += a.cost(m.run.state.units[id])
		check(m.run.free_at(id) + left <= m.run.state.units[id].available_ticks(), "AI unit %d's replanned queue fits the budget" % id)


# --- no pauses, idle fast-forward ---------------------------------

func quiet_match() -> SimMatch:
	var m := live_match()
	for id in [3, 4]:
		m.run.replace_orders(id, [])
	return m


func test_the_run_never_pauses_before_the_round_ends() -> void:
	var m := live_match()
	m.run.replace_orders(3, [SimAction.shoot(1)])  # a hit mid-round must not stop the run
	var early := false
	var last := {}
	for i in T:
		last = m.step()
		if i < T - 1:
			early = early or last["pause"]
	check(not early, "no pause on any tick before the last (no checkpoints, no interrupts)")
	check(last["finished"] and last["pause"], "the round end hands control back")


func test_a_turn_is_twenty_ticks() -> void:
	check(SimConst.TICKS_PER_TURN == 20, "20-tick rounds")
	var m := quiet_match()
	var last := {}
	for i in T:
		last = m.step()
	check(last["finished"] and m.turn == 2, "tick 20 ends the round")


func test_idle_and_overwatch_events_no_longer_interrupt() -> void:
	var m := quiet_match()
	for id in [1, 2]:
		m.run.state.units[id].sight_range = 6  # keep hidden u4 from coming into view
	m.run.replace_orders(1, moves(1))
	m.step()
	var r := m.step()
	check(r["reasons"].has("idle") and not r["pause"], "running out of orders is reported but does not stop the run")


func test_has_active_orders_covers_queues_holds_and_flight() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 5))
	check(not SimTurn.new(s, SimPlan.new()).has_active_orders(), "nothing queued: nobody is acting")
	check(SimTurn.new(s, plan_of(1, moves(1))).has_active_orders(), "a queued step is acting")
	check(SimTurn.new(s, plan_of(1, [SimAction.overwatch(Vector2i.LEFT, 6)])).has_active_orders(), "a hold counts as acting")
	var t := SimTurn.new(s, plan_of(1, moves(1)))
	t.advance()
	t.advance()
	check(not t.has_active_orders(), "once the step completes nobody is acting")


func test_step_reports_when_nobody_is_left_to_act() -> void:
	var m := quiet_match()
	var r := m.step()
	check(r["idle"], "with no orders anywhere the run is idle and can fast-forward")
	var busy := live_match()
	busy.run.replace_orders(1, moves(3))
	check(not busy.step()["idle"], "with orders in flight it is not")
