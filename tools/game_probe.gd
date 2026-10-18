class_name GameProbe
extends RefCounted

# Asks the running game what is true, in the game's own nouns. Carried over from
# Deadweight, where it replaced inferring state from screenshots.
#
# Three rules, and tools/check_rules.py enforces the first:
#
#   1. **It only reads.** A probe that can change the game is a second,
#      undocumented way to play it, and the tests drift from the real one.
#   2. **It reports, it does not judge.** Assertions live in tools/play.gd.
#   3. **Its output is plain data**, so two runs can be compared directly.

var _desk: CommandDesk = null


func _init(desk: CommandDesk) -> void:
	_desk = desk


func campaign() -> Campaign:
	return _desk.campaign


func snapshot() -> Dictionary:
	var c: Campaign = _desk.campaign
	var ms: Array = []
	for m: Mission in c.missions:
		ms.append({
			"id": m.id, "type": m.template_id, "state": Mission.STATE_NAMES[m.state],
			"expires": m.expires_at, "revealed": m.revealed, "squad": m.squad.duplicate(),
			"infiltration": snappedf(c.infiltration(m), 0.001), "outcome": m.outcome,
			"enemies": m.enemies.duplicate(),
		})
	var ss: Array = []
	for s: Soldier in c.soldiers + c.fallen:
		ss.append({"id": s.id, "status": Soldier.STATUS_NAMES[s.status], "xp": s.xp,
			"rank": s.rank, "recover_at": s.recover_at})
	return {
		"hour": c.hour, "paused": c.is_paused(), "supplies": c.supplies, "intel": c.intel,
		"missions": ms, "soldiers": ss, "log": log_types(),
		"planner_open": _desk.planner != null, "report_open": _desk.report != null,
	}


func log_types() -> Array:
	var out: Array = []
	for e: LogEvent in _desk.campaign.log_bus.events:
		out.append(e.type)
	return out


func control(node_name: String) -> Control:
	return _desk.find_child(node_name, true, false) as Control


func button(node_name: String) -> BaseButton:
	return control(node_name) as BaseButton


func text_of(node_name: String) -> String:
	var c: Control = control(node_name)
	if c is Label:
		return (c as Label).text
	if c is RichTextLabel:
		return (c as RichTextLabel).get_parsed_text()
	if c is BaseButton and c.get("text") != null:
		return str(c.get("text"))
	return ""


# Every Label's text under a node, joined — for checks that care what the
# player can read in a panel, not which Label it sits in.
func all_text(node_name: String) -> String:
	var root: Node = control(node_name)
	if root == null:
		return ""
	var parts: PackedStringArray = PackedStringArray()
	_collect_text(root, parts)
	return "\n".join(parts)


func roster_rows() -> int:
	var box: Node = control("RosterList")
	return box.get_child_count() if box != null else 0


func ops_cards() -> Array:
	var out: Array = []
	var box: Node = control("OpsList")
	if box == null:
		return out
	for child: Node in box.get_children():
		if child is OpsCard and not child.is_queued_for_deletion():
			out.append(str(child.name))
	return out


func overlay_visible() -> bool:
	return _desk.modal_open()


# Visible Controls with no area. The signature of the invisible-Control trap.
func zero_sized_controls() -> Array:
	var out: Array = []
	_walk(_desk, func(c: Control) -> void:
		if c.is_visible_in_tree() and (c.size.x <= 0.0 or c.size.y <= 0.0):
			out.append(str(_desk.get_path_to(c))))
	return out


# Visible Controls that reach outside the window — a panel cut off at the edge.
# Children of a ScrollContainer are skipped: running past their viewport is
# what they are for.
func offscreen_controls() -> Array:
	var out: Array = []
	var screen: Rect2 = Rect2(Vector2.ZERO, _desk.size).grow(1.0)
	_walk(_desk, func(c: Control) -> void:
		if not c.is_visible_in_tree() or _inside_scroll(c):
			return
		if not screen.encloses(c.get_global_rect()):
			out.append("%s %s" % [_desk.get_path_to(c), c.get_global_rect()]))
	return out


# Headless Godot lays the root Control out against a 64x64 stand-in window, so
# layout numbers mean nothing there. Compared against the project's configured
# viewport, never the runtime one, which would agree with itself.
func layout_is_trustworthy() -> bool:
	var want: Vector2 = Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 0)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 0)))
	return want.x > 0.0 and _desk.size.is_equal_approx(want)


func _walk(node: Node, visit: Callable) -> void:
	for child: Node in node.get_children():
		if child is Control:
			visit.call(child as Control)
		_walk(child, visit)


func _inside_scroll(c: Control) -> bool:
	var p: Node = c.get_parent()
	while p != null and p != _desk:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func _collect_text(node: Node, parts: PackedStringArray) -> void:
	if node is Label:
		parts.append((node as Label).text)
	elif node is RichTextLabel:
		parts.append((node as RichTextLabel).get_parsed_text())
	for child: Node in node.get_children():
		_collect_text(child, parts)
