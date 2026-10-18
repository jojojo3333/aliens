extends PanelContainer
class_name MissionPlanner

# Planning an operation: the decisions that, with no tactical layer, *are* the
# fight. Who goes, against what (if intel has been spent to find out), how long
# they will take to get in against how long the window stays open, and when
# they are allowed to pull out. Every number on this screen comes from the same
# functions the autoresolve uses; nothing here is a second estimate.

signal finished

var _c: Campaign = null
var _m: Mission = null
var _picks: Dictionary = {}   # soldier id -> CheckBox
var _roe: String = "standard"
var _roe_buttons: Dictionary = {}

var _threat: Label = null
var _reveal: Button = null
var _estimate: Label = null
var _roe_brief: Label = null
var _assess: Label = null
var _error: Label = null
var _dispatch: Button = null


func open(c: Campaign, m: Mission) -> void:
	_c = c
	_m = m
	name = "MissionPlanner"
	custom_minimum_size = Vector2(800.0, 0.0)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)

	col.add_child(Palette.label("PLAN OPERATION  ·  " + m.label.to_upper(), Palette.AMBER, 20))
	col.add_child(Palette.label("%s  ·  window closes %s (in %s)" % [
		c.region(m.region_id).label, Calendar.stamp(c.start(), m.expires_at),
		Calendar.span(m.hours_left(c.hour))], Palette.DIM, 13))
	col.add_child(Palette.wrapped(str(c.data.template(m.template_id).get("brief", "")), Palette.TEXT, 14))
	col.add_child(HSeparator.new())

	var intel_row: HBoxContainer = HBoxContainer.new()
	col.add_child(intel_row)
	_threat = Palette.wrapped("", Palette.TEXT, 14)
	intel_row.add_child(_threat)
	_reveal = Button.new()
	_reveal.name = "RevealButton"
	_reveal.custom_minimum_size = Vector2(250.0, 30.0)
	_reveal.pressed.connect(_on_reveal)
	intel_row.add_child(_reveal)
	col.add_child(HSeparator.new())

	var sq: Dictionary = c.data.cfg("squad", {}) as Dictionary
	col.add_child(Palette.header("Squad — pick %d to %d" % [int(sq.get("min", 2)), int(sq.get("max", 6))]))
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0.0, 196.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list: VBoxContainer = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 0)
	scroll.add_child(list)
	for s: Soldier in c.soldiers:
		var st: Dictionary = s.stats(c.data)
		var box: CheckBox = CheckBox.new()
		box.name = "Pick_%s" % s.id
		box.text = "%s  —  %s  ·  HP %d  Aim %d  ·  %s" % [
			s.full_name(c.data), s.class_name_text(c.data), int(st["hp"]), int(st["aim"]),
			str(c.data.class_def(s.class_id).get("perk", ""))]
		if not s.is_ready():
			box.disabled = true
			box.text += "   [%s]" % Soldier.STATUS_NAMES[s.status]
		box.add_theme_font_size_override("font_size", 13)
		box.toggled.connect(func(_on: bool) -> void: _update())
		list.add_child(box)
		_picks[s.id] = box

	_estimate = Palette.wrapped("", Palette.TEXT, 14)
	col.add_child(_estimate)
	col.add_child(HSeparator.new())

	col.add_child(Palette.header("Rules of engagement"))
	var roe_row: HBoxContainer = HBoxContainer.new()
	col.add_child(roe_row)
	var group: ButtonGroup = ButtonGroup.new()
	for id: String in ["cautious", "standard", "hold"]:
		var b: Button = Button.new()
		b.name = "RoeButton_%s" % id
		b.text = str(c.data.roe_def(id).get("name", id))
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(110.0, 30.0)
		b.button_pressed = id == _roe
		b.pressed.connect(func() -> void:
			_roe = id
			_update())
		roe_row.add_child(b)
		_roe_buttons[id] = b
	_roe_brief = Palette.wrapped("", Palette.DIM, 13)
	roe_row.add_child(_roe_brief)

	_assess = Palette.wrapped("", Palette.TEXT, 14)
	col.add_child(_assess)
	_error = Palette.wrapped("", Palette.HOSTILE, 13)
	col.add_child(_error)

	var buttons: HBoxContainer = HBoxContainer.new()
	col.add_child(buttons)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	var cancel: Button = Button.new()
	cancel.name = "CancelPlanButton"
	cancel.text = "Back to the desk"
	cancel.custom_minimum_size = Vector2(150.0, 34.0)
	cancel.pressed.connect(func() -> void: finished.emit())
	buttons.add_child(cancel)
	_dispatch = Button.new()
	_dispatch.name = "DispatchButton"
	_dispatch.custom_minimum_size = Vector2(190.0, 34.0)
	_dispatch.pressed.connect(_on_dispatch)
	buttons.add_child(_dispatch)
	_update()


func selected_ids() -> Array[String]:
	var out: Array[String] = []
	for s: Soldier in _c.soldiers:
		var box: CheckBox = _picks.get(s.id, null) as CheckBox
		if box != null and box.button_pressed and not box.disabled:
			out.append(s.id)
	return out


func _update() -> void:
	var cost: int = int(_c.data.cfg("reveal_cost", 10))
	if _m.revealed:
		_threat.text = "Confirmed hostiles: " + _c.composition_text(_m.enemies)
		_threat.add_theme_color_override("font_color", Palette.HOSTILE)
		_reveal.text = "Composition confirmed"
	else:
		var tr: Vector2i = _c.threat_range(_m)
		_threat.text = "Hostiles: %d–%d. Composition unconfirmed — Mimics, if any, will not show up on a count." % [tr.x, tr.y]
		_reveal.text = "Reveal composition (%d intel)" % cost
	_reveal.disabled = not _c.can_reveal(_m)

	var ids: Array[String] = selected_ids()
	var sq: Dictionary = _c.data.cfg("squad", {}) as Dictionary
	var lo: int = int(sq.get("min", 2))
	var hi: int = int(sq.get("max", 6))
	var window: int = _m.hours_left(_c.hour)
	if ids.is_empty():
		_estimate.text = "Pick a squad. Bigger squads hit harder and take longer to get in."
		_estimate.add_theme_color_override("font_color", Palette.DIM)
	else:
		var hours: float = _c.infiltration_hours(ids, _m)
		var need: int = ceili(hours)
		if hours <= float(window):
			_estimate.text = "Squad of %d reaches 100%% infiltration in %s — %s before the window closes. Every hour past that thins the opposition." % [
				ids.size(), Calendar.span(need), Calendar.span(window - need)]
			_estimate.add_theme_color_override("font_color", Palette.GOOD)
		else:
			_estimate.text = "Squad of %d needs %s; the window closes first, at %d%%. Under 100%% the machines get reinforcements. Send fewer, add a Scout, or plan to boost." % [
				ids.size(), Calendar.span(need), roundi(float(window) / hours * 100.0)]
			_estimate.add_theme_color_override("font_color", Palette.AMBER)

	_roe_brief.text = str(_c.data.roe_def(_roe).get("brief", ""))

	if ids.size() < lo:
		_assess.text = ""
	elif not _m.revealed:
		_assess.text = "Assessment: none. Without the composition there is nothing to assess — reveal it to get a read."
		_assess.add_theme_color_override("font_color", Palette.DIM)
	else:
		var a: Dictionary = _c.assess(_m.id, ids, _roe)
		var rate: float = float(a["win_rate"])
		var word: String = "Grim"
		var col: Color = Palette.HOSTILE
		if rate >= 0.8:
			word = "Favourable"
			col = Palette.GOOD
		elif rate >= 0.55:
			word = "Fair"
			col = Palette.GOOD
		elif rate >= 0.3:
			word = "Risky"
			col = Palette.AMBER
		_assess.text = "Assessment at full infiltration: %s. This squad wins %d of %d simulated engagements, %.1f dead on average." % [
			word, int(a["wins"]), int(a["runs"]), float(a["dead"])]
		_assess.add_theme_color_override("font_color", col)

	_dispatch.text = "Dispatch squad (%d)" % ids.size()
	_dispatch.disabled = ids.size() < lo or ids.size() > hi
	if ids.size() > hi:
		_error.text = "A squad is at most %d." % hi
	else:
		_error.text = ""


func _on_reveal() -> void:
	_c.reveal(_m.id)
	_update()


func _on_dispatch() -> void:
	var err: String = _c.dispatch(_m.id, selected_ids(), _roe)
	if err != "":
		_error.text = err
		return
	finished.emit()
