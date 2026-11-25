class_name RainFx
extends Node3D
## Rain and drizzle round the camera: thin falling streaks (one
## CPUParticles3D draw, so it runs the same on the web's Compatibility
## renderer and Forward+), slanted by the wind, and the hiss of rain made
## from noise at start-up (no sound file). Fewer streaks at lower quality.
## Visual and audio only.

## Streaks at full rain by GraphicsSettings.Quality (LOW to ULTRA).
const DROPS := [220, 600, 1100, 1800]
const BOX := Vector3(16.0, 0.0, 16.0)  ## half size of the box they fall from
const ABOVE := 9.0  ## metres above the camera they start
const RAIN_SPEED := 8.5  ## m/s, about a 2 mm drop's terminal speed
const DRIZZLE_SPEED := 2.5
const RAIN_DB := -13.0
const DRIZZLE_DB := -24.0
const MIX_RATE := 22050

var amount := 0.0  ## 0 none, 0.35 drizzle, 1 rain
var _drops: CPUParticles3D
var _sound: AudioStreamPlayer


func _init() -> void:
	name = "RainFx"
	_drops = CPUParticles3D.new()
	_drops.emitting = false
	_drops.local_coords = false
	_drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_drops.emission_box_extents = BOX
	_drops.gravity = Vector3.ZERO
	_drops.spread = 3.0
	_drops.position = Vector3(0.0, ABOVE, 0.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.012, 0.55)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.albedo_color = Color(0.82, 0.86, 0.9, 0.28)
	mat.disable_receive_shadows = true
	# A streak that falls past the lens would draw as a thick white bar
	# across the frame: fade them out inside the nearest couple of metres.
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	mat.distance_fade_min_distance = 0.6
	mat.distance_fade_max_distance = 2.5
	quad.material = mat
	_drops.mesh = quad
	add_child(_drops)
	_sound = AudioStreamPlayer.new()
	_sound.name = "RainSound"
	add_child(_sound)


## Starts (or stops, at 0) the rain: `p_amount` as RoundWeather.rain_amount,
## `quality` a GraphicsSettings.Quality, `wind` the air's velocity (m/s).
func set_rain(p_amount: float, quality: int, wind: Vector3) -> void:
	amount = p_amount
	visible = amount > 0.0
	if amount <= 0.0:
		_drops.emitting = false
		_sound.stop()
		return
	var drizzle := amount < 0.5
	var speed := DRIZZLE_SPEED if drizzle else RAIN_SPEED
	_drops.amount = maxi(roundi(float(DROPS[clampi(quality, 0, DROPS.size() - 1)]) * amount), 20)
	_drops.lifetime = (ABOVE + 2.0) / speed
	# Falling at `speed`, carried along by the wind (drizzle drifts more).
	var fall := Vector3(wind.x, -speed, wind.z) * Vector3(0.8 if drizzle else 0.5, 1.0, 0.8 if drizzle else 0.5)
	_drops.direction = fall.normalized()
	_drops.initial_velocity_min = fall.length() * 0.9
	_drops.initial_velocity_max = fall.length() * 1.1
	(_drops.mesh as QuadMesh).size = Vector2(0.008, 0.12) if drizzle else Vector2(0.012, 0.55)
	_drops.emitting = true
	if _sound.stream == null:
		_sound.stream = hiss()
	_sound.volume_db = DRIZZLE_DB if drizzle else RAIN_DB
	if not _sound.playing:
		_sound.play()


## Keeps the streaks round the camera.
func follow(cam: Camera3D) -> void:
	if visible and cam != null:
		global_position = cam.global_position


## Two seconds of looping rain: soft low-passed noise with drops landing.
static func hiss() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2003
	var n := MIX_RATE * 2
	var data := PackedByteArray()
	data.resize(n * 2)
	var low := 0.0
	var tick := 0.0
	for i in n:
		low += (rng.randf_range(-1.0, 1.0) - low) * 0.35
		if rng.randf() < 0.004:
			tick = rng.randf_range(0.3, 0.8)
		tick *= 0.86
		var v := clampf(low * 0.5 + tick * rng.randf_range(-1.0, 1.0), -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 20000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = MIX_RATE
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = n
	return s
