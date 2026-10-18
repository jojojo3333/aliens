extends HBoxContainer
class_name RosterRow

# One soldier on the desk's roster: who, what, and whether they can go.

var soldier: Soldier = null

var _name: Label = null
var _class: Label = null
var _status: Label = null


func bind(s: Soldier, data: GameData) -> void:
	soldier = s
	name = "Soldier_%s" % s.id
	_name = Palette.label(s.title(data))
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.clip_text = true
	add_child(_name)
	_class = Palette.label(s.class_name_text(data), Palette.DIM, 12)
	_class.custom_minimum_size = Vector2(76.0, 0.0)
	add_child(_class)
	_status = Palette.label("", Palette.GOOD, 12)
	_status.custom_minimum_size = Vector2(84.0, 0.0)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_status)
	var st: Dictionary = s.stats(data)
	tooltip_text = "%s — %s\nHP %d · Aim %d · Defence %d · Damage %d–%d\n%s\nMissions %d · Kills %d · XP %d" % [
		s.full_name(data), s.class_name_text(data), int(st["hp"]), int(st["aim"]),
		int(st["defense"]), int(st["dmg_min"]), int(st["dmg_max"]),
		str(data.class_def(s.class_id).get("perk", "")), s.missions, s.kills, s.xp]


func refresh(c: Campaign) -> void:
	_name.text = soldier.title(c.data)
	match soldier.status:
		Soldier.Status.READY:
			_status.text = "Ready"
			_status.add_theme_color_override("font_color", Palette.GOOD)
		Soldier.Status.INFILTRATING:
			_status.text = "Deployed"
			_status.add_theme_color_override("font_color", Palette.SQUAD)
		Soldier.Status.WOUNDED:
			_status.text = "Hurt · %s" % Calendar.span(soldier.recover_at - c.hour)
			_status.add_theme_color_override("font_color", Palette.AMBER)
		_:
			_status.text = "KIA"
			_status.add_theme_color_override("font_color", Palette.HOSTILE)
