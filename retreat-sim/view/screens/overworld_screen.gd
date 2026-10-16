class_name OverworldScreen
extends VBoxContainer
## The hub between missions: the route drawn as a map (MapCanvas) in a scroll, a header with the standing
## resources, and a bottom sheet for the stop or card you tap. Brief is offered only at the stop the convoy
## is at. It changes nothing: it asks the host to open the briefing, roster, loadout, stash or menu.

signal brief
signal open_roster
signal open_loadout
signal open_stash
signal open_menu
signal back

var _c: Campaign
var _canvas: MapCanvas
var _scroll: ScrollContainer
var _sheet := VBoxContainer.new()
var _sheet_panel := PanelContainer.new()


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)


func setup(c: Campaign) -> OverworldScreen:
	_c = c
	add_child(UiTheme.label("The route", 26))
	add_child(ResourceBar.new().setup(UiModel.resources_info(c)))
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_scroll)
	var map: Dictionary = c.story["map"]
	_canvas = MapCanvas.new().setup(map, c.route_state(), 700.0 * float(map.get("height_screens", 3)))
	_canvas.tapped.connect(select)
	_scroll.add_child(_canvas)
	_sheet_panel.add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.COL_PANEL, UiTheme.COL_AMBER, 1))
	_sheet_panel.visible = false
	_sheet_panel.add_child(_sheet)
	_sheet.add_theme_constant_override("separation", 6)
	add_child(_sheet_panel)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	add_child(nav)
	for entry: Array in [["Roster", open_roster], ["Loadout", open_loadout], ["Stash", open_stash], ["Menu", open_menu]]:
		nav.add_child(_button(entry[0], entry[1].emit, true))
	if _c.current != "" and not _c.finished and not _c.over:
		select({"kind": "node", "id": _c.current})
	_scroll_to_current.call_deferred()
	return self


## Opens the sheet for a stop or card (what a tap on the map does).
func select(hit: Dictionary) -> void:
	_canvas.select(String(hit["id"]))
	for child in _sheet.get_children():
		_sheet.remove_child(child)
		child.queue_free()
	var info := UiModel.map_sheet(_c, hit)
	_sheet.add_child(UiTheme.label(String(info["title"]), UiTheme.FONT_TITLE, UiTheme.COL_AMBER))
	for line: String in info["lines"]:
		if line != "":
			var l := UiTheme.label(line, UiTheme.FONT_SMALL)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_sheet.add_child(l)
	if info["action"] == "brief":
		var b := _button("Brief", brief.emit, false)
		b.name = "brief_button"
		_sheet.add_child(b)
	_sheet_panel.visible = true


func canvas() -> MapCanvas:
	return _canvas


func _scroll_to_current() -> void:
	if _canvas != null and _scroll != null:
		_scroll.scroll_vertical = int(maxf(0.0, _canvas.current_y() - _scroll.size.y * 0.6))


func _button(text: String, action: Callable, expand: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, UiTheme.MIN_TAP)
	if expand:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(action)
	return b
