# Plan: JA2-style combat and a pursuit sector map (agreed 2026-10-16, not started)

## Owner decisions
| Question | Answer |
|---|---|
| AP scale | Change as needed. Chosen: **25 AP** per activation |
| Wounds | Yes. **The Hollowing stays**: a merc who dies still becomes a hollow |
| Strategic map | **Small free sector grid**. Fixed checkpoints must be reached in order; the route between them is the player's choice. The squad is **pursued** across the grid. Start small to test |
| Narrative | Still a retreat. **Drop everything except the Hollowing** (scenes, Writ, Orrick, roll calls, choices, the four endings, Procession, Remembrance) |
| Carry weight | Left out |

## Rules for every phase
- Change rules, AI, UI and tests together; full suite green, a soak with 0 illegal actions and 0 frozen turns, then commit.
- Rebuild the JA2 test APK (`export_android.ps1 -Ja2Test`) at the end of each phase so it can be played on a phone.
- Back up and restore `user://` saves around any capture or end-to-end run.
- Phase-end entry in `docs/handover.md`.

## Phase 0: AP rescale and save versions
- 25 AP per activation. Proposed costs (all in `data/combat/ap_costs.json`, out of `SimConst`): step 4 (diagonal 6), shot 8 (weapon class adjusts), overwatch 8, stance change 2 to 3, reload 5, aim click 2, bandage 6.
- `CombatSave` and `Campaign` save versions bumped; loading an older save gives a clear message (old saves are not converted, since the campaign is replaced in phase 6).
- Existing tests rewritten to the new numbers. Done when: suite green, soak clean, a fight takes about the same number of rounds as now.

## Phase 1: stances
- `SimUnit.stance` (stand, crouch, prone). Actions: change stance. Step cost +1 crouched, about double prone.
- Hit chance: against crouched -10, prone -20 at range 4 or more (prone is easier up close); shooter crouched +5, prone +10.
- Cover: crouched or prone behind half cover counts as full cover. Prone reduces the range at which a unit is seen by 2.
- AI scores stance per tile (crouch in cover, go prone for long shots, stand to move).
- UI: three stance buttons with their AP cost; stance shown on the unit.
- Art: JA2 crouch and prone layers from `Data/Anims/LOBOT` composited like the standing ones (and in the original-art mode, a simple lowered frame).
- Tests: costs, hit modifiers, cover promotion, sight reduction, AI choice cases, save round trip.

## Phase 2: aimed shots
- 0 to 4 aim clicks per shot, 2 AP each, +8 to hit per click (+12 for snipers), capped at 95.
- UI: tap an enemy to preview, **Aim +** cycles the clicks and updates chance and AP, tap the enemy again to fire.
- AI compares snap and aimed shots per AP spent.
- Tests: preview equals the real roll, AP charged, cap, AI picks aiming when it pays.

## Phase 3: grid inventory
- Per merc: head, vest, legs, two hands (primary and secondary), 4 large and 8 small pockets. Items get `size` (small or large), `stack` (magazines, grenades, kits) and allowed slots in `items.json`.
- Hands replace the weapon slot; vest/head/legs replace armour; mods attach to the weapon in hand.
- Phone UI: tap an item to pick it up, tap a slot to place it, a clear "holding X" bar, tap Back to cancel. No dragging.
- Sector pile replaces the stash (items stay where they were dropped).
- In battle: items in pockets can be used (reload, bandage, throw a grenade).
- Tests: fit rules, stacking, moving between mercs and the pile, illegal placements refused, save round trip.

## Phase 4: ammo and reloading
- Weapons get calibre and magazine size; magazines are stackable pocket items. Shots and bursts use rounds.
- Reload action (5 AP) takes a matching magazine from a pocket. Empty gun cannot fire; the preview says so.
- Supply: magazines from salvage and sector caches; nothing refills for free.
- AI reloads when empty or low and out of contact, and falls back when it has nothing left.
- Tests: consumption per class, reload rules, wrong calibre refused, AI never fires empty, soak counts empty-gun stalls.

## Phase 5: wounds (Hollowing kept)
- A hit has a chance to cause bleeding: lose 1 HP every 2 rounds until bandaged.
- Bandage action (6 AP) uses a first-aid kit on yourself or an adjacent merc.
- At 0 HP a merc is **down and dying** for 3 rounds; an adjacent bandage saves them at 1 HP, otherwise they die.
- **A merc who dies becomes a hollow, exactly as now** (Reserves pay for the refill; no reserves, the slot goes empty).
- After a fight: wounds carry onto the map; HP returns with time (faster if resting or with a medkit).
- AI bandages allies and targets bleeding units when it is worth it.
- Tests: bleed timing, bandage stops it, dying countdown, rescue, death then hollow, healing over time, save round trip.

## Phase 6: pursuit sector map and narrative removal
- **Grid**: a small test map, 6 x 5 sectors. Each sector has a terrain (road, field, forest, town, ruins) that sets travel time and which battle map is built.
- **Checkpoints**: 3 fixed sectors to reach in order, then an extraction sector. Reaching extraction wins the run. How you get there is up to you.
- **Time**: each move takes hours by terrain. Resting heals but costs time.
- **Pursuit**: one or two enemy groups start behind you and move every hour towards your last known sector, faster on roads. If one enters your sector, a battle starts. Pursuers grow stronger at each checkpoint you pass.
- **Sectors**: caches of ammo, kits and gear; some sectors hold a local enemy group that blocks or ambushes you.
- **Battle maps**: generated per terrain from tile pieces (reuses the map tools and the JA2 snow tiles in JA2 art mode); checkpoint fights use authored maps (Act 1 maps, reused).
- **Loss**: whole squad dead (with no reserves left to refill hollows).
- **Narrative removed**: briefing and debrief scenes, Writ officers, Orrick, roll calls, choices, contingency cards, the four endings, Procession and Remembrance. Kept: the Hollowing and Reserves, levelling, the result and salvage screens.
- New overworld screen: grid, sector info, travel time preview, known pursuer positions, Rest and Move buttons.
- Tests: travel and time, pursuer movement and contact, checkpoint order, victory and loss, map generation always valid and winnable (reachability), save round trip. A whole-run soak with the AI playing both sides.

## Phase 7: balance and release
- Per-mission and whole-run soaks on Story and Standard; AI review with all new systems.
- Rebuild the JA2 test APK and the full APK; update the docs (design, architecture, playing, test results, remaining issues).

## Size (rough)
Phase 0: 1-2 days. Phases 1-2: 2-3 days each. Phase 3: about a week. Phases 4-5: 3-5 days each. Phase 6: one to two weeks. Phase 7: 2-3 days.

## Risks
- HP is small (2-6). Bleeding and the dying state are measured in rounds so they matter at this scale; if fights feel too short, raise HP in phase 7 rather than earlier.
- The phone UI for the grid inventory is the most likely thing to need a second pass after you play it.
- Removing the narrative touches a lot of tests (story lint, scenes, endings); those tests are deleted with the systems they cover, not left failing.
