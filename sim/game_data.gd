extends RefCounted
class_name GameData

# Every number the game plays by, read once from data/*.json. Nothing in here
# decides anything; it holds what the files say and complains loudly when one
# is missing. tools/validate_data.gd checks the contents properly — references
# between files, ranges, required keys — so a broken file is a red `verify
# static`, not a null at hour forty.

const DIR: String = "res://data/"

var campaign: Dictionary = {}
var regions: Array = []
var classes: Dictionary = {}
var enemies: Dictionary = {}
var templates: Dictionary = {}
var roster: Array = []
var ranks: Array = []
var battle: Dictionary = {}
var errors: Array[String] = []


static func load_all() -> GameData:
	var d: GameData = GameData.new()
	d.campaign = d.read("campaign")
	d.regions = d.read("regions").get("regions", []) as Array
	d.classes = d.read("classes").get("classes", {}) as Dictionary
	d.enemies = d.read("enemies").get("enemies", {}) as Dictionary
	d.templates = d.read("missions").get("templates", {}) as Dictionary
	d.roster = d.read("roster").get("soldiers", []) as Array
	d.ranks = d.read("ranks").get("ranks", []) as Array
	d.battle = d.read("battle")
	return d


func read(file_name: String) -> Dictionary:
	var path: String = DIR + file_name + ".json"
	if not FileAccess.file_exists(path):
		_fail("data file missing: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		_fail("data file is not a JSON object: %s" % path)
		return {}
	return parsed as Dictionary


func cfg(key: String, fallback: Variant) -> Variant:
	return campaign.get(key, fallback)


func rule(key: String, fallback: Variant) -> Variant:
	return battle.get(key, fallback)


func start() -> Dictionary:
	return campaign.get("start", {}) as Dictionary


func class_def(id: String) -> Dictionary:
	return classes.get(id, {}) as Dictionary


func enemy_def(id: String) -> Dictionary:
	return enemies.get(id, {}) as Dictionary


func enemy_name(id: String) -> String:
	return str(enemy_def(id).get("name", id))


func template(id: String) -> Dictionary:
	return templates.get(id, {}) as Dictionary


func roe_def(id: String) -> Dictionary:
	return (battle.get("roe", {}) as Dictionary).get(id, {}) as Dictionary


func rank_def(index: int) -> Dictionary:
	if ranks.is_empty():
		return {}
	return ranks[clampi(index, 0, ranks.size() - 1)] as Dictionary


func rank_for_xp(xp: int) -> int:
	var r: int = 0
	for i: int in range(ranks.size()):
		if xp >= int((ranks[i] as Dictionary).get("xp", 0)):
			r = i
	return r


func _fail(message: String) -> void:
	errors.append(message)
	push_error(message)
