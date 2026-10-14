class_name SimPlan
extends RefCounted

var orders: Dictionary = {}  # unit id -> Array[SimAction]


func add(unit_id: int, action: SimAction) -> void:
	if not orders.has(unit_id):
		orders[unit_id] = []
	(orders[unit_id] as Array).append(action)


## A new plan holding both plans' orders (ids are expected to be disjoint).
func merged(other: SimPlan) -> SimPlan:
	var out := SimPlan.new()
	for src: SimPlan in [self, other]:
		for id in src.orders:
			for a: SimAction in src.orders[id]:
				out.add(id, a)
	return out


## Returns human-readable errors; empty means the plan is legal.
func validate(state: SimState) -> Array[String]:
	var errors: Array[String] = []
	for id in orders:
		var u: SimUnit = state.units.get(id)
		if u == null or not u.alive:
			errors.append("unit %d is not a living unit" % id)
			continue
		var total := 0
		for a: SimAction in orders[id]:
			if not a.is_valid_shape():
				errors.append("unit %d has a malformed %s action" % [id, a.type])
			total += a.cost(u)
		if total > u.available_ticks():
			errors.append("unit %d plans %d ticks but has %d" % [id, total, u.available_ticks()])
	return errors


## Extra planning rule under fog: a shot may only target an enemy the
## shooter's squad can currently see.
func validate_fog(state: SimState) -> Array[String]:
	var errors: Array[String] = []
	var seen := {}  # team -> visible unit ids
	for id in orders:
		var u: SimUnit = state.units.get(id)
		if u == null:
			continue
		if not seen.has(u.team):
			seen[u.team] = SimVision.visible_unit_ids(state, u.team)
		for a: SimAction in orders[id]:
			if a.type == SimConst.ACTION_SHOOT and not (seen[u.team] as Array).has(a.target_id):
				errors.append("unit %d targets unit %d, which its squad cannot see" % [id, a.target_id])
	return errors
