extends SceneTree
## Smoke test for the Olcore GDExtension. Run after importing, with the
## extension built and in game/addons/olcore/bin/:
##   godot --headless --path game --import
##   godot --headless --path game -s res://tests/olcore_smoke.gd
## Prints "OLCORE NATIVE SMOKE PASSED" and exits 0 when the native sim
## matches the GDScript port on flat ground, or "OLCORE NATIVE: not
## loaded" and exits 0 when the extension is absent (the game then runs
## the GDScript port, which is the supported fallback).

var _failures := 0


func _initialize() -> void:
	if not ClassDB.class_exists("OlcorePhysics"):
		print("OLCORE NATIVE: not loaded (GDScript fallback)")
		quit(0)
		return
	var physics = ClassDB.instantiate("OlcorePhysics")
	print("OLCORE NATIVE: ", physics.get_version())
	_check_make_launch(physics)
	_check_flat_parity(physics)
	_check_timing(physics)
	if _failures == 0:
		print("OLCORE NATIVE SMOKE PASSED")
		quit(0)
	else:
		print("OLCORE NATIVE SMOKE FAILED: %d failures" % _failures)
		quit(1)


func _check_make_launch(physics) -> void:
	var l: Dictionary = physics.make_launch(60.0, 12.0, 0.0, 6000.0, 0.0)
	var want: BallState = BallPhysics.make_launch(60.0, 12.0, 0.0, 6000.0, 0.0)
	_check_near((l.velocity as Vector3).length(), want.velocity.length(), 0.01, "make_launch speed")
	_check_near((l.spin as Vector3).length(), want.spin.length(), 0.01, "make_launch spin")


func _flat_terrain_native():
	var t = ClassDB.instantiate("OlcoreTerrain")
	var n := 512
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	heights.fill(0.0)
	var surfaces := PackedByteArray()
	surfaces.resize(n * n)
	surfaces.fill(Surface.Type.FAIRWAY)
	var ok: bool = t.bake(-256.0, -256.0, 1.0, n, n, heights, surfaces, PackedFloat32Array(), PackedByteArray())
	if not ok:
		_failures += 1
		print("  FAIL: native terrain bake failed")
	return t


func _check_flat_parity(physics) -> void:
	var terrain = _flat_terrain_native()
	var launch: BallState = BallPhysics.make_launch(60.0, 12.0, 0.0, 6000.0, 0.0)
	launch.position = Vector3.ZERO
	var native: Dictionary = physics.simulate_shot(launch.position, launch.velocity, launch.spin, false,
			Vector3.ZERO, null, terrain, false, Vector3.ZERO)
	if native.is_empty():
		_failures += 1
		print("  FAIL: native simulate_shot returned empty")
		return
	var flat := FlatTerrain.new(Surface.Type.FAIRWAY, 0.0)
	var gd: ShotResult = BallPhysics.simulate_shot(launch, flat, false, Vector3.ZERO, Vector3.ZERO)
	_check_near(native.carry_m, gd.carry_m, 0.01, "flat driver carry (native vs GDScript)")
	_check_near(native.total_m, gd.total_m, 0.01, "flat driver total (native vs GDScript)")
	_check_near(native.apex_m, gd.apex_m, 0.01, "flat driver apex (native vs GDScript)")
	if int(native.outcome) != int(gd.outcome):
		_failures += 1
		print("  FAIL: flat driver outcome native=%d gd=%d" % [int(native.outcome), int(gd.outcome)])
	print("  flat driver: native carry %.2f m, total %.2f m; GDScript carry %.2f m, total %.2f m"
			% [native.carry_m, native.total_m, gd.carry_m, gd.total_m])


func _check_timing(physics) -> void:
	var terrain = _flat_terrain_native()
	var launch: BallState = BallPhysics.make_launch(60.0, 12.0, 0.0, 6000.0, 0.0)
	launch.position = Vector3.ZERO
	var flat := FlatTerrain.new(Surface.Type.FAIRWAY, 0.0)
	var n := 20
	var t0 := Time.get_ticks_usec()
	for i in n:
		physics.simulate_shot(launch.position, launch.velocity, launch.spin, false, Vector3.ZERO,
				null, terrain, false, Vector3.ZERO)
	var native_us := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	for i in n:
		BallPhysics.simulate_shot(launch, flat, false, Vector3.ZERO, Vector3.ZERO)
	var gd_us := Time.get_ticks_usec() - t0
	print("  timing: native %.1f ms/shot, GDScript %.1f ms/shot (n=%d, flat driver)"
			% [native_us / 1000.0 / n, gd_us / 1000.0 / n, n])


func _check_near(got: float, want: float, tol: float, what: String) -> void:
	if absf(got - want) > tol:
		_failures += 1
		print("  FAIL: %s: got %.4f want %.4f (tol %.4f)" % [what, got, want, tol])
