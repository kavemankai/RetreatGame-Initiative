# Tactics kit: our engine as a reusable toolkit (Godot 4.6, GDScript)

This is the part of `retreat-sim` that is not specific to The Long Retreat: a deterministic squad-tactics engine with a Jagged-Alliance-style **AP/initiative** ruleset, a fog-of-war vision model, a utility AI, data-driven maps, tiers, gear and goals, an isometric board renderer, a sandbox, a headless test suite and an Android export script. A new game reuses the layers below and replaces the data and story.

Nothing here has been moved or renamed; this document is the map. Retreat-specific pieces are listed at the end so you know what to swap.

## 1. Layers (dependencies point down only)

| Layer | Folder | Contents | Rule |
|---|---|---|---|
| **Sim core** | `sim/` | `SimState`, `SimGrid` (edge cover), `SimUnit`, `SimLos`, `SimVision` (fog), `SimPathing`, `SimResolver` (pure shot evaluation), `SimDice` (seeded d100/d10), `SimConst` (every tuning number), `SimAI` + `SimAIProfile`, `SimGoal` | Integers only, no nodes, no engine time, no floats. Same state and seed give the same result on any device. |
| **Rulesets** | `sim/sim_turn.gd`, `game/sim_match.gd`, `game/initiative_match.gd` | `SimTurn`/`SimMatch`: simultaneous 20-tick planned turns (legacy). **`InitiativeMatch`: live AP turns with interrupts and overwatch (the direction).** | A ruleset owns turn flow and calls the core. Rulesets never import views. |
| **Game layer** | `game/` | `MapData` (map JSON), `MissionBuilder`, `Campaign` (roster, stash, gear, tiers), `Sandbox`, `Session` (state across scenes) | UI-agnostic. |
| **Views** | `view/` | `BoardView` (iso renderer), `InitiativeView`, `SandboxView`, `PlayView`, `ThemeArt`, `UnitSprites`, `SoundBoard` | Views read events and state; they never decide rules. |
| **Data** | `data/` | `maps/*.json`, `ai_profiles.json`, `story/*.json` (tiers, items, route, cast) | Balance changes are data edits. |
| **Tools** | `tools/`, `tests/` | export script, map generators, screenshot rigs, balance probe, lint, 391 headless tests | Run before every build. |

## 2. The AP/initiative ruleset (`InitiativeMatch`)

Build one from any `SimMatch` and play it:

```gdscript
var im := InitiativeMatch.from_match(sim_match)   # or InitiativeMatch.new(state, profiles, assignments)
im.start()                                         # player turn 1, sentries on watch
var beats := im.move(unit_id, tile)                # -> [{"events": [...], "state": SimState}]
beats = im.shoot(unit_id, target_id)
beats = im.hold_watch(unit_id, Vector2i.RIGHT)     # costs all AP
beats = im.end_turn()                              # runs the AI turn, refills AP, turn += 1
```

Queries for a UI: `ap_of(id)`, `can_act(id)`, `reach(id)` (tile to AP cost, on the side's fog view), `path_preview(id, tile)`, **`route_preview(id, tile)`** (cost per step and which visible enemies would interrupt on that step), `shot_preview(id, target)` (result, chance, damage, cost), `is_suppressed/is_broken/is_over`, `winner`.

Rules, in one place:
- **AP:** `AP_PER_TURN` (14) per merc per turn, minus stress. Step 2, diagonal 3 (sprinter boots make it 2), shot 4 (3 at aim 8+, never below 2).
- **Order:** your whole squad acts in any order, then the enemy, then the round ends (goals check, reinforcements arrive).
- **Initiative:** `speed*10 + aim - 3*hits_taken`.
- **Interrupt:** a defender who gets a first clear shot at a mover (could not shoot the previous tile), within `min(max_range, sight)`, with initiative at least the mover's, with reaction AP and no earlier interrupt on that mover this turn, fires at once and halts the mover.
- **Reaction gate:** a unit that ends its turn with less than a shot of AP left has no reaction shot.
- **Overwatch:** costs all AP; fires once at the first enemy to move inside the cone with line of sight, regardless of initiative, then is spent.
- **Shots:** hit chance `35 + 7*aim + gear - 4*(distance-2)`, clamped 10..95, rolled on seeded dice; cover edges block outright. Hits trigger a morale check (steady = cannot shoot until its next turn, broken = no AP). Hollows (drones) are exempt.
- **Fog:** each side only sees what its units see; previews and AI use that view and never leak hidden units.

## 3. Making a new game on the kit

1. **Rules numbers:** edit `sim/sim_const.gd` (AP per turn, costs, hit chance, morale, sight). Run the tests; they show what you broke.
2. **Maps:** a JSON file in `data/maps/` (see section 4). Validate with `MapData.problem()`; `tests/test_maps.gd` shows how. Use `tools/make_sandbox_map.py` as a template for a generator script.
3. **Units:** tier stats in `data/story/enemy_tiers.json`, gear in `data/story/items.json`, AI personalities in `data/ai_profiles.json` (integer weights only).
4. **Goals:** add a `goal` block to a map (`hold`, `collect`, `survive`, `reach_return`; none = last side standing). New goal types go in `sim/sim_goal.gd`.
5. **Screens:** `InitiativeView` plays any `SimMatch`; `SandboxView` is a setup screen you can copy. Both talk to the core only through `InitiativeMatch` and `Session`.
6. **Art:** tilesets and sprite sets are folders under `assets/` (`themes/<theme>/`, `mercs/<key>_<frame>.png`); the pipeline scripts live in `art/`. Themes are listed in `MapData.THEMES`.
7. **Build:** `powershell -File tools/export_android.ps1 [-LevelTest] [-Install]`.

## 4. Data formats

**Map** (`data/maps/<id>.json`): `theme`, `size [w,h]`, `player_spawns`, `enemy_spawns`, `blocked [[x,y]]` (crates), `v_walls` and `h_walls` as `[boundary, from, to, "full"|"half"]`, optional `enemy_defs` (`pos`, `tier`, `role` patrol/guard/sentry, `facing`), `reinforcement_defs`, `zone_defs`, `goal`, `objective`.

**Enemy tier**: `stats {hp, speed, aim, cqb, morale, sight}`, `id_base`, `profile`; hollow variants are built at the world's drone percent with no morale.

**Item**: `slot` armour/weapon/mod, `stats` (hp, morale, speed, range, damage, shot_ticks, accuracy), or a mod `trait` (scope, sprinter, bracing, opener). New traits are one function each in the sim.

**AI profile**: `w_damage, w_kill, w_exposed, w_cover, preferred_range, w_range, w_objective, w_watch`.

## 5. Determinism rules (do not break these)
- Integer math only in `sim/` and rulesets; no `randf`, no `Time`, no physics.
- All randomness comes from `SimDice` keyed by `(seed, turn, tick, unit, nth)`.
- Views may only read events and states; the sim never calls into `view/`.
- Every new rule gets a headless test (`tests/test_*.gd`, discovered automatically) and, for rule changes, a mutation check (break the rule and see a test fail).

## 6. Tools
| Command | Purpose |
|---|---|
| `godot --headless --path . -s tests/run_tests.gd` | the whole suite |
| `godot --path . res://view/sandbox.tscn` | sandbox: set stats, gear, enemies on the proving ground |
| `godot --path . res://view/initiative.tscn -- --sandbox=1 "--do=sel 1;move 5,7;end" --shot=out.png` | scripted play and screenshot (`sel`, `preview`, `move`, `shoot`, `watch`, `end`) |
| `tools/balance_probe.gd` | auto-play balance (plans for the old ruleset; an AP probe is on the roadmap) |
| `tools/lint_story.gd` | validates the story and data files |
| `tools/export_android.ps1` | debug APK (SDK paths come from Godot's editor settings) |

## 7. What is Retreat-specific (replace for a new game)
`story/` and `data/story/` (cast, scenes, route, world), `Campaign` flavour (Procession, Hollowing, Writ officers), `view/campaign_view.gd`, all art and audio, `docs` (STORY_BIBLE and friends). The sim, `InitiativeMatch`, `MapData`, `Sandbox`, `BoardView` and the tests are generic apart from names.

## 8. Toolchain (checked 2026-10-14)
Godot 4.6.3 stable with matching export templates, JDK 17.0.20, Android SDK: cmdline-tools 23.0.0 (updated today), build-tools 35.0.1, platform android-35, platform-tools 37.0.1. Keep build-tools and platform at the versions Godot 4.6 expects.

## 9. Known gaps
See `ENGINE_ROADMAP.md`: doors, sight modifiers, patrol routes, hostages, stances, aimed shots, an AP-aware balance probe, camera follow and pinch zoom.
