extends TestBase
## The first-mission coach: one short tip at a time, chosen from what the player has already done.

func facts(over := {}) -> Dictionary:
	var f := {"moved": false, "enemy_in_sight": false, "previewed_shot": false, "shot": false, "ended": false, "watched": false, "over": false}
	f.merge(over, true)
	return f


func test_the_first_tip_teaches_the_two_tap_move() -> void:
	var tip := CoachModel.tip(facts())
	check(tip.contains("twice") or tip.contains("again"), "the opening tip explains tap to preview, tap again to go (%s)" % tip)


func test_an_enemy_in_sight_asks_for_a_shot_before_anything_else() -> void:
	var tip := CoachModel.tip(facts({"moved": true, "enemy_in_sight": true}))
	check(tip.to_lower().contains("hit chance"), "a visible enemy prompts the shot preview (%s)" % tip)
	var first := CoachModel.tip(facts({"enemy_in_sight": true}))
	check(first.to_lower().contains("hit chance"), "even before the first move, a visible enemy comes first (%s)" % first)


func test_a_previewed_shot_asks_for_the_confirming_tap() -> void:
	var tip := CoachModel.tip(facts({"moved": true, "enemy_in_sight": true, "previewed_shot": true}))
	check(tip.to_lower().contains("fire"), "the second tap fires (%s)" % tip)


func test_after_the_first_shot_the_ap_and_end_activation_tip_comes() -> void:
	var tip := CoachModel.tip(facts({"moved": true, "enemy_in_sight": true, "shot": true}))
	check(tip.contains("End Activation"), "the tip names End Activation (%s)" % tip)


func test_after_ending_the_overwatch_tip_comes_once() -> void:
	var tip := CoachModel.tip(facts({"moved": true, "shot": true, "ended": true}))
	check(tip.contains("Overwatch"), "the overwatch tip follows the first End Activation (%s)" % tip)
	var done := CoachModel.tip(facts({"moved": true, "shot": true, "ended": true, "watched": true}))
	check(done == "", "once overwatch has been used the coach is finished (%s)" % done)


func test_the_coach_is_silent_when_the_fight_is_over() -> void:
	check(CoachModel.tip(facts({"over": true})) == "", "no tip after the fight")


func test_the_coach_runs_only_in_the_first_fresh_mission() -> void:
	var story: Dictionary = StoryData.load_dir("res://data/story")["data"]
	var fresh := Campaign.new_game(story)
	check(CoachModel.applies(fresh, fresh.story["route"]["start"], false), "a fresh campaign's first mission is coached")
	check(not CoachModel.applies(fresh, "the_weir", false), "a later mission is not")
	check(not CoachModel.applies(fresh, fresh.story["route"]["start"], true), "a level test is not")
	check(not CoachModel.applies(null, "karsa_breakout", false), "no campaign, no coach")
	fresh.completed.append("karsa_breakout")
	check(not CoachModel.applies(fresh, "karsa_breakout", false), "a replay of the first mission after it was completed is not")
