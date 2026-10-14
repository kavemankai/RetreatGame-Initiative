class_name PlayController
extends RefCounted
## Turns taps/clicks into orders. UI-agnostic: the play screen only forwards
## input here and draws what this exposes.

const MODE_NORMAL := "normal"
const MODE_OVERWATCH := "overwatch"
const MODE_MOVE_FIRE := "move_fire"
const NO_TILE := Vector2i(-1, -1)

var game: SimMatch
var builder: PlanBuilder
var selected := -1
var mode := MODE_NORMAL
## Touch mode: the tile awaiting a confirming second tap (NO_TILE = none).
var pending := NO_TILE


func _init(p_game: SimMatch) -> void:
	game = p_game
	_new_turn()


## Rebuild the planner from the live run (after any tick or pause).
func _new_turn() -> void:
	builder = PlanBuilder.new(game.state, game.player_team, game.run)
	selected = -1
	mode = MODE_NORMAL
	pending = NO_TILE


func set_mode(m: String) -> void:
	mode = m
	pending = NO_TILE


func select(id: int) -> void:
	if builder.own_unit_ids().has(id):
		selected = id
		pending = NO_TILE


func deselect() -> void:
	selected = -1
	mode = MODE_NORMAL
	pending = NO_TILE


## Returns {"ok": bool, "msg": String}.
func click_tile(tile: Vector2i) -> Dictionary:
	pending = NO_TILE
	var u := _unit_at(tile)
	if u != null and u.team == game.player_team:
		selected = u.id
		mode = MODE_NORMAL
		return _ok("Selected u%d." % u.id)
	if selected < 0:
		return _fail("Select one of your mercs first.")
	if mode == MODE_OVERWATCH:
		return _overwatch_toward(tile)
	if mode == MODE_MOVE_FIRE:
		if u != null:
			return _fail("Pick an empty tile to move to.")
		var res := _result(builder.queue_move_fire(selected, tile), "u%d will move and fire (%d ticks)." % [selected, builder.ticks_used(selected)])
		if res["ok"]:
			mode = MODE_NORMAL
		return res
	if u != null:
		return _result(builder.queue_shoot(selected, u.id), "u%d will shoot u%d." % [selected, u.id])
	return _result(builder.queue_move(selected, tile), "u%d will move (%d ticks)." % [selected, builder.ticks_used(selected)])


## Touch input: tapping your own merc selects it at once; any other tile
## first PREVIEWS the order (path or shot result), and a second tap on the
## same tile commits it. Returns {"ok", "msg", "preview"?}.
func tap_tile(tile: Vector2i) -> Dictionary:
	var u := _unit_at(tile)
	if u != null and u.team == game.player_team:
		return click_tile(tile)
	if selected < 0:
		pending = NO_TILE
		return _fail("Select one of your mercs first.")
	if tile == pending:
		return click_tile(tile)
	var info := hover_info(tile)
	var reach := builder.reachable_fire(selected) if mode == MODE_MOVE_FIRE else builder.reachable(selected)
	if u == null and (mode == MODE_NORMAL or mode == MODE_MOVE_FIRE) and not reach.has(tile):
		pending = NO_TILE
		return _fail(info)
	pending = tile
	var res := _ok("%s Tap again to confirm." % info)
	res["preview"] = true
	return res


## Data for drawing the pending order: {} or {kind: move|shot|overwatch, ...}.
func pending_preview() -> Dictionary:
	if pending == NO_TILE or selected < 0:
		return {}
	var from := builder.projected_pos(selected)
	var u := _unit_at(pending)
	if mode == MODE_OVERWATCH:
		return {"kind": "overwatch", "pos": from, "facing": PlanBuilder.facing_toward(from, pending)}
	if mode == MODE_MOVE_FIRE:
		var pv := builder.move_fire_preview(selected, pending)
		return {} if pv.is_empty() else {"kind": "move_fire", "path": pv["path"]}
	if u != null and u.team != game.player_team:
		return {"kind": "shot", "from": from, "to": u.pos, "result": builder.shot_preview(selected, u.id)["result"]}
	var r := SimPathing.reach(builder.view(), from, selected, builder.ticks_left(selected))
	return {"kind": "move", "path": SimPathing.path_to(r, pending)}


## Short text for what a click on `tile` would do (empty if nothing).
func hover_info(tile: Vector2i) -> String:
	if selected < 0:
		return ""
	var u := _unit_at(tile)
	if mode == MODE_MOVE_FIRE:
		var pv := builder.move_fire_preview(selected, tile)
		if pv.is_empty():
			return "Can't reach that tile and still afford the shot."
		return "Move and fire: %d ticks (%d walking + %d reserved for a shot). It fires if one comes up." % [pv["cost"], int(pv["cost"]) - builder.fire_reserve(selected), builder.fire_reserve(selected)]
	if u != null and u.team != game.player_team and mode == MODE_NORMAL:
		var p := builder.shot_preview(selected, u.id)
		match p["result"]:
			"hit":
				return "Shot: %d%% to hit, %d damage." % [p["chance"], p["damage"]]
			"blocked":
				return "Shot would be blocked by cover."
		return "No shot: %s." % String(p["reason"]).replace("_", " ")
	if mode == MODE_OVERWATCH:
		return "Hold overwatch facing here."
	var dist := builder.reachable(selected)
	if dist.has(tile) and tile != builder.projected_pos(selected):
		return "Move: %d ticks." % dist[tile]
	return "Tile is unreachable."


func undo() -> void:
	pending = NO_TILE
	if selected >= 0:
		builder.undo(selected)


func clear() -> void:
	pending = NO_TILE
	builder.clear_all()


## Hand the planned orders to the live run without letting time pass.
## Returns "" or why they were refused.
func go() -> String:
	var err := game.apply_orders(builder.orders_dict())
	if err == "":
		pending = NO_TILE
	return err


## The player stopped the action: the AI replans, and the planner is rebuilt
## from the live run so it starts after each merc's committed action.
func pause() -> void:
	game.pause()
	_new_turn()


## Re-sync after the run advanced (keeps the selection).
func sync() -> void:
	var keep := selected
	_new_turn()
	if keep >= 0:
		select(keep)


## Apply the orders and run the rest of the turn without stopping.
## Returns null (see game.last_error) if the orders were refused.
func confirm() -> SimResult:
	var err := go()
	if err != "":
		game.last_error = err
		return null
	var this_turn := game.turn
	while game.turn == this_turn and not game.is_over():
		game.step()
	_new_turn()
	return game.last_result


func _overwatch_toward(tile: Vector2i) -> Dictionary:
	var facing := PlanBuilder.facing_toward(builder.projected_pos(selected), tile)
	var res := _result(builder.queue_overwatch(selected, facing), "u%d will hold overwatch." % selected)
	if res["ok"]:
		mode = MODE_NORMAL
	return res


## The visible unit standing on `tile`, if any (hidden enemies are invisible
## here exactly as they are on the board).
func _unit_at(tile: Vector2i) -> SimUnit:
	return builder.view().unit_at(tile)


func _result(err: String, ok_msg: String) -> Dictionary:
	return _fail(err) if err != "" else _ok(ok_msg)


func _ok(msg: String) -> Dictionary:
	return {"ok": true, "msg": msg}


func _fail(msg: String) -> Dictionary:
	return {"ok": false, "msg": msg}
