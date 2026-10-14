extends SceneTree
## Headless test runner. Discovers every test_* method in each suite.
##   godot --headless --path . --import      # first time only
##   godot --headless --path . -s tests/run_tests.gd

const SUITES: Array[Script] = [
	preload("res://tests/test_sim.gd"),
	preload("res://tests/test_replay.gd"),
	preload("res://tests/test_vision.gd"),
	preload("res://tests/test_ai.gd"),
	preload("res://tests/test_regressions.gd"),
	preload("res://tests/test_game.gd"),
	preload("res://tests/test_turn.gd"),
	preload("res://tests/test_live.gd"),
	preload("res://tests/test_story.gd"),
	preload("res://tests/test_campaign.gd"),
	preload("res://tests/test_missions.gd"),
	preload("res://tests/test_iso.gd"),
	preload("res://tests/test_combat.gd"),
	preload("res://tests/test_hit.gd"),
	preload("res://tests/test_tiers.gd"),
	preload("res://tests/test_equipment.gd"),
	preload("res://tests/test_maps.gd"),
	preload("res://tests/test_levels.gd"),
	preload("res://tests/test_initiative.gd"),
	preload("res://tests/test_sandbox.gd"),
	preload("res://tests/test_activation.gd"),
	preload("res://tests/test_activation_match.gd"),
	preload("res://tests/test_reactions.gd"),
	preload("res://tests/test_ai_scenarios.gd"),
	preload("res://tests/test_sound.gd"),
	preload("res://tests/test_review_fixes.gd"),
]


func _init() -> void:
	TestBase.tree = self
	var total := 0
	for script in SUITES:
		print("== ", script.resource_path.get_file())
		var names: Array[String] = []
		for m in script.get_script_method_list():
			if String(m["name"]).begins_with("test_"):
				names.append(m["name"])
		names.sort()
		for n in names:
			print("- ", n)
			var suite: TestBase = script.new()
			var before := TestBase.checks
			suite.call(n)
			total += 1
			# A test that crashed on a script error before its first check would
			# otherwise pass silently.
			if TestBase.checks == before:
				TestBase.fails += 1
				printerr("  FAIL: %s recorded no checks (did it crash?)" % n)
	print("\n%d tests, %d checks, %d failed" % [total, TestBase.checks, TestBase.fails])
	quit(1 if TestBase.fails > 0 else 0)
