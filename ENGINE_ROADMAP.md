# Engine and game roadmap (activation engine is the direction; statuses updated 2026-10-15)

> Section B was written for the live-AP `InitiativeMatch`. The activation engine replaced it as the default; rows B1, B6 and B7 below are updated, the rest still apply to either engine.

Status key: **Missing** = not built, **Partial** = built but incomplete, **Tune** = built, numbers unproven. Effort: S (under a day), M (a few days), L (a week or more).

## A. Act 1 map features (the maps play without them today)
| # | Item | Status | Notes | Effort |
|---|---|---|---|---|
| A1 | **Doors** (Karsa fire door, greenhouse doors) | Missing | An edge that is a full wall until a merc spends AP beside it. Needs a sim edge state, open/close action, AI awareness, door art, and sight blocking. | M |
| A2 | **Sight modifiers** (Weir drift fog, Orchard lit lane) | Missing | Per-tile sight cost or bonus; used by `SimVision`, `_can_fire` and the interrupt check. Art tint already exists. | M |
| A3 | **Patrol routes** | Missing | Patrols push at the squad. Needs waypoint loops in map data and a "walk the loop until you see someone" AI state. | M |
| A4 | **Hostages / escorted units** (Orchard) | Missing | A third team or neutral unit type that follows or is carried to the exit, can be shot, and counts in the goal. | L |
| A5 | **Goal variety checks** | Partial | Hold, collect, survive and reach-then-return exist; "escort" needs A4. | S |
| A6 | **Acts 2 and 3 maps** | Missing | Eight maps still use the old 12x10 layout. Redesign after Act 1 is approved. | L |

## B. Initiative ruleset
| # | Item | Status | Notes | Effort |
|---|---|---|---|---|
| B1 | **AP budget** | Done (14) | 14 AP per activation, now in `data/combat/ap_costs.json` (the sandbox can override it; AP sweep in `docs/combat/balance-table.md`). Retune from play; try 10 to 12 on tighter maps. | S |
| B2 | **Route preview with exposure** | Done | Cost per step, red steps where a visible enemy would shoot first. | - |
| B3 | **Stances** (stand, crouch, prone) | Missing | Cost AP; change hit chance, sight and interrupt exposure. The classic JA2 layer. | M |
| B4 | **Aimed shots** | Missing | Extra AP for extra hit chance. | S |
| B5 | **Overwatch cone choice** | Partial | The Watch button picks a direction automatically (toward the nearest visible enemy). Let the player choose the facing. | S |
| B6 | **Interrupt rules review** | Superseded | The activation engine has no automatic interrupts, only armed one-shot overwatch (4 AP). Interrupts remain in the legacy `InitiativeMatch` only. | - |
| B7 | **Enemy AI in AP mode** | Done (core) | `ActivationAI`: one legal action at a time, legality check, caps, decision log, lane weight, walking-distance objective; 1,000-battle soak clean. Still open: patrol routes (A3), retreat when hurt, memory of unseen shooters. | M |
| B8 | **Weapon variety** | Partial | Gear changes range, damage, ticks per shot and accuracy. Add burst/auto fire, thrown items, and reload or ammo if wanted. | M |
| B9 | **Wounds and bleeding** | Missing | HP is the only damage state. JA2 has wounds that bleed and healing items. | M |
| B10 | **Items in play** | Missing | Medkit, grenade, smoke. Needs inventory per merc and an item-use AP cost. | M |

## C. Interface (phone)
| # | Item | Status | Effort |
|---|---|---|---|
| C1 | Camera follows the selected merc or the action (the route preview can run off-screen) | Missing | S |
| C2 | Pinch zoom and drag to pan | Missing | M |
| C3 | Tap an enemy to inspect (stats, role, what they can see) | Missing | S |
| C4 | Undo for an unconfirmed move (cancel the pending tap) | Partial (second tap confirms; right click or tap elsewhere cancels) | S |
| C5 | Volume sliders and a settings page | Missing | S |
| C6 | End-of-battle summary (kills, shots, AP spent) | Missing | S |
| C7 | Sandbox: save and load setups, place enemy facing, per-enemy stat edits, map picker | Missing | M |
| C8 | Tutorial or hint overlay for the first fight | Missing | S |

## D. Balance and verification
| # | Item | Status | Effort |
|---|---|---|---|
| D1 | Human playtest of all four Act 1 maps in AP mode | Missing | - |
| D2 | A balance probe that plays the AP ruleset (the current probe uses the old planner) | Missing | M |
| D3 | Orchard stalemate for the auto AI (nobody engages) | Open | S |
| D4 | Hit chance, hit points and tier numbers retuned once AP costs settle | Tune | M |
| D5 | Soak tests: random squads and enemy lists through the sandbox build, checking no crash or stuck turn | Missing | S |

## E. Cleanup and cost
| # | Item | Notes | Effort |
|---|---|---|---|
| E1 | Retire the planned (simultaneous) mode | Remove `play_view`, `plan_builder`, `play_controller`, timeline bar, and the ruleset switch once you are sure | M |
| E2 | Docs: AP ruleset in `MECHANICS_SPEC.md` (done) and `LEVEL_DESIGN_ACT1.md` (still to do) | See `TACTICS_KIT.md` | S |
| E3 | APK size: the level-test build is 29.2 MiB against a 30 MiB delivery limit | Compress audio, trim unused sprite frames, or deliver by another route | S |

## Suggested order
1. B1 and D1 (tune the AP budget, then you play).
2. C1 (camera follow) and C3 (inspect), the two things that hurt most on a phone.
3. A1 doors and A2 sight modifiers, the two features the Act 1 designs lean on most.
4. A3 patrols and B7 AI, so enemies behave better than "stand still or charge".
5. B3 stances and B4 aimed shots, if you want the deeper JA2 feel.
6. A4 hostages, then Acts 2 and 3 maps.

## Appendix: our AP rules against JA2 1.13 (2026-10-14)
Read for ideas only. The 1.13 source and data fall under the Strategy First non-commercial licence, so nothing here is copied from them, and numbers below are quoted from `APBPConstants.ini` for comparison. Items marked (from memory) are general JA2 knowledge I did not check in the repos.

| Rule | JA2 1.13 | Ours now | Note |
|---|---|---|---|
| AP per turn | 100 (min 40) | 14 (was 20 before the first retune) | Same shape once scaled: our 14 is about JA2's 70. |
| Flat step | 12 (grass 14, bush 18, rubble 24) | 2 (diagonal 3) | JA2 gets about 8 steps per turn; we get 7. Terrain never changes our cost. |
| Gait and stance | walk -4, run -8, crawl +4; crouch 6, prone 8 | none | No stances yet (roadmap B3). |
| Turn facing | 4 | free | Facing only matters for sentries. |
| Change target | 2 | free | Shots always cost the full 4. |
| Interrupt gate | needs at least 16 AP left | (legacy mode) reaction pool of one shot, refilled each turn; the activation engine has no interrupts | Different mechanism, same intent: a spent unit cannot react. |
| Interrupt order (from memory) | interrupt points built from initiative, with a bonus for being alert | `speed*10 + aim - 3*hits_taken` | Ours is simpler and deterministic. |
| Shot cost (from memory) | roughly 2 to 3 steps, rising with aiming | 4 (2 steps) | Our shots are cheap relative to movement. |

### Proposed retune (items 1 and 3 applied 2026-10-14; 2, 4 and 5 still open; item 3, the reaction gate, applies to the legacy mode only)
Goal: fewer steps per turn so positioning matters, and shots stay a real choice.
1. **AP per turn 14** (7 straight steps, or 3 shots, or 1 shot plus 5 steps). Keep step 2, diagonal 3, shot 4. Use a separate `AP_PER_TURN` in `InitiativeMatch` so the planned mode's 20-tick round and its tests are untouched.
2. **Optional speed scaling:** `AP = 10 + speed / 2` (speed 4 gives 12, speed 8 gives 14, speed 10 gives 15). Makes fast mercs genuinely longer-legged without a new stat.
3. **Reaction gate:** today a unit's reaction shot is always refilled, however much AP it spent on its own turn. Try the JA2 feel: a unit that ends its turn with fewer AP left than one shot gets no reaction shot, so spending everything has a cost and Overwatch (all AP) stays the deliberate exception.
4. **Terrain cost (later):** bush or rubble tiles cost +1 to enter; gives open-ish maps like the proving ground more texture.
5. **Aimed shot (roadmap B4):** +2 AP for +15 hit chance, so the 14 AP budget has a real trade.

Check after retuning: how many turns it takes to cross the proving ground (20 wide) at 7 steps (about 3 turns), and that Karsa and Pellam are still winnable. The sandbox is the quickest place to feel it.
