# Takeover prompt: paste this into a new session

You are taking over **The Long Retreat**, a mobile-first, portrait, Godot 4.6.x isometric squad-tactics game (Jagged Alliance style: 3 to 4 mercs, permadeath, deterministic integer sim, no runtime AI generation, a "Hollowing" mechanic). Work only in the fork below; the original folder `C:\Users\kyler\Desktop\RetreatGame` is frozen.

## Where things are
- **Project (main work):** `C:\Users\kyler\Desktop\RetreatGame-Initiative\retreat-sim` (git repo at `RetreatGame-Initiative`, branch `feature/initiative-combat`, rollback tag `legacy-live-ap-baseline`).
- **Godot console exe:** `C:\Users\kyler\Downloads\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe`
- **Tests:** `godot --headless --path . -s tests/run_tests.gd` (run `--import` first after adding any `class_name`). Baseline: **392 tests, 1910 checks, 0 failed.** A few "String formatting error" lines are harmless old noise.
- **Android build:** `powershell -File tools/export_android.ps1 [-LevelTest] [-Install]` -> `build/RetreatSim-leveltest.apk` (29.2 MiB; files over 30 MiB cannot be delivered to the phone). Android SDK is configured in Godot editor settings (cmdline-tools 23.0.0, build-tools 35.0.1, platform android-35, JDK 17).
- **Read these first (in `docs/` and the project root):** `combat/initiative-combat-plan.md` (the redesign plan, the goal), `combat/migration-checklist.md` (source audit), `combat/initiative-combat-spec.md` (built vs plan, decisions D1 to D8), `testing/combat-regression.md`, `handover.md`, then `TACTICS_KIT.md`, `MECHANICS_SPEC.md`, `ENGINE_ROADMAP.md`.

## What exists
- `sim/`: deterministic integer core (SimGrid with edge cover, SimLos, SimVision fog, SimPathing, SimResolver, SimDice, SimAI utility planner, SimGoal). `sim/sim_const.gd` holds every tuning number.
- Two rulesets: legacy simultaneous 20-tick planned mode (`sim/sim_turn.gd`, `game/sim_match.gd`, `view/play_view.gd`) and the **AP/initiative ruleset** `game/initiative_match.gd` + `view/initiative_view.gd` (live AP, 14 AP per unit, step 2, diagonal 3, shot 4, interrupts by initiative, overwatch, a reaction gate, route preview with exposure). The user chose AP/initiative as the direction. `Session.ruleset` picks which one runs (default "initiative").
- Data-driven maps (`data/maps/*.json`, incl. the open 20x16 `proving_ground`), tiers, items, AI profiles; the **Sandbox** (`game/sandbox.gd`, `view/sandbox_view.gd`: edit 4 mercs' stats and gear, place enemies by tapping the map, choose ruleset); the Act 1 level test menu; campaign layer (`game/campaign.gd`, `mission_builder.gd`).
- Art/audio pipelines exist; **art, story and lore are out of scope** until combat gates pass (see the plan's scope lock).

## Current state
Phase 0 (audit and baseline) is done and committed. No gameplay code changed since the fork. Key findings: the sim has no real-time dependency; all state changes already go through `InitiativeMatch` commands; shot and morale logic is **duplicated** between `SimTurn` and `InitiativeMatch` (consolidate into one resolver in Phase 1); there are no mid-combat saves; there is no activation queue, initiative strip, reload, stance or aimed fire.

## Decisions the user still has to make (ask first, do not assume)
- **D1** interleaved per-unit activations (the plan, my recommendation) vs the current whole-squad-then-enemy turns; keep both behind a flag until playtested.
- **D4** drop the automatic JA2-style interrupts (the plan has none) or keep them behind a flag (my suggestion: flag, default off). The user liked "AP"; they have not specifically ruled on interrupts.
- **D3** overwatch armed for 4 AP, not refunded (the plan, recommended) vs the current "all AP".
- **D2** AP numbers: plan says 12 AP, step 1, diagonal 2; current is 14/2/3/4. Recommendation: move to a config table (`data/combat/ap_costs.json`) at the current values, retune later, one variable per build. User feedback so far: 20 AP felt like too much (now 14).

## Next step
After the user answers the decisions, start **Phase 1**: a pure, headless `CombatState` + `ActivationScheduler` + `ActionResolver` in `game/` (typed action requests/results, AP ledger, invariants helper, seeded initiative with tie-break, one activation per unit per round), reusing `SimResolver`, `SimVision`, `SimPathing`, `SimDice`; port `InitiativeMatch._fire/_morale` into the shared resolver; keep the legacy modes behind `Session.ruleset`. Exit gate: scripted 4v4 fights complete with no double activation, negative AP or lockups. Then Phase 2 (touch UI + initiative strip), 3 (AI one legal action at a time), 4 (reactions), 5 (1,000-seed soak, reliability), 6 (integration). Test-first, small commits per phase, update `docs/handover.md` at the end of each phase.

## Standing user rules and preferences
- **Build an APK only when asked**; send files with SendUserFile. Keep the level-test APK under 30 MiB.
- No attribution lines in commits or PR text. Commit messages: `<type>: <description>`.
- Higgsfield credit budget is nearly spent (about 36 of the approved 45 credits left in the earlier project); do not spend credits without asking. Never use Higgsfield music/SFX models; synthesise audio in code (`art/make_sounds.py`). Art is for the later phase.
- The user cannot see inline widgets; give art or screenshots as image files.
- Use Alt-neutral pronouns (they/them) unless stated.
- Prefer the TDD workflow in the user's global rules: write tests, mutation-check rule changes, run the full suite before reporting.

## Gotchas
- GDScript: warnings are errors on Variant inference; `trait`, `theme` and `match` are reserved or clash (we use `gear_trait`, `level_theme`); `OS.get_cmdline_user_args()` for script args.
- Bash heredocs with quotes break in the tool: write files with the Write tool or a Python patch script.
- Scripted screenshots: `godot --path . --resolution 540x960 res://view/initiative.tscn -- --sandbox=1 "--do=sel 1;move 5,7;end" --shot=out.png` (commands: `sel ID`, `preview X,Y`, `move X,Y`, `shoot ID`, `watch`, `end`).
- Keep the sim integer-only and deterministic; views must never mutate state; no hidden-information leaks (AI and previews use fog views).
- Robocopy exit code 1 means "files copied", not an error.
