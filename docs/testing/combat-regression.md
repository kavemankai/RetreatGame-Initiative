# Combat regression baseline (2026-10-14, tag `legacy-live-ap-baseline`)

Command: `godot --headless --path retreat-sim -s tests/run_tests.gd` (after `--import`).
Result: **392 tests, 1910 checks, 0 failed.** A few "String formatting error" lines in `test_campaign` and `test_initiative` are pre-existing noise from test messages containing a percent sign; they do not fail anything.

| File | Tests | Covers |
|---|---:|---|
| test_sim / test_turn / test_combat / test_hit / test_vision / test_ai | 29 / 27 / 18 / 11 / 12 / 14 | Sim core: LOS, cover, tick order, hit rolls, fog, AI planning |
| test_initiative | 19 | AP pool, step beats, reach, shooting, interrupts, overwatch, end turn, morale, goals, determinism, route preview, reaction gate |
| test_sandbox | 7 | Sandbox config, stat and gear edits, placement rules, ids, initiative play |
| test_game / test_live / test_regressions / test_review_fixes | 47 / 33 / 14 / 7 | Planned-mode controller, live play, regressions |
| test_campaign / test_missions / test_levels / test_maps / test_tiers / test_equipment / test_story | 33 / 12 / 13 / 11 / 10 / 18 / 20 | Campaign, mission building, Act 1 maps, tiers, gear, data lint |
| test_iso / test_replay / test_sound | 21 / 6 / 10 | Board projection and rendering helpers, replay model, sound |

## Gaps to fill for the redesign (not yet tests)
- Activation queue order, tie-break, one activation per round, mid-round spawns.
- Typed action validation and the AP ledger (AP before, cost, AP after); no partial side effects on rejection.
- Invariant checker; 1,000-seed headless 4v4 soak with zero illegal states or stuck turns.
- AI activation cap, repeat-state detector, illegal-action rate of zero.
- Same seed plus initial state plus commands gives an identical event log (partly covered by `test_the_mode_is_deterministic_with_real_dice`).
- Campaign smoke test: the campaign still loads and exits a battle with the new mode on.

## Phase 5 update (2026-10-14)
**448 tests, 2171 checks, 0 failed.** Gate: 1,000 seeded 4v4 AI-vs-AI battles, all finished, 0 frozen, 0 invariant problems, 0 illegal actions. Repeat: four parallel runs of `godot --headless --path . -s tools/soak_combat.gd -- --battles=250 --first=1000 --enemies=4` (each about 6.5 minutes), changing `--first` per run. AP sweep: `-- --battles=40 --first=3000 --enemies=4 --ap=N`. Mission smoke: `-- --battles=4 --mission=karsa_breakout` (also the_weir, pellam_dock, orchard_ring). `tests/test_combat_save.gd` covers save, resume and refusal of bad saves.

## Phase 3 update (2026-10-14)
**440 tests, 2130 checks, 0 failed.** Soak (`tools/soak_combat.gd -- --battles=100`): 100 of 100 finish, 0 illegal actions, 0 frozen, 0 invariant breaks, 0 oscillations, avg 4.7 rounds, 2 idle-with-target of 2,767 activations, p95 plan 45 ms (desktop). Command for repeat: `godot --headless --path . -s tools/soak_combat.gd -- --battles=100` (about 3.5 minutes). `tests/test_ai_scenarios.gd` holds the scenario and diagnostics tests.

## Phase 2 update (2026-10-14)
**418 tests, 2057 checks, 0 failed.** `tests/test_activation_match.gd`: enemy-first start hands over to a merc, one beat per move step, off-turn commands refused with a reason, End Activation plays enemy activations and returns to a merc, a lone enemy acts every round, snapshots only when asked, six full games finish with zero AI refusals, strip hides unseen enemies, reason wording, ruleset plumbing.

## Phase 1 update (2026-10-14)
**408 tests, 2001 checks, 0 failed.** `tests/test_activation.gd` covers: config load and fallback, queue order across teams, seeded tie-break and replay, one activation per round, dead-unit skip, AP refill and expiry, rejections with no side effects, hidden targets, ledger arithmetic, overwatch cost and expiry, victory stops the scheduler, invariant checker catches corruption, reinforcements at round start, shared shot resolver parity, 25 scripted 4v4 fights with invariants after every command, and same-seed replay. Still open: 1,000-seed soak (Phase 5), AI illegal-action rate (Phase 3), save/resume, campaign smoke with the new mode.
