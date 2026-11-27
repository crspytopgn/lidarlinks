class_name DesertPlants
extends RefCounted
## Cacti for desert courses (docs/epic-courses.md): saguaros, the tall
## ribbed columns with upturned arms; barrel cacti, squat ribbed globes; and
## prickly pear, clumps of flat oval pads growing out of each other. Built
## here from a few numbers (no models), a few variants of each, and drawn
## over the whole course in MultiMeshes by area, so thousands cost a few
## draws. Visual only: what the ball can hit is in add_obstacles.
##
## Figures: saguaros 4 to 12 m with arms from about 2.5 m up, stems 30 to
## 40 cm across with 12 to 24 ribs; barrels 0.5 to 1 m; prickly pear pads
## about 25 by 18 cm, clumps up to a metre or so high (US National Park
## Service, Saguaro NP and Organ Pipe Cactus NM species pages).
##
## Also the coconut palm for tropical courses: a ringed, curving trunk 8 to
## 15 m tall, 25 to 30 cm across, leaning toward the light, under a crown of
## a dozen or more fronds 4 to 5 m long that arch out and droop (Hawaii
## Tropical Plant Guide; University of Hawaii CTAHR coconut fact sheet).
##
## Where a scanned model is there (CourseProps.SKETCHFAB_DIR, "<id>_<variant>":
## PlantCatalog's saguaros and golden barrels from Sketchfab, CC BY, scaled
## to the same heights so the obstacles still match), it is drawn instead,
## with its own textures.

const IDS := ["cactus_saguaro", "cactus_barrel", "cactus_pear", "palm_coconut"]
const VARIANTS := 4
## Metres on a side of the areas each MultiMesh covers.
const AREA := 400.0
## How far off each kind is drawn, by quality (low, medium, high, ultra).
const SAGUARO_RANGE: Array[float] = [600.0, 900.0, 1400.0, 1800.0]
const SMALL_RANGE: Array[float] = [0.0, 120.0, 220.0, 320.0]

const STEM := Color(0.3, 0.4, 0.24)  # saguaro, waxy blue-green
const STEM_OLD := Color(0.4, 0.37, 0.29)  # its corky grey-brown base
const BARREL := Color(0.26, 0.32, 0.16)
const BARREL_CROWN := Color(0.85, 0.62, 0.22)  # the yellow fruit and spines on top
const PAD := Color(0.3, 0.38, 0.17)
const PAD_PURPLE := Color(0.38, 0.27, 0.27)  # pads turn purple in drought and cold
const PALM_TRUNK := Color(0.46, 0.42, 0.36)  # weathered grey-brown
const PALM_TRUNK_DARK := Color(0.32, 0.28, 0.22)  # the rings and the base
const FROND := Color(0.24, 0.36, 0.1)
const FROND_OLD := Color(0.55, 0.47, 0.2)  # lower fronds yellow before they drop

static var _meshes := {}  ## id -> Array[ArrayMesh]
static var _material: StandardMaterial3D


static func is_plant(id: String) -> bool:
	return IDS.has(id)


static func variant_of(o: PlacedObject) -> int:
	return (hash(Vector2i(roundi(o.position.x * 10.0), roundi(o.position.z * 10.0))) >> 3) % VARIANTS


## The cacti on `terrain`'s course, or null when it has none.
@warning_ignore("integer_division")
static func build(terrain: DesignedTerrain) -> Node3D:
	var quality := clampi(Landscape.detail, 0, 3)
	var groups := {}  ## [id, variant, area cell] -> PackedFloat32Array of transforms
	var scales := {}  ## [id, variant, area cell] -> the tallest scale in it
	for o in terrain.course.objects:
		if not is_plant(o.id):
			continue
		if not _tall(o.id) and SMALL_RANGE[quality] <= 0.0:
			continue
		var cell := Vector2i(floori(o.position.x / AREA), floori(o.position.z / AREA))
		var key := [o.id, variant_of(o), cell]
		var y := terrain.height_at(o.position.x, o.position.z)
		var t := Transform3D(Basis(Vector3.UP, deg_to_rad(o.yaw_deg)).scaled(Vector3.ONE * o.scale), Vector3(o.position.x, y - 0.05, o.position.z))
		var buf: PackedFloat32Array = groups.get(key, PackedFloat32Array())
		buf.append_array(PackedFloat32Array([t.basis.x.x, t.basis.y.x, t.basis.z.x, t.origin.x,
			t.basis.x.y, t.basis.y.y, t.basis.z.y, t.origin.y, t.basis.x.z, t.basis.y.z, t.basis.z.z, t.origin.z]))
		groups[key] = buf
		scales[key] = maxf(float(scales.get(key, 0.0)), o.scale)
	if groups.is_empty():
		return null
	var root := Node3D.new()
	root.name = "DesertPlants"
	for key: Array in groups:
		var buf: PackedFloat32Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh(key[0], key[1])
		mm.instance_count = buf.size() / 12
		mm.buffer = buf
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		if not is_scanned(key[0], key[1]):
			node.material_override = material()
		node.visibility_range_end = SAGUARO_RANGE[quality] if _tall(key[0]) else SMALL_RANGE[quality]
		node.visibility_range_end_margin = 30.0
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		# The tallest plant in the area, for the shadow rule
		# (DesignedTerrain.refresh_plant_shadows): how far its shadow can
		# reach off the line of play.
		node.set_meta("shadow_height", height_of(key[0], key[1]) * float(scales.get(key, 1.0)))
		root.add_child(node)
	return root


static func _tall(id: String) -> bool:
	return id == "cactus_saguaro" or id == "palm_coconut"


static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.62
		_material.metallic_specular = 0.35
	return _material


## True when variant `variant` of `id` is a scanned model (see the top).
static func is_scanned(id: String, variant: int) -> bool:
	return CourseProps.is_textured("%s_%d" % [id, variant % VARIANTS])


static func mesh(id: String, variant: int) -> Mesh:
	if is_scanned(id, variant):
		var scanned := CourseProps.mesh("%s_%d" % [id, variant % VARIANTS])
		if scanned != null:
			return scanned
	if not _meshes.has(id):
		var list: Array[ArrayMesh] = []
		for v in VARIANTS:
			var rng := RandomNumberGenerator.new()
			rng.seed = 7001 + v * 97 + id.hash()
			var part := ProcMesh.new_part()
			match id:
				"cactus_saguaro":
					_saguaro(part, rng, v)
				"cactus_barrel":
					_barrel(part, rng)
				"cactus_pear":
					_pear(part, rng)
				"palm_coconut":
					_palm(part, rng, v)
			list.append(ProcMesh.to_mesh(part))
		_meshes[id] = list
	return (_meshes[id] as Array)[variant % VARIANTS]


## Height of a saguaro variant at scale 1 (for its obstacles).
static func saguaro_height(variant: int) -> float:
	return 6.0 + 1.6 * variant


## Height in metres of `id` at variant `variant`, before any scale: the
## tallest the plant stands, so the shadow rule can judge how far its
## shadow reaches (DesignedTerrain.object_casts_sun_shadow). Barrels are
## at most 0.85 m and a prickly pear clump about 1.2 m.
static func height_of(id: String, variant: int) -> float:
	match id:
		"cactus_saguaro":
			return saguaro_height(variant)
		"palm_coconut":
			return palm_height(variant)
		"cactus_barrel":
			return 0.85
		"cactus_pear":
			return 1.2
	return 0.0


static func _saguaro(part: Dictionary, rng: RandomNumberGenerator, v: int) -> void:
	var height := saguaro_height(v)
	var radius := 0.2 + 0.015 * v
	var ribs := 16
	# The trunk: a slight lean and sway, rounded at the top.
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	var cols := PackedColorArray()
	var lean := Vector3(rng.randf_range(-0.04, 0.04), 1.0, rng.randf_range(-0.04, 0.04)).normalized()
	var n := 18
	for k in n + 1:
		var t := float(k) / n
		path.append(lean * (t * height - 0.3) + Vector3(sin(t * 3.0) * 0.06, 0.0, 0.0))
		radii.append(radius * (1.0 - pow(t, 8.0) * 0.75) * (1.04 - 0.04 * t))
		cols.append(STEM_OLD.lerp(STEM, smoothstep(0.0, 0.15, t)))
	ProcMesh.add_tube(part, path, radii, ribs * 3, ribs, 0.14, cols)
	# Arms: none on the youngest, up to four, turning up after a short
	# reach out.
	var arms := v
	for a in arms:
		var around := TAU * (float(a) / maxf(1, arms)) + rng.randf_range(-0.6, 0.6)
		var dir := Vector3(cos(around), 0.0, sin(around))
		var at := rng.randf_range(0.35, 0.6) * height
		var reach := rng.randf_range(0.7, 1.2)
		var rise := rng.randf_range(1.2, 0.55 * height - at * 0.4)
		var arm := PackedVector3Array()
		var ar := PackedFloat32Array()
		var ac := PackedColorArray()
		var start := lean * at
		var m := 12
		for k in m + 1:
			var t := float(k) / m
			# Out and up: a quarter circle out, then straight up.
			var bend := minf(t * 2.2, 1.0)
			var out := reach * sin(bend * PI * 0.5)
			var up := reach * (1.0 - cos(bend * PI * 0.5)) + maxf(t * 2.2 - 1.0, 0.0) / 1.2 * rise
			arm.append(start + dir * (out + radius * 0.3) + Vector3.UP * up)
			ar.append(radius * 0.78 * (1.0 - pow(t, 7.0) * 0.7))
			ac.append(STEM)
		ProcMesh.add_tube(part, arm, ar, ribs * 3, ribs, 0.14, ac)


static func _barrel(part: Dictionary, rng: RandomNumberGenerator) -> void:
	var r := rng.randf_range(0.28, 0.36)
	var h := rng.randf_range(0.55, 0.85)
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	var cols := PackedColorArray()
	var n := 10
	for k in n + 1:
		var t := float(k) / n
		path.append(Vector3(0.0, t * h - 0.1, 0.0))
		radii.append(r * sqrt(maxf(0.0, 1.0 - pow(t * 1.1 - 0.1, 2.0) * 0.75)) * (1.0 - pow(t, 6.0) * 0.6))
		cols.append(BARREL.lerp(BARREL_CROWN, smoothstep(0.82, 1.0, t)))
	ProcMesh.add_tube(part, path, radii, 40, 20, 0.12, cols)


static func _pear(part: Dictionary, rng: RandomNumberGenerator) -> void:
	# Pads grow from the edges of older pads, each turned and tilted.
	var pads: Array[Transform3D] = []
	var first := rng.randi_range(2, 3)
	for i in first:
		var yaw := rng.randf() * TAU
		var tilt := rng.randf_range(-0.35, 0.35)
		pads.append(Transform3D(Basis.from_euler(Vector3(0.0, yaw, tilt)), Vector3(rng.randf_range(-0.2, 0.2), 0.12, rng.randf_range(-0.2, 0.2))))
	var count := rng.randi_range(6, 11)
	var k := 0
	while pads.size() < count and k < 40:
		k += 1
		var parent := pads[rng.randi() % pads.size()]
		# From the top edge of the parent pad.
		var edge := parent * Vector3(rng.randf_range(-0.05, 0.05), 0.1, 0.0)
		if edge.y > 1.1:
			continue
		var b := parent.basis * Basis.from_euler(Vector3(0.0, rng.randf_range(-1.2, 1.2), rng.randf_range(-0.5, 0.5)))
		pads.append(Transform3D(b, edge + b.y * 0.1))
	var purple := rng.randf() < 0.3
	for t in pads:
		var rings: Array[PackedVector3Array] = []
		var cols := PackedColorArray()
		var n := 6
		for j in n + 1:
			var phi := lerpf(-PI * 0.5, PI * 0.5, float(j) / n)
			var ring := PackedVector3Array()
			for i in 12:
				var a := TAU * i / 12.0
				# An oval pad 25 x 18 cm, 4 cm thick at the middle.
				var p := Vector3(cos(phi) * cos(a) * 0.09, sin(phi) * 0.125, cos(phi) * sin(a) * 0.025)
				ring.append(t * p)
			rings.append(ring)
			cols.append(PAD.lerp(PAD_PURPLE, 0.6 if purple else 0.0).lerp(PAD_PURPLE, 0.3 * (1.0 - absf(sin(phi)))))
		ProcMesh.add_rings(part, rings, cols, true)


## Height of a palm variant's crown at scale 1 (for its obstacles).
static func palm_height(variant: int) -> float:
	return 8.5 + 1.8 * variant


static func _palm(part: Dictionary, rng: RandomNumberGenerator, v: int) -> void:
	var height := palm_height(v)
	# The trunk leans and curves back up toward the top, as coconut palms
	# grow toward the light (and the sea).
	var lean_dir := Vector3(cos(rng.randf() * TAU), 0.0, sin(rng.randf() * TAU))
	var lean := rng.randf_range(0.12, 0.32)
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	var cols := PackedColorArray()
	var n := 24
	for k in n + 1:
		var t := float(k) / n
		var side := lean * height * (t - 0.55 * t * t)
		path.append(Vector3.UP * (t * height - 0.3) + lean_dir * side)
		# Wider at the bole, then nearly even.
		radii.append(0.15 + 0.12 * pow(1.0 - t, 6.0))
		# Leaf-scar rings every few dozen centimetres.
		var ring := 0.5 + 0.5 * sin(t * height * 14.0)
		cols.append(PALM_TRUNK.lerp(PALM_TRUNK_DARK, 0.35 * ring + 0.4 * pow(1.0 - t, 8.0)))
	ProcMesh.add_tube(part, path, radii, 14, 0, 0.0, cols)
	var top := path[n]
	var up := (path[n] - path[n - 2]).normalized()
	# The crown: fronds all round, the upper ones rising, the lower ones
	# hanging and yellower; each a long arching midrib with leaflets out
	# to both sides in a shallow V.
	var fronds := 14 + v * 2
	for f in fronds:
		var around := TAU * f / fronds + rng.randf_range(-0.2, 0.2)
		var dir := Vector3(cos(around), 0.0, sin(around))
		var low := float(f % 3) / 2.0  # 0 upper, 1 lower
		var length := rng.randf_range(3.8, 5.0)
		var rise := lerpf(0.55, -0.15, low) + rng.randf_range(-0.1, 0.1)
		var col := FROND.lerp(FROND_OLD, low * low * rng.randf_range(0.2, 0.9))
		var side := dir.cross(Vector3.UP).normalized()
		var rings: Array[PackedVector3Array] = []
		var rc := PackedColorArray()
		var m := 10
		for k in m + 1:
			var t := float(k) / m
			var c := top + up * 0.2 + dir * (length * t) + Vector3.UP * (length * (rise * t - 0.55 * t * t))
			var w := 0.55 * sin(PI * minf(t * 1.15, 1.0)) + 0.02
			var droop := Vector3.UP * (-0.35 * w)
			rings.append(PackedVector3Array([c + side * w + droop, c + Vector3.UP * 0.025, c - side * w + droop, c - Vector3.UP * 0.025]))
			rc.append(col)
		ProcMesh.add_rings(part, rings, rc, false)


## What the ball can hit for cactus `o` standing on ground height `y`: a
## saguaro's trunk is solid and its arms catch like a canopy; the small
## cacti slow the ball like a bush.
static func add_obstacles(field: ObstacleField, o: PlacedObject, y: float) -> void:
	var x := o.position.x
	var z := o.position.z
	var s := o.scale
	match o.id:
		"cactus_saguaro":
			var h := saguaro_height(variant_of(o)) * s
			field.add_cylinder(x, z, 0.22 * s, y - 0.5, y + h, ObstacleField.Kind.SOLID)
			if variant_of(o) > 0:
				field.add_cylinder(x, z, 0.9 * s, y + h * 0.35, y + h * 0.8, ObstacleField.Kind.CANOPY)
		"cactus_barrel":
			field.add_cylinder(x, z, 0.35 * s, y, y + 0.8 * s, ObstacleField.Kind.CANOPY)
		"cactus_pear":
			field.add_cylinder(x, z, 0.6 * s, y, y + 1.0 * s, ObstacleField.Kind.CANOPY)
		"palm_coconut":
			# The trunk is solid; the crown catches like a canopy. (The lean
			# is small next to the crown's reach, so both stand on the base.)
			var h := palm_height(variant_of(o)) * s
			field.add_cylinder(x, z, 0.2 * s, y - 0.5, y + h, ObstacleField.Kind.SOLID)
			field.add_cylinder(x, z, 3.5 * s, y + h - 1.5 * s, y + h + 1.2 * s, ObstacleField.Kind.CANOPY)
