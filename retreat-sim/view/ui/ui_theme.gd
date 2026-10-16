class_name UiTheme
extends RefCounted
## Colours, sizes and small builders shared by the campaign screens. The palette is the one in
## ART_DIRECTION.md (cold floor greys, amber as the rare warm colour, teal for the Hegemony).

const MIN_TAP := 56  ## the smallest height of anything you tap, in px on the 540x960 reference
const MARGIN := 14
const COL_DEEP := Color("1f2227")
const COL_PANEL := Color("2b2e35")
const COL_PANEL_HI := Color("353943")
const COL_AMBER := Color("d99a3d")
const COL_TEAL := Color("3fa7a0")
const COL_TEXT := Color("d8dee9")
const COL_MUTED := Color("8a93a0")
const COL_GOOD := Color("9be39b")
const COL_BAD := Color("ff9a8a")
const COL_HOLLOW := Color("6f7885")
const FONT_SMALL := 13
const FONT_BODY := 16
const FONT_TITLE := 22


## A rounded panel background. `border_w` 0 means no border.
static func panel(bg: Color = COL_PANEL, border: Color = Color.TRANSPARENT, border_w: int = 0, radius: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


static func label(text: String, font_size: int = FONT_BODY, color: Color = COL_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


## A small rounded tag ("HOLLOW", "Lv 2", "scope").
static func chip(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var s := panel(Color(color.r, color.g, color.b, 0.22), color, 1, 10)
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	s.content_margin_left = 8
	s.content_margin_right = 8
	p.add_theme_stylebox_override("panel", s)
	p.add_child(label(text, FONT_SMALL, color))
	return p


static func delta_text(d: int) -> String:
	return "0" if d == 0 else "%+d" % d


static func delta_color(better: bool) -> Color:
	return COL_GOOD if better else COL_BAD


## Lets taps and drags through a card's inner controls to the card itself (and on to a scroll list).
static func ignore_mouse_inside(root: Node) -> void:
	for child in root.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		ignore_mouse_inside(child)
