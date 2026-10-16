# Game design: The Long Retreat (as shipped in 1.0.0)

The authoritative world text is `STORY_BIBLE.md`; combat rules are in `MECHANICS_SPEC.md` and `docs/combat/initiative-combat-spec.md`; this page says what the finished game is.

## Pitch
The war is over and nobody has told the army. You command the 9th Rearguard, the last real people in a ghost army, escorting 6,200 civilians (the Procession) along the Reliquary Lanes toward a refuge that may not let you in. Behind you comes Provost Orrick, who only wants you to be counted. When a named merc dies, a faceless hollow takes the slot (the Muster Law).

## Player loop
Overworld map -> pick the next stop -> mission prep (briefing, squad, loadout) -> tactical fight -> result and salvage -> level-ups -> roll call for the dead -> debrief and a choice -> map. A fight is one phone-screen battle of about 8-15 minutes.

## Tactical rules (activation engine)
- Rounds; units act one at a time in seeded initiative order (`speed*10 + aim`, tie die, then id). The order strip shows only what the squad can see.
- 14 AP per activation: step 2 (diagonal 3), shot 4, overwatch 4. Overwatch gives one free shot at the first enemy to enter the cone.
- Tap once to preview (route and AP, or exact hit chance and damage), tap again to commit. Red route steps are where a visible enemy would shoot first.
- Half cover takes 30 off the hit chance; full walls block. Holding fire digs in (+10 per activation up to +20), shooting from cover wears it down, a step resets it.
- Weapon classes: rifle, carbine, sniper, shotgun, heavy (incl. minigun burst), grenade (area, hurts allies), beam (ignores half cover and range falloff).
- Morale: hits shake and break units; hollows never break.
- Enemy roles: sentry (holds a lane on overwatch), guard (holds a tile), patrol (pushes), plus timed reinforcements.

## Campaign
12 story missions in three acts plus 8 contingency cards (one is drawn per act).
| Act | Missions |
|---|---|
| 1 The Breakout | Karsa Breakout (breakout), The Weir (scavenge), Pellam Dock (defend), Orchard Ring (rescue) |
| 2 The Counting | Quiet Wards (defend), Anselm (infiltrate), Cinder Market (extract), Mirror Gate (hold) |
| 3 The Door | Reliquary Lane (ambush), Long Corridor (last stand), Tamsin's Rest (infiltrate), Vesper Threshold (finale) |

Resources: **Procession** (civilians; failure costs lives), **Reserves** (hollow refills), **Remembrance** (names read at roll calls). Losing the whole squad, all reserves, or the Procession ends the run. The finale offers four choices that resolve to one of four endings: The Roll Read, Orrick's Rest, Quiet Terms, The Long Watch. Total squad loss ends the campaign (restart from the menu).

## Roster
Warden, Gran, Sable, Needle, Bulwark, Moth at the start; Wren (grenade launcher) joins at Orchard Ring and Ghost (beam) at Cinder Market. Each merc is locked to a weapon class; each of the five level-ups offers three seeded +1 stat steps, pick one.

## Difficulty (new in 1.0.0)
Chosen on the main menu before "New campaign", saved with the run.
- **Standard:** the designed fight.
- **Story:** your units have +1 hit point and every enemy has -15 accuracy. Same missions, same endings.
Measured with the stand-in AI squad on fresh gear (40 battles each): Long Corridor 24 wins on Standard, 37 on Story; Vesper Threshold 1 on Standard, 32 on Story. Human performance is not measured.

## First-mission coach (new in 1.0.0)
In the first mission of a fresh campaign a blue tip replaces the rules line and changes as the player acts: two-tap move, shot preview, confirm, AP and End Activation, overwatch.

## Presentation
Isometric pixel board with 12 themed tile sets, merc and enemy sprites with idle/move/aim/fire/hit/fall, class-specific tracers and muzzle flashes drawn in code, 38 synthesised sound files (shots per class, hits, cover, steps, UI, three music beds, eight ambiences), ambient and music chosen by theme and act, mute toggle. Screens are code-built Controls sized for 540x960 and checked at 360x800 and 960x540.

## Out of scope for 1.0.0
Stances, aimed shots, ammo, wounds, doors/patrols/hostages, pinch zoom, volume sliders. See `docs/REMAINING_ISSUES.md`.
