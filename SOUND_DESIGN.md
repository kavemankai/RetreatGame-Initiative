# Sound design (implemented, placeholder-quality)

**Method.** Higgsfield's audio models for music and sound effects are limited to its own game-generation pipeline and its tools say not to use them for standalone audio, so none were used. Every sound is synthesised from code by `art/make_sounds.py` (numpy and scipy, fixed seed) into `retreat-sim/assets/audio/*.wav` (22.05 kHz mono, 7.9 MB total). Re-run the script to regenerate; nothing is downloaded. These are working placeholders: real recorded or composed audio can replace any file of the same name without code changes.

## Sounds
| Group | Files | Used for |
|---|---|---|
| Combat | `sfx_shot_0..2`, `sfx_shot_heavy`, `sfx_hit`, `sfx_miss`, `sfx_blocked`, `sfx_death` | a shot (variant by tick and shooter; heavy for 2-damage hits), then the thud, whizz or cover ping 0.09 s later; a death 0.2 s after |
| Morale | `sfx_steady`, `sfx_broken` | a soft chime or a sinking dissonance 0.35 s after the hit |
| Movement | `sfx_step_0..2` | footsteps, thinned to one every 0.12 s so a squad on the move is not a machine gun |
| Interface | `ui_click`, `ui_confirm`, `ui_go` | any button, confirm, and the Go press |
| Camp | `sfx_equip`, `sfx_loot` | equipping gear; salvage after a mission |
| Stingers | `stinger_start`, `stinger_win`, `stinger_loss` | round start (reserved), mission won, mission lost or match over |
| Ambience | `amb_deck`, `amb_wind`, `amb_foundry`, `amb_market`, `amb_garden`, `amb_hospital`, `amb_relay`, `amb_threshold` | 12 s loops chosen by level theme (`SoundMap.AMBIENT`) |
| Music | `music_act1..3` | 24 s loops, slow minor pads with sparse bell notes; each act lower and sparser |

## Code
- `view/sound_map.gd`: pure mapping from events, themes and acts to sound names (what `tests/test_sound.gd` checks).
- `view/sound_board.gd`: a node with eight one-shot voices (small random pitch variation), one ambient and one music player, button clicks wired automatically, loops set up at load time. Buses `sfx`, `ambient`, `music`, `ui` are created at runtime.
- `view/sound_settings.gd`: per-bus volumes and a mute switch in `user://sound.json`; ambient sits 14 dB and music 10 dB under the effects.
- The play screen has a **Sound / Muted** button; the main menu has **Sound: on/off**. Combat events, Go, and the end-of-match stingers play in the play screen; the debrief plays the win or loss stinger and the loot sound, and equipping plays a clunk.

## Not done
- Nothing has been listened to by a person yet: levels, balance and taste are untuned. Volume sliders are not in the UI (only mute).
- No per-mission music, no voice, no overwatch-trigger or alert sounds, no distance attenuation or panning, and no tension layer when a merc is hit.
- The start-of-round stinger exists but is not played yet.
