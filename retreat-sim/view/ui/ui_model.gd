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
	return {"slot": slot, "name": merc_name(c, slot), "status": status, "base": c.slot_stats(slot), "stats": c.effective_stats(slot),
		"gear": gear, "gear_names": names, "sprite_key": UnitSprites.key_for(slot, 0, status == "hollow"), "selected": selected}


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
	return {"id": item_id, "name": String(def.get("name", item_id)), "slot": String(def.get("slot", "")), "tier": int(def.get("tier", 1)),
		"summary": c.item_summary(item_id), "note": String(def.get("note", "")), "count": count, "deltas": deltas,
		"icon_path": ICON_DIR + item_id + ".png", "selected": selected}


static func resources_info(c: Campaign) -> Dictionary:
	return {"procession": c.procession, "reserves": c.reserves, "remembrance": c.remembrance, "writ": c.writ_stage()}


## "range +2" / "AP per shot +1" / "trait: scope" for one delta row.
static func delta_line(d: Dictionary) -> String:
	if d["stat"] == "trait":
		return "trait: %s" % (d["to"] if d["to"] != "" else "none")
	return "%s %s" % [DELTA_LABEL.get(d["stat"], d["stat"]), UiTheme.delta_text(int(d["delta"]))]
