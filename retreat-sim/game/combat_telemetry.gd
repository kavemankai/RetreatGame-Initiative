class_name CombatTelemetry
extends RefCounted
## Combat numbers read back from a CombatState's event log and AP ledger: the pacing and AP
## figures the plan asks to record for calibration (shots per activation, AP wasted, steps).


## {"activations", "ap_offered", "ap_spent", "ap_forfeited", "shots", "hits", "reactions", "steps",
##  "moves", "kills", "actions", "rounds"} for the encounter so far.
static func summarize(cs: CombatState) -> Dictionary:
	var t := {"activations": 0, "ap_offered": 0, "ap_spent": 0, "ap_forfeited": 0, "shots": 0, "hits": 0, "reactions": 0,
		"steps": 0, "moves": 0, "kills": 0, "actions": 0, "rounds": cs.round_no}
	for e: Dictionary in cs.log:
		match e["type"]:
			"activate":
				t["activations"] += 1
				t["ap_offered"] += int(e["ap"])
			"end_turn":
				t["ap_forfeited"] += int(e["forfeited"])
			"move":
				t["steps"] += 1
			"shot":
				t["shots"] += 1
				t["hits"] += int(e["result"] == "hit")
				t["reactions"] += int(e.get("reaction", false))
			"death":
				t["kills"] += 1
	for row: Dictionary in cs.ledger:
		t["ap_spent"] += int(row["cost"])
		if row["type"] == CombatAction.MOVE:
			t["moves"] += 1
		if row["type"] != CombatAction.END_TURN:
			t["actions"] += 1
	return t


## Fractions worth reading: AP wasted, shots and steps per activation, hit rate.
static func ratios(t: Dictionary) -> Dictionary:
	var acts := maxf(1.0, float(t["activations"]))
	return {"ap_wasted": float(t["ap_forfeited"]) / maxf(1.0, float(t["ap_offered"])),
		"shots_per_activation": float(t["shots"]) / acts, "steps_per_activation": float(t["steps"]) / acts,
		"actions_per_activation": float(t["actions"]) / acts, "hit_rate": float(t["hits"]) / maxf(1.0, float(t["shots"]))}
