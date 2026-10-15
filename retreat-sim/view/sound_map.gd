class_name SoundMap
extends RefCounted
## Pure mapping from game events, themes and acts to sound names (files in
## res://assets/audio/<name>.wav, made by art/make_sounds.py). No playback here.

const AMBIENT := {
	"station_deck": "amb_deck", "hull_corridor": "amb_deck",
	"wreck_field": "amb_wind", "dock_ring": "amb_wind", "gate_frame": "amb_wind", "memorial_drift": "amb_wind",
	"garden_deck": "amb_garden", "hospital_hulk": "amb_hospital", "foundry_hold": "amb_foundry",
	"market_concourse": "amb_market", "relay_station": "amb_relay", "station_threshold": "amb_threshold",
}
const SHOT_VARIANTS := 3
const STEP_VARIANTS := 3
## Seconds after the crack that the impact, whizz or ping is heard.
const IMPACT_DELAY := 0.09
const MORALE_DELAY := 0.35
const DEATH_DELAY := 0.2
const HEAVY_DAMAGE := 2
## One sound per weapon class (rifles keep the three shot variants). A burst's bullets are spaced
## BULLET_GAP apart; a grenade that lands adds the blast.
const CLASS_SOUND := {"carbine": "sfx_shot_carbine", "sniper": "sfx_shot_sniper", "shotgun": "sfx_shot_shotgun",
	"heavy": "sfx_shot_heavy", "grenade": "sfx_shot_grenade", "beam": "sfx_shot_beam"}
const BULLET_GAP := 0.09
const BLAST_DELAY := 0.28


## What an event sounds like: [{"name", "delay"}], empty for silent events.
static func for_event(ev: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match ev["type"]:
		"shot":
			var result: String = ev["result"]
			if result == "invalid":
				return out
			var klass := String(ev.get("class", "rifle"))
			var lag := BULLET_GAP * float(int(ev.get("bullet", 0)))
			var heavy := result == "hit" and int(ev.get("damage", 1)) >= HEAVY_DAMAGE
			var variant := (int(ev["tick"]) + int(ev["unit"])) % SHOT_VARIANTS
			var shot_name: String = CLASS_SOUND[klass] if CLASS_SOUND.has(klass) else ("sfx_shot_heavy" if heavy else "sfx_shot_%d" % variant)
			out.append({"name": shot_name, "delay": lag})
			var follow: String = {"hit": "sfx_hit", "miss": "sfx_blocked" if ev.get("cover", false) else "sfx_miss", "blocked": "sfx_blocked"}.get(result, "")
			if follow != "":
				out.append({"name": follow, "delay": IMPACT_DELAY + lag})
			if klass == "grenade" and result == "hit":
				out.append({"name": "sfx_blast", "delay": BLAST_DELAY})
		"death":
			out.append({"name": "sfx_death", "delay": DEATH_DELAY})
		"morale":
			out.append({"name": "sfx_steady" if ev["result"] == "steady" else "sfx_broken", "delay": MORALE_DELAY})
		"move":
			out.append({"name": "sfx_step_%d" % ((int(ev["tick"]) + int(ev["unit"])) % STEP_VARIANTS), "delay": 0.0})
	return out


static func ambient_for(theme: String) -> String:
	return AMBIENT.get(theme, AMBIENT["station_deck"])


static func music_for(act: int) -> String:
	return "music_act%d" % clampi(act, 1, 3)


## Every sound name the game can ask for (tests check each file exists).
static func all_names() -> Array[String]:
	var names := {}
	for i in SHOT_VARIANTS:
		names["sfx_shot_%d" % i] = true
	for i in STEP_VARIANTS:
		names["sfx_step_%d" % i] = true
	for n in CLASS_SOUND.values():
		names[n] = true
	for n in ["sfx_blast", "sfx_shot_heavy", "sfx_hit", "sfx_miss", "sfx_blocked", "sfx_death", "sfx_steady", "sfx_broken",
			"sfx_equip", "sfx_loot", "ui_click", "ui_confirm", "ui_go", "stinger_win", "stinger_loss", "stinger_start"]:
		names[n] = true
	for v in AMBIENT.values():
		names[v] = true
	for act in range(1, 4):
		names[music_for(act)] = true
	var out: Array[String] = []
	for k in names:
		out.append(k)
	out.sort()
	return out
