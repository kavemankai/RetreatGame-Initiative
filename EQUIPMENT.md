# Equipment (implemented)

Every named merc has three slots: **armour**, **weapon**, **mod**. Items live in a campaign **stash** until worn. There is no currency: items come from mission rewards and from officers' drops. Data: `retreat-sim/data/story/items.json`. Rules: `retreat-sim/game/campaign.gd` (equip, stash, loot, save) and the traits in `retreat-sim/sim/`.

## Rules
- **Standard issue:** every named merc starts in a **Compact vest** (+1 hp). This replaces the old flat +1 HP edge; the human side's toughness now lives in an item.
- **Empty weapon** = the issue rifle (range 6, damage 1, 4-tick shots). Weapons are sidegrades with a trade-off. Empty mod = nothing.
- **Death:** a dead merc's items go back to the stash. A **Hollow** takes no gear and fights bare at 60% of the base stats (no morale, fearless). A reserve who fills a vacant slot starts with an empty kit.
- **Rewards:** a successful mission adds its `rewards` to the stash. Killing a Writ officer drops their signature item (Gavel's plate, Seal's rifle), even if the mission fails (but not when the squad is wiped).
- **Saves:** version 2 holds each slot's gear and the stash. A v1 save loads with the vest on every named merc and an empty stash.
- **Clamps:** hp, speed, range, damage at least 1; shot length at least `MIN_SHOT_TICKS` (2); morale 0..12.

## Items (first set; names are placeholders)
| Slot | Item | Tier (first act) | Effect |
|---|---|---|---|
| Armour | Compact vest | 1 (start) | +1 hp |
| Armour | Mourning cloak | 1 | +2 morale |
| Armour | Plate carrier | 2 | +1 hp, +1 morale, -1 speed |
| Armour | Gavel's plate | 2 (drop) | +2 hp, +1 morale, -2 speed |
| Armour | Ablative coat | 3 | +2 hp, -1 speed |
| Weapon | Short carbine | 1 | -1 range, -1 tick per shot, -5% to hit |
| Weapon | Scatter gun | 1 | -2 range, +1 damage, -5% to hit |
| Weapon | Marksman rifle | 2 | +2 range, +1 tick per shot, +10% to hit |
| Weapon | Seal's rifle | 2 (drop) | +1 range, +5% to hit |
| Weapon | Heavy rifle | 3 | +1 damage, +1 tick per shot |
| Mod | Salvaged scope | 1 | trait `scope` |
| Mod | Sprint boots | 1 | trait `sprinter` |
| Mod | Bracing stanchion | 2 | trait `bracing` |
| Mod | Reflex rig | 3 | trait `opener` |

## Mod traits
- **scope:** +2 sight, +1 range.
- **sprinter:** diagonal steps cost the same as straight ones (2 ticks, not 3). The path planner, order costs and Move+Fire pricing all use `SimUnit.step_cost`.
- **bracing:** +5% to hit for its owner's shots from beside cover; its owner gets +2 (not +1) on the morale check beside cover.
- **opener:** the owner's first clear shot each round has +15% to hit. (The planning preview does not include it.)

## Rewards by mission
Act 1: Karsa Breakout carbine; the Weir scope; Pellam Dock mourning cloak; Orchard Ring sprint boots.
Act 2: Quiet Wards plate carrier (+ Gavel's plate if Gavel falls); Anselm marksman rifle (+ Seal's rifle if Seal falls); Cinder Market scatter gun; Mirror Gate stanchion.
Act 3: Reliquary Lane heavy rifle; Long Corridor ablative coat; Tamsin's Rest reflex rig; Vesper Threshold none.
Lint rejects an item rewarded before its tier's act.

## UI
Squad screen: **Loadout** button, then a merc list, then that merc's three slots, then the stash items for a slot (each with its effect line), with Equip and Take off. The mission result page lists the salvage. Phone-first: no drag and drop.

## Not done
- Item icons and art; a slot glyph on the slot tag.
- Loadout is only reachable from the squad screen (not mid-mission).
- Enemies carry no gear; their strength is their tier (see `ENEMY_TIERS.md`).
