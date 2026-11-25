class_name LeaderboardPanel
extends PanelContainer
## Leaderboard: the daily round's online board (DailyBoard), today's or
## yesterday's, with your own place. Finishing a daily round puts you on it.

signal back_pressed
signal play_pressed

var _status: Label
var _list: Label
var _day: OptionButton
var _http: HTTPRequest
var _busy := false


func _ready() -> void:
	MenuStyle.panel(self)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(560, 0)
	add_child(box)
	box.add_child(MenuStyle.heading("Daily leaderboard", 30))
	_day = OptionButton.new()
	_day.add_item("Today")
	_day.add_item("Yesterday")
	_day.custom_minimum_size = Vector2(220, 36)
	_day.item_selected.connect(func(_i: int) -> void: refresh())
	box.add_child(_day)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(520, 0)
	box.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 340)
	box.add_child(scroll)
	_list = Label.new()
	_list.add_theme_font_size_override("font_size", 18)
	scroll.add_child(_list)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var play := MenuStyle.button("Play today's round")
	play.pressed.connect(func() -> void: play_pressed.emit())
	row.add_child(play)
	var back := MenuStyle.button("Back")
	back.pressed.connect(func() -> void:
		visible = false
		back_pressed.emit())
	row.add_child(back)
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	_http.request_completed.connect(_on_loaded)
	add_child(_http)
	visible = false


func open() -> void:
	_day.select(0)
	visible = true
	refresh()


func date() -> String:
	var t := int(Time.get_unix_time_from_system()) - _day.selected * 86400
	return Time.get_date_string_from_unix_time(t)


func refresh() -> void:
	if _busy:
		_http.cancel_request()
	var d := date()
	_status.text = "%s, %s. Loading..." % [DailyRound.course_title(DailyRound.course_for(d)), d]
	_list.text = ""
	var u := DailyBoard.url(OnlineSettings.server(), d) + "?token=" + OnlineSettings.token()
	_busy = _http.request(u) == OK
	if not _busy:
		_status.text = "Couldn't reach the leaderboard."


func _on_loaded(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	var d: Variant = JSON.parse_string(body.get_string_from_utf8())
	var day := date()
	var title := "%s, %s." % [DailyRound.course_title(DailyRound.course_for(day)), day]
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not d is Dictionary:
		_status.text = title + " Couldn't reach the leaderboard (check your connection)."
		return
	show_board(d, title)


## Shows a board the server sent.
func show_board(d: Dictionary, title: String) -> void:
	var count := int(d.get("count", 0))
	var text := title
	if count == 0:
		text += " Nobody has finished this round yet."
	else:
		text += " %d played." % count
	var you: Variant = d.get("you", null)
	if you is Dictionary:
		text += " You're %s with %d." % [DailyBoard.ordinal(int(you.get("rank", 0))), int(you.get("strokes", 0))]
	_status.text = text
	_list.text = "\n".join(DailyBoard.rows(d))
