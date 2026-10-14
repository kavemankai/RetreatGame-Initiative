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
## "planned" (simultaneous ticks) or "initiative" (action points, interrupts); chosen in the level test menu.
static var ruleset := "initiative"
## Playing the sandbox: leaving returns to its setup screen. The config outlives reset() so edits stick.
static var sandbox := false
static var sandbox_cfg: Dictionary = {}
## Set when a campaign match ends; the campaign screen applies it once.
static var pending_outcome: Dictionary = {}


static func in_campaign() -> bool:
	return campaign != null and current_match != null


static func reset() -> void:
	campaign = null
	current_match = null
	mission_id = ""
	withdrawn = false
	level_test = false
	ruleset = "initiative"
	sandbox = false
	pending_outcome = {}
