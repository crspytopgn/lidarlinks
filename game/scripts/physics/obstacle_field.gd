class_name ObstacleField
extends RefCounted
## Things on a course the ball can hit: tree trunks, canopies, buildings and
## fences, in Godot metres. Port of libs/olcore/src/obstacles.cpp; change
## both together.

enum Kind { SOLID = 0, CANOPY = 1 }  ## SOLID bounces the ball off; CANOPY soaks up its speed

const CELL := 10.0  ## metres per side of a grid cell
const CYLINDER_FLOATS := 6  ## x, z, radius, y0, y1, kind
const BOX_FLOATS := 16  ## centre, three axes, half sizes, kind

var _cylinders := PackedFloat32Array()
## Per CANOPY cylinder, in order: 1 for a conifer's crown (its needles
## carpet the ground beneath), else 0. Scenery only (DebrisField); the
## physics never reads it.
var _conifer := PackedByteArray()
var _boxes := PackedFloat32Array()
var _origin := Vector2.ZERO
var _cols := 0
var _rows := 0
## Items of cell i are _cell_items[_cell_start[i] .. _cell_start[i + 1]); an
## item k >= 0 is a cylinder, k < 0 is box -k - 1.
var _cell_start := PackedInt32Array()
var _cell_items := PackedInt32Array()
## The top of the highest item in each cell: a segment wholly above it meets
## nothing there. Mirrors olcore's cell_top_.
var _cell_top := PackedFloat64Array()
const TOP_MARGIN := 1e-3


## An upright cylinder: centre (x, z), radius, from y0 up to y1.
func add_cylinder(x: float, z: float, radius: float, y0: float, y1: float, kind: int) -> void:
	_cylinders.append_array(PackedFloat32Array([x, z, radius, y0, y1, kind]))
	if kind == Kind.CANOPY:
		_conifer.append(0)


## Marks the crown just added as a conifer's (scenery only, see _conifer).
func mark_conifer() -> void:
	if not _conifer.is_empty():
		_conifer[_conifer.size() - 1] = 1


## A box: centre, orthonormal axes (the columns of `axes`) and the half size
## along each.
func add_box(centre: Vector3, axes: Basis, half: Vector3, kind: int) -> void:
	_boxes.append_array(PackedFloat32Array([centre.x, centre.y, centre.z, axes.x.x, axes.x.y, axes.x.z, axes.y.x, axes.y.y, axes.y.z, axes.z.x, axes.z.y, axes.z.z, half.x, half.y, half.z, kind]))


## Cylinders whose footprint meets the rect (x0, z0, x1, z1), 6 floats
## each as add_cylinder() stores them, for baking into the native sim
## (OlcoreTerrain.bake_obstacles). The native field is built from the
## merged exports of the course's fields, so a shot meets the same trees
## and walls there as in the GDScript port.
func cylinders_in(x0: float, z0: float, x1: float, z1: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for o in range(0, _cylinders.size(), CYLINDER_FLOATS):
		var r := _cylinders[o + 2]
		if _cylinders[o] + r < x0 or _cylinders[o] - r > x1:
			continue
		if _cylinders[o + 1] + r < z0 or _cylinders[o + 1] - r > z1:
			continue
		out.append_array(_cylinders.slice(o, o + CYLINDER_FLOATS))
	return out


## Boxes whose footprint meets the rect, 16 floats each as add_box()
## stores them, for baking into the native sim (see cylinders_in).
func boxes_in(x0: float, z0: float, x1: float, z1: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for o in range(0, _boxes.size(), BOX_FLOATS):
		var rx := 0.0
		var rz := 0.0
		for k in 3:
			var h := _boxes[o + 12 + k]
			rx += absf(_boxes[o + 3 + 3 * k]) * h
			rz += absf(_boxes[o + 5 + 3 * k]) * h
		if _boxes[o] + rx < x0 or _boxes[o] - rx > x1:
			continue
		if _boxes[o + 2] + rz < z0 or _boxes[o + 2] - rz > z1:
			continue
		out.append_array(_boxes.slice(o, o + BOX_FLOATS))
	return out


## The tree crowns (CANOPY cylinders) as (x, z, radius), for scenery that
## grows under trees (FescueField's understory). Read only; GDScript only,
## as nothing in the physics needs it.
func canopies() -> PackedVector3Array:
	var out := PackedVector3Array()
	for o in range(0, _cylinders.size(), CYLINDER_FLOATS):
		if int(_cylinders[o + 5]) == Kind.CANOPY:
			out.append(Vector3(_cylinders[o], _cylinders[o + 1], _cylinders[o + 2]))
	return out


## Per crown of canopies(), in the same order: whether it is a conifer's.
func canopy_conifers() -> PackedByteArray:
	return _conifer


@warning_ignore("integer_division")
func size() -> int:
	return _cylinders.size() / CYLINDER_FLOATS + _boxes.size() / BOX_FLOATS


## Builds the lookup grid. Call after adding everything.
@warning_ignore("integer_division")
func finalize() -> void:
	var extent := PackedFloat32Array()  # x0, z0, x1, z1 per item
	var ids := PackedInt32Array()
	var top := PackedFloat64Array()  # each item's highest point
	for i in _cylinders.size() / CYLINDER_FLOATS:
		var o := i * CYLINDER_FLOATS
		var r := _cylinders[o + 2]
		extent.append_array(PackedFloat32Array([_cylinders[o] - r, _cylinders[o + 1] - r, _cylinders[o] + r, _cylinders[o + 1] + r]))
		ids.append(i)
		top.append(_cylinders[o + 4])
	for i in _boxes.size() / BOX_FLOATS:
		var o := i * BOX_FLOATS
		var rx := 0.0
		var ry := 0.0
		var rz := 0.0
		for k in 3:
			var h := _boxes[o + 12 + k]
			rx += absf(_boxes[o + 3 + 3 * k]) * h
			ry += absf(_boxes[o + 4 + 3 * k]) * h
			rz += absf(_boxes[o + 5 + 3 * k]) * h
		extent.append_array(PackedFloat32Array([_boxes[o] - rx, _boxes[o + 2] - rz, _boxes[o] + rx, _boxes[o + 2] + rz]))
		ids.append(-i - 1)
		top.append(_boxes[o + 1] + ry)
	_cols = 0
	_rows = 0
	_cell_start = PackedInt32Array()
	_cell_items = PackedInt32Array()
	_cell_top = PackedFloat64Array()
	if ids.is_empty():
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in ids.size():
		lo = lo.min(Vector2(extent[4 * i], extent[4 * i + 1]))
		hi = hi.max(Vector2(extent[4 * i + 2], extent[4 * i + 3]))
	_origin = lo
	_cols = floori((hi.x - lo.x) / CELL) + 1
	_rows = floori((hi.y - lo.y) / CELL) + 1
	# Two passes: count per cell, then fill.
	var count := PackedInt32Array()
	count.resize(_cols * _rows + 1)
	count.fill(0)
	for i in ids.size():
		var r := _cell_range(extent[4 * i], extent[4 * i + 1], extent[4 * i + 2], extent[4 * i + 3])
		for row in range(r.position.y, r.end.y):
			for col in range(r.position.x, r.end.x):
				count[row * _cols + col + 1] += 1
	_cell_top.resize(_cols * _rows)
	_cell_top.fill(-INF)
	for i in ids.size():
		var r := _cell_range(extent[4 * i], extent[4 * i + 1], extent[4 * i + 2], extent[4 * i + 3])
		for row in range(r.position.y, r.end.y):
			for col in range(r.position.x, r.end.x):
				_cell_top[row * _cols + col] = maxf(_cell_top[row * _cols + col], top[i])
	for i in range(1, count.size()):
		count[i] += count[i - 1]
	_cell_start = count.duplicate()
	_cell_items.resize(count[count.size() - 1])
	for i in ids.size():
		var r := _cell_range(extent[4 * i], extent[4 * i + 1], extent[4 * i + 2], extent[4 * i + 3])
		for row in range(r.position.y, r.end.y):
			for col in range(r.position.x, r.end.x):
				var c := row * _cols + col
				_cell_items[count[c]] = ids[i]
				count[c] += 1


## Cells covering x0..x1, z0..z1 as columns position.x until end.x and rows
## position.y until end.y (empty when outside the grid).
func _cell_range(x0: float, z0: float, x1: float, z1: float) -> Rect2i:
	var c0 := maxi(0, floori((x0 - _origin.x) / CELL))
	var r0 := maxi(0, floori((z0 - _origin.y) / CELL))
	var c1 := mini(_cols - 1, floori((x1 - _origin.x) / CELL))
	var r1 := mini(_rows - 1, floori((z1 - _origin.y) / CELL))
	return Rect2i(c0, r0, maxi(0, c1 - c0 + 1), maxi(0, r1 - r0 + 1))


## A segment_hit result without a Dictionary: the fraction along the
## segment, the outward normal and the kind. Fill it with
## segment_hit_into() and reuse one per shot: the hot loops ask every step,
## and the Dictionary form allocated one per candidate hit. Mirrors
## olcore::ObstacleHit, which segment_hit() there already fills by reference.
class Hit:
	var fraction := 0.0
	var normal := Vector3.ZERO
	var kind := 0


## The first obstacle the segment from -> to enters from outside:
## {fraction (0 to 1), normal (outward unit normal), kind}, or {} if none. A
## segment that starts inside an obstacle does not hit it.
func segment_hit(from: Vector3, to: Vector3) -> Dictionary:
	var hit := Hit.new()
	if not segment_hit_into(from, to, hit):
		return {}
	return {"fraction": hit.fraction, "normal": hit.normal, "kind": hit.kind}


## segment_hit() without the Dictionary: writes the first obstacle into
## `out` and returns true, or false for none. `out` keeps its old values
## on false, so only read it when this returns true.
func segment_hit_into(from: Vector3, to: Vector3, out: Hit) -> bool:
	if _cols == 0:
		return false
	var d := to - from
	var r := _cell_range(minf(from.x, to.x), minf(from.z, to.z), maxf(from.x, to.x), maxf(from.z, to.z))
	var cand := Hit.new()
	var found := false
	var low := minf(from.y, to.y)
	for row in range(r.position.y, r.end.y):
		for col in range(r.position.x, r.end.x):
			var c := row * _cols + col
			# Wholly above everything in the cell (a little room for rounding).
			if low > _cell_top[c] + TOP_MARGIN:
				continue
			for i in range(_cell_start[c], _cell_start[c + 1]):
				var k := _cell_items[i]
				var got := _hit_cylinder_into(k, from, d, cand) if k >= 0 else _hit_box_into(-k - 1, from, d, cand)
				if got and (not found or cand.fraction < out.fraction):
					out.fraction = cand.fraction
					out.normal = cand.normal
					out.kind = cand.kind
					found = true
	return found


## Where p + d t is between lo and hi, as Vector2(t0, t1); null if never.
static func _slab(p: float, d: float, lo: float, hi: float) -> Variant:
	if absf(d) < 1e-12:
		return Vector2(-INF, INF) if p >= lo and p <= hi else null
	var a := (lo - p) / d
	var b := (hi - p) / d
	return Vector2(minf(a, b), maxf(a, b))


func _hit_cylinder_into(i: int, from: Vector3, d: Vector3, out: Hit) -> bool:
	var o := i * CYLINDER_FLOATS
	var ty: Variant = _slab(from.y, d.y, _cylinders[o + 3], _cylinders[o + 4])
	if ty == null:
		return false
	var radius := _cylinders[o + 2]
	var fx := from.x - _cylinders[o]
	var fz := from.z - _cylinders[o + 1]
	var a := d.x * d.x + d.z * d.z
	var cc := fx * fx + fz * fz - radius * radius
	var tc0 := -INF
	var tc1 := INF
	if a < 1e-12:
		if cc > 0.0:
			return false
	else:
		var b := fx * d.x + fz * d.z
		var disc := b * b - a * cc
		if disc < 0.0:
			return false
		var sq := sqrt(disc)
		tc0 = (-b - sq) / a
		tc1 = (-b + sq) / a
	var y: Vector2 = ty
	var t0 := maxf(y.x, tc0)
	var t1 := minf(y.y, tc1)
	if t0 > t1 or t0 < 0.0 or t0 > 1.0:
		return false
	var normal := Vector3(0.0, -1.0 if d.y > 0.0 else 1.0, 0.0)
	if tc0 >= y.x:
		normal = Vector3((fx + d.x * t0) / radius, 0.0, (fz + d.z * t0) / radius)
	out.fraction = t0
	out.normal = normal
	out.kind = int(_cylinders[o + 5])
	return true


func _hit_box_into(i: int, from: Vector3, d: Vector3, out: Hit) -> bool:
	var o := i * BOX_FLOATS
	var rel := from - Vector3(_boxes[o], _boxes[o + 1], _boxes[o + 2])
	var t0 := -INF
	var t1 := INF
	var face := Vector3.ZERO
	for k in 3:
		var axis := Vector3(_boxes[o + 3 + 3 * k], _boxes[o + 4 + 3 * k], _boxes[o + 5 + 3 * k])
		var dk := d.dot(axis)
		var half := _boxes[o + 12 + k]
		var s: Variant = _slab(rel.dot(axis), dk, -half, half)
		if s == null:
			return false
		var span: Vector2 = s
		if span.x > t0:
			t0 = span.x
			face = -axis if dk > 0.0 else axis
		t1 = minf(t1, span.y)
	if face == Vector3.ZERO or t0 > t1 or t0 < 0.0 or t0 > 1.0:
		return false
	out.fraction = t0
	out.normal = face
	out.kind = int(_boxes[o + 15])
	return true
