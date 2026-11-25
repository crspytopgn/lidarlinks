class_name PlayCount
extends RefCounted
## The anonymous play-time count, built like OpenSGolf's and exact to the
## second: so the project can see how many hours are played on each system
## and build, and for how long at a time, the game tells LidarLinks' own
## counter (URL, a Cloudflare Worker: stats/README.md):
##
## * start/<platform>/<build> once a run, e.g. start/windows/f191d18;
## * play/<platform> with t, the whole seconds played in this run so far:
##   every 5 minutes of play (EVERY_S) and whenever play stops for a while
##   (the pause menu, the game put in the background, a round ending:
##   flush()).
##
## t only grows, so a report that is lost or repeated costs nothing: the
## counter keeps each run's highest t and adds only the increase. The last
## total of each run is kept on the device ([count] runs in PlayerStats'
## file) and sent again at the next start, so a game closed, killed or
## offline still ends up counted to the second.
##
## The play time is PlayerStats' clock (time on a course or the range, with
## the game in front, not paused, someone at the controls). Each report also
## carries the build, its number in the run and a run id: a random number
## made at each start, kept only until its last total has gone, so one
## run's reports can be told apart but never tied to a person or to another
## run. Nothing else is sent: no names, scores, rounds or courses, no
## cookies. The counter keeps only the country Cloudflare reads from the
## address, never the address.
##
## On by default. Settings > Play-time count (and the launcher's Settings)
## turns it off and forgets the kept totals; the first round says so once.
## Never sent from the tests, a headless run or a local build ("dev").

const URL := "https://lidarlinks-stats.openmcm2-laps.workers.dev/count"
## Play time between two reports.
const EVERY_S := 5.0 * 60.0
## A flush with less new play than this waits for more.
const MIN_REPORT_S := 5.0
## Runs whose last total is kept to send again, at most.
const KEEP_RUNS := 20
const TIMEOUT_S := 10.0
const NOTICE := "LidarLinks counts play time anonymously (no names or scores) to see how much it's played. Settings > Play-time count turns it off."

## Settings > Play-time count (GraphicsSettings.play_count).
static var enabled := true
## Set by the tests: reports go here instead of the network.
static var sent_log: Array[String] = []
static var log_only := false

static var _run_id := ""
## Play in this run, and the total last reported.
static var _run_play_s := 0.0
static var _reported_s := 0
static var _reports := 0
static var _started := false


## Whether reports may go out from this run at all.
static func active() -> bool:
	if not enabled:
		return false
	if log_only:
		return true
	return is_build(BuildInfo.COMMIT) and DisplayServer.get_name() != "headless" and not OS.has_feature("editor")


## A released build's name: its short commit.
static func is_build(v: String) -> bool:
	if v.length() < 7 or v.length() > 12:
		return false
	for ch in v:
		if not "0123456789abcdef".contains(ch):
			return false
	return true


## windows, macos, linux, web, android, ios or other, with -arm64 on 64-bit
## ARM desktops.
static func platform(os_name := OS.get_name(), arch := Engine.get_architecture_name()) -> String:
	var p := "other"
	match os_name:
		"Windows":
			p = "windows"
		"macOS":
			p = "macos"
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			p = "linux"
		"Web":
			return "web"
		"Android":
			return "android"
		"iOS":
			return "ios"
	return p + "-arm64" if arch == "arm64" else p


static func run_id() -> String:
	if _run_id.is_empty():
		_run_id = Crypto.new().generate_random_bytes(8).hex_encode()
	return _run_id


## The address of one report.
static func url_for(event: String, sid: String, n: int, seconds := -1, build := BuildInfo.COMMIT) -> String:
	var u := "%s?e=%s&v=%s&s=%s&n=%d" % [URL, event.uri_encode(), build, sid, n]
	if seconds >= 0:
		u += "&t=%d" % seconds
	return u + "&rnd=%d" % (randi() % 1000000)


## The game started (boot.gd): the start report, once a run, then the last
## totals of earlier runs again.
static func start() -> void:
	if _started or not active():
		return
	_started = true
	_send(url_for("start/%s/%s" % [platform(), BuildInfo.COMMIT], run_id(), 0), "")
	for r: Dictionary in _kept_runs():
		if str(r.get("s", "")) != run_id():
			_send(url_for("play/" + str(r.get("p", platform())), str(r.s), int(r.get("n", 0)) + 1, int(r.get("t", 0)),
				str(r.get("v", BuildInfo.COMMIT))), str(r.s))


## Play time went by (main.gd, with PlayerStats.add_play_time). Reports the
## run's total every EVERY_S.
static func add_play(seconds: float) -> void:
	if not enabled or seconds <= 0.0:
		return
	_run_play_s += seconds
	if _run_play_s - _reported_s >= EVERY_S:
		flush()


## Play stopped for now (paused, in the background, a round over, the game
## closing): reports the run's total if it has grown. The total is kept
## first, so a report cut off by the game closing goes at the next start.
static func flush() -> void:
	if not active() or _run_play_s - _reported_s < MIN_REPORT_S:
		return
	_reported_s = floori(_run_play_s)
	_reports += 1
	_keep_run()
	_send(url_for("play/" + platform(), run_id(), _reports, _reported_s), "")


## Settings turned the count off (or on again).
static func set_enabled(on: bool) -> void:
	enabled = on
	if not on and not _kept_runs().is_empty():
		PlayerStats._data().set_value("count", "runs", [])
		PlayerStats.save()


## True once: the first round's quiet line saying the count is on.
static func notice_once() -> bool:
	if not active() or PlayerStats._data().get_value("count", "noticed", false):
		return false
	PlayerStats._data().set_value("count", "noticed", true)
	PlayerStats.save()
	return true


## Runs whose last total is kept: [{s, t, n, v, p}, ...].
static func _kept_runs() -> Array:
	var v: Variant = PlayerStats._data().get_value("count", "runs", [])
	return (v as Array).duplicate(true) if v is Array else []


## This run's total, kept for the next start (its newest first).
static func _keep_run() -> void:
	var runs := _kept_runs().filter(func(r: Variant) -> bool: return r is Dictionary and str((r as Dictionary).get("s", "")) != run_id())
	runs.push_front({"s": run_id(), "t": _reported_s, "n": _reports, "v": BuildInfo.COMMIT, "p": platform()})
	PlayerStats._data().set_value("count", "runs", runs.slice(0, KEEP_RUNS))
	PlayerStats.save()


## An earlier run's total got through: it needn't be kept any more.
static func _forget_run(sid: String) -> void:
	var runs := _kept_runs().filter(func(r: Variant) -> bool: return r is Dictionary and str((r as Dictionary).get("s", "")) != sid)
	PlayerStats._data().set_value("count", "runs", runs)
	PlayerStats.save()


## Sends one report. `old_run`: an earlier run's id, forgotten once its total
## gets through.
static func _send(address: String, old_run: String) -> void:
	if log_only:
		sent_log.append(address)
		if not old_run.is_empty():
			_forget_run(old_run)
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var http := HTTPRequest.new()
	# Not on a thread: a threaded request with a timeout froze the game
	# (the course builder hit it).
	http.use_threads = false
	http.timeout = TIMEOUT_S
	tree.root.add_child(http)
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		http.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300 and not old_run.is_empty():
			_forget_run(old_run))
	var headers := PackedStringArray()
	if not OS.has_feature("web"):
		headers.append("User-Agent: LidarLinks/%s (%s)" % [BuildInfo.COMMIT, platform()])
	if http.request(address, headers) != OK:
		http.queue_free()
