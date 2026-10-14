class_name Scenarios
extends RefCounted
## Hand-authored scenes for the debug replay. Each returns
## {name, note, state, plan}. Add a new scenario by adding a name to NAMES
## and a matching _build_<n> function.

const NAMES: Array[String] = [
	"Overwatch ambush",
	"Flank vs cover",
	"Speed duels",
	"Contested tile + wall",
	"Squad skirmish",
	"AI vs AI: turn 1",
	"AI vs AI: turn 3",
]

const PROFILE_FILE := "res://data/ai_profiles.json"
const OBJECTIVES := {0: Vector2i(10, 5), 1: Vector2i(1, 5)}
const AI_PROFILE_BY_TEAM := {0: "aggressor", 1: "defender"}


static func count() -> int:
	return NAMES.size()


static func build(index: int) -> Dictionary:
	var sc: Dictionary
	match index:
		0: sc = _overwatch_ambush()
		1: sc = _flank_vs_cover()
		2: sc = _speed_duels()
		3: sc = _contested()
		4: sc = _skirmish()
		5: sc = _ai_match(0)
		_: sc = _ai_match(2)
	sc["name"] = NAMES[clampi(index, 0, NAMES.size() - 1)]
	return sc


static func _unit(s: SimState, id: int, team: int, pos: Vector2i, hp := 3, speed := 5, aim := 5, cqb := 5) -> void:
	s.add_unit(SimUnit.make(id, team, pos, hp, speed, aim, cqb))


static func _rights(plan: SimPlan, id: int, n: int, dir := Vector2i.RIGHT) -> void:
	for i in n:
		plan.add(id, SimAction.move(dir))


static func _overwatch_ambush() -> Dictionary:
	var s := SimState.new(SimGrid.new(12, 10))
	s.grid.set_edge(Vector2i(5, 2), Vector2i(5, 3), SimConst.EDGE_FULL)
	s.grid.set_edge(Vector2i(4, 6), Vector2i(5, 6), SimConst.EDGE_HALF)
	_unit(s, 1, 0, Vector2i(9, 5))
	_unit(s, 3, 0, Vector2i(9, 2))
	_unit(s, 2, 1, Vector2i(1, 5))
	_unit(s, 4, 1, Vector2i(1, 7), 2)
	var p := SimPlan.new()
	p.add(1, SimAction.overwatch(Vector2i.LEFT, 10))
	p.add(3, SimAction.overwatch(Vector2i(-1, 1), 12))
	_rights(p, 2, 5)
	_rights(p, 4, 5)
	return {"state": s, "plan": p, "note": "Blue watchers hold cones. Each fires once at the first red unit to finish a move in view."}


static func _flank_vs_cover() -> Dictionary:
	var s := SimState.new(SimGrid.new(12, 10))
	s.grid.set_edge(Vector2i(5, 4), Vector2i(6, 4), SimConst.EDGE_HALF)
	_unit(s, 1, 0, Vector2i(2, 4))
	_unit(s, 3, 0, Vector2i(6, 8))
	_unit(s, 2, 1, Vector2i(6, 4), 4)
	var p := SimPlan.new()
	p.add(1, SimAction.shoot(2))
	p.add(3, SimAction.move(Vector2i.UP))
	p.add(3, SimAction.shoot(2))
	return {"state": s, "plan": p, "note": "u1 shoots over the half wall (blocked). u3 flanks from the open side (hit)."}


static func _speed_duels() -> Dictionary:
	var s := SimState.new(SimGrid.new(12, 10))
	_unit(s, 1, 0, Vector2i(1, 2), 1, 6)
	_unit(s, 2, 1, Vector2i(6, 2), 1, 4)
	_unit(s, 3, 0, Vector2i(1, 7), 1, 5)
	_unit(s, 4, 1, Vector2i(6, 7), 1, 5)
	var p := SimPlan.new()
	p.add(1, SimAction.shoot(2))
	p.add(2, SimAction.shoot(1))
	p.add(3, SimAction.shoot(4))
	p.add(4, SimAction.shoot(3))
	return {"state": s, "plan": p, "note": "Top: faster u1 wins, u2's shot is cancelled. Bottom: equal speed, both die."}


static func _contested() -> Dictionary:
	var s := SimState.new(SimGrid.new(12, 10))
	s.grid.set_edge(Vector2i(5, 6), Vector2i(6, 6), SimConst.EDGE_FULL)
	_unit(s, 1, 0, Vector2i(3, 2), 3, 5)
	_unit(s, 2, 1, Vector2i(5, 2), 3, 3)
	_unit(s, 3, 0, Vector2i(3, 6))
	var p := SimPlan.new()
	p.add(1, SimAction.move(Vector2i.RIGHT))
	p.add(2, SimAction.move(Vector2i.LEFT))
	_rights(p, 3, 4)
	return {"state": s, "plan": p, "note": "Faster u1 takes the contested tile; u2 stops short. u3 walks into a wall and halts."}


## The skirmish terrain with nobody on it (campaign missions share it).
static func map_state() -> SimState:
	var s := SimState.new(SimGrid.new(12, 10))
	s.grid.set_edge(Vector2i(5, 3), Vector2i(6, 3), SimConst.EDGE_FULL)
	s.grid.set_edge(Vector2i(5, 4), Vector2i(6, 4), SimConst.EDGE_FULL)
	s.grid.set_edge(Vector2i(6, 6), Vector2i(7, 6), SimConst.EDGE_HALF)
	s.grid.set_edge(Vector2i(6, 7), Vector2i(7, 7), SimConst.EDGE_HALF)
	s.grid.set_blocked(Vector2i(5, 5))
	return s


static func skirmish_state() -> SimState:
	var s := map_state()
	_unit(s, 1, 0, Vector2i(2, 4), 3, 6)
	_unit(s, 2, 0, Vector2i(2, 6), 3, 5, 7)
	_unit(s, 3, 0, Vector2i(1, 5), 3, 4)
	_unit(s, 4, 1, Vector2i(9, 4), 3, 5)
	_unit(s, 5, 1, Vector2i(9, 6), 3, 6)
	_unit(s, 6, 1, Vector2i(10, 5), 3, 4)
	return s


static func _skirmish() -> Dictionary:
	var s := skirmish_state()
	var p := SimPlan.new()
	p.add(1, SimAction.overwatch(Vector2i.RIGHT, 6))
	_rights(p, 2, 2)
	p.add(2, SimAction.shoot(5))
	_rights(p, 3, 2)
	p.add(3, SimAction.overwatch(Vector2i.RIGHT, 6))
	_rights(p, 4, 2, Vector2i.LEFT)
	p.add(4, SimAction.shoot(1))
	p.add(5, SimAction.overwatch(Vector2i.LEFT, 4))
	_rights(p, 5, 2, Vector2i.LEFT)
	_rights(p, 6, 2, Vector2i(-1, -1))
	p.add(6, SimAction.shoot(1))
	return {"state": s, "plan": p, "note": "3v3 with walls, cover, a crate, overwatch and a shot with no line of sight."}


## Both teams planned by SimAI from their own fog-filtered views.
static func ai_plan(state: SimState, profiles: Dictionary) -> SimPlan:
	var merged := SimPlan.new()
	for team in [0, 1]:
		var assign := {}
		for id in state.units:
			if (state.units[id] as SimUnit).team == team:
				assign[id] = AI_PROFILE_BY_TEAM[team]
		merged = merged.merged(SimAI.plan_for(state, team, profiles, assign, OBJECTIVES[team]))
	return merged


## Play `turns` full AI-vs-AI turns from `start` and return the resulting
## state. `start` is not mutated.
static func play_ai_turns(start: SimState, turns: int) -> SimState:
	var profiles: Dictionary = SimAIProfile.load_file(PROFILE_FILE)["profiles"]
	var s := start
	for i in turns:
		s = SimResolver.resolve(s, ai_plan(s, profiles)).state
	return s


static func _ai_match(turns_before: int) -> Dictionary:
	var profiles: Dictionary = SimAIProfile.load_file(PROFILE_FILE)["profiles"]
	var s := play_ai_turns(skirmish_state(), turns_before)
	return {
		"state": s,
		"plan": ai_plan(s, profiles),
		"note": "Both sides planned by the utility AI from their own fog view (blue aggressor, red defender). Turn %d of an AI-vs-AI match." % (turns_before + 1),
	}
