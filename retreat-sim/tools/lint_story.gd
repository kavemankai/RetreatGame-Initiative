extends SceneTree
## Lint the story data. Exit code 1 if anything is wrong.
##   godot --headless --path . -s tools/lint_story.gd
##   godot --headless --path . -s tools/lint_story.gd -- --dir=res://data/story


func _init() -> void:
	var dir := "res://data/story"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			dir = a.substr(6)
	var loaded := StoryData.load_dir(dir)
	var errors: Array[String] = []
	errors.append_array(loaded["errors"])
	if errors.is_empty():
		errors.append_array(StoryLint.lint(loaded["data"]))
	if errors.is_empty():
		print("story lint: clean (%s)" % dir)
	for e in errors:
		printerr("story lint: ", e)
	quit(1 if not errors.is_empty() else 0)
