class_name CombatAction
extends RefCounted
## A typed command request: the only way anything changes in a CombatState.

const MOVE := "move"
const SHOOT := "shoot"
const OVERWATCH := "overwatch"
const END_TURN := "end_turn"

var actor_id: int
var type: String
var target_cell := Vector2i.ZERO
var target_id := -1
var dir := Vector2i.ZERO


static func move_to(p_actor: int, tile: Vector2i) -> CombatAction:
	var a := CombatAction.new()
	a.actor_id = p_actor
	a.type = MOVE
	a.target_cell = tile
	return a


static func shoot(p_actor: int, p_target: int) -> CombatAction:
	var a := CombatAction.new()
	a.actor_id = p_actor
	a.type = SHOOT
	a.target_id = p_target
	return a


static func overwatch(p_actor: int, p_dir: Vector2i) -> CombatAction:
	var a := CombatAction.new()
	a.actor_id = p_actor
	a.type = OVERWATCH
	a.dir = p_dir
	return a


static func end_turn(p_actor: int) -> CombatAction:
	var a := CombatAction.new()
	a.actor_id = p_actor
	a.type = END_TURN
	return a
