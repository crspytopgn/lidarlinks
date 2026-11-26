class_name OlcoreShotModel
extends ShotModel
## Native (GDExtension) shot simulation, Phase 2. Wraps an inner ShotModel
## (LinksShotModel or StandardShotModel) for launch, reach and lie power,
## and runs simulate() in C++ over a baked snapshot terrain when the
## extension is present and enabled. The GDScript port stays the default
## and the fallback: this model is only used when
## OlcoreShotModel.use_native_enabled() is true, and only for shots the
## native path can run exactly (see simulate()).
##
## Enable it with --native-physics on the command line or
## LIDARLINKS_NATIVE_PHYSICS=1 in the environment. On web it is on
## whenever the extension is present: the web export ships the wasm
## extension (variant/extensions_support=true) and there is no command
## line to pass a flag through. Wherever the extension is absent —
## a web export without it, or a desktop run without the flag —
## ClassDB has no OlcorePhysics and the GDScript port runs instead.
##
## Phase 2: the native sim meets the same obstacles and billboards as the
## GDScript port. The baked terrain carries the merged obstacle field the
## shot's model consults (see _obstacle_fields), and the Links model also
## gets the course's billboards and 3D objects (OlcoreLinksObjects). What
## still falls back: a baked box larger than MAX_BAKE_CELLS, an empty
## native result, and a ball that ends out of bounds on the box edge.
## LinksSurface records are baked only on greens; elsewhere the C++ class
## defaults apply, which is what every course checked so far uses.

## The baked box around a shot, in metres: the start-to-cup segment
## expanded by this much on every side, at 1 m cells, capped by
## MAX_BAKE_CELLS. A ball that ends within EDGE_M of the box edge is
## re-simulated by the inner model, so a clipped box can never turn a
## good shot into an out-of-bounds one.
const BAKE_MARGIN_M := 150.0
const BAKE_CELL_M := 1.0
const MAX_BAKE_CELLS := 500
const EDGE_M := 2.0

## Baked terrains shared by every model instance, keyed by terrain,
## hole and box: worker threads get a fresh model per shot, and re-baking
## for each of them would cost more than the native sim saves. Each entry
## is {"terrain": OlcoreTerrain, "objects": OlcoreLinksObjects or null}.
static var _bake_cache := {}
const _BAKE_CACHE_MAX := 4

var inner: ShotModel
var _physics = null  ## OlcorePhysics, created on first native use
var _aero = null  ## OlcoreAero, built from the inner model's tables
var _clubs = null  ## OlcoreClubs, built from the inner Links model's table
var _clubs_source := -1  ## instance id of the LinksLaunch it was built from


func _init(p_inner: ShotModel) -> void:
	inner = p_inner


static func use_native_enabled() -> bool:
	# On web there is no command line to pass --native-physics through,
	# so the wasm extension is used whenever it loaded; the GDScript
	# port is still the fallback when it did not (see native_available).
	if OS.has_feature("web"):
		return native_available()
	if OS.get_cmdline_user_args().has("--native-physics"):
		return true
	return OS.get_environment("LIDARLINKS_NATIVE_PHYSICS") == "1"


static func native_available() -> bool:
	return ClassDB.class_exists("OlcorePhysics")


## The inner model as a LinksShotModel, or null. The AI, the caddie and
## replays test `model is LinksShotModel` to set the Links-only swing
## flags (computer, chip, mouse_swing); through this wrapper that test
## fails, so they must unwrap with this instead (see computer_golfer.gd).
func links_model() -> LinksShotModel:
	return inner as LinksShotModel


## The inner model of any ShotModel, unwrapped from OlcoreShotModel.
static func unwrap(model: ShotModel) -> ShotModel:
	if model is OlcoreShotModel:
		return (model as OlcoreShotModel).inner
	return model


## The inner model of any ShotModel as a LinksShotModel, or null.
static func links_of(model: ShotModel) -> LinksShotModel:
	return unwrap(model) as LinksShotModel


func fresh() -> ShotModel:
	var m := OlcoreShotModel.new(inner.fresh())
	m.setup = setup
	m.backspin = backspin
	m.power_profile = power_profile
	return m


func launch(club: Club, power: float, accuracy: float, aim_deg: float, lie: int, from: Vector3) -> BallState:
	inner.setup = setup
	inner.backspin = backspin
	inner.power_profile = power_profile
	# The Links launch in C++ (links_launch / apply_swing), behind the
	# same flag as the native sim: the same strike, built the same way as
	# LinksShotModel.launch, with the native primitives in place of the
	# GDScript ones. Any failure before a random draw falls back to the
	# inner model; a failure after one restores the draw first (see
	# _launch_links_native).
	if use_native_enabled() and native_available():
		var links := inner as LinksShotModel
		if links != null and links.clubs != null:
			var b := _launch_links_native(links, club, power, accuracy, aim_deg, lie, from)
			if b != null:
				return b
	return inner.launch(club, power, accuracy, aim_deg, lie, from)


func reach_scale(club: Club) -> float:
	return inner.reach_scale(club)


func lie_power(lie: int, club: Club = null) -> float:
	return inner.lie_power(lie, club)


## The inner Links model's club table as OlcoreClubs, built once per
## LinksLaunch instance. Null when the table cannot be built.
func _native_clubs(links: LinksShotModel):
	if _clubs != null and _clubs_source == links.clubs.get_instance_id():
		return _clubs
	_clubs = null
	_clubs_source = -1
	if links.clubs == null:
		return null
	var c = ClassDB.instantiate("OlcoreClubs")
	if not c.set_table(links.clubs.spin, links.clubs.speed, links.clubs.loft_deg, links.clubs.glance,
			links.clubs.ball_position):
		return null
	_clubs = c
	_clubs_source = links.clubs.get_instance_id()
	return _clubs


static func _strike_dict(s: LinksLaunch.Strike) -> Dictionary:
	return {"club": s.club, "aim": s.aim, "power": s.power, "face_error": s.face_error,
			"path_error": s.path_error, "speed_scale": s.speed_scale, "spin_scale": s.spin_scale,
			"loft_scale": s.loft_scale, "setup_ball_position": s.setup.ball_position,
			"setup_face": s.setup.face, "setup_stance": s.setup.stance,
			"ground_normal": s.ground_normal}


## Copies a native strike Dictionary back into a Strike.
static func _read_strike(s: LinksLaunch.Strike, d: Dictionary) -> void:
	s.club = d.club
	s.aim = d.aim
	s.power = d.power
	s.face_error = d.face_error
	s.path_error = d.path_error
	s.speed_scale = d.speed_scale
	s.spin_scale = d.spin_scale
	s.loft_scale = d.loft_scale
	s.setup.ball_position = d.setup_ball_position
	s.setup.face = d.setup_face
	s.setup.stance = d.setup_stance
	s.ground_normal = d.ground_normal


static func _lie_dict(p: LinksGround.Params) -> Dictionary:
	return {"ground_class": p.ground_class, "restitution": p.restitution,
			"impact_friction": p.impact_friction, "skid_friction": p.skid_friction,
			"impact_drag": p.impact_drag, "roll_resistance": p.roll_resistance,
			"stop_speed": p.stop_speed, "spin_grip": p.spin_grip, "lie_spin": p.lie_spin,
			"lie_power": p.lie_power}


static func _swing_dict(w: LinksLaunch.SwingInput) -> Dictionary:
	return {"method": w.method, "skill": w.skill, "contact": w.contact, "full_power": w.full_power,
			"mouse_face_deg": w.mouse_face_deg, "mouse_path_deg": w.mouse_path_deg,
			"mouse_loft": w.mouse_loft, "left_handed": w.left_handed, "chip": w.chip,
			"teed_up": w.teed_up}


static func _ratings_dict(g: LinksLaunch.GolferRatings) -> Dictionary:
	return {"tee": g.tee, "woods": g.woods, "long_irons": g.long_irons, "mid_irons": g.mid_irons,
			"short_irons": g.short_irons, "wedges": g.wedges, "chips": g.chips,
			"max_power": g.max_power, "steady": g.steady, "long_putts": g.long_putts,
			"short_putts": g.short_putts}


## The game's launch in SI, from a native links_launch / links_putt
## result, as LinksLaunch.launch_state converts it. Null when the native
## call returns empty.
func _launch_state_native(clubs, s: LinksLaunch.Strike) -> BallState:
	var l: Dictionary = _physics.links_putt(_strike_dict(s)) if s.club == LinksLaunch.PUTTER \
			else _physics.links_launch(clubs, _strike_dict(s))
	if l.is_empty():
		return null
	var b := BallState.new(Vector3.ZERO)
	b.on_ground = s.club == LinksLaunch.PUTTER
	b.velocity = Vector3(-(l.velocity as Vector3).x, (l.velocity as Vector3).z,
			(l.velocity as Vector3).y) / LinksLaunch.FEET_PER_METRE
	b.spin = Vector3(-(l.spin as Vector3).x, (l.spin as Vector3).z, (l.spin as Vector3).y) * TAU
	return b


## LinksShotModel.launch with the native primitives (links_launch,
## apply_swing, apply_lie, meter_contact, computer_miss,
## computer_putt_miss) in place of the GDScript ones, step for step. The
## ratings, shares and chip/mouse handling stay in GDScript, identical to
## the inner model. Returns null on any native failure, after restoring
## the inner model's random draws, so launch() can fall back to the inner
## model with the round playing out the same.
func _launch_links_native(links: LinksShotModel, club: Club, power: float, accuracy: float,
		aim_deg: float, lie: int, from: Vector3) -> BallState:
	_physics_instance()
	var clubs = _native_clubs(links)
	if clubs == null:
		return null
	if not LinksLaunch.CLUB_INDEX.has(club.short_name) and not club.is_putter:
		return null
	var rng_state: int = links.rng.state
	# Restore the draws and report failure: the fallback must draw from
	# where the native path started, not from mid-way through it.
	var fail := func() -> BallState:
		links.rng.state = rng_state
		return null
	if club.is_putter:
		return _putt_links_native(links, clubs, power, accuracy, aim_deg, lie, from, rng_state, fail)
	var s := LinksLaunch.Strike.new()
	s.club = LinksLaunch.CLUB_INDEX[club.short_name]
	s.aim = deg_to_rad(aim_deg)
	var rating := 100.0 if links.chip else (LinksShotModel.club_rating(club) if links.computer \
			else links.player_rating(club))
	var share := clampf(power, 0.0, LinksShotModel.OVERSWING_MAX)
	s.power = rating * minf(share, 1.0) + 100.0 * maxf(share - 1.0, 0.0)
	s.setup.ball_position = setup.ball_position
	s.setup.face = setup.face
	s.setup.stance = setup.stance
	var lie_params := LinksGround.surface_for_class(LinksGround.ground_class_for(lie))
	if links.computer:
		if links.computer_ratings != null:
			var cw := LinksLaunch.ComputerSwing.new()
			cw.power = 100.0 * share if not links.chip else s.power
			cw.face_deg = -LinksShotModel.COMPUTER_FACE_ERROR_DEG * clampf(accuracy, -1.0, 1.0)
			var missed: Dictionary = _physics.links_computer_miss(
					{"power": cw.power, "face_deg": cw.face_deg, "path_deg": cw.path_deg},
					_ratings_dict(links.computer_ratings), s.club, lie == Surface.Type.TEE, links.chip,
					lie_params.ground_class, links.to_hole_m * LinksLaunch.FEET_PER_METRE, rng_state)
			if missed.is_empty():
				return fail.call()
			var msw: Dictionary = missed.swing
			rng_state = missed.rng_state
			s.power = msw.power if links.chip else float(msw.power) * rating / 100.0
			s.face_error = deg_to_rad(msw.face_deg)
			s.path_error = deg_to_rad(msw.path_deg)
		else:
			s.face_error = -deg_to_rad(LinksShotModel.COMPUTER_FACE_ERROR_DEG) * clampf(accuracy, -1.0, 1.0)
		var lied: Dictionary = _physics.links_apply_lie(_strike_dict(s), _lie_dict(lie_params))
		if lied.is_empty():
			return fail.call()
		_read_strike(s, lied.strike)
		var cb := _launch_state_native(clubs, s)
		if cb == null:
			return fail.call()
		links.rng.state = rng_state
		cb.position = from
		return cb
	var w := LinksLaunch.SwingInput.new()
	w.skill = links.skill
	w.teed_up = lie == Surface.Type.TEE
	w.chip = links.chip
	if links.mouse_swing != null:
		w.method = LinksLaunch.Method.MOUSE
		w.mouse_face_deg = links.mouse_swing.face_deg
		w.mouse_path_deg = links.mouse_swing.path_deg
		s.power = links.mouse_swing.power * (1.0 if links.chip else rating / LinksShotModel.club_rating(club))
	else:
		w.contact = _physics.links_meter_contact(
				-LinksShotModel.METER_UNITS_AT_FULL_MISS * clampf(accuracy, -1.0, 1.0), links.skill)
	w.full_power = rating
	var swung: Dictionary = _physics.links_apply_swing(_strike_dict(s), _swing_dict(w),
			_lie_dict(lie_params), rng_state)
	if swung.is_empty():
		return fail.call()
	_read_strike(s, swung.strike)
	rng_state = swung.rng_state
	var b := _launch_state_native(clubs, s)
	if b == null:
		return fail.call()
	links.rng.state = rng_state
	ShotShape.add_backspin(b, backspin)
	b.position = from
	return b


## LinksShotModel._putt with the native primitives, step for step.
func _putt_links_native(links: LinksShotModel, clubs, power: float, accuracy: float, aim_deg: float,
		lie: int, from: Vector3, rng_state: int, fail: Callable) -> BallState:
	var s := LinksLaunch.Strike.new()
	s.club = LinksLaunch.PUTTER
	s.aim = deg_to_rad(aim_deg)
	s.power = LinksShotModel.PUTT_POWER_AT_FULL * clampf(power, 0.0, 1.0)
	var acc := clampf(accuracy, -1.0, 1.0)
	if links.computer and links.computer_ratings != null:
		var cw := LinksLaunch.ComputerSwing.new()
		cw.power = s.power
		var missed: Dictionary = _physics.links_computer_putt_miss(
				{"power": cw.power, "face_deg": cw.face_deg, "path_deg": cw.path_deg},
				_ratings_dict(links.computer_ratings), LinksGround.ground_class_for(lie),
				links.to_hole_m * LinksLaunch.FEET_PER_METRE, rng_state)
		if missed.is_empty():
			return fail.call()
		var msw: Dictionary = missed.swing
		rng_state = missed.rng_state
		s.power = msw.power
		s.path_error = deg_to_rad(msw.path_deg)
	elif links.computer:
		s.face_error = deg_to_rad(LinksShotModel.COMPUTER_PUTT_FACE_ERROR_DEG) * acc
	else:
		var w := LinksLaunch.SwingInput.new()
		w.skill = links.skill
		if links.mouse_swing != null:
			w.method = LinksLaunch.Method.MOUSE
			w.mouse_face_deg = links.mouse_swing.face_deg
			w.mouse_path_deg = links.mouse_swing.path_deg
			s.power = links.mouse_swing.power
		else:
			w.contact = _physics.links_meter_contact(
					-LinksShotModel.METER_UNITS_AT_FULL_MISS * acc, links.skill)
		var swung: Dictionary = _physics.links_apply_swing(_strike_dict(s), _swing_dict(w),
				_lie_dict(LinksGround.surface_for_class(LinksGround.ground_class_for(lie))), rng_state)
		if swung.is_empty():
			return fail.call()
		_read_strike(s, swung.strike)
		rng_state = swung.rng_state
	var b := _launch_state_native(clubs, s)
	if b == null:
		return fail.call()
	links.rng.state = rng_state
	b.position = from
	return b


func simulate_chunked(start: BallState, terrain: CourseTerrain, cup: Vector3, wind := Vector3.ZERO) -> ResumableShot:
	# No chunked form of the native sim, and none is needed: the native
	# path only runs where worker threads exist. The GDScript port chunks,
	# and gives the same result as the native sim.
	return inner.simulate_chunked(start, terrain, cup, wind)


func simulate(start: BallState, terrain: CourseTerrain, cup: Vector3, wind := Vector3.ZERO) -> ShotResult:
	if not use_native_enabled() or not native_available():
		return inner.simulate(start, terrain, cup, wind)
	var baked: Dictionary = _native_terrain(terrain, start, cup)
	if baked.is_empty():
		return inner.simulate(start, terrain, cup, wind)
	var native = baked.terrain
	var aero = _native_aero()
	var r: Dictionary = _physics.simulate_shot(start.position, start.velocity, start.spin, start.on_ground,
			wind, aero, native, true, cup, BallPhysics.CUP_RADIUS, BallPhysics.MAX_TIME, baked.objects)
	if r.is_empty():
		return inner.simulate(start, terrain, cup, wind)
	var out := _shot_result_from_dict(r)
	# A ball that stopped on the edge of the baked box may have been cut
	# short by the box, not by the course: play it again in GDScript.
	if out.outcome == ShotResult.Outcome.OUT_OF_BOUNDS and _near_box_edge(native, out.rest):
		return inner.simulate(start, terrain, cup, wind)
	return out


func _physics_instance():
	if _physics == null:
		_physics = ClassDB.instantiate("OlcorePhysics")
	return _physics


func _native_aero():
	if _aero != null:
		return _aero
	_aero = null
	var links := inner as LinksShotModel
	if links != null and links.aero != null:
		var a = ClassDB.instantiate("OlcoreAero")
		if a.set_tables(links.aero.drag, links.aero.lift):
			_aero = a
	return _aero


func _native_terrain(terrain: CourseTerrain, start: BallState, cup: Vector3) -> Dictionary:
	_physics_instance()
	var key := "%d|%d|%d|%d|%d|%d" % [terrain.get_instance_id(), terrain.hole_number,
			int(start.position.x / 10.0), int(start.position.z / 10.0),
			int(cup.x / 10.0), int(cup.z / 10.0)]
	if _bake_cache.has(key):
		return _bake_cache[key]
	var baked := _bake(terrain, start, cup)
	if baked.is_empty():
		return {}
	_bake_cache[key] = baked
	if _bake_cache.size() > _BAKE_CACHE_MAX:
		_bake_cache.clear()
		_bake_cache[key] = baked
	return baked


## The obstacle fields the shot's model consults, as in CourseTerrain:
## the Links model meets the 3D models' boxes (model_obstacles) when the
## course has billboards for it, else the course's own obstacles; the
## stand-in model always meets the course's own. The hole's own obstacles
## are always added. Which model runs is decided by the aero tables (see
## simulate): the Links model only when they are set, exactly as
## BallPhysics.simulate_shot decides.
func _obstacle_fields(terrain: CourseTerrain, links_model: bool) -> Array:
	var fields := []
	var base = terrain.obstacles
	if links_model and terrain.links_objects != null:
		base = terrain.model_obstacles
	if base != null:
		fields.append(base)
	if terrain.hole_obstacles != null:
		fields.append(terrain.hole_obstacles)
	return fields


func _bake(terrain: CourseTerrain, start: BallState, cup: Vector3) -> Dictionary:
	var min_x := minf(start.position.x, cup.x) - BAKE_MARGIN_M
	var max_x := maxf(start.position.x, cup.x) + BAKE_MARGIN_M
	var min_z := minf(start.position.z, cup.z) - BAKE_MARGIN_M
	var max_z := maxf(start.position.z, cup.z) + BAKE_MARGIN_M
	var nx := int((max_x - min_x) / BAKE_CELL_M) + 1
	var nz := int((max_z - min_z) / BAKE_CELL_M) + 1
	if nx > MAX_BAKE_CELLS or nz > MAX_BAKE_CELLS:
		return {}
	var heights := PackedFloat32Array()
	var surfaces := PackedByteArray()
	var green := PackedFloat32Array()
	var has_green := PackedByteArray()
	heights.resize(nx * nz)
	surfaces.resize(nx * nz)
	green.resize(nx * nz * 10)
	has_green.resize(nx * nz)
	for iz in nz:
		var z := min_z + iz * BAKE_CELL_M
		for ix in nx:
			var x := min_x + ix * BAKE_CELL_M
			var i := iz * nx + ix
			heights[i] = terrain.height_at(x, z)
			var s := terrain.surface_at(x, z)
			surfaces[i] = s
			if s == Surface.Type.GREEN:
				var p = terrain.links_surface_at(x, z)
				if p != null:
					has_green[i] = 1
					green[i * 10 + 0] = p.ground_class
					green[i * 10 + 1] = p.restitution
					green[i * 10 + 2] = p.impact_friction
					green[i * 10 + 3] = p.skid_friction
					green[i * 10 + 4] = p.impact_drag
					green[i * 10 + 5] = p.roll_resistance
					green[i * 10 + 6] = p.stop_speed
					green[i * 10 + 7] = p.spin_grip
					green[i * 10 + 8] = p.lie_spin
					green[i * 10 + 9] = p.lie_power
	var t = ClassDB.instantiate("OlcoreTerrain")
	if not t.bake(min_x, min_z, BAKE_CELL_M, nx, nz, heights, surfaces, green, has_green):
		return {}
	# The merged obstacle field for this shot's model, in the baked box.
	# Merging is exact: segment_hit takes the earliest entry over all
	# items, which is what CourseTerrain does across its two fields.
	var aero = _native_aero()
	var cylinders := PackedFloat32Array()
	var boxes := PackedFloat32Array()
	for field in _obstacle_fields(terrain, aero != null):
		cylinders.append_array((field as ObstacleField).cylinders_in(min_x, min_z, max_x, max_z))
		boxes.append_array((field as ObstacleField).boxes_in(min_x, min_z, max_x, max_z))
	if not t.bake_obstacles(cylinders, boxes):
		return {}
	var objects = _bake_links_objects(terrain, aero, min_x, min_z, max_x, max_z)
	if objects is bool:
		return {}
	return {"terrain": t, "objects": objects}


## The billboards and 3D objects for the Links model, in the baked box,
## or null when the shot runs the stand-in model or the course has none.
## Returns false when the bake itself fails (the shot then falls back).
func _bake_links_objects(terrain: CourseTerrain, aero, min_x: float, min_z: float, max_x: float,
		max_z: float):
	if aero == null or terrain.links_objects == null:
		return null
	var src: LinksObjects = terrain.links_objects
	var billboards: Dictionary = src.billboards_in(min_x, min_z, max_x, max_z)
	var models: Array = src.models_in(min_x, min_z, max_x, max_z)
	if (billboards.bases as PackedVector3Array).is_empty() and models.is_empty():
		return null
	var objects = ClassDB.instantiate("OlcoreLinksObjects")
	var types: Dictionary = src.export_types()
	if not objects.set_types(types.collisions, types.shapes, types.aspects, types.mask_widths,
			types.mask_heights, types.mask_alphas, types.mask_offsets):
		return false
	for i in (billboards.bases as PackedVector3Array).size():
		objects.add_billboard((billboards.bases as PackedVector3Array)[i],
				(billboards.heights as PackedFloat32Array)[i], (billboards.anchor_x as PackedFloat32Array)[i],
				(billboards.anchor_z as PackedFloat32Array)[i], (billboards.types as PackedInt32Array)[i])
	# Only the meshes a model in the box uses, with the model's mesh
	# index remapped onto them.
	var wanted := {}
	for m in models:
		wanted[m.mesh] = true
	var remap := {}
	var exported: Array = src.export_meshes()
	for i in exported.size():
		if not wanted.has(i):
			continue
		var mesh: Dictionary = exported[i]
		var at: int = objects.add_mesh(mesh.positions, mesh.uvs, mesh.corners, mesh.faces, mesh.hole_widths,
				mesh.hole_heights, mesh.hole_alphas, mesh.hole_offsets)
		if at < 0:
			return false
		remap[i] = at
	for m in models:
		if not objects.add_model(remap[m.mesh], m.points):
			return false
	return objects


func _near_box_edge(native, pos: Vector3) -> bool:
	var origin: Vector2 = native.get_origin()
	var cell: float = native.get_cell_size()
	var size: Vector2i = native.get_size()
	var max_x: float = origin.x + (size.x - 1) * cell
	var max_z: float = origin.y + (size.y - 1) * cell
	return pos.x < origin.x + EDGE_M or pos.x > max_x - EDGE_M \
			or pos.z < origin.y + EDGE_M or pos.z > max_z - EDGE_M


static func _shot_result_from_dict(r: Dictionary) -> ShotResult:
	var out := ShotResult.new()
	out.outcome = r.outcome as ShotResult.Outcome
	out.rest = r.rest
	out.first_landing = r.first_landing
	out.rest_surface = r.rest_surface
	out.carry_m = r.carry_m
	out.total_m = r.total_m
	out.apex_m = r.apex_m
	out.time_s = r.time_s
	out.bounces = r.bounces
	out.obstacle_hits = r.obstacle_hits
	out.times = r.times
	out.points = r.points
	return out
