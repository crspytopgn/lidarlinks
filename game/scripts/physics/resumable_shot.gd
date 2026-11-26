class_name ResumableShot
extends RefCounted
## A shot simulation that can be paused between steps and resumed later,
## with exactly the same result as the one-shot BallPhysics.simulate_shot.
## Mirrors olcore::ResumableShot; change both together.
##
## Why this is safe to pause: both simulations are already loops of small
## fixed steps (0.004 s on the stand-in path, 1/60 s on the Links path),
## and everything one step needs is in this object: the ball, the clock,
## the step count, the result so far, the rolling and flight caches, and
## -- on the Links path -- the game's random-number state, which is drawn
## from in step order. Pausing between steps therefore changes nothing
## about the draws or the arithmetic; only the number of steps run per
## advance() call varies. Chunked and unchunked runs of the same shot
## agree exactly (see game/tests/chunked_shot_test.gd).
##
## Step boundaries are the loop iterations of the one-shot simulations:
## one advance() step is one flight or ground step of the original loop,
## including its landing, bounce, obstacle and cup handling. A step never
## pauses mid-bounce, mid-cup-sub-step or mid-nested-step: LinksGround's
## step runs to the end of its frame step, including the cup's 1/1200 s
## sub-steps, before returning.
##
## Budget by step count (advance) or by wall clock (advance_ms): the
## result does not depend on how the steps were grouped, so a frame loop
## can spend whatever it has -- 8 ms a frame on the web build, where the
## strike sim cannot start earlier and there are no worker threads -- and
## the ball still ends where the one-shot sim puts it. A full drive is
## roughly 1,500-3,500 stand-in steps or 300-900 Links steps.
##
## The one-shot calls stay the default on desktop and worker threads:
## BallPhysics.simulate_shot is ResumableShot.new(...).run().

## The shot as given.
var _start: BallState
var _terrain: CourseTerrain
var _has_cup := false
var _cup := Vector3.ZERO
var _wind := Vector3.ZERO
var _aero: LinksAero = null
var _links := false

## The result as built so far, and the loop clock.
var _result: ShotResult
var _t := 0.0
var _steps := 0
var _landed := false
## True once the shot has finished (rest, holed, water, out of bounds or
## timed out). result() is valid only then.
var done := false

## Stand-in path: the ball, whether it is rolling, and the caches the
## one-shot loop carries between steps (see BallPhysics.simulate_shot).
var _state: BallState
var _rolling := false
var _hit := ObstacleField.Hit.new()
var _has_obstacles := false
var _ahead_at := Vector3(INF, INF, INF)
var _ahead_normal := Vector3.UP
var _ahead_surface := -1
var _flight_xz := Vector2(INF, INF)
var _flight_y := 0.0

## Links path: the ball in the game's frame, its random numbers, the
## shared step context (ground, aero, wind, cup, billboards, facing),
## the hole, and the ball radius in metres for the bottom-of-ball frame.
var _ball: LinksGround.Ball
var _rng: LinksGround.Rng
var _ctx: LinksGround.Ctx
var _ground: LinksGround.TerrainGround
var _hole: LinksGround.Cup = null
var _radius_m := 0.0


func _init(start: BallState, terrain: CourseTerrain, has_cup := false, cup := Vector3.ZERO,
		wind := Vector3.ZERO, aero: LinksAero = null) -> void:
	_start = start
	_terrain = terrain
	_has_cup = has_cup
	_cup = cup
	_wind = wind
	_aero = aero
	_links = aero != null
	_result = ShotResult.new()
	_result.add_sample(0.0, start.position)
	if _links:
		_begin_links()
	else:
		_begin_standard()


## Runs up to `max_steps` loop iterations (at least one when not done).
## Returns true once the shot has finished.
func advance(max_steps: int) -> bool:
	if done:
		return true
	if max_steps < 1:
		max_steps = 1
	for _i in max_steps:
		if done:
			break
		# Each step method ends the shot itself when its time runs out,
		# as the one-shot loops did on leaving their while.
		done = _step_links() if _links else _step_standard()
	return done


## Runs steps until `budget_ms` of wall clock is spent (checked every 32
## steps, so a call may run a little over) or the shot finishes. Returns
## true once the shot has finished.
func advance_ms(budget_ms: float) -> bool:
	if done:
		return true
	var start_usec := Time.get_ticks_usec()
	var budget_usec := int(budget_ms * 1000.0)
	while not done:
		advance(32)
		if Time.get_ticks_usec() - start_usec >= budget_usec:
			break
	return done


## Runs to the end, as BallPhysics.simulate_shot does.
func run() -> ShotResult:
	while not advance(1024):
		pass
	return _result


## The finished result. Only valid once done is true.
func result() -> ShotResult:
	return _result


func steps_done() -> int:
	return _steps


func time_s() -> float:
	return _t


## The Links random state after the steps run so far (0 on the stand-in
## path, which draws no random numbers). Two runs of the same shot agree
## on this after the same number of steps, and on the final state when
## both are done.
func rng_state() -> int:
	return _rng.state if _links and _rng != null else 0


# ---------------------------------------------------------------------------
# The stand-in path: the pre-loop setup and one iteration of
# BallPhysics.simulate_shot's loop. The `continue`s of the loop are
# returns of false here (the step ran, the shot goes on); the
# `return _finish(...)`s set the result and return true. The sample at
# the bottom of the loop is only appended on the paths that fell through
# to it, as before.

func _begin_standard() -> void:
	var s := _start.copy()
	_state = s
	_has_obstacles = _terrain.has_obstacles()
	var n0 := _terrain.normal_at(s.position.x, s.position.z)
	var vn0 := s.velocity.dot(n0)
	var speed0 := s.velocity.length()
	if vn0 < 2.0 * BallPhysics.ROLL_THRESHOLD and s.velocity.y > BallPhysics.LOFTED_LAUNCH * speed0:
		# A lofted shot from a lie on a bank (a bunker face) leaves the slope:
		# the club follows the ground, so the launch is off the slope too.
		var lifted := s.velocity + n0 * (maxf(absf(vn0), 2.0 * BallPhysics.ROLL_THRESHOLD) - vn0)
		s.velocity = lifted * (speed0 / lifted.length())
	if s.velocity.dot(n0) < -BallPhysics.ROLL_THRESHOLD:
		# Struck into a bank steeper than its launch (a bunker face): it meets
		# the ground at once, rather than rolling away at full speed.
		BallPhysics.bounce(s, n0, _terrain.surface_at(s.position.x, s.position.z))
		_result.bounces += 1
	_rolling = s.velocity.dot(n0) < BallPhysics.ROLL_THRESHOLD
	if _rolling:
		s.velocity -= n0 * s.velocity.dot(n0)
		_landed = true
		_result.first_landing = s.position


func _finish_standard(outcome: ShotResult.Outcome, pos: Vector3) -> ShotResult:
	return BallPhysics._finish(_result, outcome, pos, _t, _landed, _start, _terrain)


func _step_standard() -> bool:
	if _t >= BallPhysics.MAX_TIME:
		_result = _finish_standard(ShotResult.Outcome.TIMED_OUT, _state.position)
		return true
	if not _rolling:
		var nxt := BallPhysics.step_flight(_state, BallPhysics.DT, _wind, _aero)
		var g0 := _flight_y if _state.position.x == _flight_xz.x and _state.position.z == _flight_xz.y \
				else _terrain.height_at(_state.position.x, _state.position.z)
		var g1 := _terrain.height_at(nxt.position.x, nxt.position.z)
		_flight_xz = Vector2(nxt.position.x, nxt.position.z)
		_flight_y = g1
		var h0 := _state.position.y - g0
		var h1 := nxt.position.y - g1
		_t += BallPhysics.DT
		_steps += 1
		_result.apex_m = maxf(_result.apex_m, nxt.position.y - _start.position.y)

		# An obstacle met before the ground. Time keeps the whole step,
		# so a ball wedged between obstacles still runs out of time.
		var ground := (h0 / (h0 - h1) if h0 > 0.0 else 0.0) if h1 <= 0.0 else 2.0
		if _has_obstacles and _terrain.obstacle_hit_into(_state.position, nxt.position, _hit) \
				and _hit.fraction < ground:
			var f: float = _hit.fraction
			var b := BallState.new(_state.position.lerp(nxt.position, f),
					_state.velocity.lerp(nxt.velocity, f), nxt.spin)
			BallPhysics.hit_obstacle(b, _hit)
			# Just outside a solid, or just inside a canopy, so the same
			# face is not met again.
			var gap := BallPhysics.OBSTACLE_GAP if _hit.kind == ObstacleField.Kind.SOLID \
					else -BallPhysics.OBSTACLE_GAP
			b.position += _hit.normal * gap
			_result.obstacle_hits += 1
			_result.add_sample(_t, b.position)
			# Settled on top of something flat enough (a wall, a bridge).
			var n: Vector3 = _hit.normal
			if _hit.kind == ObstacleField.Kind.SOLID and n.y > BallPhysics.FLAT_TOP \
					and b.velocity.dot(n) < BallPhysics.ROLL_THRESHOLD:
				if not _landed:
					_landed = true
					_result.first_landing = b.position
				_result = _finish_standard(ShotResult.Outcome.REST, b.position)
				return true
			_state = b
			return false

		if h1 <= 0.0:
			var frac := h0 / (h0 - h1) if h0 > 0.0 else 0.0
			var pos := _state.position.lerp(nxt.position, frac)
			var vel := _state.velocity.lerp(nxt.velocity, frac)
			pos.y = _terrain.height_at(pos.x, pos.z)
			_t = _t - BallPhysics.DT + BallPhysics.DT * frac
			if not _landed:
				_landed = true
				_result.first_landing = pos
			_result.add_sample(_t, pos)

			var surf := _terrain.surface_at(pos.x, pos.z)
			if surf == Surface.Type.WATER:
				_result = _finish_standard(ShotResult.Outcome.WATER, pos)
				return true
			if surf == Surface.Type.OUT_OF_BOUNDS:
				_result = _finish_standard(ShotResult.Outcome.OUT_OF_BOUNDS, pos)
				return true
			if _has_cup and BallPhysics._distance_xz(pos, _cup) < BallPhysics.CUP_RADIUS:
				_result = _finish_standard(ShotResult.Outcome.HOLED, _cup)
				return true

			var n := _terrain.normal_at(pos.x, pos.z)
			# Already moving off the ground's plane yet under the ground: the
			# slope ahead is steeper than the normal (the foot of a bunker
			# face). It rolls up it, rather than meeting it again at once
			# for ever.
			var leaving := vel.dot(n) >= 0.0
			var b := BallState.new(pos, vel, nxt.spin)
			BallPhysics.bounce(b, n, surf)
			_result.bounces += 1
			_state = b
			var vn := b.velocity.dot(n)
			# A ball that meets the ground at the very start of a step (or
			# a hair after it) was on it already (a bank ahead rising
			# faster than it flies): it rolls from there. Bounced again it
			# would land at almost the same instant, again and again, and
			# never finish.
			if vn < BallPhysics.ROLL_THRESHOLD or frac < BallPhysics.LAND_AT_START or leaving:
				_rolling = true
				_state.velocity = b.velocity - n * vn
				# The next rolling step starts here: its normal and
				# surface are already known, as the rolling branch
				# caches them for the step after.
				_ahead_at = pos
				_ahead_normal = n
				_ahead_surface = surf
			return false
		_state = nxt
	else:
		var pos := _state.position
		var v := _state.velocity
		# Where the last step ended, its normal and surface are known.
		var known := pos == _ahead_at
		var n := _ahead_normal if known else _terrain.normal_at(pos.x, pos.z)
		var here := _ahead_surface if known and _ahead_surface >= 0 else _terrain.surface_at(pos.x, pos.z)
		var g := Vector3(0.0, -BallPhysics.GRAVITY, 0.0)
		var slope := (g - n * g.dot(n)) * (5.0 / 7.0)
		var resist := Surface.rolling_resistance(here) * BallPhysics.GRAVITY * n.y
		var speed := v.length()
		var holds := slope.length() <= resist
		if speed < BallPhysics.STOP_SPEED and holds:
			_result = _finish_standard(ShotResult.Outcome.REST, pos)
			return true
		var a := slope
		if speed > 1e-9:
			a -= v * (resist / speed)
		var nv := v + a * BallPhysics.DT
		if speed > 1e-9 and nv.dot(v) < 0.0 and holds:
			_result = _finish_standard(ShotResult.Outcome.REST, pos)
			return true
		var npos := pos + nv * BallPhysics.DT
		npos.y = _terrain.height_at(npos.x, npos.z)
		# Over a crest (a bunker's lip) faster than gravity can hold it to
		# the ground: it takes off, without the spin it rolled with.
		var free_y := pos.y + nv.y * BallPhysics.DT - 0.5 * BallPhysics.GRAVITY * BallPhysics.DT * BallPhysics.DT
		if free_y - npos.y > BallPhysics.TAKE_OFF_GAP:
			# The step is taken in the air, so time always moves on.
			_rolling = false
			_state = BallState.new(Vector3(npos.x, free_y, npos.z),
					nv + Vector3(0.0, -BallPhysics.GRAVITY * BallPhysics.DT, 0.0), Vector3.ZERO)
			_t += BallPhysics.DT
			_steps += 1
			return false
		var nn := _terrain.normal_at(npos.x, npos.z)
		_ahead_at = npos
		_ahead_normal = nn
		_ahead_surface = -1
		nv -= nn * nv.dot(nn)
		_t += BallPhysics.DT
		_steps += 1

		# Rolling into a trunk or a wall; leaves do not stop a rolling ball.
		if _has_obstacles and _terrain.obstacle_hit_into(pos, npos, _hit) \
				and _hit.kind == ObstacleField.Kind.SOLID:
			var hp := pos.lerp(npos, _hit.fraction) + _hit.normal * BallPhysics.OBSTACLE_GAP
			hp.y = _terrain.height_at(hp.x, hp.z)
			var b := BallState.new(hp, nv, _state.spin)
			BallPhysics.hit_obstacle(b, _hit)
			var hn := _terrain.normal_at(hp.x, hp.z)
			_state.position = hp
			_state.velocity = b.velocity - hn * b.velocity.dot(hn)
			_state.spin = b.spin
			_result.obstacle_hits += 1
			_result.add_sample(_t, hp)
			return false

		if _has_cup and nv.length() < BallPhysics.MAX_HOLING_SPEED \
				and BallPhysics._segment_distance_xz(pos, npos, _cup) < BallPhysics.CUP_RADIUS:
			_result = _finish_standard(ShotResult.Outcome.HOLED, _cup)
			return true
		var surf := _terrain.surface_at(npos.x, npos.z)
		_ahead_surface = surf
		if surf == Surface.Type.WATER:
			_result = _finish_standard(ShotResult.Outcome.WATER, npos)
			return true
		if surf == Surface.Type.OUT_OF_BOUNDS:
			_result = _finish_standard(ShotResult.Outcome.OUT_OF_BOUNDS, npos)
			return true
		_state.position = npos
		_state.velocity = nv
	if BallPhysics.SAMPLE_EVERY > 0 and _steps % BallPhysics.SAMPLE_EVERY == 0:
		_result.add_sample(_t, _state.position)
	return false


# ---------------------------------------------------------------------------
# The Links path: the pre-loop setup and one iteration of
# LinksGround.simulate_shot's loop (one 1/60 s frame step).

func _begin_links() -> void:
	_radius_m = LinksGround.RADIUS / LinksGround.FEET_PER_METRE
	_ground = LinksGround.TerrainGround.new(_terrain)
	# The game starts a full shot in flight with its centre one radius up.
	var b := LinksGround.Ball.new()
	b.position = LinksGround._to_game(_start.position) + Vector3(0, 0, LinksGround.RADIUS)
	b.velocity = LinksGround._to_game(_start.velocity)
	b.spin = LinksGround._spin_to_game(_start.spin)
	if _start.on_ground:
		# A putt starts skidding, one radius above the slope, tilted onto it.
		var n := _ground.normal(b.position.x, b.position.y)
		b.velocity = LinksLaunch.putt_slope(b.velocity, n)
		b.spin = LinksLaunch.putt_slope(b.spin, n)
		b.position.z = _ground.height(b.position.x, b.position.y) + LinksGround.RADIUS / n.z
		b.mode = LinksGround.Mode.SKID
		_landed = true
		_result.first_landing = _start.position
	# The game takes the flagstick out for a shot from the green.
	b.flagstick_out = _ground.surface(b.position.x, b.position.y).ground_class == LinksGround.GREEN
	_ball = b
	_rng = LinksGround.Rng.new(LinksGround.Rng.seed_for(b.position.x, b.position.y))
	var wind := LinksGround._to_game(_wind)
	# Billboards face the camera behind the ball: back along the shot.
	var facing := Vector3(-b.velocity.x, -b.velocity.y, 0)
	facing = facing.normalized() if facing.length() > 0.0 else Vector3(0, -1, 0)
	if _has_cup:
		_hole = LinksGround.Cup.new()
		_hole.pin = LinksGround._to_game(_cup)
		_hole.radius = BallPhysics.CUP_RADIUS * LinksGround.FEET_PER_METRE
	# One context for the whole shot (step() makes one per step).
	var c := LinksGround.Ctx.new()
	c.objects = _terrain.links_objects
	c.facing = facing
	c.g = _ground
	c.aero = _aero
	c.wind = wind
	c.rng = _rng
	c.cup = _hole
	_ctx = c
	_has_obstacles = _terrain.has_links_obstacles()


func _finish_links(outcome: ShotResult.Outcome, pos: Vector3) -> ShotResult:
	return BallPhysics._finish(_result, outcome, pos, _t, _landed, _start, _terrain)


func _step_links() -> bool:
	var dt := LinksGround.FRAME_DT
	if _t >= BallPhysics.MAX_TIME:
		_result = _finish_links(ShotResult.Outcome.TIMED_OUT,
				LinksGround._from_game(_ball.position) - Vector3(0, _radius_m, 0))
		return true
	var before := LinksGround._from_game(_ball.position) - Vector3(0, _radius_m, 0)
	var before_velocity := LinksGround._from_game(_ball.velocity)
	var before_spin := LinksGround._spin_from_game(_ball.spin)
	var was_flying := _ball.mode == LinksGround.Mode.FLIGHT
	var info := LinksGround._step(_ctx, _ball, dt)
	_t += dt
	_steps += 1
	var after := LinksGround._from_game(_ball.position) - Vector3(0, _radius_m, 0)
	_result.apex_m = maxf(_result.apex_m, after.y - _start.position.y)

	# Walls and the like (and trees, when the course has no billboards
	# for the game's own model): our own handling, as in
	# BallPhysics.simulate_shot.
	if _has_obstacles and _terrain.links_obstacle_hit_into(before, after, _hit) \
			and (was_flying or _hit.kind == ObstacleField.Kind.SOLID):
		var solid := _hit.kind == ObstacleField.Kind.SOLID
		var hb := BallState.new(before.lerp(after, _hit.fraction), before_velocity, before_spin)
		BallPhysics.hit_obstacle(hb, _hit)
		hb.position += _hit.normal * (BallPhysics.OBSTACLE_GAP if solid else -BallPhysics.OBSTACLE_GAP)
		_result.obstacle_hits += 1
		_result.add_sample(_t, hb.position)
		_ball.position = LinksGround._to_game(hb.position) + Vector3(0, 0, LinksGround.RADIUS)
		_ball.velocity = LinksGround._to_game(hb.velocity)
		_ball.spin = LinksGround._spin_to_game(hb.spin)
		_ball.mode = LinksGround.Mode.FLIGHT
		return false

	if info.landed:
		var contact := LinksGround._from_game(info.contact)
		if not _landed:
			_landed = true
			_result.first_landing = contact
		_result.bounces += 1
		_result.add_sample(_t, contact)
		var surf := _terrain.surface_at(contact.x, contact.z)
		if surf == Surface.Type.WATER:
			_result = _finish_links(ShotResult.Outcome.WATER, contact)
			return true
		if surf == Surface.Type.OUT_OF_BOUNDS:
			_result = _finish_links(ShotResult.Outcome.OUT_OF_BOUNDS, contact)
			return true
	elif not was_flying:
		var here := _terrain.surface_at(after.x, after.z)
		if here == Surface.Type.WATER:
			_result = _finish_links(ShotResult.Outcome.WATER, after)
			return true
		if here == Surface.Type.OUT_OF_BOUNDS:
			_result = _finish_links(ShotResult.Outcome.OUT_OF_BOUNDS, after)
			return true
	if _ball.mode == LinksGround.Mode.HOLED:
		_result = _finish_links(ShotResult.Outcome.HOLED, _cup)
		return true
	if _ball.mode == LinksGround.Mode.REST:
		_result = _finish_links(ShotResult.Outcome.REST, after)
		return true
	if _steps % BallPhysics.SAMPLE_EVERY == 0:
		_result.add_sample(_t, after)
	return false
