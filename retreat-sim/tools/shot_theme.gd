extends SceneTree
## Renders a mission's real map and theme with a squad and a few enemies on it.
##   godot --path . -s tools/shot_theme.gd -- <mission_id> out.png
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var id: String = args[0] if args.size() > 0 else "karsa_breakout"
	var out: String = args[1] if args.size() > 1 else "theme.png"
	var map := MapData.load_file(id)
	var vp := SubViewport.new()
	vp.size = Vector2i(1080, 640)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var board := BoardView.new()
	board.size = Vector2(1080, 640)
	vp.add_child(board)
	var s := map.build_state()
	s.fixed_roll = 1
	for i in 4:
		s.add_unit(SimUnit.make([1, 2, 3, 4][i], 0, map.player_spawns[i], 3, 5))
	for i in 4:
		s.add_unit(SimUnit.make(200 + i if i < 2 else 210 + i, 1, map.enemy_spawns[i], 3, 5))
	board.set_level_theme(map.theme)
	var none: Array[Dictionary] = []
	board.show_frame(s, none, none)
	await process_frame
	await process_frame
	await process_frame
	vp.get_texture().get_image().save_png(out)
	quit()
