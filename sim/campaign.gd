extends RefCounted
class_name Campaign

# The strategic game, headless. Everything the desk shows is read from here and
# everything the desk does is a call into here; ui/ could be deleted and this
# would still play — which is exactly how tools/sim_runner.gd and the tests run
# it.
#
# Time is whole hours. `advance()` takes real seconds from the UI, scales them
# by the scan speed and runs as many whole hours as have accumulated; the
# harnesses call `run_hours()` directly. Either way every rule runs once per
# hour in the same order, so the same seed and the same orders at the same
# hours give the same campaign, on every machine and at every frame rate.
#
# The sim owns the pause (`time_scale`, 0 or 1). Anything that needs the
# player's attention — an operation detected, a squad fully infiltrated, a
# window about to close, a fight resolved — stops the clock through
# `_interrupt()` and writes a log line saying why.

signal interrupted(reason: String, mission_id: int)
signal battle_resolved(mission_id: int, result: BattleResult)

var data: GameData = null
var rng: RunRng = null
var log_bus: LogBus = null
var hour: int = 0
var time_scale: float = 0.0
var speed: String = "scan"
var supplies: int = 0
var intel: int = 0
var regions: Array[Region] = []
var soldiers: Array[Soldier] = []
var fallen: Array[Soldier] = []
var missions: Array[Mission] = []
# Bumps whenever something structural changes — a mission appears or changes
# state, a soldier changes status. ui/ rebuilds its lists when it moves and
# only refreshes text otherwise.
var revision: int = 0
var last_interrupt: String = ""

var _accum: float = 0.0
var _next_id: int = 1


func _init(data_in: GameData, seed_in: int = 0) -> void:
	data = data_in
	rng = RunRng.new(seed_in)
	log_bus = LogBus.new()
	supplies = int(data.cfg("supplies", 0))
	intel = int(data.cfg("intel", 0))
	for d: Variant in data.regions:
		regions.append(Region.from_data(d as Dictionary))
	for d: Variant in data.roster:
		soldiers.append(Soldier.from_data(d as Dictionary, data))
	var home: Haven = home_haven()
	_emit("campaign_start", LogEvent.NEUTRAL, {
		"haven": home.label if home != null else "",
		"region": region(home.region_id).label if home != null else "",
		"soldiers": soldiers.size(),
	})
	_spawn_first()


# --- reading ----------------------------------------------------------------

func start() -> Dictionary:
	return data.start()


func cap() -> float:
	return float(data.cfg("infiltration_cap", 2.0))


func region(id: String) -> Region:
	for r: Region in regions:
		if r.id == id:
			return r
	return null


func home_haven() -> Haven:
	for r: Region in regions:
		if r.contacted and r.haven != null:
			return r.haven
	return null


func soldier(id: String) -> Soldier:
	for s: Soldier in soldiers:
		if s.id == id:
			return s
	for s: Soldier in fallen:
		if s.id == id:
			return s
	return null


func mission(id: int) -> Mission:
	for m: Mission in missions:
		if m.id == id:
			return m
	return null


# What the operations board shows: detected or under way, soonest to close first.
func visible_missions() -> Array[Mission]:
	var out: Array[Mission] = []
	for m: Mission in missions:
		if m.is_visible():
			out.append(m)
	out.sort_custom(func(a: Mission, b: Mission) -> bool:
		return a.expires_at < b.expires_at or (a.expires_at == b.expires_at and a.id < b.id))
	return out


func ready_soldiers() -> Array[Soldier]:
	var out: Array[Soldier] = []
	for s: Soldier in soldiers:
		if s.is_ready():
			out.append(s)
	return out


func infiltration(m: Mission) -> float:
	return m.infiltration_at(hour, cap())


# Hours a squad needs to reach 100% on this operation. Squad size is the big
# lever — Long War's trade between a squad strong enough to win and one small
# enough to get in before the window closes. Scouts take some of it back.
func infiltration_hours(ids: Array[String], m: Mission) -> float:
	var sq: Dictionary = data.cfg("squad", {}) as Dictionary
	var factors: Dictionary = sq.get("size_factor", {}) as Dictionary
	var base: float = float(data.template(m.template_id).get("infiltration_hours", 48))
	var factor: float = float(factors.get(str(ids.size()), 1.0))
	var stealth: float = 0.0
	for id: String in ids:
		var s: Soldier = soldier(id)
		if s != null:
			stealth += float(s.stats(data)["stealth"])
	stealth = minf(stealth, float(sq.get("stealth_cap", 0.3)))
	return base * factor * (1.0 - stealth)


# The board's honest guess at the size of the opposition before intel is spent:
# the range the operation type allows, not the real count.
func threat_range(m: Mission) -> Vector2i:
	var t: Dictionary = data.template(m.template_id)
	var e: Dictionary = t.get("enemies", {}) as Dictionary
	var core: int = (e.get("core", []) as Array).size()
	var extra: Array = e.get("extra_count", [0, 0]) as Array
	return Vector2i(core + int(extra[0]), core + int(extra[1]))


func composition_text(ids: Array[String]) -> String:
	var counts: Dictionary = {}
	var order: Array[String] = []
	for id: String in ids:
		if not counts.has(id):
			order.append(id)
		counts[id] = int(counts.get(id, 0)) + 1
	var parts: Array[String] = []
	for id: String in order:
		parts.append("%d× %s" % [int(counts[id]), data.enemy_name(id)])
	return ", ".join(parts)


func supply_forecast() -> int:
	var total: int = int(data.cfg("supply_drop_base", 0))
	for r: Region in regions:
		if r.contacted and r.haven != null:
			total += r.haven.on_supply * int(data.cfg("supply_per_rebel", 0))
	return total


func detection_rate(h: Haven) -> float:
	return float(h.on_intel) * float(data.cfg("intel_progress_per_rebel_hour", 1.0))


func can_reveal(m: Mission) -> bool:
	return m != null and m.is_visible() and not m.revealed \
		and intel >= int(data.cfg("reveal_cost", 10))


func can_boost(m: Mission) -> bool:
	return m != null and m.state == Mission.State.INFILTRATING \
		and m.boosts_used < int(data.cfg("boosts_per_operation", 1)) \
		and intel >= int(data.cfg("boost_cost", 15)) \
		and infiltration(m) < cap()


# A read on the fight before committing to it. Runs the real autoresolve many
# times on a private RNG, at full infiltration, against the real composition —
# so it is only offered once that composition has been paid for with intel.
# The private RNG is seeded from the inputs, so the same squad gets the same
# read every time and asking never disturbs the campaign's own dice.
func assess(mission_id: int, ids: Array[String], roe: String) -> Dictionary:
	var m: Mission = mission(mission_id)
	if m == null or not m.revealed or ids.is_empty():
		return {"known": false}
	var squad: Array[Soldier] = []
	for id: String in ids:
		var s: Soldier = soldier(id)
		if s != null:
			squad.append(s)
	var key: String = "%d|%d|%s|%s" % [rng.seed_value, m.id, ",".join(ids), roe]
	var dice: RunRng = RunRng.new(1 + absi(hash(key)) % 2147483000)
	var runs: int = int(data.cfg("assessment_runs", 80))
	var wins: int = 0
	var dead: int = 0
	var ctx: Dictionary = {"infiltration": 1.0, "roe": roe, "reinforcements": []}
	for i: int in range(runs):
		var r: BattleResult = Battle.resolve(squad, m.enemies, ctx, data, dice)
		if r.outcome == BattleResult.Outcome.VICTORY:
			wins += 1
		dead += r.kia_count()
	return {
		"known": true, "runs": runs, "wins": wins,
		"win_rate": float(wins) / float(runs), "dead": float(dead) / float(runs),
	}


# --- the clock --------------------------------------------------------------

func set_speed(mode: String) -> void:
	if mode == "pause":
		time_scale = 0.0
		_accum = 0.0
		return
	speed = mode
	time_scale = 1.0


func is_paused() -> bool:
	return time_scale <= 0.0


func hours_per_second() -> float:
	return float((data.cfg("speeds", {}) as Dictionary).get(speed, 3.0))


func advance(real_delta: float) -> void:
	if time_scale <= 0.0:
		return
	_accum += real_delta * time_scale * hours_per_second()
	while _accum >= 1.0:
		_accum -= 1.0
		_step_hour()
		if time_scale <= 0.0:
			# Something wanted the player. Hours left in the batch are dropped
			# rather than run past the moment that needed attention.
			_accum = 0.0
			break


# Runs whole hours until something interrupts or `max_hours` pass. Returns the
# interrupt reason, or "" if none came. For the harnesses; the UI uses advance().
func run_hours(max_hours: int) -> String:
	last_interrupt = ""
	for i: int in range(max_hours):
		_step_hour()
		if last_interrupt != "":
			return last_interrupt
	return ""


func _step_hour() -> void:
	hour += 1
	var date: Dictionary = Calendar.date_of(start(), hour)

	for s: Soldier in soldiers:
		if s.status == Soldier.Status.WOUNDED and hour >= s.recover_at:
			s.status = Soldier.Status.READY
			s.recover_at = -1
			revision += 1
			_emit("soldier_recovered", LogEvent.GOOD, {"soldier": s.full_name(data)})

	_detect()

	if int(date["hour"]) == 0:
		_daily(date)

	for m: Mission in missions.duplicate():
		_tick_mission(m)


func _detect() -> void:
	for r: Region in regions:
		if not r.contacted or r.haven == null:
			continue
		var rate: float = detection_rate(r.haven)
		for m: Mission in missions:
			if m.state != Mission.State.HIDDEN or m.region_id != r.id:
				continue
			m.detection_progress += rate
			if m.detection_progress >= m.detection_cost:
				m.state = Mission.State.DETECTED
				revision += 1
				_emit("mission_detected", LogEvent.WARNING, {
					"mission": m.label, "region": r.label, "hours": m.hours_left(hour),
					"haven": r.haven.label,
				})
				_interrupt("mission_detected", m.id)


func _daily(date: Dictionary) -> void:
	var gained: int = 0
	for r: Region in regions:
		if r.contacted and r.haven != null:
			gained += r.haven.on_intel * int(data.cfg("intel_per_rebel_day", 0))
	intel += gained

	if int(date["day"]) == 1:
		var drop: int = supply_forecast()
		supplies += drop
		_emit("supply_drop", LogEvent.GOOD, {"amount": drop, "total": supplies})

	for r: Region in regions:
		if r.contacted and rng.chance(float(data.cfg("spawn_chance_per_day", 0.0))):
			var weights: Dictionary = {}
			for id: Variant in data.templates:
				weights[id] = float((data.templates[id] as Dictionary).get("weight", 1))
			_create_mission(rng.weighted(weights), r.id, {})


func _tick_mission(m: Mission) -> void:
	if m.state == Mission.State.INFILTRATING:
		_announce_full(m)
	if not m.is_open():
		return
	if hour >= m.expires_at:
		match m.state:
			Mission.State.HIDDEN:
				m.state = Mission.State.EXPIRED
				revision += 1
				# The lesson of the intel economy, delivered after the fact:
				# operations the haven never saw still happened.
				_emit("mission_missed", LogEvent.WARNING, {
					"mission": m.label, "region": region(m.region_id).label,
				})
			Mission.State.DETECTED:
				m.state = Mission.State.EXPIRED
				revision += 1
				_emit("mission_expired", LogEvent.WARNING, {"mission": m.label})
			Mission.State.INFILTRATING:
				_emit("window_closing", LogEvent.WARNING, {
					"mission": m.label, "infiltration": infiltration(m),
				})
				launch(m.id)
		return
	if not m.warned and m.is_visible() \
			and m.expires_at - hour <= int(data.cfg("expiry_warning_hours", 12)):
		m.warned = true
		_emit("expiry_warning", LogEvent.WARNING, {
			"mission": m.label, "hours": m.hours_left(hour),
			"infiltrating": m.state == Mission.State.INFILTRATING,
			"infiltration": infiltration(m),
		})
		_interrupt("expiry_warning", m.id)


func _announce_full(m: Mission) -> void:
	if m.full_announced or infiltration(m) < 1.0:
		return
	m.full_announced = true
	_emit("infiltration_complete", LogEvent.GOOD, {
		"mission": m.label, "hours": m.hours_left(hour),
	})
	_interrupt("infiltration_complete", m.id)


# --- orders -----------------------------------------------------------------

func reassign(region_id: String, job: String) -> bool:
	var r: Region = region(region_id)
	if r == null or r.haven == null:
		return false
	if not r.haven.move_to(job):
		return false
	revision += 1
	return true


# Sends a squad toward an operation. Returns "" on success, otherwise the reason
# it was refused — the planner shows that reason rather than a dead button.
func dispatch(mission_id: int, ids: Array[String], roe: String) -> String:
	var m: Mission = mission(mission_id)
	if m == null or m.state != Mission.State.DETECTED:
		return "That operation is not open for planning."
	var sq: Dictionary = data.cfg("squad", {}) as Dictionary
	if ids.size() < int(sq.get("min", 2)) or ids.size() > int(sq.get("max", 6)):
		return "A squad is %d to %d soldiers." % [int(sq.get("min", 2)), int(sq.get("max", 6))]
	if data.roe_def(roe).is_empty():
		return "Unknown rules of engagement."
	var names: Array[String] = []
	for id: String in ids:
		var s: Soldier = soldier(id)
		if s == null or not s.is_ready():
			return "Everyone in the squad must be ready."
		names.append(s.title(data))
	m.squad.assign(ids)
	m.roe = roe
	m.infil_start = hour
	m.infil_hours = infiltration_hours(ids, m)
	m.state = Mission.State.INFILTRATING
	for id: String in ids:
		var s: Soldier = soldier(id)
		s.status = Soldier.Status.INFILTRATING
		s.mission_id = m.id
	revision += 1
	_emit("squad_dispatched", LogEvent.NEUTRAL, {
		"mission": m.label, "squad": ", ".join(names), "hours": ceili(m.infil_hours),
		"roe": str(data.roe_def(roe).get("name", roe)),
	})
	return ""


func reveal(mission_id: int) -> bool:
	var m: Mission = mission(mission_id)
	if not can_reveal(m):
		return false
	intel -= int(data.cfg("reveal_cost", 10))
	m.revealed = true
	revision += 1
	_emit("intel_reveal", LogEvent.NEUTRAL, {
		"mission": m.label, "composition": composition_text(m.enemies),
		"cost": int(data.cfg("reveal_cost", 10)),
	})
	return true


func boost(mission_id: int) -> bool:
	var m: Mission = mission(mission_id)
	if not can_boost(m):
		return false
	intel -= int(data.cfg("boost_cost", 15))
	m.boost += float(data.cfg("boost_amount", 0.25))
	m.boosts_used += 1
	revision += 1
	_emit("intel_boost", LogEvent.NEUTRAL, {
		"mission": m.label, "infiltration": infiltration(m),
		"cost": int(data.cfg("boost_cost", 15)),
	})
	_announce_full(m)
	return true


# Fights it. Called by the player's Launch, or by the window closing on a squad
# still moving in. Applies everything the fight decided and stops the clock so
# the after-action report can be read.
func launch(mission_id: int) -> BattleResult:
	var m: Mission = mission(mission_id)
	if m == null or m.state != Mission.State.INFILTRATING:
		return null
	var infil: float = infiltration(m)
	var squad: Array[Soldier] = []
	for id: String in m.squad:
		squad.append(soldier(id))
	_emit("mission_launched", LogEvent.NEUTRAL, {"mission": m.label, "infiltration": infil})
	var t: Dictionary = data.template(m.template_id)
	var ctx: Dictionary = {
		"infiltration": infil, "roe": m.roe,
		"reinforcements": t.get("reinforcements", []) as Array,
	}
	var result: BattleResult = Battle.resolve(squad, m.enemies, ctx, data, rng)
	_apply(m, squad, result)
	m.state = Mission.State.RESOLVED
	m.outcome = BattleResult.OUTCOME_NAMES[result.outcome]
	revision += 1
	_emit("mission_result", _outcome_severity(result), {
		"mission": m.label, "outcome": m.outcome, "kia": result.kia_count(),
		"destroyed": result.hostiles_destroyed, "total": result.hostiles_total,
	})
	battle_resolved.emit(m.id, result)
	_interrupt("battle_resolved", m.id)
	return result


func _apply(m: Mission, squad: Array[Soldier], result: BattleResult) -> void:
	var wound_hours: int = int(data.cfg("wound_hours_per_hp", 30))
	var grave_hours: int = int(data.cfg("grave_wound_hours", 240))
	for s: Soldier in squad:
		var r: Dictionary = result.soldier_results.get(s.id, {}) as Dictionary
		var after: Dictionary = {"status": "unhurt", "recover_hours": 0, "promoted": ""}
		s.mission_id = -1
		s.missions += 1
		s.kills += int(r.get("kills", 0))
		if bool(r.get("kia", false)):
			s.status = Soldier.Status.KIA
			soldiers.erase(s)
			fallen.append(s)
			after["status"] = "kia"
			result.aftermath[s.id] = after
			_emit("soldier_kia", LogEvent.CRITICAL, {"soldier": s.full_name(data), "mission": m.label})
			continue
		s.xp += 1 + int(r.get("kills", 0))
		var lost: int = int(r.get("hp_lost", 0))
		if bool(r.get("downed", false)):
			s.status = Soldier.Status.WOUNDED
			s.recover_at = hour + grave_hours + lost * wound_hours
			after["status"] = "grave"
		elif lost > 0:
			s.status = Soldier.Status.WOUNDED
			s.recover_at = hour + lost * wound_hours
			after["status"] = "wounded"
		else:
			s.status = Soldier.Status.READY
		if s.status == Soldier.Status.WOUNDED:
			after["recover_hours"] = s.recover_at - hour
			_emit("soldier_wounded", LogEvent.WARNING, {
				"soldier": s.full_name(data), "hours": s.recover_at - hour,
				"grave": after["status"] == "grave",
			})
		var new_rank: int = data.rank_for_xp(s.xp)
		if new_rank > s.rank:
			s.rank = new_rank
			after["promoted"] = str(data.rank_def(new_rank).get("name", ""))
			_emit("soldier_promoted", LogEvent.GOOD, {
				"soldier": s.full_name(data), "rank": after["promoted"],
			})
		result.aftermath[s.id] = after

	if result.outcome == BattleResult.Outcome.VICTORY:
		var gain_s: int = int(m.rewards.get("supplies", 0))
		var gain_i: int = int(m.rewards.get("intel", 0))
		supplies += gain_s
		intel += gain_i
		result.rewards = {"supplies": gain_s, "intel": gain_i}
		_emit("rewards", LogEvent.GOOD, {"supplies": gain_s, "intel": gain_i, "mission": m.label})


func _outcome_severity(result: BattleResult) -> String:
	match result.outcome:
		BattleResult.Outcome.VICTORY:
			return LogEvent.GOOD
		BattleResult.Outcome.WIPED:
			return LogEvent.CRITICAL
	return LogEvent.WARNING


# --- missions ---------------------------------------------------------------

# The first operation is authored, not rolled: the campaign promises one early
# encounter that shows both kinds of enemy, so data/campaign.json pins it.
func _spawn_first() -> void:
	var f: Dictionary = data.cfg("first_mission", {}) as Dictionary
	if f.is_empty():
		return
	_create_mission(str(f.get("template", "")), str(f.get("region", "")), f)


func _create_mission(template_id: String, region_id: String, overrides: Dictionary) -> Mission:
	var t: Dictionary = data.template(template_id)
	var m: Mission = Mission.new()
	m.id = _next_id
	_next_id += 1
	m.template_id = template_id
	m.label = str(t.get("name", template_id))
	m.region_id = region_id
	m.created_at = hour
	var duration: int = int(overrides["duration_hours"]) if overrides.has("duration_hours") \
		else _roll_range(t.get("duration_hours", [72, 72]) as Array)
	m.expires_at = hour + duration
	m.detection_cost = float(overrides["detection_cost"]) if overrides.has("detection_cost") \
		else float(_roll_range(t.get("detection_cost", [60, 60]) as Array))
	if overrides.has("enemies"):
		for e: Variant in overrides["enemies"] as Array:
			m.enemies.append(str(e))
	else:
		m.enemies = _roll_composition(t.get("enemies", {}) as Dictionary)
	m.rewards = (t.get("rewards", {}) as Dictionary).duplicate()
	missions.append(m)
	return m


func _roll_range(pair: Array) -> int:
	return rng.randi_range(int(pair[0]), int(pair[1]))


func _roll_composition(e: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id: Variant in e.get("core", []) as Array:
		out.append(str(id))
	var extras: Dictionary = e.get("extras", {}) as Dictionary
	var n: int = _roll_range(e.get("extra_count", [0, 0]) as Array)
	for i: int in range(n):
		var id: String = rng.weighted(extras)
		if id != "":
			out.append(id)
	return out


# --- plumbing ---------------------------------------------------------------

func _interrupt(reason: String, mission_id: int) -> void:
	time_scale = 0.0
	_accum = 0.0
	last_interrupt = reason
	interrupted.emit(reason, mission_id)


func _emit(type: String, severity: String, values: Dictionary) -> void:
	log_bus.append(LogEvent.make(type, severity, values, hour))
