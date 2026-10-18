extends RefCounted
class_name RunRng

# The only randomness in the project. Global randi() / randf() are forbidden,
# and tools/check_rules.py enforces it: a campaign seed must reproduce a
# campaign exactly, or neither the balance harness nor a bug report can replay
# one. Carried over from Deadweight's sim/rng.gd, seed-picking detail included.

var seed_value: int = 0

var _rng: RandomNumberGenerator = null


func _init(seed_in: int = 0) -> void:
	_rng = RandomNumberGenerator.new()
	if seed_in == 0:
		# Pick the seed first, then set it, so seed_value and the generator can
		# never disagree — and so the seed is short enough to read off the
		# screen and retype into a bug report.
		var picker: RandomNumberGenerator = RandomNumberGenerator.new()
		picker.randomize()
		seed_value = picker.randi_range(100000, 999999)
	else:
		seed_value = seed_in
	_rng.seed = seed_value


func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


func randf() -> float:
	return _rng.randf()


func chance(probability: float) -> bool:
	return _rng.randf() < probability


func pick(options: Array) -> Variant:
	if options.is_empty():
		return null
	return options[_rng.randi_range(0, options.size() - 1)]


# A key from {key: weight}. Keys are sorted first so the result never depends
# on the order a JSON file happened to list them in.
func weighted(weights: Dictionary) -> String:
	var keys: Array = weights.keys()
	keys.sort()
	var total: float = 0.0
	for k: Variant in keys:
		total += float(weights[k])
	if keys.is_empty() or total <= 0.0:
		return ""
	var roll: float = _rng.randf() * total
	for k: Variant in keys:
		roll -= float(weights[k])
		if roll < 0.0:
			return str(k)
	return str(keys[keys.size() - 1])
