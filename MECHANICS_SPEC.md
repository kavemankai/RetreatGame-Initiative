# Mechanics Spec (draft v0.1) — 2026-10-13

Status: decisions from the workshop; items marked (REC) are my recommendations, not yet confirmed.

> **Read this as a decision log (updated 2026-10-15).** Early sections are history and some are superseded: the original principles below ("no RNG", "plan all, resolve together") were replaced by seeded dice and live play, and the tick-era sections apply to the legacy planned mode only. **The current rules are the last section, "Current ruleset: activation engine".**

## Principles
- Fully deterministic. No RNG in combat. Same state + same plan = same event log, on any device. *(Original wording: combat now rolls seeded dice, which are just as repeatable; see Hit chances.)*
- Integer-only math in the sim. No floats, no physics, no engine time.
- Plan all → resolve together. The player sees exact outcomes in the preview ("hits for 2" / "blocked").

## Architecture (REC)
```
sim/            pure GDScript, RefCounted only, no Node, no signals into scenes
  state         GameState: grid, units, edges, turn number
  plan          Plan: per-unit action queue (<= 12 ticks)
  resolve       resolve(state, plan) -> (new_state, events[])
  los           symmetric shadowcasting over tile edges
  rules/data    JSON/Resource tables for weapons, units, costs
view/           Godot scenes; consume events[] and animate; never mutate state
ai/             enemy planner: produces a Plan from a visible-state snapshot
tests/          headless replay tests: (state, plan) -> golden event log
```
Rule: the view may only read events; the sim may never import view code.

## Grid and movement
- Square grid, 8-direction movement (REC).
- Step cost: orthogonal 2 ticks, diagonal 3 ticks (integers).
- No diagonal corner-cutting through a blocked tile edge.

## Turn structure
- A turn is 12 ticks. Each unit queues actions totalling at most 12 ticks (REC).
- Action costs (REC): step 2/3, shot 4 (light weapons 3), reload 3, crouch/cover 1, overwatch = hold from tick N.
- Resolution loops tick 1..12; within a tick, units act in speed order (higher first).

## Conflict rules
- Same tile: earliest arrival wins; tie goes to higher speed; loser stops short (REC).
- Same-tick shots: higher speed fires first; a kill removes the slower unit's remaining shot. Equal speed = both hit (decided).
- Allies cannot pass through each other (REC).

## Cover and LOS
- Cover lives on tile edges (full wall, half wall) (REC).
- LOS by symmetric shadowcasting (REC).
- Binary hit rule (decided): a shot is blocked if its line crosses a blocking edge on the target's facing side; otherwise it lands.
- Flanking = getting an angle where no cover edge covers the target.
- Tuning handle: small HP (2-4 hits), weapon damage, range, suppression.

## Visibility and fog (REC)
- Squad-shared vision. Visible enemies show planned orders; unseen enemies are hidden until revealed.

## Open mechanics questions (all answered below; kept as history)
1. Does overwatch fire at the first unit entering the cone, or choose a target? How does it interact with simultaneous moves?
2. Suppression: does a hit-or-miss binary game still need it, and what does it do to a unit's queue?
3. Enemy AI: scripted per mission, utility scoring, or search over plans?
4. Skills improve by use: which counters, and when do they apply (end of mission)?
5. Hollowing in the sim: what is a drone's stat block and how is the slot refilled?
6. Map size and unit counts per mission.

---

## Round 2 decisions
- **Overwatch (decided; SUPERSEDED):** from the chosen tick, fires once at the first enemy entering its cone + LOS; speed order within the tick. *Now: armed for 4 AP, one free shot, until the owner's next activation, in initiative order (see the last section).*
- **Enemy AI (decided):** utility scoring per unit; weights live in data; AI receives a visible-state snapshot only.
- **Stats (decided):** HP, Speed, Aim, CQB, Morale. Drones have **no morale** (immune to stress; no growth, no abilities, per Hollowing).
- **Growth (decided 2026-10-15): XP, pick 1 of 3.** A surviving merc earns XP after a mission from hits landed, kills, surviving hits and the objective. Five levels. Each level offers three different +1 stat steps, weighted by what the merc did and seeded by campaign seed, slot and level (so reloading cannot reroll); the player picks one. Hollows never level; death freezes stats at 60% of the levelled values. The numbers live in a data file (`data/story/progression.json`, built). **Stat caps for levelling:** hp 6; speed, aim, cqb, morale 10; sight 9. Gear can lift hp and morale above these (morale to 12, see EQUIPMENT.md). **Injury is dropped:** permadeath plus hollowing is the consequence system.

### Open (answered in Round 3 and the sections below)
- What does CQB do mechanically? (Candidates: bonus in adjacent/close range, faster entry/door ticks, melee/breach options.)
- What does Aim do with a binary hit rule? (Candidates: max range, shot tick cost, suppression strength.)
- What does Morale do to a plan? (Candidates: lose ticks, refuse orders, break from cover.)
- How are drones' stat blocks scaled (fixed fraction of the fallen merc's, or flat)?

## Round 3 decisions (all accepted)
- **CQB:** a close-range damage edge only: +1 damage at CQB 6 or more within 2 tiles. (The "faster entry/breach ticks" idea was never built.)
- **Aim:** drives hit chance (35 + 7 per point, minus 4 per tile beyond 2, clamped 10..95, rolled on a seeded d100), range (`aim / 3` extra tiles) and a cheaper shot at aim 8 or more. (The original "no hit roll" was replaced; see Hit chances.)
- **Morale:** a hit unit rolls an on-hit check: steady (cannot shoot until its next activation) or broken (no AP until then). **Stress is dropped (decided 2026-10-15):** it never shortened anyone's AP; the unused `stress_penalty` field stays inert until a real source is designed.
- **Drones:** fixed ~60% of the fallen merc's stats, frozen at death; no growth, no abilities, no morale.

## Overwatch (planned mode, implemented; the default activation engine differs: see the last section)
- `SimAction.overwatch(facing, hold_ticks)`: 8 facings, 90-degree cone (integer test, boundary included), costs `hold_ticks`.
- Active on every tick from the action's start through its finish.
- Reacts to the first enemy (in move-resolution order) that **finishes a move** in the cone, within range, with LOS. Fires once, then the watch is spent.
- The reaction shot has no extra tick cost; it resolves in the normal speed-group phase alongside queued shots (equal speed = simultaneous).
- Cover applies: a blocked reaction still spends the watch. A reaction whose target was already killed by a faster group fizzles (`shot` result `invalid/no_target`) and does not spend the watch.
- A mover killed by overwatch loses the rest of its orders.
- Watching enemies already inside the cone do not trigger it unless they move.

## Fog of war (implemented)
- `SimVision` (pure, in `sim/`). The resolver stays omniscient; fog constrains **planning and display**, not resolution.
- Vision is **shared across the squad**: a tile is visible if any living teammate is within its `sight_range` (default 8, Chebyshev; per-unit stat) and has a clear line. Full walls block sight, half walls and cover do not. Own living units are always visible. Dead observers see nothing.
- `view_for(state, team)` returns a filtered copy (own units + visible enemies) — the input for the enemy AI and the player UI.
- `visible_orders(state, plan, team)` returns own orders plus the orders of **visible** enemies (per the original spec: visible enemies show planned orders).
- `SimPlan.validate_fog(state)` rejects shot orders aimed at enemies the shooter's squad cannot currently see. (Plain `validate` is unchanged, so omniscient tests still work.)
- Replay: fog toggle per team; hidden units, tiles, cones, events and log text are redacted. A shot from an unseen shooter draws only a short stub toward it.

### Fog open questions
- No memory yet: enemies leaving sight vanish (no "last seen" ghost).
- Sight range 8 on a 12x10 map makes fog mild; maps and `SIGHT_RANGE` need tuning together.
- Should a hit from an unseen shooter reveal it for the rest of the turn?
- Should enemy overwatch cones be visible only when the enemy itself is seen (currently yes)?

## Enemy AI (implemented)
- `SimAI.plan_for(state, team, profiles, assignments, objective)` — pure, deterministic, integer-only.
- **Fairness:** the AI receives only `SimVision.view_for(state, team)`. It never sees hidden enemies or the opponent's orders. Tested by moving a hidden in-range enemy and requiring an identical plan (and the test was mutation-checked against an AI that reads the full state).
- **Per unit, in id order:** enumerate every tile reachable within the tick budget (Dijkstra over tick costs); for each, consider *stay*, *shoot the best visible target*, or *overwatch* (overwatch only evaluated for the 5 best positions — it is the costliest).
- **Score (ints, from `data/ai_profiles.json`):** `w_damage` x damage (capped at target hp left) + `w_kill` bonus − `w_exposed` per visible enemy that could hit the end tile + `w_cover` per enemy whose shot would be blocked − `w_range` x |nearest enemy − preferred_range| (or − `w_objective` x distance to objective when no enemy is visible) − 1 per 2 ticks walked + overwatch value (`w_watch` x clear cone tiles x hold ticks / 48). Ties go to the first candidate enumerated.
- **Coordination:** teammates reserve destination tiles and count damage already planned against a target, so nobody overkills a doomed enemy.
- **Profiles:** `default`, `aggressor`, `defender` (see data file). Unknown keys / non-integer weights are rejected on load.
- Replay scenarios 6 and 7 play AI vs AI (blue aggressor, red defender).

### AI known limitations
- It does not model enemy overwatch cones (it can't see enemy orders), so it will walk into them. Possible fix: infer a "probable overwatch" threat from enemies that did not move last turn.
- It plans against current enemy positions; it does not predict enemy movement.
- Overwatch scoring is a heuristic (cone size x hold time), not a probability of a trigger.
- No role/mission scripting yet (retreat, escort, hold-the-line); profiles + an objective tile are the only levers.
- No hollowing awareness (drones are just units with no morale).

## Code-review fixes (changes to the rules)
- **LOS and cover are symmetric.** Lines are always walked from the canonical end (lower y, then lower x), so `can_shoot(a,b) == can_shoot(b,a)`. Cover still depends on which side the shooter is on (the edge next to the target on the shooter's side of the line). This slightly shifts a few AI/overwatch outcomes versus v0.
- **The resolver never trusts a plan.** Unknown units, dead units, null or malformed actions (including steps longer than 1 tile) are dropped and logged as a tick-0 `plan_rejected` event. `SimGrid.can_step` rejects non-adjacent steps.
- **Simultaneous shot groups log all shots first, then the deaths** they caused.
- **Fog replay:** visibility is the union of the start and end of a tick, so a unit that dies that tick (or a squad wiped out) is still shown dying; an unseen shooter's lethal hit is shown with the shooter redacted.
- **AI profiles:** a missing/invalid `default` (or file) falls back to built-in weights; weights above 100000 are rejected on load.
- Replay overwatch cones follow the resolver's budget truncation and ignore rejected plans.

### Still open from the review
- AI paths can cross a teammate's reserved destination; the later arrival can lose its orders (`move_blocked: occupied`). Not fixed: needs path-level reservation.
- A corpse hit by a second shot in the same simultaneous group still counts a `hits_taken` (arguably correct: both shots landed at once).

## Order entry and match loop (implemented)
- `PlanBuilder`: per-merc queue of **entries** (move to tile, shoot, overwatch) within the tick budget; undo pops one entry. Everything comes from the team's fog view, so entering orders cannot leak hidden enemies (moving into a hidden enemy's tile is accepted — you can't know it is there).
- Shot preview uses `SimResolver.evaluate_shot` — the same function the resolver uses — from the merc's **projected** position (after queued moves). The preview reflects enemies where they are *now*; enemies move simultaneously, so it is a forecast, not a guarantee.
- Overwatch takes all remaining ticks and a facing (click a tile; snapped to 8 ways).
- `SimMatch`: the AI plans first from its own fog view and never sees the player's orders. The player sees the orders of **visible** enemies (Into-the-Breach style intent). `submit` refuses plans that fail `validate` / `validate_fog` or that order enemy units, then resolves both plans together. Win = last side standing; simultaneous mutual wipe = draw.
- Playable skirmish: 3v3, sight shortened to 6 so fog matters; AI team uses aggressor/aggressor/defender profiles and drifts toward the player's side.
- `PlayController` turns clicks into orders (select / move / shoot / overwatch mode); `PlayOverlay` builds what is drawn on top of the board (reachable tiles, paths, ghosts, planned cones, enemy intent).

### Known gaps in the playable build
- Desktop landscape with mouse; no touch-first portrait layout yet (hover previews have no touch equivalent).
- One map, one scenario, no campaign/story/hollowing, no save/load, no sound or art.
- Enemy intent is shown only for enemies currently visible; their overwatch cones are drawn at the end of their planned moves.

## Phone portrait layout (implemented)
- One screen, two layouts: taller-than-wide windows get portrait (board full width on top; squad as three 84px cards; 60px action buttons; Confirm at the bottom thumb zone; log above it). Wider windows keep the desktop layout. Project default is 540x960, stretch `canvas_items`/`expand`, portrait orientation.
- **Two-tap commit** (touch / portrait / key T): tapping your own merc selects at once; the first tap on a tile or enemy PREVIEWS the order (path with tick cost, or exact hit/blocked/no-shot result) and a second tap on the same tile commits. Tapping elsewhere moves the preview; unreachable tiles are refused immediately. The logic lives in `PlayController.tap_tile` / `pending_preview` (tested), drawn by `PlayOverlay`.
- Touch arrives as emulated mouse clicks (`emulate_mouse_from_touch`).

### Not yet done for mobile
- Never run on a real device; no Android/iOS export preset, safe-area/notch handling, or haptics.
- Squad cards, tile size (45px at 540 wide) and fonts are first-pass numbers; verify on hardware. The 12x10 map is small enough to fit but tiles are close to the minimum comfortable tap size.
- Landscape phones use the desktop layout.

## Live turns: run, pause, replan (implemented — REPLACES "plan all, then resolve together")
Playtest feedback: ticks felt strange; wanted to pause and change plans without resetting AP.
Decisions: run + pause anywhere · auto-pause on spotted / hit / idle / overwatch · in-progress actions finish · the AI replans at every pause.
- **A turn is a live run of 12 ticks** (`SimTurn`, advanced one tick at a time; `SimResolver.resolve` = advance until finished, so stepping and one-shot resolution always agree). Tick 0 is just the first pause: the opening plan and a mid-turn replan are the same operation.
- **Spent ticks are never refunded.** Each merc has the same 12-tick turn budget; new orders must fit in `available - free_at`, where `free_at` is the tick its committed action ends.
- **Committed actions finish.** A move or shot that has already started cannot be cancelled; new orders begin after it. Holds (overwatch, wait) and actions not yet started are cancelled at once (an overwatch's remaining window ends immediately).
- **Auto-pause reasons** (`SimMatch.step` returns them): `spotted` (an enemy newly visible to the player), `hit` (a player merc was hit), `idle` (a player merc's orders ran out or were halted, with ticks to spare — only the transition counts), `overwatch` (a reaction shot involving the player's side or a visible unit fired).
- **AI replans at every pause** from its own fog view, with each unit's remaining budget and the position where its committed action ends (`SimAI.plan_for(..., live)`). It never sees the player's orders. It does NOT replan while the player keeps the clock running.
- **Enemy intent** now shows the *current* orders of visible enemies (`SimTurn.remaining_actions`), so it updates after every replan.
- **Early end:** a side wiped out mid-run ends the match at once.
- **Order entry mid-turn:** `PlanBuilder(state, team, turn)` seeds each merc's queued orders as entries (contiguous moves grouped), starts planning at the committed action's end position, and `orders_dict()` replaces the queues atomically (`SimMatch.apply_orders`, all-or-nothing, fog-checked).
- UI: one bottom button cycles **Go -> Pause -> Resume**; 1x/2x/4x speed; the log accumulates across the turn, fog-redacted (`SimVision.fog_between` per tick).

### Open (live turns)
- Pauses are free: a player can pause every tick and replan with full information. The AI replanning at each pause is a partial counterweight; limits (a pause budget, or AI-side pauses) are untested.
- The AI replans on the player's pauses only; no AI-triggered pauses.
- No "interrupt a committed shot/step" (by design, per the decision); revisit if it feels sticky.
- Tick-0 planning still shows enemy intent the AI chose before seeing your orders; replanning can exploit it.

## Campaign layer (implemented)
- **Roster:** 12 slots (cast.json). Statuses: `absent` (joins later), `named`, `hollow`, `vacant`. Unit id = slot (1..12); Provost 100; Writ officers 101..106; regulars 200+; proxies 300+.
- **Hollowing:** a named merc who dies becomes a hollow automatically: **60% of their stats** (integer rounding, min 1, **no morale**, sight unchanged), frozen, designation `HX-nn`. Refill costs 1 reserve; with none the slot is `vacant`. A hollow's death is refilled again at the same cost. Dead named mercs are reported in `report["fallen"]` for roll calls (hollowed or vacant).
- **Economy:** Procession and Reserves move by each mission's `on_success` / `on_failure`; never below 0. Procession 0, an empty roster, or a wiped squad ends the campaign (`over_reason`).
- **The Writ:** officers killed become hollow (stage 0..6 = how many). `orrick_scene()` = `orrick_stage_N`; at stage 6 (the Quiet) with Remembrance >= 6 Orrick also says his true name.
- **Endings:** the finale choice maps to an ending; unmet requirements fall back to `long_watch`. Requirements: remembrance, flags set by earlier choices, Writ stage.
- **Guards:** `can_complete(id)` (story missions only in route order; cards once; not after the end), a failed finale does not end the story, saves are version-checked and refuse damaged data (`save_problem`, `from_dict` -> null), and the unfinished debrief steps are stored **in the save** (`pending`) so quitting mid-debrief loses nothing.
- **Review fixes (live turns):** a re-issued overwatch that already fired stays spent across pause/resume; an early finish closes the turn log; queued shots at dead/hidden targets are dropped when re-planning.

## 20-tick rounds with checkpoints (implemented; supersedes the 12-tick numbers above)
Playtest direction: ticks felt strange; wanted fixed planning stops and a game that hurries when nothing is happening.
- **A round is 20 ticks** (`SimConst.TICKS_PER_TURN`). Action costs are unchanged (step 2/3, shot 4), so a merc can walk about 10 tiles a round; maps may need to grow or costs rise if that feels too cheap.
- **The run stops every 5 ticks** (`CHECKPOINT_TICKS`): four planning stops per round. Every stop is a pause in the old sense: the AI replans from its own view, you re-order the rest of the round, spent ticks stay spent, committed moves/shots finish.
- **Interrupts between checkpoints are optional** (`SimMatch.interrupts`, the Alerts button): by default **nothing** stops the run between checkpoints (changed after the first phone test: only the 5-tick pause remains); switching Alerts on makes new contact (`spotted`) and a hit on your merc stop the run; `idle` and `overwatch` are still reported in `step()["reasons"]` but no longer stop it. With Alerts off ("Calm") only the checkpoints stop it.
- **Fast-forward:** `step()["idle"]` is true when no living merc on either side has queued orders, a shot/step in flight or an overwatch hold (`SimTurn.has_active_orders`). The screen then runs at 0.04 s per tick until the next stop.
- AI cost at the 20-tick budget: about 16 ms to plan 3 units on desktop.

## Move+Fire and the plan timeline (implemented)
- **Move+Fire** (`SimAction.move_shoot`, key M): step one tile and fire when the step lands. Costs `SimConst.MOVE_SHOOT_FACTOR` (2) times a normal shot, plus 1 tick if the step is diagonal: 8 ticks orthogonal, 9 diagonal with the default 4-tick shot. It is committed once started, the step happens on the completion tick and the shot follows it (a blocked step fires nothing), and enemy overwatch can react to the move. Raise the factor to make it a heavier commitment.
- **Order entry:** pick Move+Fire, then tap an enemy; the step is chosen for you (the free adjacent tile nearest the target). The hover/preview shows the cost and what the shot would do from the stepped tile. Two-tap commit applies as usual. The AI does not use it yet.
- **Plan timeline:** every queued action is labelled on the board with the tick it completes ("t10"), and a bar under the board shows the selected merc's schedule across the 20 ticks: queued actions by colour, its committed action in grey, the checkpoints at 5/10/15 and a marker for the current tick. `PlanBuilder.timeline(id)` gives the data.

## Move+Fire (REVISED: replaces the single-step version above)
Direction from the user: pick a point to move to; the unit takes a shot if it gets one on that movement; the cost stays high even if no shot is taken.
- **Action:** `SimAction.move_fire(steps)`: walk a whole path (pick any reachable tile; key M / the Move+Fire button, then tap the destination).
- **Cost:** the path's normal movement cost **plus a reserved shot** of `shot_ticks x MOVE_FIRE_SHOT_FACTOR` (2): three orthogonal steps = 6 + 8 = **14 ticks**, paid whether or not anything is fired at. The merc stays committed (cannot be re-ordered) until the full cost is spent, even after it has arrived.
- **Pace:** steps complete at their normal times (2 ticks orthogonal, 3 diagonal); only the busy time is extended.
- **The shot:** at most **one per action**, at the first step where a target is available. It fires on that step's tick (shot phase, in speed order like any shot) and the action stops looking. Targets are limited to **enemies the merc's squad can currently see**, so it never reveals hidden units. A clean hit is preferred to a shot into cover, then the weakest target, then the lowest id.
- **Interactions:** a blocked step halts the whole action (no more steps, no shot); enemy overwatch can react to each step; the AI does not use Move+Fire yet.
- **Planning:** the hover/preview shows the total cost and how it splits; the tinted ground is only what is reachable while still affording the reserved shot; the plan timeline shows the full cost.

### Decision: AI and Move+Fire
The AI does not use Move+Fire by default. It is reserved as a **late-game elite-unit ability** (e.g. Hegemony proxies/officers in act III, or an "elite" AI profile), so facing it signals a step up in threat. Not implemented yet: needs an elite profile and a place in `SimAI` candidate generation.

## Combat rework: no pauses, ordered fire, morale on hit (planned mode, implemented; SUPERSEDES checkpoints, Alerts, mid-round replan and simultaneous shot groups above)
- **No pauses.** Once Go is pressed, orders are locked and the round plays all 20 ticks. Checkpoints, Alerts/interrupts and manual pause are retired. `SimMatch.step()` sets `pause` only when the round or match ends. (`SimMatch.pause`/`apply_orders` and `SimTurn.replace_orders` remain for tools/tests.)
- **Ordered fire.** Shots due on the same tick resolve one at a time: higher speed, then higher aim, then lower id (`SimTurn._fires_before`). Each shot sees the board left by the shots before it, so a hit can pre-empt the reply and **mutual kills in one tick no longer happen** (a draw by mutual wipe is now effectively impossible). Moves still resolve by speed, then id. If the faster shot is blocked by cover, the slower unit's shot goes ahead.
- **Morale check on a non-lethal hit.** `need = morale + 3 - wounds` (+1 when the unit stands beside a wall edge or crate; wounds = hits taken this mission, including this one); `roll = SimDice.d10(seed, turn, tick, unit, wounds)`; pass when `roll <= need`. A base unit (morale 5) therefore passes its first hit on 7 or less: **70% steady / 30% broken**. The roll and target number are never shown to the player (the log only says steady or broken).
  - **Steady:** keeps its moves (and the walk of a Move+Fire) but cannot shoot for the rest of the round: queued shots and overwatch are dropped, a shot/watch in progress ends, Move+Fire takes no shot. Logged as `{"type":"morale",...,"result":"steady"}`; dropped shots log `cancelled` with reason `suppressed`.
  - **Broken:** every remaining order stops for the round.
  - **Hollows (drones) take no morale check at all**: they never break and keep shooting after a hit.
  - A broken unit rolls no further checks that round and refuses new orders; a suppressed unit's new orders lose their shots and watches. Two hits on one unit in one tick roll separately (the hit count is part of the dice hash).
- **Seeded dice.** `SimDice.d10` is a stateless hash, so stepping, `SimResolver.resolve` and replays always agree. `SimState.seed` comes from `MissionBuilder.mission_seed` (mission id + missions completed: a retry rolls the same, missions differ); skirmishes use 1, 2, 3... per "New".
- **Tracers.** Every shot leaves a tracer until the next Go: hits solid in the shooter's colour with an impact ring, blocked shots dashed and stopping half a tile short at the cover. A hidden end is a 1.2-tile stub. Hit units show STEADY/BROKEN briefly, then a grey "no fire" pip or a red halt bar for the rest of the round. The replay viewer rebuilds the round's tracers up to the viewed tick.

### First balance read (`tools/balance_probe.gd`: first mission, AI on both sides, 40 seeds)
- Morale off (ordered fire only): 40 timeouts, 80 player and 80 enemy deaths, identical every seed.
- Morale on: 0 wins, 11 losses, 29 timeouts; 91 player deaths vs 40 enemy; player side made 131 morale checks (55 steady / 76 broken) vs enemy 80 (42 / 38).
- Reading: with morale 5 a first hit passes 40% of the time, so most hit units break. The side that advances (the player's objective run) is exposed and breaks in the open. Levers: higher base morale, wounds counting from the second hit, cover adding +1 to the check, or Hollows being fearless.

### Balance read after tuning (70/30 base, +1 cover, fearless Hollows)
Same probe, 40 seeds: 0 wins, 29 losses, 11 timeouts; 109 player deaths vs 40 enemy. Morale outcomes: player 114 steady / 35 broken, enemy 66 / 14 (about 77% steady for both). Units now stay in the fight rather than freezing, and the player's auto-played advance simply trades worse than the defenders. The probe's player is the crude "aggressor" AI, so treat it as a regression gauge, not a measure of human play; real balance needs play on a device.

### The human side is tougher (`Campaign.COMPACT_HP_BONUS`)
Every named (living) Compact merc fields with +1 hit point on top of its cast stats; Hollowed slots, enemy regulars, proxies and the Writ are unchanged. Reason: a shot has no miss chance (it hits unless cover blocks it), so aim, speed and morale barely move outcomes and hit points are the lever that matters. Balance probe (first mission, crude auto-played squad vs regulars, 40 seeds): before 0 wins / 29 losses (109 vs 40 deaths); after 40 wins / 0 losses (12 player deaths vs 120 enemy). Tests: `test_named_mercs_get_the_compact_hp_edge_but_hollows_and_enemies_do_not`. Tested and rejected: weaker enemy regulars (no effect), +1 aim, +1 morale/speed (no effect on outcomes).

## Hit chances (implemented; REPLACES "no miss chance" above)
- A shot with a clear line rolls to land. `chance = clamp(35 + 7*aim - 4*max(0, dist-2) + gear accuracy, 10, 95)` percent (`SimUnit.hit_chance_at`; constants `HIT_*` in `SimConst`). Aim 5 at 3 tiles is 66%.
- The roll is `SimDice.d100(seed, turn, tick, shooter, 1000 + shots fired)`, deterministic per mission like the morale die. A failed roll is a `miss` event: no damage, no morale check, the faster-first order of fire is unchanged, so a miss lets the slower unit's shot go ahead.
- Cover still blocks outright from that side (no roll). `evaluate_shot` stays pure and returns `{result: "hit", damage, chance}` for a clear line; only `SimTurn` rolls.
- The plan preview shows the chance ("Shot: 66% to hit, 1 damage."). Move and Fire picks a clear line over cover, then the weakest target, then the likelier hit, then the lowest id. The AI weights a shot's value by its chance (`SimAI._best_shot`).
- Tests and tools: `SimState.fixed_roll >= 0` forces every roll (TestBase installs 1, so older tests keep guaranteed hits; `test_hit.gd` turns it off).
- A miss's tracer flies 0.6 tiles past the target in a muted colour and stays until the next Go; a missed unit does not flinch.

## Enemy tiers (implemented; see ENEMY_TIERS.md)
`data/story/enemy_tiers.json`: conscript, regular, veteran (stat blocks here), elite (the Writ officers) and boss (the Provost and Orrick), each fieldable as a hollow variant (`hollow_<tier>`: 60% stats, fearless). A mission's `enemies.roster` names its tiers and counts; `Campaign.units_for_roster` builds them (ids: conscript 200, regular 210, veteran 220, hollows +100; officers 101-106, Provost 100). The AI profile follows the tier. Lint enforces each tier's first act (veteran and every hollow from act 2).

## Equipment (implemented; see EQUIPMENT.md)
Three slots (armour, weapon, mod), a stash, mission rewards and officer drops. A dead merc's kit returns to the stash; Hollows fight bare. The old flat +1 HP for the human side is now the standard-issue Compact vest.

---

## Legacy ruleset: live AP / initiative (2026-10-14; the default is now the activation engine below)

Until 2026-10-15 the game played on `InitiativeMatch` (see `TACTICS_KIT.md` for the API and `retreat-sim/game/initiative_match.gd` for the rules). The simultaneous planned turns above remain in the code as a legacy mode.

- **Live, one merc at a time.** The player's squad acts in any order, each action resolving immediately; then the enemy's turn; then the round ends.
- **AP.** 14 per merc per turn (`SimConst.AP_PER_TURN`). Step 2, diagonal 3, shot 4 (3 at aim 8+, minimum 2).
- **Interrupts.** A defender's first clear shot at a mover fires at once if its initiative (`speed*10 + aim - 3*hits_taken`) is at least the mover's; each defender gets one reaction shot per turn and one interrupt per mover; the mover stops.
- **Overwatch.** Costs all AP; fires once at the first enemy to move inside the cone with line of sight, whatever the initiative.
- **Hit chance.** `35 + 7*aim + gear - 4*(distance-2)`, clamped 10..95, on seeded dice. **Half cover no longer blocks (changed 2026-10-15 after a playtest: "cover seems to be 100%"):** a target behind half cover is hit at 30 percentage points lower (`SimConst.COVER_HIT_PENALTY`, floor 10); the preview shows the lower chance and "target in cover". Beams ignore it, full walls still stop everything. The AI values covered shots at the lower chance.
- **Route preview.** Tapping a destination shows the AP cost and marks each step where a visible enemy would shoot first.
- **Reaction gate.** A unit that ends its turn with less than one shot of AP left has no reaction shot on the enemy turn; Overwatch (all AP) is the exception.
- **Open numbers.** 14 AP is the first retune of the generous 20; tune further with play (roadmap B1).

---

## Current ruleset: activation engine (2026-10-15, the default)

- **Units act one at a time.** Each round every living unit gets exactly one activation, in initiative order whichever side it is on. Initiative = `speed*10 + aim`, fixed for the round; ties break on a seeded die, then unit id. New units join at the start of a round. Code: `game/activation_scheduler.gd`, `game/combat_state.gd`, `game/action_resolver.gd`.
- **AP.** The pool per activation is 14, read from `data/combat/ap_costs.json` (the sandbox can override it); it refills when the unit's activation begins and unused AP expires. Step 2, diagonal 3, shot 4 (3 at aim 8+, minimum 2) still come from `SimUnit` and `SimConst`.
- **Commands.** Move, shoot, arm overwatch, end activation: all through `ActionResolver.submit`. A refused command changes nothing and returns a reason code (`CombatReasons` has the player wording). Every accepted command posts an AP ledger row; `CombatInvariants` is checked after each command in the soak.
- **Overwatch.** Armed for 4 AP, not refunded. After any step an enemy takes, each armed unit whose cone, weapon range, sight and clear line cover the new tile fires once for free (initiative order, then id) and its charge is spent. A killed mover stops; a survivor carries on. Shaken, broken or dead watchers cannot react, and reactions never chain. It expires when its owner's next activation begins. Sentries start armed.
- **No automatic interrupts** (they exist only in the legacy mode). Hit chance, cover and the on-hit morale check are unchanged. Stress is dropped.
- **Enemy AI.** `ActivationAI` asks `SimAI` for a plan from the fog view, then submits one legal action at a time; a stale step is dropped and replanned, with action and replan caps and a guaranteed end of activation. New weight `w_lane` rewards tiles with a clear shot lane (default and aggressor profiles); the objective term uses walking distance.
- **Save and resume.** One autosave slot (`ResumeStore`, `CombatSave`) offered as "Resume battle" on the main menu; level test and sandbox battles only.
- **Switch.** `Session.ruleset`: `"activation"` (default), `"initiative"` (legacy live AP) or `"planned"` (legacy simultaneous ticks).
- **Measured numbers.** `docs/combat/balance-table.md` (AP sweep, 1,000-battle soak).
