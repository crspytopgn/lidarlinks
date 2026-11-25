class_name PlayerStats
extends RefCounted
## Everything played on this device, kept on this device (user://stats.cfg;
## the browser keeps it with the page's own storage): play time, launches,
## days played, rounds, holes, shots, scores by type, drives, putts, clubs
## and courses. The Stats page (StatsPanel) and the desktop launcher's Stats
## tab show it. Each player's own rounds, handicap and records stay in
## PlayerProfiles; this is the device's whole history, finished or not.
##
## Only the person's own shots count: never a computer golfer's, nor another
## player's online. Nothing here is ever sent anywhere; the only thing that
## leaves the device is PlayCount's anonymous 15-minute mark, which
## Settings > Play-time count turns off.
##
## It is also the one play-time clock: Support's once-ever thank-you line
## and PlayCount both read it. The clock runs while a round or the range is
## on screen, the game has focus, nothing is paused, and the person has
## touched a key, the mouse, the screen or a pad in the last IDLE_S.

## Where the stats are kept; the tests point this somewhere else.
static var file := "user://stats.cfg"
## Support's file from before the stats (support.cfg [support] played_s):
## its play time is carried over once.
static var support_path := "user://support.cfg"

## No input for this long and the clock stops (the person walked away).
const IDLE_S := 300.0
## Play time is written out after this much more (and at round ends).
const SAVE_EVERY_S := 60.0
## Days of play time kept for the chart (a year).
const KEEP_DAYS := 366
## Score names by strokes against par, best first (holes in one apart).
const SCORE_KEYS := ["condor", "albatross", "eagle", "birdie", "par", "bogey", "double", "worse"]

static var _cfg: ConfigFile = null
static var _unsaved_s := 0.0
static var _launched := false


static func _data() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(file)
		_carry_over_support()
	return _cfg


## Reads the file again (the tests, or another copy of the game wrote it).
## Not "reload": that is GDScript's own, and would reset the static vars.
static func reread() -> void:
	_cfg = null
	_unsaved_s = 0.0


static func save() -> void:
	if _cfg != null:
		_cfg.save(file)
	_unsaved_s = 0.0


static func _carry_over_support() -> void:
	if _cfg.get_value("time", "support_carried", false):
		return
	var old := ConfigFile.new()
	if old.load(support_path) == OK:
		var s := float(old.get_value("support", "played_s", 0.0))
		_cfg.set_value("time", "play_s", maxf(float(_cfg.get_value("time", "play_s", 0.0)), s))
	_cfg.set_value("time", "support_carried", true)


static func get_int(section: String, key: String) -> int:
	return int(_data().get_value(section, key, 0))


static func get_float(section: String, key: String) -> float:
	return float(_data().get_value(section, key, 0.0))


static func _add(section: String, key: String, n := 1) -> void:
	_data().set_value(section, key, get_int(section, key) + n)


## Adds to a total kept with decimals (metres, seconds).
static func _addf(section: String, key: String, x: float) -> void:
	_data().set_value(section, key, get_float(section, key) + x)


static func _keep_max(section: String, key: String, value: float) -> bool:
	if value <= get_float(section, key):
		return false
	_data().set_value(section, key, value)
	return true


static func _today() -> String:
	return Time.get_date_string_from_system()


# --- Play time ----------------------------------------------------------------

## Total play time in seconds.
static func play_seconds() -> float:
	return get_float("time", "play_s")


## Adds play time (main.gd calls it each frame the clock runs).
static func add_play_time(seconds: float, day := "") -> void:
	if seconds <= 0.0:
		return
	var c := _data()
	c.set_value("time", "play_s", play_seconds() + seconds)
	if day.is_empty():
		day = _today()
	var days: Dictionary = c.get_value("time", "daily", {})
	if not days.has(day):
		_add("time", "days")
		if str(c.get_value("time", "first_day", "")).is_empty():
			c.set_value("time", "first_day", day)
	days[day] = float(days.get(day, 0.0)) + seconds
	if days.size() > KEEP_DAYS:
		var keys := days.keys()
		keys.sort()
		for k in keys.slice(0, keys.size() - KEEP_DAYS):
			days.erase(k)
	c.set_value("time", "daily", days)
	c.set_value("time", "last_day", day)
	_unsaved_s += seconds
	if _unsaved_s >= SAVE_EVERY_S:
		save()


## Seconds played on each of the last `n` days, oldest first, ending today.
static func recent_days(n: int, today := "") -> Array[float]:
	var days: Dictionary = _data().get_value("time", "daily", {})
	var end := Time.get_unix_time_from_datetime_string(today if not today.is_empty() else _today())
	var out: Array[float] = []
	for i in range(n - 1, -1, -1):
		var d := Time.get_date_string_from_unix_time(end - i * 86400)
		out.append(float(days.get(d, 0.0)))
	return out


## "12 h 40 min", "35 min", "under a minute".
static func format_time(seconds: float) -> String:
	var m := int(seconds / 60.0)
	if m < 1:
		return "under a minute"
	if m < 60:
		return "%d min" % m
	return "%d h %d min" % [m / 60, m % 60] if m % 60 != 0 else "%d h" % (m / 60)


# --- What was played --------------------------------------------------------

## The game was started (boot.gd; counted once a run, however often the
## menu opens). Also brings the launcher's summary up to date.
static func note_launch() -> void:
	if _launched:
		return
	_launched = true
	_add("time", "launches")
	write_summary()


## A round started on `course` (practice too: `kind` is "round", "range"
## or "putting").
static func note_round_start(course: String, kind := "round") -> void:
	if kind == "round":
		_add("rounds", "started")
		var courses: Dictionary = _data().get_value("courses", "rounds", {})
		courses[course] = int(courses.get(course, 0)) + 1
		_data().set_value("courses", "rounds", courses)
	else:
		_add("practice", kind + "_sessions")
	save()


## A round played to its last hole: `holes` long, `strokes` in all.
static func note_round_done(course: String, holes: int, strokes: int, to_par: int) -> void:
	_add("rounds", "finished")
	if holes >= 18:
		_add("rounds", "finished_18")
	elif holes >= 9:
		_add("rounds", "finished_9")
	var best: Dictionary = _data().get_value("courses", "best", {})
	var key := "%s|%d" % [course, holes]
	if holes >= 9 and (not best.has(key) or to_par < int((best[key] as Dictionary).get("to_par", 999))):
		best[key] = {"strokes": strokes, "to_par": to_par, "date": _today()}
		_data().set_value("courses", "best", best)
	save()


## A hole finished: par `par`, `strokes` taken (picked up holes count as
## played, not as a score).
static func note_hole(course: String, par: int, strokes: int, picked_up: bool) -> void:
	_add("holes", "played")
	var courses: Dictionary = _data().get_value("courses", "holes", {})
	courses[course] = int(courses.get(course, 0)) + 1
	_data().set_value("courses", "holes", courses)
	var last: Dictionary = _data().get_value("courses", "last", {})
	last[course] = _today()
	_data().set_value("courses", "last", last)
	if picked_up or strokes <= 0:
		_add("holes", "picked_up")
		return
	_add("holes", "scored")
	_add("holes", "strokes", strokes)
	_add("holes", "par", par)
	if strokes == 1:
		_add("scores", "ace")
	_add("scores", score_key(strokes, par))


## "birdie", "par", "double"... for `strokes` on a par `par`.
static func score_key(strokes: int, par: int) -> String:
	var under := par - strokes
	if under >= 4:
		return "condor"
	if under <= -3:
		return "worse"
	return SCORE_KEYS[4 - under]


## A shot of the person's: `club` its short name ("Dr", "7i", "Pt"),
## `carry_m`/`total_m` how far it went, `holed` in the hole from `from_pin_m`,
## `tee_driver` a driver off the tee that stayed in play, `fairway` its tee
## shot found the fairway (-1: not a fairway hole), `penalty` water or out of
## bounds. Returns what it beat: "drive", "putt", "holed" or "".
static func note_shot(club: String, total_m: float, putter: bool, holed: bool, from_pin_m: float,
		tee_driver: bool, fairway: int, penalty: String) -> String:
	_add("shots", "total")
	var clubs: Dictionary = _data().get_value("clubs", "used", {})
	clubs[club] = int(clubs.get(club, 0)) + 1
	_data().set_value("clubs", "used", clubs)
	var beat := ""
	if putter:
		_add("putts", "total")
		if holed:
			_add("putts", "holed")
			_addf("putts", "holed_m", from_pin_m)
			if _keep_max("putts", "longest_holed_m", from_pin_m):
				beat = "putt"
	else:
		_addf("shots", "distance_m", total_m)
		if holed:
			_add("shots", "holed_out")
			if _keep_max("shots", "longest_holed_m", from_pin_m):
				beat = "holed"
	if tee_driver:
		_add("drives", "count")
		_addf("drives", "total_m", total_m)
		if _keep_max("drives", "longest_m", total_m):
			beat = "drive"
	if fairway >= 0:
		_add("drives", "fairway_holes")
		if fairway == 1:
			_add("drives", "fairways")
	if penalty == "water" or penalty == "out":
		_add("shots", penalty)
	return beat


## A green hit in regulation, once a hole.
static func note_green(in_regulation: bool) -> void:
	_add("holes", "gir_holes")
	if in_regulation:
		_add("holes", "gir")


## A ball hit on the range or the putting green.
static func note_practice_ball() -> void:
	_add("practice", "balls")


# --- Reading it back ------------------------------------------------------------

## The club hit most (not counting the putter), or "".
static func favourite_club() -> String:
	var clubs: Dictionary = _data().get_value("clubs", "used", {})
	var best := ""
	for c: String in clubs:
		if c == "Pt":
			continue
		if best.is_empty() or int(clubs[c]) > int(clubs[best]):
			best = c
	return best


## Courses played, most holes first: [[name, holes, rounds], ...].
static func courses() -> Array:
	var holes: Dictionary = _data().get_value("courses", "holes", {})
	var rounds: Dictionary = _data().get_value("courses", "rounds", {})
	var out: Array = []
	for c: String in holes:
		out.append([c, int(holes[c]), int(rounds.get(c, 0))])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1] or (a[1] == b[1] and a[0] < b[0]))
	return out


## Best score per course and length: [[course, holes, strokes, to_par, date], ...],
## longest rounds first, then by course.
static func best_rounds() -> Array:
	var best: Dictionary = _data().get_value("courses", "best", {})
	var out: Array = []
	for key: String in best:
		var e: Dictionary = best[key]
		var cut := key.rfind("|")
		out.append([key.substr(0, cut), int(key.substr(cut + 1)), int(e.get("strokes", 0)), int(e.get("to_par", 0)), str(e.get("date", ""))])
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1] or (a[1] == b[1] and a[0] < b[0]))
	return out


## The headline numbers, as the Stats page and the launcher show them:
## [[label, value], ...]. Empty values are left out.
static func headline() -> Array:
	var out: Array = []
	var play := play_seconds()
	out.append(["Time played", format_time(play)])
	var launches := get_int("time", "launches")
	if launches > 0:
		out.append(["Sessions", str(launches)])
	if get_int("time", "days") > 0:
		out.append(["Days played", str(get_int("time", "days"))])
	out.append(["Rounds finished", "%d of %d started" % [get_int("rounds", "finished"), get_int("rounds", "started")]])
	out.append(["Holes played", str(get_int("holes", "played"))])
	out.append(["Shots", str(get_int("shots", "total"))])
	var scored := get_int("holes", "scored")
	if scored > 0:
		var tp := get_int("holes", "strokes") - get_int("holes", "par")
		out.append(["Scoring", "%.2f a hole against par (%s per 18)" % [float(tp) / scored, _signed(18.0 * tp / scored)]])
	var fh := get_int("drives", "fairway_holes")
	if fh > 0:
		out.append(["Fairways hit", "%d%% (%d of %d)" % [roundi(100.0 * get_int("drives", "fairways") / fh), get_int("drives", "fairways"), fh]])
	var gh := get_int("holes", "gir_holes")
	if gh > 0:
		out.append(["Greens in regulation", "%d%% (%d of %d)" % [roundi(100.0 * get_int("holes", "gir") / gh), get_int("holes", "gir"), gh]])
	if scored > 0 and get_int("putts", "total") > 0:
		out.append(["Putts", "%.1f per 18" % (18.0 * get_int("putts", "total") / maxi(1, get_int("holes", "played") - get_int("holes", "picked_up")))])
	if get_float("drives", "longest_m") > 0.0:
		out.append(["Longest drive", Units.long(get_float("drives", "longest_m"))])
	if get_int("drives", "count") > 0:
		out.append(["Average drive", "%s (%d drives)" % [Units.long(get_float("drives", "total_m") / get_int("drives", "count")), get_int("drives", "count")]])
	if get_float("putts", "longest_holed_m") > 0.0:
		out.append(["Longest putt holed", Units.short(get_float("putts", "longest_holed_m"))])
	if get_float("shots", "longest_holed_m") > 0.0:
		out.append(["Longest hole-out", Units.long(get_float("shots", "longest_holed_m"))])
	var counts: Array[String] = []
	for pair: Array in [["ace", "hole in one", "holes in one"], ["albatross", "albatross", "albatrosses"], ["eagle", "eagle", "eagles"], ["birdie", "birdie", "birdies"], ["par", "par", "pars"]]:
		var n := get_int("scores", pair[0])
		if n > 0:
			counts.append("%d %s" % [n, pair[1] if n == 1 else pair[2]])
	if not counts.is_empty():
		out.append(["Scores", ", ".join(counts)])
	if get_float("shots", "distance_m") > 0.0:
		var d := get_float("shots", "distance_m")
		out.append(["Ball hit in all", ("%.1f km" % (d / 1000.0)) if Units.metric else ("%.1f miles" % (d / 1609.344))])
	var fav := favourite_club()
	if not fav.is_empty():
		out.append(["Favourite club", fav])
	var penalties: Array[String] = []
	if get_int("shots", "water") > 0:
		penalties.append("%d in the water" % get_int("shots", "water"))
	if get_int("shots", "out") > 0:
		penalties.append("%d out of bounds" % get_int("shots", "out"))
	if not penalties.is_empty():
		out.append(["Lost balls", ", ".join(penalties)])
	var c := courses()
	if not c.is_empty():
		out.append(["Courses played", "%d (most: %s)" % [c.size(), c[0][0]]])
	if get_int("practice", "balls") > 0:
		out.append(["Practice balls", str(get_int("practice", "balls"))])
	var first := str(_data().get_value("time", "first_day", ""))
	if not first.is_empty():
		out.append(["Playing since", first])
	return out


## Writes what the desktop launcher's Stats tab shows into the file's
## [summary], already worded (so the launcher, a separate small project,
## shows the same numbers in the person's units without the game's code):
## rows (headline), best rounds, players with their handicap index and recent
## differentials, and the last 30 days of play.
static func write_summary() -> void:
	var c := _data()
	c.set_value("summary", "rows", headline())
	c.set_value("summary", "best", best_rounds())
	var players: Array = []
	var profiles := PlayerProfiles.load_saved()
	for n in profiles.names():
		var diffs := profiles.differentials(n)
		var played := profiles.rounds(n)
		players.append({
			"name": n, "index": Handicap.format(profiles.index_of(n)), "rounds": played.size(),
			"last": str(played.back().get("date", "")) if not played.is_empty() else "",
			"trend": index_trend(diffs),
			"records": PlayerProfiles.records_text(profiles.records(n)),
			"career": PlayerProfiles.career_text(profiles.career(n)),
		})
	c.set_value("summary", "players", players)
	c.set_value("summary", "days", recent_days(30))
	c.set_value("summary", "updated", Time.get_datetime_string_from_system(false, true))
	save()


## The handicap index after each round (tenths), from the third round on:
## the last 20 of them.
static func index_trend(diffs: Array[int]) -> Array[int]:
	var out: Array[int] = []
	for k in range(1, diffs.size() + 1):
		var i := Handicap.index(diffs.slice(0, k))
		if i != Handicap.NONE:
			out.append(i)
	return out.slice(maxi(0, out.size() - 20))


static func _signed(v: float) -> String:
	return ("+%.1f" % v) if v > 0.05 else ("%.1f" % v)


## Starts the stats again from nothing (the Stats page's Reset). The
## play-count state is kept.
static func reset() -> void:
	var c := _data()
	var keep := {"pending": c.get_value("count", "pending", 0), "noticed": c.get_value("count", "noticed", false)}
	for s in c.get_sections():
		c.erase_section(s)
	c.set_value("time", "support_carried", true)
	c.set_value("count", "pending", keep.pending)
	c.set_value("count", "noticed", keep.noticed)
	save()
