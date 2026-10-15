class_name SimUnit
extends RefCounted

var id: int
var team: int
var pos: Vector2i
var hp: int
var speed: int
var aim: int
var cqb: int
var morale: int = 5
var stress_penalty: int = 0
var is_drone: bool = false
var alive: bool = true
var damage: int = 1
var weapon_range: int = 6
var weapon_shot_ticks: int = 4
var sight_range: int = SimConst.SIGHT_RANGE
var hit_bonus: int = 0  # gear accuracy, in percentage points
var watch_dir: Vector2i = Vector2i.ZERO  # a sentry's facing while it sees no one (set by the map)
var gear_trait: String = ""  # the mod slot's trait: scope, sprinter, bracing, opener
var weapon_class: String = "rifle"  # the equipped weapon's class (rifle, carbine, sniper, shotgun, heavy, grenade, beam)
var weapon_trait: String = ""       # the weapon's own trait: beam, area or burst
var counters: Dictionary = {}


static func make(p_id: int, p_team: int, p_pos: Vector2i, p_hp: int, p_speed: int, p_aim: int = 5, p_cqb: int = 5) -> SimUnit:
	var u := SimUnit.new()
	u.id = p_id
	u.team = p_team
	u.pos = p_pos
	u.hp = p_hp
	u.speed = p_speed
	u.aim = p_aim
	u.cqb = p_cqb
	return u


## A JSON-safe copy of every field (positions as [x, y]).
func to_dict() -> Dictionary:
	return {"id": id, "team": team, "pos": [pos.x, pos.y], "hp": hp, "speed": speed, "aim": aim, "cqb": cqb, "morale": morale,
		"stress_penalty": stress_penalty, "is_drone": is_drone, "alive": alive, "damage": damage, "weapon_range": weapon_range,
		"weapon_shot_ticks": weapon_shot_ticks, "sight_range": sight_range, "hit_bonus": hit_bonus,
		"watch_dir": [watch_dir.x, watch_dir.y], "gear_trait": gear_trait, "weapon_class": weapon_class, "weapon_trait": weapon_trait,
		"counters": counters.duplicate()}


## The unit from to_dict, tolerating JSON's floats for integers.
static func from_dict(d: Dictionary) -> SimUnit:
	var pos_a: Array = d["pos"]
	var u := SimUnit.make(int(d["id"]), int(d["team"]), Vector2i(int(pos_a[0]), int(pos_a[1])), int(d["hp"]), int(d["speed"]), int(d["aim"]), int(d["cqb"]))
	u.morale = int(d["morale"])
	u.stress_penalty = int(d["stress_penalty"])
	u.is_drone = bool(d["is_drone"])
	u.alive = bool(d["alive"])
	u.damage = int(d["damage"])
	u.weapon_range = int(d["weapon_range"])
	u.weapon_shot_ticks = int(d["weapon_shot_ticks"])
	u.sight_range = int(d["sight_range"])
	u.hit_bonus = int(d["hit_bonus"])
	var watch_a: Array = d["watch_dir"]
	u.watch_dir = Vector2i(int(watch_a[0]), int(watch_a[1]))
	u.gear_trait = String(d["gear_trait"])
	u.weapon_class = String(d.get("weapon_class", "rifle"))
	u.weapon_trait = String(d.get("weapon_trait", ""))
	for k in d["counters"]:
		u.counters[k] = int(d["counters"][k])
	return u


func clone() -> SimUnit:
	var u := SimUnit.make(id, team, pos, hp, speed, aim, cqb)
	u.morale = morale
	u.stress_penalty = stress_penalty
	u.is_drone = is_drone
	u.alive = alive
	u.damage = damage
	u.weapon_range = weapon_range
	u.weapon_shot_ticks = weapon_shot_ticks
	u.sight_range = sight_range
	u.hit_bonus = hit_bonus
	u.gear_trait = gear_trait
	u.weapon_class = weapon_class
	u.weapon_trait = weapon_trait
	u.watch_dir = watch_dir
	u.counters = counters.duplicate()
	return u


## Ticks this unit may spend in a turn. Drones have no morale and ignore stress.
func available_ticks() -> int:
	if is_drone:
		return SimConst.TICKS_PER_TURN
	return maxi(0, SimConst.TICKS_PER_TURN - stress_penalty)


@warning_ignore("integer_division")
func max_range() -> int:
	return weapon_range + aim / SimConst.AIM_RANGE_DIVISOR


func shot_ticks() -> int:
	var t := weapon_shot_ticks
	if aim >= SimConst.AIM_FAST_SHOT:
		t -= 1
	return maxi(SimConst.MIN_SHOT_TICKS, t)


## Ticks one step costs this unit (sprinters move diagonally at the straight price).
func step_cost(d: Vector2i) -> int:
	if d.x != 0 and d.y != 0 and gear_trait != "sprinter":
		return SimConst.COST_DIAG
	return SimConst.COST_ORTHO


## How dug in the unit is (see SimConst.COVER_SHIFT_STEP): added to the cover penalty on shots at it.
func cover_shift() -> int:
	return int(counters.get("cover_shift", 0))


## A beam ignores half cover (a full wall still blocks it).
func ignores_half_cover() -> bool:
	return weapon_trait == "beam"


## An area weapon's shot also hits the eight tiles around its target.
func is_area() -> bool:
	return weapon_trait == "area"


## Shots one shooting action fires: three for a burst weapon, else one.
func burst_count() -> int:
	return SimConst.BURST_COUNT if weapon_trait == "burst" else 1


## Percent chance a clear shot from here lands at `distance` (a beam loses nothing to range).
func hit_chance_at(distance: int) -> int:
	var c := SimConst.HIT_BASE + SimConst.HIT_PER_AIM * aim + hit_bonus
	if weapon_trait != "beam":
		c -= SimConst.HIT_RANGE_PENALTY * maxi(0, distance - SimConst.HIT_FREE_RANGE)
	return clampi(c, SimConst.HIT_MIN, SimConst.HIT_MAX)


func damage_at(distance: int) -> int:
	if cqb >= SimConst.CQB_BONUS_MIN and distance <= SimConst.CQB_BONUS_DISTANCE:
		return damage + 1
	return damage


func bump(counter: String, amount: int = 1) -> void:
	counters[counter] = int(counters.get(counter, 0)) + amount
