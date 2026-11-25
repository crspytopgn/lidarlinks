extends RefCounted
## The player's own stats for the launcher's Stats tab, read from the game's
## user://stats.cfg (Paths.game_stats()). The game writes a [summary] there
## already worded in the player's units (PlayerStats.write_summary in
## game/scripts/player_stats.gd) whenever it starts, a round ends or it
## quits, so the launcher shows exactly what the game's Stats page does
## without the game's code. Nothing here leaves the computer.

const Paths := preload("res://scripts/paths.gd")

## [[label, value], ...]
var rows: Array = []
## [[course, holes, strokes, to_par, date], ...]
var best: Array = []
## [{name, index, rounds, last, trend: [tenths...], records, career}, ...]
var players: Array = []
## Seconds played on each of the last 30 days, oldest first.
var days: Array = []
var updated := ""


static func load_from(path := Paths.game_stats()) -> RefCounted:
	var s: RefCounted = (load("res://scripts/game_stats.gd") as GDScript).new()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return s
	s.rows = _array(cfg.get_value("summary", "rows", []))
	s.best = _array(cfg.get_value("summary", "best", []))
	s.players = _array(cfg.get_value("summary", "players", []))
	s.days = _array(cfg.get_value("summary", "days", []))
	s.updated = str(cfg.get_value("summary", "updated", ""))
	return s


static func _array(v: Variant) -> Array:
	return v if v is Array else []


func is_empty() -> bool:
	return rows.is_empty()


## "+2", "-1", "E".
static func to_par(n: int) -> String:
	if n == 0:
		return "E"
	return ("+%d" % n) if n > 0 else str(n)


## Tenths as the game shows an index: "12.3", "+1.4" (a plus handicap).
static func index_text(tenths: int) -> String:
	var a := absi(tenths)
	return "%s%d.%d" % ["+" if tenths < 0 else "", a / 10, a % 10]
