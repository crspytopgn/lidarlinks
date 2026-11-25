class_name WebSocketLink
extends OnlineLink
## An online room over a WebSocket (works in the web build too). Call
## receive() every frame: it also polls the socket.
##
## Built for slow and flaky connections (a phone on a train): a round sends
## only each shot's inputs, a few hundred bytes, and a tiny keep-alive every
## PING_S seconds that the server answers without waking up. If the
## connection drops, the link reconnects by itself with the key the server
## gave it, gets every event it missed, and resends any of its own that
## never arrived, so nobody's round stalls or forks. The server keeps the
## seat for a few minutes (server/src/room.js AWAY_GRACE_MS).

## The keep-alive and its answer (server/src/room_object.js PING, PONG).
const PING := "{\"type\":\"ping\"}"
const PONG := "{\"type\":\"pong\"}"
const PING_S := 15.0
## Nothing heard for this long: the connection is dead even if the socket
## hasn't noticed (mobile networks drop silently).
const DEAD_S := 40.0
## Waits between reconnect tries, then the last one over and over.
const RETRY_S: Array[float] = [0.3, 1.0, 2.0, 4.0, 8.0]
## Give up after this long without a connection (the server's grace).
const GIVE_UP_S := 170.0

var url := ""
var socket := WebSocketPeer.new()
var _hello: Dictionary
var _outbox: Array[String] = []
## Set by the server's welcome: who I am and the key to get back in.
var _me := -1
var _key := ""
## Events of the round seen so far (received or sent): the next number.
var _since := 0
## My own events by number, to resend any the server didn't get.
var _mine: Dictionary = {}
var _closed := false
var _last_heard := 0.0
var _last_ping := 0.0
var _down_since := -1.0
var _retry := 0
var _retry_at := 0.0
var _gave_up := false
## Bytes sent and received, for the tests and a debug readout.
var sent_bytes := 0
var received_bytes := 0


## Opens `url` (wss://server/rooms/CODE); `hello` is sent once it opens.
func _init(p_url: String, hello: Dictionary) -> void:
	url = p_url
	_hello = hello
	_open()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _open() -> void:
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 256 * 1024
	socket.outbound_buffer_size = 256 * 1024
	socket.connect_to_url(url)
	var hello := _hello.duplicate()
	if _me >= 0:
		hello["rejoin"] = {"id": _me, "key": _key}
		hello["since"] = _since
	_outbox.push_front(JSON.stringify(hello))
	_last_heard = _now()


func send(msg: Dictionary) -> void:
	var text := JSON.stringify(msg)
	if str(msg.get("type", "")) == "event":
		var n := int(msg.get("seq", -1))
		_mine[n] = text
		_since = maxi(_since, n + 1)
	_outbox.append(text)


func receive() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _closed or _gave_up:
		return out
	socket.poll()
	var now := _now()
	var ready := socket.get_ready_state()
	if ready == WebSocketPeer.STATE_OPEN:
		while not _outbox.is_empty():
			var t: String = _outbox.pop_front()
			socket.send_text(t)
			sent_bytes += t.length()
		while socket.get_available_packet_count() > 0:
			var text := socket.get_packet().get_string_from_utf8()
			received_bytes += text.length()
			_last_heard = now
			if text == PONG:
				continue
			var d: Variant = JSON.parse_string(text)
			if d is Dictionary:
				_note(d)
				out.append(d)
		if now - _last_ping >= PING_S:
			_last_ping = now
			socket.send_text(PING)
			sent_bytes += PING.length()
		if now - _last_heard > DEAD_S:
			socket.close()
			ready = WebSocketPeer.STATE_CLOSED
	if ready == WebSocketPeer.STATE_CLOSED:
		if _me < 0 or socket.get_close_code() == 4000 or socket.get_close_code() == 4001:
			# Never got in, or the server said no, or this game got back in
			# on another connection: nothing to reconnect.
			_gave_up = true
			return out
		if _down_since < 0.0:
			_down_since = now
			_retry = 0
			_retry_at = now + RETRY_S[0]
			out.append({"type": "_link", "state": "reconnecting"})
		elif now - _down_since > GIVE_UP_S:
			_gave_up = true
		elif now >= _retry_at:
			_retry += 1
			_retry_at = now + RETRY_S[mini(_retry, RETRY_S.size() - 1)]
			_open()
	return out


## Watches the server's messages for what a reconnect needs.
func _note(d: Dictionary) -> void:
	match str(d.get("type", "")):
		"welcome":
			_me = int(d.get("you", -1))
			_key = str(d.get("key", ""))
			if bool(d.get("rejoined", false)):
				# Mine that never got there: send them again, in order.
				var server_next := int(d.get("seq", 0))
				var queued := _mine.values()
				_outbox.assign(_outbox.filter(func(t: String) -> bool: return not queued.has(t)))
				var numbers: Array = _mine.keys()
				numbers.sort()
				for n: int in numbers:
					if n >= server_next:
						_outbox.append(_mine[n])
				if _down_since >= 0.0:
					_down_since = -1.0
					d["_back"] = true
		"event":
			_since = maxi(_since, int(d.get("seq", -1)) + 1)


## True while connected, connecting, or trying to get back.
func is_open() -> bool:
	if _closed or _gave_up:
		return false
	return true


func is_reconnecting() -> bool:
	return _down_since >= 0.0 and not _gave_up


func close() -> void:
	_closed = true
	socket.close()
