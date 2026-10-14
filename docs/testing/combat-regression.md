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
