class_name ArtSkin
extends RefCounted
## Which art set the game draws with. "Original" is assets/; "JA2 placeholders" is the locally built
## set in assets/ja2/ (tools/ja2_skin.py), used for testing and private play and never committed.
## The choice is kept in user://skin.json. Without the JA2 files the original art is always used.

const SETTINGS_PATH := "user://skin.json"
const JA2_MERC_DIR := "res://assets/ja2/mercs/"
const ORIGINAL_MERC_DIR := "res://assets/mercs/"
const PROBE := "res://assets/ja2/mercs/warden_idle0.png"

static var _ja2_wanted := true
static var _loaded := false


static func ja2_available() -> bool:
	return ResourceLoader.exists(PROBE)


## Tests set this to false so they check the original art whatever is installed locally (-1 = no override).
static var forced := -1


static func ja2_active() -> bool:
	if forced >= 0:
		return forced == 1 and ja2_available()
	_load_once()
	return _ja2_wanted and ja2_available()


static func set_ja2(on: bool) -> void:
	_load_once()
	_ja2_wanted = on
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"ja2": on}))


static func merc_dir() -> String:
	return JA2_MERC_DIR if ja2_active() else ORIGINAL_MERC_DIR


## The icon for an item id: the JA2 set when active and present, else the original path (which may not exist).
static func icon_path(item_id: String) -> String:
	var ja2 := "res://assets/ja2/items/%s.png" % item_id
	if ja2_active() and ResourceLoader.exists(ja2):
		return ja2
	return "res://assets/items/%s.png" % item_id


## The JA2 theme's copy of a theme file (floor_0.png, wall_z0_full.png, ...), or "" when the skin is off or lacks it.
## Every level theme draws with the one JA2 set while the skin is on.
static func ja2_theme_file(file: String) -> String:
	if not ja2_active():
		return ""
	var path := "res://assets/ja2/themes/ja2_snow/" + file
	return path if ResourceLoader.exists(path) else ""


const VOICE_VARIANTS := 4  # clips per voice kind in assets/ja2/audio (tools/ja2_skin.py sounds)


## The path of a JA2 voice clip ("voice_hit_2"), or "" when the skin is off or the clip is missing.
static func voice_path(name: String) -> String:
	if not ja2_active():
		return ""
	var path := "res://assets/ja2/audio/%s.wav" % name
	return path if ResourceLoader.exists(path) else ""


## A JA2 portrait for a named merc's sprite key, or "" (hollows and enemies have none).
static func face_path(sprite_key: String) -> String:
	if not ja2_active():
		return ""
	var path := "res://assets/ja2/faces/%s.png" % sprite_key
	return path if ResourceLoader.exists(path) else ""


static func label() -> String:
	return "Art: JA2 placeholders" if ja2_active() else "Art: original"


static func _load_once() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if typeof(d) == TYPE_DICTIONARY:
		_ja2_wanted = bool(d.get("ja2", true))
