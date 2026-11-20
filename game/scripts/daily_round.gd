class_name DailyRound
extends RefCounted
## The daily round: one built-in course, its hole positions, the wind and
## every random draw the same for everyone each day (by the UTC date), so
## players can compare the same round. No mulligans or gimmes. The best
## score each day is kept in user://daily.cfg; an online leaderboard can
## read the same date and seed later.

const PATH := "user://daily.cfg"
## Wind for the day, drawn from these (Wind.Level values) by the seed.
const WIND_LEVELS := [1, 2, 2, 3, 3, 4]


## Today's date, "2026-11-19", in UTC so everyone's day turns together.
static func today() -> String:
	return Time.get_date_string_from_system(true)


static func seed_for(date: String) -> int:
	return (hash("lidarlinks-daily-" + date) & 0x7fffffff) | 1


## The built-in courses the day is drawn from ("" is Kettle Hollow): every
## copy of the game has them.
static func courses() -> Array[String]:
	var out: Array[String] = [""]
	var epic: Array = PlaceholderCourseLoader.EPIC.keys()
	epic.sort()
	for k: String in epic:
		out.append(k)
	return out


static func course_for(date: String) -> String:
	var all := courses()
	return all[posmod(seed_for(date), all.size())]


static func course_title(key: String) -> String:
	return PlaceholderCourseLoader.NAME if key.is_empty() else str(PlaceholderCourseLoader.EPIC.get(key, key))


## The day's round for `player`.
static func setup(date: String, player: String) -> RoundSetup:
	var s := RoundSetup.new()
	var key := course_for(date)
	var day_seed := seed_for(date)
	s.course_key = key
	s.course_name = course_title(key)
	s.mode = GameModes.Mode.STROKE
	s.holes = RoundSetup.Holes.FRONT_NINE
	s.tees = RoundSetup.Tees.MIDDLE
	s.pins = 1  # random hole positions, picked by the seed
	s.round_seed = day_seed
	s.wind_level = WIND_LEVELS[posmod(day_seed >> 8, WIND_LEVELS.size())]
	s.names.assign([player])
	s.teams.assign([0])
	s.computer.assign([RoundSetup.HUMAN])
	s.daily = date
	return s


## Keeps `to_par` for `date` if it is the best yet; returns the best.
static func record(date: String, to_par: int, path := PATH) -> int:
	var cfg := ConfigFile.new()
	cfg.load(path)
	var best := int(cfg.get_value("best", date, 999))
	if to_par < best:
		best = to_par
		cfg.set_value("best", date, best)
	cfg.set_value("played", date, int(cfg.get_value("played", date, 0)) + 1)
	cfg.save(path)
	return best


## The best score for `date`, or 999 if it hasn't been played.
static func best(date: String, path := PATH) -> int:
	var cfg := ConfigFile.new()
	cfg.load(path)
	return int(cfg.get_value("best", date, 999))


## Days in a row up to `date` with a finished daily round.
static func streak(date: String, path := PATH) -> int:
	var cfg := ConfigFile.new()
	cfg.load(path)
	var n := 0
	var t := Time.get_unix_time_from_datetime_string(date)
	while cfg.has_section_key("best", Time.get_date_string_from_unix_time(t - n * 86400)):
		n += 1
	return n


## "Red Spire, best -2": the menu tile's line.
static func describe(date: String, path := PATH) -> String:
	var text := course_title(course_for(date))
	var b := best(date, path)
	if b != 999:
		text += ", best " + Scorecard.format_to_par(b)
	return text
