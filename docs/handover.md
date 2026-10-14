# Handover log

## 2026-10-14: fork created, Phase 0 audit done
- Fork of RetreatGame at `C:\Users\kyler\Desktop\RetreatGame-Initiative`; baseline commit tagged `legacy-live-ap-baseline`; work branch `feature/initiative-combat`.
- Docs added: `docs/combat/initiative-combat-plan.md` (the redesign plan), `migration-checklist.md`, `initiative-combat-spec.md` (built vs plan, decisions D1 to D8), `docs/testing/combat-regression.md` (baseline).
- Tests: 392 pass. No gameplay code changed in Phase 0.
- Not done: `balance_probe` and `soak_campaign` baselines (they target the planned engine and are slow; skipped on request, the existing test suite is the baseline); mid-combat save audit (none exists).
- **Needs an owner decision before Phase 1:** D1 (interleaved activations), D3 and D4 (overwatch cost; keep or drop automatic interrupts), D2 (AP numbers). See the spec.
- Rollback: `git checkout legacy-live-ap-baseline`, or set `Session.ruleset = "planned"`.
- Next: Phase 1 scheduler and resolver behind a flag.
