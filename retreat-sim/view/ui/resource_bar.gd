class_name ResourceBar
extends HFlowContainer
## The campaign's standing resources as tags that wrap on a narrow screen: Procession, Reserves,
## Remembrance and the Writ's stage. Data comes from UiModel.resources_info.


func _init() -> void:
	add_theme_constant_override("h_separation", 6)
	add_theme_constant_override("v_separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(info: Dictionary) -> ResourceBar:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	add_child(UiTheme.chip("Procession %d" % int(info["procession"]), UiTheme.COL_TEAL))
	add_child(UiTheme.chip("Reserves %d" % int(info["reserves"]), UiTheme.COL_AMBER))
	add_child(UiTheme.chip("Remembrance %d" % int(info["remembrance"]), UiTheme.COL_MUTED))
	if int(info.get("writ", 0)) > 0:
		add_child(UiTheme.chip("Writ %d/6" % int(info["writ"]), UiTheme.COL_BAD))
	return self
