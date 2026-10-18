extends RefCounted
class_name BattleResult

# What an autoresolve produced: the outcome, the full blow-by-blow, and per
# soldier what happened to them. Battle fills everything above `aftermath`;
# Campaign fills `aftermath` and `rewards` when it applies the result, so the
# after-action report can show recovery times and promotions without working
# them out a second time.

enum Outcome { VICTORY, WITHDRAWN, WIPED }

const OUTCOME_NAMES: Array[String] = ["Victory", "Withdrawn", "Squad lost"]

var outcome: Outcome = Outcome.WITHDRAWN
var rounds: int = 0
var infiltration: float = 0.0
var roe: String = ""
var withdraw_reason: String = ""
var hostiles_total: int = 0
var hostiles_destroyed: int = 0
var events: Array[LogEvent] = []
# soldier id -> {hp_lost, max_hp, downed, kia, kills, shots, hits, damage}
var soldier_results: Dictionary = {}
var units: Array[BattleUnit] = []

# soldier id -> {status, recover_hours, promoted}
var aftermath: Dictionary = {}
var rewards: Dictionary = {}


func kia_count() -> int:
	var n: int = 0
	for id: Variant in soldier_results:
		if bool((soldier_results[id] as Dictionary)["kia"]):
			n += 1
	return n


func downed_count() -> int:
	var n: int = 0
	for id: Variant in soldier_results:
		if bool((soldier_results[id] as Dictionary)["downed"]):
			n += 1
	return n


func wounded_count() -> int:
	var n: int = 0
	for id: Variant in soldier_results:
		var r: Dictionary = soldier_results[id] as Dictionary
		if not bool(r["kia"]) and int(r["hp_lost"]) > 0:
			n += 1
	return n
