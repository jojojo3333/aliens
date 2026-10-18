extends SceneTree
#
# The data contract: every file in data/ holds what the game expects, and every
# reference between files points at something that exists.
#
#   godot --headless --script res://tools/validate_data.gd
#
# A missing key in a JSON file is a crash at boot, or worse, a silent default at
# hour forty. This turns both into a red `verify static`.

var _errors: Array[String] = []


func _init() -> void:
	var d: GameData = GameData.load_all()
	for e: String in d.errors:
		_err(e)
	_check_campaign(d)
	_check_regions(d)
	_check_classes(d)
	_check_enemies(d)
	_check_templates(d)
	_check_roster(d)
	_check_ranks(d)
	_check_battle(d)
	for e: String in _errors:
		print("ERROR ", e)
	if _errors.is_empty():
		print("data OK: %d regions, %d classes, %d enemy types, %d operation types, %d soldiers" % [
			d.regions.size(), d.classes.size(), d.enemies.size(), d.templates.size(), d.roster.size()])
		quit(0)
	else:
		print("data: %d error(s)" % _errors.size())
		quit(1)


func _check_campaign(d: GameData) -> void:
	var c: Dictionary = d.campaign
	for key: String in ["start", "supplies", "intel", "speeds", "intel_progress_per_rebel_hour",
			"intel_per_rebel_day", "supply_drop_base", "supply_per_rebel", "expiry_warning_hours",
			"spawn_chance_per_day", "squad", "infiltration_cap", "reveal_cost", "boost_cost",
			"boost_amount", "boosts_per_operation", "wound_hours_per_hp", "grave_wound_hours",
			"assessment_runs"]:
		_need(c, key, "campaign.json")
	var start: Dictionary = c.get("start", {}) as Dictionary
	for key: String in ["year", "month", "day", "hour"]:
		_need(start, key, "campaign.json start")
	var speeds: Dictionary = c.get("speeds", {}) as Dictionary
	for key: String in ["scan", "fast"]:
		if float(speeds.get(key, 0.0)) <= 0.0:
			_err("campaign.json speeds.%s must be > 0" % key)
	var sq: Dictionary = c.get("squad", {}) as Dictionary
	var lo: int = int(sq.get("min", 0))
	var hi: int = int(sq.get("max", 0))
	if lo < 1 or hi < lo:
		_err("campaign.json squad min/max are %d/%d" % [lo, hi])
	var factors: Dictionary = sq.get("size_factor", {}) as Dictionary
	for n: int in range(lo, hi + 1):
		if float(factors.get(str(n), 0.0)) <= 0.0:
			_err("campaign.json squad.size_factor has no positive entry for a squad of %d" % n)
	if float(c.get("infiltration_cap", 0.0)) < 1.0:
		_err("campaign.json infiltration_cap must be at least 1.0")
	var f: Dictionary = c.get("first_mission", {}) as Dictionary
	if not f.is_empty():
		if d.template(str(f.get("template", ""))).is_empty():
			_err("campaign.json first_mission.template '%s' is not in missions.json" % f.get("template", ""))
		if not _region_ids(d).has(str(f.get("region", ""))):
			_err("campaign.json first_mission.region '%s' is not in regions.json" % f.get("region", ""))
		for e: Variant in f.get("enemies", []) as Array:
			if d.enemy_def(str(e)).is_empty():
				_err("campaign.json first_mission enemy '%s' is not in enemies.json" % e)


func _check_regions(d: GameData) -> void:
	var ids: Array[String] = _region_ids(d)
	var contacted: int = 0
	for raw: Variant in d.regions:
		var r: Dictionary = raw as Dictionary
		var id: String = str(r.get("id", ""))
		for key: String in ["id", "name", "pos", "neighbors", "contacted", "strength"]:
			_need(r, key, "regions.json %s" % id)
		var pos: Array = r.get("pos", []) as Array
		if pos.size() != 2 or float(pos[0]) < 0.0 or float(pos[0]) > 1.0 \
				or float(pos[1]) < 0.0 or float(pos[1]) > 1.0:
			_err("regions.json %s pos must be two numbers in 0..1" % id)
		for n: Variant in r.get("neighbors", []) as Array:
			if not ids.has(str(n)):
				_err("regions.json %s neighbour '%s' does not exist" % [id, n])
		if bool(r.get("contacted", false)):
			contacted += 1
			if not (r.get("haven", null) is Dictionary):
				_err("regions.json %s is contacted but has no haven" % id)
			else:
				var h: Dictionary = r["haven"] as Dictionary
				for key: String in ["name", "intel", "supply"]:
					_need(h, key, "regions.json %s haven" % id)
	if contacted == 0:
		_err("regions.json: no contacted region, so nothing can ever be detected")


func _check_classes(d: GameData) -> void:
	if d.classes.is_empty():
		_err("classes.json has no classes")
	for id: Variant in d.classes:
		var c: Dictionary = d.classes[id] as Dictionary
		for key: String in ["name", "hp", "aim", "defense", "damage", "pierce", "bonus_vs",
				"spotter", "stealth", "perk"]:
			_need(c, key, "classes.json %s" % id)
		_check_damage(c, "classes.json %s" % id)


func _check_enemies(d: GameData) -> void:
	for id: Variant in d.enemies:
		var e: Dictionary = d.enemies[id] as Dictionary
		for key: String in ["name", "hp", "aim", "defense", "armor", "damage", "tags", "disguised", "brief"]:
			_need(e, key, "enemies.json %s" % id)
		_check_damage(e, "enemies.json %s" % id)


func _check_templates(d: GameData) -> void:
	if d.templates.is_empty():
		_err("missions.json has no operation types")
	for id: Variant in d.templates:
		var t: Dictionary = d.templates[id] as Dictionary
		var where: String = "missions.json %s" % id
		for key: String in ["name", "brief", "weight", "duration_hours", "detection_cost",
				"infiltration_hours", "enemies", "reinforcements", "rewards"]:
			_need(t, key, where)
		_check_range(t.get("duration_hours", []) as Array, where + " duration_hours")
		_check_range(t.get("detection_cost", []) as Array, where + " detection_cost")
		var e: Dictionary = t.get("enemies", {}) as Dictionary
		if (e.get("core", []) as Array).is_empty():
			_err("%s enemies.core is empty; an operation needs at least one hostile" % where)
		for raw: Variant in e.get("core", []) as Array:
			if d.enemy_def(str(raw)).is_empty():
				_err("%s core enemy '%s' is not in enemies.json" % [where, raw])
		for raw: Variant in (e.get("extras", {}) as Dictionary).keys():
			if d.enemy_def(str(raw)).is_empty():
				_err("%s extra enemy '%s' is not in enemies.json" % [where, raw])
		_check_range(e.get("extra_count", []) as Array, where + " enemies.extra_count")
		for raw: Variant in t.get("reinforcements", []) as Array:
			if d.enemy_def(str(raw)).is_empty():
				_err("%s reinforcement '%s' is not in enemies.json" % [where, raw])


func _check_roster(d: GameData) -> void:
	var seen: Dictionary = {}
	var sq: Dictionary = d.cfg("squad", {}) as Dictionary
	if d.roster.size() < int(sq.get("min", 2)):
		_err("roster.json has fewer soldiers than the minimum squad")
	for raw: Variant in d.roster:
		var s: Dictionary = raw as Dictionary
		var id: String = str(s.get("id", ""))
		for key: String in ["id", "first", "last", "class"]:
			_need(s, key, "roster.json %s" % id)
		if seen.has(id):
			_err("roster.json soldier id '%s' is used twice" % id)
		seen[id] = true
		if d.class_def(str(s.get("class", ""))).is_empty():
			_err("roster.json %s has class '%s', which is not in classes.json" % [id, s.get("class", "")])


func _check_ranks(d: GameData) -> void:
	if d.ranks.is_empty():
		_err("ranks.json has no ranks")
		return
	var last: int = -1
	for raw: Variant in d.ranks:
		var r: Dictionary = raw as Dictionary
		for key: String in ["name", "abbr", "xp", "aim", "hp"]:
			_need(r, key, "ranks.json %s" % r.get("name", "?"))
		if int(r.get("xp", 0)) <= last:
			_err("ranks.json xp thresholds must rise strictly")
		last = int(r.get("xp", 0))
	if int((d.ranks[0] as Dictionary).get("xp", 1)) != 0:
		_err("ranks.json: the first rank must start at 0 xp")


func _check_battle(d: GameData) -> void:
	for key: String in ["max_rounds", "hit_min", "hit_max", "crit_chance", "crit_bonus",
			"ambush_aim", "surprise_aim", "overinfiltration_step", "overinfiltration_max_removed",
			"reinforce_step", "reinforce_max", "enemies_first_below", "withdraw_aim_penalty",
			"cautious_hp_loss", "stabilize_chance", "stabilize_bonus_victory", "roe"]:
		_need(d.battle, key, "battle.json")
	for id: String in ["cautious", "standard", "hold"]:
		var r: Dictionary = d.roe_def(id)
		if r.is_empty():
			_err("battle.json roe.%s is missing; the planner offers it and Battle implements it" % id)
		else:
			_need(r, "name", "battle.json roe.%s" % id)
			_need(r, "brief", "battle.json roe.%s" % id)
	if float(d.battle.get("overinfiltration_step", 0.0)) <= 0.0 \
			or float(d.battle.get("reinforce_step", 0.0)) <= 0.0:
		_err("battle.json infiltration steps must be > 0")


func _check_damage(d: Dictionary, where: String) -> void:
	var dmg: Array = d.get("damage", []) as Array
	if dmg.size() != 2 or int(dmg[0]) < 1 or int(dmg[1]) < int(dmg[0]):
		_err("%s damage must be [min, max] with 1 <= min <= max" % where)


func _check_range(pair: Array, where: String) -> void:
	if pair.size() != 2 or int(pair[1]) < int(pair[0]) or int(pair[0]) < 0:
		_err("%s must be [lo, hi] with 0 <= lo <= hi" % where)


func _need(d: Dictionary, key: String, where: String) -> void:
	if not d.has(key):
		_err("%s is missing '%s'" % [where, key])


func _region_ids(d: GameData) -> Array[String]:
	var out: Array[String] = []
	for raw: Variant in d.regions:
		out.append(str((raw as Dictionary).get("id", "")))
	return out


func _err(message: String) -> void:
	_errors.append(message)
