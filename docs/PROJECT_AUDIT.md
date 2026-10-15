# Project audit (2026-10-16)

Audit of `RetreatGame-Initiative` (working tree on branch `agent/complete-game`, cut from `feature/initiative-combat` at `d43334d`) made at the start of the "complete the game" assignment. Everything below was measured or read in the repository on this machine; where something could not be checked it says so.

## What the project is
**The Long Retreat** (project name "Retreat Sim"): a portrait, phone-first, tap-to-act squad tactics game in an isometric sci-fi retreat setting. Eight named mercs, a 12-mission three-act campaign, permadeath with the Hollowing (a dead merc is replaced by a weaker drone), a retreat economy (Procession, Reserves, Remembrance) and four endings. The game is a private project; the intended audience for this build is one person (the owner's father).

## Stack
| Item | Value |
|---|---|
| Engine | Godot 4.6 (dev runs on 4.6.2 mono; exports use 4.6.3 and its installed templates) |
| Language | GDScript only (about 11,700 lines of game code, 6,800 lines of tests) |
| Renderer | GL Compatibility (OpenGL ES 3 on phones) |
| Targets | Android arm64 (debug-signed APK) and, added in this pass, Windows x86_64 (single exe) |
| Build | `tools/export_android.ps1 [-Full]`, `tools/export_windows.ps1`; presets in `retreat-sim/export_presets.cfg` |
| Tests | headless suite `tests/run_tests.gd` (explicit suite list, discovers `test_*`), plus soak tools in `tools/` |
| Assets | pixel/iso sprites and tiles (AI-generated, then sliced and normalised by scripts in `art/`), 38 synthesised WAV files (`art/make_sounds.py`), code-drawn UI |

## Architecture in one paragraph
`sim/` is a pure, deterministic, integer-only turn simulation (RefCounted only). `game/` holds the activation engine (`ActivationScheduler`, `ActionResolver`, `ActivationAI`), campaign rules (`Campaign`, `MissionBuilder`) and persistence (`CombatSave`, `ResumeStore`). `view/` is Control-node screens that only read events and state. `story/` + `data/` hold the lint and the JSON for cast, route, items, scenes, maps and tiers. See `TECHNICAL_ARCHITECTURE.md`.

## State at the start of this pass (measured)
| Check | Result |
|---|---|
| `godot --headless --path . -s tests/run_tests.gd` | 560 tests, 2,918 checks, 0 failed (about 100 s) |
| `tools/e2e_app.gd` (drives the real campaign and battle scenes) | 16 checks, 0 failed |
| `tools/soak_campaign.gd -- --scripted` | both campaigns reach an ending (`long_watch`, `roll_read`) |
| `tools/soak_campaign.gd` (AI fights every mission, 12 runs) | all 12 reach the finale and lose it; no engine problems |
| Mission soak, 30 battles each, stand-in AI squad on a fresh roster | Acts 1-2 won 29-30 of 30; Long Corridor 19 of 30; **Vesper Threshold (finale) 1 of 30** |
| Android | APKs for the level test and an Act-1-only campaign existed; no full-campaign package |

## Working
Campaign loop (map, prep, fight, result, salvage, level-up, roll call, debrief, Orrick, endings), activation combat (initiative, AP, cover and dug-in cover, overwatch, six weapon classes), enemy AI with legality checks, levelling, equipment and stash, versioned saves with rejection of bad files, battle autosave and resume, sound and ambience, mute, story lint inside the test suite.

## Partial or missing at the start
- The shipping Android preset was **Act 1 only** (later acts stopped at an end page).
- Acts 2 and 3 maps are still the old 12x10 layouts (roadmap A6); doors, sight modifiers, patrols and hostages (roadmap A1-A4) are not in the engine, although Act 1 map designs mention some of them.
- No tutorial; only a persistent rules line.
- Difficulty: the finale was effectively unwinnable for the stand-in squad.
- No stances, aimed shots, ammo or reloading, wounds or bleeding, thrown items (roadmap B3, B4, B8-B10).
- No volume sliders (only mute); no pinch zoom or pan.
- No human playtest of Acts 2-3 and no on-device performance data.

## Defects found in this pass
1. The campaign menu's buttons did not wrap; a long "Resume battle: ..." label widened the whole page past the 540 px screen so text and buttons were cut off on the right. Fixed (`campaign_view._fill`).
2. Developer flags (`--demo=...`) write to the real `user://campaign.json`; running them on a machine with a real save overwrites it. Not changed (they are developer tools), documented in `REMAINING_ISSUES.md`.

## Packaging
Android APK builds with the installed JDK 17, SDK build-tools 35.0.1 and 4.6.3 templates (31.7 MB). Windows exe builds (105 MB, embeds the pack). No Android device or emulator is attached to this machine, so no APK has been installed or run here.
