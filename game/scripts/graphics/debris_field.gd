class_name DebrisField
extends Node3D
## The woodland floor under tree lines, from the private Megascans pack
## (MegascansDebris, desktop only): leaf litter under broadleaf crowns and
## a carpet of needles under conifers, draped on the ground, with scanned
## leaf piles, fallen pine branches, twigs and cones near the camera, and
## the odd fallen log and old stump, so a wood's edge looks lived in rather
## than a mown lawn running up to the trunks. Visual only: the ball never
## meets any of it. Nothing without a pack or with the Grass setting off.
##
## Built in CHUNK m squares around the camera, a couple per frame, like
## FescueField. What grows follows the Grass setting: Low has the litter,
## Medium adds logs and stumps, High the small pieces near the camera.
## Each prop type is one MultiMesh per chunk, and a course uses only a few
## of each kind (LIBRARY), so draw calls stay low.

const SHADER := preload("res://shaders/debris.gdshader")
const CHUNK := 32.0
const BUILDS_PER_FRAME := 2
## Per Grass level (Off, Low, Medium, High): how far out (m) the litter,
## the logs and stumps, and the small pieces (leaf piles, twigs, cones,
## fallen branches) are drawn. Each dissolves out over its last FADE_BAND.
const LITTER_REACH := [0.0, 70.0, 90.0, 110.0]
const LOG_REACH := [0.0, 0.0, 110.0, 140.0]
const NEAR_REACH := [0.0, 0.0, 0.0, 45.0]
const FADE_BAND := 0.15
## Crowns smaller than this (bushes) drop nothing.
const MIN_CROWN := 1.5
## Litter patches per square metre of a crown, the share of the crown's
## radius they spread over, their size against the pack's patch and how
## far above the ground they float (each patch a little higher than the
## last, so overlapping ones never flicker).
const LITTER_PER_M2 := 0.11
const LITTER_SPREAD := 0.95
const LITTER_SCALE := Vector2(0.75, 1.4)
const LITTER_LIFT := 0.03
const LITTER_STEP := 0.004
## Vertices per side of a draped litter patch.
const DRAPE := 5
## Chance a crown has a fallen log, a stump; small pieces per crown.
const LOG_SHARE := 0.16
const STUMP_SHARE := 0.11
const NEAR_PIECES := Vector2i(2, 5)
## Prop types a course uses, per kind and tree (conifer, broadleaf).
const LIBRARY := {"log": 2, "stump": 2, "leaves": 3, "twigs": 2, "pine_branches": 1, "cones": 1}
## Colour grades (DebrisField -> shaders/debris.gdshader): the scans' bright
## autumn litter toned to a course's duller summer floor.
const TONE := {
	"leaves": [Color(0.8, 0.72, 0.58), 0.6, 0.55],
	"needles": [Color(0.82, 0.7, 0.55), 0.55, 0.55],
	"props": [Color(0.9, 0.88, 0.84), 0.85, 0.7],
}
## Ground the debris may lie on: under the crown on the rough, anywhere
## round it on the deep rough and out of bounds.
const OPEN := [Surface.Type.DEEP_ROUGH, Surface.Type.OUT_OF_BOUNDS]

## How much falls, by the kind of place the course is (FreeAmbience: its
## real location when known, else its name): litter and logs against the
## numbers above, and whether mossy scans suit it. A parkland is kept tidy
## (greenkeepers clear fallen wood), a wood is left to itself, a desert's
## few trees drop little and nothing grows moss there, and nor does it in
## the warm south (FreeAmbience.is_warm).
const CLIMATE := {
	FreeAmbience.Setting.PARKLAND: {"litter": 0.85, "logs": 0.55, "moss": true},
	FreeAmbience.Setting.WOODLAND: {"litter": 1.25, "logs": 1.6, "moss": true},
	FreeAmbience.Setting.SEASIDE: {"litter": 0.7, "logs": 0.7, "moss": true},
	FreeAmbience.Setting.DESERT: {"litter": 0.3, "logs": 0.3, "moss": false},
}

var terrain: CourseTerrain
var level := 0
## This course's CLIMATE entry (see climate_for).
var climate: Dictionary = CLIMATE[FreeAmbience.Setting.PARKLAND]
var _chunks := {}  ## Vector2i -> Node3D (null for an empty chunk)
var _crowns := {}  ## Vector2i -> Array of Vector4 (x, z, radius, conifer)
var _library := {}  ## "<kind>:<conifer>" -> Array[Dictionary] of props in use
var _materials := {}  ## texture file -> ShaderMaterial


func _init() -> void:
	name = "Debris"


## True when the private pack has debris in it.
static func available() -> bool:
	var p := MegascansDebris.pack()
	return not (p["litter"] as Dictionary).is_empty() or not (p["props"] as Array).is_empty()


## The CLIMATE for a course: its kind of place from where it is in the
## world (or its name), and no moss on warm courses.
static func climate_for(course: CourseData) -> Dictionary:
	if course == null:
		return CLIMATE[FreeAmbience.Setting.PARKLAND]
	var at := FreeAmbience.location_of(course)
	var c: Dictionary = (CLIMATE[FreeAmbience.setting_for_place(course.course_name, at)] as Dictionary).duplicate()
	if FreeAmbience.is_warm(at):
		c["moss"] = false
	return c


func setup(t: CourseTerrain, grass_level: int, course: CourseData = null) -> void:
	terrain = t
	climate = climate_for(course)
	level = clampi(grass_level, 0, LITTER_REACH.size() - 1) if available() else 0
	for node in _chunks.values():
		if node != null:
			node.queue_free()
	_chunks.clear()
	_crowns = crowns_by_chunk(t.obstacles if t != null else null)
	_library = library(MegascansDebris.pack()["props"], _crowns, climate["moss"])
	for m: ShaderMaterial in _materials.values():
		_set_reach(m)


func update_around(eye: Vector3) -> void:
	if terrain == null or level == 0:
		return
	var r := reach()
	var here := Vector2(eye.x, eye.z)
	for key: Vector2i in _chunks.keys():
		if _centre(key).distance_to(here) > r + CHUNK:
			var node: Node = _chunks[key]
			if node != null:
				node.queue_free()
			_chunks.erase(key)
	var wanted: Array[Vector2i] = []
	var span := ceili(r / CHUNK)
	var at := Vector2i(floori(eye.x / CHUNK), floori(eye.z / CHUNK))
	for dz in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var key := at + Vector2i(dx, dz)
			if not _chunks.has(key) and _crowns.has(key) and _centre(key).distance_to(here) < r + CHUNK * 0.71:
				wanted.append(key)
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _centre(a).distance_squared_to(here) < _centre(b).distance_squared_to(here))
	for i in mini(BUILDS_PER_FRAME, wanted.size()):
		var key := wanted[i]
		_chunks[key] = _build_node(key)


func reach() -> float:
	return maxf(LITTER_REACH[level], maxf(LOG_REACH[level], NEAR_REACH[level]))


func chunk_count() -> int:
	return _chunks.size()


static func _centre(key: Vector2i) -> Vector2:
	return (Vector2(key) + Vector2(0.5, 0.5)) * CHUNK


## The crowns of `field` big enough to drop litter, bucketed by the chunk
## their trunk stands in: (x, z, radius, 1 for a conifer else 0).
static func crowns_by_chunk(field: ObstacleField) -> Dictionary:
	var out := {}
	if field == null:
		return out
	var crowns := field.canopies()
	var conifer := field.canopy_conifers()
	for i in crowns.size():
		var c := crowns[i]
		if c.z < MIN_CROWN:
			continue
		var key := Vector2i(floori(c.x / CHUNK), floori(c.y / CHUNK))
		if not out.has(key):
			out[key] = []
		(out[key] as Array).append(Vector4(c.x, c.y, c.z, 1.0 if i < conifer.size() and conifer[i] == 1 else 0.0))
	return out


## The prop types this course uses: up to LIBRARY[kind] of each kind for
## conifers and for broadleaf trees, picked by the course's crowns so a
## course always gets the same ones.
static func library(props: Array, crowns: Dictionary, moss := true) -> Dictionary:
	var seed_from := 0
	for key: Vector2i in crowns:
		seed_from ^= hash(key)
	var out := {}
	for kind: String in LIBRARY:
		for conifer in [false, true]:
			var list := MegascansDebris.props_for(kind, conifer, props)
			if not moss:
				var dry: Array[Dictionary] = []
				dry.assign(list.filter(func(p: Dictionary) -> bool: return not (p["title"] as String).to_lower().contains("moss")))
				list = dry
			list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return hash([a["uid"], seed_from]) < hash([b["uid"], seed_from]))
			out["%s:%s" % [kind, conifer]] = list.slice(0, LIBRARY[kind])
	return out


## Whether debris may lie at (x, z), `d` m from the trunk of a crown of
## radius `r`: on the rough only under the crown, on the deep rough and out
## of bounds anywhere near it, never on the fairway, green, tee, sand or
## water.
static func lies_at(t: CourseTerrain, x: float, z: float, d: float, r: float) -> bool:
	var s := t.surface_at(x, z)
	return OPEN.has(s) or (s == Surface.Type.ROUGH and d < r)


## Everything one chunk holds: {"litter": {kind: Array of patches
## [x, z, yaw, size, cell, lift]}, "props": {uid: Array of Transform3D},
## "uses": {uid: prop}}. Deterministic.
static func plan_chunk(t: CourseTerrain, crowns: Array, lib: Dictionary, lvl: int, litter_kinds: Dictionary, clim: Dictionary = CLIMATE[FreeAmbience.Setting.PARKLAND]) -> Dictionary:
	var litter := {}
	var props := {}
	var uses := {}
	var lift_n := 0
	for crown: Vector4 in crowns:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector2i(roundi(crown.x * 10.0), roundi(crown.y * 10.0)))
		var x0 := crown.x
		var z0 := crown.y
		var r := crown.z
		var conifer := crown.w > 0.5
		# Litter: needles under conifers, leaves under the rest, with a
		# little of the other mixed in (woods are mixed).
		var count := roundi(PI * r * r * LITTER_PER_M2 * float(clim["litter"])) + 1
		for i in count:
			var d := 0.0 if i == 0 else sqrt(rng.randf()) * r * LITTER_SPREAD
			var a := rng.randf() * TAU
			var x := x0 + cos(a) * d
			var z := z0 + sin(a) * d
			var kind := "needles" if conifer != (rng.randf() < 0.12) else "leaves"
			if not litter_kinds.has(kind):
				kind = "leaves" if kind == "needles" else "needles"
			var size := rng.randf_range(LITTER_SCALE.x, LITTER_SCALE.y) * (1.3 if i == 0 else 1.0)
			var yaw := rng.randf() * TAU
			var cell := rng.randi() % 4
			if not litter_kinds.has(kind) or not lies_at(t, x, z, d, r):
				continue
			if not litter.has(kind):
				litter[kind] = []
			(litter[kind] as Array).append([x, z, yaw, size, cell, LITTER_LIFT + LITTER_STEP * (lift_n % 8)])
			lift_n += 1
		if lvl >= 2:
			var roll := rng.randf()
			var logs: float = clim["logs"]
			if roll < LOG_SHARE * logs:
				_place(t, rng, lib, "log", conifer, x0, z0, r, Vector2(0.35, 1.0), Vector2(0.9, 1.15), props, uses, true)
			elif roll < (LOG_SHARE + STUMP_SHARE) * logs:
				_place(t, rng, lib, "stump", conifer, x0, z0, r, Vector2(0.45, 1.1), Vector2(0.8, 1.1), props, uses, false)
		if lvl >= 3:
			var pieces := roundi(rng.randi_range(NEAR_PIECES.x, NEAR_PIECES.y) * float(clim["litter"]))
			for i in pieces:
				var kind := "twigs"
				var pick := rng.randf()
				if conifer:
					kind = "cones" if pick < 0.45 else ("pine_branches" if pick < 0.6 else "twigs")
				else:
					kind = "leaves" if pick < 0.7 else "twigs"
				_place(t, rng, lib, kind, conifer, x0, z0, r, Vector2(0.1, 0.9), Vector2(0.8, 1.2), props, uses, kind != "cones")
	return {"litter": litter, "props": props, "uses": uses}


## One prop of `kind` under the crown, `span` of its radius from the trunk,
## scaled by `scale`; laid along the slope when `tilt`, else standing up.
static func _place(t: CourseTerrain, rng: RandomNumberGenerator, lib: Dictionary, kind: String, conifer: bool,
		x0: float, z0: float, r: float, span: Vector2, scale: Vector2, props: Dictionary, uses: Dictionary, tilt: bool) -> void:
	var list: Array = lib.get("%s:%s" % [kind, conifer], [])
	var d := rng.randf_range(span.x, span.y) * r
	var a := rng.randf() * TAU
	var yaw := rng.randf() * TAU
	var s := rng.randf_range(scale.x, scale.y)
	var pick := rng.randi()
	if list.is_empty():
		return
	var x := x0 + cos(a) * d
	var z := z0 + sin(a) * d
	if not lies_at(t, x, z, d, r):
		return
	var prop: Dictionary = list[pick % list.size()]
	var up := t.normal_at(x, z) if tilt else Vector3.UP
	var side := Vector3(cos(yaw), 0.0, sin(yaw))
	var fwd := side.cross(up).normalized()
	side = up.cross(fwd).normalized()
	# Sunk a touch so it sits in the turf rather than on it.
	var xf := Transform3D(Basis(side, up, fwd).scaled(Vector3.ONE * s), Vector3(x, t.height_at(x, z) - 0.03 * s, z))
	var uid: String = prop["uid"]
	if not props.has(uid):
		props[uid] = []
		uses[uid] = prop
	(props[uid] as Array).append(xf)


func _build_node(key: Vector2i) -> Node3D:
	var crowns: Array = _crowns.get(key, [])
	var pack := MegascansDebris.pack()
	var plan := plan_chunk(terrain, crowns, _library, level, pack["litter"], climate)
	var node := Node3D.new()
	for kind: String in plan["litter"]:
		var info: Dictionary = pack["litter"][kind]
		var mesh := litter_mesh(terrain, plan["litter"][kind], info["size_m"])
		var mat := _material(info["albedo"], info["normal"], true, kind)
		if mesh == null or mat == null:
			continue
		mesh.surface_set_material(0, mat)
		var inst := MeshInstance3D.new()
		inst.mesh = mesh
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inst.visibility_range_end = LITTER_REACH[level] + CHUNK * 0.71
		node.add_child(inst)
	for uid: String in plan["props"]:
		var prop: Dictionary = plan["uses"][uid]
		var mesh := MegascansDebris.mesh(prop)
		var mat := _material(prop["albedo"], prop["normal"], prop["cutout"], "props", prop["kind"])
		if mesh == null or mat == null:
			continue
		var xfs: Array = plan["props"][uid]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		inst.material_override = mat
		var big: bool = prop["kind"] == "log" or prop["kind"] == "stump"
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if big else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inst.visibility_range_end = (LOG_REACH[level] if big else NEAR_REACH[level]) + CHUNK * 0.71
		node.add_child(inst)
	if node.get_child_count() == 0:
		node.free()
		return null
	add_child(node)
	return node


## The chunk's litter patches of one kind as one mesh: each patch a
## DRAPE x DRAPE grid laid over the ground, `size_m` across before its own
## scale, its UVs on one cell of the pack's 2 x 2 atlas.
static func litter_mesh(t: CourseTerrain, patches: Array, size_m: float) -> ArrayMesh:
	if patches.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := 0
	for p: Array in patches:
		var x: float = p[0]
		var z: float = p[1]
		var yaw: float = p[2]
		var half: float = size_m * float(p[3]) * 0.5
		var cell: int = p[4]
		var lift: float = p[5]
		var u := Vector3(cos(yaw), 0.0, sin(yaw))
		var v := Vector3(-u.z, 0.0, u.x)
		var uv0 := Vector2(cell % 2, floori(cell / 2.0)) * 0.5
		for j in DRAPE:
			for i in DRAPE:
				var fu := float(i) / (DRAPE - 1)
				var fv := float(j) / (DRAPE - 1)
				var w := Vector3(x, 0.0, z) + u * (fu * 2.0 - 1.0) * half + v * (fv * 2.0 - 1.0) * half
				var n := t.normal_at(w.x, w.z)
				w.y = t.height_at(w.x, w.z) + lift
				var tan := (u - n * n.dot(u)).normalized()
				st.set_normal(n)
				st.set_tangent(Plane(tan, 1.0))
				st.set_uv(uv0 + Vector2(fu, fv) * 0.5)
				st.add_vertex(w)
		for j in DRAPE - 1:
			for i in DRAPE - 1:
				var a := base + j * DRAPE + i
				st.add_index(a)
				st.add_index(a + 1)
				st.add_index(a + DRAPE)
				st.add_index(a + 1)
				st.add_index(a + DRAPE + 1)
				st.add_index(a + DRAPE)
		base += DRAPE * DRAPE
	return st.commit()


func _material(albedo: String, normal: String, cutout: bool, tone: String, kind := "") -> ShaderMaterial:
	if _materials.has(albedo):
		return _materials[albedo]
	var tex := MegascansDebris.texture(albedo)
	var mat: ShaderMaterial = null
	if tex != null:
		mat = ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("albedo_tex", tex)
		var ntex := MegascansDebris.texture(normal)
		if ntex != null:
			mat.set_shader_parameter("normal_tex", ntex)
		mat.set_shader_parameter("cutout", cutout)
		var grade: Array = TONE[tone]
		mat.set_shader_parameter("tone", grade[0])
		mat.set_shader_parameter("saturation", grade[1])
		mat.set_shader_parameter("brightness", float(grade[2]) * (1.0 if GraphicsSettings.is_forward_plus() else 1.15))
		mat.set_meta("reach", "litter" if tone != "props" else ("log" if kind == "log" or kind == "stump" else "near"))
		_set_reach(mat)
	_materials[albedo] = mat
	return mat


func _set_reach(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	var which: String = mat.get_meta("reach", "litter")
	var r: float = LITTER_REACH[level]
	if which == "log":
		r = LOG_REACH[level]
	elif which == "near":
		r = NEAR_REACH[level]
	mat.set_shader_parameter("fade_end", r)
	mat.set_shader_parameter("fade_band", maxf(r * FADE_BAND, 1.0))
