extends SceneTree
#
# Plays v0.1 through the real desk and checks what happened.
#
#   xvfb-run -a -s "-screen 0 1280x720x24" godot --script res://tools/play.gd
#   godot --headless --script res://tools/play.gd      (layout checks skipped)
#
# `verify sim` proves the simulation is right with no UI attached, which is
# exactly why it cannot see a button that does nothing, a planner taller than
# the window, or a report that never opens. This is the check that sees the
# game the player sees: it boots main.tscn, clicks the real buttons — with real
# mouse events whenever a display makes the layout trustworthy — and asks the
# running game what is true through tools/game_probe.gd.
#
# The desk's clock is stepped by hand at a fixed 1/30 s, so a run is
# reproducible: same seed, same clicks, same answers. The last check plays the
# whole thing twice and compares.

const STEP: float = 1.0 / 30.0
const MAX_STEPS: int = 20000
const SEED: int = 4242

var _failures: Array[String] = []
var _skipped: Array[String] = []
var _checks: int = 0
var _real_clicks: bool = false


func _init() -> void:
	var first: Dictionary = await _first_encounter(true)
	var second: Dictionary = await _first_encounter(false)
	_check("determinism", first == second, "two plays of seed %d with the same clicks diverged" % SEED)
	await _late_squad()
	await _report_headlines()

	print("")
	for line: String in _skipped:
		print("SKIP ", line)
	if _failures.is_empty():
		print("play: OK (%d checks, %d skipped)%s" % [_checks, _skipped.size(),
			"" if _real_clicks else " — buttons pressed by signal, no display for real clicks"])
		quit(0)
		return
	for line: String in _failures:
		printerr("FAIL ", line)
	printerr("play: %d of %d checks failed" % [_failures.size(), _checks])
	quit(1)


# --- the slice: sitting at the desk, getting a first encounter ---------------

func _first_encounter(full: bool) -> Dictionary:
	var desk: CommandDesk = await _boot()
	if desk == null:
		return {}
	var probe: GameProbe = GameProbe.new(desk)
	var c: Campaign = desk.campaign

	if full:
		_check("boot-script", desk.get_script() != null, "main.tscn has no script; it failed to compile")
		_check("boot-built", desk.get_child_count() > 0, "the desk built nothing")
		if probe.layout_is_trustworthy():
			_real_clicks = true
			var zero: Array = probe.zero_sized_controls()
			_check("desk-layout", zero.is_empty(), "zero-sized Controls: %s" % ", ".join(PackedStringArray(zero.slice(0, 5))))
			var off: Array = probe.offscreen_controls()
			_check("desk-onscreen", off.is_empty(), "Controls past the window edge: %s" % ", ".join(PackedStringArray(off.slice(0, 3))))
		else:
			_skipped.append("desk layout — needs a display; run under xvfb-run")
		_check("starts-paused", c.is_paused(), "the campaign started with the clock running")
		_check("roster-shown", probe.roster_rows() == c.soldiers.size(),
			"%d roster rows for %d soldiers" % [probe.roster_rows(), c.soldiers.size()])
		_check("board-empty", probe.ops_cards().is_empty() and probe.control("OpsList").get_child(0).visible,
			"the board is not showing its empty state at the start")
		_check("comms-opened", probe.text_of("CommsLog").contains("You have the desk"),
			"the comms log does not open with the briefing line")

		# The haven split, and Space as the clock — even with a button focused.
		await _click(desk, "HavenIntelButton")
		_check("haven-intel", c.home_haven().on_intel == 5, "+1 to intel left %d on intel" % c.home_haven().on_intel)
		await _press_space(desk)
		_check("space-runs", not c.is_paused(), "Space did not start the clock")
		_check("space-not-a-button", c.home_haven().on_intel == 5,
			"Space pressed the focused haven button (now %d on intel)" % c.home_haven().on_intel)
		await _press_space(desk)
		_check("space-pauses", c.is_paused(), "Space did not stop the clock")
		await _click(desk, "HavenSupplyButton")
		_check("haven-supply", c.home_haven().on_intel == 4, "+1 to supply left %d on intel" % c.home_haven().on_intel)

	# Scan until the haven finds something.
	await _click(desk, "SpeedButton_scan")
	_check("scan-runs", not c.is_paused(), "SCAN did not start the clock")
	await _run_until_paused(desk)
	_check("detected", c.last_interrupt == "mission_detected",
		"the first interrupt was '%s', not a detection" % c.last_interrupt)
	_check("detected-hour", c.hour == 15, "first detection at hour %d; data pins it at 15" % c.hour)
	var m: Mission = c.visible_missions()[0] if not c.visible_missions().is_empty() else null
	_check("on-the-board", m != null and probe.ops_cards().has("Op_%d" % m.id),
		"the detected operation has no card on the board")
	if m == null:
		desk.queue_free()
		return probe.snapshot()
	_check("comms-detected", probe.text_of("CommsLog").contains("OPERATION DETECTED"),
		"the detection did not reach the comms log")

	# Plan it.
	await _click(desk, "PlanButton_%d" % m.id)
	_check("planner-open", desk.planner != null and probe.overlay_visible(), "Plan operation did not open the planner")
	if full:
		if probe.layout_is_trustworthy():
			var off: Array = probe.offscreen_controls()
			_check("planner-onscreen", off.is_empty(), "planner runs past the window: %s" % ", ".join(PackedStringArray(off.slice(0, 3))))
		await _click(desk, "SpeedButton_fast", true)
		_check("modal-holds-clock", c.is_paused(), "the clock started while the planner was open")
		_check("dispatch-needs-squad", probe.button("DispatchButton").disabled, "Dispatch is live with nobody picked")
		await _click(desk, "Pick_okafor")
		_check("dispatch-needs-two", probe.button("DispatchButton").disabled, "Dispatch is live with one soldier")
		await _click(desk, "Pick_brandt")
		var blind: String = probe.all_text("MissionPlanner")
		_check("no-read-blind", not blind.contains("simulated") and blind.contains("Assessment: none"),
			"the planner offered an assessment without the composition")
		await _click(desk, "Pick_okafor")
		await _click(desk, "Pick_brandt")
	var intel_before: int = c.intel
	await _click(desk, "RevealButton")
	_check("reveal-costs", c.intel == intel_before - int(c.data.cfg("reveal_cost", 10)), "Reveal did not cost intel")
	_check("reveal-shows", probe.all_text("MissionPlanner").contains("Confirmed hostiles: 1× Warden, 1× Mimic, 1× Sentry Drone"),
		"the planner does not show the confirmed composition")
	for id: String in ["hale", "okafor", "brandt", "ruiz"]:
		await _click(desk, "Pick_%s" % id)
	var planner_text: String = probe.all_text("MissionPlanner")
	_check("estimate-shown", planner_text.contains("reaches 100% infiltration in 34h"),
		"the planner's infiltration estimate is missing or wrong")
	_check("assessment-shown", planner_text.contains("Assessment at full infiltration"),
		"no assessment with a revealed composition and a full squad")
	_check("dispatch-live", not probe.button("DispatchButton").disabled, "Dispatch is dead with four ready soldiers")
	await _click(desk, "DispatchButton")
	_check("planner-closed", desk.planner == null and not probe.overlay_visible(), "Dispatch did not close the planner")
	_check("infiltrating", m.state == Mission.State.INFILTRATING, "the operation is %s after dispatch" % Mission.STATE_NAMES[m.state])
	_check("deployed", probe.all_text("RosterList").count("Deployed") == 4, "the roster does not show four deployed")
	await _step(desk, 1)
	_check("launch-offered", probe.button("LaunchButton_%d" % m.id) != null, "the card offers no Launch")

	# Let them get in. Other operations may be found on the way; those
	# interrupts are fine, the clock is just started again.
	var guard: int = 0
	while c.infiltration(m) < 1.0 and m.state == Mission.State.INFILTRATING and guard < 20:
		await _click(desk, "SpeedButton_fast")
		await _run_until_paused(desk)
		guard += 1
	_check("in-position", c.infiltration(m) >= 1.0 and c.log_bus.has_type("infiltration_complete"),
		"the squad never reached 100%, or nobody said so")
	_check("in-position-paused", c.is_paused(), "reaching 100% did not stop the clock")

	# Launch, read the report, go back to the desk.
	await _click(desk, "LaunchButton_%d" % m.id)
	await _step(desk, 2)
	_check("report-open", desk.report != null and probe.overlay_visible(), "Launch did not open the after-action report")
	if desk.report == null:
		desk.queue_free()
		return probe.snapshot()
	if full and probe.layout_is_trustworthy():
		var off: Array = probe.offscreen_controls()
		_check("report-onscreen", off.is_empty(), "report runs past the window: %s" % ", ".join(PackedStringArray(off.slice(0, 3))))
	await _click(desk, "SkipButton")
	_check("report-complete", desk.report.is_fully_shown(), "Skip did not show the whole fight")
	var battle_text: String = probe.text_of("BattleLog")
	_check("report-worded", not battle_text.contains(LogText.FALLBACK_MARK), "a battle event reached the player unworded")
	_check("report-story", battle_text.contains("Contact.") and battle_text.contains("Spotted"),
		"the battle log is missing its contact or the Scout's spot")
	var outcome: String = m.outcome.to_upper()
	_check("report-headline", probe.text_of("Headline") == outcome,
		"headline '%s' but the operation resolved '%s'" % [probe.text_of("Headline"), outcome])
	var outcomes: Node = probe.control("SquadOutcomes")
	var rows: int = 0
	for child: Node in outcomes.get_children():
		if str(child.name).begins_with("Outcome_"):
			rows += 1
	_check("report-squad", rows == 4, "%d squad rows in the report for a squad of 4" % rows)
	_check_aftermath(c, m)
	await _click(desk, "CloseReportButton")
	_check("report-closed", desk.report == null and not probe.overlay_visible(), "Back to the desk did not close the report")
	_check("comms-worded", not probe.text_of("CommsLog").contains(LogText.FALLBACK_MARK),
		"a campaign event reached the comms log unworded")
	await _step(desk, 1)
	_check("card-gone", not probe.ops_cards().has("Op_%d" % m.id), "the fought operation is still on the board")

	var snap: Dictionary = probe.snapshot()
	desk.queue_free()
	await process_frame
	return snap


# The soldiers' states after the fight must be what the report says they are.
func _check_aftermath(c: Campaign, m: Mission) -> void:
	for id: String in m.squad:
		var s: Soldier = c.soldier(id)
		if s == null:
			_check("aftermath-%s" % id, false, "%s vanished from the campaign" % id)
			continue
		match s.status:
			Soldier.Status.KIA:
				_check("kia-%s" % id, c.fallen.has(s) and not c.soldiers.has(s), "%s is KIA but still on the roster" % id)
			Soldier.Status.WOUNDED:
				_check("wound-%s" % id, s.recover_at > c.hour, "%s is wounded with no recovery time" % id)
			Soldier.Status.INFILTRATING:
				_check("home-%s" % id, false, "%s is still marked deployed after the fight" % id)


# --- a squad too slow for its window -----------------------------------------
# The window closing must launch the operation and open the report on its own.

func _late_squad() -> void:
	var desk: CommandDesk = await _boot()
	var probe: GameProbe = GameProbe.new(desk)
	var c: Campaign = desk.campaign
	await _click(desk, "SpeedButton_scan")
	await _run_until_paused(desk)
	var m: Mission = c.visible_missions()[0]
	await _click(desk, "PlanButton_%d" % m.id)
	for id: String in ["okafor", "brandt", "ruiz", "chen", "novak", "achterberg"]:
		await _click(desk, "Pick_%s" % id)
	_check("late-warned", probe.all_text("MissionPlanner").contains("the window closes first"),
		"the planner did not warn that six without a Scout will be late")
	await _click(desk, "DispatchButton")
	var guard: int = 0
	while desk.report == null and guard < 30:
		await _click(desk, "SpeedButton_fast")
		await _run_until_paused(desk)
		await _step(desk, 2)
		guard += 1
	_check("late-report", desk.report != null, "the window closed on a squad and no report opened")
	_check("late-launched", c.log_bus.has_type("window_closing") and m.state == Mission.State.RESOLVED,
		"the window closed without launching the operation")
	desk.queue_free()
	await process_frame


# --- the report says what happened, whatever happened -------------------------
# The playthrough above only ever sees the outcome its seed produces, so a
# headline stuck on one word would pass it. This builds a report for each
# outcome directly and reads the headline back.

func _report_headlines() -> void:
	var desk: CommandDesk = await _boot()
	var c: Campaign = desk.campaign
	var m: Mission = c.mission(1)
	for outcome: int in [BattleResult.Outcome.VICTORY, BattleResult.Outcome.WITHDRAWN, BattleResult.Outcome.WIPED]:
		var r: BattleResult = BattleResult.new()
		r.outcome = outcome as BattleResult.Outcome
		r.roe = "standard"
		var report: BattleReport = BattleReport.new()
		desk.add_child(report)
		report.show_result(c, m, r)
		var head: Label = report.find_child("Headline", true, false) as Label
		var want: String = BattleResult.OUTCOME_NAMES[outcome].to_upper()
		_check("headline-%s" % want, head != null and head.text == want,
			"a %s report is headed '%s'" % [want, head.text if head != null else "<none>"])
		report.queue_free()
	desk.queue_free()
	await process_frame


# --- driving -----------------------------------------------------------------

func _boot() -> CommandDesk:
	var packed: PackedScene = load(str(ProjectSettings.get_setting("application/run/main_scene"))) as PackedScene
	_check("boot-loads", packed != null, "the main scene did not load")
	if packed == null:
		return null
	var desk: CommandDesk = packed.instantiate() as CommandDesk
	_check("boot-is-desk", desk != null, "the main scene is not the command desk")
	if desk == null:
		return null
	desk.seed_value = SEED
	root.add_child(desk)
	desk.set_process(false)
	for i: int in range(4):
		await process_frame
	return desk


func _step(desk: CommandDesk, n: int) -> void:
	for i: int in range(n):
		desk._process(STEP)
	await process_frame


func _run_until_paused(desk: CommandDesk) -> void:
	var steps: int = 0
	while not desk.campaign.is_paused() and steps < MAX_STEPS:
		desk._process(STEP)
		steps += 1
	desk._process(STEP)
	await process_frame
	await process_frame


# Clicks a button the way a player does: a real mouse press and release at its
# centre when there is a display to make the layout real — so a button hidden
# under the modal overlay, or laid out off-screen, fails to respond. Without a
# display it falls back to the signal, and says so in the summary.
func _click(desk: CommandDesk, node_name: String, expect_blocked: bool = false) -> void:
	var b: BaseButton = desk.find_child(node_name, true, false) as BaseButton
	_checks += 1
	if b == null or not b.is_visible_in_tree():
		_failures.append("click-%s: no visible button by that name" % node_name)
		return
	if b.disabled:
		_failures.append("click-%s: the button is disabled" % node_name)
		return
	if _real_clicks:
		var at: Vector2 = b.get_global_rect().get_center()
		for pressed: bool in [true, false]:
			var ev: InputEventMouseButton = InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = pressed
			ev.position = at
			ev.global_position = at
			root.push_input(ev, true)
	elif expect_blocked:
		pass   # without a display there is no overlay to block anything
	elif b is CheckBox:
		b.button_pressed = not b.button_pressed
	else:
		b.pressed.emit()
	await process_frame
	desk._process(0.0)


func _press_space(desk: CommandDesk) -> void:
	for pressed: bool in [true, false]:
		var ev: InputEventKey = InputEventKey.new()
		ev.keycode = KEY_SPACE
		ev.physical_keycode = KEY_SPACE
		ev.pressed = pressed
		root.push_input(ev, true)
	await process_frame
	desk._process(0.0)


func _check(id: String, ok: bool, detail: String) -> void:
	_checks += 1
	if not ok:
		_failures.append("%s: %s" % [id, detail])
