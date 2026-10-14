class_name TestBase
extends RefCounted
## Shared assertions and scene builders for the headless test suites.

## The turn length, so tests state limits in terms of it.
const T := SimConst.TICKS_PER_TURN

## Set by run_tests.gd so a test can add nodes to the live scene tree.
static var tree: SceneTree
static var checks := 0
static var fails := 0


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		printerr("  FAIL: ", msg)


## Test states roll a fixed 1 on every shot, so a clear line always hits and
## older tests stay about their own subject. test_hit.gd switches this off.
func make_state(w := 12, h := 12) -> SimState:
	var s := SimState.new(SimGrid.new(w, h))
	s.fixed_roll = 1
	return s


func add_unit(s: SimState, id: int, team: int, pos: Vector2i, hp := 3, speed := 5, aim := 5, cqb := 5) -> SimUnit:
	var u := SimUnit.make(id, team, pos, hp, speed, aim, cqb)
	s.add_unit(u)
	return u


func events_of(r: SimResult, type: String) -> Array:
	return r.events.filter(func(e): return e["type"] == type)


func plan_of(id: int, actions: Array) -> SimPlan:
	var p := SimPlan.new()
	for a in actions:
		p.add(id, a)
	return p


func overwatch_scene(hold := 8, enemy_hp := 3) -> SimState:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(5, 5))   # watcher
	add_unit(s, 2, 1, Vector2i(0, 5), enemy_hp)  # mover
	return s


func mover_plan(steps := 3, watcher_hold := 8, facing := Vector2i.LEFT) -> SimPlan:
	var p := SimPlan.new()
	p.add(1, SimAction.overwatch(facing, watcher_hold))
	for i in steps:
		p.add(2, SimAction.move(Vector2i.RIGHT))
	return p


func snapshot(s: SimState) -> Array:
	var out := []
	var ids := s.units.keys()
	ids.sort()
	for id in ids:
		var u: SimUnit = s.units[id]
		out.append([id, u.pos, u.hp, u.alive])
	return out


func fog_scene() -> SimState:
	var s := make_state()
	add_unit(s, 1, 0, Vector2i(2, 5))
	add_unit(s, 2, 1, Vector2i(8, 5))    # distance 6: visible
	add_unit(s, 3, 1, Vector2i(11, 5))   # distance 9: out of sight range
	return s


func ai_profiles() -> Dictionary:
	return SimAIProfile.load_file("res://data/ai_profiles.json")["profiles"]


func plan_sig(p: SimPlan) -> String:
	var parts: Array[String] = []
	var ids := p.orders.keys()
	ids.sort()
	for id in ids:
		var acts: Array[String] = []
		for a: SimAction in p.orders[id]:
			acts.append("%s:%s:%d:%d" % [a.type, a.dir, a.target_id, a.wait_ticks])
		parts.append("%d=[%s]" % [id, ",".join(acts)])
	return ";".join(parts)


func actions_of(p: SimPlan, id: int, type: String) -> Array:
	return (p.orders.get(id, []) as Array).filter(func(a: SimAction) -> bool: return a.type == type)


func hidden_enemy_scene(hidden_at: Variant) -> SimState:
	# u1 has short sight (3) but a long gun (range 7): an enemy 5 tiles away
	# is inside weapon range yet outside vision. If the AI could see it, the
	# 1 hp hidden unit would be an irresistible kill.
	var s := make_state()
	var u := add_unit(s, 1, 1, Vector2i(8, 5))
	u.sight_range = 3
	add_unit(s, 2, 0, Vector2i(6, 5))
	if hidden_at != null:
		add_unit(s, 9, 0, hidden_at as Vector2i, 1)
	return s


var _fuzz_seed := 20261013


func _rnd(n: int) -> int:
	_fuzz_seed = (_fuzz_seed * 1103515245 + 12345) & 0x7fffffff
	return (_fuzz_seed >> 8) % n


## Orthogonal steps that exactly fill a turn.
@warning_ignore("integer_division")
func full_steps() -> int:
	return T / SimConst.COST_ORTHO


func rights(n: int) -> Array:
	var out := []
	for i in n:
		out.append(SimAction.move(Vector2i.RIGHT))
	return out
