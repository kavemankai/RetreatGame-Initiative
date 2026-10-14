class_name SlotGlyph
extends Control
## A small drawn symbol for a gear slot (armour: shield, weapon: rifle, mod: diamond), amber when
## something is worn and a dim outline when the slot is empty. If a texture exists at the item's
## icon path it is drawn instead, so art can be dropped in later without touching any screen.

var kind := "armour"
var filled := false
var icon_path := ""
var _texture: Texture2D


func _init(p_px: int = 28) -> void:
	custom_minimum_size = Vector2(p_px, p_px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(p_kind: String, p_filled: bool, p_icon_path: String = "") -> SlotGlyph:
	kind = p_kind
	filled = p_filled
	icon_path = p_icon_path
	_texture = load(icon_path) as Texture2D if icon_path != "" and ResourceLoader.exists(icon_path) else null
	queue_redraw()
	return self


func _draw() -> void:
	var col := UiTheme.COL_AMBER if filled else UiTheme.COL_MUTED
	var w := size.x if size.x > 0.0 else custom_minimum_size.x
	var h := size.y if size.y > 0.0 else custom_minimum_size.y
	if _texture != null:
		draw_texture_rect(_texture, Rect2(Vector2.ZERO, Vector2(w, h)), false)
		return
	var pad := w * 0.14
	match kind:
		"armour":
			var pts := PackedVector2Array([Vector2(pad, pad), Vector2(w - pad, pad), Vector2(w - pad, h * 0.55), Vector2(w * 0.5, h - pad), Vector2(pad, h * 0.55)])
			_shape(pts, col)
		"weapon":
			var barrel := Rect2(pad, h * 0.38, w - 2.0 * pad, h * 0.16)
			var stock := PackedVector2Array([Vector2(pad, h * 0.54), Vector2(w * 0.38, h * 0.54), Vector2(w * 0.3, h - pad), Vector2(pad, h - pad)])
			if filled:
				draw_rect(barrel, col)
			else:
				draw_rect(barrel, col, false, 2.0)
			_shape(stock, col)
		_:
			var pts := PackedVector2Array([Vector2(w * 0.5, pad), Vector2(w - pad, h * 0.5), Vector2(w * 0.5, h - pad), Vector2(pad, h * 0.5)])
			_shape(pts, col)


func _shape(pts: PackedVector2Array, col: Color) -> void:
	if filled:
		draw_colored_polygon(pts, col)
	else:
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, col, 2.0)
