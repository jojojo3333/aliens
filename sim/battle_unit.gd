extends RefCounted
class_name BattleUnit

# A combatant for the length of one autoresolve. Built from a Soldier or an
# enemy definition, thrown away afterwards; the campaign reads the results off
# BattleResult and never off these.

const SQUAD: int = 0
const HOSTILE: int = 1

var key: String = ""        # soldier id, or "<type>#<n>" for a hostile
var type_id: String = ""    # class id or enemy type id
var label: String = ""      # "Cpl. Okafor", "Warden B"
var side: int = SQUAD
var max_hp: int = 1
var hp: int = 1
var aim: int = 60
var defense: int = 0
var armor: int = 0
var dmg_min: int = 1
var dmg_max: int = 2
var pierce: int = 0
var bonus_vs: Dictionary = {}
var tags: Array[String] = []
var spotter: bool = false
var disguised: bool = false
var hidden: bool = false
var down: bool = false
var kills: int = 0
var shots: int = 0
var hits: int = 0
var damage_dealt: int = 0


static func from_soldier(s: Soldier, data: GameData) -> BattleUnit:
	var st: Dictionary = s.stats(data)
	var u: BattleUnit = BattleUnit.new()
	u.key = s.id
	u.type_id = s.class_id
	u.label = s.title(data)
	u.side = SQUAD
	u.max_hp = int(st["hp"])
	u.hp = u.max_hp
	u.aim = int(st["aim"])
	u.defense = int(st["defense"])
	u.armor = int(st["armor"])
	u.dmg_min = int(st["dmg_min"])
	u.dmg_max = int(st["dmg_max"])
	u.pierce = int(st["pierce"])
	u.bonus_vs = st["bonus_vs"] as Dictionary
	u.spotter = bool(st["spotter"])
	return u


static func from_enemy(type_id_in: String, key_in: String, label_in: String, data: GameData) -> BattleUnit:
	var d: Dictionary = data.enemy_def(type_id_in)
	var dmg: Array = d.get("damage", [2, 3]) as Array
	var u: BattleUnit = BattleUnit.new()
	u.key = key_in
	u.type_id = type_id_in
	u.label = label_in
	u.side = HOSTILE
	u.max_hp = int(d.get("hp", 4))
	u.hp = u.max_hp
	u.aim = int(d.get("aim", 60))
	u.defense = int(d.get("defense", 0))
	u.armor = int(d.get("armor", 0))
	u.dmg_min = int(dmg[0])
	u.dmg_max = int(dmg[1])
	for t: Variant in d.get("tags", []) as Array:
		u.tags.append(str(t))
	u.disguised = bool(d.get("disguised", false))
	return u


func active() -> bool:
	return not down


func hp_lost() -> int:
	return max_hp - maxi(hp, 0)


func bonus_against(target: BattleUnit) -> int:
	var b: int = 0
	for tag: String in target.tags:
		b += int(bonus_vs.get(tag, 0))
	return b
