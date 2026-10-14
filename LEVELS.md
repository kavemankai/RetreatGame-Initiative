# Levels: maps and themes (implemented)

Every mission has its own map and a visual **theme**. Data: `retreat-sim/data/maps/<mission>.json`, written by `retreat-sim/tools/make_maps.py` (compact layout specs plus an ASCII preview of each map). Loader and validator: `retreat-sim/game/map_data.gd`.

## Map format
Each map's size is in its `size` field (x west to east, y north to south). The four redesigned Act 1 maps are karsa_breakout 16x12, the_weir 18x14, pellam_dock 16x14 and orchard_ring 14x14; the sandbox proving_ground is 20x16; the eight maps for acts 2 and 3 are still 12x10. `blocked` tiles (crates, vats, hull) stop movement and sight. `v_walls` `[boundary_x, y0, y1, kind]` and `h_walls` `[boundary_y, x0, x1, kind]` put full or half walls between tiles. Four player spawns on the west, eight enemy spawns on the east, and an `objective` tile. `MapData.problem()` rejects: unknown theme, too few or duplicated spawns, a spawn or objective off the map or blocked, more than 35% blocked, or any spawn or the objective that cannot be reached from the first player spawn. Contingency cards borrow the Weir (act 1), Cinder Market (act 2) or Reliquary Lane (act 3).

## The twelve maps
| Mission | Theme | Layout idea |
|---|---|---|
| Karsa Breakout | station deck | a bulkhead wall down the middle with a fire-door gap; crate cover either side |
| The Weir | wreck field | scattered hull chunks, no clear lane |
| Pellam Dock | dock ring | two cargo-stack blocks, gantry half-walls |
| Orchard Ring | garden deck | planter lines with narrow lanes between |
| Quiet Wards | hospital hulk | two long ward walls with door gaps, beds as cover |
| Anselm | foundry hold | vats and a gantry wall, close and cluttered |
| Cinder Market | market concourse | rows of low stalls to weave through |
| Mirror Gate | gate frame | a lattice platform, struts, and a control cage |
| Reliquary Lane | memorial drift | long sightlines broken by named hulls |
| Long Corridor | hull corridor | a four-tile-wide corridor and one door |
| Tamsin's Rest | relay station | server stacks and cold corridors |
| Vesper Threshold | station threshold | rows of Keepers and the door |

## Level art (`retreat-sim/assets/themes/<theme>/`, `view/theme_art.gd`)
Each theme has nine 64x32 floor diamonds, five wall sprites (full and half, both axes, plus a corner), and four props (`crate_0..3`, used for blocked tiles). The station deck is the original set; the other eleven were generated on flat magenta (`art/slice_theme.py` keys it out locally, for free). `BoardView.level_theme` selects the art; `SimMatch.theme` carries it from the mission. A theme missing a file falls back to the deck's.

## Notes and open items
- Memorial Drift's props came out as small lanterns; the art direction says no medieval lanterns, so they may want a modern lamp redo.
- The hospital floor is bright by design (sterile light) and is the lightest set in the game.
- Maps are the same size; larger maps need pan/zoom tuning (see ART_DIRECTION.md).
- Walls are drawn without a back-face and units standing behind tall walls are hidden by them, as intended.
- The balance probe (ENEMY_TIERS.md) has been re-run on these maps: Act 1 72% wins, Act 2 55%, Act 3 25% for the crude auto-squad; Quiet Wards and Long Corridor mostly stalemate for it (the auto-AI does not breach walled maps well).

## Scale (fixed after "some look tiny")
The generator drew every wall and prop at its own pixel scale (props came out between 290 and 490 px wide), so some environment pieces looked tiny next to others and next to the mercs. `art/normalize_assets.py` now rescales every wall and prop to one canonical size: props 120 px wide (about one tile at a 128 px tile) and walls 96 px wide, with a height cap relative to a merc (props 168 px, tall walls 150 px, low barriers 84 px; a merc is about 122 px tall at that scale). `BoardView` draws them all at `tile_width / 128` (`CANON_TILE_PX`). `tests/test_maps.gd` checks every piece in all 12 themes. To resize everything, change the constants at the top of the script and re-run the pipeline: `slice_theme.py`, `slice_iso_props.py`, then `normalize_assets.py` (re-slice first; repeated resizing blurs).
