class_name OnlineSettings
extends RefCounted
## Where the online server is (server/README.md): DEFAULT_SERVER, or
## [online] server in user://settings.cfg. Online play and the leaderboard
## stay hidden until the server has answered (the menu asks it once at the
## start, see probe), so a server that isn't up yet, or no internet, just
## hides them.

const DEFAULT_SERVER := "https://lidarlinks.openmcm2-laps.workers.dev"
## Set once the server answered this run.
static var reachable := false


static func server() -> String:
	var cfg := ConfigFile.new()
	cfg.load(GameFolder.SETTINGS_PATH)
	var s := str(cfg.get_value("online", "server", DEFAULT_SERVER)).strip_edges()
	return s.trim_suffix("/")


## This game's secret player token (no accounts: the server keeps only its
## hash, server/README.md), made the first time it's asked for and kept in
## [online] token. It keeps your place on the leaderboards.
static func token(path := GameFolder.SETTINGS_PATH) -> String:
	var cfg := ConfigFile.new()
	cfg.load(path)
	var t := str(cfg.get_value("online", "token", ""))
	if t.length() >= 32:
		return t
	var bytes := Crypto.new().generate_random_bytes(32)
	t = Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")
	cfg.set_value("online", "token", t)
	cfg.save(path)
	return t


static func available() -> bool:
	return reachable and not server().is_empty()


## True when `body` (GET / on the server) is our server saying hello.
static func is_hello(code: int, body: PackedByteArray) -> bool:
	if code != 200:
		return false
	var d: Variant = JSON.parse_string(body.get_string_from_utf8())
	return d is Dictionary and str(d.get("name", "")) in ["lidarlinks", "openlinks2003"]


## The WebSocket address of room `code` on `base` (https becomes wss).
static func room_url(base: String, code: String) -> String:
	var ws := base
	if ws.begins_with("https://"):
		ws = "wss://" + ws.substr(8)
	elif ws.begins_with("http://"):
		ws = "ws://" + ws.substr(7)
	return "%s/rooms/%s" % [ws, code]
