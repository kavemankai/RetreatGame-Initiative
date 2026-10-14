class_name MissionBuilder
extends RefCounted
## Turns a campaign mission into a playable SimMatch, and a finished match
## back into the facts the campaign needs (who died, who won).
##
## Each mission is built on its own map (MapData, data/maps/<mission>.json).

const MAX_WRIT_SLOT := 6
## A map role is an AI profile: patrols push like aggressors, sentries and guards hold their ground.
const ROLE_PROFILES := {"sentry": "sentry", "guard": "guard", "patrol": "aggressor"}


## `slots` are the roster slots to field (their numbers become unit ids).
static func build(campaign: Campaign, mission_id: String, slots: Array) -> SimMatch:
	var map := MapData.load_for(campaign.story, mission_id)
	var state := map.build_state()
	state.seed = mission_seed(campaign, mission_id)
	var taken := {}
	for u in campaign.squad_units(mission_id, slots, map.player_spawns):
		state.add_unit(u)
		taken[u.id] = true
	var assignments := {}
	var waiting: Array[Dictionary] = []
	if map.enemy_defs.is_empty():
		for u in campaign.enemy_units(mission_id, map.enemy_spawns):
			state.add_unit(u)
			assignments[u.id] = campaign.tier_profile(u.id)
	else:
		for e: Dictionary in map.enemy_defs:
			var u := _tier_unit(campaign, e["tier"], e["pos"], taken)
			u.watch_dir = e["facing"]
			state.add_unit(u)
			assignments[u.id] = ROLE_PROFILES[e["role"]]
		for r: Dictionary in map.reinforcement_defs:
			var u := _tier_unit(campaign, r["tier"], r["pos"], taken)
			assignments[u.id] = ROLE_PROFILES["patrol"]
			waiting.append({"round": r["round"], "unit": u})
	var profiles: Dictionary = SimAIProfile.load_file(SimMatch.PROFILE_FILE)["profiles"]
	var built := SimMatch.new(state, 0, profiles, assignments)
	built.theme = map.theme
	built.reinforcements = waiting
	if not map.goal.is_empty():
		built.goal = SimGoal.new(map.goal, map.zones)
	return built


## A map enemy of `tier` with the next free id for that tier (ids stay unique across the match).
static func _tier_unit(campaign: Campaign, tier: String, pos: Vector2i, taken: Dictionary) -> SimUnit:
	var id := campaign.next_tier_id(tier, taken)
	taken[id] = true
	return campaign.tier_unit(tier, id, pos)


## The visual theme a mission is played in (see MapData.THEMES).
static func theme_for(campaign: Campaign, mission_id: String) -> String:
	return MapData.load_for(campaign.story, mission_id).theme


## The morale-die seed for a mission: stable for the same mission at the same
## point in the campaign (a retry rolls the same), different between missions.
static func mission_seed(campaign: Campaign, mission_id: String) -> int:
	return absi(mission_id.hash() + campaign.completed.size() * 7919) & SimDice.MASK


## What the campaign needs from a match: {success, dead_slots, writ_dead,
## squad_wiped}. A withdrawal is a failure with survivors.
static func outcome(campaign: Campaign, m: SimMatch, withdrawn: bool) -> Dictionary:
	var dead_slots: Array[int] = []
	var writ_dead: Array[String] = []
	var living := 0
	for id in m.state.units:
		var u: SimUnit = m.state.units[id]
		if u.alive:
			if u.team == m.player_team:
				living += 1
			continue
		if u.team == m.player_team:
			dead_slots.append(id)
		elif _is_officer(id):
			writ_dead.append(_officer_id(campaign, id - Campaign.WRIT_ID_BASE))
	dead_slots.sort()
	return {
		"procession_loss": m.goal.penalty_total if m.goal != null else 0,
		"success": m.is_over() and m.winner == m.player_team and not withdrawn,
		"dead_slots": dead_slots,
		"writ_dead": writ_dead,
		"squad_wiped": living == 0,
	}


static func _is_officer(unit_id: int) -> bool:
	var slot := unit_id - Campaign.WRIT_ID_BASE
	return slot >= 1 and slot <= MAX_WRIT_SLOT


static func _officer_id(campaign: Campaign, slot: int) -> String:
	for o: Dictionary in campaign.story["writ"]["officers"]:
		if int(o["slot"]) == slot:
			return o["id"]
	return ""
