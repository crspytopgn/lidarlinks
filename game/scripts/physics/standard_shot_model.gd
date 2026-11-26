class_name StandardShotModel
extends ShotModel
## Published real-world golf ball physics (BallPhysics), standing in until the
## model is tuned against the original game.


## How the stand-in model shapes a shot from the setup (ShotModel.setup):
## the share of the face angle the ball starts along (the rest follows the
## path), sidespin per degree of face open or closed to the path, and the
## launch angle and backspin per ball-position step. Real-world ballpark
## figures; LinksShotModel uses the game's own launch instead.
const START_ALONG_FACE := 0.75
const SIDESPIN_RPM_PER_DEG := 160.0
const LAUNCH_DEG_PER_STEP := 1.0
const BACKSPIN_PER_STEP := 0.05


func launch(club: Club, power: float, accuracy: float, aim_deg: float, lie: int, from: Vector3) -> BallState:
	if club.is_putter:
		var p := Swing.launch_from_swing(club, power, accuracy, aim_deg, lie)
		p.position = from
		return p
	# Links 2003's setup steps: face and stance square at 30, degrees either
	# way; above 30 opens (the ball starts right). The stance turns the path
	# and the face with it.
	var face := float(setup.face - 30 + setup.stance - 30)
	var path := float(setup.stance - 30)
	var start := START_ALONG_FACE * face + (1.0 - START_ALONG_FACE) * path
	var s := Swing.launch_from_swing(club, power, accuracy, aim_deg - start, lie)
	var back := 0
	if setup.ball_position >= 0:
		back = setup.ball_position - LinksLaunch.neutral_ball_position(LinksLaunch.CLUB_INDEX.get(club.short_name, 1))
	if back != 0 or face != path:
		var right := Vector3(s.velocity.x, 0.0, s.velocity.z).normalized().cross(Vector3.UP)
		# Ball back: lower launch, less spin. Forward: the reverse.
		s.velocity = s.velocity.rotated(right, -deg_to_rad(LAUNCH_DEG_PER_STEP * back))
		var back_spin := s.spin.dot(right)
		var side := s.spin.dot(Vector3.UP)
		back_spin *= maxf(0.2, 1.0 - BACKSPIN_PER_STEP * back)
		# A face open to the path slices (negative sidespin, as a late swing).
		side -= (face - path) * SIDESPIN_RPM_PER_DEG * BallPhysics.RPM_TO_RAD_S
		s.spin = right * back_spin + Vector3.UP * side
	ShotShape.add_backspin(s, backspin)
	# The player's hitting distance (PlayerPower): a faster ball, same spin.
	s.velocity *= PlayerPower.standard_speed(power_profile, club)
	s.position = from
	return s


## The player's hitting distance sends a full swing the profile's total.
func reach_scale(club: Club) -> float:
	var want := PlayerPower.total_m(power_profile, club)
	return want / club.total_m if want > 0.0 and club.total_m > 0.0 else 1.0


func simulate(start: BallState, terrain: CourseTerrain, cup: Vector3, wind := Vector3.ZERO) -> ShotResult:
	return BallPhysics.simulate_shot(start, terrain, true, cup, wind)


func simulate_chunked(start: BallState, terrain: CourseTerrain, cup: Vector3, wind := Vector3.ZERO) -> ResumableShot:
	return ResumableShot.new(start, terrain, true, cup, wind)
