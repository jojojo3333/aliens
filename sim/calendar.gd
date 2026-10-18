extends RefCounted
class_name Calendar

# Campaign time is a single integer — hours since the campaign began — and this
# is the only place that turns it into a date. 2047 is not a leap year and no
# campaign is long enough yet to reach one, so February has 28 days.

const MONTHS: Array[String] = [
	"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
]
const DAYS_IN: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]


static func date_of(start: Dictionary, hours: int) -> Dictionary:
	var year: int = int(start.get("year", 2047))
	var month: int = int(start.get("month", 1))
	var day: int = int(start.get("day", 1))
	var total: int = int(start.get("hour", 0)) + maxi(hours, 0)
	var hour: int = total % 24
	@warning_ignore("integer_division")
	day += total / 24
	while day > DAYS_IN[month - 1]:
		day -= DAYS_IN[month - 1]
		month += 1
		if month > 12:
			month = 1
			year += 1
	return {"year": year, "month": month, "day": day, "hour": hour}


# "Mar 03, 14:00"
static func stamp(start: Dictionary, hours: int) -> String:
	var d: Dictionary = date_of(start, hours)
	return "%s %02d, %02d:00" % [MONTHS[int(d["month"]) - 1], int(d["day"]), int(d["hour"])]


# "MAR 03 2047  14:00"
static func long_stamp(start: Dictionary, hours: int) -> String:
	var d: Dictionary = date_of(start, hours)
	return "%s %02d %d  %02d:00" % [
		MONTHS[int(d["month"]) - 1].to_upper(), int(d["day"]), int(d["year"]), int(d["hour"])
	]


# "Apr 01"
static func day_stamp(d: Dictionary) -> String:
	return "%s %02d" % [MONTHS[int(d["month"]) - 1], int(d["day"])]


# A duration the way the desk shows it: "9h", "47h", "3d 04h".
static func span(hours: int) -> String:
	var h: int = maxi(hours, 0)
	if h < 48:
		return "%dh" % h
	@warning_ignore("integer_division")
	return "%dd %02dh" % [h / 24, h % 24]


# The first day of the month after the given hour — when the supply drop lands.
static func next_month_start(start: Dictionary, hours: int) -> Dictionary:
	var d: Dictionary = date_of(start, hours)
	var month: int = int(d["month"]) + 1
	var year: int = int(d["year"])
	if month > 12:
		month = 1
		year += 1
	return {"year": year, "month": month, "day": 1, "hour": 0}
