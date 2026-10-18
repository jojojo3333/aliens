extends SceneTree
#
# Renders the desk at the four moments of v0.1 and writes PNGs. Needs a display:
#
#   xvfb-run -a godot --script res://tools/screenshot.gd -- --out /tmp/desk
#
# It proves pixels were drawn and panels landed where they should. It cannot
# say whether anything feels good — nothing in a GPU-less container can, and a
# headless screenshot is never evidence of feel.

const SETTLE_FRAMES: int = 10
const SEED: int = 4242


func _init() -> void:
	var out: String = _arg("--out", "/tmp/desk")
	var desk: CommandDesk = (load("res://main.tscn") as PackedScene).instantiate() as CommandDesk
	desk.seed_value = SEED
	root.add_child(desk)
	desk.set_process(false)
	await _settle()
	await _shot(out + "-1-desk.png")

	var c: Campaign = desk.campaign
	c.set_speed("scan")
	var reason: String = c.run_hours(200)
	desk._process(0.0)
	await _settle()
	await _shot(out + "-2-detected.png")

	var m: Mission = c.visible_missions()[0]
	(desk.find_child("PlanButton_%d" % m.id, true, false) as Button).pressed.emit()
	await _settle()
	(desk.find_child("RevealButton", true, false) as Button).pressed.emit()
	for id: String in ["hale", "okafor", "brandt", "ruiz"]:
		(desk.find_child("Pick_%s" % id, true, false) as CheckBox).button_pressed = true
	desk._process(0.0)
	await _settle()
	await _shot(out + "-3-planner.png")

	(desk.find_child("DispatchButton", true, false) as Button).pressed.emit()
	desk._process(0.0)
	c.set_speed("scan")
	while c.infiltration(m) < 1.0 and m.state == Mission.State.INFILTRATING:
		c.run_hours(1)
	c.run_hours(4)
	desk._process(0.0)
	await _settle()
	await _shot(out + "-3b-infiltrating.png")

	c.launch(m.id)
	desk._process(0.0)
	await _settle()
	(desk.find_child("SkipButton", true, false) as Button).pressed.emit()
	await _settle()
	await _shot(out + "-4-report.png")
	print("screenshots written to %s-*.png (first interrupt: %s)" % [out, reason])
	quit(0)


func _settle() -> void:
	for i: int in range(SETTLE_FRAMES):
		await process_frame


func _shot(path: String) -> void:
	await process_frame
	var image: Image = root.get_texture().get_image()
	image.save_png(path)


func _arg(flag: String, fallback: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var i: int = args.find(flag)
	if i >= 0 and i + 1 < args.size():
		return args[i + 1]
	return fallback
