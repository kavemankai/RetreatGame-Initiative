class_name ThemeArt
extends RefCounted
## Floor, wall and prop textures for a level theme, from res://assets/themes/<theme>/.
## Any texture a theme lacks falls back to the station deck's.

const DIR := "res://assets/themes/"
const DEFAULT := "station_deck"
const FLOOR_COUNT := 9
const PROP_COUNT := 4
const WALL_KINDS: Array[String] = ["full", "half"]

static var _cache: Dictionary = {}  # "<theme>/<file>" -> Texture2D (or null if missing)


static func _tex(theme: String, file: String) -> Texture2D:
	var ja2 := ArtSkin.ja2_theme_file(file)
	if ja2 != "":
		var jkey := "ja2/" + file
		if not _cache.has(jkey):
			_cache[jkey] = load(ja2)
		return _cache[jkey]
	var key := "%s/%s" % [theme, file]
	if not _cache.has(key):
		var path := "%s%s/%s" % [DIR, theme, file]
		_cache[key] = load(path) if ResourceLoader.exists(path) else null
	return _cache[key]


static func _tex_or_default(theme: String, file: String) -> Texture2D:
	var t := _tex(theme, file)
	return t if t != null else _tex(DEFAULT, file)


static func floors(theme: String) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for i in FLOOR_COUNT:
		var t := _tex_or_default(theme, "floor_%d.png" % i)
		if t != null:
			out.append(t)
	return out


static func props(theme: String) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for i in PROP_COUNT:
		var t := _tex_or_default(theme, "crate_%d.png" % i)
		if t != null:
			out.append(t)
	return out


## The wall sprite for edge axis `z` (0 or 1) and kind (SimConst.EDGE_FULL / EDGE_HALF).
static func wall(theme: String, z: int, kind: int) -> Texture2D:
	return _tex_or_default(theme, "wall_z%d_%s.png" % [z, "full" if kind == SimConst.EDGE_FULL else "half"])


## Every file a complete theme provides (tests check each exists).
static func required_files() -> Array[String]:
	var out: Array[String] = []
	for i in FLOOR_COUNT:
		out.append("floor_%d.png" % i)
	for i in PROP_COUNT:
		out.append("crate_%d.png" % i)
	for z in 2:
		for k in WALL_KINDS:
			out.append("wall_z%d_%s.png" % [z, k])
	return out
