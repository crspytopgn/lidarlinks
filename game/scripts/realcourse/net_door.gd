class_name NetDoor
extends RefCounted
## The one door every real-course download goes through: per server, a cap
## on requests at once, a pause when the server says to slow down (429 or
## 503, honouring Retry-After), and a circuit breaker that stops asking a
## server that keeps failing, so a dead source costs seconds, not minutes
## of time-outs. It also names the server a build is waiting on. Pure
## bookkeeping on times in milliseconds, so it is tested without a network.
## (The breaker and back-off follow BeamNG.Earth's netfetch.py, MIT.)

const HOST_PARALLEL := 6  ## requests at once to one server
const BREAK_AFTER := 5  ## failures in a row before a server is left alone
const BREAK_MS := 60000  ## first rest for a failing server; doubles to BREAK_MAX_MS
const BREAK_MAX_MS := 300000
const SLOW_MS := 120000  ## longest pause a server's Retry-After can ask for
const BUSY_MS := 2000  ## first pause after a 429 without Retry-After; doubles to SLOW_MS
const WAITING_MS := 20000  ## a request this old is named in the progress line

var _hosts := {}
var _next_id := 0


## The server part of `url` ("tile.example.org"), lower case.
static func host_of(url: String) -> String:
	var s := url
	var i := s.find("://")
	if i >= 0:
		s = s.substr(i + 3)
	for sep in ["/", "?", "#"]:
		var j := s.find(sep)
		if j >= 0:
			s = s.substr(0, j)
	var at := s.rfind("@")
	if at >= 0:
		s = s.substr(at + 1)
	return s.to_lower()


## Seconds in a Retry-After header, or -1 when there is none (an HTTP date
## counts as a minute).
static func retry_after(headers: PackedStringArray) -> float:
	for h in headers:
		var c := h.find(":")
		if c > 0 and h.substr(0, c).strip_edges().to_lower() == "retry-after":
			var v := h.substr(c + 1).strip_edges()
			return v.to_float() if v.is_valid_float() or v.is_valid_int() else 60.0
	return -1.0


func _host(host: String) -> Dictionary:
	if not _hosts.has(host):
		_hosts[host] = {"running": {}, "fails": 0, "open_until": 0, "rest": BREAK_MS, "trial": false,
			"pause_until": 0, "busy": BUSY_MS, "slowed": false}
	return _hosts[host]


## 0 when a request to `host` may start now, -1 when the server is being
## left alone (fail at once), else milliseconds to wait before asking again.
func wait_ms(host: String, now: int) -> int:
	var h := _host(host)
	if int(h["fails"]) >= BREAK_AFTER:
		if now < int(h["open_until"]):
			return -1
		# Rested: let one request through to see if it is back.
		if bool(h["trial"]):
			return 250
	if now < int(h["pause_until"]):
		return int(h["pause_until"]) - now
	if (h["running"] as Dictionary).size() >= HOST_PARALLEL:
		return 50
	return 0


## Marks a request to `host` as started; returns its id for `finished`.
func started(host: String, now: int) -> int:
	var h := _host(host)
	_next_id += 1
	(h["running"] as Dictionary)[_next_id] = now
	if int(h["fails"]) >= BREAK_AFTER:
		h["trial"] = true
	return _next_id


## Records the answer: `code` 0 means no answer at all.
func finished(host: String, id: int, code: int, headers: PackedStringArray, now: int) -> void:
	var h := _host(host)
	(h["running"] as Dictionary).erase(id)
	h["trial"] = false
	var ra := retry_after(headers)
	if code == 429 or (code == 503 and ra >= 0.0):
		var ms := int(ra * 1000.0) if ra >= 0.0 else int(h["busy"])
		h["busy"] = mini(int(h["busy"]) * 2, SLOW_MS)
		h["pause_until"] = maxi(int(h["pause_until"]), now + clampi(ms, 500, SLOW_MS))
		h["slowed"] = true
		return
	if code == 0 or code >= 500:
		h["fails"] = int(h["fails"]) + 1
		if int(h["fails"]) >= BREAK_AFTER:
			h["open_until"] = now + int(h["rest"])
			h["rest"] = mini(int(h["rest"]) * 2, BREAK_MAX_MS)
		return
	h["fails"] = 0
	h["rest"] = BREAK_MS
	h["busy"] = BUSY_MS
	h["slowed"] = false


## Forgets a request we stopped ourselves (a cancel, or the slower map
## servers once one answered): it says nothing about the server.
func dropped(host: String, id: int) -> void:
	var h := _host(host)
	(h["running"] as Dictionary).erase(id)
	h["trial"] = false


## True while `host` is being left alone after failing again and again.
func is_open(host: String, now: int) -> bool:
	return _hosts.has(host) and int(_hosts[host]["fails"]) >= BREAK_AFTER and now < int(_hosts[host]["open_until"])


## A note for the progress line naming the server a build waits on: the one
## with the oldest request past WAITING_MS, or one that asked us to slow
## down; "" when nothing is slow.
func waiting_note(now: int) -> String:
	var worst := ""
	var oldest := now
	for host: String in _hosts:
		var h: Dictionary = _hosts[host]
		if now < int(h["pause_until"]) and bool(h["slowed"]):
			return " (%s asked us to slow down; waiting %d s)" % [host, ceili((int(h["pause_until"]) - now) / 1000.0)]
		for t: int in (h["running"] as Dictionary).values():
			if t < oldest:
				oldest = t
				worst = host
	if worst != "" and now - oldest >= WAITING_MS:
		var s := (now - oldest) / 1000
		return " (waiting on %s, %d:%02d)" % [worst, s / 60, s % 60]
	return ""
