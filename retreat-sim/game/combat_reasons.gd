class_name CombatReasons
extends RefCounted
## Player-facing wording for the reason codes ActionResolver and shot previews give.

const TEXT := {
	"encounter_over": "The fight is over.",
	"not_ready": "Wait for the current action to finish.",
	"not_your_activation": "Not your activation.",
	"dead_actor": "That unit is down.",
	"broken": "Broken: it cannot act until its next activation.",
	"suppressed": "Shaken: it cannot shoot until its next activation.",
	"no_target": "No valid target.",
	"not_visible": "Target not visible.",
	"out_of_range": "Out of range.",
	"too_close": "Too close for that weapon.",
	"no_los": "Line of sight blocked.",
	"not_enough_ap": "Not enough AP.",
	"unreachable": "Tile is unreachable.",
	"invalid_direction": "Pick a direction.",
	"unknown_action": "Unknown action.",
}


static func text(code: String) -> String:
	return String(TEXT.get(code, code.replace("_", " ").capitalize() + "."))
