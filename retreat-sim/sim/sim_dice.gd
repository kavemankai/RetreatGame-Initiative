class_name SimDice
extends RefCounted
## Seeded, stateless dice. A roll is a pure hash of its inputs, so it never
## depends on call order: stepping, one-shot resolution and replays agree.

const MASK := 0x7fffffff


## `nth` separates several rolls by one unit on the same tick (its hit count).
static func d100(seed: int, turn: int, tick: int, unit_id: int, nth: int = 0) -> int:
	return _hash(seed, turn, tick, unit_id, nth) % 100 + 1


static func d10(seed: int, turn: int, tick: int, unit_id: int, nth: int = 0) -> int:
	return _hash(seed, turn, tick, unit_id, nth) % SimConst.MORALE_DIE + 1


static func _hash(seed: int, turn: int, tick: int, unit_id: int, nth: int) -> int:
	var h := (seed * 1000003 + turn) & MASK
	h = (h * 1000003 + nth) & MASK
	h = (h * 1000003 + tick) & MASK
	h = (h * 1000003 + unit_id) & MASK
	h ^= h >> 15
	h = (h * 0x2c1b3c6d) & MASK
	h ^= h >> 12
	h = (h * 0x297a2d39) & MASK
	h ^= h >> 15
	return h
