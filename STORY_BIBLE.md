# THE LONG RETREAT — Story Bible (v1.0)

Working title: **The Long Retreat**. Source of truth for the world. The structured data in
`retreat-sim/data/` (`world.json`, `cast.json`, `writ.json`, `route.json`, `scenes.json`) must agree with
this document, and `StoryLint` (run by the test suite) enforces the mechanical parts.

> Decisions in this document were made autonomously on 2026-10-13 after the interview rounds, building
> on the user's locked choices (see DESIGN_BRIEF.md). Anything marked **[DECISION]** is a choice the
> author made and is open to being overruled.

---

## 1. One-paragraph pitch

The war is over and nobody has told the army. The **Lantern Compact** lost it years ago, but its high
command kept the books looking full: when a soldier dies, a **hollow** — a tethered, vat-grown body
wearing the dead soldier's slot number — is shipped to fill the roll, because under the **Muster Law**
no unit may be reported below strength. You command the **9th Rearguard**, the last real people in a
ghost army, escorting a convoy of 6,200 civilians (**the Procession**) along the **Reliquary Lanes**
toward a refuge that may not let you in. Behind you comes **Provost Orrick** of the Meridian
Hegemony's Retrieval Bureau, who does not want to destroy you. He wants you to be *counted*.

## 2. Themes and the rule that governs all writing

- **Counting.** Who is counted, who is only a number, and what a roll is for. Ledgers, rolls, slots,
  musters, tallies. A name read aloud is the smallest act of resistance in the game.
- **Presence vs. strength.** "Strength" is a bookkeeping state; presence is a person.
- **Reasonable horror.** The Hegemony is orderly, courteous and *offers terms*. It is frightening
  because it sounds sensible.
- **Mirror.** Orrick's squad hollows as you kill it, as yours does as it dies. By the end both sides are
  mostly bodies on a list.

**Voice (enforced where mechanical):** melancholic, spare, concrete, quiet. Short sentences. Sensory
detail (cold metal, recycler hum, the smell of ozone on a hull). Dry, small humour is allowed and
precious; it should never be a joke at the dead's expense. No exclamation-mark energy, no modern slang,
no quippy action-movie banter. Lanterns, ledgers and lights are the recurring images.

## 3. The world

### 3.1 Timeline (Compact Years, CY)
| CY | Event |
|----|-------|
| 160 | The Lantern Compact is founded: forty outer colonies, each lighting a lantern on its dock for the others to steer by. |
| 199 | The Meridian Hegemony, a core-world state built on "Reconciliation", begins absorbing Compact worlds by treaty and blockade. |
| 207 | **Battle of Ostrava Narrows.** Three Compact armies are mauled. Quartermaster-General **Idris Vael** enacts **Muster Law, Article Nine: "Strength Is Presence."** No unit is to be reported below strength. The Foundry ship *Anselm* begins producing **hollows**. |
| 208–211 | The war is lost in fact but not on paper. The Roll shows 14 companies in the field. The Hegemony counts them and finds the numbers do not add up. |
| 212 | **Fall of Karsa Station.** High command dies in the siege. The only intact company that breaks out is the 9th Rearguard, escorting the Procession. The Roll — the ledger of the dead and the "living" — survives on Quill's slate. |

### 3.2 Factions
- **The Lantern Compact** (the player). A defeated league. Its institutions are gone; its *procedures* are not. The Muster Law still runs on the Tether net and nobody can switch it off.
- **The Meridian Hegemony.** Orderly, reasonable, patient. Governs by Reconciliation: absorb, register, resettle. Its **Retrieval Bureau** recovers loose assets — people, ships, archives. Orrick's bureau.
- **The Keepers of Vesper.** A silent custodial order guarding the refuge. Neutral, unarmed, immovable.
- **The Procession.** 6,200 civilians in eleven ships: colonists, archivists, children, the wounded. Not soldiers. The reason for everything.

### 3.3 The Hollowing (the central mechanic and the central horror)
- **What it is [DECISION]:** the Compact's *own* doctrine, not an enemy weapon. When a named soldier dies,
  the Tether net auto-requisitions a replacement at the next **muster** (a resupply drop). The
  replacement is a **hollow**: a vat-grown body, neural-scrubbed, driven by a **Tether** harness on the
  squad net. It carries the dead soldier's **slot number** (designation `HX-07`, never the callsign) and
  roughly **60% of their skill** — the muscle memory the vats could copy. No morale, no growth, no
  abilities, no voice of its own.
- **It is automatic and cannot be refused** (locked decision). The squad can only decide what to *do*
  about it: the **Roll Call**.
- **Roll Call (Remembrance) [DECISION]:** after a death the squad may *read the name* aloud, or say
  nothing. It changes nothing mechanical in a fight. It accumulates **Remembrance** (7 opens The Roll Read, 6
  makes Orrick say his name; see the amendments in section 8). Some soldiers swear a hollow
  flinches when its old friend's name is read. Nobody can prove it.
- **The cost:** each refill costs **1 Reserve** (the muster drop is a physical resupply). If Reserves are
  empty the slot stays **vacant** — the squad runs below strength, which the Law forbids and the net
  reports as an error nobody is left to read.
- **Why the lie exists:** a roll that shows a full army buys time, credit and mercy. By CY 212 the lie
  *is* the only thing still holding the Compact's remaining convoys together. Which is why truth is the
  most dangerous cargo Quill carries.

### 3.4 The pursuer: Provost Orrick **[DECISION]**
- **Public face:** a relentless, courteous professional. No history, no grievance, no cruelty. He opens
  every transmission with terms: *stand down, be counted, the Procession will be resettled.*
- **The twist:** "Orrick" is a **designation**, not a man. The Bureau has used the Compact's captured
  Echo technology since Ostrava. The current Provost is the fourth **Orrick**: a volunteer who agreed
  to be "made efficient" — partially hollowed himself. His lack of a personal history is not
  discretion; it was edited out. The reveal lands on the mission *The Long Corridor* (act III).
- **The mirror:** his squad, **the Writ**, is six named officers. As you kill them the Bureau backfills
  their slots with hollows. The campaign tracks a **Writ hollow stage 0–6**; when it reaches 6 only
  Orrick is still a person, commanding six bodies. At that point (**the Quiet**) his dialogue strips to
  tallies and procedure. If the player has read enough names (Remembrance 6+), he says one true name — his own — once.
  Killing his body on the field changes nothing: Orrick is a designation, and the Bureau sends the next one.
- **What he wants:** to *count* the 9th Rearguard. A war can only end when the other side's army has
  been counted. The 9th is the last uncounted unit. He does not need them dead; dead does not close the
  ledger.

### 3.5 The refuge: Vesper Reach **[DECISION]**
- A dark station hidden in the ring-shadow of a dead gas giant (**Ouse**), sealed by the Keepers after
  an older war. It is **real and safe**, and large enough for all 6,200 civilians.
- **The price:** the Keepers admit no weapons, no Tethers, and no transmissions for forty years.
  Soldiers and hollows cannot enter. Vesper will take the Procession and the **Roll** (as a memorial),
  not the Rearguard.
- Which means the campaign's last question is not "can we get there" but "who do we become at the
  door". Hollows cannot be admitted *or* refused: they stand outside in rows. (If the Tether is cut they
  simply stop. The **Standing Hundred** is a memorial no one built.)

### 3.6 The route: the Reliquary Lanes
A drift of wrecks and dead stations from Karsa Station to Vesper Reach — the fallen fleet's graveyard.
Twelve stops across three acts (see `route.json`). The map feel is cold, hushed, half-lit: dead hulls
as cover, fog from the wreck-fields, long lines of sight through ruined decks.

### 3.7 The economy (kept deliberately small)
- **Procession** — souls in the convoy, starts at 6,200. Lost to failed escorts, ambushes, neglect.
- **Reserves** — the physical cargo of ammunition, medicine, fuel and **muster drops**. Starts at 24.
  Each hollow refill costs 1.
- **Remembrance** — a count of names read. Never spent; only felt.
- A mission's outcome moves Procession and Reserves; the squad's *dead* move hollows into the roster.

## 4. Structure

- **Act I — The Breakout** (Karsa Station, the Weir, Pellam Dock, Orchard Ring): learn the squad, the lie, the first hollow.
- **Act II — The Counting** (the Quiet Wards, the *Anselm*, Cinder Market, the Mirror Gate): Orrick arrives; the Foundry; the truth about the Roll.
- **Act III — The Door** (Reliquary Lane, the Long Corridor, Tamsin's Rest, Vesper Threshold): the mirror, the reveal, the choice.
- The **mission deck** (the Long Retreat's mission-deck idea) interleaves fixed story missions with
  **contingency cards** drawn from a pool per act: ambushes, stranded tugs, signal fires, a mutiny.
- **Campaign over** if the whole squad is lost in a mission (locked decision). A mission lost with
  survivors costs Procession and Reserves instead.

## 5. The cast (12; see `cast.json`)
A hand-crafted roster; each mission fields 3–4. Ten start; **Wren** joins at Orchard Ring, **Ghost**
at Cinder Market.

| Slot | Callsign | Name | Role | One line |
|-----|----------|------|------|----------|
| 01 | Warden | Capt. Mara Ilesh | Commander | Counts her people every night so she can sleep. |
| 02 | Quill | Tobias Quill | Muster Officer | Keeps the Roll. Knows what it is. |
| 03 | Moth | Rennick Aldous | Scout | Sees farthest; jokes softly; afraid of lights going out. |
| 04 | Sable | Sable Okonkwo | Marksman | Grieves precisely. |
| 05 | Bulwark | Dov Karelian | Heavy | Carries what others cannot. |
| 06 | Static | Ines Valcourt | Signals | Hears the Tether hum in her teeth. |
| 07 | Pilgrim | Yusuf Adeyemi-Roth | Medic / chaplain | Remembers every name. |
| 08 | Needle | Calla Voss | Breacher | Young, fast, furious. |
| 09 | Gran | Anneliese Brandt | Sergeant | Has already lost this war once. |
| 10 | Tinker | Kit Marrow | Quartermaster / demolitions | Gallows humour with a ledger. |
| 11 | Ghost | Oriel Vance | Hegemony deserter | Knows how the Bureau thinks. |
| 12 | Wren | Wren Haldane | Civilian volunteer | Seventeen. Should not be here. |

## 6. Endings (see `world.json`)
1. **The Roll Read** — Remembrance high, Orrick's name recovered. The Procession enters Vesper; the Rearguard reads the whole Roll aloud at the door; the Foundry key is destroyed; the hollows stop and stand.
2. **The Long Watch** — The squad holds the door for forty years, hollowing slot by slot as the muster drops continue to come. A tender, terrible ending.
3. **Quiet Terms** — Surrender to be counted. The Procession is "resettled". Safe, ordinary, and a loss.
4. **Orrick's Rest** — Take Orrick alive when the Writ is all hollow. He is the last person in a room of bodies. What happens to him is the last choice.

## 7. Glossary
**Roll** — the ledger of the Compact's soldiers, living and not. **Muster** — a resupply drop; the moment of
refill. **Hollow** — a Tethered replacement body. **Slot** — a soldier's number; outlives them.
**Tether** — the neural harness and squad net. **Echo** — the process of making a hollow. **Strength** —
the Law's word for a full roll. **The Quiet** — the state of Orrick's squad when all six officers are
hollow. **Reconciliation** — the Hegemony's word for absorption. **Writ** — Orrick's squad.
**Procession** — the civilian convoy. **Remembrance** — the count of names read.

## 8. Implementation status (v1.1)

| Part | Where | State |
|------|-------|-------|
| Story data | `retreat-sim/data/story/*.json` | Complete: 12 mercs, 6 Writ officers + provost, 12 missions + 8 cards, 57 scenes, 4 endings |
| Lint | `story/story_lint.gd`, `story_schema.gd`, `tools/lint_story.gd` | Structure check first, then tone, references, reachability, attainability |
| Campaign model | `game/campaign.gd` | Roster slots, Hollowing, economy, Writ stages, choices, endings, contingency cards, JSON saves |
| Missions | `game/mission_builder.gd` | Campaign mission to SimMatch; outcome back to the campaign. All missions share one map for now |
| UI | `view/campaign_view.gd`, `view/play_view.gd` | Menu, briefing, squad pick, play, result, roll calls, debrief choices, Orrick, endings, saves |
| Soak | `tools/soak_campaign.gd` | Whole campaigns (AI-played or scripted) reaching endings |

### Amendments made while building (these supersede the text above where they differ)
- **Remembrance thresholds are 7 (The Roll Read) and 6 (Orrick says his name)**, not 10 and 8. Sources: +1 per
  named merc whose name is read (whether the slot is refilled or left vacant; a hollow's death has no name),
  +1 for reading a hull's name at the Reliquary Lane, +2 for opening the Roll at Tamsin's Rest. The earlier numbers
  were found to be nearly unreachable.
- **Killing Orrick changes nothing [DECISION]:** Orrick is a designation; the Bureau sends the next one. The
  campaign tracks the Writ's hollowing, not his hit points.
- **A hollow that dies is refilled again** at 1 Reserve; with no Reserves the slot goes vacant.
- **The campaign ends three ways:** the whole squad lost in a mission, no one left to field (every slot vacant),
  or the Procession reaching zero. Failing or withdrawing from a mission with survivors costs Procession and
  Reserves and the route moves on, except the finale, which must be won (a failed finale can be retried).
- **Contingency cards** are offered once per act, after its second story mission, and stay offered until played.
  Their enemies are derived: regulars = squad size, plus one hollow proxy per act after the first.
- The Roll Read ending needs Remembrance 7+, the vats destroyed at the Anselm, and the Roll opened at Tamsin's Rest.

### Known gaps
The four Act 1 missions have their own redesigned maps (see LEVELS.md); the other eight still use the 12x10 terrain (the `map.archetype` fields are briefs for future maps); no art, audio
or voice; cast arcs have beats in data but only some surface in dialogue; `next` is single-path (no branching
routes yet); combat difficulty is untested against people (an early AI-played squad was wiped in mission 2, while in the 2026-10 soak the stand-in squad wins nearly every fight, so the AI
is a weak stand-in for a player, not a balance reference).
