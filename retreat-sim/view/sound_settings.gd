class_name SoundSettings
extends RefCounted
## Volume levels (0..1) per bus and a mute switch, kept in user://sound.json.

const DEFAULT_PATH := "user://sound.json"
const SILENT_DB := -80.0
## Ambient and music sit under the effects so a shot always cuts through.
const BUS_TRIM_DB := {"master": 0.0, "sfx": 0.0, "ambient": -14.0, "music": -10.0, "ui": -2.0}

var master := 1.0
var sfx := 0.8
var ambient := 0.6
var music := 0.5
var ui := 0.8
var muted := false


static func to_db(linear: float) -> float:
	return SILENT_DB if linear <= 0.001 else maxf(SILENT_DB, linear_to_db(linear))


func normalise() -> void:
	master = clampf(master, 0.0, 1.0)
	sfx = clampf(sfx, 0.0, 1.0)
	ambient = clampf(ambient, 0.0, 1.0)
	music = clampf(music, 0.0, 1.0)
	ui = clampf(ui, 0.0, 1.0)


## Decibels for one bus ("master", "sfx", "ambient", "music", "ui").
func bus_db(bus: String) -> float:
	if muted:
		return SILENT_DB
	var level: float = get(bus)
	return maxf(SILENT_DB, to_db(level) + float(BUS_TRIM_DB.get(bus, 0.0)))


func save(path: String = DEFAULT_PATH) -> bool:
	normalise()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"master": master, "sfx": sfx, "ambient": ambient, "music": music, "ui": ui, "muted": muted}))
	return true


static func load_from(path: String = DEFAULT_PATH) -> SoundSettings:
	var s := SoundSettings.new()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return s
	var d: Variant = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return s
	for key in ["master", "sfx", "ambient", "music", "ui"]:
		if d.has(key) and (typeof(d[key]) == TYPE_FLOAT or typeof(d[key]) == TYPE_INT):
			s.set(key, float(d[key]))
	s.muted = bool(d.get("muted", false))
	s.normalise()
	return s
