class_name CombatConfig
extends RefCounted
## The activation engine's AP budget, read from data/combat/ap_costs.json so tuning never
## touches code. Step and shot prices still come from SimUnit (step_cost, shot_ticks), which
## the legacy rulesets share; they move into this table when the legacy modes are retired.

const FILE := "res://data/combat/ap_costs.json"

var max_ap: int = SimConst.AP_PER_TURN
var overwatch_cost: int = 4


## The table at `path`; a missing or malformed file gives the built-in defaults.
static func load_file(path: String = FILE) -> CombatConfig:
	var cfg := CombatConfig.new()
	if not FileAccess.file_exists(path):
		return cfg
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("CombatConfig: %s is not a JSON object; using defaults" % path)
		return cfg
	cfg.max_ap = maxi(1, int(parsed.get("max_ap", cfg.max_ap)))
	cfg.overwatch_cost = maxi(0, int(parsed.get("overwatch_cost", cfg.overwatch_cost)))
	return cfg


## A unit's AP for one activation: the pool less stress (drones ignore stress).
func pool_for(u: SimUnit) -> int:
	return max_ap if u.is_drone else maxi(0, max_ap - u.stress_penalty)
