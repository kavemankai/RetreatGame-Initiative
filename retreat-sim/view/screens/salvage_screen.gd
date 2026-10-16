class_name SalvageScreen
extends VBoxContainer
## What the squad brought back: an ItemCard for each find, then "Equip now" (the host opens the loadout) or
## "To stash". The items are already in the stash; this screen only shows them and asks where to go next.

signal done
signal equip_now

var _ids: Array[String] = []


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)


func setup(c: Campaign, loot: Array) -> SalvageScreen:
	add_child(UiTheme.label("Salvage", 26))
	var note := UiTheme.label("The squad brought these back. They are in the stash.", UiTheme.FONT_SMALL, UiTheme.COL_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	var list := ScrollList.new()
	add_child(list)
	for id in loot:
		_ids.append(String(id))
		list.add_card(ItemCard.new().setup(UiModel.item_info(c, String(id))))
	add_child(_button("Equip now", equip_now.emit))
	add_child(_button("To stash", done.emit))
	return self


func item_ids() -> Array[String]:
	return _ids.duplicate()


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, UiTheme.MIN_TAP)
	b.pressed.connect(action)
	return b
