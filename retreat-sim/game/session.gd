class_name Session
extends RefCounted
## What survives a scene change: the campaign, the match being played, and
## the outcome waiting to be applied by the campaign screen.

static var campaign: Campaign
static var current_match: SimMatch
static var mission_id := ""
static var withdrawn := false
## A throwaway campaign started from the menu's level test: finishing returns to the menu.
static var level_test := false
## "activation" (one unit at a time by initiative), "initiative" (live AP turns with interrupts)
## or "planned" (simultaneous ticks); chosen in the level test menu and the sandbox.
const RULESETS: Array[String] = ["activation", "initiative", "planned"]
const RULESET_LABEL := {
	"activation": "Activation (one unit at a time, AP)",
	"initiative": "Initiative (live AP turns, interrupts)",
	"planned": "Planned (simultaneous ticks)",
}
static var ruleset := "activation"
## Playing the sandbox: leaving returns to its setup screen. The config outlives reset() so edits stick.
static var sandbox := false
static var sandbox_cfg: Dictionary = {}
## A battle restored from the autosave (ResumeStore), waiting for the battle screen to pick it up.
static var resume_cs: CombatState
## Set when a campaign match ends; the campaign screen applies it once.
static var pending_outcome: Dictionary = {}


static func next_ruleset(current: String) -> String:
	return RULESETS[(RULESETS.find(current) + 1) % RULESETS.size()]


## The "planned" ruleset has its own screen; the other two share the initiative screen.
static func scene_ruleset_is_planned(r: String) -> bool:
	return r == "planned"


static func in_campaign() -> bool:
	return campaign != null and current_match != null


static func reset() -> void:
	campaign = null
	current_match = null
	mission_id = ""
	withdrawn = false
	level_test = false
	ruleset = "activation"
	sandbox = false
	resume_cs = null
	pending_outcome = {}
