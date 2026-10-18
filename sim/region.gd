extends RefCounted
class_name Region

# A region of the theatre. Only a contacted region has a haven, and only a
# haven's rebels can see what the machines are doing there. In v0.1 one region
# is contacted and the rest are on the map to show where the campaign goes.

var id: String = ""
var label: String = ""
# Position on the theatre map, 0..1 on both axes. ui/ scales it.
var pos: Vector2 = Vector2.ZERO
var neighbors: Array[String] = []
var contacted: bool = false
# Custodian presence, 1..5. Shown, not yet simulated; see BACKLOG.md.
var strength: int = 1
var haven: Haven = null


static func from_data(d: Dictionary) -> Region:
	var r: Region = Region.new()
	r.id = str(d.get("id", ""))
	r.label = str(d.get("name", r.id))
	var p: Array = d.get("pos", [0.5, 0.5]) as Array
	r.pos = Vector2(float(p[0]), float(p[1]))
	for n: Variant in d.get("neighbors", []) as Array:
		r.neighbors.append(str(n))
	r.contacted = bool(d.get("contacted", false))
	r.strength = int(d.get("strength", 1))
	var hv: Variant = d.get("haven", null)
	if hv is Dictionary:
		r.haven = Haven.from_data(hv as Dictionary, r.id)
	return r
