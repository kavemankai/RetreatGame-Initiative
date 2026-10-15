extends TestBase
## The weapon traits: beam (ignores half cover and range falloff), area (blast on the target tile and
## the eight around it, walls stop it, allies are hurt), burst (three shots in one action), plus how
## they sit on a unit, in reaction fire, in the planner's valuation and across whole battles.

var story: Dictionary = StoryData.load_dir("res://data/story")["data"]


func arena(kind := "", shooter_pos := Vector2i(2, 5), target_pos := Vector2i(6, 5), target_hp := 5) -> SimState:
	var s := make_state(12, 12)
	var shooter := add_unit(s, 1, 0, shooter_pos, 5, 5, 5)
	shooter.weapon_trait = kind
	add_unit(s, 10, 1, target_pos, target_hp, 5, 5)
	return s


func events_of_type(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e["type"] == type)


# --- beam --------------------------------------------------------------------------------------

func test_a_beam_ignores_half_cover_but_a_full_wall_still_stops_it() -> void:
	var rifle := arena()
	rifle.grid.set_edge(Vector2i(5, 5), Vector2i(6, 5), SimConst.EDGE_HALF)
	var plain_shot := SimResolver.evaluate_shot(rifle.grid, rifle.units[1], rifle.units[1].pos, rifle.units[10])
	check(plain_shot["result"] == "hit" and plain_shot["cover"] == true, "a plain rifle is slowed by the half wall")
	var beam := arena("beam")
	beam.grid.set_edge(Vector2i(5, 5), Vector2i(6, 5), SimConst.EDGE_HALF)
	var beam_shot := SimResolver.evaluate_shot(beam.grid, beam.units[1], beam.units[1].pos, beam.units[10])
	check(beam_shot["result"] == "hit" and not beam_shot.has("cover") and int(beam_shot["chance"]) > int(plain_shot["chance"]), "a beam goes through half cover with no penalty")
	var walled := arena("beam")
	walled.grid.set_edge(Vector2i(4, 5), Vector2i(5, 5), SimConst.EDGE_FULL)
	var r := SimResolver.evaluate_shot(walled.grid, walled.units[1], walled.units[1].pos, walled.units[10])
	check(r["result"] == "invalid" and r["reason"] == "no_los", "a full wall still blocks a beam")


func test_a_beam_loses_nothing_to_range() -> void:
	var beam := SimUnit.make(1, 0, Vector2i.ZERO, 3, 5, 5)
	beam.weapon_trait = "beam"
	var plain := SimUnit.make(2, 0, Vector2i.ZERO, 3, 5, 5)
	check(beam.hit_chance_at(7) == beam.hit_chance_at(2), "a beam's chance is the same at 2 and 7 tiles")
	check(plain.hit_chance_at(7) < plain.hit_chance_at(2) and beam.hit_chance_at(7) > plain.hit_chance_at(7), "a plain weapon falls off with range and a beam does not")


# --- area --------------------------------------------------------------------------------------

func test_an_area_shot_hurts_the_target_its_neighbours_and_allies_but_not_bystanders() -> void:
	var s := arena("area")
	add_unit(s, 11, 1, Vector2i(7, 5), 5)   # next to the target
	add_unit(s, 12, 1, Vector2i(6, 6), 1)   # next to the target, will die
	add_unit(s, 2, 0, Vector2i(5, 5), 5)    # one of the shooter's own, next to the target
	add_unit(s, 13, 1, Vector2i(9, 9), 5)   # nowhere near
	var shooter: SimUnit = s.units[1]
	var events := ShotResolver.fire(s, shooter, 10, 1, 1, false)
	check(s.units[10].hp == 4 and s.units[11].hp == 4 and not s.units[12].alive and s.units[2].hp == 4, "target, a neighbour and an ally lose a point; the weak neighbour dies")
	check(s.units[13].hp == 5 and s.units[1].hp == 5, "a bystander and the shooter are untouched")
	check(events_of_type(events, "splash").size() == 3 and events_of_type(events, "death").size() == 1, "three splash events and one death")
	check(int(shooter.counters.get("hits_landed", 0)) == 3 and int(shooter.counters.get("kills", 0)) == 1, "enemies hit count for the shooter (3), the ally does not; one kill")


func test_a_full_wall_shuts_a_neighbour_out_of_the_blast() -> void:
	var s := arena("area")
	add_unit(s, 11, 1, Vector2i(7, 5), 5)
	s.grid.set_edge(Vector2i(6, 5), Vector2i(7, 5), SimConst.EDGE_FULL)
	var tiles := SimResolver.blast_tiles(s.grid, Vector2i(6, 5))
	check(tiles.has(Vector2i(6, 5)) and tiles.has(Vector2i(5, 5)) and not tiles.has(Vector2i(7, 5)), "the walled-off tile is not in the blast")
	ShotResolver.fire(s, s.units[1], 10, 1, 1, false)
	check(s.units[10].hp == 4 and s.units[11].hp == 5, "so its occupant is not hurt")
	var blocked := arena("area")
	blocked.grid.set_edge(Vector2i(7, 7), Vector2i(7, 8), SimConst.EDGE_HALF)
	check(SimResolver.blast_tiles(blocked.grid, Vector2i(7, 7)).size() == 9, "a half wall does not stop a blast")


func test_an_area_weapon_cannot_fire_at_something_too_close() -> void:
	var near := arena("area", Vector2i(5, 5), Vector2i(6, 5))
	var r := SimResolver.evaluate_shot(near.grid, near.units[1], near.units[1].pos, near.units[10])
	check(r["result"] == "invalid" and r["reason"] == "too_close", "adjacent is too close")
	var ok := arena("area", Vector2i(4, 5), Vector2i(6, 5))
	check(SimResolver.evaluate_shot(ok.grid, ok.units[1], ok.units[1].pos, ok.units[10])["result"] == "hit" and SimResolver.evaluate_shot(ok.grid, ok.units[1], ok.units[1].pos, ok.units[10])["area"], "two tiles is fine and the preview says it is an area shot")


func test_a_missed_area_shot_has_no_blast() -> void:
	var miss := arena("area")
	add_unit(miss, 11, 1, Vector2i(7, 5), 5)
	miss.fixed_roll = 100
	var events := ShotResolver.fire(miss, miss.units[1], 10, 1, 1, false)
	check(events[0]["result"] == "miss" and events_of_type(events, "splash").is_empty() and miss.units[11].hp == 5 and miss.units[10].hp == 5, "a miss hurts nobody")
	var cover := arena("area")
	cover.grid.set_edge(Vector2i(5, 5), Vector2i(6, 5), SimConst.EDGE_HALF)
	add_unit(cover, 11, 1, Vector2i(7, 5), 5)
	cover.fixed_roll = 1
	var landed := ShotResolver.fire(cover, cover.units[1], 10, 1, 1, false)
	check(landed[0]["result"] == "hit" and not events_of_type(landed, "splash").is_empty(), "a shell into cover that lands still blasts")


# --- burst -------------------------------------------------------------------------------------

func test_a_burst_fires_three_shots_for_one_action_at_a_lower_chance() -> void:
	var s := arena("burst")
	var shooter: SimUnit = s.units[1]
	var normal := SimResolver.evaluate_shot(s.grid, shooter, shooter.pos, s.units[10], false, true)
	var burst := SimResolver.evaluate_shot(s.grid, shooter, shooter.pos, s.units[10])
	check(burst["burst"] == 3 and burst["chance"] == normal["chance"] - SimConst.BURST_ACCURACY_PENALTY and not normal.has("burst"), "the preview shows three shots and a chance 15 points lower")
	var events := ShotResolver.fire(s, shooter, 10, 1, 1, false)
	var shots := events_of_type(events, "shot")
	check(shots.size() == 3 and shots[0]["bullet"] == 0 and shots[2]["bullet"] == 2, "three shot events, numbered")
	check(s.units[10].hp == 2 and events_of_type(events, "morale").size() <= 1, "three hits of 1, and at most one morale check")
	check(int(shooter.counters.get("shots_fired", 0)) == 3 and int(shooter.counters.get("hits_landed", 0)) == 3, "three shots fired, three hits")


func test_a_burst_stops_when_the_target_drops() -> void:
	var s := arena("burst", Vector2i(2, 5), Vector2i(6, 5), 2)
	var events := ShotResolver.fire(s, s.units[1], 10, 1, 1, false)
	check(events_of_type(events, "shot").size() == 2 and events_of_type(events, "death").size() == 1 and events_of_type(events, "morale").is_empty(), "two shots kill it; no third shot and no morale check")
	check(int(s.units[1].counters.get("shots_fired", 0)) == 2, "only the shots fired are counted")


func test_a_reaction_shot_is_single_even_with_a_burst_weapon() -> void:
	var s := arena("burst")
	var events := ShotResolver.fire(s, s.units[1], 10, 1, 1, false, true)
	check(events_of_type(events, "shot").size() == 1 and not events[0].has("burst") and not events[0].has("bullet"), "one ordinary shot")
	var normal := SimResolver.evaluate_shot(s.grid, s.units[1], s.units[1].pos, s.units[10], false, true)
	check(events[0]["chance"] == normal["chance"], "with no burst penalty")


func test_bursts_roll_distinct_dice_and_repeat_exactly() -> void:
	var a := arena("burst")
	a.fixed_roll = -1
	a.seed = 91
	var b := a.clone()
	var ea := ShotResolver.fire(a, a.units[1], 10, 1, 1, false)
	var eb := ShotResolver.fire(b, b.units[1], 10, 1, 1, false)
	check(str(ea) == str(eb), "the same seed gives the same burst")
	var rolls := events_of_type(ea, "shot").map(func(e: Dictionary) -> int: return e.get("roll", -1))
	check(rolls.size() == 3 and (rolls[0] != rolls[1] or rolls[1] != rolls[2]), "the three bullets do not all use one roll: %s" % [rolls])


func test_the_activation_engine_charges_one_action_for_a_burst_and_overwatch_stays_single() -> void:
	var s := make_state(16, 12)
	var shooter := add_unit(s, 1, 0, Vector2i(2, 5), 5, 9, 5)
	shooter.weapon_trait = "burst"
	shooter.weapon_shot_ticks = 6
	add_unit(s, 200, 1, Vector2i(7, 5), 6, 3, 5)
	var cs := CombatState.create(s)
	ActivationScheduler.start(cs)
	var r := ActionResolver.submit(cs, CombatAction.shoot(1, 200))
	check(r.success and r.cost == 6 and events_of_type(r.events, "shot").size() == 3, "one action, 6 AP, three shots")
	check(CombatInvariants.check(cs).is_empty(), "invariants hold")
	var s2 := make_state(20, 12)
	var watcher := add_unit(s2, 1, 0, Vector2i(4, 5), 5, 9, 5)
	watcher.weapon_trait = "burst"
	add_unit(s2, 200, 1, Vector2i(12, 5), 8, 4, 5)
	add_unit(s2, 201, 1, Vector2i(19, 11), 3, 1, 1)
	var cs2 := CombatState.create(s2)
	ActivationScheduler.start(cs2)
	ActionResolver.submit(cs2, CombatAction.overwatch(1, Vector2i.RIGHT))
	ActionResolver.submit(cs2, CombatAction.end_turn(1))
	var move := ActionResolver.submit(cs2, CombatAction.move_to(200, Vector2i(8, 5)))
	var reaction := events_of_type(move.events, "shot").filter(func(e: Dictionary) -> bool: return e.get("reaction", false))
	check(reaction.size() == 1, "an overwatch burst weapon fires one shot, not three")


# --- on the unit and in the data -------------------------------------------------------------------

func test_a_weapon_trait_does_not_overwrite_a_mods_trait() -> void:
	var c := Campaign.new_game(story)
	var u := SimUnit.make(5, 0, Vector2i.ZERO, 4, 3, 5)
	Campaign.apply_item(u, c.item("scope"))
	Campaign.apply_item(u, c.item("minigun"))
	check(u.gear_trait == "scope" and u.weapon_trait == "burst" and u.weapon_class == "heavy", "scope stays a mod trait; the minigun sets burst and heavy")
	check(u.sight_range == SimConst.SIGHT_RANGE + SimConst.SCOPE_SIGHT, "the scope still extends sight")
	var clone := u.clone()
	check(clone.weapon_trait == "burst" and clone.weapon_class == "heavy" and clone.gear_trait == "scope", "clone keeps both")
	var back := SimUnit.from_dict(JSON.parse_string(JSON.stringify(u.to_dict())))
	check(back.weapon_trait == "burst" and back.weapon_class == "heavy" and back.gear_trait == "scope", "a save round trip keeps both")
	var plain := SimUnit.make(6, 0, Vector2i.ZERO, 3, 5, 5)
	Campaign.apply_item(plain, c.item("service_rifle"))
	check(plain.weapon_class == "rifle" and plain.weapon_trait == "", "an ordinary rifle sets only its class")


func test_a_sandbox_squad_with_special_weapons_fields_them() -> void:
	var cfg := Sandbox.default_config(story)
	cfg = Sandbox.with_gear(cfg, 0, "weapon", "minigun")
	cfg = Sandbox.with_gear(cfg, 1, "weapon", "heavy_launcher")
	cfg = Sandbox.with_gear(cfg, 2, "weapon", "pulse_laser")
	var m := Sandbox.build(story, cfg)
	check(m.state.units[1].weapon_trait == "burst" and m.state.units[2].weapon_trait == "area" and m.state.units[3].weapon_trait == "beam", "the sandbox builds units with the traits of the weapons they carry")
	check(m.state.units[4].weapon_trait == "" and m.state.units[4].weapon_class == "shotgun", "the untouched merc keeps their class weapon")


# --- the planner -----------------------------------------------------------------------------------

func best_shot(shooter: SimUnit, state: SimState, enemy: SimUnit) -> Dictionary:
	var ctx := {"view": state, "planned_damage": {}, "enemies": [enemy] as Array[SimUnit]}
	var profile := SimAIProfile.new()
	return SimAI._best_shot(ctx, shooter, shooter.pos, profile)


func test_the_planner_values_a_burst_above_a_single_shot() -> void:
	var single := arena("")
	var burst := arena("burst")
	var a := best_shot(single.units[1], single, single.units[10])
	var b := best_shot(burst.units[1], burst, burst.units[10])
	check(not a.is_empty() and not b.is_empty() and int(b["value"]) > int(a["value"]), "a burst is worth more than one shot: %s vs %s" % [b.get("value"), a.get("value")])


func test_the_planner_sees_through_half_cover_for_a_beam_only() -> void:
	var plain := arena("")
	plain.grid.set_edge(Vector2i(5, 5), Vector2i(6, 5), SimConst.EDGE_HALF)
	var open_shot := best_shot(arena("").units[1], arena(""), arena("").units[10])
	var covered_shot := best_shot(plain.units[1], plain, plain.units[10])
	check(not covered_shot.is_empty() and int(covered_shot["value"]) < int(open_shot["value"]), "a rifle still shoots through half cover but values it lower")
	var beam := arena("beam")
	beam.grid.set_edge(Vector2i(5, 5), Vector2i(6, 5), SimConst.EDGE_HALF)
	check(not best_shot(beam.units[1], beam, beam.units[10]).is_empty(), "a beam takes the shot")


func test_the_planner_will_not_shell_its_own_side() -> void:
	var lone := arena("area")
	var clear := best_shot(lone.units[1], lone, lone.units[10])
	var crowded := arena("area")
	add_unit(crowded, 2, 0, Vector2i(5, 5), 1)
	add_unit(crowded, 3, 0, Vector2i(6, 6), 1)
	var risky := best_shot(crowded.units[1], crowded, crowded.units[10])
	check(not clear.is_empty() and int(clear["value"]) > 0, "a clean blast has positive value")
	check(not risky.is_empty() and int(risky["value"]) < 0, "a blast that would kill two friends is worth less than nothing: %s" % [risky.get("value")])
	var enemies := arena("area")
	add_unit(enemies, 11, 1, Vector2i(7, 5), 1)
	add_unit(enemies, 12, 1, Vector2i(6, 6), 1)
	check(int(best_shot(enemies.units[1], enemies, enemies.units[10])["value"]) > int(clear["value"]), "catching two more enemies is worth more")


# --- whole battles ----------------------------------------------------------------------------------

func test_battles_with_the_special_weapons_finish_cleanly() -> void:
	var bad: Array[String] = []
	var area_shots := 0
	var bursts := 0
	var beams := 0
	for sd in 6:
		var r := CombatSoak.run_battle(story, sd, false, {"enemies": 4, "weapons": ["minigun", "frag_launcher", "laser_rifle", "long_rifle"]})
		if not r["finished"] or r["frozen"] or r["rejected"] > 0 or not (r["invariant_problems"] as Array).is_empty():
			bad.append("seed %d: finished %s frozen %s refused %d inv %s" % [sd, r["finished"], r["frozen"], r["rejected"], (r["invariant_problems"] as Array).slice(0, 2)])
		for e: Dictionary in (r["cs"] as CombatState).log:
			area_shots += int(e["type"] == "shot" and e.get("unit", -1) == 2)
			bursts += int(e["type"] == "shot" and e.has("bullet"))
			beams += int(e["type"] == "shot" and e.get("unit", -1) == 3)
	check(bad.is_empty(), "no illegal action, freeze or broken invariant: %s" % [bad])
	check(area_shots > 0 and bursts > 0 and beams > 0, "all three special weapons were fired (area shots %d, burst shots %d, laser shots %d)" % [area_shots, bursts, beams])
