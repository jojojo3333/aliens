extends Control
class_name CommandDesk

# The command desk — the one screen of v0.1, and the screen the whole game is
# meant to be played from. Roster and haven on the left, the theatre in the
# middle with the comms log under it, the operations board on the right, the
# clock across the top. Planning and the after-action report open over it.
#
# This file draws what Campaign reports and turns clicks into calls back into
# Campaign. It decides nothing about the game.

var seed_value: int = 0   # 0 picks a fresh seed; tools/play.gd sets one
var campaign: Campaign = null

var planner: MissionPlanner = null
var report: BattleReport = null

var _date: Label = null
var _supplies: Label = null
var _intel: Label = null
var _seed: Label = null
var _speed_buttons: Dictionary = {}   # mode -> Button
var _roster_box: VBoxContainer = null
var _roster_head: Label = null
var _fallen: Label = null
var _haven_name: Label = null
var _haven_intel: Label = null
var _haven_supply: Label = null
var _haven_effect: Label = null
var _ops_box: VBoxContainer = null
var _ops_empty: Label = null
var _map: MapView = null
var _log: RichTextLabel = null
var _overlay: Control = null
var _overlay_center: CenterContainer = null

var _rows: Dictionary = {}    # soldier id -> RosterRow
var _cards: Dictionary = {}   # mission id -> OpsCard
var _seen_revision: int = -1
var _pending_reports: Array = []   # [mission_id, BattleResult]


func _ready() -> void:
	theme = Palette.build_theme()
	campaign = Campaign.new(GameData.load_all(), _seed_from_args())
	_build()
	campaign.log_bus.event_appended.connect(_append_log)
	campaign.battle_resolved.connect(_on_battle_resolved)
	for e: LogEvent in campaign.log_bus.events:
		_append_log(e)
	_rebuild_lists()
	_refresh()


func _seed_from_args() -> int:
	if seed_value != 0:
		return seed_value
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = args.find("--seed")
	if i >= 0 and i + 1 < args.size():
		return int(args[i + 1])
	return 0


func _process(delta: float) -> void:
	if not modal_open():
		campaign.advance(delta)
	if campaign.revision != _seen_revision:
		_rebuild_lists()
	_refresh()
	if report == null and planner == null and not _pending_reports.is_empty():
		_show_report(_pending_reports.pop_front() as Array)


# Space is the clock, and it is taken in _input — ahead of the GUI — on purpose.
# Space is also ui_accept, so in _unhandled_input it would never arrive while a
# button had focus: it would press that button instead. Click "+1 to intel",
# reach for Space to pause, and a second rebel moves to intel.
func _input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or modal_open():
		return
	if key.keycode == KEY_SPACE:
		campaign.set_speed("scan" if campaign.is_paused() else "pause")
		get_viewport().set_input_as_handled()


func modal_open() -> bool:
	return _overlay != null and _overlay.visible


# --- building ---------------------------------------------------------------

func _build() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.name = "Background"
	bg.color = Palette.BG
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var frame: MarginContainer = MarginContainer.new()
	frame.name = "Frame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		frame.add_theme_constant_override("margin_" + side, 10)
	add_child(frame)
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	frame.add_child(root)
	root.add_child(_build_top_bar())
	var body: HBoxContainer = HBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	root.add_child(body)
	body.add_child(_build_left())
	body.add_child(_build_center())
	body.add_child(_build_right())

	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	add_child(_overlay)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.66)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)
	_overlay_center = CenterContainer.new()
	_overlay_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(_overlay_center)


func _section(title: String, panel_name: String) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = panel_name
	var col: VBoxContainer = VBoxContainer.new()
	col.add_child(Palette.header(title))
	panel.add_child(col)
	return col


func _build_top_bar() -> Control:
	var bar: PanelContainer = PanelContainer.new()
	bar.name = "TopBar"
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	bar.add_child(row)

	var title: VBoxContainer = VBoxContainer.new()
	title.add_theme_constant_override("separation", 0)
	title.add_child(Palette.label("COMMAND DESK", Palette.SQUAD, 18))
	title.add_child(Palette.label("%s  ·  v0.1" % str(campaign.data.cfg("title", "")), Palette.DIM, 11))
	row.add_child(title)

	_date = Palette.label("", Palette.TEXT, 18)
	_date.name = "DateLabel"
	_date.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_date)
	_supplies = Palette.label("", Palette.TEXT, 15)
	_supplies.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_supplies)
	_intel = Palette.label("", Palette.TEXT, 15)
	_intel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_intel)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_seed = Palette.label("", Palette.FAINT, 11)
	_seed.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_seed)

	var speeds: HBoxContainer = HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 4)
	row.add_child(speeds)
	var group: ButtonGroup = ButtonGroup.new()
	for mode: String in ["pause", "scan", "fast"]:
		var b: Button = Button.new()
		b.name = "SpeedButton_%s" % mode
		b.text = mode.to_upper()
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(78.0, 34.0)
		b.tooltip_text = str({"pause": "Stop the clock (Space)", "scan": "Let time pass (Space)",
			"fast": "Let time pass quickly"}[mode])
		b.pressed.connect(_on_speed.bind(mode))
		speeds.add_child(b)
		_speed_buttons[mode] = b
	return bar


func _build_left() -> Control:
	var col: VBoxContainer = VBoxContainer.new()
	col.name = "LeftColumn"
	col.custom_minimum_size = Vector2(318.0, 0.0)
	col.add_theme_constant_override("separation", 8)

	var roster: VBoxContainer = _section("Roster", "RosterPanel")
	var roster_panel: Control = roster.get_parent() as Control
	roster_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_roster_head = Palette.label("", Palette.TEXT, 13)
	roster.add_child(_roster_head)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	roster.add_child(scroll)
	_roster_box = VBoxContainer.new()
	_roster_box.name = "RosterList"
	_roster_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_roster_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_roster_box)
	_fallen = Palette.wrapped("", Palette.DIM, 12)
	roster.add_child(_fallen)
	col.add_child(roster_panel)

	var haven: VBoxContainer = _section("Haven", "HavenPanel")
	_haven_name = Palette.label("", Palette.SQUAD, 14)
	haven.add_child(_haven_name)
	_haven_intel = Palette.label("", Palette.TEXT, 14)
	haven.add_child(_job_row(_haven_intel, "intel", "HavenIntelButton"))
	_haven_supply = Palette.label("", Palette.TEXT, 14)
	haven.add_child(_job_row(_haven_supply, "supply", "HavenSupplyButton"))
	_haven_effect = Palette.wrapped("", Palette.DIM, 12)
	haven.add_child(_haven_effect)
	col.add_child(haven.get_parent() as Control)
	return col


func _job_row(value: Label, job: String, button_name: String) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value)
	var b: Button = Button.new()
	b.name = button_name
	b.text = "+1 to %s" % job
	b.custom_minimum_size = Vector2(112.0, 28.0)
	b.pressed.connect(_on_reassign.bind(job))
	row.add_child(b)
	return row


func _build_center() -> Control:
	var col: VBoxContainer = VBoxContainer.new()
	col.name = "CenterColumn"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	_map = MapView.new()
	_map.name = "Map"
	_map.campaign = campaign
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.custom_minimum_size = Vector2(420.0, 300.0)
	col.add_child(_map)

	var comms: VBoxContainer = _section("Comms log", "LogPanel")
	var comms_panel: Control = comms.get_parent() as Control
	comms_panel.custom_minimum_size = Vector2(0.0, 196.0)
	_log = RichTextLabel.new()
	_log.name = "CommsLog"
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 13)
	_log.add_theme_font_size_override("bold_font_size", 13)
	comms.add_child(_log)
	col.add_child(comms_panel)
	return col


func _build_right() -> Control:
	var ops: VBoxContainer = _section("Operations", "OpsPanel")
	var panel: Control = ops.get_parent() as Control
	panel.custom_minimum_size = Vector2(330.0, 0.0)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ops.add_child(scroll)
	_ops_box = VBoxContainer.new()
	_ops_box.name = "OpsList"
	_ops_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ops_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_ops_box)
	_ops_empty = Palette.wrapped(
		"Nothing on the board. The machines are always doing something — the haven's intel rebels just have not found it yet. Scan to let time pass.",
		Palette.DIM, 13)
	_ops_box.add_child(_ops_empty)
	return panel


# --- refreshing -------------------------------------------------------------

func _rebuild_lists() -> void:
	_seen_revision = campaign.revision
	for row: Variant in _rows.values():
		(row as Node).queue_free()
	_rows.clear()
	for s: Soldier in campaign.soldiers:
		var row: RosterRow = RosterRow.new()
		row.bind(s, campaign.data)
		_roster_box.add_child(row)
		_rows[s.id] = row

	for card: Variant in _cards.values():
		(card as Node).queue_free()
	_cards.clear()
	for m: Mission in campaign.visible_missions():
		var card: OpsCard = OpsCard.new()
		card.bind(campaign, m)
		card.plan_requested.connect(_open_planner)
		card.launch_requested.connect(_on_launch)
		card.boost_requested.connect(_on_boost)
		_ops_box.add_child(card)
		_cards[m.id] = card
	_ops_empty.visible = _cards.is_empty()

	if campaign.fallen.is_empty():
		_fallen.text = ""
	else:
		var names: Array[String] = []
		for s: Soldier in campaign.fallen:
			names.append(s.full_name(campaign.data))
		_fallen.text = "Fallen: " + ", ".join(names)


func _refresh() -> void:
	_date.text = Calendar.long_stamp(campaign.start(), campaign.hour)
	_supplies.text = "SUPPLIES  %d" % campaign.supplies
	_intel.text = "INTEL  %d" % campaign.intel
	_seed.text = "seed %d" % campaign.rng.seed_value

	var mode: String = "pause" if campaign.is_paused() else campaign.speed
	for m: String in _speed_buttons:
		(_speed_buttons[m] as Button).set_pressed_no_signal(m == mode)

	var ready_count: int = campaign.ready_soldiers().size()
	_roster_head.text = "%d ready of %d" % [ready_count, campaign.soldiers.size()]
	for row: Variant in _rows.values():
		(row as RosterRow).refresh(campaign)

	var h: Haven = campaign.home_haven()
	if h != null:
		_haven_name.text = "%s  ·  %d rebels" % [h.label, h.rebels()]
		_haven_intel.text = "Intel     %d" % h.on_intel
		_haven_supply.text = "Supply    %d" % h.on_supply
		var drop: Dictionary = Calendar.next_month_start(campaign.start(), campaign.hour)
		_haven_effect.text = "Intel rebels find operations (%.0f progress/h) and earn %d intel a day. Supply rebels pay out at the drop: +%d supplies on %s." % [
			campaign.detection_rate(h), h.on_intel * int(campaign.data.cfg("intel_per_rebel_day", 0)),
			campaign.supply_forecast(), Calendar.day_stamp(drop)]

	for card: Variant in _cards.values():
		(card as OpsCard).refresh(campaign)


func _append_log(e: LogEvent) -> void:
	_log.append_text(LogText.campaign_line(e, campaign) + "\n")


# --- orders -----------------------------------------------------------------

func _on_speed(mode: String) -> void:
	if modal_open():
		return
	campaign.set_speed(mode)


func _on_reassign(job: String) -> void:
	var h: Haven = campaign.home_haven()
	if h != null:
		campaign.reassign(h.region_id, job)


func _on_launch(mission_id: int) -> void:
	campaign.launch(mission_id)


func _on_boost(mission_id: int) -> void:
	campaign.boost(mission_id)


func _open_planner(mission_id: int) -> void:
	var m: Mission = campaign.mission(mission_id)
	if m == null or modal_open():
		return
	campaign.set_speed("pause")
	planner = MissionPlanner.new()
	_overlay_center.add_child(planner)
	planner.open(campaign, m)
	planner.finished.connect(_close_planner)
	_overlay.visible = true


func _close_planner() -> void:
	if planner != null:
		planner.queue_free()
		planner = null
	_overlay.visible = false


func _on_battle_resolved(mission_id: int, result: BattleResult) -> void:
	_pending_reports.append([mission_id, result])


func _show_report(entry: Array) -> void:
	campaign.set_speed("pause")
	report = BattleReport.new()
	_overlay_center.add_child(report)
	report.show_result(campaign, campaign.mission(int(entry[0])), entry[1] as BattleResult)
	report.closed.connect(_close_report)
	_overlay.visible = true


func _close_report() -> void:
	if report != null:
		report.queue_free()
		report = null
	_overlay.visible = false
