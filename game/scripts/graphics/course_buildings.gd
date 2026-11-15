class_name CourseBuildings
extends MeshInstance3D
## A course's buildings (DesignedCourse.buildings: the clubhouse, houses
## along the boundary, barns), from their mapped outlines and the lidar's
## heights: walls up to the eaves and flat, gabled or hipped roofs, in the
## brick, render and roof-tile colours of their region (building.gdshader
## draws the courses of brick, windows and tiles). One mesh for the
## course; solid to the ball (add_obstacles).

const SHADER := preload("res://shaders/building.gdshader")
const OVERHANG := 0.3  ## metres the roof reaches past the walls
const FOOTING := 0.6  ## metres the walls go below the lowest ground
## Buildings drawn round a hole: within this of the line from tee to pin.
const REACH := 900.0

## Wall colours: London stock and red brick, cream and white render.
const WALLS := [
	Color(0.47, 0.29, 0.21), Color(0.55, 0.33, 0.24), Color(0.62, 0.52, 0.38),
	Color(0.66, 0.57, 0.44), Color(0.72, 0.70, 0.65), Color(0.68, 0.64, 0.56),
]
## Roof colours: slate, clay tile, weathered concrete tile.
const ROOF_COLOURS := [Color(0.20, 0.21, 0.23), Color(0.40, 0.21, 0.15), Color(0.33, 0.25, 0.21), Color(0.28, 0.27, 0.27)]
## UV2.x per kind: 0 no windows, 1 house windows, 2 big windows (clubhouse, blocks).
const WINDOWS := {"house": 1.0, "bungalow": 1.0, "clubhouse": 2.0, "block": 2.0, "other": 1.0, "shed": 0.0, "barn": 0.0}

static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	return _material


## The buildings round `hole`'s line of play, or null when there are none.
static func build(hole: HoleData) -> CourseBuildings:
	var dt := hole.terrain as DesignedTerrain
	if dt == null or dt.course == null or dt.course.buildings.is_empty():
		return null
	var a := Vector2(hole.tee.x, hole.tee.z)
	var b := Vector2(hole.pin.x, hole.pin.z)
	var near: Array[CourseBuilding] = []
	for bl in dt.course.buildings:
		if Geometry2D.get_closest_point_to_segment(bl.points[0], a, b).distance_to(bl.points[0]) < REACH:
			near.append(bl)
	return from_buildings(near, hole.terrain)


static func from_buildings(list: Array[CourseBuilding], terrain: CourseTerrain) -> CourseBuildings:
	if list.is_empty():
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in list:
		add_building(st, b, terrain)
	st.generate_normals()
	var node := CourseBuildings.new()
	node.name = "CourseBuildings"
	node.mesh = st.commit()
	node.material_override = material()
	return node


## The lowest ground under the outline: the walls stand on it.
static func base_height(b: CourseBuilding, terrain: CourseTerrain) -> float:
	var lo := INF
	for p in b.points:
		lo = minf(lo, terrain.height_at(p.x, p.y))
	var c := b.bounds().get_center()
	return minf(lo, terrain.height_at(c.x, c.y))


static func _hash(b: CourseBuilding) -> int:
	var c := b.bounds().get_center()
	return absi(int(c.x * 7.31) * 92821 + int(c.y * 3.17) * 68917)


## Each building's colours: neighbours on a street share them more often
## than not, as estates are built in one brick.
static func colours(b: CourseBuilding) -> Array[Color]:
	var h := _hash(b)
	var cell := absi(int(floor(b.points[0].x / 80.0)) * 31 + int(floor(b.points[0].y / 80.0)) * 17)
	var wall: Color = WALLS[(cell if h % 3 != 0 else h) % WALLS.size()]
	var roof: Color = ROOF_COLOURS[(cell + (h % 2 if h % 4 == 0 else 0)) % ROOF_COLOURS.size()]
	if b.kind == "barn":
		wall = Color(0.30, 0.24, 0.19)  # weatherboarding
		roof = Color(0.26, 0.27, 0.27)
	elif b.kind == "shed":
		wall = Color(0.42, 0.34, 0.26) if h % 2 == 0 else wall
	var shade := 0.92 + float(h % 17) / 100.0
	return [wall * shade, roof * (0.94 + float(h % 11) / 100.0)]


static func add_building(st: SurfaceTool, b: CourseBuilding, terrain: CourseTerrain) -> void:
	var y0 := base_height(b, terrain)
	var cols := colours(b)
	var win: float = WINDOWS.get(b.kind, 1.0)
	var pts := b.points
	if b.area() < 0.0:
		pts = pts.duplicate()
		pts.reverse()
	# Walls, counter-clockwise seen from above so they face outwards; each
	# from below the ground up to the eaves (or the top of a flat roof).
	var top := y0 + b.eave
	var along := 0.0
	for i in pts.size():
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		var len := p.distance_to(q)
		if len < 0.05:
			continue
		var gp := terrain.height_at(p.x, p.y) - FOOTING
		var gq := terrain.height_at(q.x, q.y) - FOOTING
		_quad(st, cols[0], Vector3(q.x, gq, q.y), Vector3(p.x, gp, p.y), Vector3(p.x, top, p.y), Vector3(q.x, top, q.y),
			Vector2(along + len, gq - y0), Vector2(along, gp - y0), Vector2(along, b.eave), Vector2(along + len, b.eave), Vector2(win, 0.0))
		along += len
	match b.roof:
		"gabled", "hipped":
			_pitched(st, b, y0, cols)
		_:
			_flat(st, pts, top, cols[1])


## A flat roof, with a low parapet's worth of edge darkening in the shader.
static func _flat(st: SurfaceTool, pts: PackedVector2Array, y: float, colour: Color) -> void:
	var tris := Geometry2D.triangulate_polygon(pts)
	for k in range(0, tris.size() - 2, 3):
		for m in [0, 2, 1]:
			var p := pts[tris[k + m]]
			st.set_color(colour)
			st.set_uv(p)
			st.set_uv2(Vector2(0.0, 2.0))
			st.add_vertex(Vector3(p.x, y, p.y))


## A gabled or hipped roof over the outline's oriented box.
static func _pitched(st: SurfaceTool, b: CourseBuilding, y0: float, cols: Array[Color]) -> void:
	var box := b.oriented_box()
	var c: Vector2 = box["centre"]
	var u: Vector2 = box["axis"]
	var v := Vector2(-u.y, u.x)
	var half: Vector2 = box["half"]
	var eave := y0 + b.eave
	var ridge := y0 + b.ridge
	var rise := b.ridge - b.eave
	var L := half.x + OVERHANG
	var W := half.y + OVERHANG
	# The eaves drop a little with the overhang, keeping the pitch.
	var drop := rise * OVERHANG / maxf(half.y, 0.1)
	var e := eave - drop
	var at := func(a: float, s: float, y: float) -> Vector3:
		var p := c + u * a + v * s
		return Vector3(p.x, y, p.y)
	var slope := sqrt(W * W + (rise + drop) * (rise + drop))
	if b.roof == "gabled":
		# Two slopes the whole length, and the gable ends filled in.
		_quad(st, cols[1], at.call(-L, -W, e), at.call(L, -W, e), at.call(L, 0.0, ridge), at.call(-L, 0.0, ridge),
			Vector2(0, 0), Vector2(2 * L, 0), Vector2(2 * L, slope), Vector2(0, slope), Vector2(0, 1))
		_quad(st, cols[1], at.call(L, W, e), at.call(-L, W, e), at.call(-L, 0.0, ridge), at.call(L, 0.0, ridge),
			Vector2(0, 0), Vector2(2 * L, 0), Vector2(2 * L, slope), Vector2(0, slope), Vector2(0, 1))
		for s in [-1.0, 1.0]:
			var a: float = s * half.x
			var p1: Vector3 = at.call(a, -half.y * s, eave)
			var p2: Vector3 = at.call(a, half.y * s, eave)
			var p3: Vector3 = at.call(a, 0.0, ridge)
			_tri(st, cols[0], p1, p2, p3, Vector2(0, b.eave), Vector2(2 * half.y, b.eave), Vector2(half.y, b.ridge), Vector2(0.0, 0.0))
		return
	# Hipped: a ridge along the middle, short of each end by the half width
	# (a point when the box is square).
	var r := maxf(L - W, 0.0)
	_quad(st, cols[1], at.call(-L, -W, e), at.call(L, -W, e), at.call(r, 0.0, ridge), at.call(-r, 0.0, ridge),
		Vector2(0, 0), Vector2(2 * L, 0), Vector2(L + r, slope), Vector2(L - r, slope), Vector2(0, 1))
	_quad(st, cols[1], at.call(L, W, e), at.call(-L, W, e), at.call(-r, 0.0, ridge), at.call(r, 0.0, ridge),
		Vector2(0, 0), Vector2(2 * L, 0), Vector2(L + r, slope), Vector2(L - r, slope), Vector2(0, 1))
	_tri(st, cols[1], at.call(L, -W, e), at.call(L, W, e), at.call(r, 0.0, ridge), Vector2(0, 0), Vector2(2 * W, 0), Vector2(W, slope), Vector2(0, 1))
	_tri(st, cols[1], at.call(-L, W, e), at.call(-L, -W, e), at.call(-r, 0.0, ridge), Vector2(0, 0), Vector2(2 * W, 0), Vector2(W, slope), Vector2(0, 1))


## A quad a, b, c, d (counter-clockwise seen from outside) as two triangles.
static func _quad(st: SurfaceTool, colour: Color, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2, info: Vector2) -> void:
	_tri(st, colour, a, b, c, ua, ub, uc, info)
	_tri(st, colour, a, c, d, ua, uc, ud, info)


## Godot's front faces wind clockwise, so the points go in reversed.
static func _tri(st: SurfaceTool, colour: Color, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, info: Vector2) -> void:
	for k in [[a, ua], [c, uc], [b, ub]]:
		st.set_color(colour)
		st.set_uv(k[1])
		st.set_uv2(info)
		st.add_vertex(k[0])


## Each building as a solid box round its walls and roof.
static func add_obstacles(field: ObstacleField, b: CourseBuilding, terrain: CourseTerrain) -> void:
	var box := b.oriented_box()
	var c: Vector2 = box["centre"]
	var u: Vector2 = box["axis"]
	var half: Vector2 = box["half"]
	var y0 := base_height(b, terrain)
	var top := y0 + (b.ridge + b.eave) * 0.5 if b.roof != "flat" else y0 + b.eave
	var basis := Basis(Vector3(u.x, 0, u.y), Vector3.UP, Vector3(-u.y, 0, u.x))
	field.add_box(Vector3(c.x, (y0 - FOOTING + top) * 0.5, c.y), basis, Vector3(half.x, (top - y0 + FOOTING) * 0.5, half.y), ObstacleField.Kind.SOLID)
