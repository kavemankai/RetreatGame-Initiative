class_name SimConst
extends RefCounted
## Tunable rule constants. Integers only.

const TICKS_PER_TURN := 20
## Action points a merc has per turn in the initiative ruleset (the planned mode keeps TICKS_PER_TURN).
const AP_PER_TURN := 14
## Hit chance in percent: HIT_BASE + HIT_PER_AIM * aim, minus HIT_RANGE_PENALTY
## per tile beyond HIT_FREE_RANGE, plus gear accuracy, clamped to HIT_MIN..HIT_MAX.
const HIT_BASE := 35
const HIT_PER_AIM := 7
const HIT_FREE_RANGE := 2
const HIT_RANGE_PENALTY := 4
const HIT_MIN := 10
const HIT_MAX := 95
## Hit rolls use dice index HIT_DIE_OFFSET + shots fired, so they never share a roll with morale.
const HIT_DIE_OFFSET := 1000
## Gear traits.
const BRACING_HIT_BONUS := 5
const BRACING_MORALE_BONUS := 1  # on top of MORALE_COVER_BONUS
const OPENER_HIT_BONUS := 15
const SCOPE_SIGHT := 2
const SCOPE_RANGE := 1
## A hit unit rolls this die and must score at or under morale minus wounds.
const MORALE_DIE := 10
## Added to a unit's morale before the check, so a base unit (morale 5) passes
## its first hit on 7 or less: 70% steady, 30% broken.
const MORALE_BONUS := 3
## Standing beside a low wall, wall or crate adds this to the check.
const MORALE_COVER_BONUS := 1
## Default sight radius in tiles (Chebyshev). Per-unit via SimUnit.sight_range.
const SIGHT_RANGE := 8
const COST_ORTHO := 2
const COST_DIAG := 3

const EDGE_NONE := 0
const EDGE_HALF := 1
const EDGE_FULL := 2

const ACTION_MOVE := "move"
const ACTION_SHOOT := "shoot"
const ACTION_WAIT := "wait"
const ACTION_OVERWATCH := "overwatch"
const ACTION_MOVE_FIRE := "move_fire"
## Move and Fire walks a whole path and fires once if a shot comes up. It
## reserves a shot's worth of ticks (the shot times this factor) up front, so
## the price is paid whether or not anything is ever fired at.
const MOVE_FIRE_SHOT_FACTOR := 2

## Aim at or above this shaves one tick off a shot.
const AIM_FAST_SHOT := 8
const MIN_SHOT_TICKS := 2
## Weapon traits (see items.json): a burst fires this many shots in one action, each this many
## percentage points less likely to hit; an area weapon cannot be fired at a target closer than
## AREA_MIN_RANGE tiles (its blast covers the target tile and the eight around it).
const BURST_COUNT := 3
const BURST_ACCURACY_PENALTY := 15
const AREA_MIN_RANGE := 2
## Aim adds (aim / AIM_RANGE_DIVISOR) tiles of range.
const AIM_RANGE_DIVISOR := 3
## CQB at or above this adds close-range damage.
const CQB_BONUS_MIN := 6
const CQB_BONUS_DISTANCE := 2
