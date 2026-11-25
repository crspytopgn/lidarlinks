class_name DailyBoard
extends RefCounted
## The daily round's online leaderboard (server/src/board.js): one board a
## UTC day, ranked by strokes, each player's best round. A finished daily
## round is sent as its result code (RoundRecord.to_code, a few KB), so the
## server checks it's that day's round and anyone's game can re-run it.


## The board's address for `date` ("2026-11-25") on `base`.
static func url(base: String, date: String) -> String:
	return "%s/boards/daily-%s" % [base, date]


## The body that sends a finished daily round.
static func submission(record: RoundRecord, player: String, par: int) -> String:
	return JSON.stringify({"token": OnlineSettings.token(), "name": player, "par": par, "code": record.to_code()})


## "1st", "2nd", "3rd", "11th", "22nd".
static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = ["th", "st", "nd", "rd", "th", "th", "th", "th", "th", "th"][n % 10]
	return "%d%s" % [n, suffix]


## The line the end of a daily round shows for the server's answer.
static func reply_text(d: Dictionary) -> String:
	if d.has("error"):
		return "Daily leaderboard: %s." % d.error
	var rank := int(d.get("rank", 0))
	var count := int(d.get("count", 0))
	if rank <= 0:
		return ""
	var text := "Daily leaderboard: %s of %d." % [ordinal(rank), count]
	if not bool(d.get("improved", true)):
		text += " (Your best today still stands.)"
	return text


## A board's rows as text lines: "1  Ann  35 (-1)". Shows to par when the
## board knows the course's par.
static func rows(d: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var par := int(d.get("par", 0))
	for e: Variant in d.get("entries", []):
		if not e is Dictionary:
			continue
		var strokes := int(e.get("strokes", 0))
		var line := "%-4s %-20s %d" % [ordinal(int(e.get("rank", 0))), str(e.get("name", "?")), strokes]
		if par > 0:
			line += "  (%s)" % Scorecard.format_to_par(strokes - par)
		out.append(line)
	return out
