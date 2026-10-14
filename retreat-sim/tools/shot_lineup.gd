extends SceneTree
## Renders one unit of every sprite set on the board, for checking the art in place.
##   godot --path . -s tools/shot_lineup.gd -- out.png
func _init() -> void:
	var out := "lineup.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var vp := SubViewport.new()
	vp.size = Vector2i(1080, 640)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var board := BoardView.new()
	board.size = Vector2(1080, 640)
	vp.add_child(board)
	var s := SimState.new(SimGrid.new(12, 12))
	s.fixed_roll = 1
	var ids: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 200, 210, 220, 300, 101, 102, 103, 104, 105, 106, 100]
	for i in ids.size():
		var team := 0 if ids[i] <= 12 else 1
		var u := SimUnit.make(ids[i], team, Vector2i(1 + (i % 6) * 2, 1 + (i / 6) * 2 + (i % 2)), 3, 5)
		s.add_unit(u)
	var none: Array[Dictionary] = []
	board.show_frame(s, none, none)
	await process_frame
	await process_frame
	await process_frame
	vp.get_texture().get_image().save_png(out)
	quit()
