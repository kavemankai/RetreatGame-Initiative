# Handover log

## 2026-10-14: Phase 1 done (activation engine, headless)
- **Decisions taken (owner):** D1 interleaved activations, old side-by-side mode stays (`InitiativeMatch`, `Session.ruleset`); D4 automatic interrupts kept only in the old `InitiativeMatch`, and when Phase 4 adds reactions to the new engine they go behind a flag, default off; D3 overwatch is armed for 4 AP, not refunded; D2 AP budget lives in `data/combat/ap_costs.json` at the current values (14 AP, overwatch 4).
- **New, all pure and headless, in `retreat-sim/game/`:** `combat_config.gd`, `combat_state.gd` (phases SETUP/AWAIT_COMMAND/ENDED, round, queue, AP, ledger, log), `activation_scheduler.gd` (seeded initiative = speed*10+aim, then a seeded tie die, then id; one activation per unit per round; reinforcements join at round start), `combat_action.gd` / `action_result.gd` (typed request and result), `action_resolver.gd` (move, shoot, overwatch arm, end turn; refusals have reason codes and no side effects), `combat_invariants.gd`, `shot_resolver.gd`.
- **Shared shot logic:** `InitiativeMatch._fire/_morale` now call `ShotResolver`, and `_check_winner` calls `CombatState.winner_for`. Behaviour unchanged (all old tests pass untouched).
- **Tests:** 408 tests, 2001 checks, 0 failed (`tests/test_activation.gd` adds 16). Mutation-checked: tie-break, overwatch cost, overwatch expiry, double-activation invariant each fail a test when broken. 25 seeded scripted 4v4 fights on the proving ground all finish, with the invariant helper run after every command.
- **Not done / honest limits:** step and shot prices still come from `SimUnit` (`step_cost`, `shot_ticks`) and `SimConst`, not the JSON; overwatch is armed and expires but does not fire yet (Phase 4); no view or `Session` wiring (Phase 2); AI is not hooked up (Phase 3). The scripted fights use a crude shoot-or-approach policy for both sides, not `SimAI`. They end in about 2.4 rounds with the squad winning all 25, so first-round alpha strike needs watching once the real AI is in. 25 fights take about 13 s, so the 1,000-seed soak will need roughly 9 min unless `SimVision` calls are cached.
- Rollback: `git checkout legacy-live-ap-baseline`. New files are additive.
- Next: Phase 2, route the touch UI through `ActionResolver` and add the initiative strip (needs `Session.ruleset` value, e.g. "activation").

## 2026-10-14: fork created, Phase 0 audit done
- Fork of RetreatGame at `C:\Users\kyler\Desktop\RetreatGame-Initiative`; baseline commit tagged `legacy-live-ap-baseline`; work branch `feature/initiative-combat`.
- Docs added: `docs/combat/initiative-combat-plan.md` (the redesign plan), `migration-checklist.md`, `initiative-combat-spec.md` (built vs plan, decisions D1 to D8), `docs/testing/combat-regression.md` (baseline).
- Tests: 392 pass. No gameplay code changed in Phase 0.
- Not done: `balance_probe` and `soak_campaign` baselines (they target the planned engine and are slow; skipped on request, the existing test suite is the baseline); mid-combat save audit (none exists).
- **Needs an owner decision before Phase 1:** D1 (interleaved activations), D3 and D4 (overwatch cost; keep or drop automatic interrupts), D2 (AP numbers). See the spec.
- Rollback: `git checkout legacy-live-ap-baseline`, or set `Session.ruleset = "planned"`.
- Next: Phase 1 scheduler and resolver behind a flag.
