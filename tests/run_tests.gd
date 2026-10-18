extends SceneTree
#
# The simulation, tested with no UI attached.
#
#   godot --headless --script res://tests/run_tests.gd
#
# Every test here was run against a deliberately broken sim/ before it was kept
# (CLAUDE.md, "mutation testing"). A test that cannot fail is decoration.

const TESTS: Array[String] = [
	"test_calendar",
	"test_determinism",
	"test_detection_scales_with_intel",
	"test_infiltration_hours",
	"test_dispatch_validation",
	"test_battle_invariants",
	"test_roe_hold_never_retreats",
	"test_roe_cautious_pulls_out",
	"test_infiltration_changes_the_opposition",
	"test_scout_spots_mimic",
	"test_undetected_operation_is_missed",
	"test_ignored_operation_expires",
	"test_window_launches_a_late_squad",
	"test_reveal_and_boost_cost_intel",
	"test_supply_drop",
	"test_wounds_heal",
	"test_assess_leaves_the_dice_alone",
	"test_promotion",
]

var _data: GameData = null
var _failures: Array[String] = []
var _checks: int = 0
var _current: String = ""


func _init() -> void:
	_data = GameData.load_all()
	for t: String in TESTS:
		_current = t
		call(t)
	if _failures.is_empty():
		print("tests: OK (%d tests, %d checks)" % [TESTS.size(), _checks])
		quit(0)
		return
	for f: String in _failures:
		printerr("FAIL ", f)
	printerr("tests: %d of %d checks failed" % [_failures.size(), _checks])
	quit(1)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures.append("%s: %s" % [_current, what])


func _campaign(seed_in: int = 1234) -> Campaign:
	return Campaign.new(_data, seed_in)


func _ids(list: Array) -> Array[String]:
	var out: Array[String] = []
	for x: Variant in list:
		out.append(str(x))
	return out


func _squad(c: Campaign, ids: Array[String]) -> Array[Soldier]:
	var out: Array[Soldier] = []
	for id: String in ids:
		out.append(c.soldier(id))
	return out


func _first(c: Campaign) -> Mission:
	return c.missions[0]


# --- tests ------------------------------------------------------------------

func test_calendar() -> void:
	var start: Dictionary = _data.start()
	_check(Calendar.stamp(start, 0) == "Mar 01, 06:00", "hour 0 is %s" % Calendar.stamp(start, 0))
	_check(Calendar.stamp(start, 18) == "Mar 02, 00:00", "hour 18 is %s" % Calendar.stamp(start, 18))
	_check(Calendar.stamp(start, 738) == "Apr 01, 00:00", "hour 738 is %s" % Calendar.stamp(start, 738))
	_check(Calendar.span(47) == "47h", "span 47 is %s" % Calendar.span(47))
	_check(Calendar.span(50) == "2d 02h", "span 50 is %s" % Calendar.span(50))


func test_determinism() -> void:
	var a: Array = _scripted_run(777)
	var b: Array = _scripted_run(777)
	_check(a == b, "two runs of seed 777 diverged")
	var c: Array = _scripted_run(778)
	_check(a != c, "seeds 777 and 778 produced identical campaigns; the seed is not reaching the dice")


func _scripted_run(seed_in: int) -> Array:
	var c: Campaign = _campaign(seed_in)
	c.run_hours(200)
	var m: Mission = c.visible_missions()[0]
	c.dispatch(m.id, _ids(["hale", "okafor", "brandt", "ruiz"]), "standard")
	while m.state == Mission.State.INFILTRATING and c.infiltration(m) < 1.3:
		c.run_hours(1)
	c.launch(m.id)
	c.run_hours(300)
	var out: Array = []
	for e: LogEvent in c.log_bus.events:
		out.append([e.type, e.t, e.values])
	for s: Soldier in c.soldiers:
		out.append([s.id, s.status, s.xp, s.recover_at])
	return out


func test_detection_scales_with_intel() -> void:
	var c: Campaign = _campaign()
	var reason: String = c.run_hours(200)
	_check(reason == "mission_detected", "first interrupt was '%s'" % reason)
	# 4 intel rebels at 1.0/h against a pinned cost of 60.
	_check(c.hour == 15, "default haven detected the first operation at hour %d, expected 15" % c.hour)
	var fast: Campaign = _campaign()
	for i: int in range(4):
		fast.reassign("rhine", "intel")
	fast.run_hours(200)
	_check(fast.hour < c.hour, "8 intel rebels detected at hour %d, no sooner than 4 (%d)" % [fast.hour, c.hour])
	var slow: Campaign = _campaign()
	for i: int in range(3):
		slow.reassign("rhine", "supply")
	slow.run_hours(200)
	_check(slow.hour > c.hour, "1 intel rebel detected at hour %d, no later than 4 (%d)" % [slow.hour, c.hour])


func test_infiltration_hours() -> void:
	var c: Campaign = _campaign()
	var m: Mission = _first(c)
	var four: float = c.infiltration_hours(_ids(["okafor", "brandt", "ruiz", "chen"]), m)
	_check(is_equal_approx(four, 40.0), "4 without a Scout takes %.1fh, expected 40" % four)
	var scout: float = c.infiltration_hours(_ids(["okafor", "brandt", "ruiz", "hale"]), m)
	_check(is_equal_approx(scout, 34.0), "4 with a Scout takes %.1fh, expected 34" % scout)
	var two: float = c.infiltration_hours(_ids(["okafor", "brandt"]), m)
	var six: float = c.infiltration_hours(_ids(["okafor", "brandt", "ruiz", "chen", "novak", "achterberg"]), m)
	_check(two < four and four < six, "squad size does not order infiltration: %.1f / %.1f / %.1f" % [two, four, six])
	var capped: float = c.infiltration_hours(_ids(["hale", "sato", "okafor", "brandt"]), m)
	_check(is_equal_approx(capped, 40.0 * 0.7), "two Scouts give %.1fh; stealth should cap at 30%%" % capped)


func test_dispatch_validation() -> void:
	var c: Campaign = _campaign()
	c.run_hours(200)
	var m: Mission = c.visible_missions()[0]
	_check(c.dispatch(m.id, _ids(["okafor"]), "standard") != "", "a squad of one was accepted")
	_check(c.dispatch(m.id, _ids(["okafor", "brandt", "hale", "ruiz", "chen", "novak", "sato"]), "standard") != "",
		"a squad of seven was accepted")
	_check(c.dispatch(m.id, _ids(["okafor", "brandt"]), "berserk") != "", "an unknown ROE was accepted")
	c.soldier("chen").status = Soldier.Status.WOUNDED
	_check(c.dispatch(m.id, _ids(["okafor", "chen"]), "standard") != "", "a wounded soldier was sent")
	c.soldier("chen").status = Soldier.Status.READY
	_check(c.dispatch(m.id, _ids(["okafor", "brandt"]), "hold") == "", "a valid squad was refused")
	_check(m.state == Mission.State.INFILTRATING, "dispatch did not start infiltration")
	_check(c.soldier("okafor").status == Soldier.Status.INFILTRATING, "dispatched soldier not marked deployed")
	_check(m.roe == "hold", "ROE not recorded")
	_check(c.dispatch(m.id, _ids(["ruiz", "chen"]), "standard") != "", "a second squad was sent to the same operation")


func test_battle_invariants() -> void:
	var c: Campaign = _campaign()
	var rng: RunRng = RunRng.new(99)
	var pool: Array[String] = _ids(["okafor", "brandt", "hale", "ruiz", "chen", "novak", "sato", "achterberg"])
	var enemy_pool: Array = ["warden", "sentry_drone", "mimic"]
	var outcomes: Dictionary = {}
	for i: int in range(400):
		var n: int = rng.randi_range(2, 6)
		var ids: Array[String] = []
		for id: String in pool:
			if ids.size() < n and rng.chance(0.7):
				ids.append(id)
		if ids.size() < 2:
			ids = _ids(["okafor", "brandt"])
		var enemies: Array[String] = []
		for k: int in range(rng.randi_range(1, 6)):
			enemies.append(str(rng.pick(enemy_pool)))
		var roe: String = str(rng.pick(["cautious", "standard", "hold"]))
		var infil: float = float(rng.randi_range(0, 20)) / 10.0
		var r: BattleResult = Battle.resolve(_squad(c, ids), enemies,
			{"infiltration": infil, "roe": roe, "reinforcements": ["warden"]}, _data, rng)
		outcomes[r.outcome] = int(outcomes.get(r.outcome, 0)) + 1
		var hostiles_up: int = 0
		var squad_up: int = 0
		for u: BattleUnit in r.units:
			if u.side == BattleUnit.HOSTILE and u.active():
				hostiles_up += 1
			if u.side == BattleUnit.SQUAD and u.active():
				squad_up += 1
		match r.outcome:
			BattleResult.Outcome.VICTORY:
				_check(hostiles_up == 0, "victory with %d hostiles standing" % hostiles_up)
			BattleResult.Outcome.WIPED:
				_check(squad_up == 0, "squad lost with %d soldiers standing" % squad_up)
				_check(r.kia_count() == ids.size(), "squad lost but only %d of %d dead" % [r.kia_count(), ids.size()])
			BattleResult.Outcome.WITHDRAWN:
				_check(hostiles_up > 0 and squad_up > 0, "withdrawal with %d hostiles and %d soldiers standing" % [hostiles_up, squad_up])
				_check(r.withdraw_reason != "", "withdrawal with no reason given")
		_check(r.soldier_results.size() == ids.size(), "results for %d of %d soldiers" % [r.soldier_results.size(), ids.size()])
		for id: Variant in r.soldier_results:
			var s: Dictionary = r.soldier_results[id] as Dictionary
			_check(not bool(s["kia"]) or bool(s["downed"]), "%s dead without going down" % id)
			_check(int(s["hp_lost"]) >= 0 and int(s["hp_lost"]) <= int(s["max_hp"]), "%s lost %d of %d HP" % [id, s["hp_lost"], s["max_hp"]])
		_check(r.hostiles_destroyed <= r.hostiles_total, "destroyed more hostiles than there were")
	# If any outcome never happens across 400 varied fights, the generator above
	# is not exercising the rules it claims to.
	for o: int in [BattleResult.Outcome.VICTORY, BattleResult.Outcome.WITHDRAWN, BattleResult.Outcome.WIPED]:
		_check(int(outcomes.get(o, 0)) > 0, "no %s in 400 fights" % BattleResult.OUTCOME_NAMES[o])


func test_roe_hold_never_retreats() -> void:
	var c: Campaign = _campaign()
	var rng: RunRng = RunRng.new(5)
	var squad: Array[Soldier] = _squad(c, _ids(["ruiz", "chen"]))
	for i: int in range(200):
		var r: BattleResult = Battle.resolve(squad, _ids(["warden", "warden", "warden", "mimic"]),
			{"infiltration": 0.5, "roe": "hold", "reinforcements": ["warden"]}, _data, rng)
		_check(r.withdraw_reason == "" or r.withdraw_reason == "stalemate",
			"Hold withdrew because '%s'" % r.withdraw_reason)


func test_roe_cautious_pulls_out() -> void:
	var c: Campaign = _campaign()
	var rng: RunRng = RunRng.new(6)
	var squad: Array[Soldier] = _squad(c, _ids(["ruiz", "chen", "okafor"]))
	var pulled: int = 0
	var cautious_dead: int = 0
	var hold_dead: int = 0
	for i: int in range(300):
		var ctx: Dictionary = {"infiltration": 1.0, "roe": "cautious", "reinforcements": []}
		var r: BattleResult = Battle.resolve(squad, _ids(["warden", "warden", "mimic", "sentry_drone"]), ctx, _data, rng)
		cautious_dead += r.kia_count()
		if r.outcome == BattleResult.Outcome.WITHDRAWN:
			pulled += 1
			_check(r.withdraw_reason in ["first_down", "heavy_damage", "stalemate"],
				"Cautious withdrew because '%s'" % r.withdraw_reason)
		ctx["roe"] = "hold"
		hold_dead += Battle.resolve(squad, _ids(["warden", "warden", "mimic", "sentry_drone"]), ctx, _data, rng).kia_count()
	_check(pulled > 0, "Cautious never withdrew in 300 hard fights")
	_check(cautious_dead < hold_dead, "Cautious cost %d lives, Hold %d — caution is not saving anyone" % [cautious_dead, hold_dead])


func test_infiltration_changes_the_opposition() -> void:
	var c: Campaign = _campaign()
	var squad: Array[Soldier] = _squad(c, _ids(["okafor", "brandt"]))
	var four: Array[String] = _ids(["warden", "warden", "sentry_drone", "sentry_drone"])
	var expect: Dictionary = {2.0: 2, 1.5: 3, 1.0: 4, 0.99: 4, 0.75: 5, 0.5: 6, 0.0: 7}
	for infil: Variant in expect:
		var r: BattleResult = Battle.resolve(squad, four,
			{"infiltration": float(infil), "roe": "hold", "reinforcements": ["warden"]}, _data, RunRng.new(1))
		_check(r.hostiles_total == int(expect[infil]),
			"at %d%% infiltration there were %d hostiles, expected %d" % [roundi(float(infil) * 100.0), r.hostiles_total, int(expect[infil])])
	var ambush: BattleResult = Battle.resolve(squad, four, {"infiltration": 1.0, "roe": "hold"}, _data, RunRng.new(1))
	_check(_has(ambush, "b_ambush"), "no ambush volley at 100%")
	var early: BattleResult = Battle.resolve(squad, four, {"infiltration": 0.4, "roe": "hold", "reinforcements": ["warden"]}, _data, RunRng.new(1))
	_check(not _has(early, "b_ambush") and _has(early, "b_caught"), "at 40% the squad still ambushed, or was not caught moving")


func test_scout_spots_mimic() -> void:
	var c: Campaign = _campaign()
	var with_scout: BattleResult = Battle.resolve(_squad(c, _ids(["hale", "ruiz"])), _ids(["mimic", "warden"]),
		{"infiltration": 1.0, "roe": "hold"}, _data, RunRng.new(3))
	_check(_has(with_scout, "b_spotted") and not _has(with_scout, "b_unmasked"), "a Scout did not spot the Mimic")
	var without: BattleResult = Battle.resolve(_squad(c, _ids(["chen", "ruiz"])), _ids(["mimic", "warden"]),
		{"infiltration": 1.0, "roe": "hold"}, _data, RunRng.new(3))
	_check(_has(without, "b_unmasked") and not _has(without, "b_spotted"), "a squad with no Scout saw the Mimic coming")
	# The unmasked Mimic shoots before anyone else does.
	var first_shot: String = ""
	for e: LogEvent in without.events:
		if e.type == "b_hit" or e.type == "b_miss":
			first_shot = str(e.values["attacker"])
			break
	_check(first_shot == "Mimic", "the first shot without a Scout came from '%s', not the Mimic" % first_shot)


func test_undetected_operation_is_missed() -> void:
	var c: Campaign = _campaign()
	for i: int in range(4):
		c.reassign("rhine", "supply")
	c.run_hours(100)
	_check(_first(c).state == Mission.State.EXPIRED, "first operation is %s with no intel rebels" % Mission.STATE_NAMES[_first(c).state])
	_check(c.log_bus.has_type("mission_missed"), "a missed operation wrote no log line")
	_check(not c.log_bus.has_type("mission_detected"), "something was detected with no intel rebels")


func test_ignored_operation_expires() -> void:
	var c: Campaign = _campaign()
	c.run_hours(200)
	var m: Mission = c.visible_missions()[0]
	# Hour by hour: other operations may be detected meanwhile, and their
	# interrupts are not what this test is about.
	var warned_at: int = -1
	var warn_reason: String = ""
	while m.is_open() and c.hour < 500:
		var reason: String = c.run_hours(1)
		if m.warned and warned_at < 0:
			warned_at = m.expires_at - c.hour
			warn_reason = reason
	_check(warn_reason == "expiry_warning", "the warning hour interrupted with '%s'" % warn_reason)
	_check(warned_at == int(_data.cfg("expiry_warning_hours", 12)), "warned %dh before the window closed" % warned_at)
	_check(m.state == Mission.State.EXPIRED, "ignored operation is %s after its window" % Mission.STATE_NAMES[m.state])
	_check(c.log_bus.has_type("mission_expired"), "an expired operation wrote no log line")


func test_window_launches_a_late_squad() -> void:
	var c: Campaign = _campaign()
	c.run_hours(200)
	var m: Mission = c.visible_missions()[0]
	var six: Array[String] = _ids(["okafor", "brandt", "ruiz", "chen", "novak", "achterberg"])
	_check(c.infiltration_hours(six, m) > float(m.hours_left(c.hour)), "test premise: six without Scouts should be too slow")
	c.dispatch(m.id, six, "standard")
	var resolved: Array = []
	c.battle_resolved.connect(func(id: int, r: BattleResult) -> void: resolved.append(r))
	for i: int in range(10):
		if m.state != Mission.State.INFILTRATING:
			break
		c.run_hours(200)
	_check(m.state == Mission.State.RESOLVED, "the window closed and the operation is %s" % Mission.STATE_NAMES[m.state])
	_check(c.log_bus.has_type("window_closing"), "no log line for the forced launch")
	_check(resolved.size() == 1, "battle_resolved fired %d times" % resolved.size())
	if resolved.size() == 1:
		_check((resolved[0] as BattleResult).infiltration < 1.0, "a late squad went in at full infiltration")


func test_reveal_and_boost_cost_intel() -> void:
	var c: Campaign = _campaign()
	c.run_hours(200)
	var m: Mission = c.visible_missions()[0]
	var before: int = c.intel
	_check(c.reveal(m.id), "reveal refused with %d intel" % before)
	_check(c.intel == before - int(_data.cfg("reveal_cost", 10)), "reveal did not cost intel")
	_check(m.revealed, "reveal did not reveal")
	_check(not c.reveal(m.id), "revealed twice")
	c.dispatch(m.id, _ids(["okafor", "brandt", "ruiz", "chen"]), "standard")
	c.intel = 100
	var pct: float = c.infiltration(m)
	_check(c.boost(m.id), "boost refused")
	_check(is_equal_approx(c.infiltration(m), pct + float(_data.cfg("boost_amount", 0.25))), "boost did not add infiltration")
	_check(not c.boost(m.id), "boosted past the per-operation limit")
	var poor: Campaign = _campaign()
	poor.run_hours(200)
	poor.intel = 3
	_check(not poor.reveal(poor.visible_missions()[0].id), "reveal accepted with 3 intel")


func test_supply_drop() -> void:
	var c: Campaign = _campaign()
	for i: int in range(4):
		c.reassign("rhine", "supply")   # nobody detects anything: an uninterrupted month
	var forecast: int = c.supply_forecast()
	var before: int = c.supplies
	while c.hour < 738:
		c.run_hours(738 - c.hour)
	_check(c.log_bus.has_type("supply_drop"), "no supply drop by Apr 01")
	_check(c.supplies == before + forecast, "drop paid %d, forecast said %d" % [c.supplies - before, forecast])


func test_wounds_heal() -> void:
	var c: Campaign = _campaign()
	var s: Soldier = c.soldier("chen")
	s.status = Soldier.Status.WOUNDED
	s.recover_at = c.hour + 5
	c.run_hours(4)
	_check(s.status == Soldier.Status.WOUNDED, "healed early")
	c.run_hours(1)
	_check(s.status == Soldier.Status.READY, "not healed on time")
	_check(c.log_bus.has_type("soldier_recovered"), "recovery wrote no log line")


func test_assess_leaves_the_dice_alone() -> void:
	var a: Campaign = _campaign(31)
	var b: Campaign = _campaign(31)
	a.run_hours(200)
	b.run_hours(200)
	var m: Mission = a.visible_missions()[0]
	a.reveal(m.id)
	b.reveal(b.visible_missions()[0].id)
	var read: Dictionary = a.assess(m.id, _ids(["okafor", "hale", "brandt"]), "standard")
	_check(bool(read["known"]) and int(read["runs"]) > 0, "assessment produced nothing on a revealed operation")
	var again: Dictionary = a.assess(m.id, _ids(["okafor", "hale", "brandt"]), "standard")
	_check(int(read["wins"]) == int(again["wins"]), "the same squad got two different reads")
	_check(a.rng.randi_range(0, 1000000) == b.rng.randi_range(0, 1000000), "assessing moved the campaign's RNG")
	var blind: Campaign = _campaign(31)
	blind.run_hours(200)
	_check(not bool(blind.assess(blind.visible_missions()[0].id, _ids(["okafor", "hale"]), "standard")["known"]),
		"an assessment was offered without the composition")


func test_promotion() -> void:
	var c: Campaign = _campaign()
	c.run_hours(200)
	var m: Mission = c.visible_missions()[0]
	var ruiz: Soldier = c.soldier("ruiz")
	ruiz.xp = 1   # one surviving mission from Private
	c.dispatch(m.id, _ids(["ruiz", "hale", "okafor", "brandt"]), "hold")
	while m.state == Mission.State.INFILTRATING and c.infiltration(m) < 1.5:
		c.run_hours(1)
	_check(m.state == Mission.State.INFILTRATING, "test premise: the squad should reach 150% before the window")
	if m.state != Mission.State.INFILTRATING:
		return
	var r: BattleResult = c.launch(m.id)
	if r.kia_count() == 0 or not bool((r.soldier_results["ruiz"] as Dictionary)["kia"]):
		_check(ruiz.rank >= 1, "Ruiz survived at %d xp and is still rank %d" % [ruiz.xp, ruiz.rank])
		_check(c.log_bus.has_type("soldier_promoted"), "a promotion wrote no log line")


func _has(r: BattleResult, type: String) -> bool:
	for e: LogEvent in r.events:
		if e.type == type:
			return true
	return false
