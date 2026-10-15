extends TestBase
## Dug in and exposed: a unit that holds fire gains cover at the start of its next activation, one that shot
## loses some, a step to a new tile resets it, and the shift changes the real hit chance and survives a save.

const STEP := SimConst.COVER_SHIFT_STEP
const CAP := SimConst.COVER_SHIFT_MAX


## Shooter 1 (team 0) at (5,1); target 200 (team 1, acts first) at (8,1) with a half wall on its near side.
func scene() -> CombatState:
	var s := make_state(16, 12)
	s.seed = 3
	s.grid.set_edge(Vector2i(7, 1), Vector2i(8, 1), SimConst.EDGE_HALF)
	add_unit(s, 1, 0, Vector2i(5, 1), 50, 5, 5)
	add_unit(s, 200, 1, Vector2i(8, 1), 50, 7, 5)
	var cs := CombatState.create(s)
	ActivationScheduler.start(cs)
	return cs


## Plays the other unit's activation and any pending ones until `id` is active (ending turns without acting).
func until_active(cs: CombatState, id: int) -> void:
	var guard := 0
	while cs.active_id != id and guard < 10:
		ActionResolver.submit(cs, CombatAction.end_turn(cs.active_id))
		guard += 1


func shift(cs: CombatState, id: int) -> int:
	return (cs.sim.units[id] as SimUnit).cover_shift()


func test_holding_fire_digs_in_up_to_the_cap() -> void:
	var cs := scene()
	var seen: Array[int] = []
	for i in 5:
		until_active(cs, 200)
		seen.append(shift(cs, 200))
		ActionResolver.submit(cs, CombatAction.end_turn(200))
	check(seen == [0, STEP, 2 * STEP, CAP, CAP], "no shift on the first activation, then +%d each time up to +%d (%s)" % [STEP, CAP, seen])


func test_shooting_wears_cover_down_to_the_floor() -> void:
	var cs := scene()
	var seen: Array[int] = []
	for i in 5:
		until_active(cs, 200)
		seen.append(shift(cs, 200))
		var r := ActionResolver.submit(cs, CombatAction.shoot(200, 1))
		check(r.success, "the shot is legal (%s)" % [r.reason])
		ActionResolver.submit(cs, CombatAction.end_turn(200))
	check(seen == [0, -STEP, -2 * STEP, -CAP, -CAP], "each shot costs %d cover at the next activation, down to -%d (%s)" % [STEP, CAP, seen])


func test_a_step_to_a_new_tile_resets_it() -> void:
	var cs := scene()
	for i in 3:
		until_active(cs, 200)
		ActionResolver.submit(cs, CombatAction.end_turn(200))
	until_active(cs, 200)
	check(shift(cs, 200) == 2 * STEP, "two quiet turns built +%d" % (2 * STEP))
	ActionResolver.submit(cs, CombatAction.move_to(200, Vector2i(9, 1)))
	check(shift(cs, 200) == 0, "stepping to another tile starts over")


func test_the_shift_changes_the_shot_chance() -> void:
	var cs := scene()
	var shooter: SimUnit = cs.sim.units[1]
	var target: SimUnit = cs.sim.units[200]
	var base := SimResolver.evaluate_shot(cs.sim.grid, shooter, shooter.pos, target)
	check(base["cover_penalty"] == SimConst.COVER_HIT_PENALTY, "neutral cover costs %d points" % SimConst.COVER_HIT_PENALTY)
	target.counters["cover_shift"] = CAP
	var dug := SimResolver.evaluate_shot(cs.sim.grid, shooter, shooter.pos, target)
	target.counters["cover_shift"] = -CAP
	var exposed := SimResolver.evaluate_shot(cs.sim.grid, shooter, shooter.pos, target)
	check(int(dug["chance"]) < int(base["chance"]) and int(base["chance"]) < int(exposed["chance"]), "dug in is hardest to hit, exposed easiest (%d < %d < %d)" % [dug["chance"], base["chance"], exposed["chance"]])
	check(dug["cover_penalty"] == SimConst.COVER_HIT_PENALTY + CAP and exposed["cover_penalty"] == SimConst.COVER_HIT_PENALTY - CAP, "the preview reports the real penalty")
	check(UiModel.shot_notes(dug).contains("-%d%%" % (SimConst.COVER_HIT_PENALTY + CAP)), "and the shot note says so")


func test_the_shift_survives_a_save() -> void:
	var cs := scene()
	for i in 3:
		until_active(cs, 200)
		ActionResolver.submit(cs, CombatAction.end_turn(200))
	var again := CombatSave.from_dict(JSON.parse_string(JSON.stringify(CombatSave.to_dict(cs))), cs.sim.grid, null)
	check(again != null and (again.sim.units[200] as SimUnit).cover_shift() == shift(cs, 200) and shift(cs, 200) > 0, "a dug-in unit is still dug in after a save and load")


func test_the_hint_line_names_the_state() -> void:
	var u := SimUnit.make(1, 0, Vector2i.ZERO, 3, 5)
	check(UiModel.dug_in_text(u).contains("Hold fire"), "neutral: how to dig in")
	u.counters["cover_shift"] = STEP
	check(UiModel.dug_in_text(u).contains("Dug in") and UiModel.dug_in_text(u).contains("+%d%%" % STEP), "dug in")
	u.counters["cover_shift"] = -STEP
	check(UiModel.dug_in_text(u).contains("Exposed"), "exposed")
