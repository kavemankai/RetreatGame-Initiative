extends TestBase
## Fog of war, filtered views and redacted replay.


func test_vision_range_limits_tiles() -> void:
	var tiles := SimVision.visible_tiles(fog_scene(), 0)
	check(tiles.has(Vector2i(2, 5)), "own tile is visible")
	check(tiles.has(Vector2i(10, 5)), "tile at sight range 8 is visible")
	check(not tiles.has(Vector2i(11, 5)), "tile beyond sight range is not visible")


func test_vision_enemy_visibility_by_range() -> void:
	var ids := SimVision.visible_unit_ids(fog_scene(), 0)
	check(ids.has(1) and ids.has(2), "own unit and in-range enemy are visible")
	check(not ids.has(3), "out-of-range enemy is hidden")
	var enemy_view := SimVision.visible_unit_ids(fog_scene(), 1)
	check(enemy_view.has(2) and enemy_view.has(3) and enemy_view.has(1), "the other side sees by the same rules (u2 sees u1 at 6)")


func test_vision_full_wall_blocks_half_wall_does_not() -> void:
	var walled := fog_scene()
	walled.grid.set_edge(Vector2i(4, 5), Vector2i(5, 5), SimConst.EDGE_FULL)
	check(not SimVision.visible_unit_ids(walled, 0).has(2), "a full wall hides the enemy behind it")
	var half := fog_scene()
	half.grid.set_edge(Vector2i(4, 5), Vector2i(5, 5), SimConst.EDGE_HALF)
	check(SimVision.visible_unit_ids(half, 0).has(2), "a half wall does not block sight")


func test_vision_is_shared_across_the_squad() -> void:
	var s := fog_scene()
	check(not SimVision.visible_unit_ids(s, 0).has(3), "u1 alone cannot see u3")
	add_unit(s, 4, 0, Vector2i(9, 5))
	check(SimVision.visible_unit_ids(s, 0).has(3), "a teammate closer to u3 reveals it to the whole squad")


func test_vision_dead_observers_see_nothing() -> void:
	var s := fog_scene()
	s.units[1].alive = false
	check(SimVision.visible_tiles(s, 0).is_empty(), "a squad with no living observers sees no tiles")
	check(SimVision.visible_unit_ids(s, 0).is_empty(), "and no units")


func test_view_for_hides_enemies_without_mutating() -> void:
	var s := fog_scene()
	var v := SimVision.view_for(s, 0)
	var ids := v.units.keys()
	ids.sort()
	check(ids == [1, 2], "filtered view holds own units and visible enemies only")
	check(s.units.size() == 3, "source state is untouched")
	v.units[1].pos = Vector2i(0, 0)
	check(s.units[1].pos == Vector2i(2, 5), "the view is a copy, not an alias")


func test_visible_orders_include_only_seen_enemies() -> void:
	var s := fog_scene()
	var p := SimPlan.new()
	p.add(1, SimAction.wait(2))
	p.add(2, SimAction.wait(2))
	p.add(3, SimAction.wait(2))
	var seen := SimVision.visible_orders(s, p, 0)
	var ids := seen.orders.keys()
	ids.sort()
	check(ids == [1, 2], "enemy orders appear only for visible enemies")
	check(p.orders.size() == 3, "the full plan is not mutated")


func test_validate_fog_rejects_shots_at_unseen_enemies() -> void:
	var s := fog_scene()
	var bad := plan_of(1, [SimAction.shoot(3)])
	check(bad.validate(s).is_empty(), "plain validation ignores fog")
	check(not bad.validate_fog(s).is_empty(), "fog validation rejects a shot at an unseen enemy")
	var ok := plan_of(1, [SimAction.shoot(2)])
	check(ok.validate_fog(s).is_empty(), "shooting a visible enemy passes fog validation")


func test_vision_sight_range_is_per_unit() -> void:
	var s := fog_scene()
	s.units[1].sight_range = 10
	check(SimVision.visible_unit_ids(s, 0).has(3), "a longer-sighted scout sees the distant enemy")
	s.units[1].sight_range = 4
	check(not SimVision.visible_unit_ids(s, 0).has(2), "a shorter sight range hides the nearer enemy")


func test_replay_fog_changes_with_movement() -> void:
	var s := fog_scene()
	var p := plan_of(3, [SimAction.move(Vector2i.LEFT)])  # u3: (11,5) -> (10,5) at tick 2
	var m := ReplayModel.new(s, p, SimResolver.resolve(s, p))
	check(not m.fog_at(0, 0)["units"].has(3), "tick 0: u3 hidden")
	check(m.fog_at(0, 2)["units"].has(3), "tick 2: u3 stepped into sight")
	check(m.fog_at(0, 2)["tiles"].has(Vector2i(10, 5)), "tile data comes with it")


func test_replay_event_visibility() -> void:
	var s := fog_scene()
	var p := plan_of(2, [SimAction.move(Vector2i.RIGHT)])  # visible u2 steps (8,5)->(9,5)
	var m := ReplayModel.new(s, p, SimResolver.resolve(s, p))
	var fog := m.fog_at(0, 2)
	check(ReplayModel.event_visible(m.events_at(2)[0], fog), "a visible unit's move is shown")
	var hidden := {"type": "move", "tick": 2, "unit": 3, "from": Vector2i(11, 5), "to": Vector2i(11, 6)}
	check(not ReplayModel.event_visible(hidden, fog), "a move entirely in the fog is hidden")
	var shot_in := {"type": "shot", "tick": 2, "unit": 3, "target": 1, "result": "hit", "damage": 1}
	check(ReplayModel.event_visible(shot_in, fog), "a hidden shooter hitting a visible target is shown")
	var shot_out := {"type": "shot", "tick": 2, "unit": 3, "target": 3, "result": "blocked"}
	check(not ReplayModel.event_visible(shot_out, fog), "a shot between hidden units is hidden")


func test_describe_redacts_hidden_ids_and_tiles() -> void:
	var s := fog_scene()
	var m := ReplayModel.new(s, SimPlan.new(), SimResolver.resolve(s, SimPlan.new()))
	var fog := m.fog_at(0, 0)  # u1, u2 visible; u3 hidden
	var shot := {"type": "shot", "tick": 2, "unit": 3, "target": 1, "result": "hit", "damage": 1}
	var text := ReplayModel.describe(shot, fog)
	check(not text.contains("u3") and text.contains("unseen") and text.contains("u1"), "hidden shooter is redacted: %s" % text)
	var move := {"type": "move", "tick": 2, "unit": 2, "from": Vector2i(8, 5), "to": Vector2i(11, 8)}
	var mtext := ReplayModel.describe(move, fog)
	check(mtext.contains("?") and not mtext.contains("11"), "hidden destination tile is redacted: %s" % mtext)
	check(ReplayModel.describe(shot).contains("u3"), "with no fog the full text is shown")
