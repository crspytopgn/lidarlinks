extends SceneTree
## End-to-end test for OlcoreShotModel: the native shot path through the
## ShotModel interface, with the GDScript port as the reference. Run with
## the native flag, after importing, with the extension built:
##   godot --headless --path game -s res://tests/olcore_model_test.gd -- --native-physics
## Prints "OLCORE MODEL TEST PASSED" and exits 0 when the native result
## matches the GDScript port on flat ground, or "OLCORE MODEL TEST:
## native not available" and exits 0 when the extension is absent.

var _failures := 0


func _initialize() -> void:
	if not OlcoreShotModel.use_native_enabled():
		print("OLCORE MODEL TEST: --native-physics not given, nothing to test")
		quit(0)
		return
	if not OlcoreShotModel.native_available():
		print("OLCORE MODEL TEST: native not available (GDScript fallback)")
		quit(0)
		return
	var inner := StandardShotModel.new()
	var model := OlcoreShotModel.new(inner)
	var start: BallState = BallPhysics.make_launch(60.0, 12.0, 0.0, 6000.0, 0.0)
	start.position = Vector3.ZERO
	var terrain := FlatTerrain.new(Surface.Type.FAIRWAY, 0.0)
	var cup := Vector3(0.0, 0.0, 180.0)
	var native: ShotResult = model.simulate(start, terrain, cup, Vector3.ZERO)
	var gd: ShotResult = BallPhysics.simulate_shot(start, terrain, true, cup, Vector3.ZERO)
	_check_near(native.carry_m, gd.carry_m, 0.01, "model flat driver carry (native vs GDScript)")
	_check_near(native.total_m, gd.total_m, 0.01, "model flat driver total (native vs GDScript)")
	_check_near(native.apex_m, gd.apex_m, 0.01, "model flat driver apex (native vs GDScript)")
	if int(native.outcome) != int(gd.outcome):
		_failures += 1
		print("  FAIL: model flat driver outcome native=%d gd=%d" % [int(native.outcome), int(gd.outcome)])
	print("  model flat driver: native carry %.2f m, total %.2f m; GDScript carry %.2f m, total %.2f m"
			% [native.carry_m, native.total_m, gd.carry_m, gd.total_m])
	# A second shot from the same lie reuses the baked terrain.
	var start2: BallState = BallPhysics.make_launch(45.0, 18.0, 0.0, 5000.0, 0.0)
	start2.position = Vector3.ZERO
	var native2: ShotResult = model.simulate(start2, terrain, cup, Vector3.ZERO)
	var gd2: ShotResult = BallPhysics.simulate_shot(start2, terrain, true, cup, Vector3.ZERO)
	_check_near(native2.carry_m, gd2.carry_m, 0.01, "model second shot carry (native vs GDScript)")
	_check_obstacles()
	_check_billboards()
	if _failures == 0:
		print("OLCORE MODEL TEST PASSED")
		quit(0)
	else:
		print("OLCORE MODEL TEST FAILED: %d failures" % _failures)
		quit(1)


func _check_near(got: float, want: float, tol: float, what: String) -> void:
	if absf(got - want) > tol:
		_failures += 1
		print("  FAIL: %s: got %.4f want %.4f (tol %.4f)" % [what, got, want, tol])


static func _club(short_name: String) -> Club:
	for c in Club.standard_set():
		if c.short_name == short_name:
			return c
	return Club.standard_set()[0]


func _check_shot(native: ShotResult, gd: ShotResult, what: String) -> void:
	_check_near(native.carry_m, gd.carry_m, 0.01, what + " carry (native vs GDScript)")
	_check_near(native.total_m, gd.total_m, 0.01, what + " total (native vs GDScript)")
	_check_near(native.apex_m, gd.apex_m, 0.01, what + " apex (native vs GDScript)")
	_check_near(native.rest.x, gd.rest.x, 0.01, what + " rest x (native vs GDScript)")
	_check_near(native.rest.z, gd.rest.z, 0.01, what + " rest z (native vs GDScript)")
	if int(native.outcome) != int(gd.outcome):
		_failures += 1
		print("  FAIL: %s outcome native=%d gd=%d" % [what, int(native.outcome), int(gd.outcome)])
	if native.obstacle_hits != gd.obstacle_hits:
		_failures += 1
		print("  FAIL: %s obstacle hits native=%d gd=%d" % [what, native.obstacle_hits, gd.obstacle_hits])


## Obstacles in the native sim (Phase 2): a trunk, a canopy and a hole
## obstacle, each against the GDScript port on the same terrain.
func _check_obstacles() -> void:
	var cup := Vector3(0.0, 0.0, 180.0)
	var start: BallState = BallPhysics.make_launch(60.0, 12.0, 0.0, 6000.0, 0.0)
	start.position = Vector3.ZERO
	var model := OlcoreShotModel.new(StandardShotModel.new())
	var ground := FlatTerrain.new(Surface.Type.FAIRWAY, 0.0)
	var trunk := ObstacleField.new()
	trunk.add_cylinder(0, 40, 0.5, -1, 30, ObstacleField.Kind.SOLID)
	trunk.finalize()
	ground.obstacles = trunk
	# The full driver from the tee, as run_tests.gd pins it: the ball
	# comes back off the trunk and stops at z = -27.06 m.
	var drive: BallState = Swing.launch_from_swing(_club("Dr"), 1.0, 0.0, 0.0, Surface.Type.TEE)
	drive.position = Vector3.ZERO
	var native: ShotResult = model.simulate(drive, ground, cup, Vector3.ZERO)
	var gd: ShotResult = BallPhysics.simulate_shot(drive, ground, true, cup, Vector3.ZERO)
	_check_shot(native, gd, "trunk")
	_check_near(native.rest.z, -27.06, 1.0, "trunk rest z")
	print("  trunk: native rest z %.2f m, total %.2f m, %d hits; GDScript rest z %.2f m, %d hits"
			% [native.rest.z, native.total_m, native.obstacle_hits, gd.rest.z, gd.obstacle_hits])
	var canopy_ground := FlatTerrain.new(Surface.Type.FAIRWAY, 0.0)
	var canopy := ObstacleField.new()
	canopy.add_cylinder(0, 150, 6, 3, 40, ObstacleField.Kind.CANOPY)
	canopy.finalize()
	canopy_ground.obstacles = canopy
	native = model.simulate(start, canopy_ground, cup, Vector3.ZERO)
	gd = BallPhysics.simulate_shot(start, canopy_ground, true, cup, Vector3.ZERO)
	_check_shot(native, gd, "canopy")
	print("  canopy: native carry %.2f m, %d hits; GDScript carry %.2f m, %d hits"
			% [native.carry_m, native.obstacle_hits, gd.carry_m, gd.obstacle_hits])
	# The same trunk, put up for the hole instead of the course: the merge
	# in the bake must meet it too.
	var hole_ground := FlatTerrain.new(Surface.Type.FAIRWAY, 0.0)
	var hole_field := ObstacleField.new()
	hole_field.add_cylinder(0, 40, 0.5, -1, 30, ObstacleField.Kind.SOLID)
	hole_field.finalize()
	hole_ground.hole_obstacles = hole_field
	native = model.simulate(start, hole_ground, cup, Vector3.ZERO)
	gd = BallPhysics.simulate_shot(start, hole_ground, true, cup, Vector3.ZERO)
	_check_shot(native, gd, "hole obstacle")


## Billboards and 3D objects in the native sim (Phase 2): the Links model
## against the GDScript port, with a rock billboard and a wall model.
func _check_billboards() -> void:
	var aero := LinksAero.from_exe(_synthetic_aero_exe())
	if aero == null:
		_failures += 1
		print("  FAIL: synthetic aero tables not found")
		return
	var links := LinksShotModel.new(aero, null)
	var model := OlcoreShotModel.new(links)
	var cup := Vector3(0.0, 0.0, 180.0)
	var start: BallState = BallPhysics.make_launch(60.0, 12.0, 0.0, 6000.0, 0.0)
	start.position = Vector3.ZERO
	var ground := FlatTerrain.new(Surface.Type.FAIRWAY, 0.0)
	ground.links_objects = _rock_billboard()
	var native: ShotResult = model.simulate(start, ground, cup, Vector3.ZERO)
	var gd: ShotResult = BallPhysics.simulate_shot(start, ground, true, cup, Vector3.ZERO, aero)
	_check_shot(native, gd, "billboard")
	print("  billboard: native total %.2f m; GDScript total %.2f m" % [native.total_m, gd.total_m])
	var wall_ground := FlatTerrain.new(Surface.Type.FAIRWAY, 0.0)
	wall_ground.links_objects = _wall_model()
	native = model.simulate(start, wall_ground, cup, Vector3.ZERO)
	gd = BallPhysics.simulate_shot(start, wall_ground, true, cup, Vector3.ZERO, aero)
	_check_shot(native, gd, "wall model")
	print("  wall model: native total %.2f m; GDScript total %.2f m" % [native.total_m, gd.total_m])


## A rock billboard 100 ft downrange, 30 ft tall, opaque everywhere, in
## the game's frame (feet, z up).
func _rock_billboard() -> LinksObjects:
	var objects := LinksObjects.new()
	var type := LinksObjects.ObjType.new()
	type.collision = 1
	type.shape = PackedFloat32Array([0.8, 1, 0, 0, 1, 1])
	type.aspect = 1.0
	var mask := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	mask.fill(Color(1, 1, 1, 1))
	type.mask = mask
	objects.types.append(type)
	objects.add(Vector3(0, 100, 0), 30.0, 0, 0.5, 0.0)
	return objects


## A 3D wall 200 ft downrange, 10 ft wide and 40 ft tall, faced towards
## the ball, in the game's frame.
func _wall_model() -> LinksObjects:
	var objects := LinksObjects.new()
	var mesh := LinksObjects.Mesh3D.new()
	var quad: Array[Vector3] = [Vector3(-5, 200, 0), Vector3(-5, 200, 40), Vector3(5, 200, 40),
			Vector3(5, 200, 0)]
	mesh.faces.append_array(PackedInt32Array([0, 4, 0]))
	for v in quad:
		mesh.corners.append(mesh.positions.size())
		mesh.positions.append(v)
		mesh.uvs.append(Vector2(0.5, 0.5))
	mesh.holes.append(null)
	objects.meshes.append(mesh)
	objects.add_model(0, mesh.positions)
	return objects


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
