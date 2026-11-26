class_name BallPhysics
extends RefCounted
## Ball flight, bounce and roll: a GDScript port of
## libs/olcore/src/ball_physics.cpp and libs/olcore/src/shot.cpp, so the game
## runs without a compiled extension. Change both together until GDExtension
## replaces this file. See those files for the sources of each formula.
##
## Coordinates: +y up, +z downrange, +x to the golfer's left. SI units.

const MASS := 0.04593
const RADIUS := 0.021335
const AIR_DENSITY := 1.225
const DRAG_COEFFICIENT := 0.24
const DRAG_SPIN_FACTOR := 0.18
const GRAVITY := 9.81
const SPIN_DECAY_PER_S := 0.04
const RPM_TO_RAD_S := TAU / 60.0

# olcore::ShotOptions defaults.
const DT := 0.004
const SAMPLE_EVERY := 4
const MAX_TIME := 60.0
const CUP_RADIUS := 0.054
const MAX_HOLING_SPEED := 1.6
const ROLL_THRESHOLD := 0.4
## A landing this early in a flight step (fraction of the step) counts as on
## the ground at its start (shot.cpp kLandAtStart).
const LAND_AT_START := 0.01
const STOP_SPEED := 0.03
const LOFTED_LAUNCH := 0.1  ## launch v.y / speed above which a shot is in the air
const TAKE_OFF_GAP := 0.005  ## m a step; a rolling ball this far above the ground has left it
const MAX_CRATER_DEG := 30.0
const SOLID_RESTITUTION := 0.35  ## normal speed kept off a trunk or wall
const SOLID_FRICTION := 0.75  ## speed along the face kept
const CANOPY_KEEP := 0.2  ## speed kept going into leaves
const CANOPY_BOUNCE := 0.05  ## normal speed kept coming back out
const OBSTACLE_GAP := 0.01  ## m; keeps the ball off the face it hit
const FLAT_TOP := 0.7  ## normal y above which the ball can rest on a solid


## Mirrors olcore::make_launch. Positive azimuth is left of +z; positive
## sidespin curves the ball left.
static func make_launch(speed: float, launch_deg: float, azimuth_deg: float, backspin_rpm: float, sidespin_rpm: float) -> BallState:
	var el := deg_to_rad(launch_deg)
	var az := deg_to_rad(azimuth_deg)
	var dir := Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az))
	var horiz := Vector3(dir.x, 0.0, dir.z)
	var right := Vector3(-1.0, 0.0, 0.0)
	if horiz.length() > 0.0:
		right = horiz.normalized().cross(Vector3.UP)
	var spin := right * (backspin_rpm * RPM_TO_RAD_S) + Vector3.UP * (sidespin_rpm * RPM_TO_RAD_S)
	return BallState.new(Vector3.ZERO, dir * speed, spin)


## Mirrors olcore::acceleration: gravity, spin-dependent drag, Magnus lift.
## `wind` is the velocity of the air (olcore::BallParams::wind); drag and lift
## act on the ball's velocity through it.
static func acceleration(vel: Vector3, spin: Vector3, wind := Vector3.ZERO) -> Vector3:
	var a := Vector3(0.0, -GRAVITY, 0.0)
	var air := vel - wind
	var speed := air.length()
	if speed < 1e-9:
		return a
	var area := PI * RADIUS * RADIUS
	var q := 0.5 * AIR_DENSITY * area * speed * speed
	var spin_rate := spin.length()
	var spin_ratio := RADIUS * spin_rate / speed
	var cd := DRAG_COEFFICIENT + DRAG_SPIN_FACTOR * spin_ratio
	a += air * (-q * cd / (MASS * speed))
	var wxv := spin.cross(air)
	var wxv_len := wxv.length()
	if wxv_len > 1e-9 and spin_rate > 1e-9:
		var cl := clampf(-0.05 + sqrt(0.0025 + 0.36 * spin_ratio), 0.0, 0.35)
		a += wxv * (q * cl / (MASS * wxv_len))
	return a


## Mirrors olcore::step_flight (RK4, or the game's own step with `aero`).
static func step_flight(s: BallState, dt: float, wind := Vector3.ZERO, aero: LinksAero = null) -> BallState:
	if aero != null:
		return aero.step_flight(s, dt, wind)
	var v1 := s.velocity
	var a1 := acceleration(v1, s.spin, wind)
	var v2 := s.velocity + a1 * (dt / 2.0)
	var a2 := acceleration(v2, s.spin, wind)
	var v3 := s.velocity + a2 * (dt / 2.0)
	var a3 := acceleration(v3, s.spin, wind)
	var v4 := s.velocity + a3 * dt
	var a4 := acceleration(v4, s.spin, wind)
	var out := BallState.new()
	out.position = s.position + (v1 + v2 * 2.0 + v3 * 2.0 + v4) * (dt / 6.0)
	out.velocity = s.velocity + (a1 + a2 * 2.0 + a3 * 2.0 + a4) * (dt / 6.0)
	out.spin = s.spin * maxf(0.0, 1.0 - SPIN_DECAY_PER_S * dt)
	return out


## Mirrors olcore::turf_restitution.
static func turf_restitution(normal_speed: float) -> float:
	var v := absf(normal_speed)
	if v > 20.0:
		return 0.12
	return 0.510 - 0.0375 * v + 0.000903 * v * v


## Mirrors olcore::bounce. Updates s.velocity and s.spin in place.
static func bounce(s: BallState, ground_normal: Vector3, surface: int) -> void:
	var n := ground_normal
	if s.velocity.dot(n) >= 0.0:
		return
	var along := s.velocity - n * s.velocity.dot(n)
	var along_len := along.length()
	var speed := s.velocity.length()
	if along_len > 1e-9 and speed > 1e-9:
		var impact_deg := rad_to_deg(asin(minf(1.0, -s.velocity.dot(n) / speed)))
		var tilt_deg := minf(MAX_CRATER_DEG, Surface.softness(surface) * 15.4 * (speed / 18.6) * (impact_deg / 44.4))
		var tilt := deg_to_rad(tilt_deg)
		n = n * cos(tilt) - along * (sin(tilt) / along_len)

	var vn := s.velocity.dot(n)
	if vn >= 0.0:
		return
	var e := turf_restitution(-vn) * Surface.restitution_scale(surface)
	var jn := (1.0 + e) * -vn
	var vt := s.velocity - n * vn
	var vc := vt + s.spin.cross(n * -RADIUS)
	var vc_len := vc.length()
	if vc_len > 1e-9:
		var j := minf(2.0 / 7.0 * vc_len, Surface.friction(surface) * jn)
		var dir := vc / vc_len
		vt -= dir * j
		s.spin += n.cross(dir) * (2.5 * j / RADIUS)
	s.spin -= n * (s.spin.dot(n) * 0.5)
	s.velocity = vt + n * (-e * vn)


## Mirrors olcore::hit_obstacle: a solid sends the ball back with some of its
## speed; a canopy soaks up most of it, so the ball drops. `hit` comes from
## CourseTerrain.obstacle_hit_into().
static func hit_obstacle(s: BallState, hit: ObstacleField.Hit) -> void:
	var n: Vector3 = hit.normal
	var vn := s.velocity.dot(n)
	if vn >= 0.0:
		return
	var vt := s.velocity - n * vn
	if hit.kind == ObstacleField.Kind.SOLID:
		s.velocity = vt * SOLID_FRICTION - n * (vn * SOLID_RESTITUTION)
		s.spin *= 0.5
	else:
		s.velocity = vt * CANOPY_KEEP - n * (vn * CANOPY_BOUNCE)
		s.spin *= 0.2


## Mirrors olcore::simulate_shot: flight, bounces and roll over the terrain
## until the ball stops, drops, or finds water or out of bounds. `wind` acts
## on the flight only, as in olcore. With `aero` the whole shot uses the Links
## 2003 model (olcore::BallParams::links and LinksGround.simulate_shot).
static func simulate_shot(start: BallState, terrain: CourseTerrain, has_cup := false, cup := Vector3.ZERO, wind := Vector3.ZERO, aero: LinksAero = null) -> ShotResult:
	if aero != null:
		return LinksGround.simulate_shot(start, terrain, has_cup, cup, wind, aero)
	var r := ShotResult.new()
	var s := start.copy()
	var t := 0.0
	var step := 0
	var landed := false
	# One obstacle result for the whole shot, refilled every step: the
	# Dictionary form allocated one per step (and one per candidate hit).
	var hit := ObstacleField.Hit.new()
	# Flat ground with no obstacles at all skips the per-step lookup.
	var has_obstacles := terrain.has_obstacles()
	# The ground under the end of the last rolling step, reused by the next.
	var ahead_at := Vector3(INF, INF, INF)
	var ahead_normal := Vector3.UP
	var ahead_surface := -1
	r.add_sample(0.0, s.position)

	var n0 := terrain.normal_at(s.position.x, s.position.z)
	var vn0 := s.velocity.dot(n0)
	var speed0 := s.velocity.length()
	if vn0 < 2.0 * ROLL_THRESHOLD and s.velocity.y > LOFTED_LAUNCH * speed0:
		# A lofted shot from a lie on a bank (a bunker face) leaves the slope:
		# the club follows the ground, so the launch is off the slope too.
		var lifted := s.velocity + n0 * (maxf(absf(vn0), 2.0 * ROLL_THRESHOLD) - vn0)
		s.velocity = lifted * (speed0 / lifted.length())
	if s.velocity.dot(n0) < -ROLL_THRESHOLD:
		# Struck into a bank steeper than its launch (a bunker face): it meets
		# the ground at once, rather than rolling away at full speed.
		bounce(s, n0, terrain.surface_at(s.position.x, s.position.z))
		r.bounces += 1
	var rolling := s.velocity.dot(n0) < ROLL_THRESHOLD
	if rolling:
		s.velocity -= n0 * s.velocity.dot(n0)
		landed = true
		r.first_landing = s.position

	# The ground height last looked up, and where: the next flight step
	# usually starts where the last one ended, so it is reused (same value).
	var flight_xz := Vector2(INF, INF)
	var flight_y := 0.0
	while t < MAX_TIME:
		if not rolling:
			var nxt := step_flight(s, DT, wind, aero)
			var g0 := flight_y if s.position.x == flight_xz.x and s.position.z == flight_xz.y else terrain.height_at(s.position.x, s.position.z)
			var g1 := terrain.height_at(nxt.position.x, nxt.position.z)
			flight_xz = Vector2(nxt.position.x, nxt.position.z)
			flight_y = g1
			var h0 := s.position.y - g0
			var h1 := nxt.position.y - g1
			t += DT
			step += 1
			r.apex_m = maxf(r.apex_m, nxt.position.y - start.position.y)

			# An obstacle met before the ground. Time keeps the whole step,
			# so a ball wedged between obstacles still runs out of time.
			var ground := (h0 / (h0 - h1) if h0 > 0.0 else 0.0) if h1 <= 0.0 else 2.0
			if has_obstacles and terrain.obstacle_hit_into(s.position, nxt.position, hit) and hit.fraction < ground:
				var f: float = hit.fraction
				var b := BallState.new(s.position.lerp(nxt.position, f), s.velocity.lerp(nxt.velocity, f), nxt.spin)
				hit_obstacle(b, hit)
				# Just outside a solid, or just inside a canopy, so the same
				# face is not met again.
				var gap := OBSTACLE_GAP if hit.kind == ObstacleField.Kind.SOLID else -OBSTACLE_GAP
				b.position += hit.normal * gap
				r.obstacle_hits += 1
				r.add_sample(t, b.position)
				# Settled on top of something flat enough (a wall, a bridge).
				var n: Vector3 = hit.normal
				if hit.kind == ObstacleField.Kind.SOLID and n.y > FLAT_TOP and b.velocity.dot(n) < ROLL_THRESHOLD:
					if not landed:
						landed = true
						r.first_landing = b.position
					return _finish(r, ShotResult.Outcome.REST, b.position, t, landed, start, terrain)
				s = b
				continue

			if h1 <= 0.0:
				var frac := h0 / (h0 - h1) if h0 > 0.0 else 0.0
				var pos := s.position.lerp(nxt.position, frac)
				var vel := s.velocity.lerp(nxt.velocity, frac)
				pos.y = terrain.height_at(pos.x, pos.z)
				t = t - DT + DT * frac
				if not landed:
					landed = true
					r.first_landing = pos
				r.add_sample(t, pos)

				var surf := terrain.surface_at(pos.x, pos.z)
				if surf == Surface.Type.WATER:
					return _finish(r, ShotResult.Outcome.WATER, pos, t, landed, start, terrain)
				if surf == Surface.Type.OUT_OF_BOUNDS:
					return _finish(r, ShotResult.Outcome.OUT_OF_BOUNDS, pos, t, landed, start, terrain)
				if has_cup and _distance_xz(pos, cup) < CUP_RADIUS:
					return _finish(r, ShotResult.Outcome.HOLED, cup, t, landed, start, terrain)

				var n := terrain.normal_at(pos.x, pos.z)
				# Already moving off the ground's plane yet under the ground: the
				# slope ahead is steeper than the normal (the foot of a bunker
				# face). It rolls up it, rather than meeting it again at once
				# for ever.
				var leaving := vel.dot(n) >= 0.0
				var b := BallState.new(pos, vel, nxt.spin)
				bounce(b, n, surf)
				r.bounces += 1
				s = b
				var vn := b.velocity.dot(n)
				# A ball that meets the ground at the very start of a step (or
				# a hair after it) was on it already (a bank ahead rising
				# faster than it flies): it rolls from there. Bounced again it
				# would land at almost the same instant, again and again, and
				# never finish.
				if vn < ROLL_THRESHOLD or frac < LAND_AT_START or leaving:
					rolling = true
					s.velocity = b.velocity - n * vn
					# The next rolling step starts here: its normal and
					# surface are already known, as the rolling branch
					# caches them for the step after.
					ahead_at = pos
					ahead_normal = n
					ahead_surface = surf
				continue
			s = nxt
		else:
			var pos := s.position
			var v := s.velocity
			# Where the last step ended, its normal and surface are known.
			var known := pos == ahead_at
			var n := ahead_normal if known else terrain.normal_at(pos.x, pos.z)
			var here := ahead_surface if known and ahead_surface >= 0 else terrain.surface_at(pos.x, pos.z)
			var g := Vector3(0.0, -GRAVITY, 0.0)
			var slope := (g - n * g.dot(n)) * (5.0 / 7.0)
			var resist := Surface.rolling_resistance(here) * GRAVITY * n.y
			var speed := v.length()
			var holds := slope.length() <= resist
			if speed < STOP_SPEED and holds:
				return _finish(r, ShotResult.Outcome.REST, pos, t, landed, start, terrain)
			var a := slope
			if speed > 1e-9:
				a -= v * (resist / speed)
			var nv := v + a * DT
			if speed > 1e-9 and nv.dot(v) < 0.0 and holds:
				return _finish(r, ShotResult.Outcome.REST, pos, t, landed, start, terrain)
			var npos := pos + nv * DT
			npos.y = terrain.height_at(npos.x, npos.z)
			# Over a crest (a bunker's lip) faster than gravity can hold it to
			# the ground: it takes off, without the spin it rolled with.
			var free_y := pos.y + nv.y * DT - 0.5 * GRAVITY * DT * DT
			if free_y - npos.y > TAKE_OFF_GAP:
				# The step is taken in the air, so time always moves on.
				rolling = false
				s = BallState.new(Vector3(npos.x, free_y, npos.z), nv + Vector3(0.0, -GRAVITY * DT, 0.0), Vector3.ZERO)
				t += DT
				step += 1
				continue
			var nn := terrain.normal_at(npos.x, npos.z)
			ahead_at = npos
			ahead_normal = nn
			ahead_surface = -1
			nv -= nn * nv.dot(nn)
			t += DT
			step += 1

			# Rolling into a trunk or a wall; leaves do not stop a rolling ball.
			if has_obstacles and terrain.obstacle_hit_into(pos, npos, hit) and hit.kind == ObstacleField.Kind.SOLID:
				var hp := pos.lerp(npos, hit.fraction) + hit.normal * OBSTACLE_GAP
				hp.y = terrain.height_at(hp.x, hp.z)
				var b := BallState.new(hp, nv, s.spin)
				hit_obstacle(b, hit)
				var hn := terrain.normal_at(hp.x, hp.z)
				s.position = hp
				s.velocity = b.velocity - hn * b.velocity.dot(hn)
				s.spin = b.spin
				r.obstacle_hits += 1
				r.add_sample(t, hp)
				continue

			if has_cup and nv.length() < MAX_HOLING_SPEED and _segment_distance_xz(pos, npos, cup) < CUP_RADIUS:
				return _finish(r, ShotResult.Outcome.HOLED, cup, t, landed, start, terrain)
			var surf := terrain.surface_at(npos.x, npos.z)
			ahead_surface = surf
			if surf == Surface.Type.WATER:
				return _finish(r, ShotResult.Outcome.WATER, npos, t, landed, start, terrain)
			if surf == Surface.Type.OUT_OF_BOUNDS:
				return _finish(r, ShotResult.Outcome.OUT_OF_BOUNDS, npos, t, landed, start, terrain)
			s.position = npos
			s.velocity = nv
		if step % SAMPLE_EVERY == 0:
			r.add_sample(t, s.position)
	return _finish(r, ShotResult.Outcome.TIMED_OUT, s.position, t, landed, start, terrain)


static func _finish(r: ShotResult, outcome: ShotResult.Outcome, pos: Vector3, t: float, landed: bool, start: BallState, terrain: CourseTerrain) -> ShotResult:
	# A course can limit each hole to an outline; it is judged where the ball
	# stops.
	if outcome == ShotResult.Outcome.REST and not terrain.in_bounds(pos.x, pos.z):
		outcome = ShotResult.Outcome.OUT_OF_BOUNDS
	r.outcome = outcome
	r.rest = pos
	r.time_s = t
	r.rest_surface = terrain.surface_at(pos.x, pos.z)
	if not landed:
		r.first_landing = pos
	r.carry_m = _distance_xz(start.position, r.first_landing)
	r.total_m = _distance_xz(start.position, pos)
	if r.times.is_empty() or r.times[r.times.size() - 1] < t:
		r.add_sample(t, pos)
	return r


static func _distance_xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _segment_distance_xz(a: Vector3, b: Vector3, c: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ac := Vector2(c.x - a.x, c.z - a.z)
	var len2 := ab.length_squared()
	var f := 0.0 if len2 <= 0.0 else clampf(ac.dot(ab) / len2, 0.0, 1.0)
	return (ab * f - ac).length()
