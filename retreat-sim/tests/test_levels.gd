extends TestBase
## Act 1 level systems: map goals, enemy roles, reinforcements.

const ACT1 := ["karsa_breakout", "the_weir", "pellam_dock", "orchard_ring"]


func story() -> Dictionary:
	return StoryData.load_dir("res://data/story")["data"]


func tiles(list: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for t in list:
		out.append(Vector2i(int(t[0]), int(t[1])))
	return out


# --- map data -------------------------------------------------------------------

func test_act1_maps_carry_enemies_zones_and_a_goal() -> void:
	for id in ACT1:
		var m := MapData.load_file(id)
		check(m.problem() == "", "%s is playable: %s" % [id, m.problem()])
		check(not m.enemy_defs.is_empty() and not m.zones.is_empty() and not m.goal.is_empty(), "%s has enemies, zones and a goal" % id)
	check(MapData.load_file("karsa_breakout").width == 16 and MapData.load_file("the_weir").height == 14, "the maps are bigger than 12x10 where the job needs it")


func test_act1_starts_and_sizes_differ_from_each_other() -> void:
	var starts := {}
	var sizes := {}
	for id in ACT1:
		var m := MapData.load_file(id)
		starts[str(m.player_spawns)] = true
		sizes["%dx%d" % [m.width, m.height]] = true
	check(starts.size() == 4, "every Act 1 map starts the squad somewhere different")
	check(sizes.size() >= 3, "map sizes vary")


func test_route_sizes_and_rosters_match_the_maps() -> void:
	var s := story()
	for m: Dictionary in s["route"]["missions"]:
		if not ACT1.has(m["id"]):
			continue
		var map := MapData.load_file(m["id"])
		check(map.width == int(m["map"]["size"][0]) and map.height == int(m["map"]["size"][1]), "%s: route size matches the map" % m["id"])
		var counts := {}
		for e: Dictionary in map.enemy_defs + map.reinforcement_defs:
			counts[e["tier"]] = int(counts.get(e["tier"], 0)) + 1
		var roster := {}
		for tier in m["enemies"]["roster"]:
			roster[tier] = int(m["enemies"]["roster"][tier])
		check(counts == roster, "%s: the roster %s equals the map's enemies %s" % [m["id"], roster, counts])


func test_validation_catches_bad_enemy_zone_and_goal_data() -> void:
	var base := JSON.parse_string(FileAccess.get_file_as_string("res://data/maps/karsa_breakout.json")) as Dictionary
	var d := base.duplicate(true)
	d["enemy_defs"][0]["pos"] = [8, 3]  # inside the bulkhead column? make it a blocked tile instead
	d["blocked"].append([8, 3])
	check(MapData.from_dict(d).problem().contains("enemy"), "an enemy on a blocked tile is caught")
	d = base.duplicate(true)
	d["goal"]["zone"] = "NOWHERE"
	check(MapData.from_dict(d).problem().contains("NOWHERE"), "a goal naming a missing zone is caught")
	d = base.duplicate(true)
	d["enemy_defs"][0]["role"] = "wizard"
	check(MapData.from_dict(d).problem().contains("role"), "an unknown role is caught")
	d = base.duplicate(true)
	d["enemy_defs"][0]["facing"] = [0, 0]
	check(MapData.from_dict(d).problem().contains("facing"), "a sentry needs a facing")
	d = base.duplicate(true)
	d["reinforcement_defs"].append({"pos": [99, 99], "tier": "conscript", "round": 2})
	check(MapData.from_dict(d).problem().contains("reinforcement"), "a reinforcement off the map is caught")


# --- goals ------------------------------------------------------------------------

func goal_state(player: Array, enemy: Array) -> SimState:
	var s := make_state(16, 12)
	var id := 1
	for p in player:
		add_unit(s, id, 0, Vector2i(int(p[0]), int(p[1])))
		id += 1
	id = 200
	for e in enemy:
		add_unit(s, id, 1, Vector2i(int(e[0]), int(e[1])))
		id += 1
	return s


func test_hold_wins_when_a_merc_sits_on_the_zone_and_the_spine_is_clear() -> void:
	var g := SimGoal.new({"type": "hold", "zone": "LOCK", "clear": "SPINE"}, {"LOCK": tiles([[14, 1]]), "SPINE": tiles([[10, 1], [11, 1]])})
	g.round_end(goal_state([[3, 3]], [[11, 1]]), 0)
	check(not g.won, "nobody on the lock yet")
	g.round_end(goal_state([[14, 1]], [[11, 1]]), 0)
	check(not g.won, "an enemy still in the spine blocks it")
	g.round_end(goal_state([[14, 1]], [[3, 3]]), 0)
	check(g.won, "on the lock with the spine empty wins")


func test_collect_needs_every_cache_then_everyone_home() -> void:
	var g := SimGoal.new({"type": "collect", "caches": ["A", "B"], "exit": "TUG"}, {"A": tiles([[3, 10]]), "B": tiles([[15, 3]]), "TUG": tiles([[0, 0], [1, 0]])})
	g.round_end(goal_state([[3, 10], [4, 4]], []), 0)
	check(g.collected.has("A") and not g.won, "standing on a cache at round end collects it")
	g.round_end(goal_state([[0, 0], [1, 0]], []), 0)
	check(not g.won, "home early, caches missing: no win")
	g.round_end(goal_state([[15, 3], [4, 4]], []), 0)
	check(g.collected.size() == 2 and not g.won, "all caches, but a merc is still out")
	g.round_end(goal_state([[0, 0], [1, 0]], []), 0)
	check(g.won, "everyone in the exit with all caches wins")
	var dead := SimGoal.new({"type": "collect", "caches": ["A"], "exit": "TUG"}, {"A": tiles([[3, 10]]), "TUG": tiles([[0, 0]])})
	var s := goal_state([[3, 10], [9, 9]], [])
	dead.round_end(s, 0)
	s.units[2].alive = false
	s.units[1].pos = Vector2i(0, 0)
	dead.round_end(s, 0)
	check(dead.won, "a fallen merc does not have to come home")


func test_survive_counts_rounds_and_charges_for_enemies_on_the_berths() -> void:
	var g := SimGoal.new({"type": "survive", "rounds": 3, "watch": "BERTHS", "penalty": 50}, {"BERTHS": tiles([[3, 11], [4, 11]])})
	g.round_end(goal_state([[1, 1]], [[3, 11], [9, 9]]), 0)
	check(g.penalty_total == 50 and not g.won, "one enemy on a berth costs 50")
	g.round_end(goal_state([[1, 1]], [[3, 11], [4, 11]]), 0)
	check(g.penalty_total == 150, "two more enemies on berths cost 100 more")
	g.round_end(goal_state([[1, 1]], [[9, 9]]), 0)
	check(g.won and g.rounds_done == 3, "surviving the last round wins")
	var none := SimGoal.new({"type": "survive", "rounds": 2, "watch": "BERTHS", "penalty": 50}, {"BERTHS": tiles([[3, 11]])})
	none.round_end(goal_state([], [[9, 9]]), 0)
	check(not none.won, "with no mercs left there is nothing to survive")


func test_reach_return_is_two_ordered_steps() -> void:
	var g := SimGoal.new({"type": "reach_return", "steps": ["HOUSE", "HATCH"]}, {"HOUSE": tiles([[6, 6]]), "HATCH": tiles([[12, 0]])})
	g.round_end(goal_state([[12, 0]], []), 0)
	check(g.step == 0 and not g.won, "the hatch counts only after the greenhouse")
	g.round_end(goal_state([[6, 6]], []), 0)
	check(g.step == 1 and not g.won, "reaching the greenhouse unlocks the next step")
	g.round_end(goal_state([[12, 0]], []), 0)
	check(g.won, "then the hatch wins")


func test_a_goal_reports_progress_and_marks_its_zones() -> void:
	var g := SimGoal.new({"type": "collect", "caches": ["A", "B"], "exit": "TUG"}, {"A": tiles([[3, 10]]), "B": tiles([[15, 3]]), "TUG": tiles([[0, 0]])})
	check(g.progress_text().contains("0 of 2"), "progress names the caches: %s" % g.progress_text())
	var kinds := g.zone_marks().map(func(z: Dictionary) -> String: return z["kind"])
	check(kinds.count("objective") == 2 and kinds.count("exit") == 1, "caches are objective marks and the tug is the exit")
	check(SimGoal.new({}, {}).zone_marks().is_empty() and not SimGoal.new({}, {}).won, "no goal: nothing to mark and nothing won")


# --- roles, reinforcements and the live match ----------------------------------------

func test_missions_build_from_the_maps_with_roles_and_watch_directions() -> void:
	var c := Campaign.new_game(story())
	var m := MissionBuilder.build(c, "karsa_breakout", [1, 2, 3])
	var map := MapData.load_file("karsa_breakout")
	check(m.state.units.size() == 3 + map.enemy_defs.size(), "squad plus the map's enemies")
	var sentry: SimUnit = null
	for e: Dictionary in map.enemy_defs:
		var u: SimUnit = m.state.unit_at(e["pos"])
		check(u != null and u.team == 1, "an enemy stands on %s" % [e["pos"]])
		if e["role"] == "sentry":
			sentry = u
			check(m.assignments[u.id] == "sentry" and u.watch_dir == e["facing"], "the sentry gets the sentry profile and its watch direction")
	check(sentry != null, "karsa has its sentry on the fire door")
	check(m.goal != null and m.goal.goal_type == "hold", "the goal comes from the map")


func test_sentries_hold_overwatch_guards_stay_put_and_patrols_advance() -> void:
	var profiles: Dictionary = SimAIProfile.load_file(SimMatch.PROFILE_FILE)["profiles"]
	for name in ["sentry", "guard", "aggressor"]:
		check(profiles.has(name), "profile %s exists" % name)
	var s := make_state(16, 12)
	add_unit(s, 1, 0, Vector2i(1, 9))
	var sentry := add_unit(s, 200, 1, Vector2i(11, 5))
	sentry.watch_dir = Vector2i(-1, 0)
	var guard := add_unit(s, 201, 1, Vector2i(14, 1))
	var patrol := add_unit(s, 202, 1, Vector2i(13, 9))
	var plan := SimAI.plan_for(s, 1, profiles, {200: "sentry", 201: "guard", 202: "aggressor"}, Vector2i(1, 5))
	var sentry_acts: Array = plan.orders.get(200, [])
	check(sentry_acts.size() == 1 and (sentry_acts[0] as SimAction).type == SimConst.ACTION_OVERWATCH and (sentry_acts[0] as SimAction).dir == Vector2i(-1, 0), "the sentry holds overwatch facing its lane without moving")
	var guard_moves := (plan.orders.get(201, []) as Array).filter(func(a: SimAction) -> bool: return a.type == SimConst.ACTION_MOVE)
	check(guard_moves.is_empty(), "the guard does not walk off its tile")
	var patrol_moves := (plan.orders.get(202, []) as Array).filter(func(a: SimAction) -> bool: return a.type == SimConst.ACTION_MOVE)
	check(not patrol_moves.is_empty(), "the patrol pushes toward the squad")


func test_reinforcements_arrive_on_their_round_and_are_announced() -> void:
	var c := Campaign.new_game(story())
	var m := MissionBuilder.build(c, "pellam_dock", [1, 2, 3, 4])
	var before := m.state.units.size()
	check(m.reinforcements.size() == 2, "two reinforcements are waiting")
	var start_ids := m.state.units.keys()
	for r in 40:
		if m.turn >= 2 or m.is_over():
			break
		m.step()
	check(m.turn == 2 and m.state.units.size() == before + 2, "they arrive when round 2 begins")
	check(m.notices.size() >= 1 and String(m.notices[0]).to_lower().contains("reinforcement"), "and the match says so: %s" % [m.notices])
	var ids := {}
	for id in m.state.units:
		ids[id] = true
	check(ids.size() == m.state.units.size() and not start_ids.any(func(id) -> bool: return not ids.has(id)), "ids stay unique and nobody was replaced")


func test_a_goal_ends_the_match_and_the_penalty_reaches_the_outcome() -> void:
	var s := goal_state([[14, 1]], [[3, 3]])
	var game := SimMatch.new(s, 0, {}, {})
	game.goal = SimGoal.new({"type": "hold", "zone": "LOCK", "clear": "SPINE"}, {"LOCK": tiles([[14, 1]]), "SPINE": tiles([[10, 1]])})
	for i in 25:
		if game.is_over():
			break
		game.step()
	check(game.is_over() and game.winner == 0, "holding the lock to the end of a round wins the match")
	var surv := goal_state([[1, 1]], [[3, 11]])
	var profiles: Dictionary = SimAIProfile.load_file(SimMatch.PROFILE_FILE)["profiles"]
	var g2 := SimMatch.new(surv, 0, profiles, {200: "guard"})  # a guard stays on its berth tile
	g2.goal = SimGoal.new({"type": "survive", "rounds": 1, "watch": "B", "penalty": 50}, {"B": tiles([[3, 11]])})
	for i in 25:
		if g2.is_over():
			break
		g2.step()
	check(g2.goal.penalty_total >= 50, "berth penalty accrued: %d" % g2.goal.penalty_total)
	var c := Campaign.new_game(story())
	var before := c.procession
	c.complete_mission("karsa_breakout", true, [], [], [], false, 100)
	check(c.procession == before + int(story()["route"]["missions"][0]["on_success"]["procession"]) - 100, "the penalty comes off the Procession")
