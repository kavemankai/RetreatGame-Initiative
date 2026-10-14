# THE LONG RETREAT — Art Direction (workshop draft v0.1)

Status: decisions from the art workshop. Everything marked **[OPEN]** is still to be decided.
See `art/mood_options.png` for the four palettes that were compared.

## Locked decisions

| Area | Decision |
|------|----------|
| Mood | **B. Muted, one accent per side.** A desaturated, hushed world; the colour that is there carries meaning. |
| Factions | **Amber = the Lantern Compact, teal = the Meridian Hegemony.** Accent colour is the primary at-a-glance read on a phone. |
| Faction look | **Subtle and human.** Both sides look like people; differences are small insignia, trim and kit, not a different species of design. Colour does the heavy lifting. |
| Board art | **Detailed 32x32 tiles and unit sprites.** More character per merc and wreck; the map must be zoomed/scrollable or the grid kept small on a phone. |
| Mercs | **Stylised mask / visor.** Faces are mostly hidden behind visors; each merc gets one expressive detail (eyes, scar, insignia). |
| Hollows | **Faceless and uniform.** A blank grey figure wearing the slot number; clearly not the person it replaced. |
| Fog of war | **Drifting mist** over unseen tiles, slow and animated, in keeping with the wreck-field graveyard. |
| UI chrome | **Worn hardware:** scuffed metal, stencilled labels, gear salvaged from the fleet. |
| Lighting | Warm light is rare and precious: lanterns, lamps and gun-flash are the only warm sources in a cool world (amber is also the Compact's colour, so light and the player's side rhyme). |
| Pipeline | **AI-generated sprites and tiles**, with a locked style guide and reference sheet to keep them consistent. |
| Animation | **Moderate now:** idle, move, shoot, hit, death (a few frames each). **Rich (8-direction walk/aim) only after the game is confirmed**, so the sprite sheets must be built to extend. |
| Merc identity | **Silhouette gear** (pack, long rifle, medic mark, breaching tool: the role shows in the outline) **plus the slot number / callsign tag**. No per-merc unique insignia art for now. |
| Type | **Stencil for the machine, handwriting for the people:** stencil caps for labels, slot numbers and hardware; a handwritten hand for what the squad says and writes (the Roll, notes). |
| Tone words | Melancholic, hushed, concrete. Never glossy, never neon. |

## Palette sketch (from panel B; refine on real assets)
- World: floor `#1f2227` / `#2b2e35`, walls `#8d8f94`, crate `#3a3c42` with `#55585f` edge, fog `#0e0f12`.
- Compact (player): amber `#d99a3d`. Hegemony: teal `#3fa7a0`. Hollow: neutral grey `#8b8f96`. Visor/shadow: `#15171b`.
- Light sources: amber with a soft, flat halo at ~25% alpha.

## Tensions to watch
- **Subtle factions + a muted world** leaves colour as the main faction cue. Keep amber/teal saturated enough to read at phone size, and give each side one extra non-colour cue (silhouette detail or insignia) for accessibility.
- **32x32 detail vs a 12x10 board on a phone (540 px wide):** at 1:1 a 12-tile row is 384 px, which fits; a 20-tile map will not. Decide map sizes before locking tile size.
- **Animated mist** has a performance and readability cost on mobile; it must never hide the edge of vision or enemy intent lines.

## [OPEN] questions for the next rounds
1. Which generation tool(s) and budget; the style-test batch.
2. Frame counts and sheet layout that can grow to 8-direction later.
3. Per-mission terrain themes (station deck, wreck-field, dock ring, garden deck, hospital hulk, foundry hold, market, gate frame, memorial drift, hull corridor, relay station, the threshold).
4. Visor and insignia system for the 12 mercs and the Writ officers.
5. Overwatch cones, shot lines, damage and death effects.
6. Typography, and the stencil/label language for the UI.
7. Portrait treatment (the visor look suggests a bust with a hidden face: how much is shown?).
8. Colour-blind safety and phone readability tests.

## Revision: light sources are modern, not medieval
The hand lantern with a chain read as medieval and was dropped. Warm light stays rare and amber, but comes from modern gear: portable LED work lamps, emergency strip lights, signal flares, caged industrial lights. "Lantern" survives only as the Compact's name and symbol (a signal beacon motif), not as a prop.
Candidates generated (art/style_test/lighting_options.png): A work lamp, B emergency strip, C signal flare, D caged hanging light. Selection pending.

## Style-test findings (art/style_test/, ~2 credits spent)
- Mood, visors, faceless hollow, teal Hegemony trim, mist and warm light all read correctly in `gpt_image_2_5`.
- Outputs are ~128 px figures, front-on; the game needs 32x32, top-down 3/4. Prompts must state the target size and viewpoint; downscaling needs a cleanup step.
- Tiles repeated instead of forming a varied set; each merc must be generated singly against a locked style reference to keep a 12-merc cast consistent.

### Decision: all four light sources are kept
A work lamp (main board light), B emergency strip (wall detail), C signal flare (temporary/objective marker), D caged hanging light (ceiling fixture). Warm amber only; no medieval lanterns.

## Style-test batch 2 findings (art/style_test/batch2_sheet.png, merc_32px_test.png; ~3.5 credits spent in total)
- Prompting "designed at 32x32, shown upscaled 8x, big square pixels, strict top-down" works: a genuine 9-tile varied floor set (plain, riveted, vent, tread, scuffed, hatch, cracked, cable channel, drain), plus walls and crates.
- Mercs generated singly (Warden, Sable, Bulwark) share one style and read as clearly different silhouettes (long coat, long rifle, huge pack), each with the amber visor slit.
- Shrunk to true 32x32 (box filter) the silhouettes, visor slits and amber accents still read; fine detail (coat texture, rifle) is lost, so gear must be bold.
- **Viewpoint issue:** walls and crates came out isometric (rotated 45 degrees), but the board is an orthogonal square grid. They will not tile against the floor. Decision needed: re-prompt as orthogonal 3/4 ("Zelda/Fire Emblem style": top face plus front face, not rotated), or move the whole board to isometric.

## Decision: the board is isometric (chosen after batch 2)
The orthogonal-3/4 option was rejected; the board, walls, crates and mercs are all drawn isometric (2:1 diamonds).
- **Sim unchanged.** Logic stays on the integer square grid. Only drawing and picking change.
- **Implemented:** `view/iso_projection.gd` (tile<->screen, picking, diamond corners, wall edge segments, back-to-front order; tests in `tests/test_iso.gd`). `view/board_view.gd` now draws diamonds, extruded wall faces (full = tall, half = low), raised unit discs with ground shadow, fog/cone/reach tints as diamond fills, and walls + units in one painter's pass. `tools/shot_board.gd` renders the board to a PNG.
- **Art spec:** floor tiles are 2:1 diamonds (64x32 on screen at 1:1; author at 32x16 or 64x32); walls/crates are extruded from the diamond footprint; sprites anchor at the tile centre/bottom.
- **Consequence for phones:** a 2:1 board is only half as tall as it is wide, so a 540 px wide portrait board is ~270 px tall. Maps beyond ~12x10 will need pan/zoom; the freed vertical space in portrait goes to the plan/timeline panel.
- **Costs accepted:** 4-direction facing now reads as diagonals on screen; merc sprites need facing variants (NE/NW/SE/SW) in the "rich" animation pass.

## Iso art pass (~16.5 credits total, budget raised to 20)
- Iso floor (9 tiles), walls (full/half, both axes, corner) and props (barrels, crate, console, crate stack) generated, cut out and wired into `BoardView`. Scripts: `art/slice_iso_floor.py`, `art/slice_iso_props.py`. Sprites live in `retreat-sim/assets/{tiles,walls,props}`.
- **Animation test (Warden):** one 2x2 turnaround (4 diagonal facings: se, sw, ne, nw) and one 3x3 action sheet (idle x2, walk x2, aim, fire, hit, fall, dead) in one generation each; the character stayed consistent. Sliced to 64x64 frames, feet on a shared baseline (`art/slice_warden.py` -> `assets/mercs/warden_*.png`). Frames are individually generated, so expect slight jitter; clean-up or per-frame alignment may be needed before shipping. Facing is not stored in the sim; the view must derive it from the last move/shot direction.
- Open: do the other 11 mercs get the same two-sheet treatment (about 0.5 credit each plus cut-outs), and how a shot/overwatch effect is drawn in iso.

## Warden sprites are in the engine
`BoardView` draws the Warden sprite for every unit (team 1 tinted teal) with slot-number tag and HP pips. Facing derives from the last move/shot (`IsoProjection.facing_name`); frames: idle = turnaround sprite per facing, walk/fire/hit use the se action frames mirrored for west facings, north facings fall back to the turnaround sprite, dead uses the dead pose. Placeholder discs remain as a fallback if sprites are missing. Not yet animated over time (poses are per event frame), and all units share the Warden art until the other mercs are generated.

## Motion and phone layout (iso)
- Units glide tile to tile (`glide_seconds`, set by the play view to 85% of the tick pace so a step finishes before the next tick) with walk frames while gliding; fire and hit frames hold 0.3 s. Far jumps (replay seeks, new mission) snap. The board only redraws every frame while something is animating.
- Phone portrait: the board is zoomed 1.7x on the squad in a 0.8 aspect box and can be dragged to pan (a press that travels under 12 px is still a tap; right-click still taps immediately). Landscape/desktop shows the whole board. A 540x960 screen now fits board, timeline, squad buttons and Go with nothing clipped (art/style_test/iso_portrait3.png).
- Still to do for phones: pinch-zoom, recentre-on-selection, and a check of colour-blind readability of amber vs teal tint.

## After the first phone test
- Only the 5-tick checkpoint pauses by default now (Alerts, which also stops on new contact and hits, is opt-in; the button reads "Calm" by default).
- Run cycle: six generated frames (`warden_run_0..5`, `art/slice_warden.py`) play at 12 fps for any unit that is moving, mirrored for west facings; north-facing runners use the turnaround sprite with a bob (no north run frames yet). Units keep running for 0.2 s after a step and glide for the whole tick, so consecutive steps read as one continuous run.

## Shot and morale visuals
Tracers stay until the next Go: hit = solid line in the shooter's team colour with a red impact dot and ring; blocked = thin dashed line stopping at the cover with an amber spark; "OW" label on overwatch shots. Morale: floating STEADY (grey) or BROKEN (red) text for 1 s, then a grey slashed pip (can't shoot) or red bar (halted) beside the slot tag for the rest of the round. Placeholder vector art; candidates for sprite/FX passes later.

## Later art passes created by the combat and equipment work
- Enemy tier looks: conscript, regular, veteran sprites or tints, a hollow tell (grey uniform, as for the player's Hollows), elite and boss silhouettes. All enemies currently share the Warden sprite tinted teal.
- Item icons for the three slots, and a slot glyph beside the merc's number tag.
- A distinct look for scope, sprinter, bracing and opener carriers (silhouette gear: scope on the rifle, braced stance).

## Sprite sets and level kits (done)
- **Sprites:** 12 mercs, three enemy tiers (conscript, regular, veteran), the Hollow, six Writ officers and Orrick: 23 sets in `retreat-sim/assets/mercs/`, each with four facings, 9 action frames and (except the Writ) a 6-frame run. Source sheets in `art/sprites/raw`, cut by `art/slice_character.py` (magenta keyed locally, colours matched across a set's sheets). `UnitSprites.key_for` maps a unit id to its set; each set carries its own palette, so teams are told apart by the id tag colour. The Writ and Orrick walk instead of running.
- **Levels:** 12 themes (see LEVELS.md).
- **Cost note:** background removal through Higgsfield costs 1 credit a sheet, far more than a generation (0.25), so since the Warden sheets everything is generated on flat magenta and keyed out locally for free. Earlier sprite credit tallies in this file undercounted that.
