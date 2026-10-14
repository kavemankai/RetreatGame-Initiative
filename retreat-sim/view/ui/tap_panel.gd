class_name TapPanel
extends PanelContainer
## A panel you can tap. It emits `pressed` only for a clean tap: the press and the release must be
## within TAP_SLOP of each other and the pointer must not have wandered away in between, so
## scrolling a list past a card never selects it. Events pass through (MOUSE_FILTER_PASS) so a
## ScrollContainer around it still scrolls.

signal pressed

const TAP_SLOP := 12.0

var _down := Vector2.ZERO
var _armed := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_down = button.position
			_armed = true
			modulate = Color(1, 1, 1, 0.85)
		else:
			modulate = Color.WHITE
			if _armed and button.position.distance_to(_down) <= TAP_SLOP:
				pressed.emit()
			_armed = false
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _armed and motion.position.distance_to(_down) > TAP_SLOP:
		_armed = false
		modulate = Color.WHITE
