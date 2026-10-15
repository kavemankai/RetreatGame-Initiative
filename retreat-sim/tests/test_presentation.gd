extends TestBase
## How weapon classes look and sound: shot events that name their class, tracer styles, burst staggering,
## per-class sounds and the blast, event text and fog visibility, glyphs, chips and shot notes.

var story: Dictionary = StoryData.load_dir("res://data/story")["data"]

const CLASSES: Array[String] = ["rifle", "carbine", "sniper", "shotgun", "heavy", "grenade", "beam"]


func shot(klass: String, result := "hit", extra := {}) -> Dictionary:
	var ev := {"type": "shot", "tick": 4, "unit": 1, "target": 2, "result": result, "damage": 1, "chance": 60, "class": klass}
	ev.merge(extra)
	return ev


func names_of(r: Array[Dictionary]) -> Array:
	return r.map(func(x: Dictionary) -> String: return x["name"])


func test_shot_events_name_the_shooters_weapon_class() -> void:
	var s := make_state()
	var u := add_unit(s, 1, 0, Vector2i(2, 5))
	u.weapon_class = "sniper"
	add_unit(s, 2, 1, Vector2i(6, 5), 9)
	var events := ShotResolver.fire(s, u, 2, 1, 1, false)
	check(events[0]["class"] == "sniper", "the event carries the class")


func test_each_class_has_its_own_shot_sound_and_rifles_keep_their_variants() -> void:
	var expect := {"carbine": "sfx_shot_carbine", "sniper": "sfx_shot_sniper", "shotgun": "sfx_shot_shotgun", "heavy": "sfx_shot_heavy", "grenade": "sfx_shot_grenade", "beam": "sfx_shot_beam"}
	for klass in expect:
		check(names_of(SoundMap.for_event(shot(klass)))[0] == expect[klass], "%s fires %s" % [klass, expect[klass]])
	check(String(names_of(SoundMap.for_event(shot("rifle")))[0]).begins_with("sfx_shot_") and not expect.values().has(names_of(SoundMap.for_event(shot("rifle")))[0]), "a rifle keeps the numbered variants")
	check(names_of(SoundMap.for_event({"type": "shot", "tick": 4, "unit": 1, "target": 2, "result": "hit", "damage": 1}))[0] != "sfx_shot_heavy", "an event with no class still sounds like a rifle")
	var seen := {}
	for klass in CLASSES:
		seen[names_of(SoundMap.for_event(shot(klass)))[0]] = true
	check(seen.size() >= 6, "the classes sound different from each other (%d distinct)" % seen.size())


func test_burst_bullets_are_spaced_and_a_grenade_adds_the_blast() -> void:
	var first := SoundMap.for_event(shot("heavy", "hit", {"bullet": 0, "burst": 3}))
	var third := SoundMap.for_event(shot("heavy", "hit", {"bullet": 2, "burst": 3}))
	check(float(third[0]["delay"]) > float(first[0]["delay"]) + SoundMap.BULLET_GAP, "the third bullet comes later than the first")
	check(float(third[1]["delay"]) > float(first[1]["delay"]), "and so does its impact")
	var grenade := names_of(SoundMap.for_event(shot("grenade")))
	check(grenade.has("sfx_blast"), "a grenade that lands blasts")
	check(not names_of(SoundMap.for_event(shot("grenade", "miss"))).has("sfx_blast") and not names_of(SoundMap.for_event(shot("rifle"))).has("sfx_blast"), "a miss and a rifle do not")


func test_the_weapon_sounds_are_real_audio_of_different_lengths() -> void:
	var lengths := {}
	for name in ["sfx_shot_carbine", "sfx_shot_sniper", "sfx_shot_shotgun", "sfx_shot_grenade", "sfx_shot_beam", "sfx_blast"]:
		var stream := load("res://assets/audio/%s.wav" % name) as AudioStreamWAV
		check(stream != null and stream.get_length() > 0.2, "%s is a sound longer than 0.2 s" % name)
		if stream != null:
			lengths[snappedf(stream.get_length(), 0.01)] = true
	check(lengths.size() == 6, "all six are different recordings (%d distinct lengths)" % lengths.size())


func test_tracers_remember_the_class_and_burst_bullets_start_staggered() -> void:
	var s := make_state()
	var u := add_unit(s, 1, 0, Vector2i(2, 5))
	u.weapon_class = "heavy"
	add_unit(s, 2, 1, Vector2i(6, 5), 9)
	var board := BoardView.new()
	var events: Array[Dictionary] = [shot("heavy", "hit", {"bullet": 0}), shot("heavy", "hit", {"bullet": 1}), shot("heavy", "hit", {"bullet": 2})]
	board.record_tracers(events, s)
	check(board._tracers.size() == 3 and board._tracers[0]["klass"] == "heavy", "three tracers, each knowing its class")
	var ages: Array = board._tracers.map(func(t: Dictionary) -> float: return t["age"])
	check(ages[0] >= ages[1] and ages[1] > ages[2] and ages[2] < 0.0, "later bullets start later: %s" % [ages])
	board.clear_tracers()
	board.record_tracers(events, s, {}, true)
	check(board._tracers.all(func(t: Dictionary) -> bool: return t["age"] >= BoardView.TRACER_GROW), "rebuilding an earlier frame shows them all settled")
	board.free()


func test_every_class_has_a_muzzle_flash_look() -> void:
	for klass in CLASSES:
		check(BoardView.FLASH.has(klass), "%s has a flash size and colour" % klass)
	check(BoardView.FLASH["shotgun"][0] > BoardView.FLASH["carbine"][0] and BoardView.FLASH["sniper"][1] == Color.WHITE, "a shotgun's flash is bigger than a carbine's and a sniper's is white")


func test_event_text_and_fog_visibility_cover_bursts_and_blasts() -> void:
	var fog := {"tiles": {}, "units": {1: true}}
	var burst := ReplayModel.describe(shot("heavy", "hit", {"bullet": 1, "burst": 3}), {}, Callable())
	check(burst.contains("burst 2 of 3"), "a burst bullet says which it is: %s" % burst)
	var splash := {"type": "splash", "tick": 4, "unit": 1, "target": 3, "damage": 1, "center": Vector2i(6, 5)}
	check(ReplayModel.describe(splash, {}, Callable()).contains("blast"), "a blast victim is described")
	check(ReplayModel.event_visible(splash, fog), "a blast is shown if its shooter is visible")
	check(not ReplayModel.event_visible(splash, {"tiles": {}, "units": {9: true}}), "and hidden if neither end is")
	check(ReplayModel.event_visible(splash, {"tiles": {}, "units": {3: true}}), "but shown if its victim is visible")


func test_cards_carry_the_class() -> void:
	var c := Campaign.new_game(story)
	var m := UiModel.merc_info(c, 3)
	check(m["class"] == "sniper" and m["class_name"] == "Marksman", "a merc's card info names the class")
	check(UiModel.item_info(c, "long_rifle")["class"] == "sniper" and UiModel.item_info(c, "scope")["class"] == "", "an item's info carries its class, mods have none")
	var card := MercCard.new().setup(m)
	TestBase.tree.root.add_child(card)
	var texts: Array[String] = []
	for label in card.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	check(" ".join(texts).contains("Marksman"), "the merc card shows the class chip")
	var glyphs: Array[Node] = card.find_children("*", "Control", true, false).filter(func(n: Node) -> bool: return n is SlotGlyph and (n as SlotGlyph).kind == "weapon")
	check(glyphs.size() == 1 and (glyphs[0] as SlotGlyph).weapon_class == "sniper", "and the weapon glyph is the class's")
	card.queue_free()
	var item := ItemCard.new().setup(UiModel.item_info(c, "scatter_gun"))
	TestBase.tree.root.add_child(item)
	var item_glyphs := item.find_children("*", "Control", true, false).filter(func(n: Node) -> bool: return n is SlotGlyph)
	check(item_glyphs.size() == 1 and (item_glyphs[0] as SlotGlyph).weapon_class == "shotgun", "an item card draws its class's glyph")
	item.queue_free()


func test_glyphs_accept_every_class_and_draw_without_error() -> void:
	for klass in CLASSES:
		var g := SlotGlyph.new(40).setup("weapon", true, "", klass)
		TestBase.tree.root.add_child(g)
		check(g.weapon_class == klass, "%s glyph keeps its class" % klass)
		g.queue_free()
	var empty := SlotGlyph.new(40).setup("weapon", false, "", "beam")
	check(not empty.filled, "an empty slot draws as an outline")
	empty.free()


func test_shot_notes_explain_special_weapons() -> void:
	check(UiModel.shot_notes({"result": "hit"}) == "", "an ordinary shot has no note")
	check(UiModel.shot_notes({"result": "hit", "burst": 3}) == "burst x3", "a burst says x3")
	check(UiModel.shot_notes({"result": "hit", "area": true}).begins_with("blast"), "an area shot says it blasts")
	check(CombatReasons.text("too_close") == "Too close for that weapon.", "too close has its own wording")


func test_a_miss_into_cover_sounds_like_cover_not_open_air() -> void:
	var open_miss := {"type": "shot", "tick": 4, "unit": 1, "target": 2, "result": "miss", "class": "rifle"}
	var cover_miss := {"type": "shot", "tick": 4, "unit": 1, "target": 2, "result": "miss", "class": "rifle", "cover": true}
	check(names_of(SoundMap.for_event(open_miss)).has("sfx_miss") and not names_of(SoundMap.for_event(open_miss)).has("sfx_blocked"), "an open miss whistles past")
	check(names_of(SoundMap.for_event(cover_miss)).has("sfx_blocked") and not names_of(SoundMap.for_event(cover_miss)).has("sfx_miss"), "a miss into cover hits the cover")
