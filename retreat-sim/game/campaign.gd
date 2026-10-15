class_name Campaign
extends RefCounted
## The campaign layer above single missions: the roster of slots, the
## Hollowing, the retreat economy, Orrick's squad (the Writ), choices and
## endings. Pure data and rules, driven by the story files; no UI.
##
## Slot statuses: "absent" (not joined yet), "named", "hollow", "vacant".
## A dead named merc becomes a hollow automatically (the Muster Law); each
## refill costs reserves, and with none the slot goes vacant.

const OVER_ENDING := "campaign_over"
const SAVE_VERSION := 3  # 3: the roster of eight and weapon classes; older saves use the old twelve slots and are refused
const PCT_BASE := 100
const GEAR_SLOTS: Array[String] = ["armour", "weapon", "mod"]
const PROVOST_ID := 100
const WRIT_ID_BASE := 100     # + officer slot
const HOLLOW_PREFIX := "hollow_"
const FIRST_TIER_ID := 200    # conscript 200, regular 210, veteran 220; hollows +100
## Difficulty: Standard is the designed fight. Story gives the squad one more hit point and takes
## accuracy points off every enemy, so a casual player can reach the ending.
const DIFFICULTIES := {
	"standard": {"label": "Standard", "squad_hp": 0, "enemy_hit": 0},
	"story": {"label": "Story", "squad_hp": 1, "enemy_hit": -15},
}

var story: Dictionary
var difficulty := "standard"   # a key of DIFFICULTIES; saved with the campaign
var procession := 0
var reserves := 0
var remembrance := 0
var flags: Dictionary = {}
var completed: Array[String] = []
var current := ""
var over := false
var finished := false
var ending := ""
## Why the campaign ended: squad_lost | no_one_left | procession_lost.
var over_reason := ""
## Debrief steps the player still has to see (persisted, so quitting between
## a mission and its roll calls / choices loses nothing).
var pending: Array = []
## A contingency card drawn for the next briefing but not yet played.
var offered_card := ""

## Items found and not worn, by id (duplicates allowed).
var stash: Array[String] = []
var _items: Dictionary = {}    # item id -> definition, built on first use
var _roster: Dictionary = {}   # slot -> {"status", "stats", "gear": {armour, weapon, mod}, plus the levelling fields (see _entry)}
var campaign_seed := 20261015  # seeds the level-up offers (see levelup_offer)
var _writ: Dictionary = {}     # officer id -> "named" | "hollow"
var _drawn: Array[String] = []


static func new_game(p_story: Dictionary) -> Campaign:
	var c := Campaign.new()
	c.story = p_story
	var res: Dictionary = p_story["world"]["resources"]
	c.procession = int(res["procession"]["start"])
	c.reserves = int(res["reserves"]["start"])
	c.remembrance = int(res["remembrance"]["start"])
	c.current = p_story["route"]["start"]
	for m: Dictionary in p_story["cast"]["mercs"]:
		c._roster[int(m["slot"])] = _entry("named" if m["start"] else "absent", _int_stats(m["stats"]), c._starting_gear(int(m["slot"])) if m["start"] else c._empty_gear())
	for o: Dictionary in p_story["writ"]["officers"]:
		c._writ[o["id"]] = "named"
	return c


## Sets the difficulty; false (and no change) for an unknown level.
func set_difficulty(level: String) -> bool:
	if not DIFFICULTIES.has(level):
		return false
	difficulty = level
	return true


## The level after `level` in DIFFICULTIES order, wrapping round.
static func next_difficulty(level: String) -> String:
	var keys: Array = DIFFICULTIES.keys()
	return keys[(keys.find(level) + 1) % keys.size()]


## A roster slot. Levelling fields: xp, level, picks (level-ups chosen), pending (level-ups earned and not
## yet chosen), and use counters (hits landed, steps, hits taken, kills, missions) that bias the offers.
static func _entry(status: String, stats: Dictionary, gear: Dictionary) -> Dictionary:
	return {"status": status, "stats": stats, "gear": gear, "xp": 0, "level": 1, "picks": 0, "pending": 0,
		"hits": 0, "steps": 0, "hits_taken": 0, "kills": 0, "missions": 0}


# --- equipment -------------------------------------------------------------------

func item(id: String) -> Dictionary:
	if _items.is_empty():
		for it: Dictionary in story["items"]["items"]:
			_items[it["id"]] = it
	return _items.get(id, {})


## {armour, weapon, mod} -> item id ("" = empty) for a slot.
func gear_of(slot: int) -> Dictionary:
	return ((_roster.get(slot, {}) as Dictionary).get("gear", _empty_gear()) as Dictionary).duplicate()


## "+1 hp, -1 speed" or a trait's description: what an item does, in a line.
func item_summary(id: String) -> String:
	var def := item(id)
	if def.is_empty():
		return ""
	var parts: Array[String] = []
	var st: Dictionary = def.get("stats", {})
	var labels := {"hp": "%+d hp", "morale": "%+d morale", "speed": "%+d speed", "range": "%+d range", "damage": "%+d damage", "shot_ticks": "%+d AP per shot", "accuracy": "%+d%% to hit"}
	for key in ["hp", "morale", "speed", "range", "damage", "shot_ticks", "accuracy"]:
		if st.has(key):
			parts.append(labels[key] % int(st[key]))
	if def.has("trait"):
		parts.append(String(story["items"]["traits"].get(def["trait"], def["trait"])))
	return ", ".join(parts)


## Stash items for one kind, sorted by id. With a slot, weapons are limited to that merc's class.
func stash_for(kind: String, slot: int = -1) -> Array[String]:
	var out: Array[String] = []
	for id in stash:
		var def := item(id)
		if def.get("slot", "") != kind:
			continue
		if kind == "weapon" and slot >= 0 and def.get("class", "") != class_of(slot):
			continue
		out.append(id)
	out.sort()
	return out


## Put a stash item on a merc. A worn item of the same kind goes back to the
## stash. Returns "" or the reason it was refused.
func equip(slot: int, item_id: String) -> String:
	var def := item(item_id)
	if def.is_empty():
		return "Unknown item."
	if slot_status(slot) != "named":
		return "Only a named merc can carry kit."
	if not stash.has(item_id):
		return "That item is not in the stash."
	var kind: String = def["slot"]
	if kind == "weapon" and def.get("class", "") != class_of(slot):
		return "That is a %s weapon; this merc carries %s." % [class_name_of(String(def.get("class", ""))), class_name_of(class_of(slot)).to_lower()]
	var worn: String = _roster[slot]["gear"][kind]
	stash.erase(item_id)
	if worn != "":
		stash.append(worn)
	_roster[slot]["gear"][kind] = item_id
	return ""


func unequip(slot: int, kind: String) -> String:
	if not GEAR_SLOTS.has(kind):
		return "No such slot."
	if not _roster.has(slot) or _roster[slot]["gear"][kind] == "":
		return "Nothing to take off."
	stash.append(_roster[slot]["gear"][kind])
	_roster[slot]["gear"][kind] = ""
	return ""


func _empty_gear() -> Dictionary:
	return {"armour": "", "weapon": "", "mod": ""}


## What a merc starts with: the standard armour and their class's base weapon.
func _starting_gear(slot: int) -> Dictionary:
	var g := _empty_gear()
	for kind in story["items"]["starting"]:
		g[kind] = story["items"]["starting"][kind]
	var cls: Dictionary = story["classes"]["classes"].get(class_of(slot), {})
	g["weapon"] = String(cls.get("base_item", ""))
	return g


## A merc's weapon class ("rifle", "sniper", ...), fixed by the cast.
func class_of(slot: int) -> String:
	for m: Dictionary in story["cast"]["mercs"]:
		if int(m["slot"]) == slot:
			return String(m.get("class", "rifle"))
	return "rifle"


## The display name of a class ("Marksman"), or the id if unknown.
func class_name_of(class_id: String) -> String:
	return String(story["classes"]["classes"].get(class_id, {}).get("name", class_id))


## A slot's worn items go back to the stash (it died, or hollowed).
func _return_gear(slot: int) -> void:
	for kind in GEAR_SLOTS:
		var id: String = _roster[slot]["gear"][kind]
		if id != "":
			stash.append(id)
			_roster[slot]["gear"][kind] = ""


## Fold a slot's worn items into a freshly built unit.
func _apply_gear(u: SimUnit, slot: int) -> void:
	var gear := gear_of(slot)
	for kind in GEAR_SLOTS:
		apply_item(u, item(gear[kind]))


## Add one item's stat changes and trait to a unit (an empty definition does nothing).
static func apply_item(u: SimUnit, def: Dictionary) -> void:
	if def.is_empty():
		return
	var st: Dictionary = def.get("stats", {})
	u.hp = maxi(1, u.hp + int(st.get("hp", 0)))
	u.morale = clampi(u.morale + int(st.get("morale", 0)), 0, 12)
	u.speed = maxi(1, u.speed + int(st.get("speed", 0)))
	u.weapon_range = maxi(1, u.weapon_range + int(st.get("range", 0)))
	u.damage = maxi(1, u.damage + int(st.get("damage", 0)))
	u.weapon_shot_ticks = maxi(SimConst.MIN_SHOT_TICKS, u.weapon_shot_ticks + int(st.get("shot_ticks", 0)))
	u.hit_bonus += int(st.get("accuracy", 0))
	if def.get("slot", "") == "weapon":
		u.weapon_class = String(def.get("class", "rifle"))
		u.weapon_trait = String(def.get("trait", ""))  # a weapon's trait is kept apart from the mod's
	elif def.has("trait"):
		u.gear_trait = def["trait"]
		if u.gear_trait == "scope":
			u.sight_range += SimConst.SCOPE_SIGHT
			u.weapon_range += SimConst.SCOPE_RANGE


# --- stats as the sim will see them -------------------------------------------------

## The stats compared when asking "what would this item change?", in display order.
const DELTA_STATS: Array[String] = ["hp", "morale", "speed", "sight", "range", "damage", "shot_cost", "to_hit"]


## The stats a slot would field with `gear` ({armour, weapon, mod} item ids) folded in, built the
## same way a mission builds its unit, so cards and comparisons show exactly what combat uses. A
## hollow fields bare. Keys: hp, speed, aim, cqb, morale, sight, range (tiles), damage, shot_cost
## (AP), to_hit (percentage points from gear), trait.
func stats_with_gear(slot: int, gear: Dictionary) -> Dictionary:
	var is_hollow := slot_status(slot) == "hollow"
	var u := _unit(slot, 0, Vector2i.ZERO, _roster[slot]["stats"], is_hollow)
	if not is_hollow:
		for kind in GEAR_SLOTS:
			apply_item(u, item(String(gear.get(kind, ""))))
	return {"hp": u.hp, "speed": u.speed, "aim": u.aim, "cqb": u.cqb, "morale": u.morale, "sight": u.sight_range,
		"range": u.max_range(), "damage": u.damage, "shot_cost": u.shot_ticks(), "to_hit": u.hit_bonus, "trait": u.gear_trait,
		"weapon_class": u.weapon_class, "weapon_trait": u.weapon_trait}


## A slot's stats with what it wears now.
func effective_stats(slot: int) -> Dictionary:
	return stats_with_gear(slot, gear_of(slot))


## What putting `item_id` on `slot`'s `kind` would change: [{stat, from, to, delta, better}] for each
## stat that moves (a dearer shot is worse), and a "trait" row if the trait changes. Changes nothing.
func equip_deltas(slot: int, kind: String, item_id: String) -> Array[Dictionary]:
	var now := effective_stats(slot)
	var gear := gear_of(slot)
	gear[kind] = item_id
	var then := stats_with_gear(slot, gear)
	var out: Array[Dictionary] = []
	for stat in DELTA_STATS:
		var d := int(then[stat]) - int(now[stat])
		if d != 0:
			out.append({"stat": stat, "from": now[stat], "to": then[stat], "delta": d, "better": d < 0 if stat == "shot_cost" else d > 0})
	if then["trait"] != now["trait"]:
		out.append({"stat": "trait", "from": now["trait"], "to": then["trait"], "delta": 0, "better": then["trait"] != ""})
	return out


# --- levelling ---------------------------------------------------------------------

const STAT_KEYS: Array[String] = ["hp", "speed", "aim", "cqb", "morale", "sight"]


func level_of(slot: int) -> int:
	return int((_roster.get(slot, {}) as Dictionary).get("level", 1))


func xp_of(slot: int) -> int:
	return int((_roster.get(slot, {}) as Dictionary).get("xp", 0))


func max_level() -> int:
	return (story["progression"]["levels"] as Array).size() + 1


## Total XP needed to reach `level` (level 1 needs none).
func xp_for_level(level: int) -> int:
	if level <= 1:
		return 0
	var levels: Array = story["progression"]["levels"]
	return int(levels[clampi(level - 2, 0, levels.size() - 1)])


## The XP at which a merc's next level starts (their current level's mark at the top level).
func xp_next(slot: int) -> int:
	return xp_for_level(mini(level_of(slot) + 1, max_level()))


## Level-ups earned and not yet chosen.
func levelup_pending(slot: int) -> int:
	return int((_roster.get(slot, {}) as Dictionary).get("pending", 0))


## What one mission's row ({slot, alive, shots, hits, kills, hits_taken, steps}) is worth in XP.
func xp_from_row(row: Dictionary, success: bool) -> int:
	var x: Dictionary = story["progression"]["xp"]
	var xp := int(x["deploy"]) + (int(x["objective"]) if success else 0)
	xp += mini(int(row.get("hits", 0)), int(x["hit_cap"])) * int(x["per_hit"])
	xp += int(row.get("kills", 0)) * int(x["per_kill"])
	xp += mini(int(row.get("hits_taken", 0)), int(x["survived_hit_cap"])) * int(x["survived_hit"])
	return xp


## Pays a surviving named merc for a mission and updates their use counters. Returns the report row
## ({slot, gained, xp, level_before, level_after, pending}) or {} for anyone who cannot level.
func award_xp(slot: int, row: Dictionary, success: bool) -> Dictionary:
	if slot_status(slot) != "named":
		return {}
	var e: Dictionary = _roster[slot]
	e["hits"] = int(e["hits"]) + int(row.get("hits", 0))
	e["steps"] = int(e["steps"]) + int(row.get("steps", 0))
	e["hits_taken"] = int(e["hits_taken"]) + int(row.get("hits_taken", 0))
	e["kills"] = int(e["kills"]) + int(row.get("kills", 0))
	e["missions"] = int(e["missions"]) + 1
	return apply_xp(slot, xp_from_row(row, success))


func apply_xp(slot: int, amount: int) -> Dictionary:
	var e: Dictionary = _roster[slot]
	var before := level_of(slot)
	e["xp"] = int(e["xp"]) + amount
	var level := 1
	for threshold in story["progression"]["levels"]:
		if int(e["xp"]) >= int(threshold):
			level += 1
	e["level"] = level
	e["pending"] = int(e["pending"]) + (level - before)
	return {"slot": slot, "gained": amount, "xp": int(e["xp"]), "level_before": before, "level_after": level, "pending": int(e["pending"])}


## The stat steps on offer for the merc's next pick: [{stat, from, to}], up to `offers` different ones,
## never above a cap, never CQB once it already gives its close-range bonus. Weighted by class and use,
## and drawn from dice seeded by (campaign seed, slot, picks made), so the same state always offers the
## same three and reloading cannot reroll them.
func levelup_offer(slot: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if slot_status(slot) != "named" or levelup_pending(slot) <= 0:
		return out
	var p: Dictionary = story["progression"]
	var stats := slot_stats(slot)
	var weights := {}
	for stat in STAT_KEYS:
		if int(stats[stat]) >= int(p["caps"][stat]) or (stat == "cqb" and int(stats[stat]) >= SimConst.CQB_BONUS_MIN):
			continue
		var w := int(p["class_weights"][class_of(slot)].get(stat, 0)) + _use_bonus(slot, stat)
		if w > 0:
			weights[stat] = w
	var picks := int(_roster[slot]["picks"])
	for n in mini(int(p["offers"]), weights.size()):
		var total := 0
		for stat in weights:
			total += int(weights[stat])
		var r := (SimDice.d100(campaign_seed, picks, slot, 7001, 2 * n) - 1) * 100 + SimDice.d100(campaign_seed, picks, slot, 7001, 2 * n + 1) - 1
		var at := r * total / 10000
		var chosen := ""
		for stat in STAT_KEYS:
			if not weights.has(stat):
				continue
			at -= int(weights[stat])
			if at < 0:
				chosen = stat
				break
		out.append({"stat": chosen, "from": int(stats[chosen]), "to": int(stats[chosen]) + 1})
		weights.erase(chosen)
	return out


func _use_bonus(slot: int, stat: String) -> int:
	var counter: String = {"aim": "hits", "speed": "steps", "morale": "hits_taken", "cqb": "kills", "hp": "hits_taken"}.get(stat, "")
	if counter == "":
		return 0
	@warning_ignore("integer_division")
	return int(_roster[slot].get(counter, 0)) / maxi(1, int(story["progression"]["use_divisors"].get(stat, 1)))


## Takes one of the offered steps. Returns "" or why not.
func choose_levelup(slot: int, stat: String) -> String:
	if levelup_pending(slot) <= 0:
		return "No level-up to spend."
	var offered := false
	for o in levelup_offer(slot):
		if o["stat"] == stat:
			offered = true
	if not offered:
		return "That step is not on offer."
	_roster[slot]["stats"][stat] = int(_roster[slot]["stats"][stat]) + 1
	_roster[slot]["picks"] = int(_roster[slot]["picks"]) + 1
	_roster[slot]["pending"] = int(_roster[slot]["pending"]) - 1
	return ""


# --- roster ---------------------------------------------------------------------

func slot_status(slot: int) -> String:
	return (_roster.get(slot, {}) as Dictionary).get("status", "absent")


func slot_stats(slot: int) -> Dictionary:
	return (_roster[slot]["stats"] as Dictionary).duplicate()


## Slots that can be fielded now (named or hollow), sorted.
func available_slots() -> Array[int]:
	var out: Array[int] = []
	for slot in _roster:
		if slot_status(slot) == "named" or slot_status(slot) == "hollow":
			out.append(slot)
	out.sort()
	return out


## "HX-07": a hollow is its slot, never its callsign.
static func designation(slot: int) -> String:
	return "HX-%02d" % slot


## JSON numbers arrive as floats; the sim wants integers.
static func _int_stats(stats: Dictionary) -> Dictionary:
	var out := {}
	for key in stats:
		out[key] = int(stats[key])
	return out


## A dead soldier's skill as the vats can copy it: 60%, rounded, never below
## 1, with no morale. Integer math only.
static func drone_stats(stats: Dictionary, percent: int = 60) -> Dictionary:
	var out := {}
	for key in stats:
		out[key] = maxi(1, (int(stats[key]) * percent + PCT_BASE / 2) / PCT_BASE)
	out["morale"] = 0
	out["sight"] = int(stats.get("sight", 6))
	return out


# --- units for the sim -------------------------------------------------------------

## The player's side for a mission: one SimUnit per fieldable slot, id = slot.
func squad_units(_mission_id: String, slots: Array, positions: Array = []) -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	for i in slots.size():
		var slot: int = slots[i]
		var status := slot_status(slot)
		if status != "named" and status != "hollow":
			continue
		var pos: Vector2i = positions[i] if i < positions.size() else Vector2i.ZERO
		var u := _unit(slot, 0, pos, _roster[slot]["stats"], status == "hollow")
		if status == "named":
			_apply_gear(u, slot)
		out.append(u)
	return out


## The enemy side for a mission: its tier roster, the Writ officers it fields
## (hollow ones as drones) and Orrick when present.
func enemy_units(mission_id: String, positions: Array = []) -> Array[SimUnit]:
	var m := mission_or_card(mission_id)
	var out: Array[SimUnit] = []
	if m.is_empty():
		return out
	out.append_array(units_for_roster(m["enemies"]["roster"], positions))
	var n := out.size()
	for id in m["enemies"]["writ"]:
		var o := _officer(id)
		out.append(_unit(WRIT_ID_BASE + int(o["slot"]), 1, _pos(positions, n), _officer_stats(o), writ_status(id) == "hollow"))
		n += 1
	if m.get("orrick_present", false):
		out.append(_unit(PROVOST_ID, 1, _pos(positions, n), story["writ"]["provost"]["stats"], false))
	return out


## One SimUnit per roster entry ({"conscript": 2, "hollow_regular": 1, ...}), in
## rank order. Ids are the tier's base plus an index; hollow variants fight at
## the hollowing percentage with no morale.
func units_for_roster(roster: Dictionary, positions: Array = []) -> Array[SimUnit]:
	var out: Array[SimUnit] = []
	var tiers: Dictionary = story["enemy_tiers"]["tiers"]
	var keys: Array = roster.keys()
	keys.sort_custom(func(a, b) -> bool: return _roster_order(String(a), tiers) < _roster_order(String(b), tiers))
	for key in keys:
		var base := String(key).trim_prefix(HOLLOW_PREFIX)
		var hollow := base != String(key)
		var def: Dictionary = tiers.get(base, {})
		if def.is_empty() or not def.has("stats"):
			continue
		var id_base := int(def["id_base"]) + (int(story["enemy_tiers"]["hollow"]["id_base_offset"]) if hollow else 0)
		var stats: Dictionary = _int_stats(def["stats"])
		if hollow:
			stats = drone_stats(stats, _percent())
		for i in int(roster[key]):
			out.append(_unit(id_base + i, 1, _pos(positions, out.size()), stats, hollow))
	return out


## One enemy of a solid tier (conscript, regular, veteran) with an explicit unit id.
func tier_unit(tier: String, id: int, pos: Vector2i) -> SimUnit:
	var def: Dictionary = story["enemy_tiers"]["tiers"].get(tier, {})
	if def.is_empty() or not def.has("stats"):
		return null
	return _unit(id, 1, pos, _int_stats(def["stats"]), false)


## The next free unit id for `tier` among `taken` (a Dictionary keyed by id).
func next_tier_id(tier: String, taken: Dictionary) -> int:
	var id := int(story["enemy_tiers"]["tiers"][tier]["id_base"])
	while taken.has(id):
		id += 1
	return id


## "Conscript", "Hollow Regular" and so on, for the log and the squad panel.
func enemy_label(unit_id: int) -> String:
	var tiers: Dictionary = story["enemy_tiers"]["tiers"]
	var offset := int(story["enemy_tiers"]["hollow"]["id_base_offset"])
	for key in tiers:
		var def: Dictionary = tiers[key]
		if not def.has("stats"):
			continue
		var base := int(def["id_base"])
		if unit_id >= base and unit_id < base + 10:
			return "%s %d" % [def["name"], unit_id - base + 1]
		if unit_id >= base + offset and unit_id < base + offset + 10:
			return "Hollow %s %d" % [def["name"], unit_id - base - offset + 1]
	return "Enemy"


## Sort key: solid tiers by rank, then hollow ones by rank.
func _roster_order(key: String, tiers: Dictionary) -> int:
	var base := key.trim_prefix(HOLLOW_PREFIX)
	var rank := int((tiers.get(base, {}) as Dictionary).get("rank", 99))
	return rank + (100 if base != key else 0)


## The AI profile name a tier fights with ("aggressor", "default", "defender").
func tier_profile(unit_id: int) -> String:
	if unit_id >= WRIT_ID_BASE and unit_id <= PROVOST_ID + 9:
		return story["enemy_tiers"]["tiers"]["elite"]["profile"]
	var tiers: Dictionary = story["enemy_tiers"]["tiers"]
	var best := "aggressor"
	var best_base := -1
	for key in tiers:
		var def: Dictionary = tiers[key]
		if not def.has("stats"):
			continue
		var base := int(def["id_base"])
		for offset in [0, int(story["enemy_tiers"]["hollow"]["id_base_offset"])]:
			if unit_id >= base + offset and unit_id < base + offset + 10 and base + offset > best_base:
				best = def["profile"]
				best_base = base + offset
	return best


# --- missions ----------------------------------------------------------------------

## Record a finished mission. `dead_slots`: your slots lost; `writ_dead`:
## officer ids killed; `read_slots`: slots whose names the squad read aloud.
## Returns {"hollowed": [...], "refilled": [...], "vacant": [...]}.
## `units`: one row per fielded merc from the battle ({slot, alive, hits, kills, hits_taken, steps, ...},
## see MissionBuilder.outcome_for); survivors who are still named earn XP (report["xp"]).
func complete_mission(mission_id: String, success: bool, dead_slots: Array, writ_dead: Array, read_slots: Array, squad_wiped: bool = false, extra_loss: int = 0, units: Array = []) -> Dictionary:
	var report := {"hollowed": [], "refilled": [], "vacant": [], "fallen": [], "loot": [], "xp": []}
	var m := mission_or_card(mission_id)
	if m.is_empty():
		return report
	var delta: Dictionary = m["on_success"] if success else m["on_failure"]
	procession = maxi(0, procession + int(delta["procession"]) - extra_loss)
	reserves = maxi(0, reserves + int(delta["reserves"]))
	remembrance += read_slots.size() * int(story["world"]["remembrance"]["per_name_read"])
	if squad_wiped:
		_end("squad_lost")
		return report
	var seen := {}
	for slot in dead_slots:
		if not seen.has(slot):
			seen[slot] = true
			_lose_slot(slot, report)
	for id in writ_dead:
		if _writ.get(id, "") == "named":
			_writ[id] = "hollow"
			var drop: String = story["items"]["drops"].get(id, "")
			if drop != "":
				stash.append(drop)
				report["loot"].append(drop)
	for row: Dictionary in units:
		if bool(row.get("alive", false)):
			var paid := award_xp(int(row["slot"]), row, success)
			if not paid.is_empty():
				report["xp"].append(paid)
	if success:
		for reward in m.get("rewards", []):
			stash.append(reward)
			report["loot"].append(reward)
	for id in m.get("joins", []):
		_join(id)
	if procession <= 0:
		_end("procession_lost")
		return report
	if available_slots().is_empty():
		_end("no_one_left")
		return report
	if m.has("next") and mission_id == story["route"]["finale"] and not success:
		return report  # the story only ends when the finale is won
	completed.append(mission_id)
	if offered_card == mission_id:
		offered_card = ""
	if not m.has("next"):
		return report  # a contingency card: the route does not move
	if mission_id == story["route"]["finale"]:
		finished = true
		current = ""
	else:
		current = (m["next"][0] if not (m["next"] as Array).is_empty() else "")
	return report


## The debrief queue for a finished mission, in order: the result, the salvage (if any), a level-up screen for each merc with
## picks waiting, a roll call for each fallen named merc, then (for a story mission) the debrief and
## Orrick. A campaign that has ended gets only the result. These steps are saved in `pending`.
func debrief_chain(mission_id: String, outcome: Dictionary, report: Dictionary, before: Dictionary, withdrawn: bool) -> Array:
	var steps: Array = [{"t": "result", "id": mission_id, "o": outcome, "report": report, "before": before, "withdrawn": withdrawn}]
	if over:
		return steps
	if not (report.get("loot", []) as Array).is_empty():
		steps.append({"t": "salvage", "loot": (report["loot"] as Array).duplicate()})
	var leveling: Array[int] = []
	for paid: Dictionary in report.get("xp", []):
		if levelup_pending(int(paid["slot"])) > 0 and not leveling.has(int(paid["slot"])):
			leveling.append(int(paid["slot"]))
	leveling.sort()
	for slot in leveling:
		steps.append({"t": "levelup", "slot": slot})
	for slot in report["fallen"]:
		steps.append({"t": "roll", "slot": slot, "vacant": (report["vacant"] as Array).has(slot)})
	if card(mission_id).is_empty():
		steps.append({"t": "debrief", "mission": mission_id, "deaths": (report["fallen"] as Array).size()})
		steps.append({"t": "orrick", "mission": mission_id})
	return steps


## May this mission or card be completed now? The UI asks before applying an
## outcome: story missions only in route order, cards only once.
func can_complete(mission_id: String) -> bool:
	if over or finished or completed.has(mission_id):
		return false
	if not _mission(mission_id).is_empty():
		return mission_id == current
	return not card(mission_id).is_empty()


func next_missions() -> Array:
	var m := _mission(current)
	return (m["next"] as Array).duplicate() if not m.is_empty() else []


## The route as the map shows it, in order: every story mission with its state ("done", "current",
## "next" for the stop after the current one, "far" beyond that) and the contingency cards drawn so
## far ("offered" while waiting to be played, "done" once played). Pure: reads the campaign only.
func route_state() -> Dictionary:
	var nodes: Array[Dictionary] = []
	var after := ""
	var upcoming := next_missions()
	if not upcoming.is_empty():
		after = String(upcoming[0])
	for m: Dictionary in story["route"]["missions"]:
		var id: String = m["id"]
		var state := "far"
		if completed.has(id):
			state = "done"
		elif id == current and not finished:
			state = "current"
		elif id == after:
			state = "next"
		nodes.append({"id": id, "act": int(m["act"]), "name": m["name"], "place": m["place"], "state": state})
	var cards: Array[Dictionary] = []
	for id in _drawn:
		cards.append({"id": id, "act": int(card(id).get("act", 0)), "state": "done" if completed.has(id) else "offered"})
	return {"nodes": nodes, "cards": cards}


## Cards drawn so far for an act.
func drawn_for_act(act: int) -> Array:
	return _drawn.filter(func(id: String) -> bool: return int(card(id).get("act", 0)) == act)


func card(id: String) -> Dictionary:
	for c: Dictionary in story["route"]["cards"]:
		if c["id"] == id:
			return c
	return {}


## Draw a contingency card for `act`, deterministically from `seed` and never
## repeating a card. Returns "" when the act's pool is exhausted.
func draw_contingency(act: int, seed: int) -> String:
	var pool: Array[String] = []
	for c: Dictionary in story["route"]["cards"]:
		if int(c["act"]) == act and not _drawn.has(c["id"]):
			pool.append(c["id"])
	if pool.is_empty():
		return ""
	var pick := pool[absi(seed + _drawn.size() * 7919 + act * 104729) % pool.size()]
	_drawn.append(pick)
	return pick


# --- the Writ and Orrick -------------------------------------------------------------

func writ_status(id: String) -> String:
	return _writ.get(id, "named")


## How many of Orrick's six officers are hollow (0..6).
func writ_stage() -> int:
	var n := 0
	for id in _writ:
		if _writ[id] == "hollow":
			n += 1
	return n


func is_quiet() -> bool:
	return writ_stage() >= int(story["world"]["pursuit"]["quiet_stage"])


func orrick_scene() -> String:
	return "orrick_stage_%d" % writ_stage()


## After the Quiet, with enough names read, Orrick says his own name once.
func orrick_names_himself() -> bool:
	return is_quiet() and remembrance >= int(story["world"]["pursuit"]["true_name_remembrance"])


# --- choices and endings -----------------------------------------------------------------

func flag(name: String) -> bool:
	return bool(flags.get(name, false))


## Apply a scene choice (its "sets"). Returns false for an unknown scene or choice.
func apply_choice(scene_id: String, choice_id: String) -> bool:
	for s: Dictionary in story["scenes"]["scenes"]:
		if s["id"] != scene_id:
			continue
		for c: Dictionary in s.get("choices", []):
			if c["id"] == choice_id:
				_apply_sets(c["sets"])
				return true
	return false


## The ending that follows from the finale choice, or the fallback when its
## requirements are not met.
func resolve_ending() -> String:
	var chosen: String = flags.get("choice", "")
	var fallback: String = story["world"]["fallback_ending"]
	for e: Dictionary in story["world"]["endings"]:
		if e["choice"] != chosen:
			continue
		return e["id"] if _requirements_met(e["requires"]) else fallback
	return fallback


# --- saving ---------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var slots := _roster.keys()
	slots.sort()
	var roster := {}
	for slot in slots:
		var entry: Dictionary = (_roster[slot] as Dictionary).duplicate(true)
		roster[str(slot)] = entry
	var writ_ids := _writ.keys()
	writ_ids.sort()
	var writ := {}
	for id in writ_ids:
		writ[id] = _writ[id]
	return {"version": SAVE_VERSION, "procession": procession, "reserves": reserves, "remembrance": remembrance,
			"flags": flags.duplicate(), "completed": completed.duplicate(), "current": current,
			"over": over, "over_reason": over_reason, "finished": finished, "ending": ending,
			"roster": roster, "writ": writ, "drawn": _drawn.duplicate(), "pending": pending.duplicate(true),
			"offered_card": offered_card, "stash": stash.duplicate(), "seed": campaign_seed, "difficulty": difficulty}


## Why a save cannot be loaded ("" = fine).
static func save_problem(d: Dictionary) -> String:
	var required := {"version": [TYPE_INT, TYPE_FLOAT], "procession": [TYPE_INT, TYPE_FLOAT], "reserves": [TYPE_INT, TYPE_FLOAT],
		"remembrance": [TYPE_INT, TYPE_FLOAT], "flags": [TYPE_DICTIONARY], "completed": [TYPE_ARRAY], "current": [TYPE_STRING],
		"over": [TYPE_BOOL], "finished": [TYPE_BOOL], "ending": [TYPE_STRING], "roster": [TYPE_DICTIONARY],
		"writ": [TYPE_DICTIONARY], "drawn": [TYPE_ARRAY]}
	for key in required:
		if not d.has(key):
			return "missing '%s'" % key
		if not (required[key] as Array).has(typeof(d[key])):
			return "'%s' has the wrong type" % key
	if int(d["version"]) != SAVE_VERSION:
		return "unknown save version %s (this build needs %d; older saves use the previous roster)" % [d["version"], SAVE_VERSION]
	for key in d["roster"]:
		var slot: Variant = d["roster"][key]
		if typeof(slot) != TYPE_DICTIONARY or not slot.has("status") or not slot.has("stats") or typeof(slot["stats"]) != TYPE_DICTIONARY:
			return "roster slot %s is malformed" % key
		if slot.has("gear") and typeof(slot["gear"]) != TYPE_DICTIONARY:
			return "roster slot %s has malformed gear" % key
	if d.has("difficulty") and (typeof(d["difficulty"]) != TYPE_STRING or not DIFFICULTIES.has(d["difficulty"])):
		return "unknown difficulty '%s'" % str(d["difficulty"])
	if d.has("stash"):
		if typeof(d["stash"]) != TYPE_ARRAY:
			return "'stash' has the wrong type"
		for id in d["stash"]:
			if typeof(id) != TYPE_STRING:
				return "'stash' holds something that is not an item id"
	return ""


## Returns null when the save is unusable (see save_problem).
static func from_dict(d: Dictionary, p_story: Dictionary) -> Campaign:
	if save_problem(d) != "":
		return null
	var c := Campaign.new_game(p_story)
	c.procession = int(d["procession"])
	c.reserves = int(d["reserves"])
	c.remembrance = int(d["remembrance"])
	c.flags = (d["flags"] as Dictionary).duplicate()
	c.completed.assign(d["completed"])
	c.current = d["current"]
	c.over = d["over"]
	c.over_reason = d.get("over_reason", "")
	c.finished = d["finished"]
	c.ending = d["ending"]
	for key in d["roster"]:
		var stats := {}
		for k in d["roster"][key]["stats"]:
			stats[k] = int(d["roster"][key]["stats"][k])
		var status: String = d["roster"][key]["status"]
		var gear: Dictionary = c._empty_gear()
		for kind in GEAR_SLOTS:
			var worn := str(d["roster"][key].get("gear", {}).get(kind, ""))
			var def := c.item(worn)
			if def.get("slot", "") == kind and (kind != "weapon" or def.get("class", "") == c.class_of(int(key))):
				gear[kind] = worn  # an unknown, mismatched or wrong-class id is dropped, not carried
		var saved: Dictionary = d["roster"][key]
		var entry := _entry(status, stats, gear)
		for field in ["xp", "level", "picks", "pending", "hits", "steps", "hits_taken", "kills", "missions"]:
			entry[field] = int(saved.get(field, entry[field]))
		c._roster[int(key)] = entry
	for id in d["writ"]:
		c._writ[id] = d["writ"][id]
	c._drawn.assign(d["drawn"])
	c.pending = (d.get("pending", []) as Array).duplicate(true)
	c.offered_card = d.get("offered_card", "")
	c.campaign_seed = int(d.get("seed", c.campaign_seed))
	c.difficulty = String(d.get("difficulty", "standard"))
	for id in d.get("stash", []):
		if not c.item(String(id)).is_empty():
			c.stash.append(String(id))
	return c


# --- internals ---------------------------------------------------------------------------

func _lose_slot(slot: int, report: Dictionary) -> void:
	var status := slot_status(slot)
	if status != "named" and status != "hollow":
		return
	var cost := int(story["world"]["hollowing"]["refill_cost_reserves"])
	if status == "named":
		report["fallen"].append(slot)
		_return_gear(slot)
	if reserves < cost:
		_roster[slot]["status"] = "vacant"
		report["vacant"].append(slot)
		return
	reserves -= cost
	if status == "named":
		_roster[slot]["stats"] = drone_stats(_roster[slot]["stats"], _percent())
		_roster[slot]["status"] = "hollow"
		report["hollowed"].append(slot)
	else:
		report["refilled"].append(slot)


func _end(reason: String) -> void:
	over = true
	over_reason = reason
	ending = OVER_ENDING


func _join(merc_id: String) -> void:
	for m: Dictionary in story["cast"]["mercs"]:
		if m["id"] == merc_id and slot_status(int(m["slot"])) == "absent":
			_roster[int(m["slot"])]["status"] = "named"
			_roster[int(m["slot"])]["gear"] = _starting_gear(int(m["slot"]))


func _apply_sets(sets: Dictionary) -> void:
	for key in sets:
		if key == "remembrance":
			remembrance += int(sets[key])
		else:
			flags[key] = sets[key]


func _requirements_met(req: Dictionary) -> bool:
	if remembrance < int(req.get("remembrance_min", 0)):
		return false
	if writ_stage() < int(req.get("writ_stage_min", 0)):
		return false
	for f in req.get("flags", []):
		if not flag(f):
			return false
	return true


func _percent() -> int:
	return int(story["world"]["hollowing"]["drone_percent"])


func _mission(id: String) -> Dictionary:
	for m: Dictionary in story["route"]["missions"]:
		if m["id"] == id:
			return m
	return {}


## A mission, or a contingency card shaped like one. A card's enemies are
## derived: act 1 fields conscripts equal to the squad; later acts field
## regulars equal to the squad plus one hollow regular per act after the first.
func mission_or_card(id: String) -> Dictionary:
	var m := _mission(id)
	if not m.is_empty():
		return m
	var c := card(id)
	if c.is_empty():
		return c
	var out := c.duplicate(true)
	var roster := {}
	if int(c["act"]) <= 1:
		roster["conscript"] = int(c["squad_size"])
	else:
		roster["regular"] = int(c["squad_size"])
		roster["hollow_regular"] = int(c["act"]) - 1
	out["enemies"] = {"roster": roster, "writ": []}
	out["orrick_present"] = false
	return out


func _officer(id: String) -> Dictionary:
	for o: Dictionary in story["writ"]["officers"]:
		if o["id"] == id:
			return o
	return {}


func _officer_stats(o: Dictionary) -> Dictionary:
	if writ_status(o["id"]) == "hollow":
		return drone_stats(o["stats"], _percent())
	return o["stats"]


func _pos(positions: Array, i: int) -> Vector2i:
	return positions[i] if i < positions.size() else Vector2i.ZERO


func _unit(id: int, team: int, pos: Vector2i, stats: Dictionary, drone: bool) -> SimUnit:
	var u := SimUnit.make(id, team, pos, int(stats["hp"]), int(stats["speed"]), int(stats["aim"]), int(stats["cqb"]))
	u.morale = int(stats["morale"])
	u.sight_range = int(stats["sight"])
	u.is_drone = drone
	var level: Dictionary = DIFFICULTIES[difficulty]
	if team == 0:
		u.hp += int(level["squad_hp"])
	else:
		u.hit_bonus += int(level["enemy_hit"])
	return u


## How many story missions (not cards) of `act` are done.
func completed_story_in_act(act: int) -> int:
	var n := 0
	for id in completed:
		var m := _mission(id)
		if not m.is_empty() and int(m["act"]) == act:
			n += 1
	return n
