class_name SimState
extends RefCounted

var grid: SimGrid
var units: Dictionary = {}  # id -> SimUnit
var turn: int = 0
## Mission seed for the morale die (SimDice). Same seed, same rolls.
var seed: int = 0
## Tests and tools only: >= 0 forces every hit roll to this value (1 = always hit).
var fixed_roll: int = -1


func _init(p_grid: SimGrid) -> void:
	grid = p_grid


func add_unit(u: SimUnit) -> void:
	units[u.id] = u


## The grid is treated as immutable during resolution and shared by reference.
func clone() -> SimState:
	var s := SimState.new(grid)
	s.turn = turn
	s.seed = seed
	s.fixed_roll = fixed_roll
	for id in units:
		s.units[id] = (units[id] as SimUnit).clone()
	return s


func unit_at(tile: Vector2i) -> SimUnit:
	for id in units:
		var u: SimUnit = units[id]
		if u.alive and u.pos == tile:
			return u
	return null
