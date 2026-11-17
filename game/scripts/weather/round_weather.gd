class_name RoundWeather
extends RefCounted
## One round's weather: how cloudy it is, whether it rains or drizzles, how
## misty, how windy and how warm. Drawn from the course's climate for the
## month (Climate.for_course) with the round's seed, so a friend's round or
## an online round on the same seed gets the same day; or read from a live
## forecast (from_live). The wind is the only part that touches play, and
## only through the round's Wind level: Links 2003's ball flight has no
## rain, temperature or air density in it.

enum Rain { NONE, DRIZZLE, RAIN }

const RAIN_NAMES := ["", "drizzle", "rain"]
## Mean wind (m/s) up to which each Wind.Level fits. A hole's wind is 20% to
## 100% of the level's top speed (Wind.MAX_MPH), so its mean is about 60%:
## Light averages about 2 m/s, Moderate 4, Strong 6.7.
const WIND_LEVEL_UP_TO := [0.6, 3.0, 5.5]

var cloud := 0.2  ## 0 clear to 1 overcast
var rain: Rain = Rain.NONE
var fog := 0.0  ## 0 clear air to 1 thick mist
var wind_mps := 3.5  ## the day's mean wind
var temp_c := 20.0
var live := false  ## read from a real forecast, not drawn


## A fine sunny day, as the game had before weather (and still has with
## Weather set to Always fine).
static func fine() -> RoundWeather:
	var w := RoundWeather.new()
	w.cloud = 0.0
	return w


## Draws a day from `normals` (Climate.normals) with `seed_value` (0 for a
## random one).
static func draw(normals: Dictionary, seed_value := 0) -> RoundWeather:
	var rng := RandomNumberGenerator.new()
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value ^ 0x5EA7
	var w := RoundWeather.new()
	w.temp_c = float(normals.get("temp", 20.0)) + rng.randfn(0.0, 3.0)
	w.cloud = clampf(float(normals.get("cloud", 0.4)) + rng.randfn(0.0, 0.28), 0.0, 1.0)
	if rng.randf() < float(normals.get("rain", 0.2)):
		w.rain = Rain.DRIZZLE if rng.randf() < float(normals.get("drizzle", 0.5)) else Rain.RAIN
		w.cloud = maxf(w.cloud, rng.randf_range(0.8, 1.0))
		w.temp_c -= 3.0
	# A lognormal-ish spread round the mean wind: most days near it, a few
	# still ones and the odd gale; wet days blow harder.
	var mean := float(normals.get("wind", 4.0)) * (1.2 if w.rain != Rain.NONE else 1.0)
	w.wind_mps = maxf(mean * exp(rng.randfn(0.0, 0.45)) * 0.9, 0.0)
	# Mist on still mornings; it thins as the wind gets up.
	if rng.randf() < float(normals.get("fog", 0.1)) and w.wind_mps < 6.0:
		w.fog = rng.randf_range(0.35, 1.0)
		w.cloud = maxf(w.cloud, 0.5)
	elif w.rain != Rain.NONE:
		w.fog = 0.3 if w.rain == Rain.RAIN else 0.2
	return w


## The weather now from an Open-Meteo "current" block (LiveWeather), or
## null when it is missing what we need.
static func from_live(current: Dictionary) -> RoundWeather:
	if not current.has("cloud_cover") or not current.has("wind_speed_10m"):
		return null
	var w := RoundWeather.new()
	w.live = true
	w.cloud = clampf(float(current.cloud_cover) / 100.0, 0.0, 1.0)
	w.wind_mps = maxf(float(current.wind_speed_10m), 0.0)
	w.temp_c = float(current.get("temperature_2m", 18.0))
	var mm := float(current.get("precipitation", 0.0))
	var code := int(current.get("weather_code", 0))
	# WMO codes: 45/48 fog, 51-57 drizzle, 61-67 and 80-82 rain, 95+ storms.
	if code >= 51 and code <= 57:
		w.rain = Rain.DRIZZLE
	elif (code >= 61 and code <= 67) or (code >= 80 and code <= 82) or code >= 95:
		w.rain = Rain.RAIN
	elif mm > 0.05:
		w.rain = Rain.DRIZZLE if mm < 0.5 else Rain.RAIN
	if code == 45 or code == 48:
		w.fog = 0.8
	elif current.has("visibility"):
		# Under 5 km the air reads misty; under 1 km it is fog.
		w.fog = clampf(1.0 - (float(current.visibility) - 1000.0) / 4000.0, 0.0, 1.0)
	return w


## The Wind.Level that fits the day's wind.
func wind_level() -> int:
	for i in WIND_LEVEL_UP_TO.size():
		if wind_mps <= WIND_LEVEL_UP_TO[i]:
			return i
	return Wind.Level.STRONG


## For the HUD: "Light rain, 11°C" or "Sunny, 24°C".
func describe() -> String:
	var sky := "Sunny"
	if rain == Rain.DRIZZLE:
		sky = "Drizzle"
	elif rain == Rain.RAIN:
		sky = "Rain"
	elif fog >= 0.6:
		sky = "Fog"
	elif fog >= 0.3:
		sky = "Misty"
	elif cloud >= 0.85:
		sky = "Overcast"
	elif cloud >= 0.55:
		sky = "Cloudy"
	elif cloud >= 0.25:
		sky = "Sunny spells"
	return "%s, %d°C" % [sky, roundi(temp_c)]


## How hard it rains for the rain streaks and sound, 0 to 1.
func rain_amount() -> float:
	return [0.0, 0.35, 1.0][rain]
