class_name ProcMesh
extends RefCounted
## Building blocks for the procedural rock formations (RockFormations) and
## desert plants (DesertPlants): a mesh from rings of points (a tower, a
## swept tube), with smooth normals that wrap round each ring so there is
## no seam, wound the way Godot draws front faces.
##
## A Part is {verts, normals, colors, indices}; parts are appended into one
## and turned into an ArrayMesh at the end.


static func new_part() -> Dictionary:
	return {"verts": PackedVector3Array(), "normals": PackedVector3Array(), "colors": PackedColorArray(), "indices": PackedInt32Array()}


## Appends a surface through `rings` (each the same number of points, going
## anticlockwise seen from the end the rings advance towards, e.g. round a
## tower seen from above as the rings go up) to `part`, outward-facing.
## `colors` is a vertex colour per ring, or per point (rings x points), or
## empty for white. With `cap_end`
## the last ring is closed by a fan to its middle.
static func add_rings(part: Dictionary, rings: Array[PackedVector3Array], colors := PackedColorArray(), cap_end := true) -> void:
	var nr := rings.size()
	if nr < 2:
		return
	var ns := rings[0].size()
	var base: int = (part.verts as PackedVector3Array).size()
	var verts: PackedVector3Array = part.verts
	var normals: PackedVector3Array = part.normals
	var cols: PackedColorArray = part.colors
	var indices: PackedInt32Array = part.indices
	for j in nr:
		var ring := rings[j]
		var prev := rings[maxi(j - 1, 0)]
		var next := rings[mini(j + 1, nr - 1)]
		for i in ns:
			var p := ring[i]
			var along := next[i] - prev[i]
			var around := ring[(i + 1) % ns] - ring[(i - 1 + ns) % ns]
			var n := along.cross(around)
			if n.length_squared() < 1e-12:
				n = (p - _centre(ring)).normalized()
			verts.append(p)
			normals.append(n.normalized())
			if colors.size() == nr * ns:
				cols.append(colors[j * ns + i])
			else:
				cols.append(colors[j] if j < colors.size() else Color.WHITE)
	for j in nr - 1:
		for i in ns:
			var a := base + j * ns + i
			var b := base + j * ns + (i + 1) % ns
			var c := base + (j + 1) * ns + i
			var d := base + (j + 1) * ns + (i + 1) % ns
			indices.append_array([a, b, c, b, d, c])
	if cap_end:
		var last := rings[nr - 1]
		var mid := _centre(last)
		var axis := (mid - _centre(rings[nr - 2])).normalized()
		var k := verts.size()
		verts.append(mid + axis * 0.05 * _radius(last, mid))
		normals.append(axis)
		cols.append(colors[(nr - 1) * ns] if colors.size() == nr * ns else (colors[nr - 1] if nr - 1 < colors.size() else Color.WHITE))
		var first := base + (nr - 1) * ns
		for i in ns:
			indices.append_array([k, first + i, first + (i + 1) % ns])
	part.verts = verts
	part.normals = normals
	part.colors = cols
	part.indices = indices


## Rings swept along `path`: at each point a circle of `sides` points of
## radius radii[k] square to the path, ribbed (`ribs` ridges `rib_depth` of
## the radius deep) like a cactus stem; then closed at the end.
static func add_tube(part: Dictionary, path: PackedVector3Array, radii: PackedFloat32Array, sides: int, ribs := 0, rib_depth := 0.0, colors := PackedColorArray()) -> void:
	var rings: Array[PackedVector3Array] = []
	var shaded := PackedColorArray()
	var n := path.size()
	var ref := Vector3.RIGHT
	for k in n:
		var t := (path[mini(k + 1, n - 1)] - path[maxi(k - 1, 0)]).normalized()
		# A frame that turns with the path (no sudden flips).
		var u := (ref - t * ref.dot(t))
		if u.length_squared() < 1e-6:
			u = Vector3.FORWARD - t * Vector3.FORWARD.dot(t)
		u = u.normalized()
		ref = u
		var v := u.cross(t)
		var ring := PackedVector3Array()
		for i in sides:
			var a := TAU * i / sides
			var r := radii[k]
			var groove := 0.0
			if ribs > 0:
				# Sharp ridges, rounded grooves between them.
				groove = pow(0.5 - 0.5 * cos(a * ribs), 0.6)
				r *= 1.0 - rib_depth * groove
			# Anticlockwise seen from ahead along the path.
			ring.append(path[k] + (u * cos(a) + v * sin(a)) * r)
			if ribs > 0:
				# The grooves are in their own shade.
				var base_col: Color = colors[k] if k < colors.size() else Color.WHITE
				shaded.append(base_col.darkened(0.32 * groove))
		rings.append(ring)
	add_rings(part, rings, shaded if ribs > 0 else colors, true)


static func to_mesh(part: Dictionary) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = part.verts
	arrays[Mesh.ARRAY_NORMAL] = part.normals
	arrays[Mesh.ARRAY_COLOR] = part.colors
	arrays[Mesh.ARRAY_INDEX] = part.indices
	var mesh := ArrayMesh.new()
	if (part.indices as PackedInt32Array).is_empty():
		return mesh
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Smooth value noise in 2D, for outlines (0 to 1), from a seed.
static func noise(x: float, y: float, seed_value: int) -> float:
	var ix := floori(x)
	var iy := floori(y)
	var fx := x - ix
	var fy := y - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := _hash(ix, iy, seed_value)
	var b := _hash(ix + 1, iy, seed_value)
	var c := _hash(ix, iy + 1, seed_value)
	var d := _hash(ix + 1, iy + 1, seed_value)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


## Noise round a ring: `angle` in radians wraps without a seam (`period`
## noise cells round).
static func ring_noise(angle: float, y: float, period: int, seed_value: int) -> float:
	var x := angle / TAU * period
	var a := noise(x, y, seed_value)
	var b := noise(x - period, y, seed_value)
	var w := x / period
	return lerpf(a, b, w)


static func _hash(x: int, y: int, s: int) -> float:
	var h := (x * 374761393 + y * 668265263 + s * 2147483647) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


static func _centre(ring: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for p in ring:
		c += p
	return c / maxf(1.0, ring.size())


static func _radius(ring: PackedVector3Array, c: Vector3) -> float:
	var r := 0.0
	for p in ring:
		r += p.distance_to(c)
	return r / maxf(1.0, ring.size())
