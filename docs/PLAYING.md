# Playing The Long Retreat 1.0.0

## Install
**Android phone (arm64, Android 7 or newer).** Copy `TheLongRetreat-1.0.0.apk` to the phone (cable, cloud drive or message to yourself), open it, and allow "install from this source" when asked. It is not from the Play Store, so Android will warn; that is expected. It installs as **The Long Retreat** and upgrades the earlier Act-1 build in place (saves are kept). Debug-signed; sideload only. *(Not yet run on a phone from this machine, see REMAINING_ISSUES.md.)*

**Windows PC.** Run `dist/windows/TheLongRetreat.exe` (one file, nothing to install). The window is portrait; resize it freely. Windows may show a SmartScreen warning because the file is unsigned: More info, then Run anyway.

Build instructions are in `TECHNICAL_ARCHITECTURE.md`.

## Start
Main menu: **New campaign (Story difficulty)** starts at once. "Change difficulty for a new campaign" switches between Story (your units have one extra hit point and enemies shoot less accurately) and Standard (the designed fight). The choice is saved with the campaign. **Continue campaign** loads it; **Resume battle** reopens a fight you left mid-way.

## In a fight (phone or mouse; a click counts as a tap)
| Do this | To get this |
|---|---|
| Tap a tile once | Preview the route and its AP cost (red steps: an enemy would shoot first) |
| Tap the same tile again | Move there |
| Tap an enemy once | See hit chance, damage, range and AP |
| Tap the same enemy again | Fire |
| Overwatch (4 AP) | One free shot at the first enemy that moves into the cone |
| End Activation | Pass; the next unit in the order strip acts |
| Map | Toggle a zoomed-out view of the whole board |
| Sound | Mute / unmute |
| Withdraw (tap twice) | Leave the mission as a failure, keeping the survivors |

Each merc has 14 AP per activation: a step costs 2 (diagonal 3), a shot 4. Walls and crates give cover (-30 to the enemy's hit chance); holding fire "digs in" for extra cover, shooting from cover wears it down, moving resets it. The first mission shows tips as you go.

## Between fights
The route map shows where you are. **Brief** opens the prep screen (briefing, who goes, Loadout, Roster). After a fight: result, salvage (equip from the stash), level-ups (pick one of three), roll call for the fallen, debrief and choices. The Roster and Loadout buttons are on the map and prep screens.

## Save and quit
The campaign saves after every step of the chain. A battle autosaves after each command; quitting mid-fight shows **Resume battle** on the menu. Saves live in the app's own data folder (Windows: `%APPDATA%\Godot\app_userdata\Retreat Sim`). A save from another version is refused with a reason and never overwritten.
