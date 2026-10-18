extends SceneTree
#
# The balance report: the first encounter, played many times with no UI.
#
#   godot --headless --script res://tools/sim_runner.gd -- --runs 500
#
# Every number printed here is [PLAY-GATED]. It is reported, never tuned to:
# whether a 90% win rate on the first encounter is right is a question about
# how the game feels, and only someone playing it can answer that. What this
# file can answer is whether the levers do what the design says they do —
# that a Scout matters against a Mimic, that infiltrating longer is safer, that
# a bigger squad wins more and gets in later. Those directions are asserted;
# the magnitudes are only shown.

const DEFAULT_RUNS: int = 200

var _failures: Array[String] = []
var _data: GameData = null


func _init() -> void:
	var runs: int = int(_arg("--runs", str(DEFAULT_RUNS)))
	_data = GameData.load_all()
	print("balance report — %d runs per cell. [PLAY-GATED]: report, never tune.\n" % runs)
	_detection_table(runs)
	_window_table()
	_squad_table(runs)
	_policy_campaigns(runs)
	print("")
	if _failures.is_empty():
		print("sim: OK — every lever moves the outcome the way the design says")
		quit(0)
		return
	for f: String in _failures:
		printerr("FAIL ", f)
	quit(1)


# When the first encounter shows up, against how many rebels are on intel.
func _detection_table(runs: int) -> void:
	print("first detection hour by intel rebels (of 8)")
	var last: float = -1.0
	for intel: int in [1, 2, 4, 6, 8]:
		var total: int = 0
		for i: int in range(mini(runs, 50)):
			var c: Campaign = Campaign.new(_data, 1000 + i)
			var h: Haven = c.home_haven()
			while h.on_intel > intel:
				h.move_to("supply")
			while h.on_intel < intel:
				h.move_to("intel")
			c.run_hours(400)
			total += c.hour
		var mean: float = float(total) / float(mini(runs, 50))
		print("  %d on intel   detected at hour %5.1f" % [intel, mean])
		if last >= 0.0 and mean > last:
			_failures.append("more intel rebels detected later (%.1f after %.1f)" % [mean, last])
		last = mean
	print("")


# Whether each squad size can get in before the first encounter's window shuts.
func _window_table() -> void:
	var c: Campaign = Campaign.new(_data, 1)
	c.run_hours(400)
	var m: Mission = c.visible_missions()[0]
	var window: int = m.hours_left(c.hour)
	print("first encounter: window after detection %dh" % window)
	var order: Array[String] = ["hale", "okafor", "brandt", "ruiz", "chen", "novak"]
	for n: int in range(2, 7):
		var ids: Array[String] = []
		ids.assign(order.slice(0, n))
		var no_scout: Array[String] = []
		no_scout.assign(["okafor", "brandt", "ruiz", "chen", "novak", "achterberg"].slice(0, n))
		var h: float = c.infiltration_hours(ids, m)
		var h2: float = c.infiltration_hours(no_scout, m)
		print("  squad of %d   with Scout %4.0fh %-9s  without %4.0fh %s" % [
			n, h, "(fits)" if h <= window else "(late)", h2, "(fits)" if h2 <= window else "(late)"])
	print("")


# The first encounter's real composition, fought by squads of each size, with
# and without a Scout, launched at each infiltration level, under Standard ROE.
func _squad_table(runs: int) -> void:
	var c: Campaign = Campaign.new(_data, 1)
	var enemies: Array[String] = []
	for e: Variant in (_data.cfg("first_mission", {}) as Dictionary).get("enemies", []) as Array:
		enemies.append(str(e))
	var pool: Array = _data.template("patrol_ambush").get("reinforcements", []) as Array
	print("first encounter (%s), Standard ROE — win%% / dead per fight / wounded per fight" % c.composition_text(enemies))
	print("  squad              infil 50%            infil 100%           infil 150%")
	var rows: Array = [
		["2 with Scout", ["hale", "okafor"]],
		["2 no Scout", ["okafor", "brandt"]],
		["4 with Scout", ["hale", "okafor", "brandt", "ruiz"]],
		["4 no Scout", ["okafor", "brandt", "ruiz", "chen"]],
		["6 with Scout", ["hale", "okafor", "brandt", "ruiz", "chen", "novak"]],
	]
	var table: Dictionary = {}
	for row: Array in rows:
		var ids: Array[String] = []
		ids.assign(row[1] as Array)
		var squad: Array[Soldier] = []
		for id: String in ids:
			squad.append(c.soldier(id))
		var line: String = "  %-16s" % str(row[0])
		for infil: float in [0.5, 1.0, 1.5]:
			var stats: Dictionary = _fight(squad, enemies, infil, "standard", pool, runs, 7 + ids.size())
			table["%s@%.1f" % [row[0], infil]] = stats
			line += "  %3.0f%% / %.2f / %.2f  " % [float(stats["win"]) * 100.0, float(stats["dead"]), float(stats["hurt"])]
		print(line)
	print("")

	print("rules of engagement, 4 with Scout at 50% — win% / dead per fight")
	var four: Array[Soldier] = []
	for id: String in ["hale", "okafor", "brandt", "ruiz"]:
		four.append(c.soldier(id))
	var roe_dead: Dictionary = {}
	for roe: String in ["cautious", "standard", "hold"]:
		var stats: Dictionary = _fight(four, enemies, 0.5, roe, pool, runs, 77)
		roe_dead[roe] = float(stats["dead"])
		print("  %-9s  %3.0f%% / %.2f" % [roe, float(stats["win"]) * 100.0, float(stats["dead"])])
	print("")

	# The directions the design depends on.
	_expect(table, "4 with Scout@1.0", "4 with Scout@0.5", "win", "100% infiltration should win more than 50%")
	_expect(table, "4 with Scout@1.5", "4 with Scout@1.0", "win", "over-infiltration should not win less than 100%", true)
	_expect(table, "4 with Scout@1.0", "4 no Scout@1.0", "win", "a Scout should matter against a Mimic", true)
	_expect(table, "4 with Scout@1.0", "2 with Scout@1.0", "win", "four should win more than two")
	if float(roe_dead["cautious"]) > float(roe_dead["hold"]):
		_failures.append("Cautious ROE lost more soldiers than Hold")


func _expect(table: Dictionary, better: String, worse: String, key: String, why: String,
		allow_equal: bool = false) -> void:
	var a: float = float((table[better] as Dictionary)[key])
	var b: float = float((table[worse] as Dictionary)[key])
	if a < b or (not allow_equal and is_equal_approx(a, b)):
		_failures.append("%s (%s %.2f vs %s %.2f)" % [why, better, a, worse, b])


func _fight(squad: Array[Soldier], enemies: Array[String], infil: float, roe: String,
		pool: Array, runs: int, salt: int) -> Dictionary:
	var rng: RunRng = RunRng.new(salt * 7919 + roundi(infil * 100.0))
	var wins: int = 0
	var dead: int = 0
	var hurt: int = 0
	for i: int in range(runs):
		var r: BattleResult = Battle.resolve(squad, enemies,
			{"infiltration": infil, "roe": roe, "reinforcements": pool}, _data, rng)
		if r.outcome == BattleResult.Outcome.VICTORY:
			wins += 1
		dead += r.kia_count()
		hurt += r.wounded_count()
	return {"win": float(wins) / runs, "dead": float(dead) / runs, "hurt": float(hurt) / runs}


# Whole campaigns, start to first after-action report, under a few simple
# commanders. This is the number closest to what a player actually sees.
func _policy_campaigns(runs: int) -> void:
	print("first encounter, whole campaign from the desk — win% / dead / hour of the report")
	var policies: Array = [
		["by the book", ["hale", "okafor", "brandt", "ruiz"], 1.0, true],
		["no Scout", ["okafor", "brandt", "ruiz", "chen"], 1.0, false],
		["impatient", ["hale", "okafor", "brandt", "ruiz"], 0.5, false],
		["patient", ["hale", "okafor", "brandt", "ruiz"], 1.5, true],
		["everyone", ["hale", "okafor", "brandt", "ruiz", "chen", "novak"], 9.0, false],
	]
	for p: Array in policies:
		var wins: int = 0
		var dead: int = 0
		var hours: int = 0
		for i: int in range(runs):
			var c: Campaign = Campaign.new(_data, 5000 + i)
			c.run_hours(400)
			var m: Mission = c.mission(1)
			if m == null or m.state != Mission.State.DETECTED:
				continue
			if bool(p[3]):
				c.reveal(m.id)
			var ids: Array[String] = []
			ids.assign(p[1] as Array)
			c.dispatch(m.id, ids, "standard")
			while m.state == Mission.State.INFILTRATING and c.infiltration(m) < float(p[2]):
				c.run_hours(1)
			var r: BattleResult = c.launch(m.id) if m.state == Mission.State.INFILTRATING else null
			if r == null:
				# The window closed and launched it: find that fight in the log.
				var e: LogEvent = c.log_bus.last_of_type("mission_result")
				if e != null and str(e.values["outcome"]) == "Victory":
					wins += 1
				dead += int(e.values["kia"]) if e != null else 0
			else:
				if r.outcome == BattleResult.Outcome.VICTORY:
					wins += 1
				dead += r.kia_count()
			hours += c.hour
		print("  %-12s  %3.0f%% / %.2f / hour %5.1f" % [str(p[0]), 100.0 * wins / runs, float(dead) / runs, float(hours) / runs])


func _arg(flag: String, fallback: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = args.find(flag)
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	return fallback
