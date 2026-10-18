extends RefCounted
class_name LogEvent

# Structured, never a formatted string. sim/ says what happened; ui/log_text.gd
# decides how it reads. The comms log is the spine of a game with no tactical
# layer — it is the only place the player can see *why* something happened —
# so every state change the player needs to know about writes one of these.

const NEUTRAL: String = "neutral"
const GOOD: String = "good"
const WARNING: String = "warning"
const CRITICAL: String = "critical"

var type: String = ""
var severity: String = NEUTRAL
var values: Dictionary = {}
# Campaign hour for campaign events; round number for battle events.
var t: int = 0


static func make(type_in: String, severity_in: String, values_in: Dictionary, t_in: int) -> LogEvent:
	var e: LogEvent = LogEvent.new()
	e.type = type_in
	e.severity = severity_in
	e.values = values_in.duplicate(true)
	e.t = t_in
	return e
