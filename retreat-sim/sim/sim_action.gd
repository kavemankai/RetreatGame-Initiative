class_name SimAction
extends RefCounted

var type: String
var dir: Vector2i = Vector2i.ZERO
var target_id: int = -1
var wait_ticks: int = 0
## Move and Fire: one unit step per tile of the path.
var steps: Array[Vector2i] = []


static func move(d: Vector2i) -> SimAction:
	var a := SimAction.new()
	a.type = SimConst.ACTION_MOVE
	a.dir = d
	return a


static func shoot(p_target_id: int) -> SimAction:
	var a := SimAction.new()
	a.type = SimConst.ACTION_SHOOT
	a.target_id = p_target_id
	return a


static func wait(ticks: int) -> SimAction:
	var a := SimAction.new()
	a.type = SimConst.ACTION_WAIT
	a.wait_ticks = ticks
	return a


## Walk `p_steps` (one unit step per tile) and take a shot if one comes up on
## the way. Costs the path plus a reserved double shot, paid even if nothing is
## fired at. Fires at most once, at the first step that has a visible target.
static func move_fire(p_steps: Array[Vector2i]) -> SimAction:
	var a := SimAction.new()
	a.type = SimConst.ACTION_MOVE_FIRE
	a.steps = p_steps.duplicate()
	return a


## Hold a 90-degree cone facing `facing` (one of 8 directions) for `hold_ticks`.
## Fires once at the first enemy that finishes a move inside the cone.
static func overwatch(facing: Vector2i, hold_ticks: int) -> SimAction:
	var a := SimAction.new()
	a.type = SimConst.ACTION_OVERWATCH
	a.dir = facing
	a.wait_ticks = hold_ticks
	return a


func cost(unit: SimUnit) -> int:
	match type:
		SimConst.ACTION_MOVE:
			return unit.step_cost(dir)
		SimConst.ACTION_SHOOT:
			return unit.shot_ticks()
		SimConst.ACTION_MOVE_FIRE:
			var total := unit.shot_ticks() * SimConst.MOVE_FIRE_SHOT_FACTOR
			for d in steps:
				total += unit.step_cost(d)
			return total
		SimConst.ACTION_WAIT, SimConst.ACTION_OVERWATCH:
			return maxi(1, wait_ticks)
	return SimConst.TICKS_PER_TURN + 1


func is_valid_shape() -> bool:
	if type == SimConst.ACTION_MOVE:
		return dir != Vector2i.ZERO and absi(dir.x) <= 1 and absi(dir.y) <= 1
	if type == SimConst.ACTION_SHOOT:
		return target_id >= 0
	if type == SimConst.ACTION_MOVE_FIRE:
		if steps.is_empty():
			return false
		for d in steps:
			if d == Vector2i.ZERO or absi(d.x) > 1 or absi(d.y) > 1:
				return false
		return true
	if type == SimConst.ACTION_OVERWATCH:
		return dir != Vector2i.ZERO and absi(dir.x) <= 1 and absi(dir.y) <= 1 and wait_ticks >= 1
	return type == SimConst.ACTION_WAIT and wait_ticks >= 1
