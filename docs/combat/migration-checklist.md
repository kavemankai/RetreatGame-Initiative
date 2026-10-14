# Combat migration checklist (Phase 0 source audit, 2026-10-14)

Source: `retreat-sim/` on branch `feature/initiative-combat`, tag `legacy-live-ap-baseline`. Godot 4.6.3. All paths below are under `retreat-sim/`.

## 1. What exists today (the plan was written from the APK; this is the source truth)

| Area | Reality in source | Plan assumed |
|---|---|---|
| Engines | **Two.** `sim/sim_turn.gd` + `game/sim_match.gd` (simultaneous 20-tick planned turns, the legacy mode) and `game/initiative_match.gd` (live AP, side-alternating turns, interrupts, overwatch). | One tick loop to convert. |
| Time | The sim has **no real-time dependency**: no `_process`, no `delta`, no timers in `sim/` or `game/`. `delta` appears only in `view/board_view.gd` (glide/pose animation), `view/sound_board.gd` and the beat-playback `Timer` in `view/initiative_view.gd`. | Possible live-AP clock to remove. |
| Commands | `InitiativeMatch.move/shoot/hold_watch/end_turn` are already the only mutators and return "beats" (events plus a state clone) for the view to play back. | Needs a typed command layer. |
| Shot resolution | Pure `SimResolver.evaluate_shot` plus dice in `SimTurn._resolve_shot`, and a **copy** of that logic in `InitiativeMatch._fire`/`_morale`. | One shared resolver. |
| AI | `sim/sim_ai.gd` plans a whole turn per team from a fog view; `InitiativeMatch._run_ai_turn` executes unit by unit with up to `MAX_REPLANS` (2) replans. | One legal action at a time. |
| Fog | `SimVision.view_for/visible_tiles/visible_unit_ids`; previews and AI use them. | Must not leak hidden units. |
| Saves | Campaign saves only (`Campaign.to_dict`, `SAVE_VERSION` 2, `user://`). **No mid-combat save exists.** | Needs a migration plan. |
| Tests | 392 tests, 1910 checks, 22 files, all passing (see `docs/testing/combat-regression.md`). | Needs to be built. |

## 2. Where each tick/AP concept lives

| Concept | Defined | Consumed by |
|---|---|---|
| `SimConst.TICKS_PER_TURN` (20) | `sim/sim_const.gd:5` | `sim_turn.gd` (round end), `sim_action.gd:66`, `sim_ai.gd:125` (overwatch value), `sim_unit.gd:57` (`available_ticks`), `view/play_view.gd:15`, `view/replay_view.gd:6`, `view/timeline_bar.gd:24` |
| `SimConst.AP_PER_TURN` (14) | `sim/sim_const.gd` | `initiative_match.gd` `_pool()` only |
| Step cost 2 / diagonal 3 | `SimConst.COST_ORTHO/COST_DIAG`, `SimUnit.step_cost` (sprinter trait) | `sim_pathing.gd`, `sim_action.gd`, `initiative_match.gd` |
| Shot cost | `SimUnit.shot_ticks()` from `weapon_shot_ticks` (4), minus 1 at aim 8+, min 2 | `sim_action.gd:58`, `sim_ai.gd:97`, `plan_builder.gd:120`, `initiative_match.gd` (preview, reaction gate, interrupts, AI execute) |
| Gear `shot_ticks` | `data/story/items.json` weapon stats | `Campaign.apply_item` (`game/campaign.gd`), item summaries in `campaign.gd` and `view/sandbox_view.gd`, `story/story_lint.gd` ITEM_STATS |
| `speed` | `SimUnit.speed` | `sim_turn.gd:250-261` (fire order), `initiative_match.gd:66` (initiative), `Campaign.apply_item` |
| Interrupt reaction pool | `InitiativeMatch.reaction` | `_interrupts`, `_would_interrupt`, `route_preview` |
| Overwatch | `InitiativeMatch.watch`, `hold_watch` | `_interrupts`, `view/initiative_view.gd` (`_on_watch`, `_watch_cones`) |

## 3. Tick-model coupling to isolate (legacy only)
`sim/sim_turn.gd`, `sim/sim_plan.gd`, `sim/sim_action.gd` (tick costs), `game/sim_match.gd`, `game/plan_builder.gd`, `game/play_controller.gd`, `game/play_overlay.gd`, `view/play_view.gd`, `view/timeline_bar.gd`, `view/replay_*`. These keep working behind `Session.ruleset == "planned"` until the plan's rollback gate is met.

## 4. Gaps against the plan (to schedule)
| Plan requirement | State | Phase |
|---|---|---|
| Round/activation scheduler, one activation per unit per round, interleaved by initiative | Missing (turns alternate by side) | 1 |
| Seeded tie-break value then unit id | Missing (ties break by id only) | 1 |
| Typed action request/result plus AP ledger | Missing | 1 |
| Phases/state enum and invariants checker | Missing | 1 |
| Initiative strip UI with upcoming queue | Missing | 2 |
| Reload, stance, aimed fire | Missing (no ammo or stance model) | 2 (defer reload) |
| Distinct failure reasons in UI | Partial (invalid-shot reasons exist; move reasons do not) | 2 |
| Bounded AI activation with decision cap, repeat detector, guaranteed END_TURN | Partial (`MAX_REPLANS`) | 3 |
| Illegal-action counter, AI decision log | Missing | 3 |
| One-shot overwatch armed for 4 AP | Differs (ours costs all AP; plus automatic interrupts not in the plan) | 4 (decisions D3/D4) |
| 1,000-seed headless soak | Missing for initiative (`tools/soak_campaign.gd` and `balance_probe.gd` target the planned engine) | 5 |
| Mid-combat save/versioning | Missing | 5 |

## 5. Reusable as is
`SimGrid`, `SimLos`, `SimVision`, `SimPathing`, `SimResolver`, `SimDice`, `SimAIProfile` + `data/ai_profiles.json`, `MapData` + `data/maps/*.json`, `Campaign` (roster, gear), `MissionBuilder`, `Sandbox`, `BoardView` (touch pan/zoom, tracers), `ThemeArt`, `UnitSprites`, `SoundBoard`, and the tests of those.

## 6. Entry points
- Menu: `view/campaign.tscn` (`campaign_view.gd`) starts the level test or sandbox; `Session.ruleset` selects `view/initiative.tscn` or `view/play.tscn`.
- Initiative screen: `view/initiative_view.gd` builds `InitiativeMatch.from_match(Session.current_match)`.
- Scripted capture: `res://view/initiative.tscn -- --sandbox=1 "--do=sel 1;move 5,7;end" --shot=out.png`.
- Tests: `godot --headless --path . -s tests/run_tests.gd` (run `--import` first).
