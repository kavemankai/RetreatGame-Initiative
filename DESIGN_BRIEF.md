# Design Brief (workshop draft v0.1) — 2026-10-13

## Intent
- New game; existing repos are **reference and reusable parts**, not a base.
- Purpose: **prove an AI-dev workflow** (docs-as-truth, AI art/audio, autonomous agent builds, public write-up).
- Open-ended hobby timeline. **Mobile-first, portrait, tap-to-act.**

## Pitch (working)
Jagged Alliance-style mercenary squad tactics in a space-opera **retreat arc**. A hand-crafted cast of
3-4 mercs, permadeath, and the **Hollowing**: a dead named merc is replaced by a faceless, weaker drone.
A hegemonic military is hunting the squad.

## Locked decisions
| Area | Decision |
|---|---|
| Combat | Ground squad tactics: action points, cover, line of sight |
| Turn model | **Plan all, then resolve together** (simultaneous resolution) |
| Randomness | **Fully deterministic**, no dice |
| Squad | 3-4 mercs, permadeath, Hollowing replaces the dead |
| Campaign | Mission deck, retreat/survival arc; total squad loss = campaign over, new run |
| Progression | XP from battle; a level-up offers three stat steps and you pick one (decided 2026-10-15). No injury system: permadeath plus Hollowing is the consequence. |
| Cast | Hand-crafted named mercs with portraits |
| Antagonist | Hegemonic military |
| AI at runtime | **None**; AI is used at build time (story, art, audio, code) |
| Narrative QA | Story bible + structured data + your review + automated lint |
| Engine | **Godot 4.6** (recommended) |
| Art | Pixel-art top-down tiles/sprites + illustrated portraits (recommended) |
| Fog | Partial fog: visible enemies show intent; unseen are hidden (recommended) |
| Mission length | 8-15 minutes (recommended) |
| Milestone 1 | Combat + phone UI feel |

## Reference map
- **JaggedBuild (The Long Retreat):** Hollowing, plan-then-resolve rhythm, mission deck, pilot XP,
  autoload-per-system structure. Note: it is a *space dogfighter*, not ground tactics.
- **BattleBlips:** docs-first process (MASTER_PLAN, schemas, patches), check-in vs play-mode UI split,
  data-driven balance sheet, tests/ and tools/ layout.
- **StarFall:** narrative contacts, reputation, ship-loss/insurance ideas; its AI GM is *not* used at runtime.
- **BRPG:** TypeScript/Expo shell; little documented. Likely reference only.
- **Game-Decompilations:** link list. Policy: **study mechanics only**, write original code and assets.

## Open questions
1. Title, tone references, and the one-sentence hook.
2. Squad economy during a retreat (supplies, ammo, wounds, time pressure).
3. What the Hollowing means narratively (cause, rules, whether it can be reversed).
4. Hub structure between missions (ship? convoy? safehouse?) and how mercs talk to each other.
5. Audio direction and generation pipeline.
6. Monetization (deferred, as in BattleBlips).
7. Map size, grid type, and tap-to-act UI specifics.
8. Roster size of authored cast (suggest ~10-12) and who they are.

---

## World (workshop round 9a)
- **Premise:** The war is lost. The squad is the rearguard escorting **civilian survivors** along a retreat route to a **real refuge** (whether it is safe is left for the story bible).
- **Tone:** Melancholic and haunting. Space as a graveyard; quiet, beautiful, costly.
- **The Hollowing:** the squad's *own side's doctrine* — a fallen soldier's slot is refilled by a drone to keep the unit "at strength". It is **automatic; the player cannot refuse it.** The story is how characters react.
- **The hegemony:** orderly, relentless state military; face of the enemy is the pursuer.
- **The pursuer:** a **relentless professional**, no personal history. His own squad **hollows as the player kills its members**, until it is entirely drones. (Mirror of the player's arc; his end-state is a story question.)

### New open questions
- What happens when the pursuer's squad is fully hollow — does he change, break, or become more dangerous?
- Who ordered the doctrine, and does anyone in the squad question it?
- What do the civilians do in play (objectives, morale, resources)?
- What is the refuge, and does reaching it pay off the doctrine theme?
