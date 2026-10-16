class_name StoryData
extends RefCounted
## Loads the story files (cast, writ, route, world, scenes, enemy_tiers, items, classes) from a directory.

const FILES: Array[String] = ["cast", "writ", "route", "world", "scenes", "enemy_tiers", "items", "classes", "progression", "map"]


## Returns {"data": {cast, writ, route, world, scenes, enemy_tiers, items, classes}, "errors": Array[String]}.
## A file that cannot be read or parsed is reported, never thrown.
static func load_dir(dir: String) -> Dictionary:
	var data := {}
	var errors: Array[String] = []
	for name in FILES:
		var path := "%s/%s.json" % [dir, name]
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			errors.append("cannot open %s" % path)
			data[name] = {}
			continue
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if typeof(parsed) != TYPE_DICTIONARY:
			errors.append("%s is not a JSON object" % path)
			data[name] = {}
			continue
		data[name] = parsed
	return {"data": data, "errors": errors}
