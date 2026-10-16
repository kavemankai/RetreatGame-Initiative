# Remaining issues and limits (2026-10-16)

Ordered by what most affects the one person this build is for.

## Not verified
1. **The Android APK has not been installed or run.** No phone or emulator is attached to the build machine. The same content runs from the Windows exe (checked) and the dev project, but touch input, the pause-notification autosave path, performance and battery on a real device are untested. First thing to do: sideload `TheLongRetreat-1.0.0.apk` and play Karsa Breakout.
2. **No human has played Acts 2-3 on the activation engine.** All difficulty evidence is from a stand-in AI squad on fresh gear that never levels (see `TEST_RESULTS.md`). On Standard that squad never finishes; on Story it finishes about three runs in four. Real players equip, level and use cover, so both numbers understate a person, by an unknown amount.
3. Story versus Standard is a two-number change (+1 hp, -15 enemy accuracy). It has not been tuned further.

## Not built (decided or deferred, see `FEATURE_COMPARISON.md`)
- Acts 2 and 3 maps are 12x10 (Act 1 maps are 14-18 wide with authored features). Roadmap A6.
- Doors, sight modifiers (fog/lit lanes), patrol routes, hostages: roadmap A1-A4. Act 1 maps play without them.
- Stances, aimed shots, ammo and reload, wounds and bleeding, thrown items: roadmap B3, B4, B8-B10.
- Volume sliders (only mute), pinch zoom and drag-pan, tap-to-inspect an enemy.
- The AI does not retreat when hurt, does not remember unseen shooters and does not choose to hold fire to keep cover.

## Known rough edges
- Developer capture flags (`--demo=...`) overwrite `user://campaign.json`. Do not pass them on a machine with a save you care about.
- The Android build is debug-signed (sideload only). The Windows exe is unsigned and Windows SmartScreen may warn.
- Windows exe is 105 MB because it embeds the full engine template. The APK is 31.7 MB.
- Sprite and tile generator terms are unconfirmed, so the game is not cleared for public release (`LICENSE_AUDIT.md`).
- The legacy planned and live-AP rulesets are still in the code as a rollback (roadmap E1).
