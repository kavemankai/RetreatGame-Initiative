class_name StatRow
extends HBoxContainer
## One stat: a label, pips against its cap, the value, and (when it differs) a coloured change.

const LABEL_W := 56


func _init() -> void:
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## `delta` is the change a piece of gear (or a level) makes; 0 hides it. `better` colours it.
func setup(p_label: String, p_value: int, p_cap: int, p_delta: int = 0, p_better: bool = true) -> StatRow:
	var name_label := UiTheme.label(p_label, UiTheme.FONT_BODY, UiTheme.COL_MUTED)
	name_label.custom_minimum_size = Vector2(LABEL_W, 0)
	add_child(name_label)
	add_child(StatPips.new().setup(p_value, p_cap))
	add_child(UiTheme.label(str(p_value), UiTheme.FONT_BODY))
	if p_delta != 0:
		add_child(UiTheme.label(UiTheme.delta_text(p_delta), UiTheme.FONT_BODY, UiTheme.delta_color(p_better)))
	return self
