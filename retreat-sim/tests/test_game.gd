extends TestBase
## Player-facing layers: pathing, order entry, the match loop, click handling.


# --- helpers -------------------------------------------------------------

## Blue (team 0): u1 (2,5), u2 (2,7). Red: u3 (8,5) visible (dist 6),
## u4 (11,9) hidden (dist 9 from u1; sight is 8).
func builder_state() -> SimState:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(2, 5))
	add_unit(s, 2, 0, Vector2i(2, 7))
	add_unit(s, 3, 1, Vector2i(8, 5))
	add_unit(s, 4, 1, Vector2i(11, 9))
	return s


func new_builder(s: SimState = null) -> PlanBuilder:
	return PlanBuilder.new(s if s != null else builder_state(), 0)


func new_match(s: SimState = null) -> SimMatch:
	return SimMatch.new(s if s != null else builder_state(), 0, ai_profiles())


# --- pathing -------------------------------------------------------------

func test_pathing_reach_costs_and_paths() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(5, 5))
	var r := SimPathing.reach(s, Vector2i(5, 5), 1, 6)
	check(r["dist"][Vector2i(7, 5)] == 4 and r["dist"][Vector2i(6, 6)] == 3, "orthogonal 2 ticks, diagonal 3")
	check(not r["dist"].has(Vector2i(9, 5)), "beyond the budget is unreachable")
	var path := SimPathing.path_to(r, Vector2i(7, 5))
	check(path == [Vector2i(5, 5), Vector2i(6, 5), Vector2i(7, 5)], "path walks the straight line; got %s" % [path])
	var cost := 0
	for a in SimPathing.path_actions(path):
		cost += a.cost(s.units[1])
	check(cost == 4, "path actions cost what the reach says")
	check(SimPathing.path_to(r, Vector2i(11, 11)).is_empty(), "no path to an unreachable tile")


func test_pathing_routes_around_other_units() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(5, 5))
	add_unit(s, 2, 1, Vector2i(6, 5))
	var r := SimPathing.reach(s, Vector2i(5, 5), 1, 6)
	check(not r["dist"].has(Vector2i(6, 5)), "an occupied tile is not enterable")
	check(r["dist"][Vector2i(7, 5)] == 6, "going around costs two diagonals")


# --- plan builder --------------------------------------------------------

func test_builder_queues_a_move() -> void:
	var b := new_builder()
	check(b.queue_move(1, Vector2i(5, 5)) == "", "a reachable tile is accepted")
	check(b.orders_for(1).size() == 3 and b.ticks_used(1) == 6 and b.ticks_left(1) == T - 6, "3 steps = 6 ticks")
	check(b.projected_pos(1) == Vector2i(5, 5), "the projected position follows the move")


func test_builder_chains_moves_from_the_projected_position() -> void:
	var b := new_builder()
	b.queue_move(1, Vector2i(4, 5))
	check(b.queue_move(1, Vector2i(4, 7)) == "", "the second move starts where the first ends")
	check(b.ticks_used(1) == 8 and b.projected_pos(1) == Vector2i(4, 7), "4 + 4 ticks, ending at (4,7)")


func test_builder_rejects_bad_moves_without_queuing() -> void:
	var b := new_builder()
	check(b.queue_move(1, Vector2i(11, 0)) != "", "over budget is rejected (5 diagonals + 4 steps = 23 ticks)")
	check(b.queue_move(1, Vector2i(2, 7)) != "", "a tile held by a teammate is rejected")
	check(b.queue_move(1, Vector2i(2, 5)) != "", "moving to where you already are is rejected")
	check(b.queue_move(3, Vector2i(7, 5)) != "", "you cannot order an enemy unit")
	check(b.orders_for(1).is_empty() and b.ticks_used(1) == 0, "nothing was queued")


func test_builder_move_into_a_hidden_enemy_tile_is_not_a_tell() -> void:
	var s := builder_state()
	s.units[4].pos = Vector2i(5, 5)  # now 3 tiles from u1 but... make sure it is hidden
	s.units[1].sight_range = 1
	s.units[2].sight_range = 1
	var b := new_builder(s)
	check(not SimVision.visible_unit_ids(s, 0).has(4), "setup: u4 is hidden")
	check(b.queue_move(1, Vector2i(5, 5)) == "", "the player cannot tell a hidden enemy stands there")


func test_builder_shoot_rules() -> void:
	var b := new_builder()
	check(b.queue_shoot(1, 3) == "" and b.ticks_used(1) == 4, "a visible enemy can be targeted (4 ticks)")
	check(b.orders_for(1)[0].type == "shoot" and b.orders_for(1)[0].target_id == 3, "the shoot order targets u3")
	check(b.queue_shoot(2, 4) != "", "a hidden enemy cannot be targeted")
	check(b.queue_shoot(2, 1) != "", "a teammate cannot be targeted")
	var c := new_builder()
	c.queue_move(1, Vector2i(5, 5))   # 6 ticks
	[1, 2, 3].map(func(_i): c.queue_shoot(1, 3))  # 3 x 4 ticks
	check(c.queue_shoot(1, 3) != "", "a fourth shot would exceed the budget")


func test_builder_shot_preview_uses_the_projected_position() -> void:
	var s := builder_state()
	s.grid.set_edge(Vector2i(5, 5), Vector2i(6, 5), SimConst.EDGE_FULL)
	var b := new_builder(s)
	var before := b.shot_preview(1, 3)
	check(before["result"] == "invalid" and before["reason"] == "no_los", "behind the wall: no line of sight")
	b.queue_move(1, Vector2i(5, 8))
	var after := b.shot_preview(1, 3)
	check(after["result"] == "hit" and after["damage"] == 1, "after stepping out of the shadow the shot hits for 1; got %s" % [after])


func test_builder_shot_preview_reports_cover_and_range() -> void:
	var s := builder_state()
	s.grid.set_edge(Vector2i(7, 5), Vector2i(8, 5), SimConst.EDGE_HALF)
	var b := new_builder(s)
	check(b.shot_preview(1, 3)["result"] == "blocked", "a half wall on the target's side blocks the shot")
	s.units[1].weapon_range = 1
	var far := new_builder(s)
	check(far.shot_preview(1, 3)["reason"] == "out_of_range", "short-ranged weapon: out of range")


func test_builder_overwatch_takes_the_remaining_ticks() -> void:
	var b := new_builder()
	b.queue_move(1, Vector2i(3, 5))  # 2 ticks
	check(b.queue_overwatch(1, Vector2i.RIGHT) == "", "overwatch is accepted")
	var ow: SimAction = b.orders_for(1)[b.orders_for(1).size() - 1]
	check(ow.type == "overwatch" and ow.dir == Vector2i.RIGHT and ow.wait_ticks == T - 2, "it holds the remaining ticks")
	check(b.ticks_left(1) == 0 and b.queue_overwatch(1, Vector2i.LEFT) != "", "nothing is left to queue afterwards")
	check(b.queue_overwatch(2, Vector2i.ZERO) != "", "a zero facing is rejected")


func test_builder_facing_toward_normalises_to_eight_ways() -> void:
	var o := Vector2i(5, 5)
	check(PlanBuilder.facing_toward(o, Vector2i(9, 5)) == Vector2i.RIGHT, "straight east")
	check(PlanBuilder.facing_toward(o, Vector2i(9, 9)) == Vector2i(1, 1), "diagonal")
	check(PlanBuilder.facing_toward(o, Vector2i(9, 6)) == Vector2i.RIGHT, "shallow angle snaps to the axis")
	check(PlanBuilder.facing_toward(o, o) == Vector2i.ZERO, "same tile has no facing")


func test_builder_undo_and_clear() -> void:
	var b := new_builder()
	b.queue_move(1, Vector2i(4, 5))
	b.queue_shoot(1, 3)
	b.undo(1)
	check(b.orders_for(1).size() == 2 and b.ticks_left(1) == T - 4, "undo removes only the last entry (the shot)")
	b.undo(1)
	check(b.orders_for(1).is_empty() and b.projected_pos(1) == Vector2i(2, 5), "undoing the move restores the position")
	b.undo(1)  # nothing left: must be a no-op
	b.queue_move(2, Vector2i(3, 7))
	b.clear_all()
	check(b.plan().orders.is_empty(), "clear_all empties every queue")


func test_builder_plan_is_a_legal_snapshot() -> void:
	var s := builder_state()
	var b := new_builder(s)
	b.queue_move(1, Vector2i(4, 5))
	b.queue_shoot(1, 3)
	var p := b.plan()
	check(p.validate(s).is_empty() and p.validate_fog(s).is_empty(), "the built plan passes validate and validate_fog")
	check(p.orders.keys() == [1], "only units with orders appear")
	b.clear_all()
	check(p.orders.has(1), "the returned plan is a copy")


# --- match ---------------------------------------------------------------

func test_match_skirmish_setup() -> void:
	var m := SimMatch.skirmish()
	check(m.state.units.size() == 6 and m.turn == 1 and not m.is_over(), "3v3 at turn 1")
	check(not m.ai_plan.orders.is_empty(), "the AI has already planned its turn")
	check(m.state.units[1].sight_range < SimConst.SIGHT_RANGE, "the playable skirmish shortens sight so fog matters")


func test_match_intent_shows_only_visible_enemy_orders() -> void:
	var s := builder_state()
	var m := new_match(s)
	var seen := m.enemy_intent().orders.keys()
	check(seen.has(3) or m.ai_plan.orders.get(3, []).is_empty(), "a visible enemy's orders are shown")
	check(not seen.has(4), "a hidden enemy's orders are never shown")
	check(not seen.has(1) and not seen.has(2), "your own orders are not 'enemy intent'")


func test_match_submit_resolves_and_advances() -> void:
	var m := new_match()
	var r := m.submit(SimPlan.new())
	check(r != null and m.turn == 2 and m.state.turn == 1, "the turn advances")
	check(m.last_plan.orders.size() >= m.ai_plan.orders.size(), "the resolved plan includes the AI's orders")
	check(m.last_start.turn == 0, "the pre-turn state is kept for the replay")


func test_match_rejects_illegal_plans() -> void:
	var m := new_match()
	var hidden := plan_of(1, [SimAction.shoot(4)])
	check(m.submit(hidden) == null and m.last_error != "" and m.turn == 1, "a shot at an unseen enemy is refused, turn unchanged")
	var theirs := plan_of(3, [SimAction.wait(2)])
	check(m.submit(theirs) == null, "you cannot give orders to enemy units")


func test_match_detects_a_win() -> void:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(2, 5), 3, 9)
	add_unit(s, 3, 1, Vector2i(5, 5), 1, 1)
	var m := new_match(s)
	m.submit(plan_of(1, [SimAction.shoot(3)]))
	check(m.is_over() and m.winner == 0, "killing the last enemy wins the match")
	check(m.submit(SimPlan.new()) == null, "no more turns after the match ends")


func test_match_detects_a_loss_and_first_fire_wins_a_duel() -> void:
	var lose := make_state()
	add_unit(lose, 1, 0, Vector2i(2, 5), 1, 1)
	add_unit(lose, 3, 1, Vector2i(5, 5), 3, 9)
	var m := new_match(lose)
	m.submit(plan_of(1, [SimAction.wait(2)]))
	check(m.is_over() and m.winner == 1, "losing the last merc loses the match")
	var draw := make_state()
	add_unit(draw, 1, 0, Vector2i(2, 5), 1, 5)
	add_unit(draw, 3, 1, Vector2i(5, 5), 1, 5)
	# An AI already at its preferred range (3) shoots at once instead of repositioning.
	var steady := {"default": SimAIProfile.from_dict({"preferred_range": 3})["profile"]}
	var d := SimMatch.new(draw, 0, steady)
	d.submit(plan_of(1, [SimAction.shoot(3)]))
	check(d.is_over() and d.winner == 0, "equal speed and aim: the lower id fires first, so no mutual-kill draw")


func test_match_is_reproducible() -> void:
	var a := SimMatch.skirmish()
	var b := SimMatch.skirmish()
	for i in 3:
		a.submit(SimPlan.new())
		b.submit(SimPlan.new())
	check(snapshot(a.state) == snapshot(b.state), "same inputs => same match")


# --- controller ----------------------------------------------------------

func new_controller(s: SimState = null) -> PlayController:
	return PlayController.new(new_match(s))


func test_controller_select_then_move() -> void:
	var c := new_controller()
	check(c.click_tile(Vector2i(4, 5))["ok"] == false, "with nothing selected a tile click asks you to select")
	check(c.click_tile(Vector2i(2, 5))["ok"] and c.selected == 1, "clicking your merc selects it")
	check(c.click_tile(Vector2i(4, 5))["ok"] and c.builder.ticks_used(1) == 4, "then clicking a tile queues a move")


func test_controller_click_enemy_queues_a_shot() -> void:
	var c := new_controller()
	c.click_tile(Vector2i(2, 5))
	var res := c.click_tile(Vector2i(8, 5))
	check(res["ok"] and c.builder.orders_for(1)[0].type == "shoot", "clicking a visible enemy queues a shot")


func test_controller_overwatch_mode() -> void:
	var c := new_controller()
	c.click_tile(Vector2i(2, 5))
	c.set_mode(PlayController.MODE_OVERWATCH)
	var res := c.click_tile(Vector2i(6, 5))
	var ow: SimAction = c.builder.orders_for(1)[0]
	check(res["ok"] and ow.type == "overwatch" and ow.dir == Vector2i.RIGHT, "overwatch mode turns a click into a facing")
	check(c.mode == PlayController.MODE_NORMAL, "the mode resets after use")


func test_controller_deselect_undo_and_clear() -> void:
	var c := new_controller()
	c.click_tile(Vector2i(2, 5))
	c.click_tile(Vector2i(4, 5))
	c.undo()
	check(c.builder.ticks_used(1) == 0, "undo acts on the selected unit")
	c.click_tile(Vector2i(4, 5))
	c.deselect()
	check(c.selected == -1, "deselect clears the selection")
	c.clear()
	check(c.builder.plan().orders.is_empty(), "clear wipes every queue")


func test_controller_hover_info() -> void:
	var c := new_controller()
	check(c.hover_info(Vector2i(8, 5)) == "", "no hover text without a selection")
	c.click_tile(Vector2i(2, 5))
	check(c.hover_info(Vector2i(8, 5)).contains("hit"), "hovering an enemy previews the shot")
	check(c.hover_info(Vector2i(4, 5)).contains("4"), "hovering a tile shows its tick cost")
	check(c.hover_info(Vector2i(11, 0)).contains("unreachable"), "far tiles are unreachable")


func test_controller_confirm_advances_the_match() -> void:
	var c := new_controller()
	c.click_tile(Vector2i(2, 5))
	c.click_tile(Vector2i(8, 5))
	var r := c.confirm()
	check(r != null and c.game.turn == 2, "confirming resolves the turn")
	check(c.selected == -1 and c.builder.plan().orders.is_empty(), "the next turn starts clean")


# --- overlay and soak ----------------------------------------------------

func test_overlay_never_draws_hidden_enemies() -> void:
	var s := builder_state()
	var c := new_controller(s)
	c.click_tile(Vector2i(2, 5))
	var d := PlayOverlay.build(c)
	check(not d["fog"]["units"].has(4) and d["fog"]["units"].has(3), "fog marks u3 visible and u4 hidden")
	var hidden: Vector2i = s.units[4].pos
	var leaked := false
	for path in d["overlay"]["paths"]:
		leaked = leaked or (path["tiles"] as Array).has(hidden)
	for shot in d["overlay"]["shots"]:
		leaked = leaked or shot["from"] == hidden or shot["to"] == hidden
	for w in d["watchers"]:
		leaked = leaked or w["id"] == 4
	check(not leaked, "no path, shot or cone belongs to the hidden enemy")
	check(not (d["overlay"]["reachable"] as Dictionary).is_empty(), "the selected merc's reachable tiles are shown")


func test_overlay_shows_own_orders() -> void:
	var c := new_controller()
	c.click_tile(Vector2i(2, 5))
	c.click_tile(Vector2i(4, 5))
	c.set_mode(PlayController.MODE_OVERWATCH)
	c.click_tile(Vector2i(8, 5))
	var d := PlayOverlay.build(c)
	check(d["overlay"]["ghosts"].size() == 1 and d["overlay"]["ghosts"][0]["tile"] == Vector2i(4, 5), "a ghost marks where the merc will stand")
	var own_watch: Array = d["watchers"].filter(func(w): return w["id"] == 1)
	check(own_watch.size() == 1 and own_watch[0]["pos"] == Vector2i(4, 5), "the planned overwatch cone sits at the projected position")


func test_soak_ai_driven_matches_never_reject_a_turn() -> void:
	var profiles := ai_profiles()
	for run in 3:
		var m := SimMatch.skirmish()
		var turns := 0
		while not m.is_over() and turns < 25:
			var plan := SimAI.plan_for(m.state, 0, profiles, {}, Vector2i(10, 5))
			var r := m.submit(plan)
			if r == null:
				check(false, "run %d turn %d rejected: %s" % [run, turns, m.last_error])
				break
			turns += 1
		check(turns > 1, "run %d played %d turns" % [run, turns])


# --- touch: two-tap commit -----------------------------------------------

func test_tap_previews_then_commits_a_move() -> void:
	var c := new_controller()
	c.tap_tile(Vector2i(2, 5))
	var first := c.tap_tile(Vector2i(4, 5))
	check(first["ok"] and first.get("preview", false) and first["msg"].contains("Tap again"), "the first tap previews: %s" % first["msg"])
	check(c.builder.ticks_used(1) == 0 and c.pending == Vector2i(4, 5), "nothing is queued yet; the tile is pending")
	var second := c.tap_tile(Vector2i(4, 5))
	check(second["ok"] and c.builder.ticks_used(1) == 4 and c.pending == PlayController.NO_TILE, "the second tap on the same tile commits")


func test_tap_elsewhere_retargets_the_preview() -> void:
	var c := new_controller()
	c.tap_tile(Vector2i(2, 5))
	c.tap_tile(Vector2i(4, 5))
	c.tap_tile(Vector2i(3, 4))
	check(c.builder.ticks_used(1) == 0 and c.pending == Vector2i(3, 4), "tapping a different tile moves the preview, queues nothing")


func test_tap_unreachable_tile_does_not_become_pending() -> void:
	var c := new_controller()
	c.tap_tile(Vector2i(2, 5))
	var res := c.tap_tile(Vector2i(11, 0))
	check(not res["ok"] and c.pending == PlayController.NO_TILE and res["msg"].contains("unreachable"), "far tiles are refused straight away")


func test_tap_enemy_previews_the_shot_then_queues_it() -> void:
	var c := new_controller()
	c.tap_tile(Vector2i(2, 5))
	var res := c.tap_tile(Vector2i(8, 5))
	check(res["msg"].contains("hit"), "the shot result is in the preview text: %s" % res["msg"])
	check(c.pending_preview()["kind"] == "shot" and c.pending_preview()["result"] == "hit", "the preview data says shot/hit")
	c.tap_tile(Vector2i(8, 5))
	check(c.builder.orders_for(1)[0].type == "shoot", "the second tap queues the shot")


func test_tap_on_own_merc_selects_immediately_and_clears_pending() -> void:
	var c := new_controller()
	c.tap_tile(Vector2i(2, 5))
	c.tap_tile(Vector2i(4, 5))
	var res := c.tap_tile(Vector2i(2, 7))
	check(res["ok"] and c.selected == 2 and c.pending == PlayController.NO_TILE, "tapping another merc selects it and drops the preview")


func test_tap_overwatch_previews_a_facing() -> void:
	var c := new_controller()
	c.tap_tile(Vector2i(2, 5))
	c.set_mode(PlayController.MODE_OVERWATCH)
	c.tap_tile(Vector2i(6, 5))
	check(c.pending_preview()["kind"] == "overwatch" and c.pending_preview()["facing"] == Vector2i.RIGHT, "overwatch previews its facing")
	check(c.builder.orders_for(1).is_empty(), "and queues nothing until the second tap")
	c.tap_tile(Vector2i(6, 5))
	check(c.builder.orders_for(1)[0].type == "overwatch", "second tap commits the overwatch")


func test_pending_is_cleared_by_deselect_undo_and_confirm() -> void:
	var c := new_controller()
	c.tap_tile(Vector2i(2, 5))
	c.tap_tile(Vector2i(4, 5))
	c.deselect()
	check(c.pending == PlayController.NO_TILE, "deselect clears the pending tile")
	c.tap_tile(Vector2i(2, 5))
	c.tap_tile(Vector2i(4, 5))
	c.undo()
	check(c.pending == PlayController.NO_TILE, "undo clears it")
	c.tap_tile(Vector2i(4, 5))
	c.confirm()
	check(c.pending == PlayController.NO_TILE, "confirming a turn clears it")


func test_overlay_draws_the_pending_preview() -> void:
	var c := new_controller()
	c.tap_tile(Vector2i(2, 5))
	c.tap_tile(Vector2i(4, 5))
	var move_previews: Array = PlayOverlay.build(c)["overlay"]["paths"].filter(func(p): return p.get("preview", false))
	check(move_previews.size() == 1 and move_previews[0]["tiles"].back() == Vector2i(4, 5), "a pending move draws a preview path to the tile")
	check(PlayOverlay.build(c)["overlay"]["pending"] == Vector2i(4, 5), "and marks the pending tile")
	c.tap_tile(Vector2i(8, 5))
	var shot_previews: Array = PlayOverlay.build(c)["overlay"]["shots"].filter(func(p): return p.get("preview", false))
	check(shot_previews.size() == 1, "a pending shot draws a preview line")


# --- move and shoot, and the timeline --------------------------------------------











func test_the_timeline_lists_each_action_with_its_ticks() -> void:
	var b := new_builder()
	b.queue_move(1, Vector2i(5, 5))   # 6 ticks
	b.queue_shoot(1, 3)               # 4 ticks
	var t := b.timeline(1)
	check(t.size() == 2 and t[0]["kind"] == "move" and t[0]["start"] == 0 and t[0]["end"] == 6, "the move spans ticks 0-6")
	check(t[1]["kind"] == "shoot" and t[1]["start"] == 6 and t[1]["end"] == 10, "the shot spans 6-10")


func test_the_timeline_starts_after_the_committed_action_mid_round() -> void:
	var s := builder_state()
	var turn := SimTurn.new(s, plan_of(1, rights(3)))
	turn.advance()  # first step in flight, ends at tick 2
	var b := PlanBuilder.new(turn.state, 0, turn)
	var t := b.timeline(1)
	check(t.size() == 1 and t[0]["start"] == 2 and t[0]["end"] == 6, "the queued steps run from tick 2 to 6")
	check(b.timeline(2).is_empty(), "a merc with no orders has an empty timeline")


func test_overlay_labels_each_queued_action_with_the_tick_it_completes() -> void:
	var c := new_controller()
	c.click_tile(Vector2i(2, 5))
	c.click_tile(Vector2i(5, 5))   # move: ends tick 6
	c.click_tile(Vector2i(8, 5))   # shot: ends tick 10
	var marks: Array = PlayOverlay.build(c)["overlay"]["marks"]
	var texts := marks.map(func(m): return m["text"])
	check(texts.has("t6") and texts.has("t10"), "the move and the shot are labelled; got %s" % [texts])


func fire_reserve() -> int:
	return 4 * SimConst.MOVE_FIRE_SHOT_FACTOR


func test_builder_move_fire_queues_a_path_with_a_reserved_shot() -> void:
	var b := new_builder()
	check(b.queue_move_fire(1, Vector2i(5, 5)) == "", "a reachable tile is accepted")
	var a: SimAction = b.orders_for(1)[0]
	check(a.type == "move_fire" and a.steps.size() == 3, "one action walking three steps")
	check(b.ticks_used(1) == 6 + fire_reserve() and b.projected_pos(1) == Vector2i(5, 5), "path cost plus the reserved shot; ends at the chosen tile")
	check(b.timeline(1)[0]["kind"] == "move_fire" and b.timeline(1)[0]["end"] == 6 + fire_reserve(), "the timeline shows its full cost")


func test_builder_move_fire_rules() -> void:
	var b := new_builder()
	check(b.queue_move_fire(1, Vector2i(11, 0)) != "", "too far for the budget is rejected")
	check(b.queue_move_fire(1, Vector2i(2, 5)) != "", "where you already stand is rejected")
	check(b.queue_move_fire(1, Vector2i(8, 5)) != "", "a tile held by an enemy is rejected")
	check(b.queue_move_fire(3, Vector2i(7, 5)) != "", "you cannot order an enemy unit")
	check(b.orders_for(1).is_empty(), "nothing was queued by the failures")
	var tight := new_builder()
	tight.queue_overwatch(1, Vector2i.RIGHT)  # uses every tick
	check(tight.queue_move_fire(1, Vector2i(3, 5)) != "", "with no ticks left it is rejected")
	var short := new_builder()
	short.queue_move(1, Vector2i(10, 5))  # 16 ticks, leaving 4: not enough for even one step plus the reserve
	check(short.queue_move_fire(1, Vector2i(11, 5)) != "", "the reserve must fit too")


func test_builder_move_fire_preview_reports_cost_and_path() -> void:
	var b := new_builder()
	var p := b.move_fire_preview(1, Vector2i(5, 5))
	check(p["cost"] == 6 + fire_reserve() and p["path"].size() == 4, "the preview shows the total cost and the path")
	check(b.move_fire_preview(1, Vector2i(11, 0)).is_empty(), "an unreachable tile has no preview")
	check(b.reachable_fire(1).size() < b.reachable(1).size(), "less ground is reachable once the shot is reserved")


func test_controller_move_fire_mode() -> void:
	var c := new_controller()
	c.click_tile(Vector2i(2, 5))
	c.set_mode(PlayController.MODE_MOVE_FIRE)
	check(not c.click_tile(Vector2i(8, 5))["ok"], "an enemy tile is not a destination")
	check(c.hover_info(Vector2i(5, 5)).contains("ticks") and c.hover_info(Vector2i(5, 5)).contains("shot"), "hovering a tile shows the cost and the shot reserve")
	var res := c.click_tile(Vector2i(5, 5))
	check(res["ok"] and c.builder.orders_for(1)[0].type == "move_fire" and c.mode == PlayController.MODE_NORMAL, "clicking a tile queues it and the mode resets")


func test_tap_move_fire_previews_the_path_then_commits() -> void:
	var c := new_controller()
	c.tap_tile(Vector2i(2, 5))
	c.set_mode(PlayController.MODE_MOVE_FIRE)
	var first := c.tap_tile(Vector2i(5, 5))
	check(first.get("preview", false) and c.pending_preview()["kind"] == "move_fire", "the first tap previews")
	check(c.builder.orders_for(1).is_empty(), "nothing is queued yet")
	c.tap_tile(Vector2i(5, 5))
	check(c.builder.orders_for(1)[0].type == "move_fire", "the second tap commits")


func test_a_seeded_move_fire_survives_a_pause() -> void:
	var s := builder_state()
	var turn := SimTurn.new(s, plan_of(1, [SimAction.move(Vector2i.RIGHT), SimAction.move_fire([Vector2i.RIGHT, Vector2i.RIGHT])]))
	turn.advance()  # the plain step is under way (committed)
	var b := PlanBuilder.new(turn.state, 0, turn)
	check(b.entries_for(1).size() == 1 and b.entries_for(1)[0]["kind"] == "move_fire", "the queued move-and-fire is seeded as one entry")
	check(b.projected_pos(1) == Vector2i(5, 5), "after the committed step to (3,5) and its own two steps")
	check(turn.replace_orders(1, b.orders_for(1)) == "", "and it can be handed back unchanged")


func test_the_overlay_draws_a_move_fire_path_with_its_end_tick() -> void:
	var c := new_controller()
	c.click_tile(Vector2i(2, 5))
	c.set_mode(PlayController.MODE_MOVE_FIRE)
	c.click_tile(Vector2i(5, 5))
	var d := PlayOverlay.build(c)
	var texts: Array = d["overlay"]["marks"].map(func(m): return m["text"])
	check(texts.has("t%d" % (6 + fire_reserve())), "the label shows when the full action ends; got %s" % [texts])
	var fire_paths: Array = d["overlay"]["paths"].filter(func(p): return p["color"] == PlayOverlay.COL_FIRE)
	check(fire_paths.size() == 1 and fire_paths[0]["tiles"].back() == Vector2i(5, 5), "its path is drawn in the Move+Fire colour")
