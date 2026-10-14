class_name ScrollList
extends ScrollContainer
## A vertical list that drags to scroll on a phone and never scrolls sideways. Put cards in with
## add_card; it fills the space its parent gives it.

var _box := VBoxContainer.new()


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 8)
	add_child(_box)


func add_card(card: Control) -> void:
	_box.add_child(card)


func card_count() -> int:
	return _box.get_child_count()


func clear_cards() -> void:
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
