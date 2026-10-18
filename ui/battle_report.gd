extends PanelContainer
class_name BattleReport

# The after-action report. With no tactical layer this is the only view of the
# fight the player gets, so it does two jobs: it tells the story — the log plays
# out a line at a time, like a comms feed — and it accounts for every outcome,
# so a loss can be traced back to the decision that caused it.

signal closed

const LINES_PER_SECOND: float = 12.0

var _lines: PackedStringArray = PackedStringArray()
var _shown: int = 0
var _clock: float = 0.0
var _log: RichTextLabel = null
var _squad_box: VBoxContainer = null
var _skip: Button = null


func show_result(c: Campaign, m: Mission, r: BattleResult) -> void:
	name = "BattleReport"
	custom_minimum_size = Vector2(1060.0, 600.0)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)

	var colour: Color = Palette.AMBER
	match r.outcome:
		BattleResult.Outcome.VICTORY:
			colour = Palette.GOOD
		BattleResult.Outcome.WIPED:
			colour = Palette.HOSTILE
	var head: Label = Palette.label(BattleResult.OUTCOME_NAMES[r.outcome].to_upper(), colour, 26)
	head.name = "Headline"
	col.add_child(head)
	col.add_child(Palette.label("%s  ·  %s  ·  infiltration %d%%  ·  ROE %s  ·  %d exchange%s  ·  %d of %d hostiles destroyed" % [
		m.label, c.region(m.region_id).label, LogText.pct(r.infiltration),
		str(c.data.roe_def(r.roe).get("name", r.roe)), r.rounds, "" if r.rounds == 1 else "s",
		r.hostiles_destroyed,
		r.hostiles_total], Palette.DIM, 13))
	col.add_child(HSeparator.new())

	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	col.add_child(body)
	_log = RichTextLabel.new()
	_log.name = "BattleLog"
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size = Vector2(620.0, 440.0)
	_log.add_theme_font_size_override("normal_font_size", 13)
	_log.add_theme_font_size_override("bold_font_size", 13)
	body.add_child(_log)

	_squad_box = VBoxContainer.new()
	_squad_box.name = "SquadOutcomes"
	_squad_box.custom_minimum_size = Vector2(360.0, 0.0)
	_squad_box.add_theme_constant_override("separation", 6)
	_squad_box.modulate = Color(1, 1, 1, 0)
	body.add_child(_squad_box)
	_squad_box.add_child(Palette.header("Squad"))
	for u: BattleUnit in r.units:
		if u.side != BattleUnit.SQUAD:
			continue
		_squad_box.add_child(_soldier_row(c, u, r))
	_squad_box.add_child(HSeparator.new())
	if r.rewards.is_empty():
		_squad_box.add_child(Palette.wrapped("Nothing recovered.", Palette.DIM, 13))
	else:
		_squad_box.add_child(Palette.wrapped("Recovered: +%d supplies, +%d intel." % [
			int(r.rewards.get("supplies", 0)), int(r.rewards.get("intel", 0))], Palette.GOOD, 13))

	var buttons: HBoxContainer = HBoxContainer.new()
	col.add_child(buttons)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	_skip = Button.new()
	_skip.name = "SkipButton"
	_skip.text = "Skip to the end"
	_skip.custom_minimum_size = Vector2(150.0, 34.0)
	_skip.pressed.connect(reveal_all)
	buttons.add_child(_skip)
	var back: Button = Button.new()
	back.name = "CloseReportButton"
	back.text = "Back to the desk"
	back.custom_minimum_size = Vector2(170.0, 34.0)
	back.pressed.connect(func() -> void: closed.emit())
	buttons.add_child(back)

	_lines = LogText.battle_lines(r)


func is_fully_shown() -> bool:
	return _shown >= _lines.size()


func reveal_all() -> void:
	while _shown < _lines.size():
		_show_next()
	_finish()


func _process(delta: float) -> void:
	if is_fully_shown():
		return
	_clock += delta
	while _clock >= 1.0 / LINES_PER_SECOND and not is_fully_shown():
		_clock -= 1.0 / LINES_PER_SECOND
		_show_next()
	if is_fully_shown():
		_finish()


func _show_next() -> void:
	_log.append_text(_lines[_shown] + "\n")
	_shown += 1


func _finish() -> void:
	_squad_box.modulate = Color.WHITE
	_skip.disabled = true


func _soldier_row(c: Campaign, u: BattleUnit, r: BattleResult) -> Control:
	var s: Soldier = c.soldier(u.key)
	var res: Dictionary = r.soldier_results.get(u.key, {}) as Dictionary
	var after: Dictionary = r.aftermath.get(u.key, {}) as Dictionary
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "Outcome_%s" % u.key
	box.add_theme_constant_override("separation", 0)
	var top: HBoxContainer = HBoxContainer.new()
	box.add_child(top)
	var who: Label = Palette.label(s.full_name(c.data) if s != null else u.label, Palette.SQUAD, 14)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(who)
	var status: String = str(after.get("status", "unhurt"))
	var text: String = "Unhurt"
	var colour: Color = Palette.GOOD
	match status:
		"kia":
			text = "KIA"
			colour = Palette.HOSTILE
		"grave":
			text = "Gravely wounded · %s" % Calendar.span(int(after.get("recover_hours", 0)))
			colour = Palette.AMBER
		"wounded":
			text = "Wounded · %s" % Calendar.span(int(after.get("recover_hours", 0)))
			colour = Palette.AMBER
	top.add_child(Palette.label(text, colour, 13))
	var detail: String = "%d/%d hits · %d damage · %d kill%s · took %d of %d HP" % [
		int(res.get("hits", 0)), int(res.get("shots", 0)), int(res.get("damage", 0)),
		int(res.get("kills", 0)), "" if int(res.get("kills", 0)) == 1 else "s",
		int(res.get("hp_lost", 0)), int(res.get("max_hp", 0))]
	if str(after.get("promoted", "")) != "":
		detail += " · promoted to " + str(after["promoted"])
	box.add_child(Palette.label(detail, Palette.DIM, 12))
	return box
