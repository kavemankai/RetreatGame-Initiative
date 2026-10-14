extends TestBase
## Sound: which sound an event makes, the settings, and the sound board.

const DELAY_EPS := 0.0001


func names_of(list: Array) -> Array:
	return list.map(func(r: Dictionary) -> String: return r["name"])


func test_every_referenced_sound_file_exists() -> void:
	for name in SoundMap.all_names():
		check(ResourceLoader.exists("res://assets/audio/%s.wav" % name), "%s.wav exists" % name)


func test_a_hit_cracks_then_thuds() -> void:
	var ev := {"type": "shot", "tick": 4, "unit": 1, "target": 2, "result": "hit", "damage": 1}
	var r := SoundMap.for_event(ev)
	var names := names_of(r)
	check(names.size() == 2 and String(names[0]).begins_with("sfx_shot_") and names[1] == "sfx_hit", "shot then hit; got %s" % [names])
	check(float(r[0]["delay"]) < DELAY_EPS and float(r[1]["delay"]) > 0.0, "the thud follows the crack")
	var heavy := SoundMap.for_event({"type": "shot", "tick": 4, "unit": 1, "target": 2, "result": "hit", "damage": 2})
	check(names_of(heavy)[0] == "sfx_shot_heavy", "a two-damage hit is a heavy shot")


func test_misses_and_cover_have_their_own_sounds() -> void:
	check(names_of(SoundMap.for_event({"type": "shot", "tick": 1, "unit": 1, "target": 2, "result": "miss"}))[1] == "sfx_miss", "a miss whizzes")
	check(names_of(SoundMap.for_event({"type": "shot", "tick": 1, "unit": 1, "target": 2, "result": "blocked"}))[1] == "sfx_blocked", "a shot into cover pings")
	check(SoundMap.for_event({"type": "shot", "tick": 1, "unit": 1, "target": 2, "result": "invalid"}).is_empty(), "an invalid shot is silent")


func test_deaths_morale_and_steps() -> void:
	check(names_of(SoundMap.for_event({"type": "death", "tick": 4, "unit": 2, "killer": 1})) == ["sfx_death"], "a death")
	check(names_of(SoundMap.for_event({"type": "morale", "tick": 4, "unit": 2, "roll": 3, "need": 7, "result": "steady"})) == ["sfx_steady"], "steady chimes")
	check(names_of(SoundMap.for_event({"type": "morale", "tick": 4, "unit": 2, "roll": 9, "need": 7, "result": "broken"})) == ["sfx_broken"], "broken sinks")
	var step := names_of(SoundMap.for_event({"type": "move", "tick": 3, "unit": 1, "from": Vector2i(1, 1), "to": Vector2i(2, 1)}))
	check(step.size() == 1 and String(step[0]).begins_with("sfx_step_"), "a move is a footstep")
	check(SoundMap.for_event({"type": "turn_end", "tick": 20}).is_empty(), "turn end is silent")


func test_variants_are_deterministic_and_vary() -> void:
	var seen := {}
	for tick in range(1, 13):
		var a: String = names_of(SoundMap.for_event({"type": "shot", "tick": tick, "unit": 1, "target": 2, "result": "hit", "damage": 1}))[0]
		var b: String = names_of(SoundMap.for_event({"type": "shot", "tick": tick, "unit": 1, "target": 2, "result": "hit", "damage": 1}))[0]
		check(a == b, "the same shot always sounds the same")
		seen[a] = true
	check(seen.size() == 3, "the three shot variants all come up; got %d" % seen.size())


func test_ambient_and_music_are_chosen_by_theme_and_act() -> void:
	for theme in MapData.THEMES:
		check(ResourceLoader.exists("res://assets/audio/%s.wav" % SoundMap.ambient_for(theme)), "%s has an ambient loop" % theme)
	check(SoundMap.ambient_for("foundry_hold") != SoundMap.ambient_for("hospital_hulk"), "different places sound different")
	check(SoundMap.ambient_for("no_such_theme") == SoundMap.ambient_for("station_deck"), "an unknown theme gets the deck")
	check(SoundMap.music_for(1) == "music_act1" and SoundMap.music_for(3) == "music_act3" and SoundMap.music_for(9) == "music_act3" and SoundMap.music_for(0) == "music_act1", "music by act, clamped")


func test_settings_clamp_convert_and_persist() -> void:
	var s := SoundSettings.new()
	s.sfx = 2.0
	s.music = -1.0
	s.normalise()
	check(s.sfx == 1.0 and s.music == 0.0, "volumes clamp to 0..1")
	check(SoundSettings.to_db(1.0) == 0.0 and SoundSettings.to_db(0.0) <= -60.0 and SoundSettings.to_db(0.5) < 0.0, "linear volume to decibels")
	s.muted = true
	check(s.bus_db("sfx") <= -60.0, "muted silences every bus")
	s.muted = false
	s.sfx = 0.6
	var path := "user://test_sound_settings.json"
	check(s.save(path), "settings save")
	var loaded := SoundSettings.load_from(path)
	check(is_equal_approx(loaded.sfx, 0.6) and not loaded.muted, "and load back")
	DirAccess.remove_absolute(path)
	check(SoundSettings.load_from("user://does_not_exist.json").master == 1.0, "a missing file gives the defaults")


func test_streams_loop_only_when_they_should() -> void:
	var amb := SoundBoard.load_stream("amb_deck")
	var shot := SoundBoard.load_stream("sfx_shot_0")
	check(amb != null and amb.loop_mode == AudioStreamWAV.LOOP_FORWARD and amb.loop_end > 0, "ambient and music loop")
	for name in ["amb_deck", "amb_hospital", "music_act1", "music_act3"]:
		var st := SoundBoard.load_stream(name)
		var samples := st.get_length() * st.mix_rate
		check(absf(float(st.loop_end) - samples) <= samples * 0.01, "%s loops over its whole length (loop_end %d of %d samples)" % [name, st.loop_end, int(samples)])
		check(st.get_length() > 10.0, "%s is a long track, not a fragment" % name)
	check(shot != null and shot.loop_mode == AudioStreamWAV.LOOP_DISABLED, "effects play once")
	check(SoundBoard.load_stream("nope") == null, "an unknown sound is null, not a crash")


func test_sound_board_plays_events_throttles_steps_and_respects_mute() -> void:
	var board := SoundBoard.new()
	board.build()
	TestBase.tree.root.add_child(board)
	board.settings.muted = false
	var shot := {"type": "shot", "tick": 4, "unit": 1, "target": 2, "result": "hit", "damage": 1}
	var evs: Array[Dictionary] = [shot]
	board.play_events(evs)
	check(board.requests.size() == 2, "a hit requests two sounds; got %s" % [board.requests])
	board.requests.clear()
	var steps: Array[Dictionary] = [
		{"type": "move", "tick": 1, "unit": 1, "from": Vector2i(1, 1), "to": Vector2i(2, 1)},
		{"type": "move", "tick": 1, "unit": 3, "from": Vector2i(1, 2), "to": Vector2i(2, 2)},
		{"type": "move", "tick": 1, "unit": 4, "from": Vector2i(1, 3), "to": Vector2i(2, 3)},
	]
	board.play_events(steps)
	check(board.requests.size() == 1, "a crowd of footsteps in one tick is one sound; got %d" % board.requests.size())
	board.requests.clear()
	board.settings.muted = true
	board.play_events(evs)
	check(board.requests.is_empty(), "muted: nothing is requested")
	board.set_ambient("hospital_hulk")
	check(board.current_ambient == "amb_hospital", "ambient follows the theme")
	board.set_music(2)
	check(board.current_music == "music_act2", "music follows the act")
	board.queue_free()


func test_mute_unmute_resumes_the_same_loops_and_silences_late_sounds() -> void:
	var board := SoundBoard.new()
	board.build()
	TestBase.tree.root.add_child(board)
	board.settings.muted = false
	board.set_ambient("foundry_hold")
	board.set_music(3)
	check(board.loops_started == 2, "two loops start")
	board.set_muted(true)
	var loops := board.loops_started
	board.set_ambient("hospital_hulk")
	check(board.loops_started == loops, "muted: a new ambient is remembered but not started")
	var before := board.started
	board._start_voice("sfx_hit", "sfx")
	check(board.started == before, "a delayed sound that fires after mute stays silent")
	board.set_muted(false)
	check(board.current_ambient == "amb_hospital" and board.current_music == "music_act3", "unmuting remembers the latest place and the act")
	check(board.loops_started == loops + 2, "and starts both loops again")
	board._start_voice("ui_click", "ui")
	board._start_voice("sfx_hit", "sfx")
	check(board.started == before + 2, "unmuted sounds start")
	board.settings.muted = false
	board.settings.save()
	board.queue_free()
