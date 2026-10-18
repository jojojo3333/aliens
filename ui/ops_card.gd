extends PanelContainer
class_name OpsCard

# One operation on the board. A detected operation offers a plan; one under way
# shows the squad, infiltration against the window, and the two decisions left:
# launch now, or spend intel to get further in.

signal plan_requested(mission_id: int)
signal launch_requested(mission_id: int)
signal boost_requested(mission_id: int)

var mission: Mission = null

var _window: Label = null
var _threat: Label = null
var _bar: ProgressBar = null
var _bar_text: Label = null
var _launch: Button = null
var _boost: Button = null


func bind(c: Campaign, m: Mission) -> void:
	mission = m
	name = "Op_%d" % m.id
	var infiltrating: bool = m.state == Mission.State.INFILTRATING
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	add_child(col)

	var title: Label = Palette.label(m.label.to_upper(), Palette.SQUAD if infiltrating else Palette.AMBER, 15)
	col.add_child(title)
	_window = Palette.label("", Palette.DIM, 12)
	col.add_child(_window)
	_threat = Palette.wrapped("", Palette.TEXT, 13)
	col.add_child(_threat)

	if not infiltrating:
		var plan: Button = Button.new()
		plan.name = "PlanButton_%d" % m.id
		plan.text = "Plan operation"
		plan.custom_minimum_size = Vector2(0.0, 30.0)
		plan.pressed.connect(func() -> void: plan_requested.emit(m.id))
		col.add_child(plan)
		return

	var names: Array[String] = []
	for id: String in m.squad:
		var s: Soldier = c.soldier(id)
		if s != null:
			names.append(s.last_name)
	col.add_child(Palette.wrapped("Squad: " + ", ".join(names) + "  ·  ROE " +
		str(c.data.roe_def(m.roe).get("name", m.roe)), Palette.SQUAD, 12))
	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = c.cap() * 100.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0.0, 10.0)
	col.add_child(_bar)
	_bar_text = Palette.label("", Palette.TEXT, 12)
	col.add_child(_bar_text)
	var row: HBoxContainer = HBoxContainer.new()
	col.add_child(row)
	_launch = Button.new()
	_launch.name = "LaunchButton_%d" % m.id
	_launch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_launch.custom_minimum_size = Vector2(0.0, 30.0)
	_launch.pressed.connect(func() -> void: launch_requested.emit(m.id))
	row.add_child(_launch)
	_boost = Button.new()
	_boost.name = "BoostButton_%d" % m.id
	_boost.custom_minimum_size = Vector2(0.0, 30.0)
	_boost.pressed.connect(func() -> void: boost_requested.emit(m.id))
	row.add_child(_boost)


func refresh(c: Campaign) -> void:
	var left: int = mission.hours_left(c.hour)
	_window.text = "%s  ·  window closes in %s" % [c.region(mission.region_id).label, Calendar.span(left)]
	if left <= int(c.data.cfg("expiry_warning_hours", 12)):
		_window.add_theme_color_override("font_color", Palette.AMBER)
	if mission.revealed:
		_threat.text = "Confirmed: " + c.composition_text(mission.enemies)
	else:
		var tr: Vector2i = c.threat_range(mission)
		_threat.text = "Hostiles: %d–%d, composition unconfirmed" % [tr.x, tr.y]
	if mission.state != Mission.State.INFILTRATING:
		return
	var pct: float = c.infiltration(mission)
	_bar.value = pct * 100.0
	var to_full: int = ceili(maxf(0.0, (1.0 - pct) * mission.infil_hours))
	if pct < 1.0:
		_bar_text.text = "Infiltration %d%%  ·  full in %s" % [roundi(pct * 100.0), Calendar.span(to_full)]
	else:
		_bar_text.text = "Infiltration %d%%  ·  in position" % roundi(pct * 100.0)
	_launch.text = "Launch at %d%%" % roundi(pct * 100.0)
	_boost.text = "Boost +%d%% (%d intel)" % [
		roundi(float(c.data.cfg("boost_amount", 0.25)) * 100.0), int(c.data.cfg("boost_cost", 15))]
	_boost.disabled = not c.can_boost(mission)
