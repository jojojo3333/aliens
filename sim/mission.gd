extends RefCounted
class_name Mission

# One Custodian operation, from the moment the machines start it to the moment
# it is fought, missed or left to expire.
#
# The life of a mission is the whole of v0.1:
#
#   HIDDEN        the machines are doing something; nobody knows yet. The
#                 haven's intel rebels accumulate detection progress against it.
#   DETECTED      on the operations board, with a window that is already
#                 closing. The player plans it, or lets it go.
#   INFILTRATING  a squad is moving in. Infiltration climbs toward 100% and on
#                 to the cap; the player launches whenever they judge it right,
#                 and the window closing launches it for them.
#   RESOLVED      fought. `outcome` says how it went.
#   EXPIRED       the window closed with no squad on it — detected or not.

enum State { HIDDEN, DETECTED, INFILTRATING, RESOLVED, EXPIRED }

const STATE_NAMES: Array[String] = ["HIDDEN", "DETECTED", "INFILTRATING", "RESOLVED", "EXPIRED"]

var id: int = 0
var template_id: String = ""
var label: String = ""
var region_id: String = ""
var created_at: int = 0
var expires_at: int = 0
var detection_cost: float = 1.0
var detection_progress: float = 0.0
var state: State = State.HIDDEN
# True once intel has been spent to confirm the composition.
var revealed: bool = false
# Enemy type ids, fixed when the machines start the operation. Core units come
# first and extras after, so over-infiltration removes extras before the core.
var enemies: Array[String] = []
var squad: Array[String] = []
var roe: String = "standard"
var infil_start: int = -1
# Hours from dispatch to 100%. Fixed at dispatch.
var infil_hours: float = 0.0
var boost: float = 0.0
var boosts_used: int = 0
var warned: bool = false
var full_announced: bool = false
var rewards: Dictionary = {}
var outcome: String = ""


func is_open() -> bool:
	return state == State.HIDDEN or state == State.DETECTED or state == State.INFILTRATING


func is_visible() -> bool:
	return state == State.DETECTED or state == State.INFILTRATING


func infiltration_at(hour: int, cap: float) -> float:
	if state != State.INFILTRATING or infil_hours <= 0.0:
		return 0.0
	return clampf(float(hour - infil_start) / infil_hours + boost, 0.0, cap)


func hours_left(hour: int) -> int:
	return maxi(expires_at - hour, 0)
