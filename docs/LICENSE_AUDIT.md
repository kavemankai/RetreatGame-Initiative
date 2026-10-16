# Licence audit (2026-10-16)

This is a working record, not legal advice. **Release status: private testing and sharing with one family member only. Not cleared for commercial release or public distribution. The builds in `dist/` now contain Jagged Alliance 2 art and sound (below): do not upload or share them beyond that.**

## Jagged Alliance 2 source (reference only)
- Repository: `github.com/kavemankai/jaggedalliance2` (fork of `videogamepreservation/jaggedalliance2`), top level `ja2/`, `Standard Gaming Platform/`, `readme.txt` and **`SFI Source Code license agreement.txt`**; GitHub reports no SPDX licence.
- The SFI-SCLA (read in full on 2026-10-16) allows use "for any non-commercial purpose"; forbids using or distributing the software **or any works that derive from it** for commercial purposes; requires a verbatim copy of the licence, change notices and the disclaimer if you distribute it or derivatives; reserves all other rights; grants Strategy First rights to modifications; ends automatically on breach.
- **Superseded 2026-10-16 (see "JA2 placeholder art" below): the original text here said nothing was taken. Source code and data are still not used.** Original statement: No JA2 source, data, text, art or audio was copied, translated or ported into this repository. The JA2 systems were studied only as design reference (see `FEATURE_COMPARISON.md`); the game's AP, initiative, overwatch, cover and AI code are original GDScript written for this project, and the existing design notes record numbers "quoted for comparison, not copied". For that reason the SFI-SCLA obligations for derivative works are not triggered. If any JA2-derived code or data is ever added, the whole game becomes subject to the non-commercial terms above.
- The JA2 repository was not cloned into this repository or built during this pass.

## Engine and tools
| Component | Licence | Note |
|---|---|---|
| Godot Engine 4.6.x and export templates | MIT (plus the third-party notices Godot ships; Android templates include Kotlin/AndroidX parts under Apache-2.0) | The exported games embed these; Godot's own licence texts are in the editor under Help > About, and must accompany a public release |
| Default UI font | Godot's built-in font (Open Sans, SIL OFL) | No other fonts are bundled |
| Python scripts in `art/` and `tools/` | Own code; use Pillow for image slicing | Not shipped in the game |

## Game content
| Content | Origin | Status |
|---|---|---|
| Code, data, story, scenes, cast | Written for this project | Owner's |
| Sprites, tiles, props, portraits | AI-image-generated, then cut out, normalised and re-timed by scripts in `art/` (see `ART_DIRECTION.md`) | **Terms of the generation tools were not re-checked in this pass.** Fine for private sharing; confirm the generators' commercial and redistribution terms before any public release |
| Sound effects, ambience, music beds | Synthesised in code by `art/make_sounds.py` (no samples) | Original |
| UI art | Drawn in code | Original |

## Restrictions to carry forward
1. Do not publish or sell the game until the sprite/tile generation terms are confirmed.
2. Do not add JA2 source, data or assets (or code ported from them) without accepting the SFI-SCLA non-commercial limit for the whole game.
3. The Android build is debug-signed; it is for sideloading only.

## JA2 placeholder art (added 2026-10-16, owner request)
The owner asked for Jagged Alliance 2 assets to be used as placeholders and tests. Source: `github.com/1dot13/gamedir` (archived; "Game assets for the Jagged Alliance 2 v1.13 project", no licence file), sparse-checked-out to `C:\Users\kyler\JA2Assets` (outside this repository).
- Used: soldier animation layers (`Data/Anims/LOBOT/RGM`), gun and item art (`Data-1.13/BigItems`), portraits (`Data-1.13/faces`), snow tileset objects (`Data-1.13/tilesets/50`), merc voice clips (`Data-1.13/BattleSNDS`). Converted by our own code (`tools/ja2_sti.py`, `tools/ja2_skin.py`) into `retreat-sim/assets/ja2/`, which is **git-ignored** and never committed.
- The packaged exe and APK built from a machine that has `assets/ja2/` **embed these files**. They are third-party copyrighted game assets of unclear terms (the repository has no licence; the JA2 source licence next door is non-commercial only). Treat them as private test material for the owner and one family member.
- Toggle: main menu "Art: JA2 placeholders / Art: original". With the folder absent, or the toggle set to original, the game uses only its own art. To ship without JA2 material, delete `retreat-sim/assets/ja2/` and rebuild.
- No JA2 *code* was used (the STI reader is written from the public file format).