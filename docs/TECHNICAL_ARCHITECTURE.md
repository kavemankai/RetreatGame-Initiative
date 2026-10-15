# Technical architecture

Short form of `TACTICS_KIT.md` (the long form, with the layer rules) plus what matters for building and shipping.

## Layers (dependencies point down only)
| Layer | Folder | Notes |
|---|---|---|
| Sim core | `retreat-sim/sim/` | Pure integer simulation: `SimState`, `SimGrid`, `SimUnit`, `SimLos`, `SimVision`, `SimPathing`, `SimResolver`, `SimDice` (seeded), `SimConst`, `SimAI`. No nodes, no engine time, no floats. |
| Activation engine (default) | `retreat-sim/game/` | `CombatState`, `ActivationScheduler`, `ActionResolver`, `ActivationMatch`, `ActivationAI`, `ShotResolver`, `CombatInvariants`, `CombatSave`, `ResumeStore`. |
| Campaign | `retreat-sim/game/campaign.gd`, `mission_builder.gd`, `map_data.gd` | Roster, stash, gear, levelling, economy, endings, difficulty, saves; turns a mission into a match. |
| Story data | `retreat-sim/data/story/*.json`, `retreat-sim/story/` | Cast, route, scenes, items, tiers, world, map; `StoryLint` runs inside the test suite. |
| Views | `retreat-sim/view/`, `view/screens/`, `view/ui/` | Control-node screens; read events and state only. `CoachModel` is the pure rules for the first-mission tips. |
| Legacy rulesets | `sim_turn.gd`, `initiative_match.gd`, `play_view.gd` | Planned and live-AP modes kept as a rollback; not reachable in the campaign-only builds. |
| Tools and tests | `retreat-sim/tools/`, `retreat-sim/tests/` | Soaks, map and asset scripts, headless suites. |

## Data flow in a fight
`Campaign` -> `MissionBuilder.build` (map JSON, tier units, roles, goal, reinforcements) -> `SimMatch` -> `CombatState` + `ActivationMatch` -> `InitiativeView` issues commands, reads `ActionResult.beats`. Outcome returns through `MissionBuilder.outcome_for` and `Session.pending_outcome`; `Campaign.complete_mission` applies it exactly once.

## Determinism
Dice are a seeded clock (`SimDice`); the mission seed is stable for the same mission at the same point in the campaign, so a retry rolls the same. Combat saves store the dice clock, so a resumed fight plays out identically (tested).

## Persistence
| File (`user://`) | Written by | Rules |
|---|---|---|
| `campaign.json` | `campaign_view._save` | Versioned (`SAVE_VERSION` 3); `Campaign.save_problem` rejects wrong versions, missing or mistyped keys, unknown difficulty; a rejected file is never overwritten or deleted; `difficulty` is optional (older v3 saves load as Standard) |
| `combat_resume.json` | `ResumeStore` | One silent autosave per battle, cleared when the fight ends; untrustworthy files are discarded |
| `sound.json` | `SoundSettings` | Per-bus levels and mute, clamped on load |

## Build and release
| Output | Command | Where |
|---|---|---|
| Tests | `godot --headless --path retreat-sim -s tests/run_tests.gd` | exit 1 on any failure |
| Android full campaign | `powershell -File retreat-sim/tools/export_android.ps1 -Full` | `retreat-sim/build/TheLongRetreat-1.0.0.apk` |
| Windows | `powershell -File retreat-sim/tools/export_windows.ps1` | `dist/windows/TheLongRetreat.exe` |

Export presets (`retreat-sim/export_presets.cfg`): "Android" (everything, dev), "Android Level Test", "Android Campaign" (Act 1 only demo, `act1_only`), **"Android Full Campaign"** (`campaign_only`, all acts), **"Windows Desktop"** (`campaign_only`). The `campaign_only` feature tag hides skirmish, level test and sandbox from the menu; `act1_only` stops the campaign at the end of Act 1. Needs Godot 4.6.3 templates, JDK 17, Android SDK build-tools 35.0.1 (APK is debug-signed: fine for sideloading, not the Play Store).

## Developer capture flags
`--demo=<menu|map|briefing|...>`, `--campaign=ID --live=1`, `--do="sel 1;move 3,9;end"`, `--shot=path.png`. **They write to the real `user://campaign.json`** (the demos create a throwaway campaign and save it); back the save up first.
