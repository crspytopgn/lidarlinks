class_name RockFormations
extends RefCounted
## Sandstone formations for desert courses (docs/epic-courses.md): towers
## (spires), hoodoos with cap rocks, flat-topped buttes, a natural arch and
## fallen blocks, built here from a few numbers per formation rather than
## shipped as models. They are modelled on the Colorado Plateau's: walls
## of stacked beds that step in and out (hard beds stand out as ledges,
## soft ones weather back), towers that taper to a harder cap, buttes on a
## skirt of fallen rubble (talus), arches whose feet flare into the rock
## they were cut from. Every formation is its own mesh, varied by a seed
## from where it stands; the course is seen from everywhere, so they are
## drawn for every hole (DesignedTerrain.build_visual) and never per hole.
##
## params() is the one description of each formation: the mesh and what
## the ball can hit (add_obstacles) both come from it.

const IDS := ["rock_spire", "rock_hoodoo", "rock_butte", "rock_arch", "rock_boulder"]
const SHADER := preload("res://shaders/rock_formation.gdshader")
## Metres between rings up a tower, and points round each.
const RING_STEP := 1.1
const SIDES := 36
const BOULDER_VARIANTS := 4
## How square towers and buttes are in plan (2 a circle, higher squarer).
const SQUARE := 2.8

static var _material: ShaderMaterial
static var _boulders: Array[ArrayMesh] = []
static var _cache := {}  ## "id x z scale" -> ArrayMesh


static func is_rock(id: String) -> bool:
	return id.begins_with("rock_") and IDS.has(id)


## A formation's numbers: kind, height, radii, seed. Deterministic from
## where it stands, so the mesh and its obstacles agree everywhere.
static func params(o: PlacedObject) -> Dictionary:
	var seed_value := hash(Vector2i(roundi(o.position.x * 10.0), roundi(o.position.z * 10.0))) & 0xffffff
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var s := o.scale
	match o.id:
		"rock_spire":
			return {"seed": seed_value, "height": 40.0 * s * rng.randf_range(0.85, 1.15), "base": 9.0 * s,
				"waist": 5.2 * s * rng.randf_range(0.85, 1.1), "cap": 4.4 * s, "stretch": rng.randf_range(1.0, 1.45)}
		"rock_hoodoo":
			return {"seed": seed_value, "height": 14.0 * s * rng.randf_range(0.85, 1.15), "base": 4.5 * s,
				"waist": 1.7 * s, "cap": 2.7 * s, "stretch": rng.randf_range(1.0, 1.25)}
		"rock_butte":
			return {"seed": seed_value, "height": 45.0 * s * rng.randf_range(0.85, 1.1), "base": 48.0 * s,
				"waist": 33.0 * s, "cap": 31.0 * s, "stretch": rng.randf_range(1.15, 1.5)}
		"rock_arch":
			return {"seed": seed_value, "span": 46.0 * s, "height": 30.0 * s, "rib": 8.5 * s, "depth": 10.0 * s}
		"rock_boulder":
			return {"seed": seed_value, "radius": 1.2 * s, "variant": seed_value % BOULDER_VARIANTS}
	return {}


## The formations, boulders and all, standing on `terrain`'s course, or
## null when it has none.
@warning_ignore("integer_division")
static func build(terrain: DesignedTerrain) -> Node3D:
	var root: Node3D = null
	var boulders: Array[PackedFloat32Array] = []
	boulders.resize(BOULDER_VARIANTS)
	for o in terrain.course.objects:
		if not is_rock(o.id):
			continue
		if root == null:
			root = Node3D.new()
			root.name = "RockFormations"
		var y := _foot(terrain, o)
		if o.id == "rock_boulder":
			var p := params(o)
			var t := Transform3D(Basis(Vector3.UP, deg_to_rad(o.yaw_deg)).scaled(Vector3.ONE * float(p.radius)), Vector3(o.position.x, y, o.position.z))
			var list := boulders[int(p.variant)]
			list.append_array(PackedFloat32Array([t.basis.x.x, t.basis.y.x, t.basis.z.x, t.origin.x,
				t.basis.x.y, t.basis.y.y, t.basis.z.y, t.origin.y, t.basis.x.z, t.basis.y.z, t.basis.z.z, t.origin.z]))
			boulders[int(p.variant)] = list
			continue
		var inst := MeshInstance3D.new()
		inst.name = o.id
		inst.mesh = mesh_for(o)
		inst.material_override = material()
		inst.position = Vector3(o.position.x, y, o.position.z)
		inst.rotation_degrees.y = o.yaw_deg
		root.add_child(inst)
	for v in BOULDER_VARIANTS:
		if boulders[v].is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = boulder_mesh(v)
		mm.instance_count = boulders[v].size() / 12
		mm.buffer = boulders[v]
		var node := MultiMeshInstance3D.new()
		node.name = "Boulders%d" % v
		node.multimesh = mm
		node.material_override = material()
		node.visibility_range_end = 900.0
		root.add_child(node)
	return root


## The lowest ground under a formation's middle, so it never floats on a
## slope.
static func _foot(terrain: DesignedTerrain, o: PlacedObject) -> float:
	var x := o.position.x
	var z := o.position.z
	var r := 2.0 * o.scale
	var y := terrain.height_at(x, z)
	for k in 6:
		var a := TAU * k / 6.0
		y = minf(y, terrain.height_at(x + cos(a) * r, z + sin(a) * r))
	return y


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		var l := Biome.land(Biome.DESERT)
		_material.set_shader_parameter("rock_color", l.rock)
		_material.set_shader_parameter("rock2_color", l.rock2)
		var albedo := FreeAssets.ground("cliff", "albedo")
		var normal := FreeAssets.ground("cliff", "normal")
		if albedo != null and normal != null:
			_material.set_shader_parameter("detail_albedo", albedo)
			_material.set_shader_parameter("detail_normal", normal)
			var mean := FreeAssets.mean_color(albedo).srgb_to_linear()
			_material.set_shader_parameter("detail_mean", Vector3(mean.r, mean.g, mean.b))
			_material.set_shader_parameter("has_detail", true)
	return _material


static func mesh_for(o: PlacedObject) -> ArrayMesh:
	var key := "%s %.1f %.1f %.2f" % [o.id, o.position.x, o.position.z, o.scale]
	if _cache.has(key):
		return _cache[key]
	var p := params(o)
	var part := ProcMesh.new_part()
	match o.id:
		"rock_spire":
			_tower(part, p, _spire_profile)
		"rock_hoodoo":
			_tower(part, p, _hoodoo_profile)
		"rock_butte":
			_tower(part, p, _butte_profile)
		"rock_arch":
			_arch(part, p)
	var mesh := ProcMesh.to_mesh(part)
	_cache[key] = mesh
	return mesh


# --- Towers -------------------------------------------------------------------
# A tower is rings stacked from below the ground to its top. Its radius at
# height t (0 to 1 of its height) comes from a profile; each ring's outline
# wanders by low-harmonic noise (a buttress here, a recess there) and steps
# in and out by bed (ledges every few metres), and the whole stretches one
# way, as joints split fins and towers along one direction.

static func _spire_profile(t: float, p: Dictionary) -> float:
	var base: float = p.base
	var waist: float = p.waist
	var cap: float = p.cap
	# Talus skirt, then the tower narrowing up to a harder cap.
	var r := lerpf(waist * 1.15, waist * 0.8, smoothstep(0.15, 0.85, t))
	r = lerpf(base, r, smoothstep(0.0, 0.16, t))
	r = lerpf(r, cap, smoothstep(0.86, 0.9, t))
	return r


static func _hoodoo_profile(t: float, p: Dictionary) -> float:
	var base: float = p.base
	var waist: float = p.waist
	var cap: float = p.cap
	# A pedestal, a column of soft and hard beds (beads), a cap rock.
	var beads := 1.0 + 0.22 * sin(t * 26.0)
	var r := lerpf(base, waist * beads, smoothstep(0.0, 0.3, t))
	r = lerpf(r, cap, smoothstep(0.82, 0.86, t))
	return r


static func _butte_profile(t: float, p: Dictionary) -> float:
	var base: float = p.base
	var waist: float = p.waist
	var cap: float = p.cap
	# A concave apron of rubble to a third of the way up, then a cliff with
	# a bench (a harder bed) at about two thirds, and the flat top.
	var apron := 1.0 - pow(1.0 - smoothstep(0.0, 0.34, t), 1.8)
	var r := lerpf(base, waist, apron)
	r = lerpf(r, cap, smoothstep(0.6, 0.64, t))
	return r


static func _tower(part: Dictionary, p: Dictionary, profile: Callable) -> void:
	var height: float = p.height
	var seed_value: int = p.seed
	var stretch: float = p.stretch
	var rings: Array[PackedVector3Array] = []
	var colors := PackedColorArray()
	var bottom := -4.0
	var count := maxi(8, ceili((height - bottom) / RING_STEP))
	var sides := SIDES if height > 20.0 else 24
	for j in count + 1:
		var y := lerpf(bottom, height, float(j) / count)
		var t := clampf(y / height, 0.0, 1.0)
		var r: float = profile.call(t, p)
		# Beds: ledges every 2 to 5 metres, the hard ones standing out.
		var bed := ProcMesh.noise(y / 3.1, 0.5, seed_value + 7)
		r *= 0.965 + 0.07 * smoothstep(0.35, 0.65, bed)
		var ring := PackedVector3Array()
		for i in sides:
			var a := TAU * i / sides
			# Joints square the outline off into faces with rounded
			# corners (a superellipse), then buttresses and recesses
			# wander it, and rain cuts vertical flutes into it.
			var c := cos(a)
			var sn := sin(a)
			var square := 1.0 / pow(pow(absf(c), SQUARE) + pow(absf(sn), SQUARE), 1.0 / SQUARE)
			var wobble := 0.36 * (ProcMesh.ring_noise(a, y / 22.0, 5, seed_value) - 0.5)
			wobble += 0.16 * (ProcMesh.ring_noise(a, y / 7.0, 13, seed_value + 3) - 0.5)
			wobble += 0.05 * (ProcMesh.ring_noise(a, y / 40.0, 31, seed_value + 5) - 0.5)
			var rr := r * square * (1.0 + wobble)
			ring.append(Vector3(c * rr * stretch, y, sn * rr))
		rings.append(ring)
		# Darker low down in the rubble's shade and in the soft beds.
		colors.append(Color(1, 1, 1).darkened(0.25 * (1.0 - smoothstep(0.0, 0.25, t))))
	# A gently domed top with a broken edge.
	var top: PackedVector3Array = rings[rings.size() - 1]
	var inner := PackedVector3Array()
	for q in top:
		inner.append(Vector3(q.x * 0.7, height + 0.6, q.z * 0.7))
	rings.append(inner)
	colors.append(Color.WHITE)
	ProcMesh.add_rings(part, rings, colors, true)


# --- The arch -----------------------------------------------------------------
# A rib swept along a flattened half-ellipse from one foot to the other,
# thicker at the crown's ends and flaring into massive abutments at the
# feet, set in the rock fin it was cut from (two low towers).

static func _arch(part: Dictionary, p: Dictionary) -> void:
	var span: float = p.span
	var height: float = p.height
	var rib: float = p.rib
	var depth: float = p.depth
	var seed_value: int = p.seed
	var a := span * 0.5 + rib * 0.5
	var b := height + rib * 0.5
	var steps := 48
	var rings: Array[PackedVector3Array] = []
	var colors := PackedColorArray()
	for k in steps + 1:
		var u := lerpf(-0.14, PI + 0.14, float(k) / steps)
		# A flattened crown (a superellipse), as real spans are.
		var su := signf(sin(u)) * pow(absf(sin(u)), 0.7)
		var centre := Vector3(a * cos(u), b * su, 0.0)
		# Thick feet, a slimmer span, a heavier crown.
		var foot := 1.0 - smoothstep(0.0, 0.9, minf(u + 0.14, PI + 0.14 - u))
		# Weathered unevenly: the rib swells and pinches along its length,
		# and one leg is heavier than the other.
		var along := 0.75 + 0.5 * ProcMesh.noise(float(k) / 7.0, 3.5, seed_value + 17)
		var lean := 1.0 + 0.25 * cos(u)
		var thick := rib * (1.0 + 1.6 * foot + 0.15 * sin(u)) * along * lean
		var deep := depth * (1.0 + 0.8 * foot) * (0.85 + 0.3 * ProcMesh.noise(float(k) / 5.0, 7.5, seed_value + 23))
		var out := Vector3(cos(u), sin(u), 0.0)  # away from the opening
		var ring := PackedVector3Array()
		var sides := 24
		for i in sides:
			var ang := TAU * i / sides
			var wob := 1.0 + 0.34 * (ProcMesh.ring_noise(ang, float(k) / 5.0, 5, seed_value) - 0.5)
			wob += 0.16 * (ProcMesh.ring_noise(ang, float(k) / 1.7, 11, seed_value + 9) - 0.5)
			# A rounded box across the rib (out by thick, z by depth).
			var c := cos(ang)
			var s := sin(ang)
			var sq := Vector2(signf(c) * pow(absf(c), 0.6), signf(s) * pow(absf(s), 0.6))
			ring.append(centre + (out * sq.x * thick * 0.5 + Vector3(0, 0, 1) * sq.y * deep * 0.5) * wob)
		rings.append(ring)
		colors.append(Color.WHITE.darkened(0.2 * foot))
	ProcMesh.add_rings(part, rings, colors, true)
	# The abutments: the fin the arch was cut from, either side.
	for side in [-1.0, 1.0]:
		var ab := ProcMesh.new_part()
		var q := {"seed": seed_value + int(side * 11.0), "height": height * 0.55, "base": rib * 2.4,
			"waist": rib * 1.5, "cap": rib * 1.3, "stretch": 0.7}
		_tower(ab, q, _spire_profile)
		var shift := Vector3(side * (a + rib * 0.8), 0.0, 0.0)
		var off: int = (part.verts as PackedVector3Array).size()
		for v: Vector3 in ab.verts:
			(part.verts as PackedVector3Array).append(v + shift)
		(part.normals as PackedVector3Array).append_array(ab.normals)
		(part.colors as PackedColorArray).append_array(ab.colors)
		for i: int in ab.indices:
			(part.indices as PackedInt32Array).append(i + off)


# --- Boulders -------------------------------------------------------------------

static func boulder_mesh(variant: int) -> ArrayMesh:
	while _boulders.size() <= variant:
		var v := _boulders.size()
		var part := ProcMesh.new_part()
		var rings: Array[PackedVector3Array] = []
		var n := 9
		for j in n + 1:
			var phi := lerpf(-0.45 * PI, 0.5 * PI, float(j) / n)
			var ring := PackedVector3Array()
			for i in 14:
				var a := TAU * i / 14.0
				var r := 1.0 + 0.3 * (ProcMesh.ring_noise(a, float(j) / 3.0, 4, 91 + v * 13) - 0.5)
				# Blocky: flattened top and sides, as joints break them.
				var c := Vector3(cos(phi) * cos(a), sin(phi) * 0.7, cos(phi) * sin(a))
				c = Vector3(signf(c.x) * pow(absf(c.x), 0.75), signf(c.y) * pow(absf(c.y), 0.75), signf(c.z) * pow(absf(c.z), 0.75))
				ring.append(c * r * Vector3(1.0 + 0.3 * v / BOULDER_VARIANTS, 1.0, 1.0) + Vector3(0, 0.2, 0))
			rings.append(ring)
		ProcMesh.add_rings(part, rings, PackedColorArray(), true)
		_boulders.append(ProcMesh.to_mesh(part))
	return _boulders[variant]


# --- What the ball can hit -------------------------------------------------------

## Adds the formation `o` standing on ground height `y` to `field`, as
## drawn: a tower as a stack of cylinders following its profile, the arch
## as its two legs and the span over them.
static func add_obstacles(field: ObstacleField, o: PlacedObject, y: float) -> void:
	var p := params(o)
	if p.is_empty():
		return
	var x := o.position.x
	var z := o.position.z
	match o.id:
		"rock_spire", "rock_hoodoo", "rock_butte":
			var profile: Callable = _spire_profile
			if o.id == "rock_hoodoo":
				profile = _hoodoo_profile
			elif o.id == "rock_butte":
				profile = _butte_profile
			var height: float = p.height
			var bands := 6
			var stretch: float = p.stretch
			for k in bands:
				var t0 := float(k) / bands
				var t1 := float(k + 1) / bands
				# The band's typical radius, a little inside the outline
				# (the wobble goes both ways).
				var r: float = (profile.call(t0, p) + profile.call(t1, p)) * 0.5 * 0.95
				field.add_cylinder(x, z, r * sqrt(stretch), y - 2.0 + height * t0, y + height * t1 + (0.6 if k == bands - 1 else 0.0), ObstacleField.Kind.SOLID)
		"rock_arch":
			var axes := Basis(Vector3.UP, deg_to_rad(o.yaw_deg))
			var span: float = p.span
			var height: float = p.height
			var rib: float = p.rib
			var depth: float = p.depth
			var a := span * 0.5 + rib * 0.5
			for side in [-1.0, 1.0]:
				# Each leg and its abutment.
				var leg := Vector3(side * (a + rib * 0.3), y + height * 0.35, 0.0)
				field.add_box(Vector3(x, 0, z) + axes * leg, axes, Vector3(rib * 1.3, height * 0.4, depth * 0.7), ObstacleField.Kind.SOLID)
			# The span over the opening.
			field.add_box(Vector3(x, y + height + rib * 0.35, z), axes, Vector3(a, rib * 0.55, depth * 0.5), ObstacleField.Kind.SOLID)
		"rock_boulder":
			var r: float = p.radius
			field.add_cylinder(x, z, r * 0.95, y - 0.5, y + r * 0.85, ObstacleField.Kind.SOLID)
