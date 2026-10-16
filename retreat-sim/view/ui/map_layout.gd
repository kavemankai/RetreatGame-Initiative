class_name MapLayout
extends RefCounted
## Where things sit on the overworld canvas. Pure: it turns the normalised positions in map.json into
## pixels for a given canvas size and finds which node a tap lands on. No drawing and no rules here.

const HIT_RADIUS := 34.0   ## px: the tap target around a node (a 68 px circle, above the 56 px minimum)
const CARD_HIT_RADIUS := 28.0


static func point(norm: Array, canvas: Vector2) -> Vector2:
	return Vector2(float(norm[0]) * canvas.x, float(norm[1]) * canvas.y)


## The pixel position of a mission node, or Vector2(-1, -1) if the map has none for it.
static func node_point(map: Dictionary, id: String, canvas: Vector2) -> Vector2:
	var nodes: Dictionary = map.get("nodes", {})
	if not nodes.has(id):
		return Vector2(-1, -1)
	return point(nodes[id], canvas)


## The pixel position of an act's contingency-card marker; later cards in the same act stack down.
static func card_point(map: Dictionary, act: int, index: int, canvas: Vector2) -> Vector2:
	var anchors: Dictionary = map.get("card_anchors", {})
	if not anchors.has(str(act)):
		return Vector2(-1, -1)
	return point(anchors[str(act)], canvas) + Vector2(0, 44 * index)


## What a tap at `at` hits: {"kind": "node"|"card", "id": ...} or {} if nothing. Nodes win over cards;
## the nearest wins when circles overlap.
static func hit_test(map: Dictionary, route: Dictionary, at: Vector2, canvas: Vector2) -> Dictionary:
	var best := {}
	var best_d := INF
	for n: Dictionary in route["nodes"]:
		var d := at.distance_to(node_point(map, n["id"], canvas))
		if d <= HIT_RADIUS and d < best_d:
			best_d = d
			best = {"kind": "node", "id": n["id"]}
	if not best.is_empty():
		return best
	var per_act := {}
	for c: Dictionary in route["cards"]:
		var act := int(c["act"])
		var index := int(per_act.get(act, 0))
		per_act[act] = index + 1
		var d := at.distance_to(card_point(map, act, index, canvas))
		if d <= CARD_HIT_RADIUS and d < best_d:
			best_d = d
			best = {"kind": "card", "id": c["id"]}
	return best
