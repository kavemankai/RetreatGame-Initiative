class_name StoryLint
extends RefCounted
## Mechanical checks that keep the story data consistent with itself and with
## the game: dangling references, unreachable missions, stat ranges, tone
## rules. Returns human-readable errors; an empty array means clean.

const BANNED: Array[String] = ["okay", "ok", "awesome", "guys", "dude", "yeah", "cool", "lol", "wow", "gonna", "wanna", "super", "epic", "nope", "yep", "hey"]
const SCENE_KINDS: Array[String] = ["briefing", "debrief", "card", "roll_call", "orrick", "camp", "ending"]
const MAX_LINE := 160
const MAX_SAMPLE := 140
const STAT_RANGES := {"hp": [2, 4], "speed": [1, 9], "aim": [1, 9], "cqb": [1, 9], "morale": [1, 9], "sight": [4, 8]}
const NON_CAST_SPEAKERS: Array[String] = ["narrator", "hollow", "keeper", "orrick"]
const MIN_CARDS_PER_ACT := 2
const MIN_CAMP_SCENES := 5  # four of the nine were about mercs who left the roster of eight
## Enemy spawn points every map provides (tests check each map has at least this many).
const MAX_ENEMIES := 8
## Each enemy tier owns this many consecutive unit ids.
const ID_SPAN := 10
const ITEM_STATS: Array[String] = ["hp", "morale", "speed", "range", "damage", "shot_ticks", "accuracy"]
const MAX_WRIT_SLOT := 6
const WEAPON_TRAITS: Array[String] = ["beam", "area", "burst"]

static var _banned_re: RegEx


static func lint(d: Dictionary) -> Array[String]:
	var errs: Array[String] = StorySchema.check(d)
	if not errs.is_empty():
		return errs  # the deeper checks assume this shape
	var mercs: Array = d["cast"].get("mercs", [])
	var officers: Array = d["writ"].get("officers", [])
	var missions: Array = d["route"].get("missions", [])
	var mission_ids := _ids(missions)
	_lint_cast(d, errs, mercs, mission_ids)
	_lint_writ(d, errs, officers, missions, mission_ids)
	_lint_route(d, errs, missions, mission_ids, mercs)
	_lint_scenes(d, errs, mercs, officers)
	_lint_world(d, errs, officers)
	_lint_tiers(errs, d["enemy_tiers"])
	_lint_items(errs, d)
	return errs


# --- cast ----------------------------------------------------------------------

static func _lint_cast(d: Dictionary, errs: Array[String], mercs: Array, mission_ids: Array) -> void:
	var ids := {}
	var slots := {}
	for m: Dictionary in mercs:
		var id: String = m.get("id", "")
		if id == "" or ids.has(id):
			errs.append("duplicate or empty merc id '%s'" % id)
		ids[id] = true
		var slot: int = int(m.get("slot", -1))
		if slots.has(slot):
			errs.append("duplicate slot %d (%s)" % [slot, id])
		slots[slot] = true
		_stat_ranges(errs, id, m["stats"])
		if not (d["classes"]["classes"] as Dictionary).has(m.get("class", "")):
			errs.append("%s: unknown weapon class '%s'" % [id, m.get("class", "")])
		for key in ["callsign", "name", "role", "bio", "wound", "death_line", "hollow_note"]:
			if str(m.get(key, "")) == "":
				errs.append("%s: missing %s" % [id, key])
			_tone(errs, "%s.%s" % [id, key], str(m.get(key, "")))
		var samples: Array = (m.get("voice", {}) as Dictionary).get("samples", [])
		if samples.size() < 3:
			errs.append("%s: needs at least 3 voice samples" % id)
		for s in samples:
			if str(s).length() > MAX_SAMPLE:
				errs.append("%s: a voice sample is too long (%d chars)" % [id, str(s).length()])
			_tone(errs, "%s sample" % id, str(s))
		if not m.get("start", true) and not mission_ids.has(m.get("joins", "")):
			errs.append("%s: joins a mission that does not exist" % id)
		for a: Dictionary in m.get("arc", []):
			if not mission_ids.has(a.get("mission", "")):
				errs.append("%s: arc beat references unknown mission '%s'" % [id, a.get("mission", "")])
	for i in range(1, mercs.size() + 1):
		if not slots.has(i):
			errs.append("slots must be contiguous 1..%d; missing %d" % [mercs.size(), i])
	for m: Dictionary in mercs:
		for r: Dictionary in m.get("relationships", []):
			if not ids.has(r.get("with", "")) or r.get("with", "") == m.get("id", ""):
				errs.append("%s: relationship with unknown merc '%s'" % [m.get("id", ""), r.get("with", "")])


# --- writ ----------------------------------------------------------------------

static func _lint_writ(d: Dictionary, errs: Array[String], officers: Array, missions: Array, mission_ids: Array) -> void:
	var ids := {}
	var slots := {}
	for o: Dictionary in officers:
		var id: String = o.get("id", "")
		if id == "" or ids.has(id):
			errs.append("duplicate or empty writ id '%s'" % id)
		ids[id] = true
		var oslot := int(o.get("slot", -1))
		if slots.has(oslot):
			errs.append("duplicate writ slot %s" % o.get("slot", -1))
		slots[oslot] = true
		if oslot < 1 or oslot > MAX_WRIT_SLOT or oslot > officers.size():
			errs.append("writ officer %s: slot %d must be 1..%d (units are 100 + slot)" % [id, oslot, mini(officers.size(), MAX_WRIT_SLOT)])
		_stat_ranges(errs, "writ officer %s" % id, o["stats"])
		var intro: String = o.get("introduced", "")
		var found := false
		for m: Dictionary in missions:
			if m["id"] == intro and (m["enemies"]["writ"] as Array).has(id):
				found = true
		if not found:
			errs.append("writ officer %s is introduced at '%s', which does not field them" % [id, intro])
		for l in o.get("alive_lines", []) + o.get("hollow_lines", []):
			_tone(errs, "writ %s line" % id, str(l))
	for m: Dictionary in missions:
		for w in m["enemies"]["writ"]:
			if not ids.has(w):
				errs.append("mission %s fields unknown writ officer '%s'" % [m["id"], w])
	var stage_max: int = int(d["world"].get("pursuit", {}).get("stage_max", -1))
	if stage_max != officers.size():
		errs.append("pursuit stage_max (%d) must equal the number of writ officers (%d)" % [stage_max, officers.size()])
	if (d["writ"].get("stage_names", []) as Array).size() != officers.size() + 1:
		errs.append("writ stage_names must have officers + 1 entries")
	_stat_ranges(errs, "provost", d["writ"]["provost"]["stats"])
	var reveal: String = d["writ"].get("provost", {}).get("reveal_mission", "")
	if not mission_ids.has(reveal):
		errs.append("provost reveal_mission '%s' does not exist" % reveal)


# --- route ---------------------------------------------------------------------

static func _lint_route(d: Dictionary, errs: Array[String], missions: Array, mission_ids: Array, mercs: Array) -> void:
	var route: Dictionary = d["route"]
	var types: Array = route.get("objective_types", [])
	var by_id := {}
	for m: Dictionary in missions:
		if by_id.has(m["id"]):
			errs.append("duplicate mission id '%s'" % m["id"])
		by_id[m["id"]] = m
	if not by_id.has(route.get("start", "")):
		errs.append("route start '%s' does not exist" % route.get("start", ""))
	if not by_id.has(route.get("finale", "")):
		errs.append("route finale '%s' does not exist" % route.get("finale", ""))
	var scene_ids := _scene_ids(d)
	for m: Dictionary in missions:
		_lint_mission(errs, m, by_id, types, scene_ids, d)
	_lint_reachability(errs, route, by_id)
	_lint_cards(errs, route, types, scene_ids)
	_lint_joins(errs, missions, mercs)


## Why `tier` (a roster key, optionally "hollow_<tier>") cannot be fielded in `act` ("" = fine).
static func _tier_error(tiers: Dictionary, tier: String, act: int) -> String:
	var base := tier.trim_prefix("hollow_")
	var hollow := base != tier
	var def: Dictionary = tiers["tiers"].get(base, {})
	if def.is_empty() or not def.has("stats"):
		return "unknown enemy tier '%s'" % tier
	var first_act := maxi(int(def["min_act"]), int(tiers["hollow"]["min_act"]) if hollow else 0)
	if act < first_act:
		return "tier '%s' does not appear before act %d (mission is in act %d)" % [tier, first_act, act]
	return ""


static func _lint_items(errs: Array[String], d: Dictionary) -> void:
	var items: Dictionary = d["items"]
	var slots: Array = items["slots"]
	if slots != Campaign.GEAR_SLOTS:
		errs.append("items.slots %s must equal the game's gear slots %s" % [slots, Campaign.GEAR_SLOTS])
	var by_id := {}
	for it: Dictionary in items["items"]:
		var id: String = it["id"]
		if by_id.has(id):
			errs.append("item %s is defined twice" % id)
		by_id[id] = it
		if not slots.has(it["slot"]):
			errs.append("item %s: unknown slot '%s'" % [id, it["slot"]])
		if it["slot"] == "mod":
			if not (items["traits"] as Dictionary).has(it.get("trait", "")) or WEAPON_TRAITS.has(it.get("trait", "")):
				errs.append("item %s: unknown mod trait '%s'" % [id, it.get("trait", "")])
		elif it["slot"] == "weapon":
			if not (d["classes"]["classes"] as Dictionary).has(it.get("class", "")):
				errs.append("weapon %s: unknown class '%s'" % [id, it.get("class", "")])
			if it.has("trait") and not WEAPON_TRAITS.has(it["trait"]):
				errs.append("weapon %s: '%s' is not a weapon trait (%s)" % [id, it["trait"], WEAPON_TRAITS])
		elif it.has("trait"):
			errs.append("item %s: only mods and weapons carry a trait" % id)
		if it["slot"] != "weapon" and it.has("class"):
			errs.append("item %s: only weapons have a class" % id)
		for stat in (it.get("stats", {}) as Dictionary):
			if not ITEM_STATS.has(stat):
				errs.append("item %s: unknown stat '%s'" % [id, stat])
		_tone(errs, "item %s note" % id, String(it["note"]))
	for slot in items["starting"]:
		var start: String = items["starting"][slot]
		if not by_id.has(start) or by_id[start]["slot"] != slot:
			errs.append("starting %s '%s' is not an item of that slot" % [slot, start])
	for cid in (d["classes"]["classes"] as Dictionary):
		var base: String = d["classes"]["classes"][cid].get("base_item", "")
		if not by_id.has(base) or by_id[base]["slot"] != "weapon" or by_id[base].get("class", "") != cid or int(by_id[base]["tier"]) != 1:
			errs.append("class %s: base_item '%s' must be a tier 1 weapon of that class" % [cid, base])
	var officer_ids := {}
	for o: Dictionary in d["writ"]["officers"]:
		officer_ids[o["id"]] = true
	for officer in items["drops"]:
		if not officer_ids.has(officer):
			errs.append("drop for unknown officer '%s'" % officer)
		if not by_id.has(items["drops"][officer]):
			errs.append("drop for %s: unknown item '%s'" % [officer, items["drops"][officer]])
	for m: Dictionary in d["route"]["missions"]:
		for reward in m["rewards"]:
			if not by_id.has(reward):
				errs.append("mission %s rewards unknown item '%s'" % [m["id"], reward])
			elif int(by_id[reward]["tier"]) > int(m["act"]):
				errs.append("mission %s (act %d) rewards '%s', which is not found before act %d" % [m["id"], int(m["act"]), reward, int(by_id[reward]["tier"])])


static func _lint_tiers(errs: Array[String], tiers: Dictionary) -> void:
	var profiles: Dictionary = SimAIProfile.load_file("res://data/ai_profiles.json")["profiles"]
	var offset := int(tiers["hollow"]["id_base_offset"])
	var ranges: Array = []  # [first id, last id, label]
	for key in tiers["tiers"]:
		var t: Dictionary = tiers["tiers"][key]
		if not profiles.has(t["profile"]):
			errs.append("enemy tier %s: unknown AI profile '%s'" % [key, t["profile"]])
		if not t.has("stats"):
			continue  # elite and boss use the Writ's own ids
		var base := int(t["id_base"])
		ranges.append([base, base + ID_SPAN - 1, key])
		ranges.append([base + offset, base + offset + ID_SPAN - 1, "hollow_%s" % key])
	ranges.append([1, 12, "merc slots"])
	ranges.append([100, 109, "the Writ and the Provost"])
	for i in ranges.size():
		for j in range(i + 1, ranges.size()):
			if ranges[i][0] <= ranges[j][1] and ranges[j][0] <= ranges[i][1]:
				errs.append("enemy tier ids overlap: %s (%d-%d) and %s (%d-%d)" % [ranges[i][2], ranges[i][0], ranges[i][1], ranges[j][2], ranges[j][0], ranges[j][1]])
	var last_rank := 0
	var keys: Array = tiers["tiers"].keys()
	keys.sort_custom(func(a, b) -> bool: return int(tiers["tiers"][a]["rank"]) < int(tiers["tiers"][b]["rank"]))
	for key in keys:
		var t: Dictionary = tiers["tiers"][key]
		if int(t["rank"]) <= last_rank:
			errs.append("enemy tier %s: ranks must be strictly increasing" % key)
		last_rank = int(t["rank"])
		if t.has("stats"):
			for stat in STAT_RANGES:
				var v := int((t["stats"] as Dictionary).get(stat, -1))
				if v < int(STAT_RANGES[stat][0]) - (1 if stat == "hp" else 0) or v > int(STAT_RANGES[stat][1]):
					errs.append("enemy tier %s: %s %d is outside %s" % [key, stat, v, STAT_RANGES[stat]])


static func _lint_mission(errs: Array[String], m: Dictionary, by_id: Dictionary, types: Array, scene_ids: Dictionary, d: Dictionary) -> void:
	var id: String = m["id"]
	_tone(errs, "mission %s name" % id, m["name"])
	_tone(errs, "mission %s summary" % id, m["summary"])
	_tone(errs, "mission %s objective" % id, m["objective"]["text"])
	if (m["next"] as Array).size() > 1:
		errs.append("mission %s: branching routes are not supported yet (only next[0] is followed)" % id)
	var enemies: Dictionary = m["enemies"]
	var count := (enemies["writ"] as Array).size() + (1 if m["orrick_present"] else 0)
	for tier in enemies["roster"]:
		var n: int = int(enemies["roster"][tier])
		count += n
		var tier_err := _tier_error(d["enemy_tiers"], String(tier), int(m["act"]))
		if tier_err != "":
			errs.append("mission %s: %s" % [id, tier_err])
		if n < 1:
			errs.append("mission %s: roster entry '%s' must be at least 1" % [id, tier])
	if count > MAX_ENEMIES:
		errs.append("mission %s fields %d enemies but only %d spawn points exist" % [id, count, MAX_ENEMIES])
	for n in m.get("next", []):
		if not by_id.has(n):
			errs.append("mission %s: next '%s' does not exist" % [id, n])
		elif int(by_id[n]["act"]) < int(m["act"]):
			errs.append("mission %s: next '%s' goes back an act" % [id, n])
	if id == d["route"].get("finale", "") and not (m.get("next", []) as Array).is_empty():
		errs.append("finale %s must have no exits" % id)
	elif id != d["route"].get("finale", "") and (m.get("next", []) as Array).is_empty():
		errs.append("mission %s has no next and is not the finale" % id)
	var size: int = int(m.get("squad_size", 0))
	if size < 3 or size > 4:
		errs.append("mission %s: squad_size %d must be 3-4" % [id, size])
	if not types.has(m.get("objective", {}).get("type", "")):
		errs.append("mission %s: unknown objective type" % id)
	if int(m.get("act", 0)) < 1 or int(m.get("act", 0)) > 3:
		errs.append("mission %s: act must be 1-3" % id)
	if (m.get("map", {}).get("size", []) as Array).size() != 2:
		errs.append("mission %s: map size must be [w, h]" % id)
	if int(m["on_failure"]["procession"]) > int(m["on_success"]["procession"]):
		errs.append("mission %s: failure must not be better for the procession than success" % id)
	for key in ["briefing", "debrief"]:
		if not scene_ids.has(m["scenes"].get(key, "")):
			errs.append("mission %s: %s scene '%s' does not exist" % [id, key, m["scenes"].get(key, "")])
		elif scene_ids[m["scenes"][key]].get("kind", "") != key:
			errs.append("mission %s: %s scene '%s' has the wrong kind" % [id, key, m["scenes"][key]])
	_lint_declared_choices(errs, m, scene_ids)


## A mission's declared choices must be exactly the choices its debrief offers.
static func _lint_declared_choices(errs: Array[String], m: Dictionary, scene_ids: Dictionary) -> void:
	var scene: Dictionary = scene_ids.get(m["scenes"].get("debrief", ""), {})
	var offered: Array = (scene.get("choices", []) as Array).map(func(c): return c["id"])
	var declared: Array = m.get("choices", [])
	for c in declared:
		if not offered.has(c):
			errs.append("mission %s declares choice '%s' that its debrief does not offer" % [m["id"], c])
	for c in offered:
		if not declared.has(c):
			errs.append("mission %s: debrief offers choice '%s' that the mission does not declare" % [m["id"], c])


static func _lint_reachability(errs: Array[String], route: Dictionary, by_id: Dictionary) -> void:
	var seen := {}
	var queue: Array = [route.get("start", "")]
	while not queue.is_empty():
		var id: String = queue.pop_front()
		if seen.has(id) or not by_id.has(id):
			continue
		seen[id] = true
		queue.append_array(by_id[id].get("next", []))
	for id in by_id:
		if not seen.has(id):
			errs.append("mission %s is unreachable from the start" % id)
	if not seen.has(route.get("finale", "")):
		errs.append("the finale is unreachable from the start")
	var state := {}
	for id in by_id:
		if _has_cycle(id, by_id, state):
			errs.append("the route contains a cycle through %s" % id)
			break


static func _has_cycle(id: String, by_id: Dictionary, state: Dictionary) -> bool:
	if state.get(id, 0) == 1:
		return true
	if state.get(id, 0) == 2 or not by_id.has(id):
		return false
	state[id] = 1
	for n in by_id[id].get("next", []):
		if _has_cycle(n, by_id, state):
			return true
	state[id] = 2
	return false


static func _lint_cards(errs: Array[String], route: Dictionary, types: Array, scene_ids: Dictionary) -> void:
	var per_act := {}
	var seen := {}
	var mission_ids := _ids(route.get("missions", []))
	for c: Dictionary in route.get("cards", []):
		if seen.has(c["id"]):
			errs.append("duplicate card id '%s'" % c["id"])
		if mission_ids.has(c["id"]):
			errs.append("card id '%s' collides with a mission id" % c["id"])
		seen[c["id"]] = true
		_tone(errs, "card %s name" % c["id"], c["name"])
		_tone(errs, "card %s objective" % c["id"], c["objective"]["text"])
		if scene_ids.has(c["scene"]) and scene_ids[c["scene"]].get("kind", "") != "card":
			errs.append("card %s: scene '%s' has the wrong kind" % [c["id"], c["scene"]])
		per_act[int(c["act"])] = int(per_act.get(int(c["act"]), 0)) + 1
		if not scene_ids.has(c.get("scene", "")):
			errs.append("card %s: scene '%s' does not exist" % [c["id"], c.get("scene", "")])
		if not types.has(c.get("objective", {}).get("type", "")):
			errs.append("card %s: unknown objective type" % c["id"])
		if int(c.get("squad_size", 0)) < 3 or int(c.get("squad_size", 0)) > 4:
			errs.append("card %s: squad_size must be 3-4" % c["id"])
	for act in [1, 2, 3]:
		if int(per_act.get(act, 0)) < MIN_CARDS_PER_ACT:
			errs.append("cards: act %d needs at least %d contingency cards" % [act, MIN_CARDS_PER_ACT])


static func _lint_joins(errs: Array[String], missions: Array, mercs: Array) -> void:
	var by_merc := {}
	for m: Dictionary in mercs:
		by_merc[m["id"]] = m
	for mission: Dictionary in missions:
		for id in mission.get("joins", []):
			if not by_merc.has(id) or by_merc[id].get("joins", null) != mission["id"]:
				errs.append("join mismatch: mission %s lists %s, but the cast does not agree" % [mission["id"], id])
	for m: Dictionary in mercs:
		if not m.get("start", true):
			var ok := false
			for mission: Dictionary in missions:
				if mission["id"] == m.get("joins", "") and (mission.get("joins", []) as Array).has(m["id"]):
					ok = true
			if not ok:
				errs.append("join mismatch: %s joins %s, but that mission does not list them" % [m["id"], m.get("joins", "")])


# --- scenes --------------------------------------------------------------------

static func _lint_scenes(d: Dictionary, errs: Array[String], mercs: Array, officers: Array) -> void:
	var speakers: Array = NON_CAST_SPEAKERS.duplicate()
	for m: Dictionary in mercs:
		speakers.append(m["id"])
	for o: Dictionary in officers:
		speakers.append(o["id"])
	var seen := {}
	var camp := 0
	for s: Dictionary in d["scenes"].get("scenes", []):
		var id: String = s.get("id", "")
		if id == "" or seen.has(id):
			errs.append("duplicate or empty scene id '%s'" % id)
		seen[id] = true
		if not SCENE_KINDS.has(s.get("kind", "")):
			errs.append("scene %s: unknown kind '%s'" % [id, s.get("kind", "")])
		if s.get("kind", "") == "camp":
			camp += 1
		if (s.get("lines", []) as Array).is_empty():
			errs.append("scene %s has no lines" % id)
		for l: Dictionary in s.get("lines", []):
			if not speakers.has(l.get("who", "")):
				errs.append("scene %s: unknown speaker '%s'" % [id, l.get("who", "")])
			var text := str(l.get("text", ""))
			if text == "":
				errs.append("scene %s: empty line" % id)
			if text.length() > MAX_LINE:
				errs.append("scene %s: line is too long (%d chars)" % [id, text.length()])
			_tone(errs, "scene %s" % id, text)
		for c: Dictionary in s.get("choices", []):
			if str(c["id"]) == "" or str(c["text"]) == "":
				errs.append("scene %s: malformed choice" % id)
			_tone(errs, "scene %s choice" % id, str(c["text"]))
	if camp < MIN_CAMP_SCENES:
		errs.append("need at least %d camp scenes, found %d" % [MIN_CAMP_SCENES, camp])
	var stage_max: int = int(d["world"].get("pursuit", {}).get("stage_max", 0))
	var required: Array[String] = ["roll_call_prompt", "roll_call_read", "roll_call_silent", "hollow_arrives", "orrick_true_name"]
	for i in range(0, stage_max + 1):
		required.append("orrick_stage_%d" % i)
	for r in required:
		if not seen.has(r):
			errs.append("required scene '%s' is missing" % r)
	for e: Dictionary in d["world"].get("endings", []):
		if not seen.has(e.get("scene", "")):
			errs.append("ending %s: scene '%s' does not exist" % [e.get("id", ""), e.get("scene", "")])


# --- world ---------------------------------------------------------------------

static func _lint_world(d: Dictionary, errs: Array[String], officers: Array) -> void:
	var w: Dictionary = d["world"]
	var ending_ids := {}
	var vesper_choices := []
	for s: Dictionary in d["scenes"].get("scenes", []):
		if s.get("id", "") == "debrief_vesper_threshold":
			vesper_choices = (s.get("choices", []) as Array).map(func(c): return c["id"])
	for e: Dictionary in w.get("endings", []):
		if ending_ids.has(e.get("id", "")):
			errs.append("duplicate ending id '%s'" % e.get("id", ""))
		ending_ids[e.get("id", "")] = true
		if not vesper_choices.has(e.get("choice", "")):
			errs.append("ending %s is bound to choice '%s', which the finale does not offer" % [e.get("id", ""), e.get("choice", "")])
	if not ending_ids.has(w.get("fallback_ending", "")):
		errs.append("fallback ending '%s' does not exist" % w.get("fallback_ending", ""))
	_lint_thresholds(d, errs)
	var faction_ids := {}
	for f: Dictionary in w.get("factions", []):
		if faction_ids.has(f.get("id", "")):
			errs.append("duplicate faction id '%s'" % f.get("id", ""))
		faction_ids[f.get("id", "")] = true
	for e: Dictionary in w.get("endings", []):
		_tone(errs, "ending %s name" % e["id"], e["name"])
		_tone(errs, "ending %s summary" % e["id"], e["summary"])
	for f: Dictionary in w.get("factions", []):
		_tone(errs, "faction %s summary" % f.get("id", ""), str(f.get("summary", "")))
	if int(w["hollowing"]["refill_cost_reserves"]) < 0:
		errs.append("hollowing refill_cost_reserves must not be negative")
	if int(w["pursuit"]["quiet_stage"]) != int(w["pursuit"]["stage_max"]):
		errs.append("pursuit quiet_stage must equal stage_max")
	var pct: int = int(w.get("hollowing", {}).get("drone_percent", 0))
	if pct < 1 or pct > 99:
		errs.append("hollowing drone_percent %d must be 1-99" % pct)
	for key in ["procession", "reserves"]:
		if int(w.get("resources", {}).get(key, {}).get("start", -1)) < 0:
			errs.append("resource %s needs a non-negative start" % key)


# --- helpers -------------------------------------------------------------------

static func _stat_ranges(errs: Array[String], who: String, stats: Dictionary) -> void:
	for stat in STAT_RANGES:
		var v := int(stats.get(stat, -99))
		if v < STAT_RANGES[stat][0] or v > STAT_RANGES[stat][1]:
			errs.append("%s: stat %s=%d is outside %s" % [who, stat, v, STAT_RANGES[stat]])


static func _ids(list: Array) -> Array:
	return list.map(func(x): return x.get("id", ""))


static func _scene_ids(d: Dictionary) -> Dictionary:
	var out := {}
	for s: Dictionary in d["scenes"].get("scenes", []):
		out[s.get("id", "")] = s
	return out


## Tone rules: no modern slang, no exclamation marks.
static func _tone(errs: Array[String], where: String, text: String) -> void:
	if _banned_re == null:
		_banned_re = RegEx.create_from_string("(?i)\\b(" + "|".join(BANNED) + ")\\b")
	var hit := _banned_re.search(text)
	if hit != null:
		errs.append("%s: banned word '%s'" % [where, hit.get_string()])
	if text.contains("!"):
		errs.append("%s: exclamation mark (the voice is quiet)" % where)


## Ending requirements must be satisfiable: flags that a choice can actually
## set, and remembrance that a realistic play can reach.
static func _lint_thresholds(d: Dictionary, errs: Array[String]) -> void:
	var settable := {}
	var other_remembrance := 0
	for s: Dictionary in d["scenes"]["scenes"]:
		for c: Dictionary in s.get("choices", []):
			for key in c["sets"]:
				settable[key] = true
				if key == "remembrance" and s["id"] != "roll_call_prompt":
					other_remembrance += int(c["sets"][key])
	var realistic: int = (d["cast"]["mercs"] as Array).size() / 2 + other_remembrance
	for e: Dictionary in d["world"]["endings"]:
		var req: Dictionary = e["requires"]
		for f in req.get("flags", []):
			if not settable.has(f):
				errs.append("ending %s requires flag '%s', which no choice sets" % [e["id"], f])
		if int(req.get("remembrance_min", 0)) > realistic:
			errs.append("ending %s needs remembrance %d, which is not attainable (about %d)" % [e["id"], int(req["remembrance_min"]), realistic])
		if int(req.get("writ_stage_min", 0)) > int(d["world"]["pursuit"]["stage_max"]):
			errs.append("ending %s needs a writ stage beyond stage_max" % e["id"])
	if int(d["world"]["pursuit"]["true_name_remembrance"]) > realistic:
		errs.append("Orrick's true name needs remembrance %d, which is not attainable (about %d)" % [int(d["world"]["pursuit"]["true_name_remembrance"]), realistic])
