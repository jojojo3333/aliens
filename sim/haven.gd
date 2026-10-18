extends RefCounted
class_name Haven

# A resistance cell in a contacted region. Its rebels work one of two jobs, and
# the split is the first decision the desk asks for:
#
#   intel  — finds the machines' operations before they finish, and earns the
#            intel that buys reveals and boosts.
#   supply — pays out once a month, at the supply drop.
#
# Finding operations now against money later is the trade Long War's haven
# screen is built on. Hiding, recruiting and the Mimic infiltration of havens
# are not in v0.1; see BACKLOG.md.

var label: String = ""
var region_id: String = ""
var on_intel: int = 0
var on_supply: int = 0


static func from_data(d: Dictionary, region: String) -> Haven:
	var h: Haven = Haven.new()
	h.label = str(d.get("name", "Haven"))
	h.region_id = region
	h.on_intel = int(d.get("intel", 0))
	h.on_supply = int(d.get("supply", 0))
	return h


func rebels() -> int:
	return on_intel + on_supply


# Moves one rebel onto `job` from the other one. False when nobody is left to move.
func move_to(job: String) -> bool:
	if job == "intel" and on_supply > 0:
		on_supply -= 1
		on_intel += 1
		return true
	if job == "supply" and on_intel > 0:
		on_intel -= 1
		on_supply += 1
		return true
	return false
