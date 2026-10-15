class_name CoachModel
extends RefCounted
## The first-mission coach: pure rules for which single tip to show, from what the player has already done.
## The battle screen tracks the facts and draws the text; nothing here touches the scene tree.

## `facts`: moved, enemy_in_sight, previewed_shot, shot, ended, watched, over (all bool), and ap (the activation budget).
## Returns "" when there is nothing to say.
static func tip(facts: Dictionary) -> String:
	if bool(facts.get("over", false)):
		return ""
	var enemy := bool(facts.get("enemy_in_sight", false))
	var shot := bool(facts.get("shot", false))
	if enemy and not shot:
		if bool(facts.get("previewed_shot", false)):
			return "Tap the same enemy again to fire."
		return "An enemy is in sight. Tap it once to see your hit chance and damage."
	if not bool(facts.get("moved", false)):
		return "Tap a tile once to see the route and its AP cost, then tap it again to go. Red steps are where an enemy would shoot first."
	if not shot:
		return "Walls and crates lower enemy hit chances. Move from cover to cover and let them come to you."
	if not bool(facts.get("ended", false)):
		return "Each merc has %d AP per activation. Spend what you need, then tap End Activation to pass." % int(facts.get("ap", 14))
	if not bool(facts.get("watched", false)):
		return "Overwatch (4 AP) gives one free shot at the first enemy that moves into view. Holding fire also digs you in."
	return ""


## The coach runs only in the very first mission of a fresh campaign, never in a level test, a
## replay of a finished mission, or the sandbox.
static func applies(campaign: Campaign, mission_id: String, level_test: bool) -> bool:
	if campaign == null or level_test:
		return false
	return mission_id == String(campaign.story["route"]["start"]) and campaign.completed.is_empty()
