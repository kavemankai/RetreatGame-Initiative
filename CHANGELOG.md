# Changelog

## 1.0.0 (2026-10-16, branch `agent/complete-game`)
### Added
- Full-campaign builds: Android APK (all 12 missions) and a Windows single-file exe.
- Difficulty: Story (squad +1 hit point, enemy accuracy -15) and Standard, chosen on the menu, saved with the campaign; the menu defaults to Story.
- First-mission coach: one contextual tip at a time (two-tap move, shot preview and confirm, AP and End Activation, overwatch).
- `tools/soak_activation_campaign.gd`, `--difficulty` on `tools/soak_combat.gd`.
- Project documentation set under `docs/`.

### Fixed
- Long menu button labels (for example the "Resume battle" line) widened the page past a phone screen; they now wrap.

### Earlier work (0.1.0 and the initiative-combat branch)
Activation combat engine with cover, dug-in cover and overwatch; six weapon classes; roster of eight; levelling; equipment and stash; overworld map; prep, result, salvage and level-up screens; battle autosave and resume; synthesised sound; Act 1 redesigned maps. See `docs/handover.md`.
