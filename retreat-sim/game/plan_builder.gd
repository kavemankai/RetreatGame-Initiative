class_name PlanBuilder
extends RefCounted
## Builds a team's orders for one turn, one entry at a time, within each
## merc's tick budget. Everything the player may know comes from the team's
## fog-filtered view, so order entry cannot leak hidden enemies.
##
## With a live SimTurn the builder plans the REST of the turn: each merc's
## budget starts after its committed action, positions are projected from where
## that action ends, and the merc's queued orders are seeded as entries (so they
## can be undone or kept).
##
## An "entry" is one player gesture (a move to a tile, a shot, an overwatch)
## and is the unit of undo. Entry: {kind, actions, cost, pos, path?}.

var _team: int
var _view: SimState
var _entries: Dictionary = {}  # unit id -> Array[Dictionary]
var _free: Dictionary = {}     # unit id -> ticks already spoken for (live run)
var _origin: Dictionary = {}   # unit id -> where planning starts (live run)


func _init(state: SimState, team: int, turn: SimTurn = null) -> void:
	_team = team
	_view = SimVision.view_for(state, team)
	if turn != null:
		for id in own_unit_ids():
			_free[id] = turn.free_at(id)
			_origin[id] = turn.projected_pos(id)
			_seed(id, turn)


func own_unit_ids() -> Array[int]:
	var ids: Array[int] = []
	for id in _view.units:
		var u: SimUnit = _view.units[id]
		if u.alive and u.team == _team:
			ids.append(id)
	ids.sort()
	return ids


func view() -> SimState:
	return _view


func entries_for(id: int) -> Array:
	return _entries.get(id, [])


func ticks_used(id: int) -> int:
	var total := 0
	for e: Dictionary in entries_for(id):
		total += int(e["cost"])
	return total


func ticks_left(id: int) -> int:
	var u: SimUnit = _view.units.get(id)
	return 0 if u == null else u.available_ticks() - int(_free.get(id, 0)) - ticks_used(id)


## Where the merc will stand once its queued orders are done.
func projected_pos(id: int) -> Vector2i:
	var list := entries_for(id)
	if not list.is_empty():
		return list[list.size() - 1]["pos"]
	return _origin.get(id, (_view.units[id] as SimUnit).pos)


func orders_for(id: int) -> Array[SimAction]:
	var out: Array[SimAction] = []
	for e: Dictionary in entries_for(id):
		out.append_array(e["actions"])
	return out


## Tiles (-> tick cost) the merc could still walk to from its projected spot.
func reachable(id: int) -> Dictionary:
	if _own_error(id) != "":
		return {}
	return SimPathing.reach(_view, projected_pos(id), id, ticks_left(id))["dist"]


func queue_move(id: int, tile: Vector2i) -> String:
	var err := _own_error(id)
	if err != "":
		return err
	var from := projected_pos(id)
	if tile == from:
		return "Already there."
	var r := SimPathing.reach(_view, from, id, ticks_left(id))
	var path := SimPathing.path_to(r, tile)
	if path.is_empty():
		return "Can't reach that tile (%d ticks left)." % ticks_left(id)
	_push(id, {"kind": "move", "actions": SimPathing.path_actions(path), "cost": r["dist"][tile], "pos": tile, "path": path})
	return ""


## What a shot at `target_id` would do from the merc's projected position.
func shot_preview(id: int, target_id: int) -> Dictionary:
	var target: SimUnit = _view.units.get(target_id)
	if _own_error(id) != "" or target == null or not target.alive:
		return {"result": "invalid", "reason": "no_target"}
	if target.team == _team:
		return {"result": "invalid", "reason": "friendly"}
	var fired := (entries_for(id) as Array).any(func(e: Dictionary) -> bool: return e["kind"] == "shoot" or e["kind"] == "move_fire")
	return SimResolver.evaluate_shot(_view.grid, _view.units[id], projected_pos(id), target, not fired)


func queue_shoot(id: int, target_id: int) -> String:
	var err := _own_error(id)
	if err != "":
		return err
	var target: SimUnit = _view.units.get(target_id)
	if target == null or not target.alive:
		return "You can't see that target."
	if target.team == _team:
		return "That's your own merc."
	var shooter: SimUnit = _view.units[id]
	if ticks_left(id) < shooter.shot_ticks():
		return "Not enough ticks for a shot (%d needed, %d left)." % [shooter.shot_ticks(), ticks_left(id)]
	_push(id, {"kind": "shoot", "actions": [SimAction.shoot(target_id)], "cost": shooter.shot_ticks(), "pos": projected_pos(id), "target": target_id})
	return ""


## Walk to `tile` and take a shot if one comes up on the way. The cost is the
## path plus a reserved double shot, paid whether or not anything is fired at.
func queue_move_fire(id: int, tile: Vector2i) -> String:
	var plan := _fire_plan(id, tile)
	if plan.has("error"):
		return plan["error"]
	var action := SimAction.move_fire(plan["steps"])
	_push(id, {"kind": "move_fire", "actions": [action], "cost": plan["cost"], "pos": tile, "path": plan["path"]})
	return ""


## What Move and Fire to `tile` would cost: {cost, path}, or {} if it can't be done.
func move_fire_preview(id: int, tile: Vector2i) -> Dictionary:
	var plan := _fire_plan(id, tile)
	return {} if plan.has("error") else {"cost": plan["cost"], "path": plan["path"]}


## Ticks reserved for the shot in a Move and Fire.
func fire_reserve(id: int) -> int:
	var u: SimUnit = _view.units.get(id)
	return 0 if u == null else u.shot_ticks() * SimConst.MOVE_FIRE_SHOT_FACTOR


## Tiles (-> walking ticks) reachable while still affording the reserved shot.
func reachable_fire(id: int) -> Dictionary:
	if _own_error(id) != "":
		return {}
	return SimPathing.reach(_view, projected_pos(id), id, maxi(ticks_left(id) - fire_reserve(id), 0))["dist"]


## One block per queued entry, in absolute round ticks: {kind, start, end}.
func timeline(id: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var t: int = int(_free.get(id, 0))
	for e: Dictionary in entries_for(id):
		out.append({"kind": e["kind"], "start": t, "end": t + int(e["cost"])})
		t += int(e["cost"])
	return out


## Hold overwatch facing `facing` for every tick the merc has left.
func queue_overwatch(id: int, facing: Vector2i) -> String:
	var err := _own_error(id)
	if err != "":
		return err
	if facing == Vector2i.ZERO or absi(facing.x) > 1 or absi(facing.y) > 1:
		return "Pick a direction for overwatch."
	var hold := ticks_left(id)
	if hold < 1:
		return "No ticks left to hold overwatch."
	_push(id, {"kind": "overwatch", "actions": [SimAction.overwatch(facing, hold)], "cost": hold, "pos": projected_pos(id), "facing": facing})
	return ""


func undo(id: int) -> void:
	var list := entries_for(id)
	if not list.is_empty():
		list.pop_back()


func clear(id: int) -> void:
	_entries.erase(id)


func clear_all() -> void:
	_entries.clear()


## Every own merc's future orders (empty array = cleared), ready for
## SimMatch.apply_orders.
func orders_dict() -> Dictionary:
	var out := {}
	for id in own_unit_ids():
		out[id] = orders_for(id)
	return out


## A snapshot of the team's orders, safe to keep after further edits.
func plan() -> SimPlan:
	var p := SimPlan.new()
	for id in own_unit_ids():
		for a: SimAction in orders_for(id):
			p.add(id, a)
	return p


## 8-way facing from `from` toward `to` (zero if they are the same tile).
static func facing_toward(from: Vector2i, to: Vector2i) -> Vector2i:
	var d := to - from
	var ax := absi(d.x)
	var ay := absi(d.y)
	return Vector2i(signi(d.x) if 2 * ax >= ay else 0, signi(d.y) if 2 * ay >= ax else 0)


## {path, steps, cost} for a Move and Fire to `tile`, or {"error": reason}.
func _fire_plan(id: int, tile: Vector2i) -> Dictionary:
	var err := _own_error(id)
	if err != "":
		return {"error": err}
	var from := projected_pos(id)
	if tile == from:
		return {"error": "Already there."}
	var reserve := fire_reserve(id)
	var budget := ticks_left(id) - reserve
	if budget < SimConst.COST_ORTHO:
		return {"error": "Not enough ticks to move and fire (%d needed for the shot alone, %d left)." % [reserve, ticks_left(id)]}
	var r := SimPathing.reach(_view, from, id, budget)
	var path := SimPathing.path_to(r, tile)
	if path.is_empty():
		return {"error": "Can't reach that tile and still afford the shot (%d ticks of walking at most)." % budget}
	var steps: Array[Vector2i] = []
	for i in range(1, path.size()):
		steps.append(path[i] - path[i - 1])
	return {"path": path, "steps": steps, "cost": int(r["dist"][tile]) + reserve}


func _push(id: int, entry: Dictionary) -> void:
	if not _entries.has(id):
		_entries[id] = []
	(_entries[id] as Array).append(entry)


func _own_error(id: int) -> String:
	var u: SimUnit = _view.units.get(id)
	if u == null or not u.alive or u.team != _team:
		return "That isn't one of your mercs."
	return ""


## Turn a merc's queued orders (after its committed action) into entries.
func _seed(id: int, turn: SimTurn) -> void:
	var unit: SimUnit = _view.units[id]
	var actions := turn.remaining_actions(id)
	if turn.committed_action(id) != null:
		actions = actions.slice(1)
	var pos: Vector2i = _origin[id]
	var path: Array[Vector2i] = [pos]
	var run_actions: Array[SimAction] = []
	var run_cost := 0
	for a: SimAction in actions:
		if a.type == SimConst.ACTION_MOVE:
			pos += a.dir
			path.append(pos)
			run_actions.append(a)
			run_cost += a.cost(unit)
			continue
		_flush_move(id, path, run_actions, run_cost)
		path = [pos]
		run_actions = []
		run_cost = 0
		# A queued shot at a target that has since died or left sight cannot be
		# kept (Resume would be refused); it is dropped and can be re-ordered.
		if a.type == SimConst.ACTION_SHOOT and not _view.units.has(a.target_id):
			continue
		if a.type == SimConst.ACTION_MOVE_FIRE:
			var fire_path: Array[Vector2i] = [pos]
			for d in a.steps:
				pos += d
				fire_path.append(pos)
			_push(id, {"kind": "move_fire", "actions": [a], "cost": a.cost(unit), "pos": pos, "path": fire_path})
			continue
		_push(id, _seeded_entry(unit, a, pos))
	_flush_move(id, path, run_actions, run_cost)


func _flush_move(id: int, path: Array[Vector2i], actions: Array[SimAction], cost: int) -> void:
	if not actions.is_empty():
		_push(id, {"kind": "move", "actions": actions, "cost": cost, "pos": path[path.size() - 1], "path": path})


func _seeded_entry(unit: SimUnit, a: SimAction, pos: Vector2i) -> Dictionary:
	match a.type:
		SimConst.ACTION_SHOOT:
			return {"kind": "shoot", "actions": [a], "cost": a.cost(unit), "pos": pos, "target": a.target_id}
		SimConst.ACTION_OVERWATCH:
			return {"kind": "overwatch", "actions": [a], "cost": a.cost(unit), "pos": pos, "facing": a.dir}
	return {"kind": "wait", "actions": [a], "cost": a.cost(unit), "pos": pos}
