extends RefCounted
class_name Soldier

# One person on the roster. Stats are not stored here: they are the class's
# numbers plus the rank's bonus, worked out when asked, so a balance change in
# data/classes.json reaches every soldier already recruited.

enum Status { READY, INFILTRATING, WOUNDED, KIA }

const STATUS_NAMES: Array[String] = ["Ready", "Deployed", "Wounded", "KIA"]

var id: String = ""
var first_name: String = ""
var last_name: String = ""
var class_id: String = ""
var xp: int = 0
var rank: int = 0
var status: Status = Status.READY
# The campaign hour a wound heals; -1 when not wounded.
var recover_at: int = -1
# The operation this soldier is committed to; -1 when not deployed.
var mission_id: int = -1
var kills: int = 0
var missions: int = 0


static func from_data(d: Dictionary, data: GameData) -> Soldier:
	var s: Soldier = Soldier.new()
	s.id = str(d.get("id", ""))
	s.first_name = str(d.get("first", ""))
	s.last_name = str(d.get("last", ""))
	s.class_id = str(d.get("class", ""))
	s.xp = int(d.get("xp", 0))
	s.rank = data.rank_for_xp(s.xp)
	return s


func stats(data: GameData) -> Dictionary:
	var c: Dictionary = data.class_def(class_id)
	var r: Dictionary = data.rank_def(rank)
	var dmg: Array = c.get("damage", [3, 4]) as Array
	return {
		"hp": int(c.get("hp", 5)) + int(r.get("hp", 0)),
		"aim": int(c.get("aim", 65)) + int(r.get("aim", 0)),
		"defense": int(c.get("defense", 0)),
		"armor": int(c.get("armor", 0)),
		"dmg_min": int(dmg[0]),
		"dmg_max": int(dmg[1]),
		"pierce": int(c.get("pierce", 0)),
		"bonus_vs": c.get("bonus_vs", {}) as Dictionary,
		"spotter": bool(c.get("spotter", false)),
		"stealth": float(c.get("stealth", 0.0)),
	}


func class_name_text(data: GameData) -> String:
	return str(data.class_def(class_id).get("name", class_id))


# "Cpl. Okafor"
func title(data: GameData) -> String:
	return "%s %s" % [str(data.rank_def(rank).get("abbr", "")), last_name]


# "Cpl. Ada Okafor"
func full_name(data: GameData) -> String:
	return "%s %s %s" % [str(data.rank_def(rank).get("abbr", "")), first_name, last_name]


func is_ready() -> bool:
	return status == Status.READY
