class_name StatPips
extends Control
## A row of small squares: `value` of `maximum` filled. Used by StatRow.

const PIP := 7.0
const GAP := 2.0

var value := 0
var maximum := 10
var tint := UiTheme.COL_AMBER


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(p_value: int, p_maximum: int, p_tint: Color = UiTheme.COL_AMBER) -> StatPips:
	value = p_value
	maximum = maxi(1, p_maximum)
	tint = p_tint
	custom_minimum_size = Vector2(maximum * (PIP + GAP), PIP + 4.0)
	queue_redraw()
	return self


func _draw() -> void:
	for i in maximum:
		var r := Rect2(i * (PIP + GAP), 2.0, PIP, PIP)
		if i < value:
			draw_rect(r, tint)
		else:
			draw_rect(r, UiTheme.COL_MUTED, false, 1.0)
