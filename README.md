# The Long Retreat (RetreatGame-Initiative)

> ## TAKING OVER THIS PROJECT? START HERE
> **[`docs/TAKEOVER.md`](docs/TAKEOVER.md)** is the takeover package: where everything is, settled decisions, commands, gotchas, and the first-day checklist.
> Then read **[`docs/JA2_COMBAT_PLAN.md`](docs/JA2_COMBAT_PLAN.md)** (what to build next: stances, aimed shots, grid inventory, ammo, wounds, pursuit sector map) and the top of **[`docs/handover.md`](docs/handover.md)** (current state).
> Active branch: **`agent/complete-game`**. JA2 art and sound are local private placeholders and are not in this repo (`docs/LICENSE_AUDIT.md`).

A portrait, phone-first squad tactics game: eight mercs, a 12-mission three-act campaign, initiative and action-point combat with cover and overwatch, permadeath with the Hollowing, four endings. Godot 4.6, GDScript. Private project, built to be shared with one person.

- **Play:** `docs/PLAYING.md` (install, controls, saves)
- **Game design:** `docs/GAME_DESIGN.md`, world in `STORY_BIBLE.md`
- **Engine and build:** `docs/TECHNICAL_ARCHITECTURE.md`, `TACTICS_KIT.md`
- **State of the work:** `docs/handover.md` (top section), `docs/TEST_RESULTS.md`, `docs/REMAINING_ISSUES.md`
- **Licences:** `docs/LICENSE_AUDIT.md` (not cleared for public or commercial release)

## Quick start (developers)
```
cd retreat-sim
godot --headless --path . --import
godot --headless --path . -s tests/run_tests.gd        # whole suite, about two minutes
godot --path .                                          # run the game (project opens 540x960)
powershell -File tools/export_windows.ps1               # ../dist/windows/TheLongRetreat.exe
powershell -File tools/export_android.ps1 -Full         # build/TheLongRetreat-1.0.0.apk
```
Needs Godot 4.6.3 with its export templates; Android also needs JDK 17 and the Android SDK (see `retreat-sim/README.md`).

Branch for this release: `agent/complete-game`.
