class_name LiveWeather
extends HTTPRequest
## Fetches the weather at a real course right now from Open-Meteo (free, no
## key, open to browsers), and emits `arrived` with a RoundWeather, or with
## null when it can't be had (offline, blocked, slow). Only the course's own
## latitude and longitude are sent.

signal arrived(weather: RoundWeather)

const URL := "https://api.open-meteo.com/v1/forecast?latitude=%.3f&longitude=%.3f&current=temperature_2m,precipitation,weather_code,cloud_cover,wind_speed_10m,visibility&wind_speed_unit=ms"
const TIMEOUT_S := 8.0


## Starts the request; `arrived` follows. False when the course isn't placed.
func fetch(at: Vector2) -> bool:
	if is_nan(at.x):
		return false
	timeout = TIMEOUT_S
	request_completed.connect(_on_done, CONNECT_ONE_SHOT)
	if request(URL % [at.x, at.y]) != OK:
		request_completed.disconnect(_on_done)
		return false
	return true


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var w: RoundWeather = null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		w = parse(body.get_string_from_utf8())
	arrived.emit(w)


## The RoundWeather in an Open-Meteo reply, or null.
static func parse(text: String) -> RoundWeather:
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary or not (data as Dictionary).get("current") is Dictionary:
		return null
	return RoundWeather.from_live(data.current)
