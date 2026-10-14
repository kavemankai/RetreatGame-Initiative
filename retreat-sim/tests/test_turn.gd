extends TestBase
## SimTurn: the incremental, interruptible resolver.


func busy_scene() -> SimState:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 5), 3, 6)
	add_unit(s, 2, 0, Vector2i(1, 7), 3, 5)
	add_unit(s, 3, 1, Vector2i(8, 5), 3, 4)
	add_unit(s, 4, 1, Vector2i(8, 7), 3, 3)
	return s


func busy_plan() -> SimPlan:
	var p := SimPlan.new()
	p.add(1, SimAction.move(Vector2i.RIGHT))
	p.add(1, SimAction.move(Vector2i.RIGHT))
	p.add(1, SimAction.shoot(3))
	p.add(2, SimAction.overwatch(Vector2i.RIGHT, 6))
	p.add(3, SimAction.move(Vector2i.LEFT))
	p.add(3, SimAction.shoot(1))
	p.add(4, SimAction.move(Vector2i.LEFT))
	p.add(4, SimAction.move(Vector2i.LEFT))
	return p


func test_stepping_equals_full_resolve() -> void:
	var s := busy_scene()
	var full := SimResolver.resolve(s, busy_plan())
	var turn := SimTurn.new(s, busy_plan())
	var ticks := 0
	while not turn.is_finished():
		turn.advance()
		ticks += 1
	check(ticks == SimConst.TICKS_PER_TURN, "a turn is exactly 12 advances")
	check(str(turn.events) == str(full.events), "stepping tick by tick yields the identical event log")
	check(snapshot(turn.state) == snapshot(full.state), "and the identical final state")


func test_advance_returns_only_that_ticks_events() -> void:
	var turn := SimTurn.new(busy_scene(), busy_plan())
	var first := turn.advance()
	check(first.is_empty() and turn.tick == 1, "tick 1: nothing completes yet")
	var second := turn.advance()
	check(second.all(func(e): return e["tick"] == 2) and not second.is_empty(), "tick 2 returns only tick-2 events")


func test_input_state_is_not_mutated_by_a_live_turn() -> void:
	var s := busy_scene()
	var turn := SimTurn.new(s, busy_plan())
	while not turn.is_finished():
		turn.advance()
	check(s.units[1].pos == Vector2i(1, 5) and s.turn == 0, "the starting state is untouched")


func test_snapshots_record_the_board_after_each_tick() -> void:
	var turn := SimTurn.new(busy_scene(), busy_plan(), true)
	turn.advance()
	turn.advance()
	check(turn.snapshots.size() == 3, "snapshot 0 (start) plus one per tick")
	check(turn.snapshots[0].units[1].pos == Vector2i(1, 5) and turn.snapshots[2].units[1].pos == Vector2i(2, 5), "snapshots hold the positions at that moment")


func test_idle_units_are_reported_once_when_orders_run_out() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 5))
	var turn := SimTurn.new(s, plan_of(1, [SimAction.move(Vector2i.RIGHT)]))
	turn.advance()
	check(turn.last_idle.is_empty(), "tick 1: still stepping")
	turn.advance()
	check(turn.last_idle == [1], "tick 2: the step finished and the merc is now idle")
	turn.advance()
	check(turn.last_idle.is_empty(), "it is not reported again")


func test_blocked_units_count_as_idle() -> void:
	var s := make_state()
	s.grid.set_edge(Vector2i(1, 5), Vector2i(2, 5), SimConst.EDGE_FULL)
	add_unit(s, 1, 0, Vector2i(1, 5))
	var turn := SimTurn.new(s, plan_of(1, [SimAction.move(Vector2i.RIGHT), SimAction.move(Vector2i.RIGHT)]))
	turn.advance()
	turn.advance()
	check(turn.last_idle == [1], "a merc halted by a wall is idle")


func test_replace_orders_swaps_the_queue_for_an_idle_unit() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 5))
	var turn := SimTurn.new(s, SimPlan.new())
	turn.advance()
	turn.advance()  # paused at tick 2 with nothing planned
	check(turn.replace_orders(1, [SimAction.move(Vector2i.RIGHT)]) == "", "an idle merc can be given orders mid-turn")
	turn.advance()
	turn.advance()  # the step started at tick 3, finishes at tick 4
	check(turn.state.units[1].pos == Vector2i(2, 5), "the new step ran from tick 3 to 4")


func test_in_progress_move_finishes_then_new_orders_follow() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 5))
	var turn := SimTurn.new(s, plan_of(1, [SimAction.move(Vector2i.RIGHT), SimAction.move(Vector2i.RIGHT), SimAction.move(Vector2i.RIGHT)]))
	turn.advance()  # tick 1: first step is half done (finishes tick 2)
	check(turn.committed_action(1) != null and turn.free_at(1) == 2, "the half-done step is committed and frees the merc at tick 2")
	check(turn.projected_pos(1) == Vector2i(2, 5), "projected position is where that step ends")
	check(turn.replace_orders(1, [SimAction.move(Vector2i.DOWN)]) == "", "new orders are accepted")
	while not turn.is_finished():
		turn.advance()
	check(turn.state.units[1].pos == Vector2i(2, 6), "right (committed) then down (new); the old queue is gone")


func test_overwatch_can_be_cancelled_immediately() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(5, 5))
	var turn := SimTurn.new(s, plan_of(1, [SimAction.overwatch(Vector2i.RIGHT, 12)]))
	turn.advance()
	turn.advance()
	check(turn.committed_action(1) == null and turn.free_at(1) == 2, "a hold is never committed; the merc is free right away")
	check(turn.replace_orders(1, [SimAction.move(Vector2i.RIGHT)]) == "", "so a new order can replace it")
	check(turn.watchers().is_empty(), "the watch is gone")


func test_replace_orders_respects_the_remaining_budget() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 5))
	var turn := SimTurn.new(s, SimPlan.new())
	for i in T - 4:
		turn.advance()  # 4 ticks left
	check(turn.replace_orders(1, [SimAction.move(Vector2i.RIGHT), SimAction.move(Vector2i.RIGHT), SimAction.move(Vector2i.RIGHT)]) != "", "6 ticks of orders do not fit in 4")
	check(turn.replace_orders(1, [SimAction.move(Vector2i.RIGHT), SimAction.move(Vector2i.RIGHT)]) == "", "4 ticks fit exactly")
	check(turn.replace_orders(1, [SimAction.move(Vector2i(2, 0))]) != "", "malformed actions are refused")


func test_committed_action_counts_against_the_budget() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 5))
	var turn := SimTurn.new(s, plan_of(1, [SimAction.shoot(2)]))
	add_unit(turn.state, 2, 1, Vector2i(5, 5))
	turn.advance()  # shot in progress, finishes tick 4
	check(turn.free_at(1) == 4, "a shot in progress holds the merc until tick 4")
	var five: Array[SimAction] = []
	for i in full_steps() - 1:
		five.append(SimAction.move(Vector2i.RIGHT))
	check(turn.replace_orders(1, five) != "", "4 (shot) + one step too many exceeds the turn")
	check(turn.replace_orders(1, five.slice(0, full_steps() - 2)) == "", "the shot plus the steps that remain fits exactly")


func test_replace_with_nothing_clears_the_queue() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 5))
	var turn := SimTurn.new(s, plan_of(1, [SimAction.move(Vector2i.RIGHT), SimAction.move(Vector2i.RIGHT), SimAction.move(Vector2i.RIGHT)]))
	turn.advance()
	turn.advance()  # first step done, second just started? (start = tick+1)
	check(turn.replace_orders(1, []) == "", "an empty replacement is allowed")
	while not turn.is_finished():
		turn.advance()
	check(turn.state.units[1].pos == Vector2i(2, 5), "only the finished step happened")


func test_remaining_actions_lists_current_and_queued() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 5))
	var turn := SimTurn.new(s, plan_of(1, [SimAction.move(Vector2i.RIGHT), SimAction.move(Vector2i.RIGHT), SimAction.wait(2)]))
	check(turn.remaining_actions(1).size() == 3, "at the start everything remains")
	turn.advance()
	turn.advance()
	check(turn.remaining_actions(1).size() == 2, "after one step completes, two remain")


func test_dead_units_cannot_be_reordered() -> void:
	var s := make_state()
	var u := add_unit(s, 1, 0, Vector2i(1, 5))
	u.alive = false
	var turn := SimTurn.new(s, SimPlan.new())
	check(turn.replace_orders(1, [SimAction.wait(2)]) != "", "orders for a dead merc are refused")
	check(turn.replace_orders(99, [SimAction.wait(2)]) != "", "so are orders for unknown ids")


func test_watchers_report_active_overwatch() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(5, 5))
	var turn := SimTurn.new(s, plan_of(1, [SimAction.overwatch(Vector2i.LEFT, 6)]))
	var w := turn.watchers()
	check(w.size() == 1 and w[0]["id"] == 1 and w[0]["dir"] == Vector2i.LEFT and not w[0]["spent"], "an active, unspent watch is listed")
	for i in 7:
		turn.advance()
	check(turn.watchers().is_empty(), "it disappears when the hold ends")


# --- review regressions ----------------------------------------------------

func overwatch_shots(turn: SimTurn) -> int:
	return turn.events.filter(func(e): return e["type"] == "shot" and e.get("overwatch", false)).size()


func test_a_spent_overwatch_stays_spent_when_the_same_hold_is_reissued() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(8, 5))
	add_unit(s, 2, 1, Vector2i(1, 5), 9)
	var p := SimPlan.new()
	p.add(1, SimAction.overwatch(Vector2i.LEFT, 12))
	for i in 6:
		p.add(2, SimAction.move(Vector2i.RIGHT))
	var turn := SimTurn.new(s, p)
	for i in 4:
		turn.advance()
	check(overwatch_shots(turn) == 1, "the watch fired once, early")
	check(turn.replace_orders(1, turn.remaining_actions(1)) == "", "pause + resume re-issues the unchanged hold")
	while not turn.is_finished():
		turn.advance()
	check(overwatch_shots(turn) == 1, "a re-issued hold does not fire a second time; got %d" % overwatch_shots(turn))


func test_a_different_overwatch_after_a_pause_is_a_fresh_watch() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(8, 5))
	add_unit(s, 2, 1, Vector2i(1, 5), 9)
	var p := SimPlan.new()
	p.add(1, SimAction.overwatch(Vector2i.LEFT, 12))
	for i in 6:
		p.add(2, SimAction.move(Vector2i.RIGHT))
	var turn := SimTurn.new(s, p)
	for i in 4:
		turn.advance()
	turn.replace_orders(1, [SimAction.overwatch(Vector2i(-1, 1), 8)])
	check(turn.watchers().size() == 1 and not turn.watchers()[0]["spent"], "a new facing is a new, unspent watch")


func test_a_blocked_committed_move_drops_the_replacement_orders() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 5))
	s.grid.set_edge(Vector2i(1, 5), Vector2i(2, 5), SimConst.EDGE_FULL)
	var turn := SimTurn.new(s, plan_of(1, [SimAction.move(Vector2i.RIGHT)]))
	turn.advance()
	check(turn.replace_orders(1, [SimAction.wait(2)]) == "", "orders are accepted while the step is under way")
	turn.advance()
	check(turn.last_idle == [1] and turn.remaining_actions(1).is_empty(), "the step is blocked by the wall; the merc is idle and the queued wait is gone (by design)")


# --- move and fire ---------------------------------------------------------------

func steps_right(n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in n:
		out.append(Vector2i.RIGHT)
	return out


func reserve_of(u: SimUnit) -> int:
	return u.shot_ticks() * SimConst.MOVE_FIRE_SHOT_FACTOR


func test_move_fire_costs_the_path_plus_a_reserved_double_shot() -> void:
	var u := SimUnit.make(1, 0, Vector2i.ZERO, 3, 5, 5, 5)
	check(SimAction.move_fire(steps_right(3)).cost(u) == 6 + reserve_of(u), "three steps (6 ticks) plus the reserve")
	check(SimAction.move_fire([Vector2i(1, 1)]).cost(u) == 3 + reserve_of(u), "a diagonal step costs 3")
	check(SimConst.MOVE_FIRE_SHOT_FACTOR >= 2, "the reserved shot is never cheaper than double")


func test_move_fire_shape_is_validated() -> void:
	check(not SimAction.move_fire([]).is_valid_shape(), "no steps is malformed")
	check(not SimAction.move_fire([Vector2i(2, 0)]).is_valid_shape(), "a two-tile step is malformed")
	check(not SimAction.move_fire([Vector2i.RIGHT, Vector2i.ZERO]).is_valid_shape(), "a zero step is malformed")
	check(SimAction.move_fire(steps_right(2)).is_valid_shape(), "a proper path is fine")


func test_move_fire_walks_at_a_normal_pace_and_stays_busy_for_the_full_cost() -> void:
	var s := make_state()
	var u := add_unit(s, 1, 0, Vector2i(1, 5))
	var turn := SimTurn.new(s, plan_of(1, [SimAction.move_fire(steps_right(3))]))
	var cost := SimAction.move_fire(steps_right(3)).cost(u)
	for i in 2:
		turn.advance()
	check(turn.state.units[1].pos == Vector2i(2, 5), "the first step lands on tick 2")
	for i in 4:
		turn.advance()
	check(turn.state.units[1].pos == Vector2i(4, 5), "the path is walked by tick 6")
	check(turn.committed_action(1) != null and turn.free_at(1) == cost, "but the merc stays committed until the full cost is paid (tick %d)" % cost)
	while turn.tick < cost:
		turn.advance()
	check(turn.last_idle == [1], "it is only idle once the reserve is spent")


func test_move_fire_fires_once_at_the_first_opportunity() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 5))
	add_unit(s, 2, 1, Vector2i(6, 5), 3, 1)
	var turn := SimTurn.new(s, plan_of(1, [SimAction.move_fire(steps_right(3))]))
	while not turn.is_finished():
		turn.advance()
	var shots := turn.events.filter(func(e): return e["type"] == "shot")
	check(shots.size() == 1 and shots[0]["tick"] == 2 and shots[0]["result"] == "hit", "one shot, on the first step that finds a target")
	check(turn.state.units[2].hp == 2, "and only one hit lands")


func test_move_fire_takes_no_shot_when_none_comes_up_but_still_costs() -> void:
	var s := make_state()
	var u := add_unit(s, 1, 0, Vector2i(1, 5))
	u.weapon_range = 2  # max range 3
	add_unit(s, 2, 1, Vector2i(9, 5), 3, 1)
	var action := SimAction.move_fire(steps_right(3))
	var turn := SimTurn.new(s, plan_of(1, [action]))
	while turn.tick < 6:
		turn.advance()
	check(turn.events.filter(func(e): return e["type"] == "shot").is_empty(), "nothing was ever in range, so nothing was fired")
	check(turn.free_at(1) == action.cost(u), "yet the merc is still committed for the whole cost")


func test_move_fire_never_fires_at_an_enemy_its_squad_cannot_see() -> void:
	var s := make_state()
	var u := add_unit(s, 1, 0, Vector2i(1, 5))
	u.sight_range = 3
	add_unit(s, 2, 1, Vector2i(7, 5), 3, 1)  # in weapon range from the first step, but hidden
	var turn := SimTurn.new(s, plan_of(1, [SimAction.move_fire(steps_right(4))]))
	while not turn.is_finished():
		turn.advance()
	var shots := turn.events.filter(func(e): return e["type"] == "shot")
	check(shots.size() == 1 and shots[0]["tick"] == 6, "sight 3: the enemy 7 tiles away is first seen from the third step (tick 6), not before (got %s)" % [shots[0]["tick"] if not shots.is_empty() else "none"])


func test_move_fire_prefers_a_clean_hit_over_a_shot_into_cover() -> void:
	var s := make_state()
	s.grid.set_edge(Vector2i(5, 5), Vector2i(6, 5), SimConst.EDGE_HALF)
	add_unit(s, 1, 0, Vector2i(1, 5))
	add_unit(s, 2, 1, Vector2i(6, 5), 3, 1)   # behind the half wall: the shot would be blocked
	add_unit(s, 3, 1, Vector2i(6, 2), 3, 1)   # in the open
	var turn := SimTurn.new(s, plan_of(1, [SimAction.move_fire(steps_right(2))]))
	while not turn.is_finished():
		turn.advance()
	check(turn.state.units[3].hp == 2 and turn.state.units[2].hp == 3, "the open target is hit, the covered one ignored")


func test_a_blocked_move_fire_halts_the_whole_action() -> void:
	var s := make_state()
	s.grid.set_edge(Vector2i(2, 5), Vector2i(3, 5), SimConst.EDGE_FULL)
	add_unit(s, 1, 0, Vector2i(1, 5))
	var turn := SimTurn.new(s, plan_of(1, [SimAction.move_fire(steps_right(3))]))
	while not turn.is_finished():
		turn.advance()
	check(turn.state.units[1].pos == Vector2i(2, 5), "it stops where the wall stops it")
	check(turn.events.any(func(e): return e["type"] == "move_blocked"), "the block is logged")


func test_move_fire_projects_the_end_of_its_path_while_in_progress() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 5))
	var turn := SimTurn.new(s, plan_of(1, [SimAction.move_fire(steps_right(3))]))
	turn.advance()
	turn.advance()
	check(turn.projected_pos(1) == Vector2i(4, 5), "partway along, the merc still projects to the end of its path")
