# Decision log (assignment "complete game", 2026-10-16)

Earlier combat decisions D1-D8 are in `docs/combat/initiative-combat-spec.md`. Entries here are from this pass.

| # | Decision | Why | How to reverse |
|---|---|---|---|
| D-1 | Work in the existing `RetreatGame-Initiative` checkout (the working base named in the brief; `origin` is the supplied GitHub URL) on a new branch `agent/complete-game` cut from `feature/initiative-combat` (`d43334d`). The older `Desktop\RetreatGame` copy is untouched. | Preserve the owner's work; the brief requires a new branch | `git checkout feature/initiative-combat` |
| D-2 | Keep Godot 4.6 / GDScript, the activation engine and the current art and audio. No engine change, no JA2 code. | Decision hierarchy: identity, then working functionality; the engine already passes 560 tests | - |
| D-3 | JA2 is a design reference only; no JA2 source, data or text is copied. Dispositions are in `FEATURE_COMPARISON.md`. | The SFI source licence is non-commercial and restricts derivative works (`LICENSE_AUDIT.md`) | - |
| D-4 | Ship the whole 12-mission campaign: new presets "Android Full Campaign" (`campaign_only`, no `act1_only`) and "Windows Desktop". The old Act-1-only presets stay. | The shipping build stopped after Act 1; the brief requires a reachable ending | Use `-Campaign` for the Act-1 demo build |
| D-5 | Add a Difficulty choice (Standard, Story) and **default the menu to Story** for this build. Story = squad +1 hp, enemy accuracy -15. `Campaign.difficulty` itself defaults to `standard`, so old saves and tests are unchanged. | Measured with the stand-in AI squad on the real engine: Standard reached the ending in 0 of 8 campaigns, Story in 6 of 8; the finale was won 1 of 40 times on Standard and 32 of 40 on Story. The audience is one casual player | Set `_new_difficulty := "standard"` in `view/campaign_view.gd` |
| D-6 | Add a first-mission coach instead of a separate tutorial level. | Smallest change that fixes "no onboarding"; pure, tested rules (`CoachModel`) | Delete the `_coach` block in `initiative_view.gd` |
| D-7 | The coach replaces the rules line while it has a tip. | With both visible, the End Activation button was pushed off a 540x960 screen (seen in a screenshot) | - |
| D-8 | Buttons on the campaign menu now wrap their text. | A long "Resume battle" label widened the page past the screen | - |
| D-9 | Did not redesign the Acts 2-3 maps, nor build doors, patrols, hostages, stances, ammo or wounds. | Roadmap A6 says redesign after Act 1 is approved by a human; no human playtest of Acts 2-3 exists. The maps work (soak: 0 illegal actions, 0 frozen turns) and are listed as the first remaining work item | See `REMAINING_ISSUES.md` |
| D-10 | `docs/HANDOVER.md` is the existing `docs/handover.md` (same file on Windows); the new handover section is added at its top. | Avoid two files differing only by case | - |
| D-11 | Release status: private, for one person. Not "commercially releasable". | Sprite/tile generator terms unverified (`LICENSE_AUDIT.md`) | - |
| D-12 | The user's own `user://` saves were backed up before running the real-scene driver and the capture flags, and restored afterwards (byte-identical, checked by hash). | The developer capture flags overwrite the campaign save | - |
