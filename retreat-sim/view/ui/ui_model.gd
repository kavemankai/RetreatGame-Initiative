class_name UiModel
extends RefCounted
## Turns campaign data into the plain dictionaries the card widgets take. Pure: it reads a Campaign
## and never changes it, so the same data can be tested without any screen.

const STAT_ORDER: Array[String] = ["hp", "speed", "aim", "cqb", "morale", "sight"]
const STAT_LABEL := {"hp": "HP", "speed": "SPD", "aim": "AIM", "cqb": "CQB", "morale": "MOR", "sight": "SIGHT"}
## The most each stat can reach when levelling (hp 6, sight 9, the rest 10; see MECHANICS_SPEC.md).
const STAT_CAP := {"hp": 6, "speed": 10, "aim": 10, "cqb": 10, "morale": 10, "sight": 9}
const DELTA_LABEL := {"hp": "HP", "morale": "morale", "speed": "speed", "sight": "sight", "range": "range", "damage": "damage", "shot_cost": "AP per shot", "to_hit": "to hit"}
const ICON_DIR := "res://assets/items/"


## A merc's card: callsign (or HX-nn), status, gear-included stats beside the base stats, worn gear.
static func merc_info(c: Campaign, slot: int, selected := false) -> Dictionary:
	var status := c.slot_status(slot)
	var gear := c.gear_of(slot)
	var names := {}
	for kind in Campaign.GEAR_SLOTS:
		names[kind] = String(c.item(String(gear[kind])).get("name", ""))
	var info := {"slot": slot, "name": merc_name(c, slot), "status": status, "class": c.class_of(slot), "class_name": c.class_name_of(c.class_of(slot)),
		"base": c.slot_stats(slot), "stats": c.effective_stats(slot),
		"gear": gear, "gear_names": names, "sprite_key": UnitSprites.key_for(slot, 0, status == "hollow"), "selected": selected}
	if status == "named":
		info["level"] = c.level_of(slot)
		info["xp"] = c.xp_of(slot)
		info["xp_next"] = c.xp_next(slot)
		info["pending"] = c.levelup_pending(slot)
	return info


static func merc_name(c: Campaign, slot: int) -> String:
	if c.slot_status(slot) == "hollow":
		return Campaign.designation(slot)
	for m: Dictionary in c.story["cast"]["mercs"]:
		if int(m["slot"]) == slot:
			return String(m["callsign"])
	return "Merc %d" % slot


## An item's card. With a merc (`slot` >= 0) and the slot kind it would go in, includes what it
## would change for them; `count` is how many are in the stash.
static func item_info(c: Campaign, item_id: String, count := 1, slot := -1, kind := "", selected := false) -> Dictionary:
	var def := c.item(item_id)
	var deltas: Array[Dictionary] = []
	if slot >= 0 and kind != "":
		deltas = c.equip_deltas(slot, kind, item_id)
	return {"id": item_id, "name": String(def.get("name", item_id)), "slot": String(def.get("slot", "")), "class": String(def.get("class", "")), "tier": int(def.get("tier", 1)),
		"summary": c.item_summary(item_id), "note": String(def.get("note", "")), "count": count, "deltas": deltas,
		"icon_path": ICON_DIR + item_id + ".png", "selected": selected}


static func resources_info(c: Campaign) -> Dictionary:
	return {"procession": c.procession, "reserves": c.reserves, "remembrance": c.remembrance, "writ": c.writ_stage()}


## In plain words what one more point of a stat does in combat, from the real rules (SimConst, SimUnit):
## "+7% to hit", "acts earlier", "+1 damage within 2 tiles" ...
static func stat_effect_text(stat: String, from: int, to: int) -> String:
	match stat:
		"hp":
			return "+1 hit point"
		"speed":
			return "Acts earlier in the round (+%d initiative)" % [10 * (to - from)]
		"aim":
			var parts: Array[String] = ["+%d%% to hit" % [SimConst.HIT_PER_AIM * (to - from)]]
			if to / SimConst.AIM_RANGE_DIVISOR > from / SimConst.AIM_RANGE_DIVISOR:
				parts.append("+1 range")
			if to >= SimConst.AIM_FAST_SHOT and from < SimConst.AIM_FAST_SHOT:
				parts.append("shots cost 1 AP less")
			return ", ".join(parts)
		"cqb":
			return "+1 damage within %d tiles" % SimConst.CQB_BONUS_DISTANCE if to >= SimConst.CQB_BONUS_MIN and from < SimConst.CQB_BONUS_MIN else "One step closer to +1 close-range damage (at %d)" % SimConst.CQB_BONUS_MIN
		"morale":
			return "+1 to the check after being hit"
		"sight":
			return "Sees 1 tile further"
	return ""


## What a shot preview adds to the plain numbers: "burst x3", "blast: also hits the 8 tiles around",
## "beam: ignores half cover". Empty for an ordinary shot.
static func shot_notes(preview: Dictionary) -> String:
	var parts: Array[String] = []
	if preview.has("burst"):
		parts.append("burst x%d" % int(preview["burst"]))
	if preview.get("area", false):
		parts.append("blast: also hits the 8 tiles around")
	return ", ".join(parts)


## "range +2" / "AP per shot +1" / "trait: scope" for one delta row.
static func delta_line(d: Dictionary) -> String:
	if d["stat"] == "trait":
		return "trait: %s" % (d["to"] if d["to"] != "" else "none")
	return "%s %s" % [DELTA_LABEL.get(d["stat"], d["stat"]), UiTheme.delta_text(int(d["delta"]))]
