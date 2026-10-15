# Test results (run 2026-10-16 on the build machine, Godot 4.6.2 mono, Windows 11)

Everything below was run in this session. Items not run are listed at the end.

## Automated
| What | Command (from `retreat-sim/`) | Result |
|---|---|---|
| Full headless suite | `godot --headless --path . -s tests/run_tests.gd` | **576 tests, 2,990 checks, 0 failed** (exit 0). Baseline at the start of the pass was 560 / 2,918. New: `test_coach.gd` 7, `test_difficulty.gd` 9. The "Parse JSON failed" lines in the output come from tests that feed deliberately corrupt saves |
| Story lint | `-s tools/lint_story.gd` | clean |
| Real-scene driver | `-s tools/e2e_app.gd` | **16 of 16 pass, 0 failed**: menu, new campaign, map, prep, loadout round trip, deploy, battle scene loads, outcome applied once, result/salvage/level-up chain, map at next stop, save on disk. (It first failed after the menu label gained the difficulty text; the driver was updated and re-run.) |
| Combat soak, 100 seeded 4v4 battles | `-s tools/soak_combat.gd -- --battles=100` | 100 finished, 0 frozen, 0 invariant problems, 0 illegal AI actions, 0 oscillations; squad wins 97; p95 plan time 30 ms on this PC |
| Scripted campaigns to the endings | `-s tools/soak_campaign.gd -- --scripted` | both reach an ending (`long_watch`, `roll_read`) |
| Per-mission soak, 30 battles each, stand-in AI squad, fresh roster, Standard | `-s tools/soak_combat.gd -- --battles=30 --mission=ID` | 0 frozen, 0 invariant problems, 0 illegal actions in all 12. Squad wins: Karsa 30, Weir 30, Pellam 30, Orchard 29, Quiet Wards 30, Anselm 29, Cinder Market 30, Mirror Gate 30, Reliquary Lane 30, Long Corridor 19, Tamsin's Rest 30, **Vesper Threshold 1** |
| Difficulty comparison, 40 battles | same, `--difficulty=standard|story` | Long Corridor 24 vs 37 wins; **Vesper Threshold 1 vs 32** |
| Whole campaigns on the activation engine, 8 runs each | `-s tools/soak_activation_campaign.gd -- --runs=8 --difficulty=...` | Standard: **0 of 8** reach the ending (all end `squad_lost`, after 5-10 missions). Story: **6 of 8** reach the ending (the other 2 lose at mission 12). 0 engine problems in both. The stand-in squad never changes gear or levels up, so these are floors, not predictions for a person |

## Packaged builds
| Artifact | Check | Result |
|---|---|---|
| `dist/windows/TheLongRetreat.exe` (105.1 MB, SHA-256 `780A10E2...AE2A65`) | Launched outside the project folder with `--demo=menu` and `--demo=map`, screenshots read | Starts, exits 0, shows the campaign-only menu (no skirmish, level test or sandbox) with the Story default, renders the route map from the embedded pack |
| `dist/android/TheLongRetreat-1.0.0.apk` (31.7 MB, SHA-256 `C274362A...E4B5D8`) | `aapt2 dump badging`, `apksigner verify`, zip listing | package `com.kyler.retreatsim.campaign`, versionName 1.0.0 / versionCode 2, label "The Long Retreat", min SDK 24, arm64-v8a only; APK Signature Scheme v2 and v3 verify (debug key); contains Act 2-3 data, themes and music |

## Not run (and why)
- **The APK was not installed or launched**: no Android device or emulator is attached to this machine.
- No human playtest of Acts 2-3, no on-device performance, battery or thermal measurement, no touch-input checks (accidental drags, rapid taps).
- Code coverage was not measured (no coverage tool is set up for GDScript here); the 80% figure in the project rules is therefore unverified.
- No mutation check of the two new suites; their assertions test the specific numbers (+1 hp, -15 accuracy, tip text, save round trip).
- The packaged exe was not driven by scripted input through a full mission (the dev-project driver `e2e_app.gd` covers that flow).
