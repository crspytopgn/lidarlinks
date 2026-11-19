class_name RoundCamera
extends Camera3D
## The round's camera, framed the way Links 2003 frames a shot: low behind
## the ball looking down the aim line with the golfer large in the lower
## half; during the shot it holds its place and turns to follow the ball,
## then for longer shots cuts to a view near where the ball comes down,
## watching it land and roll. The next shot cuts straight back behind the
## ball. Distances are by eye from the original (needs data for exact feel).
##
## With `broadcast` set (the Broadcast presentation) a ShotDirector cuts
## between TV-style cameras instead, and each hole opens with a flyover.

## Behind the ball, and how high, for full shots and putts.
const AIM_BACK := 4.2
const AIM_UP := 1.75
const PUTT_BACK := 2.6
const PUTT_UP := 1.2
## The aim view looks at a point this far down the line, this high.
## The Broadcast presentation's tee and fairway view, framed like a TV
## golf broadcast (and PGA Tour 2K25): lower, at the golfer's hip, and
## closer, so he stands tall in the frame from his shoes up, the horizon
## near the middle and the hole beyond compressed by the long lens.
const BROADCAST_AIM_BACK := 3.3
const BROADCAST_AIM_UP := 1.15
const AIM_LOOK_AHEAD := 70.0
const AIM_LOOK_UP := 2.0
## The aim camera climbs (and steps back) at most this far to see over a
## rise. It was 4 m: on a blind tee shot (Kettle Hollow's 1st) the very first
## view of a round became a high, toy-like look down on the golfer, where TV
## golf and 2K25 keep the camera low behind him and leave a blind shot blind
## (the HUD says BLIND and the aim marker shows the target).
const AIM_MAX_LIFT := 1.5
## Off a tee shelf above a downhill hole the fairway can drop out of sight
## under the tee's own front edge. The golfer still fills the foot of the
## frame from a little higher, as TV's raised tee cameras show, so a target
## at least DOWNHILL_DROP below the ball lets the camera climb this far.
const AIM_DOWNHILL_LIFT := 4.0
const DOWNHILL_DROP := 4.0
const AIM_FRAME_FOV := 50.0  ## framing over a rise assumes at most this vertical field of view
const PUTT_LOOK_AHEAD := 6.0
## Shots that carry further than this get the landing view.
const LANDING_VIEW_MIN_CARRY := 70.0
## The landing view sits short of the landing point and off to the side,
## and takes over when the ball has this much of its flight left.
const LANDING_SHORT := 30.0
const LANDING_SIDE := 14.0
const LANDING_UP := 4.0
const LANDING_CUT_LEFT := 2.2  ## seconds before the first landing
const KEEP_ABOVE_GROUND := 1.0

## Quick pace (GraphicsSettings.quick_pace): a shorter hole flyover.
var quick := false
var terrain: CourseTerrain
var _look := Vector3.ZERO
var _look_now := Vector3.ZERO
var _shot: ShotResult
var _landing_time := -1.0
var _cut_to_landing := false
## TV-style cameras (ShotDirector) instead of the Links framing.
var broadcast := false
## Broadcast: one camera that trails the ball through the flight and the
## roll (ShotDirector follow_ball) rather than the TV cuts.
var follow_ball := false
var director: ShotDirector
## Things only the camera keeps out of: the gallery's grandstands.
var blockers: ObstacleField
## The golfer playing the shot; the putting camera keeps clear of them.
var golfer: Node3D
var _variant := 0
var _aim_pos := Vector3.ZERO
var _aim_look := Vector3.ZERO
## Hole flyover: a path the camera flies before the first shot; empty when
## not flying.
var _fly_path := PackedVector3Array()
var _fly_t := 0.0
var _fly_length := 0.0
var _fly_pin := Vector3.ZERO
var _fly_look_path := PackedVector3Array()
var _fly_step := 1.0
var _fly_dt := 1.0 / 60.0

## The TV cameraman (Broadcast only). A long lens on a tripod is never
## quite still: the operator's hand drifts it a few hundredths of a degree,
## more while panning after the ball, and the pan itself lags the ball
## a little and settles with the faintest overshoot when it stops. The
## Classic Links camera stays locked off, as in the original.
const OPERATOR_DRIFT_DEG := 0.05  ## resting on the tripod
const OPERATOR_PAN_DEG := 0.14  ## extra while following a ball in the air
const OPERATOR_FOLLOW := 13.5  ## pan spring, radians per second
const OPERATOR_DAMPING := 0.85  ## below 1: a slight overshoot as the pan stops
var _look_vel := Vector3.ZERO
var _operator_t := 0.0
var _operator_pan := 0.0  ## 0 resting to 1 panning, eased so the drift never jumps

const FLYOVER_SPEED := 45.0  ## metres per second along the path
const FLYOVER_MIN_S := 6.0
const FLYOVER_MAX_S := 12.0
## Quick pace: the hole flyover at this share of its time (a click still
## ends it).
const QUICK_FLYOVER := 0.6
const FLYOVER_UP := 38.0
const FLYOVER_LOW := 7.0  ## height over the green at the end of the flyover
const FLY_STEP := 2.0  ## metres between the flyover path's samples
const FLY_SMOOTH_SAMPLES := 10  ## corner rounding, samples either side
const FLY_SIDE := 15.0  ## the flyover clears the ground this far either side
const FLY_GROUND_SLOPE := 0.25  ## steepest climb or drop it makes for the ground
const FLY_HEIGHT_SMOOTH := 40.0  ## metres the height changes are spread over, at least
const FLY_HEIGHT_SMOOTH_S := 1.0  ## and at least this many seconds of flight
const FLY_LOOK_AHEAD := 90.0  ## metres along the path the camera looks
const FLY_APPROACH := 30.0  ## the last turn in, short of the pin
const FLY_EASE_IN := 0.25
const FLY_EASE_OUT := 0.35


## Snaps behind the ball, looking down the aim line `dir` (flat, unit).
func aim(ball: Vector3, dir: Vector3, putting: bool, reach := 0.0) -> void:
	_shot = null
	var lens := lens_factor(fov)
	var tv := broadcast and not putting
	var back := (PUTT_BACK if putting else (BROADCAST_AIM_BACK if tv else AIM_BACK)) * lens
	var up := (PUTT_UP if putting else (BROADCAST_AIM_UP if tv else AIM_UP)) * (1.0 + (lens - 1.0) * 0.4)
	var pos := _above_ground(ball - dir * back + Vector3.UP * up)
	if putting:
		_look = ball + dir * PUTT_LOOK_AHEAD
	else:
		var ahead := ball + dir * AIM_LOOK_AHEAD
		_look = Vector3(ahead.x, maxf(ball.y, _ground(ahead)) + AIM_LOOK_UP, ahead.z)
		# A rise in front can hide where the shot is going: lift the camera
		# until it can see the target, and look at the target.
		if reach > AIM_LOOK_AHEAD and terrain != null:
			var far := ball + dir * reach
			var target := Vector3(far.x, _ground(far) + 1.0, far.z)
			if not sight_clear(terrain, pos, target) and _aim_over_rise(ball, dir, pos, target):
				return
		# A long lens from further back puts the ball near the bottom edge:
		# pitch down until it sits 60% of the way there (85% put the ball
		# and the golfer's shoes under the swing meter and caddie line, and
		# half the frame was sky; 2K25's tee view holds the horizon about
		# 40% down).
		var half := deg_to_rad(minf(fov, AIM_FRAME_FOV)) * 0.5
		var pitch := _angle_below(pos, ball) - half * 0.6
		if pitch > _angle_below(pos, _look):
			var flat := Vector3(dir.x, 0.0, dir.z).normalized()
			_look = pos + flat * AIM_LOOK_AHEAD + Vector3.DOWN * tan(pitch) * AIM_LOOK_AHEAD
	_aim_pos = pos
	_aim_look = _look
	if flying():
		return
	position = pos
	_look_now = _look
	look_at(_look_now)


## How much further back the aim view stands with a narrower lens than
## the 50 degrees its distances were set for, so the golfer stays the same
## size in frame while the hole behind him is compressed, as on TV.
static func lens_factor(fov_degrees: float) -> float:
	return clampf(tan(deg_to_rad(25.0)) / tan(deg_to_rad(clampf(fov_degrees, 30.0, 90.0) * 0.5)), 0.6, 1.8)


## Stands at `pos` looking at `look`, for reading a putt (GreenRead.View).
func look_from(pos: Vector3, look: Vector3) -> void:
	_shot = null
	if flying():
		end_flyover()
	position = pos
	_look = look
	_look_now = look
	look_at(look)
## The aim view when a rise hides the target. Links always shows the golfer
## and ball at address, so the camera only climbs a little (and steps back
## as it climbs) and pitches down to keep them in the lower part of the
## frame; over a big rise the target can still be out of sight.
func _aim_over_rise(ball: Vector3, dir: Vector3, start: Vector3, target: Vector3) -> bool:
	var half := deg_to_rad(minf(fov, AIM_FRAME_FOV)) * 0.5
	var feet := ball + Vector3.UP * 0.1
	var pos := start
	var cleared := false
	var max_lift := AIM_DOWNHILL_LIFT if target.y < ball.y - DOWNHILL_DROP else AIM_MAX_LIFT
	var steps := 3 if max_lift <= AIM_MAX_LIFT else 6
	for step in range(1, steps + 1):
		var lift := max_lift * step / float(steps)
		pos = _above_ground(start - dir * minf(lift, AIM_MAX_LIFT) + Vector3.UP * lift)
		if sight_clear(terrain, pos, target):
			cleared = true
			break
	# Truly blind (a crest no small lift sees over): keep the usual low
	# view down the line, as TV and 2K25 do, rather than climbing and
	# pitching down on to the golfer.
	if not cleared:
		return false
	var down_to_target := _angle_below(pos, target)
	var down_to_feet := _angle_below(pos, feet)
	# The feet sit 60% of the way to the bottom edge; the target shows above
	# them when the frame is tall enough.
	var pitch := down_to_feet - half * 0.6
	pitch = maxf(pitch, minf(down_to_target, down_to_feet))
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	_look = pos + flat * 100.0 + Vector3.DOWN * tan(pitch) * 100.0
	_aim_pos = pos
	_aim_look = _look
	if flying():
		return true
	position = pos
	_look_now = _look
	look_at(_look_now)
	return true


## Angle below the horizontal from `from` to `to`, radians.
static func _angle_below(from: Vector3, to: Vector3) -> float:
	var flat := Vector2(to.x - from.x, to.z - from.z).length()
	return atan2(from.y - to.y, flat)


## Starts following a shot. `pin` and `putting` steer the broadcast cameras;
## `variant` picks between their alternatives (replays pass a new one).
func follow(shot: ShotResult, pin := Vector3.ZERO, putting := false, variant := -1) -> void:
	_shot = shot
	_cut_to_landing = false
	_landing_time = -1.0
	end_flyover()
	director = null
	if broadcast:
		if variant < 0:
			_variant += 1
			variant = _variant
		director = ShotDirector.plan(shot, pin, terrain, position, putting, variant, blockers, follow_ball)
		director.golfer = golfer
		return
	if shot.carry_m >= LANDING_VIEW_MIN_CARRY:
		_landing_time = time_near(shot, shot.first_landing)


## Moves the camera for time `t` into the shot (or just eases the view when
## no shot is playing).
func update(delta: float, t: float, ball: Vector3) -> void:
	if flying():
		_update_flyover(delta)
		return
	# Until the club meets the ball (t still 0) the view holds the address
	# framing: looking down at the ball the moment the downswing began
	# tilted the picture away and back again within half a second.
	var struck := t > 0.0
	if _shot != null and director != null:
		var pose := director.step(t, ball, position, delta)
		position = pose[0]
		if struck:
			_look = pose[1]
			if pose[2]:
				_look_now = _look
	elif _shot != null and struck:
		if not _cut_to_landing and _landing_time > 0.0 and t >= _landing_time - LANDING_CUT_LEFT:
			_cut_to_landing = true
			_place_for_landing()
			_look_now = ball
		_look = ball
	var snapped := _look_now == _look
	if broadcast:
		# A damped spring rather than an ease, so the pan trails the ball
		# and settles the way a person's does.
		if snapped:
			_look_vel = Vector3.ZERO
		var dt := minf(delta, 0.05)
		var acc := (_look - _look_now) * OPERATOR_FOLLOW * OPERATOR_FOLLOW - _look_vel * 2.0 * OPERATOR_DAMPING * OPERATOR_FOLLOW
		_look_vel += acc * dt
		_look_now += _look_vel * dt
	else:
		_look_now = _look_now.lerp(_look, 1.0 - exp(-delta * 8.0))
	var to_look := _look_now - position
	if to_look.length() > 0.1 and absf(to_look.normalized().y) < 0.99:
		look_at(_look_now)
		if broadcast:
			_operator_t += delta
			var panning := 1.0 if _shot != null and director != null else 0.0
			_operator_pan = move_toward(_operator_pan, panning, delta * 0.8)
			var off := operator_offset(_operator_t, _operator_pan)
			rotate_object_local(Vector3.UP, off.x)
			rotate_object_local(Vector3.RIGHT, off.y)


## The operator's drift at time `t` seconds, `panning` 0 to 1, as (yaw,
## pitch) in radians:
## a few incommensurate slow sways, so it never visibly repeats.
static func operator_offset(t: float, panning: float) -> Vector2:
	var amp := deg_to_rad(OPERATOR_DRIFT_DEG + OPERATOR_PAN_DEG * panning)
	var yaw := sin(t * 0.71) + 0.6 * sin(t * 1.93 + 1.3) + 0.3 * sin(t * 4.1 + 0.4)
	var pitch := sin(t * 0.53 + 2.1) + 0.6 * sin(t * 1.61 + 0.7) + 0.3 * sin(t * 3.7 + 2.9)
	return Vector2(yaw, pitch * 0.7) * amp / 1.9


## Flies over the hole from behind the tee, along its route, down to the
## green, then settles behind the ball (wherever aim() last put it).
##
## Built like a TV flyover: the route is turned into one smooth curve and
## sampled every FLY_STEP metres by distance, so the speed along it is even
## (a spline stepped by control point raced down long legs and crawled
## round short ones); the height follows a smoothed envelope of the ground
## that never climbs or drops faster than FLY_GROUND_SLOPE (no bobbing over
## every mound); the camera looks at a point a fixed distance ahead, also
## smoothed, so the view turns gently into a dogleg before the camera does;
## and the speed eases in and out rather than peaking mid-hole.
func start_flyover(hole: HoleData) -> void:
	_fly_path = PackedVector3Array()
	_fly_look_path = PackedVector3Array()
	_fly_pin = hole.pin
	var xz := fly_route(hole)
	xz = _resample(_spline(xz), FLY_STEP)
	xz = _smooth_line(xz, FLY_SMOOTH_SAMPLES)
	xz = _resample(xz, FLY_STEP)
	var n := xz.size()
	_fly_length = 0.0
	for i in range(1, n):
		_fly_length += xz[i - 1].distance_to(xz[i])
	_fly_step = _fly_length / maxf(n - 1, 1)
	# The ground under the path and either side of it.
	var under := PackedFloat32Array()
	var wide := PackedFloat32Array()
	under.resize(n)
	wide.resize(n)
	for i in n:
		var tangent := (xz[mini(i + 1, n - 1)] - xz[maxi(i - 1, 0)]).normalized()
		var side := Vector2(-tangent.y, tangent.x) * FLY_SIDE
		var g := _ground2(xz[i])
		under[i] = g
		wide[i] = maxf(g, maxf(_ground2(xz[i] + side), _ground2(xz[i] - side)))
	# Cone envelope: the highest ground nearby, less FLY_GROUND_SLOPE per
	# metre away, so rises are seen coming and the climb starts early.
	var drop := FLY_GROUND_SLOPE * _fly_step
	for i in range(1, n):
		wide[i] = maxf(wide[i], wide[i - 1] - drop)
	for i in range(n - 2, -1, -1):
		wide[i] = maxf(wide[i], wide[i + 1] - drop)
	# Then the highest of that within 3R and three moving averages R wide:
	# smooth over a second or more of flight (three passes leave no kinks
	# in the climb rate), and still never below it, since each average only
	# mixes in maxima whose window held this point.
	var spread := maxf(FLY_HEIGHT_SMOOTH, _fly_length / _fly_seconds() * FLY_HEIGHT_SMOOTH_S)
	var r := maxi(1, roundi(spread * 0.67 / maxf(_fly_step, 0.01)))
	var floor_h := _running_max(wide, 3 * r)
	for _pass in 3:
		floor_h = _smooth_values(floor_h, r)
	var ground_s := _smooth_values(_smooth_values(under, 10), 10)
	var ahead := maxi(1, roundi(FLY_LOOK_AHEAD / maxf(_fly_step, 0.01)))
	for i in n:
		var s := i * _fly_step
		var c := fly_clearance(s, _fly_length)
		var h := maxf(floor_h[i] + c, under[i] + KEEP_ABOVE_GROUND + 2.0)
		_fly_path.append(Vector3(xz[i].x, h, xz[i].y))
		var j := mini(i + ahead, n - 1)
		var look := Vector3(xz[j].x, ground_s[j], xz[j].y)
		_fly_look_path.append(look.lerp(_fly_pin, smoothstep(0.45, 0.85, s / maxf(_fly_length, 1.0))))
	_fly_look_path = _smooth_points(_smooth_points(_fly_look_path, 10), 10)
	_fly_t = 0.0
	_fly_dt = 1.0 / 60.0
	position = _fly_path[0]
	_look_now = _fly_look_path[0]
	_look = _look_now
	look_at(_look_now)


## The flyover's line over the ground, (x, z): from behind the tee, along
## the route, to a low spot short of the green and a little to one side.
## Route points on top of the tee or close to the green are skipped (they
## made the old path double back on itself).
static func fly_route(hole: HoleData) -> PackedVector2Array:
	var tee := Vector2(hole.tee.x, hole.tee.z)
	var pin := Vector2(hole.pin.x, hole.pin.z)
	var pts := PackedVector2Array([tee])
	for r in hole.route:
		if r.distance_to(pts[pts.size() - 1]) > 8.0 and r.distance_to(pin) > FLY_APPROACH + 5.0:
			pts.append(r)
	var into := pin - pts[pts.size() - 1]
	if into.length() < 1.0:
		into = Vector2(0.0, 1.0)  # a hole with the pin on the tee: fly straight down +z
		pin = tee + into * 60.0
	var first := (pts[1] - pts[0]) if pts.size() > 1 else into
	first = first.normalized()
	var last := into.normalized()
	var out := PackedVector2Array([tee - first * 40.0])
	out.append_array(pts)
	if pin.distance_to(pts[pts.size() - 1]) > FLY_APPROACH + 1.0:
		out.append(pin - last * FLY_APPROACH)
	out.append(pin - last * 14.0 + Vector2(-last.y, last.x) * 6.0)
	return out


## Height above the (smoothed) ground at distance `s` of `length`: a little
## lower behind the tee, the full height along the hole, gliding down to a
## low view of the green over the last stretch.
static func fly_clearance(s: float, length: float) -> float:
	var descend := clampf(length * 0.45, 40.0, 170.0)
	var low := smoothstep(0.0, 1.0, clampf((length - s) / descend, 0.0, 1.0))
	var c := lerpf(FLYOVER_LOW, FLYOVER_UP, low * low * (3.0 - 2.0 * low))
	return c * lerpf(0.8, 1.0, smoothstep(0.0, 200.0, s))


## Centripetal Catmull-Rom through `pts`, sampled about every metre (no
## loops or overshoot where the points are unevenly spaced).
static func _spline(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in range(n - 1):
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p0 := pts[i - 1] if i > 0 else p1 * 2.0 - p2
		var p3 := pts[i + 2] if i + 2 < n else p2 * 2.0 - p1
		var steps := maxi(2, ceili(p1.distance_to(p2)))
		for k in steps:
			out.append(_centripetal(p0, p1, p2, p3, float(k) / steps))
	out.append(pts[n - 1])
	return out


static func _centripetal(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, u: float) -> Vector2:
	var t1 := sqrt(maxf(p0.distance_to(p1), 0.01))
	var t2 := t1 + sqrt(maxf(p1.distance_to(p2), 0.01))
	var t3 := t2 + sqrt(maxf(p2.distance_to(p3), 0.01))
	var t := lerpf(t1, t2, u)
	var a1 := p0 * (t1 - t) / t1 + p1 * t / t1
	var a2 := p1 * (t2 - t) / (t2 - t1) + p2 * (t - t1) / (t2 - t1)
	var a3 := p2 * (t3 - t) / (t3 - t2) + p3 * (t - t2) / (t3 - t2)
	var b1 := a1 * (t2 - t) / t2 + a2 * t / t2
	var b2 := a2 * (t3 - t) / (t3 - t1) + a3 * (t - t1) / (t3 - t1)
	return b1 * (t2 - t) / (t2 - t1) + b2 * (t - t1) / (t2 - t1)


## `line` re-sampled at even spacing of about `step` metres, ends kept.
static func _resample(line: PackedVector2Array, step: float) -> PackedVector2Array:
	var n := line.size()
	var along := PackedFloat32Array([0.0])
	for i in range(1, n):
		along.append(along[i - 1] + line[i - 1].distance_to(line[i]))
	var total := along[n - 1]
	var count := maxi(1, ceili(total / step))
	var out := PackedVector2Array()
	var j := 0
	for k in count + 1:
		var s := total * k / count
		while j < n - 2 and along[j + 1] < s:
			j += 1
		var seg := along[mini(j + 1, n - 1)] - along[j]
		var f := clampf((s - along[j]) / seg, 0.0, 1.0) if seg > 0.0 else 0.0
		out.append(line[j].lerp(line[mini(j + 1, n - 1)], f))
	return out


## Three passes of a moving average `radius` samples either side, the ends
## held (a window that narrowed towards the ends put a kink in the motion
## where it reached full width).
static func _smooth_line(line: PackedVector2Array, radius: int) -> PackedVector2Array:
	for _pass in 3:
		var out := line.duplicate()
		var n := line.size()
		for i in n:
			var sum := Vector2.ZERO
			for k in range(i - radius, i + radius + 1):
				sum += line[clampi(k, 0, n - 1)]
			out[i] = sum / (2 * radius + 1)
		line = out
	return line


static func _running_max(v: PackedFloat32Array, radius: int) -> PackedFloat32Array:
	var out := v.duplicate()
	var n := v.size()
	for i in n:
		var m := v[i]
		for k in range(maxi(i - radius, 0), mini(i + radius, n - 1) + 1):
			m = maxf(m, v[k])
		out[i] = m
	return out


static func _smooth_points(pts: PackedVector3Array, radius: int) -> PackedVector3Array:
	var out := pts.duplicate()
	var n := pts.size()
	for i in n:
		var sum := Vector3.ZERO
		for k in range(i - radius, i + radius + 1):
			sum += pts[clampi(k, 0, n - 1)]
		out[i] = sum / (2 * radius + 1)
	return out


static func _smooth_values(v: PackedFloat32Array, radius: int) -> PackedFloat32Array:
	var out := v.duplicate()
	var n := v.size()
	for i in n:
		var sum := 0.0
		for k in range(i - radius, i + radius + 1):
			sum += v[clampi(k, 0, n - 1)]
		out[i] = sum / (2 * radius + 1)
	return out


func flying() -> bool:
	return _fly_path.size() > 1


## Ends a flyover early (a click) or once it's done, cutting behind the ball.
func end_flyover() -> void:
	if not flying():
		return
	_fly_path = PackedVector3Array()
	_fly_look_path = PackedVector3Array()
	position = _aim_pos
	_look = _aim_look
	_look_now = _look
	look_at(_look_now)


func flyover_progress() -> float:
	return clampf(_fly_t / _fly_seconds(), 0.0, 1.0) if flying() else 1.0


func _fly_seconds() -> float:
	var s := clampf(_fly_length / FLYOVER_SPEED, FLYOVER_MIN_S, FLYOVER_MAX_S)
	return s * QUICK_FLYOVER if quick else s


func _update_flyover(delta: float) -> void:
	# A frame far slower than the ones before it (the course still streaming
	# in as the hole opens) moves the camera on by about a normal frame, so
	# the glide slows for an instant rather than jumping.
	# (Paused frames, delta 0, leave the running average alone.)
	var dt := minf(delta, maxf(_fly_dt * 2.0, 1.0 / 30.0))
	if dt > 0.0:
		_fly_dt = lerpf(_fly_dt, dt, 0.1)
	_fly_t += dt
	var u := _fly_t / _fly_seconds()
	if u >= 1.0:
		end_flyover()
		return
	var s := fly_ease(u) * _fly_length
	position = _above_ground(_fly_sample(_fly_path, s))
	_look_now = _fly_sample(_fly_look_path, s)
	_look = _look_now
	var to_look := _look_now - position
	if to_look.length() > 0.1 and absf(to_look.normalized().y) < 0.99:
		look_at(_look_now)


## Share of the path flown at share `u` of the time: the speed rises
## smoothly over the first FLY_EASE_IN, holds, and falls away over the last
## FLY_EASE_OUT (a smoothstep over the whole flight peaked at 1.5 times the
## average speed in the middle of the hole).
static func fly_ease(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	var a := FLY_EASE_IN
	var b := FLY_EASE_OUT
	var total := 1.0 - a * 0.5 - b * 0.5
	var d: float
	if u < a:
		d = a * _ramp_area(u / a)
	elif u > 1.0 - b:
		d = total - b * _ramp_area((1.0 - u) / b)
	else:
		d = a * 0.5 + (u - a)
	return d / total


## Area under smoothstep from 0 to `x`.
static func _ramp_area(x: float) -> float:
	return x * x * x - x * x * x * x * 0.5


## The point `s` metres along an evenly spaced flyover path.
func _fly_sample(path: PackedVector3Array, s: float) -> Vector3:
	var n := path.size()
	var f := clampf(s / maxf(_fly_step, 0.001), 0.0, n - 1.0)
	var i := mini(int(f), n - 2)
	# Catmull-Rom through the samples, so speed and turn never kink at one.
	var p0 := path[maxi(i - 1, 0)]
	var p3 := path[mini(i + 2, n - 1)]
	return path[i].cubic_interpolate(path[i + 1], p0, p3, f - i)


func _ground2(p: Vector2) -> float:
	return terrain.height_at(p.x, p.y) if terrain != null else 0.0


func _place_for_landing() -> void:
	var land := _shot.first_landing
	var start := _shot.points[0] if _shot.points.size() > 0 else land
	var dir := Vector3(land.x - start.x, 0.0, land.z - start.z)
	dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
	var right := dir.cross(Vector3.UP)
	# Off to the side short of the landing, on whichever side (and at
	# whatever distance) keeps the camera out of the trees.
	var fallback := Vector3.INF
	for side: float in [1.0, -1.0]:
		for short: float in [LANDING_SHORT, LANDING_SHORT * 0.6, LANDING_SHORT * 1.5]:
			var p := _above_ground(land - dir * short + right * side * LANDING_SIDE + Vector3.UP * LANDING_UP)
			if ShotDirector.view_clear(terrain, p, land + Vector3.UP, blockers):
				position = p
				return
			if fallback == Vector3.INF and not ShotDirector.near_obstacle(terrain, p, blockers):
				fallback = p
	if fallback == Vector3.INF:
		fallback = _above_ground(land - dir * LANDING_SHORT + right * LANDING_SIDE + Vector3.UP * LANDING_UP)
		for i in 8:
			if not ShotDirector.near_obstacle(terrain, fallback, blockers):
				break
			fallback.y += 4.0
	position = fallback


## True if no ground lies between `from` and `to`.
static func sight_clear(t: CourseTerrain, from: Vector3, to: Vector3) -> bool:
	const STEPS := 40
	for i in range(2, STEPS):
		var p := from.lerp(to, float(i) / STEPS)
		if t.height_at(p.x, p.z) > p.y:
			return false
	return true


func _above_ground(p: Vector3) -> Vector3:
	return Vector3(p.x, maxf(p.y, _ground(p) + KEEP_ABOVE_GROUND), p.z)


func _ground(p: Vector3) -> float:
	return terrain.height_at(p.x, p.z) if terrain != null else p.y


## Time of the flight sample closest to `p`.
static func time_near(shot: ShotResult, p: Vector3) -> float:
	var best := -1.0
	var best_d := INF
	for i in shot.points.size():
		var d := shot.points[i].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = shot.times[i]
	return best
