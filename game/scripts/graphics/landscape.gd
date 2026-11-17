class_name Landscape
extends RefCounted
## The real land round a designed course, drawn out to the horizon: the
## valley walls, mesas and mountains a course built on dramatic ground is
## seen against (docs/epic-courses.md). The course file carries it as a
## coarse height grid (DesignedCourse.landscape, LAND_CELL metres between
## samples, kilometres each way) on the same datum as the course's own
## heights, so the two meet. Courses that have one draw it in place of
## FarScenery's rings and DesignedTerrain's apron.
##
## One lit mesh in chunks (so the GPU skips the ones behind the camera),
## coloured by landscape.gdshader from slope and height for the course's
## Biome. The chunks wholly inside the course aren't built; where a chunk
## reaches under the course's edge its ground is let down below the
## course's, so the course's own mesh covers it. Visual only: everything
## beyond the course area is out of bounds.

## The round camera's far plane on a course with a landscape (main.gd);
## the land reaches about 8 km each way from the course's middle.
const CAMERA_FAR := 12000.0
## Grid cells per chunk side.
const CHUNK := 50
## How far under the course's ground the land is let down inside it.
const SINK := 0.8
## Quality below which every other sample is used (a quarter of the
## triangles), for phones, tablets and the web.
const FULL_FROM := GraphicsSettings.Quality.HIGH
const SHADER := preload("res://shaders/landscape.gdshader")
const SEA_SHADER := preload("res://shaders/sea.gdshader")
## How much of the scene's fog each biome's air carries far off: desert air
## is very clear, so walls 10 km off still stand out.
const AIR_SHARE := {Biome.DESERT: 0.2, Biome.SNOW: 0.25, Biome.ALPINE: 0.3, Biome.TROPICAL: 0.4}

## The graphics quality (GraphicsSettings.Quality), set by main.gd.
static var detail := GraphicsSettings.Quality.HIGH
static var _materials: Array[ShaderMaterial] = []
static var _cache := {}  ## [course instance id, step] -> Array[ArrayMesh]
static var _haze := [Color(0.7, 0.78, 0.86), 0.0005, 1.0]  ## the last set_haze()


## The land round `terrain`'s course, or null when it has none.
static func build(terrain: DesignedTerrain) -> Node3D:
	var land := terrain.course.landscape
	if land.is_empty():
		return null
	var step := 1 if detail >= FULL_FROM else 2
	var key := [terrain.course.get_instance_id(), step]
	if not _cache.has(key):
		_cache.clear()
		_cache[key] = _meshes(terrain, step)
	var root := Node3D.new()
	root.name = "Landscape"
	var mat := material_for(terrain.course.biome)
	for m: ArrayMesh in _cache[key]:
		var inst := MeshInstance3D.new()
		inst.mesh = m
		inst.material_override = mat
		# Its shadows would only reach the course from cliffs a few hundred
		# metres off, past the sun's shadow distance.
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inst.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		root.add_child(inst)
	var sea := sea_level(terrain.course)
	if not is_nan(sea):
		# The sea over the land below sea level (the elevation tiles carry
		# the sea floor), out to the land's edge.
		var plane := PlaneMesh.new()
		# Out past the far plane, so the horizon is the sea's.
		plane.size = Vector2.ONE * CAMERA_FAR * 3.0
		plane.subdivide_width = 48
		plane.subdivide_depth = 48
		var water := MeshInstance3D.new()
		water.name = "Sea"
		water.mesh = plane
		water.material_override = sea_material()
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var o: Vector2 = land.origin
		var mid := o + Vector2(land.cols, land.rows) * float(land.cell) * 0.5
		water.position = Vector3(mid.x, sea, mid.y)
		root.add_child(water)
	return root


## The height of the sea on `course` (course metres), or NAN when its biome
## has no sea. A course built from the map is measured from its own low
## point (source.base_height metres above the sea); a built-in course
## from its datum, where the biome's figure applies.
static func sea_level(course: DesignedCourse) -> float:
	var l := Biome.land(course.biome)
	if float(l.sea) < -9000.0:
		return NAN
	if course.source.has("base_height"):
		return float(l.sea) - float(course.source["base_height"])
	return float(l.sea)


## The shared material for `biome`'s land.
static func material_for(biome: String) -> ShaderMaterial:
	for m in _materials:
		if m.get_meta("biome", "") == biome:
			return m
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_meta("biome", biome)
	var l := Biome.land(biome)
	m.set_shader_parameter("low_color", l.low)
	m.set_shader_parameter("high_color", l.high)
	m.set_shader_parameter("rock_color", l.rock)
	m.set_shader_parameter("rock2_color", l.rock2)
	m.set_shader_parameter("plant_color", l.plants)
	m.set_shader_parameter("cover", l.cover)
	m.set_shader_parameter("snow_from", l.snow_from)
	m.set_shader_parameter("air_share", float(AIR_SHARE.get(biome, FarScenery.AIR_PER_FOG)))
	_materials.append(m)
	set_haze(_haze[0], _haze[1], _haze[2])
	return m


## The open sea's material (sea.gdshader), hazed like the land.
static func sea_material() -> ShaderMaterial:
	for m in _materials:
		if m.get_meta("biome", "") == "_sea":
			return m
	var m := ShaderMaterial.new()
	m.shader = SEA_SHADER
	m.set_meta("biome", "_sea")
	# Sea air is clear over open water, and the haze is the course's land
	# haze (grey): at the land's share the far sea drew as a grey wall.
	m.set_shader_parameter("air_share", 0.12)
	_materials.append(m)
	set_haze(_haze[0], _haze[1], _haze[2])
	return m


## The haze every landscape fades into (Scenery, as FarScenery.set_haze).
static func set_haze(color: Color, fog_density: float, brightness := 1.0) -> void:
	_haze = [color, fog_density, brightness]
	for m in _materials:
		m.set_shader_parameter("haze_color", color)
		m.set_shader_parameter("fog_density", fog_density)
		m.set_shader_parameter("brightness", brightness)


@warning_ignore("integer_division")
static func _meshes(terrain: DesignedTerrain, step: int) -> Array[ArrayMesh]:
	var land := terrain.course.landscape
	var cols: int = land.cols
	var rows: int = land.rows
	var cell: float = land.cell
	var o: Vector2 = land.origin
	var area := terrain.course.area
	# Heights and normals once over the (stepped) grid.
	var nx := (cols - 1) / step + 1
	var nz := (rows - 1) / step + 1
	var heights: PackedFloat32Array = land.heights
	var h := PackedFloat32Array()
	h.resize(nx * nz)
	for b in nz:
		for a in nx:
			var p := o + Vector2(a * step, b * step) * cell
			# Under the course, let down below its own ground.
			if area.has_point(p):
				h[b * nx + a] = terrain.height_at(p.x, p.y) - SINK
			else:
				h[b * nx + a] = heights[b * step * cols + a * step]
	var d := cell * step
	var out: Array[ArrayMesh] = []
	var chunk := maxi(8, CHUNK / step)
	for cb in range(0, nz - 1, chunk):
		for ca in range(0, nx - 1, chunk):
			var a1 := mini(ca + chunk, nx - 1)
			var b1 := mini(cb + chunk, nz - 1)
			# A chunk wholly inside the course (with a cell to spare) is
			# never seen.
			var lo := o + Vector2(ca, cb) * d
			var hi := o + Vector2(a1, b1) * d
			if area.grow(-d).encloses(Rect2(lo, hi - lo)):
				continue
			var verts := PackedVector3Array()
			var normals := PackedVector3Array()
			var w := a1 - ca + 1
			for b in range(cb, b1 + 1):
				for a in range(ca, a1 + 1):
					var y := h[b * nx + a]
					verts.append(Vector3(o.x + a * d, y, o.y + b * d))
					var hl := h[b * nx + maxi(a - 1, 0)]
					var hr := h[b * nx + mini(a + 1, nx - 1)]
					var hd := h[maxi(b - 1, 0) * nx + a]
					var hu := h[mini(b + 1, nz - 1) * nx + a]
					normals.append(Vector3(hl - hr, 2.0 * d, hd - hu).normalized())
			var indices := PackedInt32Array()
			for b in b1 - cb:
				for a in a1 - ca:
					# Cells wholly inside the course are hidden under it.
					var c0 := o + Vector2(ca + a, cb + b) * d
					if area.grow(-1.0).encloses(Rect2(c0, Vector2(d, d))):
						continue
					var k := b * w + a
					# Wound so the faces look up (DesignedTerrain._add_tri).
					indices.append_array([k, k + 1, k + w, k + 1, k + w + 1, k + w])
			if indices.is_empty():
				continue
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_INDEX] = indices
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			out.append(mesh)
	return out
