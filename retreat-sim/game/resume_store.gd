class_name ResumeStore
extends RefCounted
## The one autosave slot for a battle in progress, in the usual mobile-tactics way: written after
## every committed action and whenever the app is paused, never edited by hand, no undo (so it
## cannot be used to reload out of a bad shot), offered as "Resume battle" on the main menu, and
## gone as soon as the fight ends. Starting another battle replaces it. A save that cannot be
## trusted (garbage, another version, an unknown mission, a broken state) is discarded and never
## offered.
##
## The file holds {"meta": {kind, mission_id, label}, "combat": CombatSave}. The map and goal are
## rebuilt from the meta (the sandbox map, or the mission), not stored.

const PATH := "user://combat_resume.json"
const KIND_SANDBOX := "sandbox"
const KIND_LEVEL_TEST := "level_test"


## Writes the slot. A finished fight is never saved (and clears the slot). Returns true if written.
static func save(cs: CombatState, meta: Dictionary, path: String = PATH) -> bool:
	if cs.is_over():
		clear(path)
		return false
	var m := meta.duplicate()
	m["label"] = label_for(cs, m)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("ResumeStore: cannot write %s (error %d)" % [path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify({"meta": m, "combat": CombatSave.to_dict(cs)}))
	return true


## The slot's meta ({kind, mission_id, label}) if there is a plausible save, else {}. Cheap: it
## does not rebuild anything, so the menu can call it every time it opens.
static func peek(path: String = PATH) -> Dictionary:
	var d := _read(path)
	if d.is_empty() or not d.get("meta") is Dictionary or not d.get("combat") is Dictionary:
		return {}
	if int((d["combat"] as Dictionary).get("version", -1)) != CombatSave.VERSION:
		return {}
	return d["meta"]


## Rebuilds the battle: {"cs", "match", "campaign", "meta"} for the screen, or {} (and the slot is
## cleared) if it cannot be trusted.
static func load_battle(story: Dictionary, path: String = PATH) -> Dictionary:
	var meta := peek(path)
	if meta.is_empty():
		clear(path)
		return {}
	var rebuilt := _rebuild(story, meta)
	if rebuilt.is_empty():
		clear(path)
		return {}
	var m: SimMatch = rebuilt["match"]
	var cs := CombatSave.from_dict(_read(path)["combat"], m.state.grid, m.goal)
	if cs == null:
		clear(path)
		return {}
	return {"cs": cs, "match": m, "campaign": rebuilt["campaign"], "meta": meta}


## Puts a loaded battle into Session for the battle screen to pick up (the same way the menu does
## it). Returns false, with the slot cleared, if the save could not be used.
static func enter_session(story: Dictionary) -> bool:
	var loaded := load_battle(story)
	if loaded.is_empty():
		return false
	var meta: Dictionary = loaded["meta"]
	Session.reset()
	Session.ruleset = "activation"
	Session.level_test = true
	Session.sandbox = meta.get("kind") == KIND_SANDBOX
	Session.campaign = loaded["campaign"]
	Session.mission_id = Sandbox.MAP if Session.sandbox else String(meta.get("mission_id", ""))
	Session.current_match = loaded["match"]
	Session.resume_cs = loaded["cs"]
	return true


static func exists(path: String = PATH) -> bool:
	return FileAccess.file_exists(path)


static func clear(path: String = PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## What the menu button says. It names the battle and the squad's state only; nothing about
## enemies the squad has not seen.
static func label_for(cs: CombatState, meta: Dictionary) -> String:
	var alive := 0
	var total := 0
	for id in cs.sim.units:
		var u: SimUnit = cs.sim.units[id]
		if u.team == cs.player_team:
			total += 1
			alive += int(u.alive)
	var name := "Sandbox" if meta.get("kind") == KIND_SANDBOX else String(meta.get("mission_id", "")).replace("_", " ").capitalize()
	return "%s, round %d, %d of %d squad standing" % [name, cs.round_no, alive, total]


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## The match (for its grid and a fresh goal) and the throwaway campaign the screen's names come from.
static func _rebuild(story: Dictionary, meta: Dictionary) -> Dictionary:
	var campaign := Campaign.new_game(story)
	match meta.get("kind"):
		KIND_SANDBOX:
			var map := MapData.load_file(Sandbox.MAP)
			if map == null:
				return {}
			var m := SimMatch.new(map.build_state())
			m.theme = map.theme
			return {"match": m, "campaign": campaign}
		KIND_LEVEL_TEST:
			var id := String(meta.get("mission_id", ""))
			var card: Dictionary = campaign.mission_or_card(id)
			if card.is_empty():
				return {}
			var slots: Array = campaign.available_slots().slice(0, int(card["squad_size"]))
			return {"match": MissionBuilder.build(campaign, id, slots), "campaign": campaign}
	return {}
