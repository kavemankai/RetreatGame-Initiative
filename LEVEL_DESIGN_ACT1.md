# Act 1 level design: theory and block-outs (DRAFT for review)

Block-outs: `art/style_test/blockouts_act1.png` (one file per map: `art/style_test/blockout_<mission>.png`). Draft data: `retreat-sim/data/maps_draft/<mission>.json`, written by `retreat-sim/tools/design_maps.py`. None of this is live yet; the current 12x10 maps stay in the game until these are approved.

## What was wrong with the first pass
All twelve maps shared the same 12x10 size, the same squad start (a 2x2 blob, west, centre), the same enemy blob (east, centre) and the same west-to-east fight. Terrain was the only difference, so no map had a reason to exist.

## Research, and what each source gave us
| Source | What it teaches | Where we use it |
|---|---|---|
| Fire Emblem GBA decomps (SamidyFR list: FE6/FE7/FE8 repos) | Chapters ship scripted **MapChanges** (doors open, walls breach, bridges fall) and reinforcement events alongside the terrain, so maps change mid-fight | Karsa's fire door; Pellam's east-gate reinforcements |
| Fire Emblem community design write-ups and the FEU enemy-placement guide | **The objective decides the route.** Plan where the player should be each turn and place enemies so each turn is a fight, not a slog; vary AI roles (charge, guard a tile, attack in range, linked groups); 2-3x as many enemies as player units feels full; defend maps go stale at a single choke, so give them a timer and more than one approach | Every map: one objective, enemies by role, staggered encounters; Pellam has two gates and a 4-round timer |
| Desperados III / Commandos (Mimimi) | Big levels are **sections that each work as a small puzzle**; static guards watch fixed places, patrols create windows; sight must be readable | Karsa's sentry on the door, the Weir's guarded caches, Orchard's two ring patrols |
| XCOM 2 (Firaxis, "Plot and Parcel", GDC 2018) | Hand-place the **objective and spawn points**, then dress the rest; fights gather where partial and full cover cluster | Each map's cover is clustered where the objective forces a fight, not spread evenly |
| Jagged Alliance 2 | Sectors have **two or more entry points**; Omerta teaches one fight, then pushes you outward; a conscript garrison is followed by regulars counter-attacking | Starts vary per map; Act 1 ladders conscripts first, regulars last (Orchard) |
| Into the Breach | Tiny maps work when there is **something to protect** and every turn forces a hard choice | Pellam: the berths are the Procession's lives, so losses cost people, not just units |
| Advance Wars 2, Vandal Hearts, Fallout 2 (also on the list) | Objective variety (rout, escape, defend, escort) and towns as landmarks | Objective mix across the act; every map has a named landmark |

Principles we design to:
1. **One reason to exist.** Each map has an objective that only that map asks for, and at least one iconic, named feature the player will remember ("the fire door", "the broken freighter").
2. **The objective draws the route.** Spawns, cover and enemies are placed so the objective pulls the squad through the interesting ground.
3. **Size follows the job.** Bigger only when the objective needs travel or choice (the Weir), otherwise compact.
4. **Enemies have jobs.** Sentry (overwatch a lane), guard (hold a tile), patrol (walk or push), plus timed reinforcements. No blobs.
5. **Different starts.** Corner, edge, inside a room: the start sets the first question the map asks.
6. **Act 1 teaches one new thing per map**, in small fights (1-2 enemies at a time), so the act is easy without being trivial.

## The four maps

### 1. Karsa Breakout (station deck, 16x12) — teaches doors, overwatch and flanking
- **Story job:** cut a path so the Procession can load; reach and hold the lock.
- **Start:** sealed in the TRAM BAY (south-west room); one gap leads out.
- **Iconic:** THE FIRE DOOR: a full bulkhead splits the deck. The obvious way through is a sealed door that opens onto an enemy **sentry on overwatch**. The VENT (a one-tile gap in the bulkhead, south) is the flank. Second landmark: THE LOCK at the end of the NORTH SPINE corridor.
- **Enemies (3 conscripts):** S on overwatch facing the door; P walking the east hall; G holding the lock.
- **Why it matters:** the first lesson is "never walk through a door into overwatch". The map rewards the player who finds the vent.
- **Win:** a merc ends a round on the lock tiles with no enemy left in the North Spine.

### 2. The Weir (wreck field, 18x14) — teaches route choice and splitting up
- **Story job:** scavenge. The convoy needs what is in the wrecks.
- **Start:** north-west corner, at the TUG (also the exit).
- **Iconic:** THE BROKEN FREIGHTER, a long diagonal hull that cuts the field in two, with one BREACH through its middle. DRIFT FOG lies over the north (shorter sight there).
- **Objective layout:** three caches in three different corners: A (south-west, unguarded), B (north-east, guarded), C (south-east, guarded). Then everyone back to the tug.
- **Enemies (3 conscripts):** G on cache B, G on cache C, P watching the breach.
- **Why it matters:** the first big map. The player must choose to go round, through the breach, or under the fog, and whether to split the squad. Cache A is the safe warm-up.
- **Win:** all three caches recovered (end a round on each), all living mercs back at the tug.

### 3. Pellam Dock (dock ring, 16x14) — teaches holding ground against a timer
- **Story job:** defend the tug berths while the Procession boards.
- **Start:** spread along the TUG BERTHS (south edge), not in a clump.
- **Iconic:** the GANTRY CRANE in the middle, cargo-stack alleys, and the BOLLARD LINE (half cover along the berths). Two gates: NORTH GATE (enemies start there) and EAST GATE (reinforcements on round 2).
- **Enemies (3 conscripts + 1 regular):** two P push through the north gate; S on overwatch down the west alley; on round 2 a conscript and a regular arrive at the east gate.
- **Why it matters:** a defend map with **two approaches and a timer**, so sitting at one choke does not win. Losses are counted in people: each enemy on a berth tile at a round's end costs the Procession 50.
- **Win:** survive 4 rounds.

### 4. Orchard Ring (garden deck, 14x14) — teaches patrol timing and escorting
- **Story job:** rescue the people held in the greenhouse.
- **Start:** the MAINTENANCE HATCH in the north-east corner (also the exit).
- **Iconic:** THE GREENHOUSE in the centre (glass walls, two doors) inside a PLANTER RING with gaps, giving an outer and an inner lane. The inner GROW-LAMP LANE is lit (everyone is easier to see there).
- **Enemies (2 conscripts + 2 regulars):** G on each greenhouse door; two regulars patrol the inner ring in opposite directions. These are the act's first regulars, as JA2 does it.
- **Why it matters:** the player reads the patrols, slips in on a window, and then must get the hostages out, which is a new kind of fight: slow and exposed.
- **Win:** hostages reach the hatch.

## What the game needs before these can be played (engine work, after approval)
1. **Bigger maps:** map size is already data-driven (MapData). Needs a camera check at 18x14 on a phone (zoom and pan exist) and `route.json` sizes updated.
2. **Doors:** an edge that is a full wall until a merc spends ticks next to it to open it (Karsa's fire door). FE-style MapChange.
3. **Enemy roles per spawn:** sentry starts on overwatch facing a set direction; guard holds its tile until seen or hit; patrol pushes. This maps onto the existing AI profiles plus a "hold tile" rule.
4. **Reinforcements:** units that appear at a set round on set tiles (Pellam).
5. **Objectives:** reach-and-hold a zone (Karsa), collect zones then exit (Weir), survive N rounds with a penalty for berth tiles (Pellam), escort civilians to an exit (Orchard). Plus a UI marker and a briefing line for each.
6. **Sight modifiers:** fog tiles shorten sight (Weir), lit tiles lengthen it (Orchard, Karsa's spine).
7. **Balance:** re-run the probe. Act 1 sends 3-4 enemies in small groups across bigger ground, so encounters stay small even where counts rose slightly (Karsa 2 to 3 conscripts).

## Sources
- [Plot and Parcel: Procedural Level Design in XCOM 2 (GDC 2018)](https://gdcvault.com/play/1025213/Plot-and-Parcel-Procedural-Level), [GDC news](https://gdconf.com/news/come-learn-xcom-2s-procedural-level-design-works), [Game Developer: XCOM deep dive](https://www.gamedeveloper.com/design/a-deep-dive-into-xcom-and-xcom-2)
- [Jagged Alliance 2 (Wikipedia)](https://en.wikipedia.org/wiki/Jagged_Alliance_2), [StrategyWiki: Omerta](https://strategywiki.org/wiki/Jagged_Alliance_2/Omerta), [JA wiki: SAM Site](https://jaggedalliance.fandom.com/wiki/SAM_Site)
- [Into the Breach (Wikipedia)](https://en.wikipedia.org/wiki/Into_the_Breach), [Giant Bomb review](https://www.giantbomb.com/into-the-breach/3030-58234/user-reviews/2200-31048/)
- [Desperados III review (Noobfeed)](https://www.noobfeed.com/reviews/1660/desperados-iii-pc-review), [Worthplaying review](https://worthplaying.com/article/2020/7/29/reviews/120867-ps4-review-desperados-iii/)
- [RandomWizard's Enemy Placement Guide (FEU)](https://feuniverse.us/t/randomwizards-enemy-placement-guide/14888), [Awakening ch. 6 walkthrough](https://www.gamerguides.com/fire-emblem-awakening/story-walkthrough/beginning-to-chapter/chapter-6-foreseer)
- Decomp repos from the SamidyFR list: [fireemblem8u](https://github.com/FireEmblemUniverse/fireemblem8u) (chapter MapChanges data), [Vandal Hearts](https://github.com/shao113/vh), [Advance Wars 2](https://github.com/Eebit/aw2bhr), [Fallout 2](https://github.com/alexbatalov/fallout2-re)

## Status: playable in the Act 1 level test build
The four maps are live (`retreat-sim/data/maps/`, written by `tools/design_maps.py`) and play from the main menu's **Act 1 level test** (a throwaway campaign; nothing is saved). Build with `powershell -File retreat-sim/tools/export_android.ps1 -LevelTest` (29.1 MiB; the full build is 31.8 MiB because it carries all 12 themes, all audio and all 23 sprite sets).

Implemented:
- Bigger maps (16x12, 18x14, 16x14, 14x14) and per-map squad starts; the portrait zoom now scales with map size, and a **Map** button shows the whole board.
- Per-unit enemy placement with roles: **sentry** (holds overwatch facing a set direction), **guard** (stays on its tile, shoots what comes in range), **patrol** (pushes at the squad, as the aggressor profile).
- **Reinforcements** on a set round (Pellam, round 2), announced in the log.
- **Goals** checked at the end of each round, shown as a "Goal:" line and tinted zones: hold a zone (Karsa), collect caches then everyone to the exit (Weir), survive N rounds with a berth penalty that comes off the Procession (Pellam), reach then return (Orchard). Eliminating every enemy also wins.

Not yet built (the maps play without them):
- **Doors:** Karsa's fire door and the greenhouse doors are plain gaps. The sentry still covers the gap, and the vent is still the flank.
- **Sight modifiers:** the Weir's drift fog and the lit lanes only change the art, not how far units see.
- **Patrol loops:** patrols push rather than walk a route.
- **Hostages:** Orchard's rescue is "reach the greenhouse, then the hatch"; there are no hostage units to escort.
- **Balance:** the crude auto-AI stalemates on Orchard (nobody engages) and wins Karsa and Pellam easily; it can't play to a goal, so a human pass is needed.
