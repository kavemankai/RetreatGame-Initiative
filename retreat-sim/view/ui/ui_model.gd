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
	if preview.get("cover", false):
		parts.append("target in cover: -%d%% to hit" % SimConst.COVER_HIT_PENALTY)
	if preview.get("area", false):
		parts.append("blast: also hits the 8 tiles around")
	return ", ".join(parts)


## "range +2" / "AP per shot +1" / "trait: scope" for one delta row.
static func delta_line(d: Dictionary) -> String:
	if d["stat"] == "trait":
		return "trait: %s" % (d["to"] if d["to"] != "" else "none")
	return "%s %s" % [DELTA_LABEL.get(d["stat"], d["stat"]), UiTheme.delta_text(int(d["delta"]))]


## What the overworld's bottom sheet says about a tapped stop or card: {title, lines, action}.
## `action` is "brief" only for the stop the convoy is at (or a card that is on offer). Stops beyond the next
## are unknown ground: the sheet never names their objective or summary.
static func map_sheet(c: Campaign, hit: Dictionary) -> Dictionary:
	var id: String = hit["id"]
	var route := c.route_state()
	if hit["kind"] == "card":
		var card := c.card(id)
		var offered := false
		for r: Dictionary in route["cards"]:
			if r["id"] == id:
				offered = r["state"] == "offered"
		return {"title": "Contingency: %s" % card["name"], "lines": [String(card["objective"]["text"]), "Squad of %d. Optional; it is offered once and costs nothing to ignore for now." % int(card["squad_size"])], "action": "brief" if offered else ""}
	var m := c.mission_or_card(id)
	var state := ""
	for n: Dictionary in route["nodes"]:
		if n["id"] == id:
			state = n["state"]
	if state == "far":
		return {"title": "Unknown ground", "lines": ["Act %d. The net has nothing on this stop yet." % int(m["act"])], "action": ""}
	var lines: Array[String] = ["Act %d. %s" % [int(m["act"]), m["place"]], String(m.get("summary", "")), "Objective: %s" % m["objective"]["text"], "Squad of %d." % int(m["squad_size"])]
	if state == "done":
		lines.append("Done.")
	return {"title": m["name"], "lines": lines, "action": "brief" if state == "current" else ""}


## A merc's callsign by slot even if they have since fallen (merc_name shows the hollow's designation).
static func callsign(c: Campaign, slot: int) -> String:
	for m: Dictionary in c.story["cast"]["mercs"]:
		if int(m["slot"]) == slot:
			return String(m["callsign"])
	return "Slot %02d" % slot


## The default squad: named mercs first, then hollows, up to `need`.
static func default_squad(c: Campaign, need: int) -> Array[int]:
	var picked: Array[int] = []
	var hollow: Array[int] = []
	for slot in c.available_slots():
		if c.slot_status(slot) == "named":
			if picked.size() < need:
				picked.append(slot)
		else:
			hollow.append(slot)
	for slot in hollow:
		if picked.size() < need:
			picked.append(slot)
	return picked


## How many the squad takes: the mission's size, or everyone left if fewer.
static func squad_need(c: Campaign, m: Dictionary) -> int:
	return mini(int(m["squad_size"]), c.available_slots().size())


## Plain warnings about a squad before it deploys. Hollows carry no kit, so they are never warned about.
## A missing weapon is a real problem; a missing armour or mod is only worth a mention.
static func readiness(c: Campaign, picked: Array, need: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if picked.size() != need:
		out.append({"level": "block", "text": "Choose %d for the squad (%d chosen)." % [need, picked.size()]})
	for slot in picked:
		if c.slot_status(int(slot)) != "named":
			continue
		var gear := c.gear_of(int(slot))
		var who := callsign(c, int(slot))
		if String(gear["weapon"]) == "":
			out.append({"level": "warn", "text": "%s has no weapon." % who})
		if String(gear["armour"]) == "":
			out.append({"level": "note", "text": "%s has no armour." % who})
		if String(gear["mod"]) == "":
			out.append({"level": "note", "text": "%s has no mod." % who})
	return out


## "Procession +0, Reserves -2" for a mission's on_success or on_failure.
static func stakes_text(delta: Dictionary) -> String:
	return "Procession %s, Reserves %s" % [UiTheme.delta_text(int(delta["procession"])), UiTheme.delta_text(int(delta["reserves"]))]


## What the mission prep screen shows for a mission or card, from the data alone: place, objective, the
## stakes of winning and losing, reward names, the enemy tiers the briefing names, and whether Orrick is there.
static func prep_info(c: Campaign, mission_id: String) -> Dictionary:
	var m := c.mission_or_card(mission_id)
	var is_card := not c.card(mission_id).is_empty()
	var rewards: Array[String] = []
	for id in m.get("rewards", []):
		rewards.append(String(c.item(String(id)).get("name", id)))
	var enemies: Array[String] = []
	var enemy_def: Dictionary = m.get("enemies", {})
	var roster: Dictionary = enemy_def.get("roster", {})
	for tier in roster:
		enemies.append("%d %s" % [int(roster[tier]), tier])
	var writ_count := (enemy_def.get("writ", []) as Array).size()
	if writ_count > 0:
		enemies.append("%d Writ officer%s" % [writ_count, "" if writ_count == 1 else "s"])
	return {"id": mission_id, "is_card": is_card, "name": String(m["name"]), "act": int(m.get("act", 0)), "place": String(m.get("place", "")),
		"objective": String(m["objective"]["text"]), "squad_size": int(m["squad_size"]),
		"on_success": stakes_text(m["on_success"]), "on_failure": stakes_text(m["on_failure"]),
		"rewards": rewards, "enemies": enemies, "orrick": bool(m.get("orrick_present", false))}


## The result screen's data for a "result" debrief step: verdict, resource changes, notes about the dead
## and the Writ, one row per fielded merc (outcome, shots, hits, kills, XP earned) and the salvage ids.
static func result_info(c: Campaign, step: Dictionary) -> Dictionary:
	var o: Dictionary = step["o"]
	var report: Dictionary = step["report"]
	var before: Dictionary = step["before"]
	var m := c.mission_or_card(String(step["id"]))
	var verdict := "Withdrawn" if step["withdrawn"] else ("Complete" if o["success"] else "Failed")
	if o["squad_wiped"]:
		verdict = "The squad is lost"
	var notes: Array[String] = []
	for slot in report["hollowed"]:
		notes.append("%s is dead. %s stands in the slot. One reserve spent." % [callsign(c, int(slot)), Campaign.designation(int(slot))])
	for slot in report["refilled"]:
		notes.append("%s is replaced. One reserve spent." % Campaign.designation(int(slot)))
	for slot in report["vacant"]:
		notes.append("%s is dead. Slot %02d stays empty; there is nothing left to send." % [callsign(c, int(slot)), int(slot)])
	for wid in o["writ_dead"]:
		notes.append("The Writ: %s falls. The Bureau fills the slot with a hollow." % writ_name(c, String(wid)))
	var paid := {}
	for x: Dictionary in report.get("xp", []):
		paid[int(x["slot"])] = x
	var squad: Array[Dictionary] = []
	for row: Dictionary in o.get("units", []):
		var slot := int(row["slot"])
		var outcome := "Fell" if not bool(row["alive"]) else ("Unhurt" if int(row["hits_taken"]) == 0 else "Hit %d time%s" % [int(row["hits_taken"]), "" if int(row["hits_taken"]) == 1 else "s"])
		var entry := {"slot": slot, "name": callsign(c, slot) if c.slot_status(slot) == "named" or not bool(row["alive"]) else Campaign.designation(slot), "outcome": outcome, "alive": bool(row["alive"]),
			"shots": int(row["shots"]), "hits": int(row["hits"]), "kills": int(row["kills"]), "xp_gained": 0}
		if paid.has(slot):
			entry["xp_gained"] = int(paid[slot]["gained"])
			entry["level"] = int(paid[slot]["level_after"])
			entry["leveled"] = int(paid[slot]["level_after"]) > int(paid[slot]["level_before"])
			entry["xp"] = int(paid[slot]["xp"])
			entry["xp_floor"] = c.xp_for_level(int(paid[slot]["level_after"]))
			entry["xp_next"] = c.xp_for_level(mini(int(paid[slot]["level_after"]) + 1, c.max_level()))
		squad.append(entry)
	return {"title": String(m.get("name", "Mission")), "verdict": verdict, "won": bool(o["success"]) and not bool(step["withdrawn"]) and not bool(o["squad_wiped"]),
		"deltas": [
			{"label": "Procession", "before": int(before["procession"]), "after": c.procession},
			{"label": "Reserves", "before": int(before["reserves"]), "after": c.reserves}],
		"notes": notes, "squad": squad, "loot": (report.get("loot", []) as Array).duplicate()}


static func writ_name(c: Campaign, id: String) -> String:
	for o: Dictionary in c.story["writ"]["officers"]:
		if o["id"] == id:
			return String(o["callsign"])
	return id
