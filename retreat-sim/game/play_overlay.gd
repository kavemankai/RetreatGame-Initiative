class_name PlayOverlay
extends RefCounted
## Everything the planning screen draws on top of the board, built from the
## controller. Pure data (no nodes), so it can be inspected in tests.

const COL_OWN := Color("8fd0ff")
const COL_ENEMY := Color("ff8a8a")
const COL_FIRE := Color("ff9f43")
const COL_PREVIEW := Color(1, 1, 1, 0.75)
const COL_PREVIEW_HIT := Color("7bf08a")
const COL_PREVIEW_BLOCKED := Color("f2b134")


## Returns {"overlay": Dictionary, "watchers": Array[Dictionary], "fog": Dictionary}.
static func build(c: PlayController) -> Dictionary:
	var state := c.game.state
	var team := c.game.player_team
	var overlay := {"selected": c.selected, "paths": [], "shots": [], "ghosts": [], "reachable": {}, "pending": c.pending, "marks": []}
	var watchers: Array[Dictionary] = []
	if c.selected >= 0:
		overlay["reachable"] = c.builder.reachable_fire(c.selected) if c.mode == PlayController.MODE_MOVE_FIRE else c.builder.reachable(c.selected)
	_own_plan(c, overlay, watchers)
	_enemy_intent(c, overlay, watchers)
	_pending(c, overlay, watchers)
	var units := {}
	for id in SimVision.visible_unit_ids(state, team):
		units[id] = true
	return {"overlay": overlay, "watchers": watchers, "fog": {"tiles": SimVision.visible_tiles(state, team), "units": units}}


static func _own_plan(c: PlayController, overlay: Dictionary, watchers: Array[Dictionary]) -> void:
	var view := c.builder.view()
	for id in c.builder.own_unit_ids():
		var moved := false
		for e: Dictionary in c.builder.entries_for(id):
			match e["kind"]:
				"move":
					overlay["paths"].append({"tiles": e["path"], "color": COL_OWN})
					moved = true
				"shoot":
					var target: SimUnit = view.units.get(e["target"])
					if target != null:
						overlay["shots"].append({"from": e["pos"], "to": target.pos, "color": COL_OWN})
				"overwatch":
					watchers.append({"id": id, "dir": e["facing"], "spent": false, "pos": e["pos"]})
				"move_fire":
					overlay["paths"].append({"tiles": e["path"], "color": COL_FIRE})
					moved = true
		_ticks_marks(c, id, overlay)
		if moved:
			overlay["ghosts"].append({"id": id, "team": c.game.player_team, "tile": c.builder.projected_pos(id)})


## Orders of visible enemies, drawn dashed in red (the AI has already planned).
static func _enemy_intent(c: PlayController, overlay: Dictionary, watchers: Array[Dictionary]) -> void:
	var state := c.game.state
	var intent := c.game.enemy_intent()
	for id in intent.orders:
		var u: SimUnit = state.units[id]
		var pos := u.pos
		var tiles: Array[Vector2i] = [pos]
		for a: SimAction in intent.orders[id]:
			match a.type:
				SimConst.ACTION_MOVE:
					pos += a.dir
					tiles.append(pos)
				SimConst.ACTION_SHOOT:
					var target: SimUnit = state.units.get(a.target_id)
					if target != null:
						overlay["shots"].append({"from": pos, "to": target.pos, "color": COL_ENEMY})
				SimConst.ACTION_OVERWATCH:
					watchers.append({"id": id, "dir": a.dir, "spent": false, "pos": pos})
		if tiles.size() > 1:
			overlay["paths"].append({"tiles": tiles, "color": COL_ENEMY, "dashed": true})


## The not-yet-committed order from a first tap, drawn lighter than real ones.
static func _pending(c: PlayController, overlay: Dictionary, watchers: Array[Dictionary]) -> void:
	var p := c.pending_preview()
	match p.get("kind", ""):
		"move":
			overlay["paths"].append({"tiles": p["path"], "color": COL_PREVIEW, "dashed": true, "preview": true})
		"shot":
			var col: Color = COL_PREVIEW_HIT if p["result"] == "hit" else (COL_PREVIEW_BLOCKED if p["result"] == "blocked" else COL_PREVIEW)
			overlay["shots"].append({"from": p["from"], "to": p["to"], "color": col, "preview": true})
		"overwatch":
			watchers.append({"id": c.selected, "dir": p["facing"], "spent": false, "pos": p["pos"]})
		"move_fire":
			overlay["paths"].append({"tiles": p["path"], "color": COL_PREVIEW, "dashed": true, "preview": true})
			var mcol: Color = COL_PREVIEW_HIT if p["result"] == "hit" else (COL_PREVIEW_BLOCKED if p["result"] == "blocked" else COL_PREVIEW)
			overlay["shots"].append({"from": p["from"], "to": p["to"], "color": mcol, "preview": true})


## A small "t8" beside where each queued action completes, so the plan reads as
## a schedule. Shown for the selected merc, or for everyone when none is selected.
static func _ticks_marks(c: PlayController, id: int, overlay: Dictionary) -> void:
	if c.selected >= 0 and c.selected != id:
		return
	var entries := c.builder.entries_for(id)
	var line := c.builder.timeline(id)
	var lanes := {}
	for i in entries.size():
		var tile: Vector2i = entries[i]["pos"]
		var lane: int = int(lanes.get(tile, 0))
		lanes[tile] = lane + 1
		overlay["marks"].append({"tile": tile, "text": "t%d" % int(line[i]["end"]), "lane": lane, "id": id})
