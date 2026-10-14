class_name SimAIProfile
extends RefCounted
## Integer scoring weights for the utility AI. Loaded from data so balance
## changes never touch code. All weights are integers (determinism).

const KEYS: Array[String] = [
	"w_damage", "w_kill", "w_exposed", "w_cover",
	"preferred_range", "w_range", "w_objective", "w_watch",
]

## Weights beyond this magnitude are rejected (guards int overflow in scoring).
const MAX_WEIGHT := 100000

var w_damage: int = 10        ## per point of damage a shot would deal
var w_kill: int = 25          ## bonus when the shot kills
var w_exposed: int = 6        ## penalty per visible enemy that could hit the end tile
var w_cover: int = 3          ## bonus per visible enemy whose shot would be blocked there
var preferred_range: int = 4  ## tiles; ideal distance to the nearest visible enemy
var w_range: int = 2          ## penalty per tile away from preferred_range
var w_objective: int = 2      ## penalty per tile from the objective (no enemy visible)
var w_watch: int = 0          ## overwatch bonus: w_watch x clear cone tiles x hold ticks / 48


## Returns {"profile": SimAIProfile or null, "errors": Array[String]}.
## Missing keys keep their defaults; unknown keys and non-integers are errors.
static func from_dict(d: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var p := SimAIProfile.new()
	for key in d:
		if not KEYS.has(key):
			errors.append("unknown key '%s'" % key)
			continue
		var v: Variant = d[key]
		var ok: bool = (typeof(v) == TYPE_INT) or (typeof(v) == TYPE_FLOAT and float(v) == floorf(float(v)))
		if not ok:
			errors.append("'%s' must be an integer, got %s" % [key, str(v)])
			continue
		if absf(float(v)) > MAX_WEIGHT:
			errors.append("'%s' is out of range (max %d)" % [key, MAX_WEIGHT])
			continue
		p.set(key, int(v))
	return {"profile": null if not errors.is_empty() else p, "errors": errors}


## Returns {"profiles": {name: SimAIProfile}, "errors": Array[String]}.
static func load_file(path: String) -> Dictionary:
	var profiles := {}
	var errors: Array[String] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"profiles": profiles, "errors": ["cannot open %s" % path]}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"profiles": profiles, "errors": ["%s is not a JSON object" % path]}
	for name in parsed:
		var r := from_dict(parsed[name] if typeof(parsed[name]) == TYPE_DICTIONARY else {"": 0})
		if (r["errors"] as Array).is_empty():
			profiles[name] = r["profile"]
		else:
			for e in r["errors"]:
				errors.append("%s: %s" % [name, e])
	if not profiles.has("default"):
		errors.append("missing a valid 'default' profile (built-in weights will be used)")
	return {"profiles": profiles, "errors": errors}
