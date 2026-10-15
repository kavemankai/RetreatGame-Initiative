class_name MercCard
extends TapPanel
## A tappable merc summary: sprite, callsign, status and level tags, the six stats (green where gear
## lifts them, red where it lowers them), one glyph per gear slot, and an optional XP bar.
## Data comes from UiModel.merc_info (plus optional "level", "xp", "xp_next" once levelling exists).

const SPRITE_PX := 64
const SPRITE_DIR := "res://assets/mercs/"

var _sprite := TextureRect.new()
var _name := UiTheme.label("", UiTheme.FONT_TITLE)
var _chips := HFlowContainer.new()
var _stats := GridContainer.new()
var _glyphs := HBoxContainer.new()
var _xp := ProgressBar.new()


func _init() -> void:
	super._init()
	custom_minimum_size = Vector2(0, 96)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	_sprite.custom_minimum_size = Vector2(SPRITE_PX, SPRITE_PX)
	_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(_sprite)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # never clipped to nothing
	head.add_child(_name)
	_chips.add_theme_constant_override("h_separation", 4)
	head.add_child(_chips)
	col.add_child(head)
	_stats.columns = 3
	_stats.add_theme_constant_override("h_separation", 10)
	_stats.add_theme_constant_override("v_separation", 0)
	col.add_child(_stats)
	_glyphs.add_theme_constant_override("separation", 6)
	col.add_child(_glyphs)
	_xp.custom_minimum_size = Vector2(0, 8)
	_xp.show_percentage = false
	_xp.visible = false
	col.add_child(_xp)
	UiTheme.ignore_mouse_inside(self)


func setup(info: Dictionary) -> MercCard:
	var hollow: bool = info["status"] == "hollow"
	_name.text = String(info["name"])
	_name.add_theme_color_override("font_color", UiTheme.COL_HOLLOW if hollow else UiTheme.COL_TEXT)
	for child in _chips.get_children():
		_chips.remove_child(child)
		child.queue_free()
	if info.has("class_name"):
		_chips.add_child(UiTheme.chip(String(info["class_name"]), UiTheme.COL_AMBER))
	if info["status"] != "named":
		_chips.add_child(UiTheme.chip(String(info["status"]).to_upper(), UiTheme.COL_HOLLOW))
	if info.has("level"):
		_chips.add_child(UiTheme.chip("Lv %d" % int(info["level"]), UiTheme.COL_AMBER))
	var trait_name: String = String(info["stats"].get("trait", ""))
	if trait_name != "":
		_chips.add_child(UiTheme.chip(trait_name, UiTheme.COL_TEAL))
	for child in _stats.get_children():
		_stats.remove_child(child)
		child.queue_free()
	for key in UiModel.STAT_ORDER:
		var now := int(info["stats"][key])
		var base := int(info["base"][key])
		var color := UiTheme.COL_TEXT if now == base else UiTheme.delta_color(now > base)
		_stats.add_child(UiTheme.label("%s %d" % [UiModel.STAT_LABEL[key], now], 14, color))
	for child in _glyphs.get_children():
		_glyphs.remove_child(child)
		child.queue_free()
	for kind in Campaign.GEAR_SLOTS:
		var id := String(info["gear"].get(kind, ""))
		var glyph := SlotGlyph.new().setup(kind, id != "", ArtSkin.icon_path(id) if id != "" else "", String(info.get("class", "")) if kind == "weapon" else "")
		glyph.tooltip_text = String(info["gear_names"].get(kind, "empty"))
		_glyphs.add_child(glyph)
	_xp.visible = info.has("xp") and info.has("xp_next")
	if _xp.visible:
		_xp.max_value = maxf(1.0, float(info["xp_next"]))
		_xp.value = float(info["xp"])
	var path := ArtSkin.merc_dir() + String(info["sprite_key"]) + "_idle0.png"
	_sprite.texture = load(path) as Texture2D if ResourceLoader.exists(path) else null
	add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.COL_PANEL_HI if bool(info.get("selected", false)) else UiTheme.COL_PANEL, UiTheme.COL_AMBER if bool(info.get("selected", false)) else Color.TRANSPARENT, 2))
	UiTheme.ignore_mouse_inside(self)
	return self
