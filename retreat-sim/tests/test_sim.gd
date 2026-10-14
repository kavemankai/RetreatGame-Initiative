extends TestBase
## Core rules: movement, shooting, growth, determinism, overwatch, cones.


func test_orthogonal_move_cost() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 1))
	var r := SimResolver.resolve(s, plan_of(1, [SimAction.move(Vector2i.RIGHT), SimAction.move(Vector2i.RIGHT), SimAction.move(Vector2i.RIGHT)]))
	check(r.state.units[1].pos == Vector2i(4, 1), "3 east steps end at (4,1)")
	var ticks: Array = events_of(r, "move").map(func(e): return e["tick"])
	check(ticks == [2, 4, 6], "orthogonal steps complete on ticks 2,4,6; got %s" % [ticks])


func test_diagonal_move_cost() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 1))
	var r := SimResolver.resolve(s, plan_of(1, [SimAction.move(Vector2i(1, 1)), SimAction.move(Vector2i(1, 1))]))
	check(r.state.units[1].pos == Vector2i(3, 3), "2 diagonal steps end at (3,3)")
	var ticks: Array = events_of(r, "move").map(func(e): return e["tick"])
	check(ticks == [3, 6], "diagonal steps complete on ticks 3,6; got %s" % [ticks])


func test_plan_over_budget_rejected() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 1))
	var ok := plan_of(1, rights(full_steps()))
	check(ok.validate(s).is_empty(), "a full turn of steps is valid")
	var over := plan_of(1, rights(full_steps() + 1))
	check(not over.validate(s).is_empty(), "one step more than a turn is rejected")


func test_stress_reduces_budget() -> void:
	var s := make_state()
	var u := add_unit(s, 1, 0, Vector2i(1, 1))
	u.stress_penalty = 2
	var six := plan_of(1, rights(full_steps()))
	check(not six.validate(s).is_empty(), "stress 2 removes 2 ticks; a full turn of orders is rejected")
	var drone := add_unit(s, 2, 0, Vector2i(1, 3))
	drone.is_drone = true
	drone.stress_penalty = 2
	check(drone.available_ticks() == SimConst.TICKS_PER_TURN, "drones ignore stress")


func test_full_wall_blocks_movement() -> void:
	var s := make_state()
	s.grid.set_edge(Vector2i(2, 1), Vector2i(3, 1), SimConst.EDGE_FULL)
	add_unit(s, 1, 0, Vector2i(1, 1))
	var r := SimResolver.resolve(s, plan_of(1, [SimAction.move(Vector2i.RIGHT), SimAction.move(Vector2i.RIGHT), SimAction.move(Vector2i.RIGHT)]))
	check(r.state.units[1].pos == Vector2i(2, 1), "unit stops short of the wall")
	check(events_of(r, "move_blocked").size() == 1, "one move_blocked event")
	check(events_of(r, "move").size() == 1, "later queued steps are dropped after halting")


func test_diagonal_corner_cut_blocked() -> void:
	var s := make_state()
	s.grid.set_edge(Vector2i(1, 1), Vector2i(2, 1), SimConst.EDGE_FULL)
	add_unit(s, 1, 0, Vector2i(1, 1))
	var r := SimResolver.resolve(s, plan_of(1, [SimAction.move(Vector2i(1, 1))]))
	check(r.state.units[1].pos == Vector2i(1, 1), "diagonal step cannot cut a corner through a full wall")
	check(events_of(r, "move_blocked").size() == 1, "corner cut reports move_blocked")


func test_open_shot_hits() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 1))
	add_unit(s, 2, 1, Vector2i(5, 1), 3)
	var r := SimResolver.resolve(s, plan_of(1, [SimAction.shoot(2)]))
	check(r.state.units[2].hp == 2, "open-ground shot deals 1 damage")
	var shots := events_of(r, "shot")
	check(shots.size() == 1 and shots[0]["result"] == "hit" and shots[0]["tick"] == 4, "hit event on tick 4")


func test_full_wall_blocks_los() -> void:
	var s := make_state()
	s.grid.set_edge(Vector2i(2, 1), Vector2i(3, 1), SimConst.EDGE_FULL)
	add_unit(s, 1, 0, Vector2i(1, 1))
	add_unit(s, 2, 1, Vector2i(5, 1), 3)
	var r := SimResolver.resolve(s, plan_of(1, [SimAction.shoot(2)]))
	check(r.state.units[2].hp == 3, "no damage through a full wall")
	var shots := events_of(r, "shot")
	check(shots.size() == 1 and shots[0]["result"] == "invalid" and shots[0]["reason"] == "no_los", "shot is invalid: no_los")


func test_half_wall_cover_blocks_and_flank_hits() -> void:
	var s := make_state()
	s.grid.set_edge(Vector2i(4, 1), Vector2i(5, 1), SimConst.EDGE_HALF)
	add_unit(s, 1, 0, Vector2i(1, 1))
	add_unit(s, 3, 0, Vector2i(5, 5))
	add_unit(s, 2, 1, Vector2i(5, 1), 3)
	var p := SimPlan.new()
	p.add(1, SimAction.shoot(2))
	var r := SimResolver.resolve(s, p)
	check(r.state.units[2].hp == 3, "half wall on the target's facing side blocks the shot")
	check(events_of(r, "shot")[0]["result"] == "blocked", "result is blocked")
	var flank := SimPlan.new()
	flank.add(3, SimAction.shoot(2))
	var r2 := SimResolver.resolve(s, flank)
	check(r2.state.units[2].hp == 2, "a flanking shot from an uncovered side hits")


func test_out_of_range() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 1))
	add_unit(s, 2, 1, Vector2i(9, 1), 3)
	var r := SimResolver.resolve(s, plan_of(1, [SimAction.shoot(2)]))
	var shots := events_of(r, "shot")
	check(shots[0]["result"] == "invalid" and shots[0]["reason"] == "out_of_range", "distance 8 > range 7 is out_of_range")
	check(r.state.units[2].hp == 3, "no damage when out of range")


func test_higher_speed_kills_first() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 1), 1, 6)
	add_unit(s, 2, 1, Vector2i(5, 1), 1, 4)
	var p := SimPlan.new()
	p.add(1, SimAction.shoot(2))
	p.add(2, SimAction.shoot(1))
	var r := SimResolver.resolve(s, p)
	check(r.state.units[1].alive, "faster unit survives")
	check(not r.state.units[2].alive, "slower unit dies")
	check(events_of(r, "shot").size() == 1, "slower unit's shot is cancelled, not fired")
	check(events_of(r, "cancelled").size() == 1, "a cancelled event is logged")


func test_equal_speed_lower_id_fires_first_no_mutual_kill() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 1), 1, 5)
	add_unit(s, 2, 1, Vector2i(5, 1), 1, 5)
	var p := SimPlan.new()
	p.add(1, SimAction.shoot(2))
	p.add(2, SimAction.shoot(1))
	var r := SimResolver.resolve(s, p)
	check(r.state.units[1].alive and not r.state.units[2].alive, "equal speed and aim: the lower id fires first and the reply never comes")


func test_move_collision_earlier_speed_wins() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 1), 3, 5)
	add_unit(s, 2, 1, Vector2i(3, 1), 3, 3)
	var p := SimPlan.new()
	p.add(1, SimAction.move(Vector2i.RIGHT))
	p.add(2, SimAction.move(Vector2i.LEFT))
	var r := SimResolver.resolve(s, p)
	check(r.state.units[1].pos == Vector2i(2, 1), "faster unit takes the contested tile")
	check(r.state.units[2].pos == Vector2i(3, 1), "slower unit stops short")
	check(events_of(r, "move_blocked").size() == 1, "loser gets move_blocked")


func test_counters_recorded() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 1))
	add_unit(s, 2, 1, Vector2i(5, 1), 3)
	var p := SimPlan.new()
	p.add(1, SimAction.move(Vector2i.DOWN))
	p.add(1, SimAction.shoot(2))
	var r := SimResolver.resolve(s, p)
	check(r.state.units[1].counters.get("steps_moved", 0) == 1, "steps_moved counted")
	check(r.state.units[1].counters.get("shots_fired", 0) == 1, "shots_fired counted")
	check(r.state.units[2].counters.get("hits_taken", 0) == 1, "hits_taken counted")


func test_cqb_close_range_damage() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 1), 3, 5, 5, 6)
	add_unit(s, 2, 1, Vector2i(2, 1), 5)
	var r := SimResolver.resolve(s, plan_of(1, [SimAction.shoot(2)]))
	check(r.state.units[2].hp == 3, "CQB>=6 at distance<=2 adds 1 damage")


func test_aim_reduces_shot_ticks() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 1), 3, 5, 8)
	add_unit(s, 2, 1, Vector2i(4, 1), 3)
	var r := SimResolver.resolve(s, plan_of(1, [SimAction.shoot(2)]))
	check(events_of(r, "shot")[0]["tick"] == 3, "Aim>=8 shaves a tick off the shot")


func test_resolve_is_deterministic_and_pure() -> void:
	var s := make_state()
	s.grid.set_edge(Vector2i(4, 1), Vector2i(5, 1), SimConst.EDGE_HALF)
	add_unit(s, 1, 0, Vector2i(1, 1))
	add_unit(s, 2, 1, Vector2i(5, 1), 3)
	add_unit(s, 3, 0, Vector2i(5, 5))
	var p := SimPlan.new()
	p.add(1, SimAction.move(Vector2i.DOWN))
	p.add(1, SimAction.shoot(2))
	p.add(3, SimAction.shoot(2))
	var a := SimResolver.resolve(s, p)
	var b := SimResolver.resolve(s, p)
	check(str(a.events) == str(b.events), "same state + plan => identical event log")
	check(s.units[1].pos == Vector2i(1, 1) and s.units[2].hp == 3 and s.turn == 0, "input state is not mutated")
	check(a.state.turn == 1, "resolved state advances the turn")


func test_cone_geometry() -> void:
	var o := Vector2i(5, 5)
	check(SimLos.in_cone(o, Vector2i.RIGHT, Vector2i(8, 5)), "straight ahead is in cone")
	check(SimLos.in_cone(o, Vector2i.RIGHT, Vector2i(8, 8)), "45 degree boundary is in cone")
	check(not SimLos.in_cone(o, Vector2i.RIGHT, Vector2i(8, 9)), "beyond 45 degrees is out")
	check(not SimLos.in_cone(o, Vector2i.RIGHT, Vector2i(2, 5)), "behind is out")
	check(not SimLos.in_cone(o, Vector2i.RIGHT, o), "own tile is out")
	check(SimLos.in_cone(o, Vector2i(1, 1), Vector2i(7, 5)), "diagonal facing covers a quadrant edge")
	check(not SimLos.in_cone(o, Vector2i(1, 1), Vector2i(2, 5)), "diagonal facing excludes the far side")


func test_overwatch_fires_once_at_mover_in_cone() -> void:
	var s := overwatch_scene()
	s.units[2].morale = 99  # steady whatever the roll: this test is about overwatch, not morale
	var r := SimResolver.resolve(s, mover_plan())
	var ow := events_of(r, "shot").filter(func(e): return e.get("overwatch", false))
	check(ow.size() == 1, "exactly one overwatch shot; got %d" % ow.size())
	check(ow[0]["tick"] == 2 and ow[0]["result"] == "hit", "fires on the tick the mover arrives in view")
	check(r.state.units[2].hp == 2, "mover took 1 damage and no more")
	check(r.state.units[2].pos == Vector2i(3, 5), "mover still completes its 3 steps")


func test_overwatch_ignores_targets_outside_cone() -> void:
	var r := SimResolver.resolve(overwatch_scene(), mover_plan(3, 8, Vector2i.UP))
	check(events_of(r, "shot").is_empty(), "mover outside the cone triggers nothing")


func test_overwatch_window_is_limited_to_hold() -> void:
	var s := overwatch_scene()
	var p := SimPlan.new()
	p.add(1, SimAction.overwatch(Vector2i.LEFT, 2))
	p.add(2, SimAction.wait(3))
	p.add(2, SimAction.move(Vector2i.RIGHT))  # arrives tick 5, after the 2-tick hold
	var r := SimResolver.resolve(s, p)
	check(events_of(r, "shot").is_empty(), "no reaction after the hold has ended")


func test_overwatch_kill_cancels_movers_orders() -> void:
	var s := overwatch_scene(8, 1)
	var p := mover_plan()
	p.add(2, SimAction.shoot(1))
	var r := SimResolver.resolve(s, p)
	check(not r.state.units[2].alive, "overwatch kills the 1 hp mover")
	check(events_of(r, "move").size() == 1, "mover's later steps never happen")
	check(r.state.units[1].hp == 3, "mover's queued shot never fires")


func test_overwatch_equal_speed_both_fire() -> void:
	var s := overwatch_scene()
	add_unit(s, 3, 0, Vector2i(5, 6))
	var p := mover_plan(1)
	p.add(3, SimAction.overwatch(Vector2i.LEFT, 8))
	var r := SimResolver.resolve(s, p)
	check(r.state.units[2].hp == 1, "two equal-speed watchers both hit the same mover")


func test_overwatch_faster_watcher_kills_before_slower() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(5, 5), 3, 6)
	add_unit(s, 3, 0, Vector2i(5, 6), 3, 4)
	add_unit(s, 2, 1, Vector2i(0, 5), 1)
	var p := SimPlan.new()
	p.add(1, SimAction.overwatch(Vector2i.LEFT, 8))
	p.add(3, SimAction.overwatch(Vector2i.LEFT, 8))
	p.add(2, SimAction.move(Vector2i.RIGHT))
	var r := SimResolver.resolve(s, p)
	var hits := events_of(r, "shot").filter(func(e): return e["result"] == "hit")
	check(hits.size() == 1 and hits[0]["unit"] == 1, "only the faster watcher lands the kill")
	check(not r.state.units[2].alive, "mover dies")


func test_overwatch_cover_blocks_but_spends_watch() -> void:
	var s := overwatch_scene()
	s.grid.set_edge(Vector2i(1, 5), Vector2i(2, 5), SimConst.EDGE_HALF)
	var r := SimResolver.resolve(s, mover_plan())
	var shots := events_of(r, "shot")
	check(shots.size() == 1 and shots[0]["result"] == "blocked", "covered mover: shot is blocked")
	check(r.state.units[2].hp == 3, "no damage through cover")


func test_overwatch_ignores_friendlies() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(5, 5))
	add_unit(s, 2, 0, Vector2i(0, 5))
	var r := SimResolver.resolve(s, mover_plan())
	check(events_of(r, "shot").is_empty(), "friendly movement never triggers overwatch")


func test_overwatch_validation() -> void:
	var s := overwatch_scene()
	var bad_facing := plan_of(1, [SimAction.overwatch(Vector2i.ZERO, 4)])
	check(not bad_facing.validate(s).is_empty(), "zero facing is rejected")
	var too_long := plan_of(1, [SimAction.overwatch(Vector2i.LEFT, T + 1)])
	check(not too_long.validate(s).is_empty(), "hold longer than the turn is rejected")
	var ok := plan_of(1, [SimAction.overwatch(Vector2i.LEFT, T)])
	check(ok.validate(s).is_empty(), "a full-turn hold is valid")


func test_cone_tiles_split_clear_and_shadowed() -> void:
	var g := SimGrid.new(12, 12)
	g.set_edge(Vector2i(4, 5), Vector2i(5, 5), SimConst.EDGE_FULL)
	var c := SimLos.cone_tiles(g, Vector2i(2, 5), Vector2i.RIGHT, 7)
	check(c["clear"].has(Vector2i(3, 5)) and c["clear"].has(Vector2i(4, 5)), "tiles before the wall are clear")
	check(c["shadowed"].has(Vector2i(7, 5)) and c["shadowed"].has(Vector2i(5, 5)), "tiles behind the wall are shadowed")
	check(not c["clear"].has(Vector2i(2, 5)) and not c["shadowed"].has(Vector2i(2, 5)), "origin is in neither list")
	var open := SimLos.cone_tiles(SimGrid.new(12, 12), Vector2i(2, 5), Vector2i.RIGHT, 7)
	check(open["shadowed"].is_empty() and open["clear"].has(Vector2i(7, 5)), "open ground has no shadow")


func test_cone_tiles_respect_range_bounds_and_terrain() -> void:
	var g := SimGrid.new(8, 8)
	g.set_blocked(Vector2i(4, 4))
	var c := SimLos.cone_tiles(g, Vector2i(1, 4), Vector2i.RIGHT, 4)
	var all: Array = c["clear"] + c["shadowed"]
	check(not all.has(Vector2i(6, 4)), "tiles beyond range are excluded")
	check(not all.has(Vector2i(4, 4)), "terrain-blocked tiles are excluded")
	check(all.all(func(t: Vector2i) -> bool: return g.in_bounds(t)), "only in-bounds tiles")
	var edge := SimLos.cone_tiles(g, Vector2i(7, 4), Vector2i.RIGHT, 4)
	check((edge["clear"] + edge["shadowed"]).is_empty(), "a cone facing the map edge has no tiles")
