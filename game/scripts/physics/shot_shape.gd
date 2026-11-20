class_name ShotShape
extends RefCounted
## Draw, fade, high and low: the round's simple face on Links 2003's shot
## setup (ball position, club face and stance, LinksLaunch.Setup).
##
## A fade turns the stance (and so the swing path) `curve` degrees left of the
## target and turns the club face back by the same, so the face stays square
## to the target and is open to the path: the ball starts on or just left of
## the target line and curves right. A draw is the reverse. Height moves the
## ball forward in the stance (higher, more spin) or back (lower, less spin),
## one of the game's ball-position steps at a time.
##
## The limits are our own: the game's setup screen limits are not read yet.
##
## Away from Classic Links there is also `spin`, extra backspin, which Links
## 2003 has no setting for: up spins the ball more, so a wedge checks or
## spins back on the green; down takes spin off. How much the ball checks
## still comes from the game's own bounce (club, power, lie and green
## firmness); see backspin_scale.

const MAX_CURVE := 6
const MAX_HEIGHT := 3
const MAX_SPIN := 3
## Backspin kept per extra step: more per step up, less per step down.
const BACKSPIN_MORE_PER_STEP := 0.25
const BACKSPIN_LESS_PER_STEP := 0.15

## Degrees of face open to the path: positive fades, negative draws.
var curve := 0
## Ball-position steps forward of the club's neutral spot: positive is higher.
var height := 0
## Extra backspin steps (not in Classic Links): positive spins more.
var spin := 0


func is_square() -> bool:
	return curve == 0 and height == 0 and spin == 0


func reset() -> void:
	curve = 0
	height = 0
	spin = 0


func nudge_spin(step: int) -> bool:
	var before := spin
	spin = clampi(spin + step, -MAX_SPIN, MAX_SPIN)
	return spin != before


func nudge_curve(step: int) -> bool:
	var before := curve
	curve = clampi(curve + step, -MAX_CURVE, MAX_CURVE)
	return curve != before


func nudge_height(step: int) -> bool:
	var before := height
	height = clampi(height + step, -MAX_HEIGHT, MAX_HEIGHT)
	return height != before


## Extra backspin steps for the shot (ShotModel.backspin): none in Classic
## Links.
func backspin(classic: bool) -> int:
	return 0 if classic else spin


## What `steps` of extra backspin multiply the launch backspin by: 1.75 at
## +3, 0.55 at -3.
static func backspin_scale(steps: int) -> float:
	var k := clampi(steps, -MAX_SPIN, MAX_SPIN)
	return 1.0 + k * (BACKSPIN_MORE_PER_STEP if k > 0 else BACKSPIN_LESS_PER_STEP)


## Scales the backspin of `b` (not its sidespin) by backspin_scale(steps).
static func add_backspin(b: BallState, steps: int) -> void:
	if steps == 0:
		return
	var flat := Vector3(b.velocity.x, 0.0, b.velocity.z)
	if flat.length() < 1e-6:
		return
	var right := flat.normalized().cross(Vector3.UP)
	var back := b.spin.dot(right)
	b.spin += right * back * (backspin_scale(steps) - 1.0)


## The game's setup for `club_short_name` (a LinksLaunch.CLUB_INDEX key).
## Square is the game's own default (ball position -1, the club's neutral).
func to_setup(club_short_name: String) -> LinksLaunch.Setup:
	var s := LinksLaunch.Setup.new()
	s.stance = 30 - curve
	s.face = 30 + curve
	if height != 0:
		var neutral := LinksLaunch.neutral_ball_position(LinksLaunch.CLUB_INDEX.get(club_short_name, 1))
		s.ball_position = maxi(0, neutral - height)
	return s


## "Draw 2, high 1"; empty when square.
func describe() -> String:
	var parts: Array[String] = []
	if curve != 0:
		parts.append("%s %d" % ["Fade" if curve > 0 else "Draw", absi(curve)])
	if height != 0:
		parts.append("%s %d" % ["high" if height > 0 else "low", absi(height)])
	if spin != 0:
		parts.append("%s %d" % ["backspin" if spin > 0 else "less spin", absi(spin)])
	if parts.is_empty():
		return ""
	var text := ", ".join(parts)
	return text.substr(0, 1).to_upper() + text.substr(1)
