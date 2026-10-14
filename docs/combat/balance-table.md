# Combat balance table (activation ruleset)

Measured 2026-10-14 with `tools/soak_combat.gd` (AI on both sides). **Read this with care:** the squad side is a bold stand-in human that knows where the enemy is, so it wins nearly every battle. These numbers are for pacing and AP calibration, not for judging whether the enemy is beatable. Nothing here is a validated balance claim.

## Current values
| Setting | Value | Where |
|---|---:|---|
| AP per activation | 14 | `data/combat/ap_costs.json` (`max_ap`); sandbox button overrides it |
| Overwatch arm cost | 4 (not refunded) | same file |
| Step / diagonal | 2 / 3 | `SimConst` (shared with legacy modes) |
| Shot | 4 (3 at aim 8+, never below 2) | `SimUnit.shot_ticks()` |
| Initiative | speed x 10 + aim, seeded tie die, then id | `ActivationScheduler` |

## AP sweep: 40 seeded 4v4 battles on the proving ground per row (seeds 3000 to 3039)
| AP | rounds to finish | shots / activation | steps / activation | AP wasted | squad dead | enemy dead | reaction shots |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 8 | 6.0 | 0.56 | 1.60 | 19% | 0.35 | 4.00 | 106 |
| 10 | 5.2 | 0.70 | 2.00 | 21% | 0.42 | 4.00 | 117 |
| 12 | 4.3 | 0.80 | 2.50 | 21% | 0.15 | 4.00 | 123 |
| **14** | 3.9 | 0.94 | 2.95 | 22% | 0.30 | 4.00 | 121 |
| 16 | 3.3 | 1.01 | 3.43 | 22% | 0.25 | 4.00 | 111 |
| 20 | 3.1 | 1.18 | 4.24 | 23% | 0.25 | 4.00 | 109 |

Reading it: every 2 AP removed adds roughly 0.6 to 0.9 rounds and trims about half a step per activation; the proving ground is 20 wide, so at 8 AP (about 3 tiles per activation) crossing it takes five or six activations. About a fifth of AP is forfeited at every budget, so the budget is not the cause of waste. At 14 a unit averages under one shot and about three steps per activation, which matches "AP feels high in the sandbox". Tighter levels (smaller maps, more cover) will want fewer AP; a good first test is 10 to 12 on the proving ground, changing only that one number.

## Reliability gate (Phase 5)
- 1,000 seeded 4v4 battles (seeds 1000 to 1999): 1,000 finished, 0 frozen, 0 invariant problems, 0 illegal actions, 1 flagged A-B-A-B shuffle (that battle still finished), 1 idle activation with a target in range, avg 3.7 rounds, p95 plan time 40 to 71 ms on a desktop (not measured on a phone).
- Act 1 missions through the same engine (one seed each in the test suite): karsa_breakout, the_weir, pellam_dock, orchard_ring all finish with no illegal actions.
