extends RefCounted
class_name LogBus

# Append-only stream of LogEvents. Consumers subscribe; none may mutate an
# event. The comms log in ui/ is the first consumer, tools/play.gd and the
# tests read it to find out what happened.

signal event_appended(event: LogEvent)

var events: Array[LogEvent] = []


func append(event: LogEvent) -> void:
	events.append(event)
	event_appended.emit(event)


func count_of_type(type: String) -> int:
	var n: int = 0
	for e: LogEvent in events:
		if e.type == type:
			n += 1
	return n


func has_type(type: String) -> bool:
	return count_of_type(type) > 0


func last_of_type(type: String) -> LogEvent:
	for i: int in range(events.size() - 1, -1, -1):
		if events[i].type == type:
			return events[i]
	return null
