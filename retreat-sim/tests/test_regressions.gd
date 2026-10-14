extends TestBase
## Regression tests from the code-review pass.


func test_los_is_symmetric() -> void:
	var g := SimGrid.new(6, 6)
	g.set_blocked(Vector2i(0, 1))
	g.set_blocked(Vector2i(3, 3))
	g.set_edge(Vector2i(2, 0), Vector2i(3, 0), SimConst.EDGE_FULL)
	g.set_edge(Vector2i(4, 2), Vector2i(4, 3), SimConst.EDGE_FULL)
	var asymmetric := 0
	for ay in 6:
		for ax in 6:
			for by in 6:
				for bx in 6:
					var a := Vector2i(ax, ay)
					var b := Vector2i(bx, by)
					if a != b and not g.is_blocked(a) and not g.is_blocked(b) and SimLos.can_shoot(g, a, b) != SimLos.can_shoot(g, b, a):
						asymmetric += 1
	check(asymmetric == 0, "can_shoot(a,b) == can_shoot(b,a) for every pair; %d asymmetric" % asymmetric)


func test_cover_depends_on_shooter_side_for_both_line_orders() -> void:
	var g := SimGrid.new(12, 12)
	g.set_edge(Vector2i(5, 4), Vector2i(5, 5), SimConst.EDGE_HALF)  # north edge of (5,5)
	var target := Vector2i(5, 5)
	check(SimLos.is_covered(g, Vector2i(5, 1), target), "shooter north of the wall: covered")
	check(not SimLos.is_covered(g, Vector2i(5, 9), target), "shooter south of the wall: not covered")
	check(not SimLos.is_covered(g, Vector2i(1, 5), target), "shooter on an unwalled side: not covered")


func test_can_step_rejects_non_adjacent_steps() -> void:
	var g := SimGrid.new(8, 8)
	check(not g.can_step(Vector2i(1, 1), Vector2i(3, 1)), "a 2-tile step is illegal")
	check(not g.can_step(Vector2i(1, 1), Vector2i(1, 1)), "a zero step is illegal")
	check(g.can_step(Vector2i(1, 1), Vector2i(2, 2)), "a normal diagonal is still legal")


func test_resolver_rejects_malformed_plans_safely() -> void:
	var s := make_state()
	s.grid.set_edge(Vector2i(1, 1), Vector2i(2, 1), SimConst.EDGE_FULL)
	add_unit(s, 1, 0, Vector2i(1, 1))
	var long_step := plan_of(1, [SimAction.move(Vector2i(2, 0))])
	var r := SimResolver.resolve(s, long_step)
	check(r.state.units[1].pos == Vector2i(1, 1), "an oversized step cannot jump a wall")
	check(events_of(r, "plan_rejected").size() == 1, "the rejection is logged")
	var with_null := SimPlan.new()
	with_null.orders[1] = [null]
	var r2 := SimResolver.resolve(s, with_null)
	check(events_of(r2, "plan_rejected").size() == 1, "a null action is rejected, not a crash")
	var ghost := plan_of(99, [SimAction.wait(2)])
	var r3 := SimResolver.resolve(s, ghost)
	check(events_of(r3, "plan_rejected").size() == 1, "orders for an unknown unit are rejected")
	s.units[1].alive = false
	var r4 := SimResolver.resolve(s, plan_of(1, [SimAction.wait(2)]))
	check(events_of(r4, "plan_rejected").size() == 1, "orders for a dead unit are rejected")


func test_empty_plan_is_safe() -> void:
	var s := fog_scene()
	var r := SimResolver.resolve(s, SimPlan.new())
	check(r.events.size() == 1 and r.events[0]["type"] == "turn_end", "an empty plan only ends the turn")
	check(snapshot(r.state) == snapshot(s), "and changes nothing")


func test_three_way_tile_contention() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 1), 3, 6)
	add_unit(s, 2, 1, Vector2i(3, 1), 3, 5)
	add_unit(s, 3, 1, Vector2i(2, 2), 3, 4)
	var p := SimPlan.new()
	p.add(1, SimAction.move(Vector2i.RIGHT))
	p.add(2, SimAction.move(Vector2i.LEFT))
	p.add(3, SimAction.move(Vector2i.UP))
	var r := SimResolver.resolve(s, p)
	check(r.state.units[1].pos == Vector2i(2, 1), "the fastest unit takes the contested tile")
	check(r.state.units[2].pos == Vector2i(3, 1) and r.state.units[3].pos == Vector2i(2, 2), "the other two stop short")
	check(events_of(r, "move_blocked").size() == 2, "both losers get move_blocked")


func test_friendly_fire_is_invalid() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 1))
	add_unit(s, 2, 0, Vector2i(4, 1))
	var r := SimResolver.resolve(s, plan_of(1, [SimAction.shoot(2)]))
	var shot: Dictionary = events_of(r, "shot")[0]
	check(shot["result"] == "invalid" and shot["reason"] == "friendly" and r.state.units[2].hp == 3, "a shot at a teammate is invalid and harmless")


func test_stress_truncates_queue_at_the_budget() -> void:
	var s := make_state()
	var u := add_unit(s, 1, 0, Vector2i(1, 1))
	u.stress_penalty = T - 4  # 4 ticks available
	var p := plan_of(1, [SimAction.move(Vector2i.RIGHT), SimAction.move(Vector2i.RIGHT), SimAction.move(Vector2i.RIGHT)])
	var r := SimResolver.resolve(s, p)
	check(r.state.units[1].pos == Vector2i(3, 1), "only the two moves that fit in 4 ticks execute")


func test_resolve_does_not_mutate_the_grid() -> void:
	var sc := Scenarios.build(4)
	var g: SimGrid = sc["state"].grid
	var before := str(g.edges) + str(g.blocked) + str(g.width) + str(g.height)
	SimResolver.resolve(sc["state"], sc["plan"])
	check(str(g.edges) + str(g.blocked) + str(g.width) + str(g.height) == before, "the shared grid is untouched by resolve")


func test_ordered_fire_logs_death_then_the_cancelled_reply() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(1, 1), 1, 5)
	add_unit(s, 2, 1, Vector2i(5, 1), 1, 5)
	var p := SimPlan.new()
	p.add(1, SimAction.shoot(2))
	p.add(2, SimAction.shoot(1))
	var r := SimResolver.resolve(s, p)
	var types: Array = r.events.filter(func(e): return e["tick"] == 4).map(func(e): return e["type"])
	check(types == ["shot", "death", "cancelled"], "first shot, its kill, then the dead unit's cancelled reply; got %s" % [types])


func test_fog_shows_lethal_shots_and_deaths() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(2, 5))
	add_unit(s, 2, 1, Vector2i(6, 5), 1)
	var p := plan_of(1, [SimAction.shoot(2)])
	var m := ReplayModel.new(s, p, SimResolver.resolve(s, p))
	var fog := m.fog_at(0, 4)
	var evs := m.events_at(4)
	check(evs.size() == 2, "tick 4 has a shot and a death")
	for ev in evs:
		check(ReplayModel.event_visible(ev, fog), "the viewer sees the %s event" % ev["type"])
	check(ReplayModel.describe(evs[0], fog).contains("u2"), "the victim is named, not redacted, in the lethal shot")


func test_fog_hidden_shooter_killing_a_visible_unit_is_shown() -> void:
	var s := make_state()
	var victim := add_unit(s, 1, 0, Vector2i(5, 5), 1)
	victim.sight_range = 2
	add_unit(s, 2, 1, Vector2i(9, 5))  # outside the victim's sight, inside its own gun range
	var p := plan_of(2, [SimAction.shoot(1)])
	var m := ReplayModel.new(s, p, SimResolver.resolve(s, p))
	var visible := m.events_at(4).filter(func(e): return ReplayModel.event_visible(e, m.fog_at(0, 4)))
	check(visible.size() == 2, "the viewer sees a hit and a death from an unseen shooter; saw %d" % visible.size())
	check(not ReplayModel.describe(visible[0], m.fog_at(0, 4)).contains("u2"), "but the shooter stays redacted")


func test_replay_watchers_respect_budget_truncation() -> void:
	var s := make_state()
	var u := add_unit(s, 1, 0, Vector2i(5, 5))
	u.stress_penalty = T - 2  # 2 ticks available; a 4-tick watch never starts
	var p := plan_of(1, [SimAction.overwatch(Vector2i.LEFT, 4)])
	var m := ReplayModel.new(s, p, SimResolver.resolve(s, p))
	check(m.watchers_at(1).is_empty(), "a watch the resolver dropped is not drawn")
	var ghost := plan_of(99, [SimAction.overwatch(Vector2i.LEFT, 2)])
	var m2 := ReplayModel.new(s, ghost, SimResolver.resolve(s, ghost))
	check(m2.watchers_at(1).is_empty(), "unknown unit ids do not crash the replay")


func test_ai_profile_loading_is_safe() -> void:
	var res := SimAIProfile.load_file("res://data/does_not_exist.json")
	check(not (res["errors"] as Array).is_empty(), "a missing file is reported")
	check(SimAIProfile.from_dict({"w_damage": 1.0e30})["errors"].size() > 0, "an absurd weight is rejected")
	var no_default := {"aggressor": SimAIProfile.new()}
	var s := make_state()
	add_unit(s, 1, 1, Vector2i(8, 5))
	add_unit(s, 2, 0, Vector2i(4, 5))
	check(actions_of(SimAI.plan_for(s, 1, no_default), 1, "shoot").size() == 1, "a table without 'default' falls back to built-in weights")
	check(actions_of(SimAI.plan_for(s, 1, {}), 1, "shoot").size() == 1, "an empty table also works")
