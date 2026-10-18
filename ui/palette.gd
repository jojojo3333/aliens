extends RefCounted
class_name Palette

# Colours and the one Theme every screen uses. The look is a dim operations
# room: cold slate panels, teal for the squad, red for the machines, amber for
# anything that wants a decision. Colour is never the only carrier of meaning —
# every state it marks is also spelled out in words and in the comms log.

const BG: Color = Color("0a0e11")
const PANEL: Color = Color("11171c")
const BUTTON: Color = Color("18222a")
const BUTTON_HOVER: Color = Color("1f2d37")
const BUTTON_DOWN: Color = Color("21394a")
const LINE: Color = Color("2a3843")
const TEXT: Color = Color("c6d0d6")
const DIM: Color = Color("74838d")
const FAINT: Color = Color("3b4852")
const SQUAD: Color = Color("5fb8cc")
const HOSTILE: Color = Color("d65a4a")
const AMBER: Color = Color("d8a443")
const GOOD: Color = Color("86b56c")


static func hex(c: Color) -> String:
	return c.to_html(false)


static func tint(text: String, c: Color) -> String:
	return "[color=#%s]%s[/color]" % [hex(c), text]


static func build_theme() -> Theme:
	var t: Theme = Theme.new()
	t.default_font_size = 14

	var panel: StyleBoxFlat = box(PANEL, LINE, 10, 8)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	t.set_stylebox("normal", "Button", box(BUTTON, LINE, 10, 5))
	t.set_stylebox("hover", "Button", box(BUTTON_HOVER, SQUAD.darkened(0.35), 10, 5))
	t.set_stylebox("pressed", "Button", box(BUTTON_DOWN, SQUAD, 10, 5))
	t.set_stylebox("hover_pressed", "Button", box(BUTTON_DOWN, SQUAD, 10, 5))
	t.set_stylebox("disabled", "Button", box(PANEL, Color("1c252c"), 10, 5))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", SQUAD)
	t.set_color("font_hover_pressed_color", "Button", SQUAD)
	t.set_color("font_disabled_color", "Button", FAINT)

	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	t.set_color("font_pressed_color", "CheckBox", SQUAD)
	t.set_color("font_hover_pressed_color", "CheckBox", SQUAD)
	t.set_color("font_disabled_color", "CheckBox", FAINT)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(state, "CheckBox", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 4, 2))
	t.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())

	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	t.set_stylebox("focus", "RichTextLabel", StyleBoxEmpty.new())

	var bar_bg: StyleBoxFlat = box(Color("0c1114"), LINE, 0, 0)
	var bar_fill: StyleBoxFlat = box(SQUAD.darkened(0.25), Color(0, 0, 0, 0), 0, 0)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_color("font_color", "ProgressBar", TEXT)

	var sep: StyleBoxLine = StyleBoxLine.new()
	sep.color = LINE
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 6)

	t.set_constant("separation", "VBoxContainer", 6)
	t.set_constant("separation", "HBoxContainer", 8)
	return t


static func box(bg: Color, border: Color, pad_x: int, pad_y: int) -> StyleBoxFlat:
	var b: StyleBoxFlat = StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(1 if border.a > 0.0 else 0)
	b.set_corner_radius_all(2)
	b.content_margin_left = pad_x
	b.content_margin_right = pad_x
	b.content_margin_top = pad_y
	b.content_margin_bottom = pad_y
	return b


static func label(text: String, color: Color = TEXT, font_size: int = 14) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	return l


# A section header: small, spaced, dim.
static func header(text: String) -> Label:
	var l: Label = label(text.to_upper(), DIM, 12)
	return l


static func wrapped(text: String, color: Color = TEXT, font_size: int = 14) -> Label:
	var l: Label = label(text, color, font_size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l
