extends RefCounted
class_name Battle

# The autoresolve. This game has no tactical layer, so this is the whole fight:
# a short abstract skirmish between named units, rolled on the campaign's
# seeded RNG, every roll written to the battle log.
#
# It is deliberately not clever. What it has to be is *causal*: every outcome
# in the after-action report must trace back to a decision made at the desk.
#
#   who went          classes matter — EMP against mechs, Scouts against Mimics
#   how long they     under 100% the machines get reinforcements and, below
#   infiltrated       50%, the first move; at 100% the squad gets an ambush
#                     volley; past it, hostiles are slipped entirely
#   what intel        a confirmed composition is what makes the first two
#   was bought        choices informed rather than guessed
#   rules of          when the squad pulls out, and so who comes home carried
#   engagement        and who does not come home at all
#
# If a loss cannot be explained from the log, the game is a slot machine, and
# no strategic layer survives that. Machines never retreat; people do.

const ENEMY_LETTERS: String = "ABCDEFGHIJ"

var _data: GameData = null
var _rng: RunRng = null
var _res: BattleResult = null
var _squad: Array[BattleUnit] = []
var _hostile: Array[BattleUnit] = []
var _round: int = 0


static func resolve(squad: Array[Soldier], enemy_ids: Array[String], ctx: Dictionary,
		data: GameData, rng: RunRng) -> BattleResult:
	var b: Battle = Battle.new()
	return b._run(squad, enemy_ids, ctx, data, rng)


func _run(squad: Array[Soldier], enemy_ids: Array[String], ctx: Dictionary,
		data: GameData, rng: RunRng) -> BattleResult:
	_data = data
	_rng = rng
	_res = BattleResult.new()
	var infil: float = float(ctx.get("infiltration", 1.0))
	var roe: String = str(ctx.get("roe", "standard"))
	_res.infiltration = infil
	_res.roe = roe

	for s: Soldier in squad:
		_squad.append(BattleUnit.from_soldier(s, data))

	var ids: Array[String] = []
	ids.assign(enemy_ids)
	_event("b_contact", LogEvent.NEUTRAL, {
		"infiltration": infil, "squad": _squad.size(), "hostiles": ids.size(),
	})
	_adjust_for_infiltration(ids, infil, ctx.get("reinforcements", []) as Array)
	_spawn_hostiles(ids)
	_res.hostiles_total = _hostile.size()

	_unmask()
	if infil >= 1.0 and not _over():
		_event("b_ambush", LogEvent.GOOD, {})
		var ambush_aim: int = int(_data.rule("ambush_aim", 15))
		for u: BattleUnit in _squad:
			if _over():
				break
			if u.active():
				var t: BattleUnit = _choose_target(u)
				if t != null:
					_attack(u, t, ambush_aim)

	var squad_first: bool = infil >= float(_data.rule("enemies_first_below", 0.5))
	if not squad_first:
		_event("b_caught", LogEvent.WARNING, {})

	var max_rounds: int = int(_data.rule("max_rounds", 6))
	var why: String = ""
	while not _over():
		if _round >= max_rounds:
			why = "stalemate"
			break
		_round += 1
		_event("b_round", LogEvent.NEUTRAL, {"n": _round})
		var order: Array = [_squad, _hostile] if squad_first else [_hostile, _squad]
		for side: Array in order:
			for u: BattleUnit in side:
				if _over():
					break
				if not u.active():
					continue
				var t: BattleUnit = _choose_target(u)
				if t != null:
					_attack(u, t, 0)
		if _over():
			break
		why = _withdraw_reason(roe)
		if why != "":
			break

	if not _over() and why != "":
		_res.withdraw_reason = why
		_event("b_withdraw", LogEvent.WARNING, {"reason": why})
		# Breaking contact is not free: every machine still standing gets a
		# parting shot, at a penalty, at whoever is last out.
		var penalty: int = int(_data.rule("withdraw_aim_penalty", 20))
		for h: BattleUnit in _hostile:
			if _alive(_squad) == 0:
				break
			if h.active():
				var t: BattleUnit = _choose_target(h)
				if t != null:
					_attack(h, t, -penalty)

	if _alive(_squad) == 0:
		_res.outcome = BattleResult.Outcome.WIPED
		_event("b_wiped", LogEvent.CRITICAL, {})
	elif _alive(_hostile) == 0:
		_res.outcome = BattleResult.Outcome.VICTORY
		_event("b_victory", LogEvent.GOOD, {})
	else:
		_res.outcome = BattleResult.Outcome.WITHDRAWN
		_event("b_extracted", LogEvent.WARNING, {})

	_resolve_downed()
	_res.rounds = _round
	for h: BattleUnit in _hostile:
		if h.down:
			_res.hostiles_destroyed += 1
	_res.units.append_array(_squad)
	_res.units.append_array(_hostile)
	return _res


# Long War's infiltration rule, adapted: time spent getting in is paid for in
# what is waiting when you arrive.
func _adjust_for_infiltration(ids: Array[String], infil: float, pool: Array) -> void:
	if infil >= 1.0:
		var step: float = float(_data.rule("overinfiltration_step", 0.5))
		var n: int = floori((infil - 1.0) / step + 0.0001)
		n = mini(n, int(_data.rule("overinfiltration_max_removed", 2)))
		n = mini(n, ids.size() - 1)
		if n <= 0:
			return
		var gone: Array[String] = []
		for i: int in range(n):
			gone.append(_data.enemy_name(str(ids.pop_back())))
		_event("b_slipped", LogEvent.GOOD, {"enemies": ", ".join(gone), "count": n})
		return
	var step_r: float = float(_data.rule("reinforce_step", 0.25))
	var add: int = floori((1.0 - infil) / step_r + 0.0001)
	add = mini(add, int(_data.rule("reinforce_max", 3)))
	if add <= 0 or pool.is_empty():
		return
	var came: Array[String] = []
	for i: int in range(add):
		var id: String = str(_rng.pick(pool))
		ids.append(id)
		came.append(_data.enemy_name(id))
	_event("b_reinforced", LogEvent.WARNING, {"enemies": ", ".join(came), "count": add})


func _spawn_hostiles(ids: Array[String]) -> void:
	var counts: Dictionary = {}
	for id: String in ids:
		counts[id] = int(counts.get(id, 0)) + 1
	var seen: Dictionary = {}
	for id: String in ids:
		var n: int = int(seen.get(id, 0))
		seen[id] = n + 1
		var label: String = _data.enemy_name(id)
		if int(counts[id]) > 1:
			label += " " + ENEMY_LETTERS[mini(n, ENEMY_LETTERS.length() - 1)]
		_hostile.append(BattleUnit.from_enemy(id, "%s#%d" % [id, n], label, _data))


# A Mimic walks up looking like a refugee. A Scout knows the gait; without one,
# the first anybody knows of it is the shot.
func _unmask() -> void:
	var spotter: BattleUnit = null
	for u: BattleUnit in _squad:
		if u.spotter:
			spotter = u
			break
	for h: BattleUnit in _hostile:
		if not h.disguised:
			continue
		if spotter != null:
			_event("b_spotted", LogEvent.GOOD, {"soldier": spotter.label, "enemy": h.label})
		else:
			h.hidden = true
	var surprise: int = int(_data.rule("surprise_aim", 20))
	for h: BattleUnit in _hostile:
		if not h.hidden or _over():
			continue
		_event("b_unmasked", LogEvent.CRITICAL, {"enemy": h.label})
		var t: BattleUnit = _weakest(_squad)
		if t != null:
			_attack(h, t, surprise)
		h.hidden = false


func _choose_target(u: BattleUnit) -> BattleUnit:
	var foes: Array[BattleUnit] = _hostile if u.side == BattleUnit.SQUAD else _squad
	if u.side == BattleUnit.HOSTILE:
		# Infiltrators go for the kill they can get; everything else spreads
		# fire, weighted toward whoever is easiest to hit.
		if u.tags.has("infiltrator"):
			return _weakest(foes)
		var total: float = 0.0
		var pool: Array[BattleUnit] = []
		var weights: Array[float] = []
		for f: BattleUnit in foes:
			if f.active() and not f.hidden:
				var w: float = float(_chance(u, f, 0))
				pool.append(f)
				weights.append(w)
				total += w
		if pool.is_empty():
			return null
		var roll: float = _rng.randf() * total
		for i: int in range(pool.size()):
			roll -= weights[i]
			if roll < 0.0:
				return pool[i]
		return pool[pool.size() - 1]

	# Soldiers take the shot with the best expected return, and a likely kill
	# over a scratch. Deterministic, ties to the first listed.
	var best: BattleUnit = null
	var best_score: float = -1.0
	for f: BattleUnit in foes:
		if not f.active() or f.hidden:
			continue
		var p: float = float(_chance(u, f, 0)) / 100.0
		var expected: float = maxf(1.0,
			(u.dmg_min + u.dmg_max) * 0.5 + u.bonus_against(f) - maxi(0, f.armor - u.pierce))
		var score: float = p * minf(expected, float(f.hp))
		if expected >= float(f.hp):
			score += p * 3.0
		if score > best_score:
			best_score = score
			best = f
	return best


func _weakest(units: Array[BattleUnit]) -> BattleUnit:
	var best: BattleUnit = null
	for u: BattleUnit in units:
		if not u.active() or u.hidden:
			continue
		if best == null or u.hp < best.hp:
			best = u
	return best


func _chance(a: BattleUnit, t: BattleUnit, mod: int) -> int:
	return clampi(a.aim + mod - t.defense,
		int(_data.rule("hit_min", 5)), int(_data.rule("hit_max", 95)))


func _attack(a: BattleUnit, t: BattleUnit, mod: int) -> void:
	var chance: int = _chance(a, t, mod)
	a.shots += 1
	if _rng.randi_range(1, 100) > chance:
		_event("b_miss", LogEvent.NEUTRAL, {
			"attacker": a.label, "target": t.label, "chance": chance, "side": a.side,
		})
		return
	a.hits += 1
	var dmg: int = _rng.randi_range(a.dmg_min, a.dmg_max)
	var bonus: int = a.bonus_against(t)
	var crit: bool = _rng.chance(float(_data.rule("crit_chance", 0.1)))
	dmg += bonus
	if crit:
		dmg += int(_data.rule("crit_bonus", 2))
	var soak: int = maxi(0, t.armor - a.pierce)
	dmg = maxi(1, dmg - soak)
	t.hp -= dmg
	a.damage_dealt += dmg
	var fell: bool = t.hp <= 0
	if fell:
		t.hp = 0
		t.down = true
		if a.side == BattleUnit.SQUAD:
			a.kills += 1
	var severity: String = LogEvent.NEUTRAL
	if fell:
		severity = LogEvent.CRITICAL if t.side == BattleUnit.SQUAD else LogEvent.GOOD
	_event("b_hit", severity, {
		"attacker": a.label, "target": t.label, "damage": dmg, "chance": chance,
		"crit": crit, "bonus": bonus, "soak": soak, "fell": fell, "side": a.side,
		"hp": t.hp,
	})


func _withdraw_reason(roe: String) -> String:
	var n: int = _squad.size()
	var down: int = n - _alive(_squad)
	match roe:
		"cautious":
			if down > 0:
				return "first_down"
			var lost: int = 0
			var total: int = 0
			for u: BattleUnit in _squad:
				lost += u.hp_lost()
				total += u.max_hp
			if float(lost) >= float(total) * float(_data.rule("cautious_hp_loss", 0.34)):
				return "heavy_damage"
		"standard":
			if down * 2 >= n:
				return "half_down"
			if _alive(_squad) < _alive(_hostile):
				return "outnumbered"
	return ""


# A soldier at zero is down, not dead. Whether they come home depends on who
# holds the ground: carried out after a win or an orderly withdrawal, they
# might make it. Left on a field the machines own, they do not.
func _resolve_downed() -> void:
	var stabilize: float = float(_data.rule("stabilize_chance", 0.6))
	if _res.outcome == BattleResult.Outcome.VICTORY:
		stabilize += float(_data.rule("stabilize_bonus_victory", 0.2))
	for u: BattleUnit in _squad:
		var kia: bool = false
		if u.down:
			if _res.outcome == BattleResult.Outcome.WIPED:
				kia = true
				_event("b_lost", LogEvent.CRITICAL, {"soldier": u.label})
			elif _rng.chance(stabilize):
				_event("b_stabilized", LogEvent.WARNING, {"soldier": u.label})
			else:
				kia = true
				_event("b_bled_out", LogEvent.CRITICAL, {"soldier": u.label})
		_res.soldier_results[u.key] = {
			"hp_lost": u.hp_lost(), "max_hp": u.max_hp, "downed": u.down, "kia": kia,
			"kills": u.kills, "shots": u.shots, "hits": u.hits, "damage": u.damage_dealt,
		}


func _alive(units: Array[BattleUnit]) -> int:
	var n: int = 0
	for u: BattleUnit in units:
		if u.active():
			n += 1
	return n


func _over() -> bool:
	return _alive(_squad) == 0 or _alive(_hostile) == 0


func _event(type: String, severity: String, values: Dictionary) -> void:
	_res.events.append(LogEvent.make(type, severity, values, _round))
