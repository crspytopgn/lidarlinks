class_name FlagMotion
extends RefCounted
## How the pin flag moves in the wind (shaders/flag.gdshader), tuned
## against tour footage of 20 x 14 in nylon flags:
## - a breath of air (under about 3 mph) leaves it hanging on the pole,
##   only its tail stirring and swinging slowly round as the air wanders;
## - about 10 mph flies it at roughly 50 to 60 degrees with a lazy wave;
## - 20 mph and over holds it straight out, a small quick ripple running
##   to a flicking tail, never violent flapping.
## The ripple's phase is integrated here, frame by frame: the old shader
## used TIME * frequency, so each gust changed the frequency and the
## phase leapt (more the longer the game had run), which made the flag
## thrash. The wind the flag feels is eased a little, as the cloth has a
## little inertia, so a gust swells it rather than snapping it.

## Seconds for the flag to take up most of a change in the wind.
const EASE_S := 0.45
## Ripple frequency, cycles per second, at `speed` m/s: about 0.8 Hz in
## 4 mph, 1.5 Hz in 10 mph, 2.8 Hz in 20 mph, never above 4.5 Hz.
const RIPPLE_BASE_HZ := 0.25
const RIPPLE_HZ_PER_MS := 0.28
const RIPPLE_MAX_HZ := 4.5
## In light air the direction wanders this far either way.
const LIGHT_WANDER_DEG := 28.0

var wind := Vector2.ZERO  ## the eased wind the flag flies in, m/s
var phase := 0.0  ## ripple cycles so far, kept in 0..1
var _clock := 0.0


static func ripple_hz(speed: float) -> float:
	return minf(RIPPLE_BASE_HZ + RIPPLE_HZ_PER_MS * maxf(speed, 0.0), RIPPLE_MAX_HZ)


## Jumps straight to `seen` (a new hole: no swinging in from the last).
func snap(seen: Vector2) -> void:
	wind = _wandered(seen)


## Moves the flag on by `delta` seconds in the wind the eye sees.
func step(seen: Vector2, delta: float) -> void:
	delta = clampf(delta, 0.0, 0.1)
	_clock += delta
	var target := _wandered(seen)
	wind = wind.lerp(target, 1.0 - exp(-delta / EASE_S))
	phase = fposmod(phase + ripple_hz(wind.length()) * delta, 1.0)


## Light air never blows from one quarter: swing it slowly about.
func _wandered(seen: Vector2) -> Vector2:
	var speed := seen.length()
	if speed < 0.01:
		return Vector2.ZERO
	var light := 1.0 - clampf((speed - 1.0) / 3.0, 0.0, 1.0)
	if light <= 0.0:
		return seen
	var swing := deg_to_rad(LIGHT_WANDER_DEG) * light * (0.6 * sin(TAU * _clock / 7.3) + 0.4 * sin(TAU * _clock / 12.9 + 1.1))
	return seen.rotated(swing)
