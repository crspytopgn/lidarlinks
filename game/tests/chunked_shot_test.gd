extends SceneTree
## Chunked == unchunked, exactly, for the GDScript port: the same shot run
## through ResumableShot in different step sizes must end in the same place,
## with the same path, the same bounce count and (on the Links path) the same
## random state. Mirrors libs/olcore/tests/test_main.cpp test_shot_chunking.
## Run after importing:
##   godot --headless --path game -s res://tests/chunked_shot_test.gd
## Prints "CHUNKED SHOT TEST PASSED" and exits 0 when everything passes.

var _failures := 0


func _initialize() -> void:
	BackgroundWork.enabled = false
	var cup := Vector3(0.0, 0.0, 180.0)
	var fairway := FlatTerrain.new(Surface.Type.FAIRWAY, 0.0)
	var drive: BallState = Swing.launch_from_swing(_club("Dr"), 1.0, 0.0, 0.0, Surface.Type.TEE)
	drive.position = Vector3.ZERO
	var whole: ShotResult = BallPhysics.simulate_shot(drive, fairway, true, cup, Vector3.ZERO)
	var by_one := _run_chunked(drive, fairway, true, cup, Vector3.ZERO, null, [1])
	var by_handful := _run_chunked(drive, fairway, true, cup, Vector3.ZERO, null, [7, 1, 250, 3])
	_check_same(whole, by_one, "flat driver, one step at a time")
	_check_same(whole, by_handful, "flat driver, uneven chunks")
	_check(by_one.steps_done() == by_handful.steps_done(), "flat driver step count independent of chunking")
	print("  flat driver: %d steps, carry %.2f m, total %.2f m, %d bounces"
			% [by_one.steps_done(), whole.carry_m, whole.total_m, whole.bounces])
	# advance_ms: the same result, reached in time slices.
	var sliced := ResumableShot.new(drive, fairway, true, cup, Vector3.ZERO)
	var slices := 0
	while not sliced.advance_ms(8.0):
		slices += 1
		if slices > 10000:
			break
	_check(sliced.done, "flat driver finishes through advance_ms(8)")
	_check_same(whole, sliced.result(), "flat driver, 8 ms slices")
	_check(slices > 1, "flat driver takes more than one 8 ms slice")
	print("  flat driver: %d slices of 8 ms" % slices)
	# A trunk in the way: obstacle hits chunk the same.
	var trunk_ground := FlatTerrain.new(Surface.Type.FAIRWAY, 0.0)
	var trunk := ObstacleField.new()
	trunk.add_cylinder(0, 40, 0.5, -1, 30, ObstacleField.Kind.SOLID)
	trunk.finalize()
	trunk_ground.obstacles = trunk
	var trunk_whole: ShotResult = BallPhysics.simulate_shot(drive, trunk_ground, true, cup, Vector3.ZERO)
	_check_same(trunk_whole, _run_chunked(drive, trunk_ground, true, cup, Vector3.ZERO, null, [3, 11]),
			"driver into a trunk")
	print("  trunk: rest z %.2f m, %d hits" % [trunk_whole.rest.z, trunk_whole.obstacle_hits])
	# Through the ShotModel interface, as the game plays it.
	var model := StandardShotModel.new()
	var model_sim := model.simulate_chunked(drive, fairway, cup, Vector3.ZERO)
	_check_same(whole, model_sim.run(), "flat driver through ShotModel.simulate_chunked")

	# The Links path, with its random draws.
	var aero := LinksAero.from_exe(_synthetic_aero_exe())
	if aero == null:
		_failures += 1
		print("  FAIL: synthetic aero tables not found")
	else:
		_check_links(aero, cup)
	if _failures == 0:
		print("CHUNKED SHOT TEST PASSED")
		quit(0)
	else:
		print("CHUNKED SHOT TEST FAILED: %d failures" % _failures)
		quit(1)


func _check_links(aero: LinksAero, cup: Vector3) -> void:
	var fairway := FlatTerrain.new(Surface.Type.FAIRWAY, 0.0)
	var pw: BallState = Swing.launch_from_swing(_club("PW"), 1.0, 0.0, 0.0, Surface.Type.FAIRWAY)
	pw.position = Vector3.ZERO
	var whole: ShotResult = BallPhysics.simulate_shot(pw, fairway, true, cup, Vector3.ZERO, aero)
	var by_one := _run_chunked(pw, fairway, true, cup, Vector3.ZERO, aero, [1])
	var by_handful := _run_chunked(pw, fairway, true, cup, Vector3.ZERO, aero, [5, 2, 40])
	_check_same(whole, by_one, "links PW, one step at a time")
	_check_same(whole, by_handful, "links PW, uneven chunks")
	# The RNG accumulator after the same number of steps must not depend
	# on how the steps were grouped.
	var a := ResumableShot.new(pw, fairway, true, cup, Vector3.ZERO, aero)
	var b := ResumableShot.new(pw, fairway, true, cup, Vector3.ZERO, aero)
	for _i in 13:
		a.advance(1)
	b.advance(13)
	_check(a.rng_state() == b.rng_state(), "links RNG state independent of chunk grouping")
	_check(a.steps_done() == 13 and b.steps_done() == 13, "links step count")
	_check(by_one.rng_state() == by_handful.rng_state(), "links final RNG state independent of chunking")
	print("  links PW: %d steps, carry %.2f m, total %.2f m, rng %08x"
			% [by_one.steps_done(), whole.carry_m, whole.total_m, by_one.rng_state()])
	# A putt that drops, and a shot into the rough (whose ground hops draw).
	var green := FlatTerrain.new(Surface.Type.GREEN, 0.0)
	var putt_cup := Vector3(0.0, 0.0, 3.0)
	var putt := BallState.new(Vector3.ZERO, Vector3(0.0, 0.0, 3.55))
	var putt_whole: ShotResult = BallPhysics.simulate_shot(putt, green, true, putt_cup, Vector3.ZERO, aero)
	_check(putt_whole.outcome == ShotResult.Outcome.HOLED, "links putt drops (one-shot)")
	_check_same(putt_whole, _run_chunked(putt, green, true, putt_cup, Vector3.ZERO, aero, [3, 17]),
			"links putt that drops")
	var rough := FlatTerrain.new(Surface.Type.ROUGH, 0.0)
	var rough_whole: ShotResult = BallPhysics.simulate_shot(pw, rough, true, cup, Vector3.ZERO, aero)
	var rough_chunked := _run_chunked(pw, rough, true, cup, Vector3.ZERO, aero, [2, 9])
	_check_same(rough_whole, rough_chunked, "links PW into rough")
	_check(rough_chunked.rng_state() != 0, "links rough draws random numbers")
	print("  links rough: carry %.2f m, total %.2f m, rng %08x"
			% [rough_whole.carry_m, rough_whole.total_m, rough_chunked.rng_state()])
	# Through the Links ShotModel, as the game plays it.
	var links := LinksShotModel.new(aero, null)
	var links_sim := links.simulate_chunked(pw, fairway, cup, Vector3.ZERO)
	_check_same(whole, links_sim.run(), "links PW through ShotModel.simulate_chunked")
	# Cost per step, for the frame budget (STRIKE_CHUNK_MS in main.gd).
	var t0 := Time.get_ticks_usec()
	ResumableShot.new(pw, fairway, true, cup, Vector3.ZERO, aero).run()
	var links_usec := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	ResumableShot.new(Swing.launch_from_swing(_club("Dr"), 1.0, 0.0, 0.0, Surface.Type.TEE),
			fairway, true, cup, Vector3.ZERO).run()
	var std_usec := Time.get_ticks_usec() - t0
	print("  one-shot cost: links PW %d usec (%d steps), stand-in driver %d usec"
			% [links_usec, by_one.steps_done(), std_usec])


func _run_chunked(start: BallState, terrain: CourseTerrain, has_cup: bool, cup: Vector3,
		wind: Vector3, aero: LinksAero, chunks: Array) -> ResumableShot:
	var sim := ResumableShot.new(start, terrain, has_cup, cup, wind, aero)
	var i := 0
	while not sim.done:
		var n: int = chunks[i % chunks.size()]
		i += 1
		sim.advance(n)
		if i > 100000:
			break
	return sim


func _check_same(a: ShotResult, b, what: String) -> void:
	if b is ResumableShot:
		b = (b as ResumableShot).result()
	if int(a.outcome) != int(b.outcome):
		_failures += 1
		print("  FAIL: %s outcome %d vs %d" % [what, int(a.outcome), int(b.outcome)])
		return
	_check_near(a.rest.x, b.rest.x, 0.0, what + " rest x")
	_check_near(a.rest.y, b.rest.y, 0.0, what + " rest y")
	_check_near(a.rest.z, b.rest.z, 0.0, what + " rest z")
	_check_near(a.first_landing.x, b.first_landing.x, 0.0, what + " first landing x")
	_check_near(a.first_landing.z, b.first_landing.z, 0.0, what + " first landing z")
	_check_near(a.carry_m, b.carry_m, 0.0, what + " carry")
	_check_near(a.total_m, b.total_m, 0.0, what + " total")
	_check_near(a.apex_m, b.apex_m, 0.0, what + " apex")
	_check_near(a.time_s, b.time_s, 0.0, what + " time")
	if a.bounces != b.bounces:
		_failures += 1
		print("  FAIL: %s bounces %d vs %d" % [what, a.bounces, b.bounces])
	if a.obstacle_hits != b.obstacle_hits:
		_failures += 1
		print("  FAIL: %s obstacle hits %d vs %d" % [what, a.obstacle_hits, b.obstacle_hits])
	if a.times.size() != b.times.size():
		_failures += 1
		print("  FAIL: %s path samples %d vs %d" % [what, a.times.size(), b.times.size()])
		return
	for i in a.times.size():
		if a.times[i] != b.times[i] or a.points[i] != b.points[i]:
			_failures += 1
			print("  FAIL: %s path sample %d differs" % [what, i])
			return


func _check_near(got: float, want: float, tol: float, what: String) -> void:
	if absf(got - want) > tol:
		_failures += 1
		print("  FAIL: %s: got %.4f want %.4f (tol %.4f)" % [what, got, want, tol])


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failures += 1
		print("  FAIL: %s" % what)


static func _club(short_name: String) -> Club:
	for c in Club.standard_set():
		if c.short_name == short_name:
			return c
	return Club.standard_set()[0]


## The synthetic coefficient tables of run_tests.gd.
static func _synthetic_aero_exe() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(64)
	out.fill(0xCD)
	for table in 2:
		var b := PackedByteArray()
		b.resize(LinksAero.TABLE_BYTES)
		b.encode_u32(0, 11)
		b.encode_u32(4, 14)
		var q := 8
		for i in 11:
			b.encode_float(q, 30.0 * i)
			q += 4
		for i in 14:
			b.encode_float(q, 10.0 * i)
			q += 4
		b.encode_u32(q, 0x00401000)
		b.encode_u32(q + 4, 0x0040102c)
		b.encode_u32(q + 8, 0)
		q += 12
		for row in 11:
			for col in 14:
				b.encode_float(q, 0.2 + 0.01 * row + 0.001 * col if table == 0 else 0.01 * col)
				q += 4
		out.append_array(b)
		var pad := PackedByteArray()
		pad.resize(40)
		pad.fill(0xCD)
		out.append_array(pad)
	return out
