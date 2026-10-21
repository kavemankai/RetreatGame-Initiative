# The Long Quiet: design for a humans-versus-creatures version of The Long Retreat

Status: design only, nothing built. Written 2026-10-21 as an alternative to `docs/JA2_COMBAT_PLAN.md`. Where the two disagree, this page is the newer proposal and the owner decides.

## 1. Pitch

The Compact's hollows were never alive. They were vat-grown bodies kept on a leash called the Tether so the army could look full on paper. When Karsa Station fell, the Tether net broke. Every hollow in the fleet, tens of thousands parked in cargo holds as "strength", woke with nobody holding the other end. They are called the Slack. They follow sound.

You still command the 9th Rearguard, escorting the Procession toward the sealed refuge at Vesper Reach. Behind you the Slack move down the Reliquary Lanes as one slow mass, the Tide. Ahead of you every dead ship is full of them, asleep. You cannot kill them all. You do not have the bullets. The game is about moving through them without being heard, and about what you do when you are.

One line for the store page: a retreat where every gunshot is a decision, because the thing that kills you is listening.

## 2. What stays, what changes

The engine already does most of what a zombie game needs: initiative order, AP, overwatch, fog of war, cover, morale, permadeath, a deterministic sim, phone-first two-tap controls. Those stay. The setting, the enemy, and four rules change.

| Area | The Long Retreat today | The Long Quiet |
|---|---|---|
| Enemy | Hegemony troops, Writ officers, Orrick | Creatures (the Slack and what they become) |
| Hollows | Replacement bodies on your side | The enemy. Your dead can rise against you |
| Core tension | Hit chance, cover, who shoots first | Noise: every action is audible, loud actions pull the horde |
| Ammo | None (excluded) | Finite. Magazines, reload, no free refills |
| Injury | None (excluded) | Bites infect. A clock, then a choice |
| Reinforcements | Timed | Driven by the Pressure bar, which you fill by being loud |
| Pursuer | Orrick, ahead of the story | The Tide, a gap number that shrinks when you waste time |
| Replacements | Reserves fill dead slots with hollows | Volunteers from the Procession fill dead slots (weaker, shaky morale) |
| Doors, barricades, crouching | Not in the engine | In, and central |
| Faction colour | Amber vs teal | Amber vs a dead teal glow (the Tether harness on every Slack) |

Reversals of earlier decisions, stated plainly so nobody finds them later. `FEATURE_COMPARISON.md` excluded ammo because it "adds bookkeeping, not decisions". In this design ammo is the decision, because it prices noise. The "no injury system" ruling from 2026-10-15 is reversed for one injury only: the bite. There is no bleeding and no wound tracking. The JA2 plan's removal of the narrative is also reversed here, because the Hollowing becomes the creature origin and the story is what separates this from a generic zombie shooter.

## 3. The pillar: noise

Every action emits noise. Noise has a radius in tiles. Creatures hear it and walk to where it came from. That is the whole system, and everything else in this document hangs off it.

### 3.1 Noise values (starting numbers, all tunable in data)

| Action | Radius |
|---|---|
| Step, standing | 3 |
| Step, crouched | 1 |
| Heavy kit (Bulwark) | +1 to steps |
| Reload | 1 |
| Melee kill | 2 |
| Melee, enemy not dead | 3 |
| Suppressed or crossbow shot | 4 |
| Hammering a barricade | 4 |
| Carbine, rifle | 10 |
| Sniper, shotgun | 12 |
| Heavy gun burst | 14 |
| Grenade or explosion | 14 |
| Thrown noisemaker | 8, at the tile it lands on |
| A creature bashing a barricade | 5 |
| A Caller's scream | 14 |

A unit that acts several times in one activation emits only its loudest noise once, so a long quiet walk costs one pulse, not twelve.

### 3.2 How noise travels

Noise floods outward over walkable tiles at integer cost, so it follows corridors and leaks around corners the way real sound does. Open tile: 1. Half wall: 1 extra. Closed door: 3 extra. Full wall: 6 extra. If the radius runs out, the sound dies. No floats, same tiles and seed give the same result on any device, which keeps the sim deterministic like the rest of `sim/`.

### 3.3 How creatures react

Each creature pack is in one of four states.

- **Dormant.** Asleep in place. Wakes only on noise of radius 8 or more reaching it, or a human within 2 tiles in sight.
- **Wandering.** Drifts between waypoints. Reacts to any noise reaching it.
- **Alert.** Heard something. Walks to the loudest noise (nearest breaks ties), then searches for one round.
- **Hunting.** Has sight of a human. Chases, and keeps chasing for four rounds after sight is lost.

A pack that arrives at a noise and finds nothing goes back to Wandering. So retreating works. Breaking line of sight and staying quiet for a few rounds sheds a pack. That is the stealth loop.

### 3.4 Pressure

A bar at the top of the battle screen, 0 to 18, with notches at 6, 12 and 18. Each loud shot (radius 10 or more) adds 1. Explosions and heavy bursts add 2. A scream adds 3. Each round in which the squad emits nothing above radius 3 removes 1. When a notch is passed, a fresh pack enters from a marked breach point at the map edge. The player sees an arrow and a two-round warning ("Something is coming from the east") before it arrives.

This replaces the engine's timed reinforcements. Same machinery, but now the player causes it. A careful squad on a hard map sees one horde. A trigger-happy squad on an easy map sees three.

### 3.5 The player's tools for noise

- **Crouch.** 2 AP to toggle, steps cost +1 AP, noise drops to radius 1, and Slack see a crouched unit only within 2 tiles. Borrowed from phase 1 of the JA2 plan, minus prone.
- **Quiet kill.** A melee attack on a Dormant or Wandering creature that has not noticed the squad is an automatic kill, noise radius 2. This is the stealth reward and the reason Needle exists.
- **Lure.** Throw a noisemaker (a can, a flare, a distress beacon) up to 6 tiles for 3 AP. It emits noise 8 at the landing tile. Packs go there. Walk the other way.
- **Doors.** Open or close for 1 AP. A closed door cuts sound and sight. Close it behind you.
- **Barricade.** 5 AP and one plank turn a door tile into a full wall with 3 HP. Each creature that bashes it removes 1. Bashing is loud, so a barricade buys time and also calls friends.
- **Suppressed and silent weapons.** Slow, weak, quiet. The cost of staying quiet is killing slower.

### 3.6 The honest problem with noise

Noise is hidden information. If a player shoots and the screen later fills with creatures they never saw coming, they will feel cheated, not outplayed. So the UI must show it. Section 10 covers how. If it cannot be made legible on a phone, the pillar fails and the game is an ordinary zombie shooter.

## 4. Combat changes

### 4.1 Keep

Activation order by `speed*10 + aim`, 14 AP per activation, step 2 (diagonal 3), shot 4, overwatch 4, two-tap move and fire, the hit chance formula (`35 + 7*aim`, minus 4 per tile past range 2, clamped 10 to 95), half cover minus 30, dug-in cover, fog of war, morale on hit.

### 4.2 Packs, not individual creatures

The activation engine gives every unit its own turn. With 30 creatures on screen that is unreadable and slow on a phone. So creatures act in **packs**: 1 to 8 creatures of one type that share a single activation and a single decision. The order strip shows a pack as one chip with a count. A pack moves its members one after another with a short staggered animation. A cap of 24 live creatures per map keeps the phone playable, and anything beyond the cap waits in a spawn queue.

Pack initiative is the leader's `speed*10 + aim`. Slack are slow, so they usually act after the squad, which is what makes retreat and kiting possible.

### 4.3 Creatures bite, they do not shoot

Most creatures are melee. Cover therefore does less. A unit behind a full wall or a barricade is safe until the barrier falls. A unit in the open next to a creature is bitten.

- **Bite chance** against a human: 75 minus 4 per point of the human's cqb, minimum 20.
- **Bite damage:** 1 (Hulk: 2).
- **Infection chance on a bite that lands:** 50%, minus the armour's bite resistance.
- Humans have 2 to 4 HP, so three bites usually kill. Killing is the lesser risk. The infection is the real one.

### 4.4 Melee for humans

3 AP, range 1, noise radius 2 on a kill. Hit chance `55 + 5*cqb`, clamped 10 to 95. A machete or axe is a weapon-slot item with no ammo. This gives every merc a quiet fallback that costs HP risk instead of rounds, and it makes Needle (cqb 9) the squad's knife.

### 4.5 Ammo and reload

Each weapon has a magazine. Reload costs 4 AP and takes a magazine from the merc's pouch. A merc carries a loaded magazine plus two spare. Starting capacities (tunable):

| Class | Mag | Burst or note |
|---|---|---|
| Rifle | 8 | |
| Carbine | 10 | |
| Sniper | 5 | |
| Shotgun | 4 | close range cone |
| Heavy | 20 | a burst uses 3 |
| Launcher | 3 | area |
| Crossbow | 1 | silent, bolts are recoverable from bodies |

Ammo is tracked per merc as a counter ("8 + 16"), not a grid. The earlier objection to ammo was bookkeeping. A counter on the merc card is not a spreadsheet.

Design target: a mission's creature count should be about one and a half times the squad's loaded rounds. The rest must be handled by melee, fire, doors, lures and avoidance. If a squad can shoot its way through, the ammo is too generous.

### 4.6 Overwatch

Still 4 AP, still one free shot at the first thing to enter the cone. Now the shot is loud. Overwatch becomes a risky sentry tool, not a free guard. A suppressed weapon on overwatch is the quiet version.

### 4.7 Morale

Humans keep the existing morale check, and it fires on new triggers: a Caller's scream, three or more creatures in sight, a squadmate turning. Broken units cannot shoot and halt. Creatures never break, as hollows never did.

## 5. The Turning (infection)

A bitten merc with a successful infection roll is Infected and gets a visible clock of 12 rounds. Rounds pass in fights. Between missions, camp counts as 4 rounds. When the clock hits zero the merc dies and rises on the creature side as a **Fresh** (fast runner) carrying the dead merc's last weapon, in the middle of the fight if the clock ran out mid-mission.

Three options for an Infected merc, each costing something.

- **Sera.** A rare one-dose antiviral. Stops the clock. Scarce enough that there are fewer doses than bitten mercs.
- **Put them down.** Tap Mercy. The merc dies as a human, with gear recovered, and counts toward Remembrance if their name is read. Costs the merc and the squad's morale.
- **Gamble.** Keep fighting. The merc has full stats until the clock ends. This is the interesting choice on turn one of a fight: a doomed merc who can still carry the rear guard.

A merc who dies unreadable on the field (not recovered, not mercy-killed) is not safe either. See the Named below.

## 6. The Named and the Roll Call

The old game's Roll Call let the squad read a dead merc's name aloud for Remembrance, with no mechanical effect. Here it matters.

After a death the squad can **Lay them to rest**: read the name, spend one burial charge (a medical kit variant), gain Remembrance. That merc never returns. Or they can **Leave them**: free, no Remembrance. A merc left unrested can come back in a later mission as a **Named**, an elite Slack with the old merc's callsign, 60% of their stats and their old weapon. The cast data already carries a `hollow_note` per merc ("It walks with her limp", "Its hands still count to four before it fires"). Those lines become the Named's behaviour tell and its introduction text, with no new writing needed.

So the player's choice at camp reaches the battlefield. This is the closest thing the design has to a signature mechanic besides noise, and it is the original game's Hollowing turned inside out: your dead no longer fill your roll, they come for it.

## 7. Creature roster

Existing stat blocks (`hp, speed, aim, cqb, morale, sight`) cover the humans. Creatures add **move** (tiles per activation) and **hearing** (noise radius they respond to). Numbers are starting values.

| Creature | In-world name | HP | Move | Notes | First act |
|---|---|---|---|---|---|
| Walker | Slack | 1 | 3 | Slow, sight 4, hearing 8. One hit kills. Numbers are its threat | 1 |
| Runner | Fresh | 1 | 6 | Sight 6, hearing 10. Matches human speed, so you cannot outrun it. A turned merc comes back as one | 1 (late) |
| Crawler | Drag | 1 | 2 | Low. Hidden in fog until within 2 tiles. Cannot be targeted through half cover. Pins its victim: the unit cannot move until the Drag is dead | 2 |
| Screamer | Caller | 1 | 2 | No attack. Flees humans. On sight of one, it screams (noise 14, Pressure +3, morale check on every human that sees it). First thing to kill | 2 |
| Bloater | Swell | 3 | 2 | Bursts when killed. Spores on its tile and the eight around it for 2 rounds, 1 damage and an infection chance, creatures immune. Kill it at range 4 or more | 2 |
| Brute | Hulk | 6 | 3 | Bite does 2. Smashes a barricade in one round and a half wall in two. Armoured: each hit does 1 unless from a sniper, a close shotgun or an explosive | 3 |
| Spitter | Weeper | 2 | 3 | Ranged acid, range 5, ignores cover. Strips the target's dug-in cover and lowers its armour's bite resistance by 1 | 3 |
| Spawner | The Nest | 8 | 0 | Fixed. Sleeps until loud noise wakes it, then spawns one Slack pack each round. Destroy with explosives or fire | 3 |
| Named | the dead merc's callsign | 60% of merc | 3 | Elite Slack with their old weapon and a behavioural tell | 2+ |

Fire is a creature answer. A flame or incendiary weapon (see Ghost below) puts fire on tiles for 3 rounds. Creatures path around fire, take 1 damage crossing it, and fire blocks a corridor without spending a plank.

## 8. Roster and classes

Eight playable mercs, the shipped cast, with new weapon roles. The story bible's other four (Quill, Static, Pilgrim, Tinker) remain unplayable but their sprites exist; they are candidates for volunteers or NPC survivors.

| Merc | Class today | Class here | Role in the new game |
|---|---|---|---|
| Warden | rifle | rifle | The steady middle. Commander. Reads the names |
| Gran | rifle | rifle | The veteran. Highest morale, holds the rear |
| Sable | sniper | sniper | Long range, 5-round mag, loud. Must be placed with care |
| Needle | shotgun | melee and shotgun | Fast, cqb 9. The quiet-kill specialist and the door breaker |
| Bulwark | heavy | heavy | Slow, 4 HP, burst gun. Loudest merc. A walking Pressure generator |
| Moth | carbine | crossbow and carbine | Sight 8. The scout and lure thrower. Crossbow keeps her silent |
| Wren | grenade | launcher | Area. Dangerous near Swells. Joins at Orchard Ring |
| Ghost | beam | flamer or incendiary | Fire area denial. Ex-Bureau, knows what the Slack are. Joins at Cinder Market |

Gear: the three slots stay (armour, weapon, mod). Armour gains **bite resistance**. Compact vest 10%, plate carrier 20%, ablative coat 30%, Gavel's plate is retired. New mods: **suppressor**, **flashlight** (sight +2, but doubles the radius at which Slack see you), **barricade kit** (two free planks). Items stay data in `items.json`.

## 9. Campaign

### 9.1 Resources

Three numbers, as before, with one new one.

- **Procession.** Survivors in the convoy, starts at 6,200. Failed escorts and being overrun cost lives.
- **Volunteers.** Replacements for dead mercs, starts at 12. A volunteer has 60% of the dead merc's stats and morale 3. Costs one Volunteer. If you have none, the slot stays vacant, as Reserves worked.
- **Remembrance.** Names read. Never spent.
- **The Tide gap.** Distance between the convoy and the horde behind it, as a number from 0 to 12, starting at 8. A mission that goes quickly and quietly preserves it. A long, loud mission costs 1 or more. Sabotage objectives can add 1. At 0 the next mission becomes an Overrun (last stand at the loading dock, no stealth).

The Tide gap replaces Orrick as the thing chasing you.

### 9.2 Route

Keep the 12 stops, three acts, the 8 contingency cards, and the existing 12 maps and 12 art themes. Missions recast as below.

| Act | Mission | Theme | Recast |
|---|---|---|---|
| 1 The Breakout | Karsa Breakout | station deck | Reach the lock through a dormant station. Teaches crouch, doors, quiet kills |
| 1 | The Weir | wreck field | Three caches (rounds, kits, planks) among sleeping packs. Greed is noise |
| 1 | Pellam Dock | dock ring | Hold the gantries while the convoy boards. The first real horde, from Pressure |
| 1 | Orchard Ring | garden deck | Escort survivors who are slow and panic when they see a Slack. Wren joins |
| 2 The Quiet | Quiet Wards | hospital hulk | Stealth ward with a Caller. Find sera. A mission built to be done silently |
| 2 | The Anselm | foundry hold | The vat hall. Creatures come out of the vats. Destroy them or take the key |
| 2 | Cinder Market | market concourse | Drags in the stalls. Ghost joins. Trade with the market's survivors |
| 2 | Mirror Gate | gate frame | Hold the frame for forty rounds of waves. Pressure runs at maximum |
| 3 The Door | Reliquary Lane | memorial drift | Long sightlines. The Tide's vanguard crosses the lane. Swells and a first Hulk |
| 3 | The Long Corridor | hull corridor | Last stand with creatures from both ends. The first Named appears |
| 3 | Tamsin's Rest | relay station | Read the archive and learn what the Roll really was. Weepers. The Nest is here |
| 3 | Vesper Threshold | station threshold | The finale at the door |

### 9.3 The door

The refuge keeps the old rule: no weapons, no Tethers. It adds a test. The Keepers count everyone through the door, and the count checks for the Echo. Anyone Infected is refused. Squad members with a live clock cannot enter. The final choice is who you spend your last sera on, and who stays outside.

### 9.4 Endings

1. **The Roll Read.** High Remembrance, the Archive read, the Nest destroyed. The Procession enters. The squad reads the whole Roll at the door and the Slack, with their Tether finally cut, stop and stand.
2. **The Long Watch.** The squad holds the door for forty years. Names go in and the squad slowly dies and rises.
3. **The Decoy.** The Keepers take the Procession. The squad leads the Tide away on purpose.
4. **The Last Host.** Take the Nest's voice alive, the one Slack that still has a fragment of a person. What happens to it is the last choice.

## 10. Phone UI

The existing screens stay. New elements, all designed for a 540x960 portrait screen.

- **Noise preview.** When a shot or move is previewed, a diamond ring spreads from the unit on the iso board to the radius the action will emit, tinted by loudness. Previews carry a LOUD or QUIET chip. Nothing is a surprise.
- **Heard-but-unseen markers.** A creature noise outside sight leaves a dim "?" with a bearing arrow at the board edge, lasting one round. The player can hear what they cannot see.
- **Pressure bar** at the top with notches, and a pulsing breach arrow when a pack is two rounds out.
- **Ammo counter** on each merc card ("8 + 16") and a Reload button when the merc is out.
- **Order strip** shows packs as a single chip with a count.
- **Infection clock** on a bitten merc, a red number in place of an HP pip.
- **Door and barricade buttons** appear when the selected merc stands next to a door.

Everything stays two taps: preview, then commit.

## 11. Art and audio

The art pipeline is already built, so most of this is reuse.

- **Reused as is:** the 8 playable merc sprite sets, the 12 theme tile sets, the tracers and muzzle flashes, the iso board renderer.
- **Reused with a new role:** the existing Hollow sprite (faceless grey figure with the slot number) becomes the Slack. It already looks right. Teal Hegemony trim is replaced by a dead teal Tether light at the neck, flickering on a Slack and flaring on a Caller.
- **New sprite sets (about seven):** Fresh, Drag, Caller, Swell, Hulk, Weeper, Nest. Named reuses the merc's own sprite, grey and with the teal light.
- **New props:** doors (open and closed), barricade, sleeping-creature poses, vat growth overlays, a fire tile.
- **New FX in code:** noise rings, pack movement, spore cloud.
- **Audio:** the sound is half the game. New: bite, groan variants, bash, scream, noisemaker clink, door, reload, a heartbeat layer as Pressure rises. Gunshots must be audibly huge against an otherwise near-silent bed. The 38 existing files cover steps, shots and ambience, and the shot sounds should be pushed louder against the new quiet.

Tone stays hushed and concrete. This is not a gore game. Violence is fast and quiet, death is unglamorous, and the horror is that the enemy is the army's own bookkeeping.

## 12. Comparisons

- **Zombicide** (board game): noise and spawning at the map edge. Closest on the horde logic. This game is single-player, authored, and has a story.
- **XCOM:** overwatch, cover, small named squads, permadeath. The shell is the same.
- **The Banner Saga:** a caravan of civilians in retreat, resources bleeding away. Closest on the campaign.
- **They Are Billions:** a horde that overwhelms a defence. Here the horde is a clock, not a base-defence puzzle.
- **This War of Mine:** scarcity and the moral cost of survival. The Roll Call and the Volunteers play in that register.
- **Left 4 Dead:** the AI Director that spawns hordes in response to the players. Pressure is a visible, simple version of it.
- **Project Zomboid, Dying Light, State of Decay:** sound draws the dead. Same rule, turn-based and on a phone.
- **Jagged Alliance 2:** the AP and initiative core the engine started from.

The honest read: the genre is crowded, and a turn-based phone zombie game with ammo is not new. What is new is the combination: noise as the central verb, a hollow mirror in the Named, and a retreat structure with a visible pursuer. If those do not land, it is a reskin.

## 13. Reuse map

| Layer | Status |
|---|---|
| Sim core (grid, LOS, vision, pathing, dice, resolver) | Kept. Add noise flood, hearing, doors, melee |
| Activation engine (state, scheduler, resolver) | Kept. Add pack activation, stance, reload, barricade, throw, mercy |
| `SimAI` and `ActivationAI` | Kept for the human side of tests. New creature AI for packs and noise states |
| Campaign (`campaign.gd`) | Changed. Reserves to Volunteers, Hollowing to Turning and Named, new Tide gap, Roll Call mechanics |
| Story data (cast, scenes, route, world, writ) | Cast kept. Writ and Orrick removed. Scenes rewritten for the creature plot. Route kept, goals recast |
| Items | Kept. Add ammo, bite resistance, melee weapons, planks, noisemakers |
| Maps | The 4 redesigned Act 1 maps kept. Acts 2 and 3 still need real maps either way, now with doors and breach points |
| Views | Board, screens, order strip kept. Add noise rings, pressure bar, ammo, door buttons, pack chips |
| Tests and soak tools | Kept as the pattern. A creature-aware soak is needed (see risks) |

## 14. Build order (no code in this pass)

Each stage ends with a headless suite pass and a soak with 0 illegal actions and 0 frozen turns, as the repo already requires. The first stage is a fun test, not a content pass.

0. **Spike.** One map (Karsa Breakout), Slack only, noise, packs, crouch, quiet kill, Pressure. Play it. If the quiet-versus-loud loop is not fun here, stop.
1. Ammo, reload and melee.
2. Doors, barricades, lures.
3. Infection, the Turning, Sera, mercy.
4. Full creature roster and the Nest.
5. Campaign layer: Tide gap, Volunteers, Roll Call, Named.
6. Act 2 and 3 maps, new sprites, new audio.

The size is larger than the JA2 plan's phases 0 to 2 and smaller than its phase 6, because the sim changes are contained and the art mostly exists. Stage 6 is the largest single item.

## 15. Risks and where this might be wrong

- **Noise legibility.** The biggest risk. If the player cannot predict what a shot will cost, the pillar becomes a source of frustration. Rings, chips and markers have to be tested on a real phone before anything else is polished.
- **Pack readability.** Packs hide individual creature positions. If players cannot tell how many are in a pack, melee decisions turn into guesses. Show a count and fan the sprites out.
- **Ammo balance.** HP is 1 to 4 and a Slack dies in one hit. That means ammo is the only dial, and a wrong number makes the game either a shooter or a stealth-only puzzle. Needs the soak and a human.
- **The stand-in AI squad.** The current AI squad wins by shooting. It cannot test a stealth game. A creature-aware soak needs an AI that crouches and avoids, which is new work.
- **Losing the Hegemony.** The old game's best writing was a courteous enemy that offers terms. Creatures cannot speak. The story has to carry that through the Nest's voice, the Named and the Keepers. The cost is real.
- **Infection frustration.** A bite that dooms a merc on a die roll can feel unfair. The Gamble option and the armour resistance are the mitigation, but a human playtest has to confirm it.
- **Scope.** This reverses three earlier decisions, adds about eight new systems and needs seven sprite sets. The story is a rewrite. It is a new game on an old engine, not a reskin.

## 16. Open questions for the owner

1. Space ships and derelicts, as written here, or an earthbound setting? The assets say space. A move to earth throws away 12 tile sets.
2. Keep Orrick as a second front (a human faction that wants the vats), or leave the creatures as the only enemy? Recommendation: leave him out.
3. How much gore? The design assumes none beyond a body marker.
4. Is the Gamble option acceptable, or does a bitten merc have to be put down or cured?
5. Does this replace the JA2 plan, or run alongside it? Stance and ammo overlap with that plan, and the narrative removal conflicts with this one.
