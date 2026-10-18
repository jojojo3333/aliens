extends Control
class_name MapView

# The theatre map in the middle of the desk.
#
# **Placeholder art, drawn in code.** A strategy map is a plate — terrain,
# coastlines, borders — and it belongs in assets/ the way a ship plate does in
# Deadweight. Until there is one, this draws an abstract node map so the state
# on top of it has somewhere to sit. Everything that *changes* is state and
# stays code-drawn when the plate arrives: contact, haven, Custodian presence,
# operations and squads in the field.

var campaign: Campaign = null

var _pulse: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _process(delta: float) -> void:
	# Wall-clock, and purely cosmetic: it only drives the marker pulse and never
	# reaches the simulation.
	_pulse = fmod(_pulse + delta, 2.0)
	queue_redraw()


func region_point(r: Region) -> Vector2:
	var inset: Vector2 = Vector2(70.0, 54.0)
	var span: Vector2 = size - inset * 2.0
	return inset + Vector2(r.pos.x * span.x, r.pos.y * span.y)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("0d1317"))
	var grid: Color = Color("16212899")
	var step: float = 48.0
	var x: float = step
	while x < size.x:
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), grid, 1.0)
		x += step
	var y: float = step
	while y < size.y:
		draw_line(Vector2(0.0, y), Vector2(size.x, y), grid, 1.0)
		y += step
	draw_rect(Rect2(Vector2.ZERO, size), Palette.LINE, false, 1.0)

	var font: Font = get_theme_default_font()
	draw_string(font, Vector2(12.0, 20.0), "THEATRE  ·  WESTERN EUROPE", HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 11, Palette.DIM)
	draw_string(font, Vector2(12.0, size.y - 10.0), "placeholder map — terrain plate pending",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, Palette.FAINT)

	if campaign == null:
		return

	for r: Region in campaign.regions:
		for n_id: String in r.neighbors:
			var n: Region = campaign.region(n_id)
			if n != null and r.id < n.id:
				var lit: bool = r.contacted or n.contacted
				draw_line(region_point(r), region_point(n),
					Palette.SQUAD.darkened(0.55) if lit else Palette.FAINT, 2.0 if lit else 1.0)

	for r: Region in campaign.regions:
		_draw_region(r, font)

	var slot: Dictionary = {}
	for m: Mission in campaign.visible_missions():
		var r: Region = campaign.region(m.region_id)
		if r == null:
			continue
		var k: int = int(slot.get(r.id, 0))
		slot[r.id] = k + 1
		# A row above the region, clear of its name and of the neighbours' labels.
		_draw_mission(m, region_point(r) + Vector2(-16.0 + 34.0 * k, -66.0), font)


func _draw_region(r: Region, font: Font) -> void:
	var p: Vector2 = region_point(r)
	var radius: float = 30.0
	var fill: Color = Color("15303a") if r.contacted else Color("151b20")
	var edge: Color = Palette.SQUAD if r.contacted else Palette.FAINT
	draw_circle(p, radius, fill)
	draw_arc(p, radius, 0.0, TAU, 48, edge, 2.0 if r.contacted else 1.0)
	draw_string(font, p + Vector2(-90.0, radius + 18.0), r.label.to_upper(), HORIZONTAL_ALIGNMENT_CENTER,
		180.0, 12, Palette.TEXT if r.contacted else Palette.DIM)

	# Custodian presence, as pips under the name. Shown, not yet simulated.
	var pips: int = 5
	var start: Vector2 = p + Vector2(-float(pips - 1) * 6.0, radius + 30.0)
	for i: int in range(pips):
		var c: Color = Palette.HOSTILE.darkened(0.15) if i < r.strength else Palette.FAINT
		draw_rect(Rect2(start + Vector2(i * 12.0 - 4.0, 0.0), Vector2(8.0, 4.0)), c)

	if r.contacted and r.haven != null:
		draw_rect(Rect2(p - Vector2(7.0, 7.0), Vector2(14.0, 14.0)), Palette.SQUAD)
		draw_string(font, p + Vector2(-60.0, -radius - 6.0), "HAVEN", HORIZONTAL_ALIGNMENT_CENTER,
			120.0, 10, Palette.SQUAD)
	else:
		draw_string(font, p + Vector2(-60.0, 4.0), "NO CONTACT", HORIZONTAL_ALIGNMENT_CENTER,
			120.0, 9, Palette.FAINT)


func _draw_mission(m: Mission, at: Vector2, font: Font) -> void:
	var glow: float = 0.5 + 0.5 * cos(_pulse * PI)
	if m.state == Mission.State.DETECTED:
		var s: float = 10.0
		var diamond: PackedVector2Array = PackedVector2Array([
			at + Vector2(0, -s), at + Vector2(s, 0), at + Vector2(0, s), at + Vector2(-s, 0)])
		draw_colored_polygon(diamond, Palette.AMBER)
		draw_arc(at, s + 4.0 + 4.0 * glow, 0.0, TAU, 32, Color(Palette.AMBER, 0.6 * (1.0 - glow)), 2.0)
		draw_string(font, at + Vector2(-40.0, -16.0), Calendar.span(m.hours_left(campaign.hour)),
			HORIZONTAL_ALIGNMENT_CENTER, 80.0, 10, Palette.AMBER)
	else:
		var pct: float = campaign.infiltration(m)
		draw_circle(at, 9.0, Color("102a33"))
		draw_arc(at, 12.0, -PI / 2.0, -PI / 2.0 + TAU * minf(pct, 1.0), 32, Palette.SQUAD, 3.0)
		if pct > 1.0:
			draw_arc(at, 16.0, -PI / 2.0, -PI / 2.0 + TAU * minf(pct - 1.0, 1.0), 32, Palette.GOOD, 2.0)
		draw_string(font, at + Vector2(-40.0, -20.0), "%d%%" % roundi(pct * 100.0),
			HORIZONTAL_ALIGNMENT_CENTER, 80.0, 10, Palette.SQUAD)
