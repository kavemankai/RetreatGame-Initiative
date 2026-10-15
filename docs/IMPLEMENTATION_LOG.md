# Implementation log

Newest first. Each entry is something that exists in git on `agent/complete-game`.

## 2026-10-16
- `export_presets.cfg`: **Android Full Campaign** (`campaign_only`, all 12 missions, version 1.0.0 / code 2, package `com.kyler.retreatsim.campaign` so it upgrades the Act-1 build) and **Windows Desktop** presets. `tools/export_android.ps1 -Full`, `tools/export_windows.ps1`. `dist/` is git-ignored.
- `view/ui/coach_model.gd` + `tests/test_coach.gd` (7 tests, written first): the first-mission coach. Wired into `view/initiative_view.gd` (`_coach`, `_coach_facts`, `_refresh_coach`); runs only in the first mission of a fresh campaign, never on a resumed battle, level test or sandbox.
- `game/campaign.gd` + `tests/test_difficulty.gd` (9 tests, written first): `DIFFICULTIES`, `difficulty`, `set_difficulty`, `next_difficulty`, applied in `_unit` (squad +hp, enemy `hit_bonus`), saved as `difficulty` (optional on load, validated in `save_problem`). Menu: "New campaign (X difficulty)" and "Change difficulty for a new campaign" in `view/campaign_view.gd`; default Story (D-5).
- `view/campaign_view.gd`: menu buttons wrap long labels (found from a screenshot).
- `game/combat_soak.gd`, `tools/soak_combat.gd`: `--difficulty=`. New `tools/soak_activation_campaign.gd`: whole campaigns on the activation engine.
- `docs/`: PROJECT_AUDIT, FEATURE_COMPARISON, GAME_DESIGN, TECHNICAL_ARCHITECTURE, LICENSE_AUDIT, DECISION_LOG, IMPLEMENTATION_LOG, TEST_RESULTS, REMAINING_ISSUES, PLAYING; root README.md and CHANGELOG.md.

Earlier history (combat engine, UI kit, equipment, levelling, overworld, prep and result screens, sound, cover) is in `docs/handover.md` and `git log`.
