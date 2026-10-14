class_name UnitSprites
extends RefCounted
## Which sprite set a unit draws with. Sets live in res://assets/mercs/ as
## <key>_<frame>.png (see art/slice_character.py). Pure mapping, no drawing.

## Player slot -> sprite key (slot 1..12).
const MERC_KEYS := {
	1: "warden", 2: "quill", 3: "moth", 4: "sable", 5: "bulwark", 6: "static",
	7: "pilgrim", 8: "needle", 9: "gran", 10: "tinker", 11: "ghost", 12: "wren",
}
## Writ officer slot (unit id 100 + slot) -> sprite key.
const WRIT_KEYS := {1: "clerk", 2: "gavel", 3: "seal", 4: "notary", 5: "surveyor", 6: "usher"}
const PROVOST_ID := 100
const WRIT_ID_BASE := 100
const TIER_KEYS: Array[String] = ["conscript", "regular", "veteran"]  # id bases 200, 210, 220
const TIER_ID_BASE := 200
const TIER_ID_STEP := 10
const HOLLOW_OFFSET := 100  # a hollow variant's ids are its tier's plus this
const FALLBACK_PLAYER := "warden"
const FALLBACK_ENEMY := "regular"


static func key_for(id: int, team: int, is_drone: bool) -> String:
	if team == 0:
		if is_drone:
			return "hollow"
		return MERC_KEYS.get(id, FALLBACK_PLAYER)
	if id == PROVOST_ID:
		return "orrick"
	if id > WRIT_ID_BASE and id < WRIT_ID_BASE + 10:
		return WRIT_KEYS.get(id - WRIT_ID_BASE, FALLBACK_ENEMY)
	if id >= TIER_ID_BASE + HOLLOW_OFFSET:
		return "hollow"
	if id >= TIER_ID_BASE:
		var tier := (id - TIER_ID_BASE) / TIER_ID_STEP
		if tier < TIER_KEYS.size():
			return TIER_KEYS[tier]
	return FALLBACK_ENEMY


## Every sprite key the game can ask for (tests check each has its art).
static func all_keys() -> Array[String]:
	var out: Array[String] = []
	for k in MERC_KEYS.values():
		out.append(k)
	for k in WRIT_KEYS.values():
		out.append(k)
	out.append_array(TIER_KEYS)
	out.append("hollow")
	out.append("orrick")
	return out
