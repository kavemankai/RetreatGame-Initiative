extends TestBase
## Ordered fire, morale checks on a hit, and the seeded morale die.

const STEADY := 99   # morale so high every roll passes
const SHAKY := -99  # morale so low every roll fails


## Two units face each other 3 tiles apart on an open row.
func duel(speed_a := 5, speed_b := 5, aim_a := 5, aim_b := 5, hp := 3) -> SimState:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(2, 5), hp, speed_a, aim_a)
	add_unit(s, 2, 1, Vector2i(5, 5), hp, speed_b, aim_b)
	return s


func shots_of(r: SimResult) -> Array:
	return events_of(r, "shot")


func both_shoot(s: SimState) -> SimPlan:
	var p := SimPlan.new()
	p.add(1, SimAction.shoot(2))
	p.add(2, SimAction.shoot(1))
	return p


func test_faster_hit_cancels_the_slower_return_shot() -> void:
	var s := duel(7, 5)
	s.units[2].morale = STEADY
	var r := SimResolver.resolve(s, both_shoot(s))
	var shots := shots_of(r)
	check(shots.size() == 1 and shots[0]["unit"] == 1 and shots[0]["result"] == "hit", "only the faster unit fires, and hits")
	var cancelled := events_of(r, "cancelled").filter(func(e): return e["unit"] == 2)
	check(cancelled.size() == 1 and cancelled[0]["reason"] == "suppressed", "the hit unit's return shot is cancelled as suppressed")
	check(r.state.units[1].hp == 3, "the faster unit takes no damage")


func test_a_shot_into_cover_that_misses_lets_the_slower_unit_return_fire() -> void:
	var s := duel(7, 5)
	s.fixed_roll = 100  # every roll misses
	s.grid.set_edge(Vector2i(4, 5), Vector2i(5, 5), SimConst.EDGE_HALF)  # cover beside unit 2
	var r := SimResolver.resolve(s, both_shoot(s))
	var shots := shots_of(r)
	check(shots.size() == 2, "both fire")
	check(shots[0]["unit"] == 1 and shots[0]["result"] == "miss", "the faster shot goes first and misses the covered target")
	check(shots[1]["unit"] == 2 and shots[1]["result"] == "miss", "the slower unit gets its shot back (fixed dice: it misses too)")


func test_equal_speed_breaks_ties_on_aim_then_id() -> void:
	var s := duel(5, 5, 4, 7)
	s.units[1].morale = STEADY
	var r := SimResolver.resolve(s, both_shoot(s))
	check(shots_of(r).size() == 1 and shots_of(r)[0]["unit"] == 2, "equal speed: the better aim fires first")
	var t := duel(5, 5, 5, 5)
	t.units[2].morale = STEADY
	var r2 := SimResolver.resolve(t, both_shoot(t))
	check(shots_of(r2).size() == 1 and shots_of(r2)[0]["unit"] == 1, "equal speed and aim: lower id fires first")


func test_no_mutual_kill_in_one_tick() -> void:
	var s := duel(5, 5, 5, 5, 1)
	var r := SimResolver.resolve(s, both_shoot(s))
	var dead := [r.state.units[1].alive, r.state.units[2].alive].count(false)
	check(dead == 1 and r.state.units[1].alive, "exactly one dies: the first to fire survives")


func test_steady_unit_keeps_moving_but_cannot_shoot() -> void:
	var s := duel(7, 5)
	s.units[2].morale = STEADY
	var p := SimPlan.new()
	p.add(1, SimAction.shoot(2))
	p.add(2, SimAction.shoot(1))  # lost to the hit
	p.add(2, SimAction.move(Vector2i.DOWN))
	p.add(2, SimAction.shoot(1))  # dropped: suppressed for the round
	var r := SimResolver.resolve(s, p)
	var morale := events_of(r, "morale")
	check(morale.size() == 1 and morale[0]["result"] == "steady", "a steady morale result is logged")
	check(r.state.units[2].pos == Vector2i(5, 6), "the steady unit still makes its move")
	check(shots_of(r).filter(func(e): return e["unit"] == 2).is_empty(), "and never fires again this round")


func test_steady_move_fire_takes_no_shot() -> void:
	var s := duel(7, 5)
	s.units[2].morale = STEADY
	var p := SimPlan.new()
	p.add(1, SimAction.shoot(2))  # lands on tick 4
	p.add(2, SimAction.wait(4))   # still holding when hit
	var steps: Array[Vector2i] = [Vector2i.UP, Vector2i.UP, Vector2i.UP]
	p.add(2, SimAction.move_fire(steps))
	var r := SimResolver.resolve(s, p)
	check(shots_of(r).filter(func(e): return e["unit"] == 2).is_empty(), "a suppressed Move+Fire never shoots")
	check(r.state.units[2].pos == Vector2i(5, 2), "but it finishes its walk")
	var calm := duel(7, 5)
	calm.units[2].morale = STEADY
	var q := SimPlan.new()
	q.add(2, SimAction.wait(4))
	q.add(2, SimAction.move_fire(steps))
	check(not shots_of(SimResolver.resolve(calm, q)).is_empty(), "control: unhit, the same Move+Fire does shoot")


func test_steady_watcher_loses_its_overwatch() -> void:
	var p := SimPlan.new()
	p.add(1, SimAction.wait(4))
	p.add(1, SimAction.shoot(2))       # lands on tick 8
	p.add(2, SimAction.overwatch(Vector2i.DOWN, T))
	p.add(3, SimAction.wait(8))
	for i in 3:
		p.add(3, SimAction.move(Vector2i.UP))  # walks into the cone from tick 10
	var s := duel(7, 5)
	s.units[2].morale = STEADY
	add_unit(s, 3, 0, Vector2i(5, 9))
	var r := SimResolver.resolve(s, p)
	check(shots_of(r).filter(func(e): return e["unit"] == 2).is_empty(), "a suppressed watcher's overwatch never triggers")
	var control := duel(7, 5)
	add_unit(control, 3, 0, Vector2i(5, 9))
	var q := SimPlan.new()
	q.add(2, SimAction.overwatch(Vector2i.DOWN, T))
	q.add(3, SimAction.wait(8))
	for i in 3:
		q.add(3, SimAction.move(Vector2i.UP))
	check(not shots_of(SimResolver.resolve(control, q)).filter(func(e): return e["unit"] == 2).is_empty(), "control: unhit, the watch fires")


func test_broken_unit_stops_all_orders() -> void:
	var s := duel(7, 5)
	s.units[2].morale = SHAKY
	var p := SimPlan.new()
	p.add(1, SimAction.shoot(2))
	p.add(2, SimAction.wait(4))
	p.add(2, SimAction.move(Vector2i.DOWN))
	var r := SimResolver.resolve(s, p)
	var morale := events_of(r, "morale")
	check(morale.size() == 1 and morale[0]["result"] == "broken", "a broken result is logged")
	check(r.state.units[2].pos == Vector2i(5, 5), "a broken unit makes no further moves")


func test_base_unit_is_seventy_thirty_on_a_first_hit() -> void:
	var s := duel(7, 5)  # morale 5, the base for a regular
	var r := SimResolver.resolve(s, plan_of(1, [SimAction.shoot(2)]))
	check(events_of(r, "morale")[0]["need"] == 7, "a base unit's first hit needs 7 or less on a d10: 70% steady, 30% broken")


func test_morale_need_drops_with_wounds() -> void:
	var s := duel(7, 5, 5, 5, 4)
	s.units[2].morale = 6
	var p := SimPlan.new()
	p.add(1, SimAction.shoot(2))
	p.add(1, SimAction.shoot(2))
	var r := SimResolver.resolve(s, p)
	var needs := events_of(r, "morale").map(func(e): return e["need"])
	check(needs.size() >= 1 and needs[0] == 8, "first hit: morale 6 + 3 - 1 wound")
	if needs.size() == 2:
		check(needs[1] == 7, "second hit: one fewer")


func test_cover_adds_one_to_the_check() -> void:
	var open := duel(7, 5)
	var covered := duel(7, 5)
	covered.grid.set_edge(Vector2i(5, 5), Vector2i(5, 6), SimConst.EDGE_HALF)  # a low wall beside unit 2, not on the shot line
	var p := plan_of(1, [SimAction.shoot(2)])
	var need_open: int = events_of(SimResolver.resolve(open, p), "morale")[0]["need"]
	var need_cover: int = events_of(SimResolver.resolve(covered, p), "morale")[0]["need"]
	check(need_cover == need_open + 1, "standing beside cover is +1")
	var crate := duel(7, 5)
	crate.grid.set_blocked(Vector2i(5, 4))
	check(events_of(SimResolver.resolve(crate, p), "morale")[0]["need"] == need_open + 1, "a crate beside the unit counts as cover too")


func test_dice_are_stateless_in_range_and_seed_dependent() -> void:
	var same := SimDice.d10(7, 1, 3, 2) == SimDice.d10(7, 1, 3, 2)
	check(same, "same inputs, same roll")
	var in_range := true
	var differs := 0
	var seen := {}
	for i in 200:
		var a := SimDice.d10(1, 1, i % 20 + 1, i)
		var b := SimDice.d10(2, 1, i % 20 + 1, i)
		in_range = in_range and a >= 1 and a <= SimConst.MORALE_DIE and b >= 1 and b <= SimConst.MORALE_DIE
		differs += 1 if a != b else 0
		seen[a] = true
	check(in_range, "rolls are 1..10")
	check(differs > 100, "a different seed changes most rolls")
	check(seen.size() == SimConst.MORALE_DIE, "every face comes up")


func test_hollows_never_break_and_keep_shooting_after_a_hit() -> void:
	var s := duel(7, 5)
	s.units[2].is_drone = true
	s.units[2].morale = 0
	var p := SimPlan.new()
	p.add(1, SimAction.shoot(2))
	p.add(2, SimAction.wait(4))
	p.add(2, SimAction.shoot(1))
	var r := SimResolver.resolve(s, p)
	check(events_of(r, "morale").filter(func(e): return e["unit"] == 2).is_empty(), "no morale check for a Hollow")
	check(shots_of(r).any(func(e): return e["unit"] == 2), "the hit Hollow still fires its queued shot")


func test_stepping_matches_resolve_with_dice() -> void:
	for seed in [1, 2, 3, 4, 5]:
		var s := duel(7, 5)
		s.seed = seed
		s.units[2].morale = 5
		var p := SimPlan.new()
		p.add(1, SimAction.shoot(2))
		p.add(2, SimAction.shoot(1))
		p.add(2, SimAction.move(Vector2i.DOWN))
		var once := SimResolver.resolve(s, p)
		var run := SimTurn.new(s, p)
		while not run.is_finished():
			run.advance()
		check(snapshot(once.state) == snapshot(run.state) and once.events == run.events, "seed %d: stepped equals resolve" % seed)


func test_a_broken_unit_takes_no_further_morale_checks() -> void:
	var s := duel(7, 5, 5, 5, 6)
	s.units[2].morale = SHAKY
	var p := SimPlan.new()
	for i in 4:
		p.add(1, SimAction.shoot(2))
	var r := SimResolver.resolve(s, p)
	var checks := events_of(r, "morale")
	check(checks.size() == 1 and checks[0]["result"] == "broken", "once broken, later hits this round roll no morale")


func test_two_hits_in_one_tick_roll_separately() -> void:
	var a := SimDice.d10(5, 1, 4, 2, 1)
	var differs := false
	for seed in range(1, 30):
		differs = differs or SimDice.d10(seed, 1, 4, 2, 1) != SimDice.d10(seed, 1, 4, 2, 2)
	check(a >= 1 and a <= 10 and differs, "the hit count is part of the roll, so a second hit is a fresh roll")


func test_broken_units_refuse_new_orders_and_suppressed_units_cannot_reacquire_fire() -> void:
	var s := duel(7, 5)
	s.units[2].morale = SHAKY
	var run := SimTurn.new(s, plan_of(1, [SimAction.shoot(2)]))
	while run.tick < 4:
		run.advance()
	check(run.is_broken(2), "the hit unit is broken")
	check(run.replace_orders(2, [SimAction.move(Vector2i.DOWN)]) != "", "a broken unit cannot be given new orders this round")
	check(run.replace_orders(2, []) == "", "clearing its (empty) orders is still fine")
	var t := duel(7, 5)
	t.units[2].morale = STEADY
	var run2 := SimTurn.new(t, plan_of(1, [SimAction.shoot(2)]))
	while run2.tick < 4:
		run2.advance()
	check(run2.replace_orders(2, [SimAction.overwatch(Vector2i.LEFT, 6), SimAction.shoot(1), SimAction.move(Vector2i.DOWN)]) == "", "a suppressed unit can still be re-ordered")
	var kinds := run2.remaining_actions(2).map(func(a: SimAction) -> String: return a.type)
	check(kinds == [SimConst.ACTION_MOVE], "but its new shots and watches are stripped; got %s" % [kinds])
	check(run2.watchers().is_empty(), "and it never shows an overwatch cone")


func test_morale_halt_reports_idle() -> void:
	var s := duel(7, 5)
	s.units[2].morale = SHAKY
	var p := plan_of(1, [SimAction.shoot(2)])
	p.add(2, SimAction.wait(8))
	var run := SimTurn.new(s, p)
	var idle_seen := false
	while not run.is_finished():
		run.advance()
		idle_seen = idle_seen or run.last_idle.has(2)
	check(idle_seen, "a broken unit is reported idle so the log can say it has stopped")
