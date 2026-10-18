extends RefCounted
class_name LogText

# Turns LogEvents into the words the player reads. sim/ never formats text; this
# is the one place that does, for the comms log and the after-action report
# alike. An event type with no wording here falls through to its raw name, which
# is ugly on purpose — tools/play.gd fails on any line that reaches the fallback.

const FALLBACK_MARK: String = "<?>"


static func campaign_line(e: LogEvent, c: Campaign) -> String:
	var v: Dictionary = e.values
	var when: String = Palette.tint(Calendar.stamp(c.start(), e.t), Palette.FAINT)
	return "%s  %s" % [when, campaign_body(e.type, v)]


static func campaign_body(type: String, v: Dictionary) -> String:
	match type:
		"campaign_start":
			return "You have the desk, Commander. %s in the %s is on the line. %d soldiers on the roster, nothing on the board yet. [b]Scan[/b] and let the haven's eyes work." % [
				str(v["haven"]), str(v["region"]), int(v["soldiers"])]
		"mission_detected":
			return "%s %s — %s. %s's network picked it up. Window closes in %s." % [
				Palette.tint("OPERATION DETECTED", Palette.AMBER), _b(str(v["mission"])),
				str(v["region"]), str(v["haven"]), Calendar.span(int(v["hours"]))]
		"mission_missed":
			return Palette.tint("Missed: ", Palette.AMBER) + "a %s in the %s came and went. Nobody spotted it in time." % [
				str(v["mission"]).to_lower(), str(v["region"])]
		"mission_expired":
			return Palette.tint("Window closed: ", Palette.AMBER) + "%s. No squad went." % str(v["mission"])
		"expiry_warning":
			if bool(v["infiltrating"]):
				return Palette.tint("Window closing: ", Palette.AMBER) + "%s in %s. Squad at %d%% — launch, or they go in when it shuts." % [
					_b(str(v["mission"])), Calendar.span(int(v["hours"])), pct(float(v["infiltration"]))]
			return Palette.tint("Window closing: ", Palette.AMBER) + "%s in %s, and nobody is on it." % [
				_b(str(v["mission"])), Calendar.span(int(v["hours"]))]
		"squad_dispatched":
			return "Squad out to %s: %s. Full infiltration in %s. Rules of engagement: %s." % [
				_b(str(v["mission"])), Palette.tint(str(v["squad"]), Palette.SQUAD),
				Calendar.span(int(v["hours"])), str(v["roe"])]
		"infiltration_complete":
			return Palette.tint("In position: ", Palette.GOOD) + "%s squad at 100%%. Launch now for the ambush, or wait — past 100%% they slip hostiles. %s left." % [
				_b(str(v["mission"])), Calendar.span(int(v["hours"]))]
		"window_closing":
			return Palette.tint("Window shut: ", Palette.AMBER) + "%s squad goes in at %d%%." % [
				_b(str(v["mission"])), pct(float(v["infiltration"]))]
		"intel_reveal":
			return "Intel spent (%d): %s confirmed as %s." % [
				int(v["cost"]), _b(str(v["mission"])), Palette.tint(str(v["composition"]), Palette.HOSTILE)]
		"intel_boost":
			return "Intel spent (%d): %s infiltration boosted to %d%%." % [
				int(v["cost"]), _b(str(v["mission"])), pct(float(v["infiltration"]))]
		"mission_launched":
			return "Launching %s at %d%% infiltration." % [_b(str(v["mission"])), pct(float(v["infiltration"]))]
		"mission_result":
			var outcome: String = str(v["outcome"])
			var col: Color = Palette.GOOD if outcome == "Victory" else (Palette.HOSTILE if outcome == "Squad lost" else Palette.AMBER)
			return "%s — %s. %d of %d hostiles destroyed, %d dead." % [
				_b(str(v["mission"])), Palette.tint(outcome.to_upper(), col),
				int(v["destroyed"]), int(v["total"]), int(v["kia"])]
		"rewards":
			return "Recovered from %s: %s supplies, %s intel." % [
				str(v["mission"]), Palette.tint("+%d" % int(v["supplies"]), Palette.GOOD),
				Palette.tint("+%d" % int(v["intel"]), Palette.GOOD)]
		"soldier_kia":
			return Palette.tint("KIA: ", Palette.HOSTILE) + "%s did not come back from %s." % [
				_b(str(v["soldier"])), str(v["mission"])]
		"soldier_wounded":
			var kind: String = "Gravely wounded" if bool(v["grave"]) else "Wounded"
			return Palette.tint(kind + ": ", Palette.AMBER) + "%s, out for %s." % [
				str(v["soldier"]), Calendar.span(int(v["hours"]))]
		"soldier_recovered":
			return Palette.tint("Back on duty: ", Palette.GOOD) + str(v["soldier"]) + "."
		"soldier_promoted":
			return Palette.tint("Promoted: ", Palette.GOOD) + "%s to %s." % [str(v["soldier"]), str(v["rank"])]
		"supply_drop":
			return Palette.tint("Supply drop: ", Palette.GOOD) + "+%d supplies (%d on hand)." % [
				int(v["amount"]), int(v["total"])]
	return "%s %s %s" % [FALLBACK_MARK, type, str(v)]


static func battle_lines(r: BattleResult) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for e: LogEvent in r.events:
		out.append(battle_line(e))
	return out


static func battle_line(e: LogEvent) -> String:
	var v: Dictionary = e.values
	match e.type:
		"b_contact":
			return "Contact. Squad of %d against %d hostiles; infiltration %d%%." % [
				int(v["squad"]), int(v["hostiles"]), pct(float(v["infiltration"]))]
		"b_slipped":
			return Palette.tint("Over-infiltrated: ", Palette.GOOD) + "the squad slipped past %s." % _h(str(v["enemies"]))
		"b_reinforced":
			return Palette.tint("Compromised on the way in: ", Palette.AMBER) + "%s joined the patrol." % _h(str(v["enemies"]))
		"b_spotted":
			return Palette.tint("Spotted: ", Palette.GOOD) + "%s clocks the %s before it gets close." % [
				_s(str(v["soldier"])), _h(str(v["enemy"]))]
		"b_unmasked":
			return Palette.tint("Unmasked: ", Palette.HOSTILE) + "a refugee at the roadside turns — it was a %s." % _h(str(v["enemy"]))
		"b_ambush":
			return Palette.tint("Ambush. ", Palette.GOOD) + "The squad opens fire first, from cover, with the advantage."
		"b_caught":
			return Palette.tint("Caught moving. ", Palette.AMBER) + "The machines were waiting — they act first every round."
		"b_round":
			return "\n" + Palette.tint("— Exchange %d —" % int(v["n"]), Palette.DIM)
		"b_miss":
			return Palette.tint("%s misses %s (%d%%)." % [
				_plain(str(v["attacker"])), _plain(str(v["target"])), int(v["chance"])], Palette.DIM)
		"b_hit":
			var squad_shot: bool = int(v["side"]) == BattleUnit.SQUAD
			var who: String = _s(str(v["attacker"])) if squad_shot else _h(str(v["attacker"]))
			var whom: String = _h(str(v["target"])) if squad_shot else _s(str(v["target"]))
			var extra: PackedStringArray = PackedStringArray()
			if bool(v["crit"]):
				extra.append("critical")
			if int(v["bonus"]) > 0:
				extra.append("EMP +%d" % int(v["bonus"]))
			if int(v["soak"]) > 0:
				extra.append("armour −%d" % int(v["soak"]))
			# Not square brackets: RichTextLabel would read them as BBCode.
			var note: String = " — %s" % ", ".join(extra) if not extra.is_empty() else ""
			var tail: String = ""
			if bool(v["fell"]):
				tail = Palette.tint(" Destroyed." if squad_shot else " DOWN.", Palette.GOOD if squad_shot else Palette.HOSTILE)
			return "%s hits %s for %d (%d%%)%s.%s" % [who, whom, int(v["damage"]), int(v["chance"]), note, tail]
		"b_withdraw":
			return "\n" + Palette.tint("Withdrawing: ", Palette.AMBER) + withdraw_reason(str(v["reason"]))
		"b_extracted":
			return Palette.tint("The squad breaks contact and gets out.", Palette.AMBER)
		"b_victory":
			return "\n" + Palette.tint("Last machine down. The field is ours.", Palette.GOOD)
		"b_wiped":
			return "\n" + Palette.tint("No one left standing. The machines hold the field.", Palette.HOSTILE)
		"b_stabilized":
			return Palette.tint("Carried out: ", Palette.AMBER) + "%s is stabilised on the way back." % _s(str(v["soldier"]))
		"b_bled_out":
			return Palette.tint("Lost: ", Palette.HOSTILE) + "%s dies before the squad reaches the haven." % _s(str(v["soldier"]))
		"b_lost":
			return Palette.tint("Lost: ", Palette.HOSTILE) + "%s is left on the field." % _s(str(v["soldier"]))
	return "%s %s %s" % [FALLBACK_MARK, e.type, str(v)]


static func withdraw_reason(reason: String) -> String:
	match reason:
		"first_down":
			return "someone is down, and the orders were cautious."
		"heavy_damage":
			return "the squad has taken a third of its strength in wounds, and the orders were cautious."
		"half_down":
			return "half the squad is down."
		"outnumbered":
			return "the squad is outnumbered."
		"stalemate":
			return "the fight has bogged down, and the machines can wait longer than we can."
	return reason


static func pct(f: float) -> int:
	return roundi(f * 100.0)


static func _b(text: String) -> String:
	return "[b]%s[/b]" % text


static func _s(text: String) -> String:
	return Palette.tint(text, Palette.SQUAD)


static func _h(text: String) -> String:
	return Palette.tint(text, Palette.HOSTILE)


static func _plain(text: String) -> String:
	return text
