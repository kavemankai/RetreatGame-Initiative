class_name ItemCard
extends TapPanel
## A tappable item: slot glyph (or icon), name, stash count, tier pips, its effect line, and (when a
## merc is being compared) the stat changes it would cause, green when better and red when worse.
## Data comes from UiModel.item_info.

var _glyph := SlotGlyph.new(40)
var _name := UiTheme.label("", UiTheme.FONT_BODY)
var _count := UiTheme.label("", UiTheme.FONT_BODY, UiTheme.COL_MUTED)
var _tier := UiTheme.label("", UiTheme.FONT_SMALL, UiTheme.COL_AMBER)
var _summary := UiTheme.label("", UiTheme.FONT_SMALL, UiTheme.COL_MUTED)
var _deltas := HFlowContainer.new()


func _init() -> void:
	super._init()
	custom_minimum_size = Vector2(0, 72)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	row.add_child(_glyph)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.clip_text = true
	head.add_child(_name)
	head.add_child(_count)
	head.add_child(_tier)
	col.add_child(head)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_summary)
	_deltas.add_theme_constant_override("h_separation", 8)
	col.add_child(_deltas)
	UiTheme.ignore_mouse_inside(self)


func setup(info: Dictionary) -> ItemCard:
	_glyph.setup(String(info["slot"]), true, String(info.get("icon_path", "")))
	_name.text = String(info["name"])
	_count.text = "x%d" % int(info["count"]) if int(info["count"]) > 1 else ""
	_tier.text = "I".repeat(clampi(int(info["tier"]), 1, 3))
	_summary.text = String(info["summary"])
	for child in _deltas.get_children():
		_deltas.remove_child(child)
		child.queue_free()
	for d: Dictionary in info["deltas"]:
		_deltas.add_child(UiTheme.label(UiModel.delta_line(d), UiTheme.FONT_SMALL, UiTheme.delta_color(bool(d["better"]))))
	var selected := bool(info.get("selected", false))
	add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.COL_PANEL_HI if selected else UiTheme.COL_PANEL, UiTheme.COL_AMBER if selected else Color.TRANSPARENT, 2))
	UiTheme.ignore_mouse_inside(self)
	return self
