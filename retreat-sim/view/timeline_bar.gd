class_name TimelineBar
extends Control
## The round as a strip of ticks. Shows how far the run has got, what the
## selected merc is already committed to, and when each queued action will
## complete. Faint marks every SCALE_TICKS are a scale only; the run never stops on them.

const COLORS := {
	"move": Color("8fd0ff"),
	"shoot": Color("ff6b5a"),
	"move_fire": Color("ff9f43"),
	"overwatch": Color("7fd6d0"),
	"wait": Color("8a93a0"),
}
const COL_BG := Color("1a1e25")
const COL_PAST := Color(0, 0, 0, 0.45)
const COL_COMMITTED := Color("5b6573")
const COL_NOW := Color("ffd479")
const HEIGHT := 30.0
const LABEL_SIZE := 11
const SCALE_TICKS := 5

var _segments: Array = []
var _tick := 0
var _total := SimConst.TICKS_PER_TURN
var _committed_until := 0


func _init() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)


## `segments`: [{kind, start, end}] in absolute round ticks.
func set_data(segments: Array, tick: int, total: int, committed_until: int) -> void:
	_segments = segments
	_tick = tick
	_total = maxi(total, 1)
	_committed_until = committed_until
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var cell := w / _total
	draw_rect(Rect2(0, 0, w, size.y), COL_BG)
	if _committed_until > _tick:
		draw_rect(Rect2(_tick * cell, 4, (_committed_until - _tick) * cell, size.y - 8), COL_COMMITTED)
	for s: Dictionary in _segments:
		var col: Color = COLORS.get(s["kind"], COLORS["wait"])
		draw_rect(Rect2(int(s["start"]) * cell + 1, 4, (int(s["end"]) - int(s["start"])) * cell - 2, size.y - 8), col)
	draw_rect(Rect2(0, 0, _tick * cell, size.y), COL_PAST)
	var font := ThemeDB.fallback_font
	for t in range(SCALE_TICKS, _total, SCALE_TICKS):
		draw_line(Vector2(t * cell, size.y - 6), Vector2(t * cell, size.y), Color(1, 1, 1, 0.3), 1.0)
		draw_string(font, Vector2(t * cell + 3, LABEL_SIZE), str(t), HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, Color(1, 1, 1, 0.4))
	draw_line(Vector2(_tick * cell, 0), Vector2(_tick * cell, size.y), COL_NOW, 2.5)
