class_name FrameWatch
extends Node
## Watches the frame rate in play and, when the machine can't keep 50 to 60
## frames a second on the look it was started on, steps the look down, as a console game
## would: Natural to Performance, then Performance to its lean form
## (GraphicsSettings.lean). Only a look the game picked itself is changed
## (GraphicsSettings.auto_look); a look the player chose is left alone.
## Dynamic resolution gets the first go: the look only steps down once the
## 3D resolution is already as low as it goes and frames are still slow.

## A frame this slow or slower, as the median of a window, is too slow for
## the richer looks: under 50 frames a second, as play should be smooth at
## 60 (a 60 Hz screen's frames come in at 16.7 ms). Performance only steps
## to its lean form under 30 (LEAN_MS), as that costs the trees and grass.
const SLOW_MS := 20.0
const LEAN_MS := 33.0
## Seconds of frames per decision, and slow windows in a row before a step.
const WINDOW := 5.0
const SLOW_WINDOWS := 2
## Frames longer than this are a hitch (loading, a hidden browser tab), not
## the frame rate, and are left out.
const HITCH_MS := 250.0
## Seconds after start and after each step before watching.
const SETTLE := 6.0

## Called with the new look when it steps down.
signal stepped(look: int)

var _settings: GraphicsSettings
var _viewport: Viewport
var _dynamic: DynamicResolution
var _times := PackedFloat32Array()
var _window := 0.0
var _slow := 0
var _settle := SETTLE
## Off while a hole is loading or a menu is up (set by the round).
var watching := true


func setup(settings: GraphicsSettings, viewport: Viewport, dynamic: DynamicResolution) -> void:
	_settings = settings
	_viewport = viewport
	_dynamic = dynamic
	restart()


## Starts watching again after SETTLE seconds.
func restart() -> void:
	_times.clear()
	_window = 0.0
	_slow = 0
	_settle = SETTLE


func _process(delta: float) -> void:
	if _settings == null or not watching or next_look(_settings) < 0:
		return
	if _settle > 0.0:
		_settle -= delta
		return
	var ms := delta * 1000.0
	if ms < HITCH_MS:
		_times.append(ms)
		_window += delta
	if _window < WINDOW:
		return
	var slow := is_slow(_times, LEAN_MS if _settings.look == GraphicsSettings.Look.PERFORMANCE else SLOW_MS)
	_times.clear()
	_window = 0.0
	# Dynamic resolution first: only once it is at its floor.
	var at_floor := _dynamic == null or _dynamic.target_fps <= 0 or _viewport == null \
		or _viewport.scaling_3d_scale <= _dynamic.min_scale + 0.01
	_slow = _slow + 1 if slow and at_floor else 0
	if _slow < SLOW_WINDOWS:
		return
	var to := next_look(_settings)
	step_down(_settings)
	_settings.save()
	restart()
	stepped.emit(to)


## True when the median frame of `times` (ms) is `limit` or slower.
static func is_slow(times: PackedFloat32Array, limit := SLOW_MS) -> bool:
	if times.size() < 10:
		return false
	var sorted := times.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2] >= limit


## The look `s` would step down to, or -1 when it stays (a look the player
## chose, or already the leanest).
static func next_look(s: GraphicsSettings) -> int:
	if not s.auto_look:
		return -1
	match s.look:
		GraphicsSettings.Look.PHOTOREAL, GraphicsSettings.Look.CINEMATIC, GraphicsSettings.Look.NATURAL:
			return GraphicsSettings.Look.PERFORMANCE
		GraphicsSettings.Look.PERFORMANCE:
			return -1 if s.lean else GraphicsSettings.Look.PERFORMANCE
	return -1


## Steps `s` down one look (next_look); Performance's next step is its lean
## form.
static func step_down(s: GraphicsSettings) -> void:
	var to := next_look(s)
	if to < 0:
		return
	if s.look == GraphicsSettings.Look.PERFORMANCE:
		s.lean = true
	s.apply_look(to)
