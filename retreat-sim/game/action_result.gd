class_name ActionResult
extends RefCounted
## What ActionResolver.submit returns. A rejected action has success == false, a `reason`
## code, and changed nothing.

var success := false
var reason := ""
var ap_before := 0
var cost := 0
var ap_after := 0
var events: Array = []
## True when this action ended the unit's activation (END_TURN, or its unit died).
var activation_ended := false
## Who is active after the action (-1 once the encounter is over).
var next_active := -1


static func rejected(p_reason: String) -> ActionResult:
	var r := ActionResult.new()
	r.reason = p_reason
	return r
