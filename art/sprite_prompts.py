"""Prompt builders for character sheets (generated on flat magenta so they can
be keyed out locally for free). Usage: python art/sprite_prompts.py <key>"""
import json
import sys

COMMON = ("Pixel art, designed at 32x48 pixels per figure, shown upscaled 8x with big square pixels, "
          "flat solid pure magenta #ff00ff background everywhere, no ground shadow, no text, no border. "
          "Isometric 2:1 dimetric game view. Muted desaturated palette, hushed, melancholic.")

FACINGS = ("{common} A character turnaround sheet: ONE character drawn four times in a 2x2 grid, standing idle, each figure facing a "
           "different diagonal: top-left cell faces down-right (toward the camera, its right side), top-right cell faces down-left "
           "(toward the camera, its left side), bottom-left cell faces up-right (back turned), bottom-right cell faces up-left (back turned). "
           "Character: {desc} Same character and proportions in all four cells.")
ACTIONS = ("{common} An animation sprite sheet: a 3x3 grid of nine frames of ONE character facing down-right. Frames in reading order: "
           "1 idle, 2 idle breathing (slight shift), 3 walk step left foot, 4 walk step right foot, 5 aiming the weapon, "
           "6 firing with a small amber muzzle flash, 7 hit reaction recoiling, 8 collapsing, 9 lying dead on the ground. "
           "Character: {desc} Same character and proportions in every frame, feet on the same baseline in each cell.")
RUN = ("{common} An animation sprite sheet: a 3x2 grid (3 columns, 2 rows) of six frames forming one smooth looping RUN CYCLE of ONE "
       "character facing down-right, sprinting forward with the weapon held across the body: 1 contact (front foot landing), 2 down, "
       "3 passing, 4 contact on the other foot, 5 down, 6 passing. Clothing and pack swing with the motion, body leans forward. "
       "Character: {desc} Same character and proportions in every frame, feet on the same baseline in each cell.")


def prompts(desc: str) -> dict:
    return {kind: tpl.format(common=COMMON, desc=desc) for kind, tpl in
            (("faces", FACINGS), ("actions", ACTIONS), ("run", RUN))}


if __name__ == "__main__":
    data = json.load(open(__file__.replace("sprite_prompts.py", "sprite_roster.json"), encoding="utf-8"))
    print(json.dumps(prompts(data[sys.argv[1]]["desc"]), indent=1))
