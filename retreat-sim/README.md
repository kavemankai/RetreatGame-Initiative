# Retreat Sim

## Play

The main menu opens the campaign, the Act 1 level test and the **Sandbox** (set stats, gear and enemies on an open test map). Play uses the AP/initiative ruleset by default (`view/initiative.tscn`); the layout and key notes below describe the older planned mode. For the engine as a reusable kit see `../TACTICS_KIT.md`; for what is left to build see `../ENGINE_ROADMAP.md`.

    godot --path .                      # opens the playable skirmish (view/play.tscn)

**Phone/portrait:** the layout switches automatically when the window is taller than wide (the project opens at 540x960). Tap a merc, then **tap a tile or enemy once to preview** (path or exact shot result) and **tap it again to commit**. Press T on desktop to try two-tap with a mouse.

**Desktop:** click a merc, then a tile to move or an enemy to shoot (exact hit/blocked preview on hover). **O** = overwatch, then click a direction. **Enter/Space** starts the turn (**Go**), and again to **Pause**/**Resume**. The 20-tick round plays live and stops every 5 ticks (and, with Alerts on, at new contact or a hit); re-plan the rest (spent ticks stay spent; a move or shot already under way finishes; the AI replans too). **S** cycles speed; Backspace undoes; Esc/right-click deselects; **N** new match; **V** replay viewer. Dashed red = enemy orders you can currently see.

## Sim core

Deterministic, integer-only, node-free turn simulation. See ../MECHANICS_SPEC.md.

Run tests (headless):

    godot --headless --path . --import      # first time only
    godot --headless --path . -s tests/run_tests.gd   # discovers every test_* in tests/test_*.gd

Layout: `sim/` pure logic (RefCounted only) · `game/` order entry, match loop, click handling (UI-agnostic) · `view/` screens · `tests/` headless suites.
Rule: the view reads `SimResult.events`; the sim never imports view code.

## Debug replay view

    godot --path .                      # opens view/replay.tscn

Keys: Space play/pause · Left/Right step · Home/End jump · 1-7 pick scenario · F cycle fog (off / Blue / Red).
Headless capture: `godot --path . -- --scenario=4 --tick=8 --fog=0 --shot=shots/out.png   (fog: -1 off, 0 Blue, 1 Red)`

The view only reads `SimResult.events` (via `view/replay_model.gd`); it never calls into the sim to decide anything.
Add scenarios in `view/scenarios.gd`.

## Enemy AI

`SimAI.plan_for(state, team, profiles, assignments, objective)` plans a turn for one side from its fog-filtered view.
Weights live in `data/ai_profiles.json` (integers only). Scenarios 6-7 in the replay play AI vs AI.

## Android

    powershell -File tools/export_android.ps1            # builds build/RetreatSim-debug.apk
    powershell -File tools/export_android.ps1 -Install   # ...and installs + launches on a connected phone

- Preset: `export_presets.cfg` ("Android"): package `com.kyler.retreatsim`, arm64-v8a only, portrait, min Android 7.0 (API 24), OpenGL ES 3 (Compatibility renderer), no Gradle build (uses the prebuilt template).
- Needs Godot **4.6.3** (the installed export templates), JDK 17 and an Android SDK with build-tools 35.0.1 + platform android-35, configured in Godot's editor settings.
- `data/*` is explicitly included in the export (JSON is not auto-exported; without it the AI would silently fall back to built-in weights). `tests/`, `shots/`, `build/` and `*.md` are excluded.
- **Debug-signed**: fine for sideloading, not for the Play Store (that needs your own release keystore).
- Phone: Settings > About > tap Build number 7x > Developer options > USB debugging; plug in and accept the prompt. Or copy the APK to the phone and open it (allow installs from that source).

## Story and campaign

The world lives in `../STORY_BIBLE.md` and `data/story/*.json` (cast, writ, route, world, scenes).
The campaign (`game/campaign.gd`) tracks the roster, the Hollowing, the retreat economy and the endings;
`game/mission_builder.gd` turns a mission into a match; `view/campaign_view.gd` is the screen.
The game now opens on the campaign menu; "Quick skirmish" plays a standalone 3v3.

    godot --headless --path . -s tools/lint_story.gd                      # lint the story data (exit 1 on errors)
    godot --headless --path . -s tools/soak_campaign.gd -- --scripted     # play whole campaigns to their endings
    godot --headless --path . -s tools/soak_campaign.gd                   # same, with the AI fighting the missions

The test suite (`tests/run_tests.gd`) runs the story lint, so a story edit that breaks a reference fails CI.
