# Enemy tiers (implemented)

Five tiers, each of the first three also fielded as a **hollow** variant. Data: `retreat-sim/data/story/enemy_tiers.json`. A mission's `enemies.roster` names its tiers and counts; `Campaign.units_for_roster` builds them.

| Tier | Role | hp | speed | aim | cqb | morale | sight | AI profile | First act |
|---|---|---|---|---|---|---|---|---|---|
| 1 Conscript | Bureau levies; Act 1 fodder | 2 | 4 | 2 | 2 | 3 | 5 | aggressor | 1 |
| 2 Regular | Line troops | 2 | 5 | 4 | 3 | 5 | 6 | aggressor | 1 |
| 3 Veteran | Act 2-3 core; use cover and range | 3 | 5 | 5 | 4 | 6 | 6 | default | 2 |
| 4 Elite | The Writ's six officers (their own stat blocks in `writ.json`) | 2-4 | 4-8 | 4-8 | 2-7 | 6-9 | 5-8 | defender | 2 |
| 5 Boss | The Provost (Orrick), when he stands in the line | 4 | 7 | 7 | 6 | 9 | 8 | defender | 3 |

**Hollow variants** (`hollow_conscript`, `hollow_regular`, `hollow_veteran`, and the Writ's own hollow officers): the tier's stats at `world.hollowing.drone_percent` (60%, minimum 1) with no morale. They never break and keep shooting after a hit. Individually weak, steady in numbers. Hollow tiers appear from Act 2.

Unit ids: conscript 200-209, regular 210-219, veteran 220-229, hollow conscript/regular/veteran 300/310/320 +index; officers 101-106; the Provost 100; player slots 1-12. Lint enforces non-overlapping ranges, known AI profiles, and each tier's first act. The combat log names them "Conscript 2", "Hollow Regular 1".

## Pacing by mission (`route.json`)
| Act | Mission | Squad | Roster |
|---|---|---|---|
| 1 | Karsa Breakout | 3 | 2 conscripts |
| 1 | The Weir | 3 | 3 conscripts |
| 1 | Pellam Dock | 4 | 3 conscripts, 1 regular |
| 1 | Orchard Ring | 4 | 2 conscripts, 2 regulars |
| 2 | Quiet Wards | 4 | 2 conscripts + Clerk, Gavel |
| 2 | Anselm | 4 | 2 regulars, 1 veteran + Seal |
| 2 | Cinder Market | 4 | 2 regulars, 1 veteran, 1 hollow regular |
| 2 | Mirror Gate | 4 | 1 regular, 1 veteran, 1 hollow regular + Notary |
| 3 | Reliquary Lane | 4 | 1 regular, 2 hollow regulars + Surveyor, Usher |
| 3 | Long Corridor | 4 | 1 veteran, 3 hollow regulars + Orrick |
| 3 | Tamsin's Rest | 4 | 2 veterans, 3 hollow regulars |
| 3 | Vesper Threshold | 4 | 4 hollow veterans + Orrick |

Contingency cards: Act 1 fields conscripts equal to the squad; later acts field regulars equal to the squad plus one hollow regular per act after the first.

## Balance read (`tools/balance_probe.gd`, 12 seeds each, crude auto-played squad in a Compact vest)
The probe plays each mission AI-vs-AI from a fresh campaign with no loot, so it is a regression gauge and not a measure of human play. Many "timeouts" are stalemates the auto-AI cannot crack (25-turn cap).

| Mission | Wins | Player deaths/run |
|---|---|---|
| Karsa Breakout | 83% | 0.50 |
| The Weir | 75% | 0.42 |
| Pellam Dock | 83% | 0.67 |
| Orchard Ring | 58% | 1.00 |
| Quiet Wards | 25% | 3.17 |
| Anselm | 75% | 1.50 |
| Cinder Market | 58% | 1.92 |
| Mirror Gate | 75% | 1.75 |
| Reliquary Lane | 8% | 3.08 |
| Long Corridor | 33% | 1.92 |
| Tamsin's Rest | 33% | 1.42 |
| Vesper Threshold | 41% | 2.58 |

Act 1 reads as 75% wins and 0.65 deaths per mission; Act 2 about 55%, Act 3 about 30%. The Act 1 target I set (at least 90% wins) was not met by this auto-squad; Act 1 is easy for it, not trivial. The Writ missions (Quiet Wards, Reliquary Lane) are the hardest because the officers hold strong positions. Gear (see `EQUIPMENT.md`) is not in the probe and should lift the human side from Act 1's carbine onwards. Rerun after any change to tier stats, rosters, hit constants or items.

## Levers
Stats and counts in `enemy_tiers.json` and `route.json`; hit constants in `SimConst`; gear in `items.json`. A tier's stats changed with no code change; counts are data. Conscript aim 3 to 2 plus the Act 1 rosters above moved Act 1 from 72% / 0.96 deaths to 75% / 0.65.
