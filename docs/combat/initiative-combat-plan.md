# RetreatSim — Initiative Combat Redesign
**Implementation plan and engineering handover · 14 October 2026 · Version 1.0**

> **Status 2026-10-15:** phases 0 to 5 are built. This is the original brief; where it differs, the built values win: AP is 14 (not 12), step 2 and diagonal 3 (not 1 and 2), shot 4; aimed fire, reload and stance are deferred (no ammo or stance model). See `initiative-combat-spec.md`, `docs/handover.md` and `docs/combat/balance-table.md`.

## Executive decision
Convert the existing continuous/live-AP combat model into a **discrete, individual-initiative, action-point tactical system**. Retain current touch controls, grid/pathfinding, line-of-sight, cover, shooting, damage, visibility and unit art where feasible. The aim is a stable, enjoyable, readable **mobile combat foundation** before changing the wider game.

> **SCOPE LOCK — ART, STORY AND LORE ARE NOT PRIORITIES.** Do not commission, generate, polish or replace character art, portraits, sprite sheets, environments, effects, audio, dialogue, codex entries, cinematics, worldbuilding, lore, campaign chapters or new missions during the combat-system conversion. Reuse existing assets and existing maps. Only make UI changes essential for interacting with and understanding the new rules. Do not redesign the strategic campaign or monetisation yet.

**Evidence boundary:** The supplied `RetreatSim-leveltest.apk` is a packaged Godot Android build, not the editable project. Its package contains compiled GDScript modules including `sim_turn`, `sim_action`, `sim_resolver`, `sim_state`, `sim_unit`, `sim_ai`, `sim_ai_profile`, `sim_pathing`, `sim_los`, `sim_vision`, and views including `initiative_view`, `timeline_bar`, `board_view`, `play_view`, plus `balance_probe` and `soak_campaign`. It also includes `data/maps/proving_ground.json` and JSON equipment and AI profiles. Exact function signatures and runtime behaviour must be verified in the source project before refactoring. Player reports that current combat and touch controls already feel good; AI is decent but needs further testing.

## 1. Product goals and constraints

### Goals (P0)
1. Turn order is always explicit, deterministic and understandable.
2. The player can move, aim/fire, reload, take cover and end a unit's activation using the familiar touch experience.
3. Player and enemy follow one rule set: AP, movement, range, cover, visibility, damage and reactions.
4. The enemy takes valid, timely, credible turns; no idle loops, illegal actions or omniscient targeting.
5. Matches resolve reliably, including death, suppression, morale changes, victory/defeat, saves and app backgrounding.
6. Rules are testable without rendering or Android UI.
7. An option exists to revert to the old mode until the new mode passes acceptance testing.

### Non-goals (explicitly deferred)
- New art, portraits, sprites, animation sets, music, sound redesign or visual identity.
- Story, lore, dialogue, characters' backstories, campaign rewrite, branching narratives or new factions.
- New maps or environment tiles beyond minimal debugging fixtures.
- Strategic layer, sector conquest, hiring economics, weapon catalog expansion, inventory overhaul, progression redesign, multiplayer and procedural missions.
- Sophisticated ballistic simulation, destructible terrain, full interrupt chains or multi-shot overwatch.

### Protect
- Existing board-camera gestures and navigation, tap/selection affordances, attack targeting, feedback and control sizes.
- Simulation calculations that are already correct; keep established damage, cover, sight and pathing formulas until baseline tests exist.
- Campaign data and associated content; freeze them rather than deleting them.

## 2. Combat model — approved baseline

### 2.1 Round and activation
- Combat is divided into **rounds**; every living, eligible unit receives **one activation per round**.
- At encounter start and each new round, create an initiative snapshot. Higher initiative activates earlier.
- **Individual initiative** means enemies and allies may interleave; it is not an entire-friendly-team-then-entire-enemy-team model.
- The active unit may perform multiple actions while it has sufficient AP; it then explicitly ends its turn (or is automatically ended when no useful affordable actions remain, subject to player confirmation setting).
- The game **does not advance combat simulation just because real-world seconds pass**. Input, animations and UI can continue, but combat-state changes require a validated command or scheduled reaction.
- Units killed/incapacitated before activation are skipped; newly created units join under documented spawn rules at the following round unless a scenario expressly overrides this.
- Never grant a unit two activations in the same round. No initiative reroll that permits an immediate double turn at the round boundary.
- On victory/defeat, stop the scheduler cleanly; do not activate another unit.

### 2.2 Initiative formula and tie breaks
**Prototype rule:** `initiative = base_speed + small, explicit modifiers` (do not fabricate values until existing speed stat is reviewed). At first, keep the calculated initiative stable for the battle; re-evaluate for future rounds only if an existing effect clearly requires it. Tie break using a precomputed, seeded tie value then persistent unit ID. Log the values and ordering. UI must disclose position in the queue.

**Potential future rules, not MVP:** equipment weight, wounds, fatigue, suppression or morale penalties, pre-battle surprise and command abilities. Resist adding these during conversion, as they confound balance testing.

**Fairness risk:** highest-initiative units may incapacitate multiple opponents before they act. Test spawn cover and round-one attrition; consider activation interleaving or cap first-round alpha-strike only if evidence requires it. Do not silently give enemies extra turns.

### 2.3 Action-point budget
Start with **12 AP per unit activation** as a deliberately provisional test configuration; this is *not* a final balance claim. AP is refilled at activation start and otherwise declines only via accepted actions. Any unused AP expires at activation end. No general banking between turns.

| Action | Initial tuning value | Notes |
|---|---:|---|
| Walk one orthogonal tile | 1 AP | Validate map pace; path preview displays sum |
| Walk one diagonal tile | 2 AP | Keep in sync with current diagonal/pathing rules |
| Snap fire | 4 AP | Uses existing hit and damage formulas |
| Aimed fire | 6 AP | Cost includes aim; accuracy benefit configurable |
| Reload | 4 AP | Defer if ammunition is not yet modeled consistently |
| Change stance | 2 AP | Only if current stance functionality exists |
| Overwatch | 4 AP | Arms one eligible reaction, spent immediately |
| End turn | 0 AP | Forfeits any remaining AP |

**Config-driven:** store AP costs and budgets outside controller/view code. No hardcoded `shot_ticks` or time-to-fire values should leak into new AP resolution. Existing `data/story/items.json` explicitly contains weapon `shot_ticks` values from the tick model; create a deliberate translation to AP costs instead of treating ticks as interchangeable with AP. Keep range, damage and accuracy independent from tempo.

**Required behaviours:** reject unaffordable actions without partial side effects; never permit negative AP; every accepted action produces a ledger entry (`AP before → cost → AP after`); permit selecting and previewing an unaffordable move without executing it; show exactly where a path stops if the player elects an affordable partial move.

### 2.4 Movement and positioning
- Preserve grid/pathfinding, diagonal restrictions, blocked cells and line-of-sight.
- Path preview shows reachable tiles, AP total, endpoint and remaining AP; optionally show a separate safe endpoint if path exceeds available AP.
- Revalidate paths immediately before executing, not only when they are previewed.
- Movement may animate tile-by-tile while its **logical resolution stays sequential and authoritative**. Decide once how reactions interrupt movement: pause the mover upon entering a triggering tile, resolve reaction, then resume if still eligible.
- No moving through occupied cells; no target tile duplication; handle knocked-out units according to existing occupancy rules.
- Distinguish camera movement from character movement and maintain existing gesture ergonomics.

### 2.5 Shooting and cover
- Preserve existing weapon range, line-of-sight, cover and hit/damage resolution first. Only adjust the action cadence and affordability.
- Tap target → display hit probability/range/cover/AP cost → confirm shot using established interaction pattern.
- Resolve a shot exactly once; avoid multiple hits if an animation completion callback fires twice.
- Never allow shots at hidden enemies merely because the AI or state store knows their coordinates.
- Retain existing morale/critical injury/death systems unchanged until combat parity is measured.

### 2.6 Reactions / overwatch
**Phase 1:** A unit may spend 4 AP to enter one-shot overwatch; it triggers only on the next qualifying visible opponent movement event before its next activation, consumes its one charge, and expires when its next activation begins. The 4 AP is spent when the mode is armed and is **not refunded** if never triggered. Reaction execution does not draw another 4 AP. These explicit semantics avoid ambiguity.

Overwatch requires valid line-of-sight, weapon availability, range, faction check and a valid trigger. A reaction cannot itself trigger another reaction (depth limit = 1 in MVP). All reaction checks run in deterministic order (e.g. initiative, then unit ID). An eliminated or incapacitated unit cannot react. If a mover dies, remaining path actions are cancelled. Add reaction logging and visual feedback using current UI assets.

## 3. State-machine architecture

### 3.1 Required combat phases
`ENCOUNTER_SETUP → ROUND_START → ACTIVATE_UNIT → AWAIT_COMMAND (player) / AI_PLAN (enemy) → VALIDATE_ACTION → RESOLVE_ACTION → RESOLVE_REACTIONS → CHECK_END → AWAIT_COMMAND or END_ACTIVATION → NEXT_UNIT → ROUND_START ... → ENCOUNTER_END`

Allow animations to be separate from simulation transition sequencing: events drive presentation, never the reverse. Do not grant AP when an animation ends or rely on frame delta for damage. Maintain a single authoritative `CombatState`.

### 3.2 Proposed module responsibilities (adapt names to actual source)
| Existing packaged component | New or preserved responsibility |
|---|---|
| `sim_turn` | Refactor old tick loop into round/activation scheduler; feature-flag the original mode |
| `sim_action` | Typed actions, AP costs, targeting requirements, eligibility |
| `sim_resolver` | Validate and atomically resolve actions, publish resulting events |
| `sim_state` / `sim_unit` | Active unit, round index, remaining AP, alive status, overwatch flag, initiative/tie data |
| `sim_ai` / `sim_ai_profile` | One legal action selection at a time, plus plan/score for full activation |
| `sim_pathing` / `sim_grid` | Reachability and authoritative traversal cost |
| `sim_los` / `sim_vision` | Eligibility and visibility, shared by player/AI |
| `initiative_view` / `timeline_bar` | Display round, current combatant, upcoming queue and status, not realtime countdown |
| `board_view` / `play_view` | Keep selection, touch gestures, action buttons and feedback, updated for active-unit permissions |
| `balance_probe` / `soak_campaign` | Adapt to new scheduler and regression gates |

The APK only proves the files exist; **source inspection determines actual edit locations**. Do not patch/decompile the APK as the long-term development workflow. Obtain the Godot source tree and version control history.

### 3.3 Interfaces and invariants
Suggested action request: `{actor_id, action_type, target_cell?, target_unit_id?, weapon_id?, metadata?}`.
Suggested result: `{success, failure_reason?, state_changes, ap_cost, events[], next_phase}`.

Invariants after every committed action:
1. Exactly one active combatant unless transitioning between turns.
2. All AP values are within `[0, max_ap]`.
3. A unit has activated no more than once this round.
4. No dead or incapacitated unit remains active or on valid overwatch.
5. Every map tile has legal occupancy and movement history.
6. Every resolved attack obeys range, sight, faction and AP rules.
7. Simulation only progresses through commands and scheduler events, not frame updates.
8. A match cannot remain forever in `AI_PLAN`, `RESOLVE_ACTION` or `END_ACTIVATION`.

Prefer immutable or auditable action events where practical. Keep RNG seeded at battle start so scenarios can be replayed identically from commands and initial state.

## 4. Enemy AI conversion and strengthening

### 4.1 Reuse, do not discard
The APK includes `data/ai_profiles.json` with `default`, `aggressor`, `defender`, `sentry` and `guard` profiles. Their weights include damage, kill, exposure, cover, preferred range, objective and watch. Preserve those as **behavioural scoring weights** while changing the execution loop to discrete activations. They are not proof of actual good AI; instrument and test outcomes.

### 4.2 AI turn loop
1. Determine what the unit is legitimately able to perceive; use memory of last seen targets only if modeled.
2. Enumerate legal actions given AP, tile occupancy, line of sight, weapon and states.
3. Score plausible actions and short sequences: shoot now, move into cover + shoot, move to flank, reload, approach objective, defend/overwatch, withdraw.
4. Choose a bounded sequence; execute **one action at a time through the shared resolver**, then rescore if the world changes.
5. End turn when no positive-value legal action remains, when AP is exhausted or when a strict maximum action count is reached.

Avoid the classic failure where an enemy oscillates between two tiles, attempts an impossible shot or loops until the app hangs. Add a per-activation **decision and action cap**, duplicate-state detector and a guaranteed fallback `END_TURN`.

### 4.3 Behaviour objectives
- Aggressors pressure weak or isolated targets but avoid obviously suicidal routes.
- Defenders favour covered positions, protected sightlines and overwatch.
- Sentries guard important approaches and respond to revealed threats.
- All profiles use the same shot/cover/hit rules as human players.
- AI must not coordinate with information from concealed enemies unless it has a valid observation/shared-intelligence mechanism.
- AI decisions should be quick on actual midrange Android hardware; profile real-device response time, not only desktop tests.

### 4.4 AI quality tests
- Open-field advance; covered defender; flankable defender; narrow-door chokepoint; low-health retreat; low-AP decision; target disappears; wounded ally; reload required; reaction threat; unreachable target; two enemies coordinating under shared threat.
- Log chosen action, alternative scores, reason, AP before/after, sightline and enemy-known information.
- Track illegal-action rate (target **zero**), idle-turn rate, path oscillation, unfair information use, hit rate, casualties, cover usage and completion rate. Don't mistake high player casualties for intelligent AI.

## 5. Mobile user-experience conversion

### Essential interface
- Persistent initiative strip with highlighted active unit, upcoming 4–6 units and round label.
- Active unit clearly outlined on the board; other allies selectable for inspection but **not commanded** outside their activation.
- Prominent AP counter with affordability preview on action selection.
- Contextual move/attack targets; keep the current successful input scheme.
- Clear **End Turn**, distinct from `End Round`; provide optional fast/confirm settings later.
- Differentiate `Not enough AP`, `Out of range`, `Line of sight blocked`, `Not your activation` and `Target not visible`.
- Overwatch armed/expired state visible without requiring new character artwork.
- Animation speed option and skip option for repeated movement/fire sequences, without skipping gameplay events.

### Gesture rules
- Preserve pinch zoom, pan and tap ergonomics already judged good by the player.
- A tap should not accidentally fire while panning or selecting an off-turn ally.
- Selecting a tile displays path + AP before commitment; selected action state is dismissible.
- Maintain generous targets for phone screens; test with UI scaling and gesture conflicts.
- App background/resume must not advance initiative or resolve hidden actions.

## 6. Balance strategy

Change the **time/turn mechanic only** at first. Do not simultaneously rebalance every weapon, alter damage curves, redesign cover or add injuries: this would make causes of improvement/regression impossible to identify.

After baseline, calibrate 12-AP starting budget to actual map dimensions, engagement distances and action durations. The packaged `proving_ground.json` is 20×16 cells with 4 player spawns and 12 possible enemy spawns; begin with **4v4 encounters** by selecting four enemy spawn points. Record average movement distance, shots/activation, AP wasted, rounds-to-resolution, casualties and percentage of turns with at least two meaningful options.

Principles: (1) advancing under fire must cost resources; (2) cover is meaningful but not mandatory for every action; (3) moving then shooting should commonly be possible; (4) no single attack type dominates all ranges; (5) first-turn initiative advantage must not decide most fights; (6) the player should rarely watch a long, noninteractive enemy sequence.

Only after these pass: test suppression, equipment effects, reactive fire improvements, and variable initiative one at a time.

## 7. Implementation phases and exit gates

### Phase 0 — Baseline and source audit (P0)
Tasks: acquire original Godot source, identify engine/runtime version, branch `feature/initiative-combat`, tag last functional live-AP build, document entry points and dependencies, capture existing test match videos, seed/log initial battle state, run current probe/soak scripts. Map every use of live timers, `delta`, `shot_ticks`, speed and AP. Snapshot current UX and existing campaign save format.

**Exit:** architecture map; reproducible old-build baseline; tracked migration checklist; reversible branch. If source isn't available, stop modifying gameplay until it is recovered.

### Phase 1 — Pure scheduler and commands (P0)
Tasks: implement activation scheduler and state phases, persistent actor identity, seeded initiative sort, new `APState`, command validation, end-turn/next-round, death/skip and victory/defeat. Keep a legacy mode behind a feature flag while wiring headless or debug-console simulation.

**Exit:** 4v4 sample can complete repeated scripted fights without UI; no unit twice per round; no negative AP or scheduler lockups.

### Phase 2 — Player actions and touch UI (P0)
Tasks: adapt movement path costs/previews, shooting, reload if present, turn termination, selection rules and initiative strip. Preserve gestures; provide AP/status/error feedback. Route *all* actions through one authoritative resolver; detach animation callbacks from game-state mutation.

**Exit:** a human can finish the proving-ground scenario on Android without debugging tools, using all permitted actions and no ambiguous input.

### Phase 3 — Enemy activation AI (P0)
Tasks: rewire existing profiles to action enumeration, constrained short-horizon planning, legal command submission, fallback/end-turn, deterministic tie-breaking, visibility enforcement and AI turn diagnostics.

**Exit:** 100 automated representative battles with zero illegal actions, zero frozen turns and no repeated-action loops; human sanity playtest finds credible basic tactics.

### Phase 4 — Reactions / overwatch (P1)
Tasks: implement one-shot overwatch with transparent AP cost, movement interruption, deterministic reaction sequencing, expiration and UI feedback. Test death during traversal and competing reactions.

**Exit:** scripted trigger tests pass; no recursive reaction loops, duplicate shots, lost turns or invalid movement resumes.

### Phase 5 — Reliability and balance (P0 for reliability / P1 for tuning)
Tasks: seeded soak tests, manual mobile testing, fatigue/edge cases, save/load or restart behavior, app suspend/resume, UI input cancellation, combat telemetry, AP/weapon/initiative calibration and targeted AI adjustments.

**Exit:** at least 1,000 seed-varied **headless** 4v4 encounters with zero deadlocks, no unresolved turns, zero illegal AP/state transitions; Android playtests and performance acceptance completed. Re-run campaign smoke tests to ensure it still loads and exits battles correctly.

### Phase 6 — Integration and release candidate (P0)
Tasks: disable legacy mode by default once stable; preserve a rollback path until release; run regression matrix on included missions, verify outcome propagation and saves, package Android build, review crash reports and document known limitations.

**Exit:** release-candidate build, test report, migration notes, measured gameplay metrics and approval based on mobile playtesting. **Do not begin new art/story/lore production as a substitute for unmet combat gates.**

## 8. Testing plan and measurable acceptance

### Automated unit tests
- Deterministic sorted queue; equal initiative; killed unit skipped; spawn mid-round; multi-round order stable; victory at last action.
- AP full/spent/insufficient; exact-affordability; zero-AP; cost cannot be negative; one action cannot be paid twice; end-turn expiry.
- Legal/illegal paths; diagonal costing; blocked tile; changing occupancy; movement interrupted by death; no duplicate positions.
- Line-of-sight with half/full walls; fog-of-war hidden targets; out-of-range and cover modifiers; fixed seeded hit result.
- One-shot overwatch trigger/no-trigger/expiry; invalidated overwatcher; deterministic multiple reactions; no reaction recursion.
- AI turn maximum budget and legal actions, including no-target and unreachable-target cases.
- Save/reload and resume at player activation, AI activation and between action and presentation, if supported.

### Integration test matrix
- 1v1, 2v2, 4v4, 4v8; crowded corridor; open field; objective defence; multi-round battle; enemy reinforcement; full campaign mission smoke test.
- Screen-size/UI scale checks, portrait/background interruptions, rapid repeated taps, accidental drags, zoom/pan during selection, low battery and performance on Android.

### Targets to ratify with testing
- **0** illegal actions/AP violations and **0** frozen turn loops across **1,000** automated seeds.
- **100%** reproducibility for same seed + initial state + command sequence.
- No observable pause or unresponsive touch during AI planning on target device; record 95th-percentile decision latency and optimize if visible.
- Complete at least **10 external or blinded mobile playtest sessions** and report comprehension, combat duration, frustrating waits and control mistakes.
- 4v4 combat can be completed and understood without explaining initiative verbally to the tester.
- All existing campaign routes and data files still load in a smoke test; content changes are not needed to demonstrate tactical success.

**Measurement disclaimer:** numeric AP costs and encounter-length targets are hypotheses for testing, not validated balancing. Do not report these as verified until measured.

## 9. Source migration and backward compatibility

- Do not delete or change the packaged narrative JSON during the scheduler refactor.
- Audit old saves and combat snapshots for tick position, action progress, AP regeneration timers, active projectile queues and UI countdown state.
- Version saved data. Campaign-level saves should ideally remain loadable; tactical mid-combat saves may require an explicit migration or a documented "restart encounter" fallback, not silent corruption.
- Convert old weapon `shot_ticks` data to new action AP values using a single adapter/config table. Keep original source data available during comparison.
- New save state should include round, initiative queue, activated flags, active unit, AP, RNG seed/state, unit state, overwatch charges and map occupancy.
- Provide developer debug controls for next actor, force turn end, print queue, AP ledger, AI scores and replay seed; never ship arbitrary debug bypasses in production.
- Keep feature flag until release-candidate validation passes; use the same content and maps for A/B evaluation.

## 10. Highest risks and mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Changing the combat clock breaks many old scripts | High | Audit tick dependencies and gate refactor; adapt one layer at a time |
| Losing the controls that already feel good | High | Preserve existing views and gestures; change only affordances that must express new rules |
| Enemy turns become long or monotonous | High | Bound AI search; concise animation; track wait time and offer speed controls |
| Initiative creates first-turn wipeouts | High | Record opening-round attrition; test cover/spawns before altering entire initiative system |
| Illegal action or AI infinite loop | High | Single resolver, invariants, time/action caps, deterministic soak tests |
| Overwatch breaks movement or reactions cascade | High | One-shot, depth-limited, event-driven reactions; test death mid-path |
| Combat changes corrupt saves/campaign outcomes | High | Schema-versioned saves and campaign smoke tests |
| Premature content expansion diverts resources | High | Scope lock; no new assets, story, lore, missions or major meta-systems until combat gates pass |
| Large-scale rebalance obscures root causes | Medium | Change one balancing dimension per build; preserve seeds and telemetry |

## 11. Team/AI-coding-agent execution rules

1. First inspect the editable Godot project; do not assume the APK's compiled scripts reveal complete source structure.
2. Produce a dependency map and concrete file-edit list before changes.
3. Work in small commits per phase, retain an always-runnable Android build and test each change.
4. Reuse existing assets; don't generate new images, rewrite the campaign or alter lore.
5. Do not rewrite game logic in view/controller code; all gameplay commands pass through the shared resolver.
6. Every new game rule needs deterministic tests and a concise explanation in the combat specification.
7. No "AI cheating" with hidden target information or special AP rules.
8. Record decisions, regressions, open defects and the most recent build/test results in a handover log.
9. If an existing subsystem is stable, leave it alone unless conversion requires intervention.
10. At the end of each phase, supply: touched files, tests executed, measured results, known defects, rollback instructions and next tasks.

### Suggested repository documents
- `docs/combat/initiative-combat-spec.md` — source of truth for rules and states.
- `docs/combat/migration-checklist.md` — old tick/AP dependency mapping, source files and migration status.
- `docs/combat/balance-table.md` — current action AP costs with versioned test metrics.
- `docs/testing/combat-regression.md` — deterministic tests, seeds and pass/fail outcomes.
- `docs/handover.md` — concise implementation log and remaining risks.

## 12. Priority backlog

| Priority | Work item | Dependency |
|---|---|---|
| P0 | Source audit and existing-build baseline | None |
| P0 | Discrete combat scheduler and typed action resolver | Audit |
| P0 | Single source of AP truth + cost configuration | Scheduler |
| P0 | Initiative calculation, deterministic queue, one activation per round | Scheduler |
| P0 | Adapt existing touch movement/aim/shoot/end-turn to queue | Resolver, AP |
| P0 | Convert AI from continuous processing to bounded legal activations | Resolver, scheduler |
| P0 | Regression tests, logs, action ledger, Android controls | Every phase |
| P1 | One-shot reaction/overwatch model | Resolver, path events |
| P1 | Pacing and combat-balance pass | Playable 4v4 |
| P1 | Save/migration and campaign smoke-test hardening | Stable rules |
| P2 | Advanced initiative modifiers, suppression, improved flanking | Reliable baseline |
| **Deferred** | **New art, sound, animation polish, story, lore, worldbuilding, campaign, metagame** | **Only after combat approval** |

## 13. Definition of done

This redesign is complete when a player can start a mobile encounter, immediately understand who acts next, use existing intuitive controls to make multiple meaningful AP-based decisions, watch enemies respond legally and competently, use a simple reaction mechanic, finish the battle without hangs or invalid states, and resume or restart safely. The result must be backed by deterministic automated battles and mobile playtesting.

**Not a completion criterion:** new character art, more lore, revised dialogue, expanded campaign, new factions, cosmetic UI polish or an enlarged feature list. None of those substitute for functioning initiative, AP economy, controls and AI.

## 14. Next immediate engineering action

Obtain the editable Godot project/repository and make the Phase 0 source audit. Map exactly where `sim_turn` advances time, how `sim_action` and `sim_resolver` accept actions, how `sim_ai` schedules decisions, where `shot_ticks` is consumed, and which view currently owns tactical input. Build a 4v4 proving-ground reproducible baseline. **Then implement the scheduler behind a feature flag**, before altering weapon balance or campaign content.
