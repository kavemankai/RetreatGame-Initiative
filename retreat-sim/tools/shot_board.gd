extends SceneTree
## Renders the skirmish map through BoardView to a PNG.
##   godot --path . -s tools/shot_board.gd -- out.png
func _init() -> void:
	var out := "board.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	var vp := SubViewport.new()
	vp.size = Vector2i(540, 300)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var board := BoardView.new()
	board.size = Vector2(540, 300)
	vp.add_child(board)
	var s := Scenarios.skirmish_state()
	var no_events: Array[Dictionary] = []
	var no_watchers: Array[Dictionary] = []
	board.show_frame(s, no_events, no_watchers)
	await process_frame
	await process_frame
	await process_frame
	vp.get_texture().get_image().save_png(out)
	quit()
