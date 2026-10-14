class_name StorySchema
extends RefCounted
## The required shape of the story files. StoryLint runs this first and
## stops if anything is wrong, so its deeper checks can index keys freely.
## Reports "structure: ..." errors; never throws on bad data.

## A JSON number (int or float).
const NUM := -1

const STATS := {"hp": NUM, "speed": NUM, "aim": NUM, "cqb": NUM, "morale": NUM, "sight": NUM}
const COSTS := {"procession": NUM, "reserves": NUM}

const MERC := {
	"id": TYPE_STRING, "slot": NUM, "callsign": TYPE_STRING, "name": TYPE_STRING, "role": TYPE_STRING,
	"start": TYPE_BOOL, "stats": STATS, "bio": TYPE_STRING, "wound": TYPE_STRING,
	"voice": {"samples": TYPE_ARRAY}, "relationships": TYPE_ARRAY, "arc": TYPE_ARRAY,
	"death_line": TYPE_STRING, "hollow_note": TYPE_STRING,
}
const OFFICER := {
	"id": TYPE_STRING, "slot": NUM, "callsign": TYPE_STRING, "name": TYPE_STRING, "rank": TYPE_STRING,
	"stats": STATS, "alive_lines": TYPE_ARRAY, "hollow_lines": TYPE_ARRAY, "introduced": TYPE_STRING,
}
const MISSION := {
	"id": TYPE_STRING, "act": NUM, "name": TYPE_STRING, "summary": TYPE_STRING,
	"objective": {"type": TYPE_STRING, "text": TYPE_STRING}, "squad_size": NUM,
	"map": {"size": TYPE_ARRAY}, "enemies": {"roster": TYPE_DICTIONARY, "writ": TYPE_ARRAY},
	"rewards": TYPE_ARRAY, "next": TYPE_ARRAY, "on_success": COSTS, "on_failure": COSTS, "joins": TYPE_ARRAY,
	"choices": TYPE_ARRAY, "scenes": {"briefing": TYPE_STRING, "debrief": TYPE_STRING}, "orrick_present": TYPE_BOOL,
}
const CARD := {
	"id": TYPE_STRING, "act": NUM, "name": TYPE_STRING, "objective": {"type": TYPE_STRING, "text": TYPE_STRING},
	"squad_size": NUM, "on_success": COSTS, "on_failure": COSTS, "scene": TYPE_STRING,
}
const SCENE := {"id": TYPE_STRING, "kind": TYPE_STRING, "lines": TYPE_ARRAY}
const LINE := {"who": TYPE_STRING, "text": TYPE_STRING}
const CHOICE := {"id": TYPE_STRING, "text": TYPE_STRING, "sets": TYPE_DICTIONARY}
const ENDING := {"id": TYPE_STRING, "name": TYPE_STRING, "choice": TYPE_STRING, "requires": TYPE_DICTIONARY, "summary": TYPE_STRING, "scene": TYPE_STRING}
const WORLD := {
	"title": TYPE_STRING, "endings": TYPE_ARRAY, "fallback_ending": TYPE_STRING, "factions": TYPE_ARRAY,
	"resources": {"procession": {"start": NUM}, "reserves": {"start": NUM}, "remembrance": {"start": NUM}},
	"hollowing": {"drone_percent": NUM, "refill_cost_reserves": NUM},
	"remembrance": {"per_name_read": NUM, "roll_read_threshold": NUM},
	"pursuit": {"stage_max": NUM, "quiet_stage": NUM, "true_name_remembrance": NUM},
}
const WRIT := {"provost": {"id": TYPE_STRING, "stats": STATS, "reveal_mission": TYPE_STRING}, "officers": TYPE_ARRAY, "stage_names": TYPE_ARRAY}
const ROUTE := {
	"start": TYPE_STRING, "finale": TYPE_STRING, "objective_types": TYPE_ARRAY, "missions": TYPE_ARRAY,
	"cards": TYPE_ARRAY, "contingencies_per_act": NUM,
}
const CAST := {"mercs": TYPE_ARRAY}
const TIER := {"rank": NUM, "name": TYPE_STRING, "min_act": NUM, "id_base": NUM, "profile": TYPE_STRING}
const ITEMS := {"slots": TYPE_ARRAY, "traits": TYPE_DICTIONARY, "starting": TYPE_DICTIONARY, "items": TYPE_ARRAY, "drops": TYPE_DICTIONARY}
const ITEM := {"id": TYPE_STRING, "slot": TYPE_STRING, "name": TYPE_STRING, "note": TYPE_STRING, "tier": NUM}
const ENEMY_TIERS := {"tiers": TYPE_DICTIONARY, "hollow": {"min_act": NUM, "id_base_offset": NUM}}


## Returns "structure: ..." errors; empty means every file has its required shape.
static func check(d: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	for key in ["cast", "writ", "route", "world", "scenes", "enemy_tiers", "items"]:
		if not d.has(key) or typeof(d[key]) != TYPE_DICTIONARY:
			errs.append("structure: %s.json is missing or not an object" % key)
	if not errs.is_empty():
		return errs
	_shape(errs, d["cast"], "cast", CAST)
	_shape(errs, d["writ"], "writ", WRIT)
	_shape(errs, d["route"], "route", ROUTE)
	_shape(errs, d["world"], "world", WORLD)
	_shape(errs, d["enemy_tiers"], "enemy_tiers", ENEMY_TIERS)
	_shape(errs, d["items"], "items", ITEMS)
	if typeof(d["scenes"].get("scenes", null)) != TYPE_ARRAY:
		errs.append("structure: scenes.scenes is missing or not an array")
	if not errs.is_empty():
		return errs  # the lists below cannot be walked safely
	_each(errs, d["cast"]["mercs"], "cast.mercs", MERC)
	_each(errs, d["writ"]["officers"], "writ.officers", OFFICER)
	_each(errs, d["route"]["missions"], "route.missions", MISSION)
	_each(errs, d["route"]["cards"], "route.cards", CARD)
	_each(errs, d["world"]["endings"], "world.endings", ENDING)
	_each(errs, d["items"]["items"], "items.items", ITEM)
	for tier_key in d["enemy_tiers"]["tiers"]:
		_shape(errs, d["enemy_tiers"]["tiers"][tier_key], "enemy_tiers.tiers.%s" % tier_key, TIER)
	_each(errs, d["world"]["factions"], "world.factions", {"id": TYPE_STRING})
	_each(errs, d["scenes"]["scenes"], "scenes", SCENE)
	if not errs.is_empty():
		return errs
	for s: Dictionary in d["scenes"]["scenes"]:
		_each(errs, s["lines"], "scene %s lines" % s["id"], LINE)
		if s.has("choices"):
			if typeof(s["choices"]) != TYPE_ARRAY:
				errs.append("structure: scene %s choices is not an array" % s["id"])
			else:
				_each(errs, s["choices"], "scene %s choices" % s["id"], CHOICE)
	return errs


static func _each(errs: Array[String], list: Array, path: String, schema: Dictionary) -> void:
	for i in list.size():
		_shape(errs, list[i], "%s[%d]" % [path, i], schema)


static func _shape(errs: Array[String], obj: Variant, path: String, schema: Dictionary) -> void:
	if typeof(obj) != TYPE_DICTIONARY:
		errs.append("structure: %s is not an object" % path)
		return
	for key in schema:
		if not (obj as Dictionary).has(key):
			errs.append("structure: %s is missing '%s'" % [path, key])
			continue
		var want: Variant = schema[key]
		var got: Variant = obj[key]
		if typeof(want) == TYPE_DICTIONARY:
			_shape(errs, got, "%s.%s" % [path, key], want)
		elif want == NUM:
			if typeof(got) != TYPE_INT and typeof(got) != TYPE_FLOAT:
				errs.append("structure: %s.%s must be a number" % [path, key])
		elif typeof(got) != want:
			errs.append("structure: %s.%s has the wrong type" % [path, key])
