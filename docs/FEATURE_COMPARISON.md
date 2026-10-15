# Feature comparison: Jagged Alliance 2 systems and The Long Retreat

The 1.13 JA2 source (`github.com/kavemankai/jaggedalliance2`, a fork of `videogamepreservation/jaggedalliance2`, shipped with a Strategy First non-commercial source licence) was used **for ideas only**. No JA2 code, data, art, text or audio is in this game (see `LICENSE_AUDIT.md`). JA2 behaviour below is described from general knowledge of the game and the notes recorded in `ENGINE_ROADMAP.md` (appendix); the JA2 source was not copied or cloned into this repository during this pass.

Dispositions: **Retain** (already in the game and kept), **Improve**, **Replace** (a different design on purpose), **Build** (new work), **Exclude** (deliberately not in this game).

| JA2 system | The Long Retreat today | Disposition | Reason |
|---|---|---|---|
| Turn-based combat, action points | Activation engine: 14 AP per activation, step 2 (diagonal 3), shot 4, overwatch 4 (`data/combat/ap_costs.json`) | Retain | Core of the game; tuned over several playtests |
| Initiative and turn order | Seeded `speed*10 + aim`, one activation per unit per round, shown in an order strip | Retain | Deterministic and readable on a phone |
| Interrupts | Replaced by armed one-shot overwatch (cone, free shot) | Replace | Interrupts need a rules explanation a phone player will not read; overwatch is a visible, chosen action |
| Ballistics and hit chance | Aim + gear, range falloff, half cover -30, dug-in cover +/-10..20 per activation, beams ignore half cover | Retain | Previewed exactly before the confirming tap |
| Weapons | Seven classes (rifle, carbine, sniper, shotgun, heavy, grenade, beam), 32 items, class-locked to mercs, burst and area rules | Retain | Variety without a gun encyclopaedia |
| Ammo, reloading, jams | None | Exclude | Adds bookkeeping, not decisions, at 14 AP and 2-3 hp |
| Aimed shots, stances | None | Exclude (for 1.0) | Roadmap B3/B4; the cover and overwatch layer already carries the positioning decisions |
| Attributes and progression | Six stats with caps; 3 seeded offers per level, pick one; use counters bias the offers | Retain | Decided 2026-10-15 |
| Skills and specialisations | Weapon class per merc plus class weights in offers | Retain | Enough identity for 8 mercs |
| Enemy AI | `SimAI` scores moves and shots (threat, lane, cover, objective distance); `ActivationAI` executes one legal action at a time | Retain | 1,000-battle soak: 0 illegal actions, 0 frozen turns |
| Cover, vision and line of sight | Fog by sight range, wall and half-wall edges, LOS in `SimLos`, visible-enemy-only strip | Retain | |
| Pathfinding and movement cost | Orthogonal 2, diagonal 3, occupancy rules; route preview marks exposed steps | Retain | Terrain costs not modelled |
| Squad management | Roster of 8, squads of 3-4 per mission, prep screen, loadout hub | Retain | |
| Inventory | Three slots per merc (armour, weapon, mod) and a shared stash | Replace | Grid inventory is a desktop interaction; three slots read on a phone |
| Strategic map, sectors, militia, mines | Linear route with branch cards on an overworld map; retreat economy (Procession, Reserves, Remembrance) | Replace | The game is a retreat, not a conquest |
| Encounters and reinforcements | Authored missions with roles (sentry, guard, patrol, picket), goals (hold, collect, defend, reach-then-return) and timed reinforcements | Retain | |
| Morale | Morale checks, shaken and broken states, hollows never break | Retain | |
| Wounds, bleeding, medical, doctors | None; permadeath plus the Hollowing is the consequence | Exclude | Owner decision 2026-10-15 ("no injury system") |
| Mercenary hiring and finances | Fixed cast; Wren and Ghost join mid-campaign | Exclude | Story-driven roster |
| Doors, patrols, hostages, sight modifiers | Not in the engine | Exclude (for 1.0) | Roadmap A1-A4; Act 1 maps play without them |
| World persistence and saving | Versioned campaign save (v3), validation with reasons, never overwritten when unreadable; one silent battle autosave and a Resume button | Retain | |
| Difficulty setting | **Standard and Story** (Story: +1 squad hp, -15 enemy accuracy), saved with the campaign | Build | Added 2026-10-16 so the finale is reachable for a casual player |
| Tutorial | **First-mission coach** (one tip at a time from what the player has done) | Build | Added 2026-10-16 |
