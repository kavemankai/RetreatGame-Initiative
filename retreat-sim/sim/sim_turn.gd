class_name SimTurn
extends RefCounted
## One turn as a live, interruptible run: advance it a tick at a time and
## re-order mercs between ticks. SimResolver.resolve() is just "advance until
## finished", so stepping and one-shot resolution always agree.
##
## Per tick (1..TICKS_PER_TURN):
##   1. Moves complete, highest speed first (ties: lower unit id). A step into
##      an occupied or impassable tile halts that unit's remaining orders.
##   2. Shots complete one at a time: highest speed first, then higher aim,
##      then lower id. Candidates are queued shoot orders, Move and Fire
##      opportunities and overwatch reactions to this tick's movers. Each shot
##      sees the board the shots before it left, so a hit can pre-empt the
##      reply (no mutual kills). A non-lethal hit forces a morale check
##      (SimDice d10 <= morale + 3 - wounds, +1 beside cover; Hollows are exempt): steady = keeps moving but cannot
##      shoot for the rest of the round; broken = all remaining orders stop.
##   3. Finished units advance to their next order.
## An action takes effect on the tick it finishes (start + cost - 1).
## Overwatch is active on every tick from its start through its finish.
##
## Re-ordering (replace_orders): spent ticks stay spent. A move or shot that
## has already started finishes ("committed"); holds (overwatch/wait) and
## actions that have not started are cancelled at once.

var state: SimState
var tick := 0
var events: Array[Dictionary] = []
## snapshots[t] = the board after tick t (0 = start). Only kept on request.
var snapshots: Array[SimState] = []
## Units whose orders ran out (or were halted) on the tick just advanced.
var last_idle: Array[int] = []

var _rt := {}  # unit id -> {queue, idx, start, finish, spent, marks, step, fired}
var _opportunists: Array[int] = []  # move-and-fire units that stepped this tick
var _suppressed := {}  # unit id -> true: steady after a hit, no more shooting this round
var _broken := {}  # unit id -> true: broke after a hit, no more orders this round
var _fired_this_round := {}  # unit id -> true once it has taken a shot (for the opener trait)
var _keep_snapshots: bool


func _init(start: SimState, plan: SimPlan, keep_snapshots: bool = false) -> void:
	state = start.clone()
	_keep_snapshots = keep_snapshots
	var order_ids := plan.orders.keys()
	order_ids.sort()
	for id in order_ids:
		var queue: Array = plan.orders[id]
		var rejection := _rejection(id, queue)
		if rejection != "":
			events.append({"type": "plan_rejected", "tick": 0, "unit": id, "reason": rejection})
			continue
		var u: SimUnit = state.units[id]
		if queue.is_empty():
			continue
		var finish: int = (queue[0] as SimAction).cost(u)
		if finish <= u.available_ticks():
			_rt[id] = {"queue": queue, "idx": 0, "start": 1, "finish": finish, "spent": false}
			_arm(_rt[id], u)
	if keep_snapshots:
		snapshots.append(state.clone())


func is_finished() -> bool:
	return tick >= SimConst.TICKS_PER_TURN


func result() -> SimResult:
	var r := SimResult.new()
	r.state = state
	r.events = events
	return r


## Resolve the next tick. Returns the events produced on that tick.
func advance() -> Array[Dictionary]:
	if is_finished():
		return []
	var first := events.size()
	tick += 1
	last_idle.clear()
	var due := _due()
	var moved := _phase_moves(due)
	_phase_shots(due, moved)
	_advance_queues(due)
	if tick == SimConst.TICKS_PER_TURN:
		state.turn += 1
		events.append({"type": "turn_end", "tick": tick})
	if _keep_snapshots:
		snapshots.append(state.clone())
	return events.slice(first)


# --- re-ordering -------------------------------------------------------------

## The move/shot this merc is in the middle of, or null. Such an action
## cannot be cancelled; it finishes before any new order starts.
func committed_action(id: int) -> SimAction:
	var e: Dictionary = _rt.get(id, {})
	if e.is_empty() or e["start"] > tick:
		return null
	var a := _current(id)
	return a if a.type in [SimConst.ACTION_MOVE, SimConst.ACTION_SHOOT, SimConst.ACTION_MOVE_FIRE] else null


## The last tick that is already spoken for; new orders start the tick after.
func free_at(id: int) -> int:
	return (_rt[id]["finish"] as int) if committed_action(id) != null else tick


## Where the merc will stand once its committed action (if any) completes.
func projected_pos(id: int) -> Vector2i:
	var u: SimUnit = state.units[id]
	var a := committed_action(id)
	if a == null:
		return u.pos
	if a.type == SimConst.ACTION_MOVE:
		return u.pos + a.dir
	if a.type == SimConst.ACTION_MOVE_FIRE:
		var p := u.pos
		for i in range(int(_rt[id]["step"]), a.steps.size()):
			p += a.steps[i]
		return p
	return u.pos


## The current action plus everything queued behind it.
func remaining_actions(id: int) -> Array[SimAction]:
	var out: Array[SimAction] = []
	var e: Dictionary = _rt.get(id, {})
	if e.is_empty():
		return out
	var queue: Array = e["queue"]
	for i in range(e["idx"], queue.size()):
		var a: SimAction = queue[i]
		# A hold already under way only has the rest of its window left.
		if i == e["idx"] and e["start"] <= tick and (a.type == SimConst.ACTION_OVERWATCH or a.type == SimConst.ACTION_WAIT):
			var left: int = e["finish"] - tick
			if left < 1:
				continue
			a = SimAction.overwatch(a.dir, left) if a.type == SimConst.ACTION_OVERWATCH else SimAction.wait(left)
		out.append(a)
	return out


## Would replace_orders accept this queue? Returns "" or the reason, and
## changes nothing.
func can_replace(id: int, actions: Array) -> String:
	var u: SimUnit = state.units.get(id)
	if u == null or not u.alive:
		return "That merc can't take orders."
	if _broken.has(id) and not actions.is_empty():
		return "That merc is broken and holds until the round ends."
	for a in actions:
		if not (a is SimAction) or not (a as SimAction).is_valid_shape():
			return "Malformed order."
	var cursor := free_at(id)
	for a: SimAction in actions:
		cursor += a.cost(u)
	if cursor > u.available_ticks():
		return "Those orders need %d ticks; only %d remain." % [cursor - free_at(id), u.available_ticks() - free_at(id)]
	return ""


## Replace a merc's future orders. Returns "" or an error message.
func replace_orders(id: int, actions: Array) -> String:
	if _suppressed.has(id):
		actions = _without_fire(actions)
	var err := can_replace(id, actions)
	if err != "":
		return err
	var u: SimUnit = state.units[id]
	var kept := committed_action(id)
	var spent := _spent_hold_continues(id, actions)
	var queue: Array = []
	if kept != null:
		queue.append(kept)
	queue.append_array(actions)
	if queue.is_empty():
		_rt.erase(id)
	elif kept != null:
		_rt[id]["queue"] = queue
		_rt[id]["idx"] = 0
	else:
		_rt[id] = {"queue": queue, "idx": 0, "start": tick + 1, "finish": tick + (queue[0] as SimAction).cost(u), "spent": spent}
		_arm(_rt[id], u)
	return ""


## Re-issuing the hold a merc is already in (pause + resume with no edit)
## must not re-arm a watch that has already fired.
func _spent_hold_continues(id: int, actions: Array) -> bool:
	var e: Dictionary = _rt.get(id, {})
	if e.is_empty() or actions.is_empty() or e["start"] > tick or not e["spent"]:
		return false
	var current := _current(id)
	var first: SimAction = actions[0]
	return current.type == SimConst.ACTION_OVERWATCH and first.type == SimConst.ACTION_OVERWATCH and first.dir == current.dir


## Close the turn log when a match ends before tick 12.
func end_early() -> void:
	if tick < SimConst.TICKS_PER_TURN and (events.is_empty() or events.back()["type"] != "turn_end"):
		state.turn += 1
		events.append({"type": "turn_end", "tick": tick})


## Is any living merc still carrying out or waiting on orders (queued steps,
## shots in flight, overwatch holds)? When not, the run can fast-forward.
func has_active_orders() -> bool:
	for id in _rt:
		if (state.units[id] as SimUnit).alive:
			return true
	return false


## Overwatch windows that will be live on the next tick: {id, dir, spent, pos}.
func watchers() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids := _rt.keys()
	ids.sort()
	for id: int in ids:
		var e: Dictionary = _rt[id]
		var a := _current(id)
		var u: SimUnit = state.units[id]
		if a.type == SimConst.ACTION_OVERWATCH and u.alive and not _suppressed.has(id) and e["start"] <= tick + 1 and e["finish"] >= tick + 1:
			out.append({"id": id, "dir": a.dir, "spent": e["spent"], "pos": u.pos})
	return out


# --- resolution internals ------------------------------------------------------

## Why a unit's orders cannot be run at all ("" = fine). The resolver never
## trusts a plan: malformed orders are dropped with a logged reason.
func _rejection(id: int, queue: Array) -> String:
	var u: SimUnit = state.units.get(id)
	if u == null:
		return "unknown_unit"
	if not u.alive:
		return "dead_unit"
	for a in queue:
		if not (a is SimAction) or not (a as SimAction).is_valid_shape():
			return "malformed_action"
	return ""


## Shot order inside a tick: faster first, then the better aim, then lower id.
func _fires_before(a: int, b: int) -> bool:
	var ua: SimUnit = state.units[a]
	var ub: SimUnit = state.units[b]
	if ua.speed != ub.speed:
		return ua.speed > ub.speed
	if ua.aim != ub.aim:
		return ua.aim > ub.aim
	return a < b


func _before(a: int, b: int) -> bool:
	var ua: SimUnit = state.units[a]
	var ub: SimUnit = state.units[b]
	if ua.speed != ub.speed:
		return ua.speed > ub.speed
	return a < b


func _current(id: int) -> SimAction:
	var e: Dictionary = _rt[id]
	return (e["queue"] as Array)[e["idx"]]


func _due() -> Array[int]:
	var due: Array[int] = []
	for id in _rt:
		if _rt[id]["finish"] == tick and (state.units[id] as SimUnit).alive:
			due.append(id)
	due.sort_custom(_before)
	return due


## Returns the ids that completed a step this tick, in resolution order.
## Plain moves finish with their action; Move and Fire completes one step at
## each of its own marks along the way.
func _phase_moves(due: Array[int]) -> Array[int]:
	var moved: Array[int] = []
	_opportunists.clear()
	var movers: Array[int] = []
	for id in due:
		if _rt.has(id) and _current(id).type == SimConst.ACTION_MOVE:
			movers.append(id)
	for id in _rt:
		var e: Dictionary = _rt[id]
		if (state.units[id] as SimUnit).alive and _current(id).type == SimConst.ACTION_MOVE_FIRE and e["step"] < (e["marks"] as Array).size() and e["marks"][e["step"]] == tick:
			movers.append(id)
	movers.sort_custom(_before)
	for id in movers:
		if not _rt.has(id):
			continue
		var action := _current(id)
		var e: Dictionary = _rt[id]
		var u: SimUnit = state.units[id]
		var dir: Vector2i = action.dir if action.type == SimConst.ACTION_MOVE else action.steps[e["step"]]
		var dest := u.pos + dir
		var reason := ""
		if not state.grid.can_step(u.pos, dest):
			reason = "terrain"
		elif state.unit_at(dest) != null:
			reason = "occupied"
		if reason != "":
			events.append({"type": "move_blocked", "tick": tick, "unit": id, "at": u.pos, "to": dest, "reason": reason})
			_rt.erase(id)
			_note_idle(id)
			continue
		events.append({"type": "move", "tick": tick, "unit": id, "from": u.pos, "to": dest})
		u.pos = dest
		u.bump("steps_moved")
		moved.append(id)
		if action.type == SimConst.ACTION_MOVE_FIRE:
			e["step"] += 1
			if not e["fired"]:
				_opportunists.append(id)
	return moved


func _phase_shots(due: Array[int], moved: Array[int]) -> void:
	var candidates: Array[Dictionary] = []
	for id in due:
		if _rt.has(id) and _current(id).type == SimConst.ACTION_SHOOT:
			candidates.append({"id": id, "target": _current(id).target_id, "overwatch": false})
	for id in _opportunists:
		if _rt.has(id) and not _rt[id]["fired"] and not _suppressed.has(id):
			var target := _opportunity(id)
			if target >= 0:
				candidates.append({"id": id, "target": target, "overwatch": false, "on_the_move": true})
	candidates.append_array(_overwatch_triggers(moved))
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _fires_before(a["id"], b["id"]))
	for c in candidates:
		_resolve_shot(c)


## Each active, unspent watcher reacts to the first mover (in resolution
## order) that is an enemy inside its cone, range and line of sight.
func _overwatch_triggers(moved: Array[int]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if moved.is_empty():
		return out
	for id in _rt:
		var e: Dictionary = _rt[id]
		var action := _current(id)
		var watcher: SimUnit = state.units[id]
		if action.type != SimConst.ACTION_OVERWATCH or e["spent"] or not watcher.alive or _suppressed.has(id):
			continue
		if tick < e["start"] or tick > e["finish"]:
			continue
		for mid in moved:
			var mover: SimUnit = state.units[mid]
			if not mover.alive or mover.team == watcher.team:
				continue
			if not SimLos.in_cone(watcher.pos, action.dir, mover.pos):
				continue
			if SimLos.chebyshev(watcher.pos, mover.pos) > watcher.max_range():
				continue
			if not SimLos.can_shoot(state.grid, watcher.pos, mover.pos):
				continue
			out.append({"id": id, "target": mid, "overwatch": true})
			break
	return out


func _resolve_shot(c: Dictionary) -> void:
	var id: int = c["id"]
	var shooter: SimUnit = state.units[id]
	if not shooter.alive:
		events.append({"type": "cancelled", "tick": tick, "unit": id, "reason": "dead"})
		return
	if not _rt.has(id) or _suppressed.has(id):
		# Hit earlier this tick: a broken unit has no orders left, a steady one may not fire.
		events.append({"type": "cancelled", "tick": tick, "unit": id, "reason": "broken" if _broken.has(id) else "suppressed"})
		return
	var ev := {"type": "shot", "tick": tick, "unit": id, "target": c["target"]}
	if c["overwatch"]:
		ev["overwatch"] = true
	ev.merge(_eval_shot(shooter, c["target"]))
	if ev["result"] == "hit":
		_roll_to_hit(ev, shooter)
	# A fired reaction spends the watch; a fizzled one (target already gone) keeps it.
	if c["overwatch"] and ev["result"] != "invalid":
		_rt[id]["spent"] = true
	if c.get("on_the_move", false) and ev["result"] != "invalid":
		_rt[id]["fired"] = true  # one shot per Move and Fire
	events.append(ev)
	if ev["result"] == "invalid":
		return
	shooter.bump("shots_fired")
	if ev["result"] != "hit":
		return
	var target: SimUnit = state.units[ev["target"]]
	target.hp -= int(ev["damage"])
	target.bump("hits_taken")
	if target.hp <= 0 and target.alive:
		target.alive = false
		_rt.erase(target.id)
		events.append({"type": "death", "tick": tick, "unit": target.id, "killer": id})
	elif target.alive and not _broken.has(target.id):
		_morale_check(target)


## A clear shot still has to land: roll d100 against the shooter's chance.
## A failed roll turns the event into a miss (no damage, no morale check).
func _roll_to_hit(ev: Dictionary, shooter: SimUnit) -> void:
	_fired_this_round[shooter.id] = true
	var roll: int = state.fixed_roll
	if roll < 0:
		roll = SimDice.d100(state.seed, state.turn, tick, shooter.id, SimConst.HIT_DIE_OFFSET + int(shooter.counters.get("shots_fired", 0)))
	ev["roll"] = roll
	if roll > int(ev["chance"]):
		ev["result"] = "miss"
		ev.erase("damage")


## A hit unit rolls the morale die. Steady: keeps its moves, loses its shots.
## Broken: every remaining order stops.
func _morale_check(u: SimUnit) -> void:
	if u.is_drone:
		return  # Hollows feel nothing: no check, they keep shooting
	var wounds := int(u.counters.get("hits_taken", 0))
	var need := u.morale + SimConst.MORALE_BONUS - wounds
	if state.grid.has_cover_nearby(u.pos):
		need += SimConst.MORALE_COVER_BONUS
		if u.gear_trait == "bracing":
			need += SimConst.BRACING_MORALE_BONUS
	var roll := SimDice.d10(state.seed, state.turn, tick, u.id, wounds)
	var steady := roll <= need
	events.append({"type": "morale", "tick": tick, "unit": u.id, "roll": roll, "need": need, "result": "steady" if steady else "broken"})
	if steady:
		_suppress(u.id)
	else:
		_broken[u.id] = true
		_rt.erase(u.id)
		_note_idle(u.id)


## Drop every shot and watch from a unit's orders for the rest of the round.
## A move (or the walk of a Move and Fire) in progress carries on; a shot or
## watch in progress ends now and the next remaining order starts next tick.
func _suppress(id: int) -> void:
	_suppressed[id] = true
	if not _rt.has(id):
		return
	var e: Dictionary = _rt[id]
	var queue: Array = e["queue"]
	var current: SimAction = queue[e["idx"]]
	var rest: Array = []
	for i in range(int(e["idx"]) + 1, queue.size()):
		var a: SimAction = queue[i]
		if a.type != SimConst.ACTION_SHOOT and a.type != SimConst.ACTION_OVERWATCH:
			rest.append(a)
	if current.type in [SimConst.ACTION_MOVE, SimConst.ACTION_MOVE_FIRE, SimConst.ACTION_WAIT]:
		e["queue"] = [current] + rest
		e["idx"] = 0
		e["fired"] = true
		return
	if rest.is_empty():
		_rt.erase(id)
		_note_idle(id)
		return
	var u: SimUnit = state.units[id]
	e["queue"] = rest
	e["idx"] = 0
	e["start"] = tick + 1
	e["finish"] = tick + (rest[0] as SimAction).cost(u)
	e["spent"] = false
	_arm(e, u)
	if e["finish"] > u.available_ticks():
		_rt.erase(id)
		_note_idle(id)


func is_broken(id: int) -> bool:
	return _broken.has(id)


func is_suppressed(id: int) -> bool:
	return _suppressed.has(id)


## A suppressed unit's new orders lose their shots and watches.
func _without_fire(actions: Array) -> Array:
	return actions.filter(func(a) -> bool: return not (a is SimAction) or ((a as SimAction).type != SimConst.ACTION_SHOOT and (a as SimAction).type != SimConst.ACTION_OVERWATCH))


## The shot a Move and Fire merc takes on its current step, or -1. Only
## enemies the merc's squad can see are considered (so it never reveals
## anything hidden); a clean hit beats a shot into cover, then the weakest
## target, then the lowest id.
func _opportunity(id: int) -> int:
	var shooter: SimUnit = state.units[id]
	var best := -1
	var best_key := -1
	for tid in SimVision.visible_unit_ids(state, shooter.team):
		var t: SimUnit = state.units[tid]
		if not t.alive or t.team == shooter.team:
			continue
		var r := SimResolver.evaluate_shot(state.grid, shooter, shooter.pos, t, not _fired_this_round.has(shooter.id))
		if r["result"] == "invalid":
			continue
		# A clean line beats cover, then the weakest target, then the likelier hit.
		var key := (100000 if r["result"] == "hit" else 0) + (100 - t.hp) * 1000 + int(r.get("chance", 0))
		if key > best_key:
			best_key = key
			best = tid
	return best


## Set up per-action progress when an action becomes the merc's current one.
## Move and Fire completes a step at each mark (start + the steps' costs).
func _arm(e: Dictionary, u: SimUnit) -> void:
	var a: SimAction = (e["queue"] as Array)[e["idx"]]
	e["marks"] = []
	e["step"] = 0
	e["fired"] = false
	if a.type == SimConst.ACTION_MOVE_FIRE:
		var t: int = int(e["start"]) - 1
		for d in a.steps:
			t += u.step_cost(d)
			(e["marks"] as Array).append(t)


func _eval_shot(shooter: SimUnit, target_id: int) -> Dictionary:
	var target: SimUnit = state.units.get(target_id)
	if target == null or not target.alive:
		return {"result": "invalid", "reason": "no_target"}
	if target.team == shooter.team:
		return {"result": "invalid", "reason": "friendly"}
	return SimResolver.evaluate_shot(state.grid, shooter, shooter.pos, target, not _fired_this_round.has(shooter.id))


func _advance_queues(due: Array[int]) -> void:
	for id in due:
		if not _rt.has(id):
			continue
		var e: Dictionary = _rt[id]
		if e["start"] > tick:
			continue  # re-armed this tick by a morale check; its next order has not run yet
		e["idx"] += 1
		var queue: Array = e["queue"]
		if e["idx"] >= queue.size():
			_rt.erase(id)
			_note_idle(id)
			continue
		var u: SimUnit = state.units[id]
		e["start"] = tick + 1
		e["finish"] = tick + (queue[e["idx"]] as SimAction).cost(u)
		e["spent"] = false
		_arm(e, u)
		if e["finish"] > u.available_ticks():
			_rt.erase(id)
			_note_idle(id)


## A merc with ticks to spare that has nothing left to do. (Mercs that were
## never given orders are not "idle events"; only the transition counts.)
func _note_idle(id: int) -> void:
	var u: SimUnit = state.units[id]
	if u.alive and tick < u.available_ticks():
		last_idle.append(id)
