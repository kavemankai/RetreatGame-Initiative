# Plan: equipment, levelling, overworld map and pre/post-combat UI

## Context
Combat is now solid (activation engine, AI soak, resume). The campaign shell around it is still plain text-and-buttons (`view/campaign_view.gd`, one reused `_show` page), real campaign missions still launch in the old planned mode, and there is no XP, no level-up, no stats screen and no map. Equipment rules exist and work (14 items, 3 slots, `Campaign.equip/unequip/stash_for`) but the screens are bare text and nothing shows gear-folded stats. This plan adds the screens and the data behind them without changing the combat rules.

Owner decisions: earn XP then pick 1 of 3 stat steps; items stay find-only (no currency); fixed 12-stop route drawn in code (no new art); wire campaign missions to the activation engine first.

Findings that shape the plan: no item icons, portraits or UI art exist (sprites are 64x64 full-body); every screen is built from `_show(title, bbcode, buttons, status, columns, footer)`; `campaign.pending` is a saved queue of debrief steps (a new step type plugs in there); `MissionBuilder.outcome` returns only success, dead slots, Writ dead, wipe and loss, with no survivors or per-merc counters; stress is never set; the route is a single chain in `route.json` with no map coordinates; docs `MECHANICS_SPEC.md` still describe tick-era growth and stress.

## Order of work (each phase: tests first, mutation check, small commit, handover note)
A -> B -> C, D, E (any order) -> F.

### A. Campaign missions on the activation engine (prerequisite)
- `campaign_view._deploy` launches `INITIATIVE_SCENE`; planned mode stays behind `Session.ruleset == "planned"` as the rollback.
- `InitiativeView` end-of-fight builds a campaign outcome from `ActivationMatch` and sets `Session.pending_outcome` (same dict `MissionBuilder.outcome` returns, so `_apply_outcome` and `Campaign.complete_mission` are untouched), then returns to `campaign.tscn`.
- Extend the outcome with `survivors`, per-slot `{shots, hits, kills, hits_taken, steps}` and `rounds`. Add `hits_landed` and `kills` counters in `game/shot_resolver.gd` (bump on the shooter).
- Extend `ResumeStore` with kind `campaign` (rebuild from `user://campaign.json` plus mission id) so a mid-mission app kill resumes.
- Tests: outcome parity with `MissionBuilder.outcome`; a whole mission played by AI then applied to a campaign; update `tools/soak_campaign.gd` to use the engine.

### B. Shared UI kit (`view/ui/`, no new art)
Small code-built Controls on a `UiTheme` helper using the ART_DIRECTION palette (floor #1f2227/#2b2e35, amber #d99a3d, teal #3fa7a0, fog #0e0f12), 540x960 portrait reference, 14 margin, tap targets at least 56 px:
`MercCard` (callsign, status chip, stat pips, gear glyphs, optional XP bar), `ItemCard` (icon slot with slot-glyph fallback, name, tier pips, effect lines, optional delta chips), `StatRow` (label, value, +/- delta), `ResourceBar` (Procession, Reserves, Remembrance, Writ stage), `ScrollList`.
Screens become classes in `view/screens/` emitting `done`/`back`; `campaign_view` stays the hub and keeps `_show` for narrative pages. Views hold no rules; they call `Campaign`.
Tests: headless instantiate each widget and screen with a fake campaign; assert no errors and every button is at least 48 px.

### C. Equipment
Existing list (14): armour compact_vest, mourning_cloak, plate_carrier, ablative_coat, gavel_plate; weapon carbine, scatter_gun, marksman_rifle, heavy_rifle, seal_rifle; mod scope, sprint_boots, stanchion, reflex_rig. Traits: scope, sprinter, bracing, opener.

Proposed additions (a draft for your review; stats use only existing fields, tuned later with the soak):
| Slot | Item | Tier | Idea |
|---|---|---|---|
| armour | padded_jacket | 1 | morale +1, hp +0 (cheap morale option) |
| armour | stalker_wrap | 2 | speed +1, hp -1 (glass runner) |
| armour | bulwark_plate | 3 | hp +2, speed -1, morale +1 (sits between ablative and gavel) |
| weapon | service_pistol | 1 | range -2, shot cost -1 (3 AP), accuracy 0 |
| weapon | repeater | 2 | shot cost -1, accuracy -10 |
| weapon | long_rifle | 3 | range +3, shot cost +1, accuracy +5 |
| weapon | breacher | 2 | damage +1, range -2, accuracy 0 (close specialist, pairs with CQB 6+) |
| mod | field_glasses | 1 | trait scope-lite: +1 sight |
| mod | steady_grip | 2 | accuracy +5 |
| mod | spare_battery | 3 | trait: +1 AP per activation (needs a small engine hook in `ActivationScheduler`/`CombatConfig.pool_for`; flagged optional) |
Rules to keep: no currency, items arrive as mission rewards by tier (lint already rejects early rewards), dead merc's gear returns to the stash, hollows take no gear. New items need `story_lint.gd` ITEM_STATS entries and reward placement in `route.json`.

Screens (reach: squad pre-mission, overworld between missions, result salvage "Equip now"; not mid-mission):
1. Loadout hub: a `MercCard` per named merc, tap to open.
2. Merc gear: sprite, six stats showing gear-folded totals (new `Campaign.effective_stats(slot)`, built via `squad_units` so it matches combat), three slot buttons showing `ItemCard`s.
3. Item picker: stash grouped with xN counts, each with before/after delta chips (+1 hp, -1 speed in green/red), tier pips, note line; Equip, Take off.
4. Stash view: every item and who wears it.
Reuse: `Campaign.gear_of`, `stash_for`, `equip`, `unequip`, `item_summary` (and delete the sandbox duplicate at `sandbox_view.gd:273`), `apply_item`.
Icon convention: `res://assets/items/<id>.png`, falling back to a code-drawn slot glyph, so art can drop in later.
Tests: `effective_stats` equals the fielded unit; grouped counts; delta math; equip and take-off through the screen; new-item lint.

### D. Levelling up
Model (all numbers in new `data/story/progression.json`, lint-checked, tunable): per mission a surviving merc earns XP for hits landed (cap 6), kills (3 each), surviving hits taken (cap 2), objective success (+2) and deploying (+2). Level thresholds 6, 14, 24, 36 (max level 5). Each level offers 3 distinct stat steps of +1, weighted by what the merc did (hits to aim, steps to speed, hits survived to morale, close kills to cqb), seeded by campaign seed, slot and level so reloading cannot reroll. Caps: hp 6, speed/aim/cqb/morale 10, sight 9. Hollows never level; death still freezes stats at 60% of the levelled values.
Check against combat effect: aim (7 hit points each, range per 3, cheaper shot at 8) and morale (on-hit check) matter most; speed is initiative only; cqb only bites at 6+ within 2 tiles; sight sets vision and reaction range. The offer text states the real effect ("Aim 6 to 7: +7% to hit"), and weights favour stats that matter.
State: roster slot gains `xp`, `level`, `kills`, `missions`; `SAVE_VERSION` 3 with tolerant load (`d.get` defaults; v1 and v2 still load). New `Campaign.apply_xp(slot, counters)`, `offer_levelup(slot)`, `choose_levelup(slot, stat)`; a `{"t": "levelup", "slot": n}` step in `campaign.pending` (persisted, so quitting mid-choice is safe).
Screens: post-mission Level-up step (MercCard with XP bar before to after, three choice cards showing current to new and the plain effect, confirm), and a Roster screen (every merc: level, XP bar, six stats with gear totals, status, kills and missions, gear glyphs; hollow and vacant shown plainly).
Docs: fix `MECHANICS_SPEC.md` tick-era growth and stress lines (stress has no source; decide to drop or give it one).
Tests: XP table, seeded offers repeat, caps, hollows excluded, save v2 to v3 migration, offer text matches the stat effect.

### E. Overworld map
Data: new `data/story/map.json` with a normalised (0..1) node position per mission id, act bands, route control points and contingency-card anchors; lint that every mission has a node. Pure `Campaign.route_state()` returns done, current, upcoming and card states (tested).
Screen (`OverworldScreen`, `_draw`-based, vertical drag-scroll): Karsa Station at the bottom up to Vesper Reach; walked route in solid amber, route ahead dashed, fog darkening everything beyond the next stop (matches the cold wreck-field mood and the no-spoiler rule), done nodes ticked, current node pulsing, offered contingency cards as small diamonds, a convoy marker for the Procession, a header `ResourceBar`. Tap a node for a bottom sheet: place, act, summary, objective, squad size, theme chip, and Brief or Deploy for the current node only. Bottom nav: Roster, Loadout, Stash, Menu, Sound.
Flow: after the debrief the convoy moves to the next node, then the player taps in to pre-combat. Replaces `_briefing` as the hub.
Tests: map lint, `route_state` through a full campaign, node hit-testing, headless draw smoke.

### F. Pre-combat and post-combat
Pre-combat "Mission prep" (one screen, three steps): (1) Briefing card: place, objective, stakes shown plainly (win and loss resource deltas from `on_success` and `on_failure`), reward preview, known enemy tiers, Orrick flag; (2) Squad pick with `MercCards` (stats, status, gear glyphs, toggle, need N of `squad_size`); (3) per-merc Loadout shortcut. A readiness line warns ("Quill has no weapon", "no mod") and Deploy stays disabled until the count is right.
Post-combat is an ordered chain through `campaign.pending`: result banner and objective line with resource deltas animating before to after; squad report (each deployed merc: unhurt, hit n times, or fell and becomes a hollow; shots, hits, kills, XP bar); salvage `ItemCards` with Equip now or To stash (Writ drops flagged); level-ups (D); the existing roll call, debrief and Orrick scenes; then the overworld arrival.
Tests: stakes text matches the mission data, readiness warnings, the pending chain order, outcome applies exactly once (`can_complete` guard stays).

## Verification
- Every phase: write tests first, run `godot --headless --path . -s tests/run_tests.gd` (currently 452 tests), mutation-check the new rules, run the soak (`tools/soak_combat.gd`, one mission each) after Phase A.
- Screenshot every new screen with scripted `--demo=` captures at 540x960, 360x800 and landscape, and read them.
- End-to-end in the real engine: new campaign, brief, pick squad, equip, deploy, finish, see report, level up, arrive on the map; then save, quit mid-battle, resume.
- Build the APK only when you ask.

## Gear appearance and weapon types: tools and assets found (researched 2026-10-15)
Goal: weapon type (pistol, carbine, rifle, shotgun, sniper) and armour class visible without regenerating 575 sprite frames. The existing sprites are baked whole-body frames (25 per character), so layers, tints or a new pipeline are needed. Everything below was read from the vendor or listing pages; items marked verify were not confirmed.

**Free now (no credits, no art spend):**
- Weapon glyphs: CC0 "Guns" pack by SnoopethDuckDuck (111 weapons, 32x32, DawnBringer palette) and CC0 "2D Gun Pack" on OpenGameArt (pistols, rifles, grenades). Use as references or recolour for the item cards; none confirmed to include a sniper (verify). Keep the code-drawn `SlotGlyph` as the fallback. Avoid RandGameDev "Pixel Guns" (restricted licence) and CC-BY packs unless a credit line is acceptable.
- Muzzle flashes: Reactorcore "Gun Muzzle Flash Effects" (232 pixel sprites). Listed CC0 on OpenGameArt but CC-BY 4.0 on RenderHub: check the creator's page before use. Also CC0: CodeManu "Free VFX asset pack" (22 effects) and ansimuz "Warped Shooting Fx" (beams, suits energy weapons). No free tracer pack found: tracers stay code-drawn per weapon class in `BoardView`.
- Gun sounds: keep synthesising in code (`art/make_sounds.py`, your standing rule). sfxr-family tools (jsfxr, Bfxr, the gdfxr Godot port) are useful for auditioning; gdfxr stores parameters only and does not synthesise at runtime. Starting recipe per class (my knowledge, unverified): noise burst, near-zero attack, fast decay, falling pitch, low-pass sweep; shotgun longer and heavier, sniper a sharp crack plus low thump, pistol short.
- Armour looks by colour: Godot palette-swap shaders (Godot Shaders "Palette Swap" and "Advanced Palette"; a ten-line key-colour shader with a tolerance works; MIT editor add-ons exist). Needs nearest filtering. Changes colour, not silhouette.
- Equip logic and paper-doll UI references (not needed for our data model): Equipment Lite (MIT), Layered Sprite (MIT).

**Layered 2D sprites:** the standard method stacks one sprite per slot over a base body, which requires every layer to share one canvas size and pivot per frame. The LPC generator is the best-known source but is CC BY-SA / GPL (share-alike and credit duties) and is top-down, not isometric: poor fit. Our baked sprites cannot be split into layers.

**Modular 3D rendered to pixel sprites (the scalable route, a style change):**
- Base art: Quaternius Ultimate Modular Characters (CC0, 11 characters each in 4 swappable models, 24 animations; no separate equipment pieces listed) and Sci-Fi Essentials Kit (CC0, textured guns and robots).
- Animations: Mixamo (free with an Adobe ID; raw files may not be redistributed; read Adobe's current terms).
- Rendering: free Blender add-on Omnidirectional Isometric Render (sprite sheet export, transparent background; direction count and output licence not stated: verify). Paid alternatives: Render 8 Directions (pay what you want), Pre Render Creator ($17.99), Get Sheet Done ($17.95), Blaterna Studio. Forum workflow: render body and each gear piece as separate layers with the same camera and frames, downscale with nearest neighbour to a shared palette, composite, mirror to halve directions.
- Fit: gives every weapon-by-armour-by-merc combination for free once built, but would replace the current AI-drawn look for all 23 sets or live beside it. A Blender connection exists in this session for scripting renders.

**AI sprite tools for variants (compare against the credit cost of Higgsfield):**
- PixelLab: 4 and 8 directions including isometric, skeleton animation, inpaint and edit, a "Transfer outfit (Pro)" tool, REST API and MCP (subscription; pricing not verified). Does not document that an edited sprite keeps frame alignment: test.
- SpriteCook: free 40 credits per 30 days, paid from $8 a month (vendor page, June 2026), commercial use stated; animates an uploaded sprite keeping its design and palette; no documented equipment-variant tool. Its plugin is installed in this session but needs your authorisation.
- Retro Diffusion (paid Aseprite extension): outputs usable commercially per the developer's informal statement, no variant tool documented.
- Test before committing: one merc, one armour class, check that the 25 frames stay aligned and on style.

**Recommended path:** (1) now, free: weapon-class glyphs, class tracers and muzzle flashes, synthesised class sounds, armour tint shader and trait badges, plus the variant lookup with fallback in code. (2) small paid trial: one merc through PixelLab or SpriteCook free credits for an armour class. (3) only if appearance becomes a pillar: the modular Blender pipeline with Quaternius CC0 bases, accepting the style change.

## Roster of eight and weapon classes (decided 2026-10-15; build before Phase C)
**Roster (keep slot numbers so sprite keys and unit ids do not change):** slot 1 Warden rifle, 9 Gran rifle, 4 Sable sniper, 8 Needle shotgun, 5 Bulwark heavy, 3 Moth carbine/SMG; joiners 12 Wren grenade launcher (joins at Orchard Ring) and 11 Ghost laser (joins at Cinder Market). Cut: 2 Quill, 6 Static, 7 Pilgrim, 10 Tinker. Missions still field 3 to 4. Remembrance thresholds are left alone (owner: do not worry about them).

**Classes:** a class is the weapon type and is fixed per merc, so the baked sprite weapon is always right. Weapon items become class-locked upgrade lines (a merc's weapon slot only takes their class); armour and mods stay shared. Each merc starts with their class's base weapon. Hollows keep a class chip but use the generic hollow sprite. Enemy tiers can later be given classes so their looks and sounds match.
| Class | Rule | Example upgrade line |
|---|---|---|
| Rifle | baseline | issue rifle, then two new rifles |
| Carbine | cheap shot (3 AP), shorter range | carbine, repeater |
| Sniper | long range, +to hit, dearer shot | marksman rifle, Seal's rifle, long rifle |
| Shotgun | short range, +1 damage | scatter gun, breacher |
| Heavy | damage, dear shot; top of the line is a **minigun** with **burst**: three low-accuracy shots at one target for one action at a higher AP cost | heavy rifle, then LMG, then minigun |
| Grenade launcher (Wren) | **area**: hits the target tile and the 8 around it, blocked by full walls, lower accuracy, more AP, can hurt allies | launcher upgrades |
| Laser (Ghost) | **beam**: ignores half cover and range falloff; full walls still block | laser upgrades |

**Engine changes (all deterministic, integer, tested, soaked):**
- `SimUnit` gains `weapon_class` and a separate `weapon_trait`. Today `apply_item` writes a single `gear_trait`, so a weapon trait and a mod trait would overwrite each other.
- Beam: `SimResolver.evaluate_shot` skips half-cover and the distance penalty when the shooter's trait is beam.
- Area: `ShotResolver` resolves a splash (target plus neighbours, allies included, full walls block), one event per victim, morale checks and kill attribution per victim.
- Burst: three rolls (distinct dice indices) per action, stops early if the target dies, one ledger row; overwatch stays a single shot.
- Previews (`shot_preview`) report burst count and splash tiles for the UI; `SimAI._best_shot` values burst (three expected shots) and area (enemy damage minus ally damage); the 1,000-battle soak must stay clean.
- Presentation per class: glyph, tracer style, muzzle flash and a synthesised sound (see the research section).

**Churn (mostly mechanical):** `cast.json` 12 to 8 entries plus `class`, relationship and route references (about 15 in `route.json`, 1 in `scenes.json`); `story_lint` and tests that assume 12 mercs or the old joiners (slots 2, 6, 7, 10 appear in some tests); `UnitSprites` keeps its keys; sandbox default squad becomes four of the eight; `items.json` weapons gain `class`, base weapons added, about 14 new weapon items in total.

**Order:** R1 data and class lock, R2 sim rules (beam, area, burst) with tests and soak, R3 presentation, then Phases C to F built once for class-locked weapons.

## Status (2026-10-15): R1 to R4 complete
Phases A to F and R1 to R3 are built, tested and committed (see `docs/handover.md` for each). Final checks: 549 tests, 0 failed; a 150-battle soak with 0 frozen, 0 invariant problems, 0 illegal actions; every new screen checked at 540x960, 360x800 and 960x540; the real scenes were driven by `tools/e2e_app.gd` (new campaign, Brief, prep, Deploy, fight scene, outcome, debrief chain, map at the next stop, save on disk), which found and fixed a count-up tween bug the headless tests missed. Differences from the plan: the overworld's bottom nav is Roster / Loadout / Stash / Menu (sound is on the main menu); the result screen counts the resource figures up rather than animating bars; `spare_battery` was cut and item icons stay code-drawn glyphs (both confirmed by the owner on 2026-10-15). Not done by instruction: no APK, no asset downloads, no SpriteCook/PixelLab trials.

## Out of scope
New art, music, story text, shops and currency, branching routes, mid-mission loadout, enemy gear, and the optional `spare_battery` trait until you approve the engine hook.

## Critical files
`view/campaign_view.gd` (hub, deploy, outcome), `view/initiative_view.gd` (outcome on finish), `game/campaign.gd` (stats, XP, route state, save v3), `game/mission_builder.gd` (outcome), `game/shot_resolver.gd` (counters), `game/resume_store.gd`, `data/story/items.json`, `route.json`, new `progression.json` and `map.json`, `story/story_lint.gd`, `view/sandbox_view.gd` (reuse stepper and summary), new `view/ui/` and `view/screens/`, `docs/MECHANICS_SPEC.md`.
