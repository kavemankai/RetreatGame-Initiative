class_name SlotGlyph
extends Control
## A small drawn symbol for a gear slot (armour: shield, weapon: rifle, mod: diamond), amber when
## something is worn and a dim outline when the slot is empty. If a texture exists at the item's
## icon path it is drawn instead, so art can be dropped in later without touching any screen.

var kind := "armour"
var filled := false
var icon_path := ""
var weapon_class := ""  ## for a weapon glyph: rifle, carbine, sniper, shotgun, heavy, grenade or beam
var _texture: Texture2D


func _init(p_px: int = 28) -> void:
	custom_minimum_size = Vector2(p_px, p_px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(p_kind: String, p_filled: bool, p_icon_path: String = "", p_class: String = "") -> SlotGlyph:
	kind = p_kind
	filled = p_filled
	icon_path = p_icon_path
	weapon_class = p_class
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
			_draw_weapon(w, h, pad, col)
		_:
			var pts := PackedVector2Array([Vector2(w * 0.5, pad), Vector2(w - pad, h * 0.5), Vector2(w * 0.5, h - pad), Vector2(pad, h * 0.5)])
			_shape(pts, col)


## Seven silhouettes, readable at 28 px: they differ in barrel length, bulk and a feature.
func _draw_weapon(w: float, h: float, pad: float, col: Color) -> void:
	var barrel_len := w - 2.0 * pad
	var barrel_h := h * 0.16
	var barrel_y := h * 0.38
	match weapon_class:
		"carbine":
			barrel_len = w * 0.6
		"sniper":
			barrel_h = h * 0.10
			barrel_y = h * 0.42
		"shotgun":
			barrel_len = w * 0.72
			barrel_h = h * 0.26
		"heavy":
			barrel_h = h * 0.24
			barrel_y = h * 0.34
		"grenade":
			barrel_len = w * 0.62
			barrel_h = h * 0.32
			barrel_y = h * 0.32
	var barrel := Rect2(pad, barrel_y, barrel_len, barrel_h)
	_rect(barrel, col)
	var stock := PackedVector2Array([Vector2(pad, barrel_y + barrel_h), Vector2(w * 0.38, barrel_y + barrel_h), Vector2(w * 0.3, h - pad), Vector2(pad, h - pad)])
	_shape(stock, col)
	match weapon_class:
		"sniper":
			_rect(Rect2(w * 0.38, barrel_y - h * 0.14, w * 0.2, h * 0.1), col)  # scope
		"heavy":
			_rect(Rect2(w * 0.42, barrel_y + barrel_h, w * 0.14, h * 0.26), col)  # box magazine
		"grenade":
			draw_circle(Vector2(w * 0.5, barrel_y + barrel_h + h * 0.12), h * 0.14, col)  # drum
		"beam":
			for i in 3:  # glow at the muzzle
				draw_circle(Vector2(pad + barrel_len + 1.0 + float(i) * h * 0.1, barrel_y + barrel_h * 0.5), h * 0.045, col)


func _rect(r: Rect2, col: Color) -> void:
	if filled:
		draw_rect(r, col)
	else:
		draw_rect(r, col, false, 2.0)


func _shape(pts: PackedVector2Array, col: Color) -> void:
	if filled:
		draw_colored_polygon(pts, col)
	else:
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, col, 2.0)
