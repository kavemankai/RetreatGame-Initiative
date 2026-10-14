# Initiative combat spec: as built vs the redesign plan

Status 2026-10-14. **Decided by the owner: D1 adopt the plan (flag for the old mode), D2 config table at current values, D3 arm for 4 AP, D4 interrupts behind a flag, default off. D5 to D8 as recommended.** "Built" is `InitiativeMatch` today; "Plan" is `docs/combat/initiative-combat-plan.md`. Rows marked **decision** need an owner call before Phase 1 starts; the recommendation is mine and nothing has been changed yet.

| # | Topic | Built | Plan | Recommendation |
|---|---|---|---|---|
| D1 | Turn structure | Whole squad acts live in any order, then the enemy, then the round ends. | One activation per unit per round, units interleave by initiative; the queue picks the active unit. | **Adopt the plan.** It makes order explicit. The "love AP" feedback was for the current model, so keep both behind a flag until D1 is playtested. |
| D2 | AP economy | 14 AP per unit per turn; step 2, diagonal 3, shot 4 (3 at aim 8+). | 12 AP; step 1, diagonal 2, snap 4, aimed 6, reload 4, stance 2, overwatch 4. | **Config table first**, defaults equal to the current numbers (14/2/3/4). Retune after the scheduler works, one variable per build. |
| D3 | Overwatch | Costs all AP; fires once at the first enemy to move into its cone, regardless of initiative. | Arm for 4 AP (not refunded), one shot, expires at the next activation. | **Adopt the plan's 4 AP arm**; keep the cone and the one-shot rule. |
| D4 | Interrupts | Automatic: a first clear shot at a mover from a unit with equal or higher initiative and reaction AP. | None; only armed overwatch. | **Decision needed.** The plan removes the JA2-style interrupt you liked. Option: keep interrupts behind a flag for an A/B playtest, default off. |
| D5 | Initiative | `speed*10 + aim - 3*hits_taken`, live. | Stable per battle; base speed plus small explicit modifiers; seeded tie value then unit id. | **Adopt the plan:** fix at round start from `speed*10 + aim`, drop the wound term for the MVP, add a seeded tie value. |
| D6 | Reload, ammo, stance | None. | Reload 4, stance 2, "if present". | **Defer;** there is no ammo or stance model. |
| D7 | Morale | A hit unit rolls morale: steady = cannot shoot until its next turn, broken = no AP. | Keep unchanged. | Keep. |
| D8 | AI | Utility planner, whole-unit plan, up to 2 replans. | One legal action at a time, decision cap, repeat detector, END_TURN fallback. | Adopt in Phase 3. |

## Proposed order for this repo
1. **Phase 0:** audit, baseline, checklist. Done.
2. **Phase 1:** new `CombatState`, `ActivationScheduler` and `ActionResolver` in `game/` (pure, headless), configured by `data/combat/ap_costs.json`, reusing `SimResolver`, `SimVision`, `SimPathing` and `SimDice`. Port `InitiativeMatch._fire/_morale` into the shared resolver so both rulesets call it. Legacy modes stay behind `Session.ruleset`.
3. Phases 2 to 6 as in the plan.

## Invariants to enforce in code (plan section 3.3)
One active combatant; AP within `[0, max]`; one activation per unit per round; no dead unit active or on overwatch; legal occupancy; every attack obeys range, sight, faction and AP; no sim progress without a command; no stuck phase. Each becomes an assertion in a `CombatInvariants.check(state)` helper that the soak calls after every command.
