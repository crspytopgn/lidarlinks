class_name StatsPanel
extends PanelContainer
## The "Stats" page: everything played on this device (PlayerStats) — time
## played with the last 30 days as bars, rounds, holes, shots, scoring,
## fairways, greens, putts, drives, scores by type, favourite club, courses
## and best rounds — then each player's handicap index with its trend, career
## numbers and records (PlayerProfiles). All of it is kept on this device
## only. Reset starts the device's stats again (asks once more); players'
## rounds stay on the Players page.

signal back_pressed

## Courses and best rounds listed, at most.
const SHOWN := 12

var _body: VBoxContainer
var _back: Button
var _reset: Button
var _confirm := false


func _ready() -> void:
	MenuStyle.panel(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(760, 0)
	add_child(box)
	box.add_child(MenuStyle.heading("Stats", 30))
	var help := Label.new()
	help.text = "Everything you've played on this device. It stays here: only an anonymous count of play time is ever sent, and Settings > Play-time count turns that off."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 15)
	help.modulate = Color(1, 1, 1, 0.75)
	box.add_child(help)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_body)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	_reset = MenuStyle.button("Reset stats")
	_reset.pressed.connect(_on_reset)
	buttons.add_child(_reset)
	_back = MenuStyle.button("Back")
	_back.pressed.connect(back_pressed.emit)
	buttons.add_child(_back)
	visible = false


func open() -> void:
	PlayerStats.reread()
	_confirm = false
	_reset.text = "Reset stats"
	_fill()
	visible = true
	_back.grab_focus.call_deferred()


func close() -> void:
	visible = false


func _fill() -> void:
	for child in _body.get_children():
		child.queue_free()
	_body.add_child(_section("Time played, last 30 days"))
	var bars := DayBars.new()
	bars.days = PlayerStats.recent_days(30)
	bars.custom_minimum_size = Vector2(0, 70)
	_body.add_child(bars)

	_body.add_child(_section("On this device"))
	_body.add_child(_table(PlayerStats.headline()))

	var profiles := PlayerProfiles.load_saved()
	var names := profiles.names()
	if not names.is_empty():
		_body.add_child(_section("Players"))
	for n in names:
		var played := profiles.rounds(n)
		var head := _line("%s    Index %s    %d round%s" % [n, Handicap.format(profiles.index_of(n)), played.size(), "" if played.size() == 1 else "s"], 17)
		head.add_theme_color_override("font_color", MenuStyle.ACCENT)
		_body.add_child(head)
		var trend := PlayerStats.index_trend(profiles.differentials(n))
		if trend.size() >= 2:
			var t := IndexTrend.new()
			t.values = trend
			t.custom_minimum_size = Vector2(0, 54)
			_body.add_child(t)
			_body.add_child(_line("Handicap index over the last %d rounds: %s to %s (lower is better)" % [
				trend.size(), Handicap.format(trend[0]), Handicap.format(trend[trend.size() - 1])], 14, 0.7))
		var career := PlayerProfiles.career_text(profiles.career(n))
		if not career.is_empty():
			_body.add_child(_line(career, 15))
		var records := PlayerProfiles.records_text(profiles.records(n))
		if not records.is_empty():
			_body.add_child(_line(records, 15))

	var best := PlayerStats.best_rounds()
	if not best.is_empty():
		_body.add_child(_section("Best rounds"))
		var rows: Array = []
		for b: Array in best.slice(0, SHOWN):
			rows.append(["%s (%d holes)" % [b[0], b[1]], "%d (%s)   %s" % [b[2], Scorecard.format_to_par(b[3]), b[4]]])
		_body.add_child(_table(rows))
	var courses := PlayerStats.courses()
	if not courses.is_empty():
		_body.add_child(_section("Courses"))
		var rows: Array = []
		for c: Array in courses.slice(0, SHOWN):
			rows.append([c[0], "%d holes, %d round%s" % [c[1], c[2], "" if c[2] == 1 else "s"]])
		_body.add_child(_table(rows))


func _on_reset() -> void:
	if not _confirm:
		_confirm = true
		_reset.text = "Sure? Reset"
		return
	PlayerStats.reset()
	_confirm = false
	_reset.text = "Reset stats"
	_fill()


func _section(text: String) -> Label:
	var l := _line(text.to_upper(), 13, 0.6)
	l.add_theme_constant_override("line_spacing", 0)
	return l


func _line(text: String, size: int, alpha := 1.0) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.modulate = Color(1, 1, 1, alpha)
	return l


## Two columns: name, value.
func _table(rows: Array) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 24)
	g.add_theme_constant_override("v_separation", 4)
	for r: Array in rows:
		var k := _line(str(r[0]), 15, 0.7)
		k.autowrap_mode = TextServer.AUTOWRAP_OFF
		k.custom_minimum_size = Vector2(230, 0)
		g.add_child(k)
		var v := _line(str(r[1]), 15)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(v)
	return g


## Minutes played per day as bars, today on the right.
class DayBars:
	extends Control
	var days: Array[float] = []

	func _draw() -> void:
		if days.is_empty():
			return
		var top := 1.0
		for d in days:
			top = maxf(top, d)
		var w := size.x / days.size()
		var h := size.y - 16.0
		for i in days.size():
			var bh := h * days[i] / top
			var c := MenuStyle.ACCENT if i == days.size() - 1 else Color(1, 1, 1, 0.55)
			if days[i] > 0.0:
				draw_rect(Rect2(i * w + 1.0, h - maxf(bh, 2.0), maxf(w - 2.0, 1.0), maxf(bh, 2.0)), c)
		draw_line(Vector2(0, h), Vector2(size.x, h), Color(1, 1, 1, 0.25))
		var font := get_theme_default_font()
		draw_string(font, Vector2(0, size.y - 2), "30 days ago", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.5))
		draw_string(font, Vector2(size.x - 160, size.y - 2), "Today: " + PlayerStats.format_time(days[days.size() - 1]),
			HORIZONTAL_ALIGNMENT_RIGHT, 160, 12, Color(1, 1, 1, 0.7))
		draw_string(font, Vector2(4, 12), "Most in a day: " + PlayerStats.format_time(top), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.5))


## The handicap index round by round as a line (lower, better, is higher up).
class IndexTrend:
	extends Control
	var values: Array[int] = []

	func _draw() -> void:
		if values.size() < 2:
			return
		var lo := values[0]
		var hi := values[0]
		for v in values:
			lo = mini(lo, v)
			hi = maxi(hi, v)
		var span := maxf(float(hi - lo), 10.0)
		var pts := PackedVector2Array()
		for i in values.size():
			var x := 6.0 + (size.x - 12.0) * i / (values.size() - 1)
			var y := 6.0 + (size.y - 12.0) * (values[i] - lo) / span
			pts.append(Vector2(x, y))
		draw_polyline(pts, MenuStyle.ACCENT, 2.0, true)
		draw_circle(pts[pts.size() - 1], 4.0, MenuStyle.ACCENT)
