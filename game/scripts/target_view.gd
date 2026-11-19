class_name TargetView
extends RefCounted
## "View target": the camera leaves the address view behind the ball,
## glides out to stand above and short of where the shot is aimed and looks
## down on the landing area, then glides home again. It is the look at the
## landing zone that PGA Tour 2K25 and GSPro give on a button. The player
## can keep aiming while out there (the view follows the aim point) and the
## swing waits until the camera is back behind the ball.
##
## The round (main.gd) steps it each frame in place of RoundCamera.update,
## and puts the camera exactly back on the aim view when it lands home.

## Seconds to fly out, and home again.
const OUT_S := 1.15
const HOME_S := 0.85
## Full shots: the view stands this share of the shot's length short of the
## target, and this share of it above, within these bounds (metres). A drive
## of 250 m stands 55 m short and 19 m up, looking down at about 20 degrees,
## low enough to see the green beyond, as 2K25's landing view does.
const BACK_SHARE := 0.22
const BACK_MIN := 16.0
const BACK_MAX := 55.0
const UP_SHARE := 0.075
const UP_MIN := 6.0
const UP_MAX := 20.0
## Putts and short chips: a low look from just short of the hole.
const SHORT_SHOT_M := 25.0
const PUTT_BACK := 3.0
const PUTT_UP := 1.6
## The look falls a little past the target, so the target sits a touch below
## the middle of the frame with the ground beyond it in view.
const LOOK_PAST_SHARE := 0.06
const LOOK_PAST_MAX := 12.0
## Kept at least this far above the ground on the way and at the end, and
## lifted up to this much more (in steps) if a rise hides the target.
const CLEARANCE := 2.0
const MAX_EXTRA_LIFT := 30.0
## On a long glide the camera rises this share of the way it travels above
## the straight line, so it flies over what lies between rather than
## skimming it (at most ARC_MAX metres).
const ARC_SHARE := 0.12
const ARC_MAX := 22.0

enum Phase { HOME, OUT, THERE, BACK }

var phase := Phase.HOME
var terrain: CourseTerrain
var position := Vector3.ZERO
var look := Vector3.ZERO
var _t := 0.0
var _from_pos := Vector3.ZERO
var _from_look := Vector3.ZERO
var _to_pos := Vector3.ZERO
var _to_look := Vector3.ZERO
var _home_pos := Vector3.ZERO
var _home_look := Vector3.ZERO
var _arc := 0.0


## True while the camera is out at the target or on its way there or back.
func busy() -> bool:
	return phase != Phase.HOME


## True while it is going to, or standing at, the target (not on its way home).
func out() -> bool:
	return phase == Phase.OUT or phase == Phase.THERE


## Where the camera stands to look at `target`, aimed from `ball`, and what
## it looks at: [position, look].
static func pose(t: CourseTerrain, ball: Vector3, target: Vector3, putting: bool) -> Array:
	var flat := Vector3(target.x - ball.x, 0.0, target.z - ball.z)
	var dist := flat.length()
	var dir := flat / dist if dist > 0.01 else Vector3.FORWARD
	var short := putting or dist < SHORT_SHOT_M
	var back := clampf(dist * 0.5, 1.5, PUTT_BACK) if short else clampf(dist * BACK_SHARE, BACK_MIN, BACK_MAX)
	var up := PUTT_UP if short else clampf(dist * UP_SHARE, UP_MIN, UP_MAX)
	var ground_at := _height(t, target)
	var past := 0.0 if short else minf(dist * LOOK_PAST_SHARE, LOOK_PAST_MAX)
	var seen := target + dir * past
	var view_at := Vector3(seen.x, _height(t, seen) + (0.0 if short else 0.5), seen.z)
	var spot := target - dir * back
	var pos := _above(t, Vector3(spot.x, maxf(ground_at, _height(t, spot)) + up, spot.z))
	# A rise between the camera and the target (a crest, a bunker face):
	# climb until it is in sight.
	if t != null and not short:
		var aim := Vector3(target.x, ground_at + 0.3, target.z)
		var lift := 0.0
		while lift < MAX_EXTRA_LIFT and not RoundCamera.sight_clear(t, pos + Vector3.UP * lift, aim):
			lift += 3.0
		pos.y += lift
	return [pos, view_at]


## Flies out from the camera's view now to the target's `to` (pose()).
## `home` is the aim view to come back to ([position, look]).
func start(from_pos: Vector3, from_look: Vector3, to: Array, home: Array) -> void:
	_home_pos = home[0]
	_home_look = home[1]
	_glide(from_pos, from_look, to[0], to[1], Phase.OUT)


## The aim (or the club) changed: follow the new target and remember the
## new aim view to come home to.
func retarget(to: Array, home: Array) -> void:
	_home_pos = home[0]
	_home_look = home[1]
	if phase == Phase.OUT or phase == Phase.THERE:
		_to_pos = to[0]
		_to_look = to[1]
	elif phase == Phase.BACK:
		_to_pos = _home_pos
		_to_look = _home_look


## Glides home from wherever the camera is now.
func go_home() -> void:
	if out():
		_glide(position, look, _home_pos, _home_look, Phase.BACK)


## Turns back out towards `to` (a second press while gliding home).
func go_out(to: Array) -> void:
	if phase == Phase.BACK:
		_glide(position, look, to[0], to[1], Phase.OUT)


## Drops the view at once (the turn moved on); the camera is the round's again.
func cancel() -> void:
	phase = Phase.HOME


## Moves the view on by `delta` seconds. Returns true the frame it lands
## home, when the round puts the camera back on the aim view.
func step(delta: float) -> bool:
	match phase:
		Phase.HOME:
			return false
		Phase.THERE:
			# The aim moved: follow it smoothly rather than jumping.
			var k := 1.0 - exp(-delta * 5.0)
			position = position.lerp(_to_pos, k)
			look = look.lerp(_to_look, k)
			return false
	var length := OUT_S if phase == Phase.OUT else HOME_S
	_t = minf(_t + delta / length, 1.0)
	var u := ease_in_out(_t)
	position = _from_pos.lerp(_to_pos, u) + Vector3.UP * (_arc * sin(PI * u))
	position = _above(terrain, position)
	look = _from_look.lerp(_to_look, u)
	if _t < 1.0:
		return false
	position = _to_pos
	look = _to_look
	if phase == Phase.OUT:
		phase = Phase.THERE
		return false
	phase = Phase.HOME
	return true


## Smoother-step: starts and stops with no jolt in speed or acceleration.
static func ease_in_out(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	return u * u * u * (u * (u * 6.0 - 15.0) + 10.0)


func _glide(from_pos: Vector3, from_look: Vector3, to_pos: Vector3, to_look: Vector3, next: Phase) -> void:
	_from_pos = from_pos
	_from_look = from_look
	_to_pos = to_pos
	_to_look = to_look
	_arc = minf(from_pos.distance_to(to_pos) * ARC_SHARE, ARC_MAX)
	_t = 0.0
	phase = next
	position = from_pos
	look = from_look


## `p`, raised to stay CLEARANCE above the ground.
static func _above(t: CourseTerrain, p: Vector3) -> Vector3:
	if t != null:
		p.y = maxf(p.y, t.height_at(p.x, p.z) + CLEARANCE)
	return p


static func _height(t: CourseTerrain, p: Vector3) -> float:
	return t.height_at(p.x, p.z) if t != null else p.y
