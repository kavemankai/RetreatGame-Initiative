class_name CombatState
extends RefCounted
## The single authoritative state of an activation-based encounter: the board (SimState),
## the round and its initiative queue, who is active, every unit's AP and status, the AP
## ledger and the event log. It is changed only by ActivationScheduler and ActionResolver,
## never by a view or by the passing of real time.

enum Phase { SETUP, AWAIT_COMMAND, ENDED }

const NO_WINNER := SimMatch.NO_WINNER
const DRAW := SimMatch.DRAW
## Salt for the seeded initiative tie-break die, so it never shares a roll with the others.
const TIE_DIE_OFFSET := 2000

var sim: SimState
var config: CombatConfig
var player_team := 0
var ai_team := 1
var profiles: Dictionary = {}
var assignments: Dictionary = {}
var objective := SimMatch.AI_OBJECTIVE
var goal: SimGoal
var reinforcements: Array[Dictionary] = []
var theme := "station_deck"

var phase := Phase.SETUP
var round_no := 0
var active_id := -1
var winner := NO_WINNER
## This round's initiative snapshot, [{id, initiative, tie}], best first (fixed for the round).
var order: Array[Dictionary] = []
## Ids still to activate this round, in order (the active unit is not in it).
var queue: Array[int] = []
var activations: Dictionary = {}  # id -> activations this round (never above 1)
var ap: Dictionary = {}           # id -> AP left (zero for everyone but the active unit)
var overwatch: Dictionary = {}    # id -> facing, from arming until the owner's next activation
var suppressed: Dictionary = {}   # steady after a hit: cannot shoot until its next activation
var broken: Dictionary = {}       # broken after a hit: no AP until its next activation
var fired: Dictionary = {}        # id -> true once it has shot this activation (opener trait)
var ledger: Array[Dictionary] = []  # one row per accepted action: AP before, cost, AP after
var log: Array[Dictionary] = []     # every event, in order
var notices: Array[String] = []
var clock := 0


static func create(p_sim: SimState, p_config: CombatConfig = null) -> CombatState:
	var cs := CombatState.new()
	cs.sim = p_sim
	cs.config = p_config if p_config != null else CombatConfig.load_file()
	return cs


## The same mission as a planned-mode SimMatch: its units, goal, reinforcements and roles.
static func from_match(m: SimMatch, p_config: CombatConfig = null) -> CombatState:
	var cs := create(m.state.clone(), p_config)
	cs.profiles = m.profiles
	cs.assignments = m.assignments
	cs.objective = m.objective
	cs.goal = m.goal
	cs.theme = m.theme
	cs.reinforcements = m.reinforcements.duplicate()
	return cs


func is_over() -> bool:
	return phase == Phase.ENDED


func ap_of(id: int) -> int:
	return int(ap.get(id, 0))


func next_tick() -> int:
	clock += 1
	return clock


func record(events: Array) -> void:
	for e: Dictionary in events:
		log.append(e)


## The side that has won, DRAW if nobody is left, NO_WINNER while both sides stand.
static func winner_for(state: SimState, goal_: SimGoal, player: int, ai: int) -> int:
	if goal_ != null and goal_.won:
		return player
	var mine := 0
	var theirs := 0
	for id in state.units:
		var u: SimUnit = state.units[id]
		if u.alive:
			if u.team == player:
				mine += 1
			else:
				theirs += 1
	if mine > 0 and theirs > 0:
		return NO_WINNER
	if mine > 0:
		return player
	if theirs > 0:
		return ai
	return DRAW
