# Takeover guide: continuing The Long Retreat / JA2-style combat

For a new engineer or agent picking this project up cold. Read this first, then `docs/JA2_COMBAT_PLAN.md` (what to build) and the top of `docs/handover.md` (state). Everything here was true on 2026-10-16 at commit `802e175`.

## 1. What this is
A portrait, phone-first Godot 4.6 (GDScript) squad tactics game, private, for the owner and their father. Combat is an AP / initiative "activation" engine with cover, overwatch, six weapon classes, a seeded AI, permadeath and the **Hollowing** (a dead merc becomes a weaker drone). It currently has a 12-mission narrative campaign; the agreed direction is a JA2-like game (stances, aimed shots, ammo, wounds, grid inventory) on a small pursuit sector map, with all narrative removed except the Hollowing.

## 2. Where everything is
| Thing | Location |
|---|---|
| Repo | `C:\Users\kyler\Desktop\RetreatGame-Initiative` (origin `github.com/kavemankai/RetreatGame-Initiative`); **nothing pushed**, all work is local |
| Branch | `agent/complete-game` (from `feature/initiative-combat`, base `d43334d`). Do not touch `feature/initiative-combat`, do not force-push |
| Game project | `retreat-sim/` (Godot project root) |
| Older copy | `Desktop\RetreatGame` (untouched, ignore) |
| JA2 source (reference only) | `github.com/kavemankai/jaggedalliance2`, SFI non-commercial licence; **never copy its code or data** |
| JA2 art/sound data | `github.com/1dot13/gamedir`, sparse-checked-out at `C:\Users\kyler\JA2Assets\gamedir` (BigItems, BattleSNDS, faces, tilesets 50/51, Interface) and `C:\Users\kyler\JA2Assets\anims\RGM` (soldier layers: standing, walk, run, shot, fall, die2). More anim layers can be fetched from `raw.githubusercontent.com/1dot13/gamedir/master/Data/Anims/LOBOT/RGM/<name>.sti` |
| Generated JA2 placeholder art | `retreat-sim/assets/ja2/` (git-ignored; rebuild with `python tools/ja2_skin.py all`) |
| Builds | `dist/windows/TheLongRetreat.exe`, `dist/android/TheLongRetreat-1.0.0.apk`, `dist/android/RetreatSim-ja2test.apk` (git-ignored; rebuild with the commands below) |
| Docs | `docs/` (audit, design, architecture, licence, decisions, test results, remaining issues, plan, this file); older design notes in the repo root (`STORY_BIBLE.md`, `MECHANICS_SPEC.md`, `TACTICS_KIT.md`, `ENGINE_ROADMAP.md`) |

## 3. Owner decisions that are settled
- AP scale: change as needed (plan uses 25). Wounds: yes. **Hollowing stays.**
- Small free sector grid; fixed checkpoints reached in order, route free; the squad is pursued. Start small.
- Still a retreat; **drop all other narrative** (scenes, Writ, Orrick, roll calls, choices, endings, Procession, Remembrance).
- Carry weight: no.
- JA2 assets are **placeholders and tests**, private use only (see `docs/LICENSE_AUDIT.md`). Do not commit them or ship them beyond the owner and their father.
- The menu defaults to Story difficulty (squad +1 hp, enemy -15 accuracy); Standard is the designed fight.

## 4. Toolchain (this Windows machine)
- Godot dev binary: `godot` on PATH (4.6.2 mono). Exports use Godot **4.6.3** at `C:\Users\kyler\Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe` with its installed templates. JDK 17 and the Android SDK (build-tools 35.0.1) are configured. No Android device or emulator is attached.
- Shell: Git Bash and PowerShell. In PowerShell `R` is an alias (Invoke-History), `>` writes UTF-16 (never use it for binary), `Remove-Item` on some paths is blocked, and `Start-Sleep` followed by checks is blocked: run long jobs in the background and wait for the notification.
- Python 3.11 with Pillow for the art tools.

## 5. Commands (run from `retreat-sim/`)
```
godot --headless --path . --import                          # after adding or changing assets
godot --headless --path . -s tests/run_tests.gd             # full suite, ~100 s; must end "0 failed"
godot --headless --path . -s tools/e2e_app.gd               # real-scene driver, 16 checks
godot --headless --path . -s tools/lint_story.gd
godot --headless --path . -s tools/soak_combat.gd -- --battles=100 [--mission=ID] [--difficulty=story]
godot --headless --path . -s tools/soak_activation_campaign.gd -- --runs=8 --difficulty=story
powershell -File tools/export_android.ps1 -Ja2Test          # build/RetreatSim-ja2test.apk (Act 1, JA2 art, own package)
powershell -File tools/export_android.ps1 -Full             # build/TheLongRetreat-1.0.0.apk
powershell -File tools/export_windows.ps1                   # ../dist/windows/TheLongRetreat.exe
python tools/ja2_skin.py all                                # rebuild assets/ja2 from C:\Users\kyler\JA2Assets
godot --path . res://view/initiative.tscn -- --campaign=karsa_breakout --shot=shots/x.png   # screenshot a battle
```
The test suite lists suites explicitly in `tests/run_tests.gd`; a new `tests/test_x.gd` must be added there. A test that records no checks fails.

## 6. Gotchas that have already cost time
1. **Saves get overwritten.** `--demo=`, `--shot`, `--campaign=... ` flags and `tools/e2e_app.gd` write the real `user://campaign.json` and `combat_resume.json` (`%APPDATA%\Godot\app_userdata\Retreat Sim`). Back them up first and restore after, then compare hashes. The owner's original saves are backed up in this session's scratchpad (`...\scratchpad\save_backup`); take a fresh copy before you start.
2. `class_name Skin` collides with a Godot built-in; the art layer is `ArtSkin` (`view/art_skin.gd`). Check new class names against Godot's.
3. The suite sets `ArtSkin.forced = 0` so tests always use the original art. New art-dependent tests must not assume JA2 is active.
4. Long button labels widened the campaign menu off-screen; buttons now autowrap. Check new UI at 540x960, 360x800 and 960x540.
5. Showing both the coach tip and the rules line pushed End Activation off a 540x960 screen. Vertical space in the battle panel is tight (`PORTRAIT_PANEL_RESERVE`).
6. JA2 STI files are palette-indexed with placeholder colours (hair cyan, skin magenta, vest blue, trousers green, shadow yellow); `tools/ja2_skin.py` recolours them by hue. Soldier frames are 8 directions per animation (N, NE, E, SE, S, SW, W, NW). Layers: shadow, legs, torso, head, hands; weapons are separate layers not yet drawn.
7. Item art lookup: `ArtSkin.icon_path(item_id)`; add new items to `ITEM_ART` in `tools/ja2_skin.py`.
8. Packaged builds embed `assets/ja2/` if it exists on the build machine. Delete it before any build meant for people other than the owner and their father.
9. Stand-in AI squads never change gear or level up, so soak win rates are floors, not predictions for a person.

## 7. Architecture map (where to change what)
- Sim rules (pure, deterministic, integers): `sim/` (`sim_unit.gd`, `sim_const.gd`, `sim_resolver.gd`, `sim_ai.gd`, `sim_grid.gd`, `sim_los.gd`, `sim_vision.gd`).
- Activation engine: `game/combat_state.gd`, `activation_scheduler.gd`, `action_resolver.gd` (all actions go through `submit`/`problem`), `activation_ai.gd`, `shot_resolver.gd`, `combat_invariants.gd`, `combat_save.gd`, `resume_store.gd`, `data/combat/ap_costs.json`.
- Campaign: `game/campaign.gd` (roster, gear, levelling, difficulty, saves), `mission_builder.gd`, `map_data.gd`; data in `data/story/*.json` and `data/maps/*.json`.
- Views: `view/initiative_view.gd` (battle screen), `board_view.gd` (iso renderer), `view/screens/*`, `view/ui/*`, `view/campaign_view.gd` (menu and campaign pages), `view/art_skin.gd` (art/sound toggle).
- Rule of the codebase: views read events and state, never decide rules; the sim never imports views.

## 8. Takeover plan
Work through `docs/JA2_COMBAT_PLAN.md` in order. For each phase the cycle is: read the touched code, write tests first, implement, run the suite and a soak, screenshot the UI, rebuild the JA2 test APK, commit, update `docs/handover.md`, then stop for the owner's phone feedback before the next phase.

### First day
1. Read `docs/handover.md` (top section), `docs/JA2_COMBAT_PLAN.md`, `docs/REMAINING_ISSUES.md`.
2. `git checkout agent/complete-game`; confirm `git status` is clean; back up saves.
3. `godot --headless --path retreat-sim --import`, then run the suite; expect **576 tests, 0 failed**. Run `e2e_app.gd` (expect 16/16) and a 100-battle soak (expect 0 illegal, 0 frozen).
4. Start **phase 0**: move AP costs out of `SimConst` and `SimUnit.step_cost/shot_ticks` into `data/combat/ap_costs.json`, set 25 AP (step 4, diagonal 6, shot 8, overwatch 8, stance 2-3, reload 5, aim click 2, bandage 6), bump `CombatSave` and `Campaign` save versions with a clear refusal message, fix every test that hard-codes the old numbers, re-run soaks to check fights are still about 4 rounds.

### Phase order and exit criteria (summary; details in the plan)
| Phase | Exit criterion |
|---|---|
| 0 AP rescale | Suite green, soak clean, similar fight length, old saves refused with a reason |
| 1 Stances | Tests for costs, hit modifiers, cover promotion, sight; AI uses stances; JA2 crouch/prone frames on screen |
| 2 Aimed shots | Preview equals the real roll; AP charged; AI chooses aiming when it pays |
| 3 Grid inventory | Tap-to-place UI works at 540x960; fit/stack rules tested; saves round trip |
| 4 Ammo | No empty-gun fire; reload and salvage tested; AI reloads; soak shows no stalls |
| 5 Wounds | Bleed, bandage, dying, rescue, **death still creates a hollow**; healing over time |
| 6 Sector map | 6x5 grid, 3 checkpoints in order then extraction, pursuit, generated battle maps always valid; narrative systems and their tests removed; whole-run soak |
| 7 Balance and release | Soaks on both difficulties, docs updated, final APKs |

### Definition of done for any phase
Suite 0 failed; soak 0 illegal / 0 frozen; screenshots read at the three screen sizes; JA2 test APK rebuilt and verified (`aapt2 dump badging`, `apksigner verify`); commit; `docs/handover.md` and `docs/TEST_RESULTS.md` updated with real numbers; anything not run said plainly.

## 9. Working rules (from the owner's brief)
Build, run, test, fix; never claim an untested feature is done; record assumptions in `docs/DECISION_LOG.md`; keep `docs/IMPLEMENTATION_LOG.md` current; commit milestones to `agent/complete-game`; do not delete the original repos, force-push, spend money, or expose secrets; no monetisation, timers or accounts. Do not add attribution lines to commit messages.

## 10. Open items to raise with the owner
- Phone feedback on the JA2 test APK (soldier sprites, wall height, icons, portraits, voices) is still outstanding.
- Weapons are not drawn in the soldiers' hands yet (separate JA2 weapon layers).
- Licence of the 1dot13 assets is unconfirmed; keep builds private.
- Acts 2-3 maps are irrelevant once phase 6 replaces the campaign, so they are not being redesigned.
