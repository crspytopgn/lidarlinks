class_name StoneWalls
extends MeshInstance3D
## The field walls of a course (DesignedCourse.walls, from OpenStreetMap's
## barrier=wall and dry_stone_wall on a course built from a map), drawn as
## dry-stone walls the way they're built in Britain and Ireland: about
## 1.2 m high, battered in from 0.7 m at the foot to 0.4 m under a row of
## coping stones set on edge (stone_wall.gdshader draws the courses of
## stone on the faces). The faces use a scanned rock from the private
## Megascans pack when it's there. Scenery only: the ball passes through.

const HEIGHT := 1.2
const BASE := 0.35  ## half the width at the foot
const TOP := 0.2  ## half the width under the coping
const STEP := 1.0  ## metres between samples along the wall
const COPING := 0.2  ## metres along the wall per coping stone
const SHADER := preload("res://shaders/stone_wall.gdshader")
## Walls drawn round a hole: within this of the line from tee to pin.
const REACH := 180.0

static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		# The weathered grey-brown upland stone of field walls, if the pack has it.
		for r: Dictionary in RockField.rocks():
			if r["kind"] == "upland" or r["kind"] == "woodland":
				var a := FreeAssets.megascans_texture(str(r["id"]) + "_albedo.jpg", "rocks/")
				var n := FreeAssets.megascans_texture(str(r["id"]) + "_normal.jpg", "rocks/", true)
				if a != null and n != null:
					_material.set_shader_parameter("rock_albedo", a)
					_material.set_shader_parameter("rock_normal", n)
					_material.set_shader_parameter("has_rock", true)
					break
	return _material


## The walls round `hole`'s line of play, or null when there are none.
static func build(hole: HoleData) -> StoneWalls:
	var dt := hole.terrain as DesignedTerrain
	if dt == null or dt.course == null or dt.course.walls.is_empty():
		return null
	var a := Vector2(hole.tee.x, hole.tee.z)
	var b := Vector2(hole.pin.x, hole.pin.z)
	var near: Array[PackedVector2Array] = []
	for w in dt.course.walls:
		for p in w:
			if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < REACH:
				near.append(w)
				break
	return from_lines(near, hole.terrain)


static func from_lines(lines: Array[PackedVector2Array], terrain: CourseTerrain) -> StoneWalls:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1789
	var any := false
	for line in lines:
		var pts := _resample(line)
		if pts.size() < 2:
			continue
		any = true
		_add_wall(st, pts, terrain, rng)
	if not any:
		return null
	st.generate_normals()
	st.generate_tangents()
	var w := StoneWalls.new()
	w.name = "StoneWalls"
	w.mesh = st.commit()
	w.material_override = material()
	w.visibility_range_end = 600.0
	return w


static func _resample(line: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(1, line.size()):
		var a := line[i - 1]
		var b := line[i]
		var n := maxi(1, ceili(a.distance_to(b) / STEP))
		for k in n:
			out.append(a.lerp(b, float(k) / n))
	if not line.is_empty():
		out.append(line[line.size() - 1])
	return out


static func _add_wall(st: SurfaceTool, pts: PackedVector2Array, t: CourseTerrain, rng: RandomNumberGenerator) -> void:
	var along := 0.0
	var prev: Array = []
	for i in pts.size():
		var p := pts[i]
		var d := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := Vector2(-d.y, d.x)
		if i > 0:
			along += pts[i - 1].distance_to(p)
		var y := t.height_at(p.x, p.y) - 0.1  # set into the ground
		var top := y + HEIGHT + 0.1
		var ring := [
			Vector3(p.x + side.x * BASE, y, p.y + side.y * BASE), Vector3(p.x + side.x * TOP, top, p.y + side.y * TOP),
			Vector3(p.x - side.x * TOP, top, p.y - side.y * TOP), Vector3(p.x - side.x * BASE, y, p.y - side.y * BASE),
			along]
		if not prev.is_empty():
			# Left face, right face and the top, between the last sample and this one.
			_quad(st, prev[0], prev[1], ring[1], ring[0], prev[4], ring[4], 0.0, HEIGHT)
			_quad(st, ring[3], ring[2], prev[2], prev[3], ring[4], prev[4], 0.0, HEIGHT)
			_quad(st, prev[1], prev[2], ring[2], ring[1], prev[4], ring[4], HEIGHT, HEIGHT + TOP * 2.0)
		prev = ring
	# Coping: stones set on edge along the top, each leaning a touch.
	var total := along
	var s := 0.0
	while s < total:
		var len := rng.randf_range(0.12, COPING * 1.4)
		var c := _at(pts, s + len * 0.5)
		var d: Vector2 = c[1]
		var side := Vector2(-d.y, d.x)
		var base_y := t.height_at(c[0].x, c[0].y) - 0.1 + HEIGHT + 0.1
		var h := rng.randf_range(0.14, 0.26)
		var lean := rng.randf_range(-0.05, 0.05)
		_box(st, Vector3(c[0].x, base_y, c[0].y), Vector3(d.x, 0, d.y), Vector3(side.x, 0, side.y), len * 0.46, TOP * 1.05, h, lean, s)
		s += len
	return


## The point `s` metres along `pts`, and the direction there.
static func _at(pts: PackedVector2Array, s: float) -> Array:
	for i in range(1, pts.size()):
		var l := pts[i - 1].distance_to(pts[i])
		if s <= l or i == pts.size() - 1:
			var d := (pts[i] - pts[i - 1]).normalized()
			return [pts[i - 1] + d * minf(s, l), d]
		s -= l
	return [pts[0], Vector2.RIGHT]


## A quad a-b-c-d, its UV metres along (u0 at a/b, u1 at c/d) and up (v0
## at a/d, v1 at b/c).
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, u0: float, u1: float, v0: float, v1: float) -> void:
	var uv := [Vector2(u0, v0), Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0)]
	var p := [a, b, c, d]
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[k])
		st.add_vertex(p[k])


static func _box(st: SurfaceTool, at: Vector3, fwd: Vector3, side: Vector3, hl: float, hw: float, h: float, lean: float, u: float) -> void:
	var up := (Vector3.UP + fwd * lean).normalized()
	var c := [at - fwd * hl - side * hw, at + fwd * hl - side * hw, at + fwd * hl + side * hw, at - fwd * hl + side * hw]
	var t := [c[0] + up * h, c[1] + up * h, c[2] + up * h, c[3] + up * h]
	var v0 := HEIGHT
	var v1 := HEIGHT + h
	_quad(st, c[1], t[1], t[0], c[0], u + hl * 2.0, u, v0, v1)  # one face
	_quad(st, c[3], t[3], t[2], c[2], u, u + hl * 2.0, v0, v1)  # the other
	_quad(st, c[0], t[0], t[3], c[3], u, u + 0.4, v0, v1)  # ends
	_quad(st, c[2], t[2], t[1], c[1], u, u + 0.4, v0, v1)
	_quad(st, t[0], t[1], t[2], t[3], u, u + hl * 2.0, v1, v1 + hw * 2.0)  # top
