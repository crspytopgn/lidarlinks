class_name CoursePlayability
extends RefCounted
## Makes a course built from the map playable, as a club's builder would
## have shaped it, wherever the measured ground can't be played as it is
## (the GDScript side of tools/homecourse/playable.py, for courses built in
## the game):
##
## - smooth_ground: coarse open elevation tiles (3 to 5 m a pixel, no
##   lidar) carry speckle and steps at their tile edges, a metre or two
##   high: on Sydney's flat Australian Golf Club the greens came out tilted
##   15 to 33 %. They are smoothed over about two of their pixels.
## - grade_greens: a green steeper than a real one's pinnable ground (over
##   3 % overall, or a quarter of it over 4.5 %) is cut and filled to a
##   plate falling 2 % toward its front, keeping a softened share of its own
##   contours, and the ground round it eased onto it. Crans-sur-Sierre's
##   greens follow the mountain at 8 to 13 %, where no ball stops.
## - level_tees: tee boxes are flat, eased into the ground round them.
## - trim_par3_tees: a par 3 tee further than a driver carries is dropped
##   while the hole has another.
##
## game/tests/realcourse_tests.gd checks each on a made-up course.

const FALL := 0.02  ## the graded plate's fall toward the front
const MAX_PLANE := 0.03  ## a green steeper overall than this is graded
const MAX_SPOT := 0.045  ## or with a quarter of it steeper than this
const BLEND := 14.0  ## metres over which the ground round a green eases onto it
const CONTOUR_KEEP := 0.35  ## share of the green's own contours kept
const CONTOUR_MAX := 0.15  ## metres either side of the plate
const TEE_BLEND := 6.0  ## metres over which a levelled tee eases into the ground
const MAX_TEE_TILT := 0.015
const LONGEST_PAR3 := 220.0  ## metres: a driver carries about 224 m (Club.standard_set)


## Smooths the heights over about `metres` (Image resampling, so it is quick
## on a big course).
static func smooth_ground(c: DesignedCourse, metres: float) -> void:
	var f := maxi(roundi(metres / DesignedCourse.CELL), 1)
	if f <= 1 or c.cols < f * 4 or c.rows < f * 4:
		return
	var img := Image.create_from_data(c.cols, c.rows, false, Image.FORMAT_RF, c.heights.to_byte_array())
	img.resize(maxi(c.cols / f, 2), maxi(c.rows / f, 2), Image.INTERPOLATE_LANCZOS)
	img.resize(c.cols, c.rows, Image.INTERPOLATE_CUBIC)
	c.heights = img.get_data().to_float32_array()


## Grades the greens too steep to hold a ball; returns how many.
static func grade_greens(c: DesignedCourse) -> int:
	var graded := 0
	for s in c.shapes:
		if s.surface == Surface.Type.GREEN and grade_green(c, s):
			graded += 1
	return graded


## Grades one green if it is too steep; true if it did.
static func grade_green(c: DesignedCourse, s: CourseShape) -> bool:
	var b := s.bounds()
	var lo := c.cell_of(b.position - Vector2.ONE * (BLEND + DesignedCourse.CELL * 2.0))
	var hi := c.cell_of(b.end + Vector2.ONE * (BLEND + DesignedCourse.CELL * 2.0))
	# Half a metre off the drawn edge is close enough, and far quicker.
	var ring := RealCourseBuilder.simplify_ring(s.outline(), 0.5)
	# Signed distance to the edge (negative inside) at each sample nearby.
	var cells: Array[Vector2i] = []
	var sd := PackedFloat32Array()
	for j in range(lo.y, hi.y + 1):
		for i in range(lo.x, hi.x + 1):
			var p := c.sample_pos(i, j)
			var d := _edge_distance(ring, p)
			if Geometry2D.is_point_in_polygon(p, ring):
				d = -d
			if d < BLEND:
				cells.append(Vector2i(i, j))
				sd.append(d)
	# The plane through the green (least squares over its samples).
	var n := 0
	var sx := 0.0
	var sz := 0.0
	var sh := 0.0
	var sxx := 0.0
	var szz := 0.0
	var sxz := 0.0
	var sxh := 0.0
	var szh := 0.0
	for k in cells.size():
		if sd[k] >= 0.0:
			continue
		var p := c.sample_pos(cells[k].x, cells[k].y) - b.get_center()
		var h := c.heights[cells[k].y * c.cols + cells[k].x]
		n += 1
		sx += p.x
		sz += p.y
		sh += h
		sxx += p.x * p.x
		szz += p.y * p.y
		sxz += p.x * p.y
		sxh += p.x * h
		szh += p.y * h
	if n < 20:
		return false
	var fit := _solve3(Basis(Vector3(n, sx, sz), Vector3(sx, sxx, sxz), Vector3(sz, sxz, szz)), Vector3(sh, sxh, szh))
	var tilt := Vector2(fit.y, fit.z).length()
	# Steep spots inside it (the collar's bank at the edge doesn't count).
	var slopes := PackedFloat32Array()
	for k in cells.size():
		if sd[k] < -DesignedCourse.CELL * 2.0:
			slopes.append(_slope(c, cells[k].x, cells[k].y))
	if slopes.size() < 10:
		for k in cells.size():
			if sd[k] < 0.0:
				slopes.append(_slope(c, cells[k].x, cells[k].y))
	slopes.sort()
	var spot := slopes[int(slopes.size() * 0.75)] if not slopes.is_empty() else 0.0
	if tilt <= MAX_PLANE and spot <= MAX_SPOT:
		return false
	var centre := b.get_center()
	var front := _front(c, centre)
	if front == Vector2.ZERO:
		front = -Vector2(fit.y, fit.z) / maxf(tilt, 1e-6)  # keep its own fall
	var mean := sh / n
	# The green's own contours, smoothed (3 x 3) and softened.
	var res := {}
	for k in cells.size():
		if sd[k] < 0.0:
			var q := cells[k]
			res[q] = c.heights[q.y * c.cols + q.x] - _plane(fit, c.sample_pos(q.x, q.y) - centre)
	var out := PackedFloat32Array()
	out.resize(cells.size())
	for k in cells.size():
		var q := cells[k]
		var p := c.sample_pos(q.x, q.y)
		var h := c.heights[q.y * c.cols + q.x]
		var plane := _plane(fit, p - centre)
		var plate := mean - FALL * (p - centre).dot(front)
		if sd[k] < 0.0:
			var sum := 0.0
			var m := 0
			for dj in range(-1, 2):
				for di in range(-1, 2):
					var r: Variant = res.get(q + Vector2i(di, dj))
					if r != null:
						sum += float(r)
						m += 1
			var kept := clampf(sum / m * CONTOUR_KEEP, -CONTOUR_MAX, CONTOUR_MAX)
			var inner := smoothstep(0.0, 3.0, -sd[k])
			out[k] = lerpf(plate + (h - plane), plate + kept, inner)
		else:
			out[k] = h + (plate - plane) * (1.0 - smoothstep(0.0, BLEND, sd[k]))
	for k in cells.size():
		c.heights[cells[k].y * c.cols + cells[k].x] = clampf(out[k], -DesignedCourse.MAX_HEIGHT, DesignedCourse.MAX_HEIGHT)
	return true


## Levels the tee boxes that slope; returns how many.
static func level_tees(c: DesignedCourse) -> int:
	var levelled := 0
	for s in c.shapes:
		if s.surface != Surface.Type.TEE:
			continue
		var b := s.bounds()
		var ring := RealCourseBuilder.simplify_ring(s.outline(), 0.3)
		var lo := c.cell_of(b.position - Vector2.ONE * (TEE_BLEND + DesignedCourse.CELL))
		var hi := c.cell_of(b.end + Vector2.ONE * (TEE_BLEND + DesignedCourse.CELL))
		var sum := 0.0
		var n := 0
		var top := -INF
		var low := INF
		for j in range(lo.y, hi.y + 1):
			for i in range(lo.x, hi.x + 1):
				if Geometry2D.is_point_in_polygon(c.sample_pos(i, j), ring):
					var h := c.heights[j * c.cols + i]
					sum += h
					n += 1
					top = maxf(top, h)
					low = minf(low, h)
		if n < 2:
			continue
		var span := maxf(b.size.x, b.size.y)
		if top - low <= MAX_TEE_TILT * span:
			continue
		var level := sum / n
		for j in range(lo.y, hi.y + 1):
			for i in range(lo.x, hi.x + 1):
				var p := c.sample_pos(i, j)
				var d := _edge_distance(ring, p)
				var w := 1.0 if Geometry2D.is_point_in_polygon(p, ring) else 1.0 - smoothstep(0.0, TEE_BLEND, d)
				var k := j * c.cols + i
				c.heights[k] = lerpf(c.heights[k], level, w)
		levelled += 1
	return levelled


## Drops par 3 tees further than LONGEST_PAR3 from the pin while the hole
## keeps another; returns how many.
static func trim_par3_tees(c: DesignedCourse) -> int:
	var dropped := 0
	for h in c.holes:
		if h.par != 3 or h.tees.size() < 2:
			continue
		var keep := PackedVector2Array()
		for t in h.tees:
			if t.distance_to(h.pin) <= LONGEST_PAR3:
				keep.append(t)
		if not keep.is_empty() and keep.size() < h.tees.size():
			dropped += h.tees.size() - keep.size()
			h.tees = keep
	return dropped


## Unit (x, z) from a green toward where its hole comes in from; zero if no
## hole ends there.
static func _front(c: DesignedCourse, centre: Vector2) -> Vector2:
	for h in c.holes:
		if h.pin.distance_to(centre) < 60.0:
			var back := h.route[h.route.size() - 1] if not h.route.is_empty() else (h.tees[0] if not h.tees.is_empty() else h.pin)
			var d := back - h.pin
			return d.normalized() if d.length() > 1e-3 else Vector2.ZERO
	return Vector2.ZERO


static func _plane(fit: Vector3, p: Vector2) -> float:
	return fit.x + fit.y * p.x + fit.z * p.y


## Solves m * x = v for a symmetric 3 x 3 m (columns as given).
static func _solve3(m: Basis, v: Vector3) -> Vector3:
	if absf(m.determinant()) < 1e-9:
		return Vector3(v.x / maxf(m.x.x, 1.0), 0.0, 0.0)
	return m.inverse() * v


static func _slope(c: DesignedCourse, i: int, j: int) -> float:
	var i0 := maxi(i - 1, 0)
	var i1 := mini(i + 1, c.cols - 1)
	var j0 := maxi(j - 1, 0)
	var j1 := mini(j + 1, c.rows - 1)
	var gx := (c.heights[j * c.cols + i1] - c.heights[j * c.cols + i0]) / ((i1 - i0) * DesignedCourse.CELL)
	var gz := (c.heights[j1 * c.cols + i] - c.heights[j0 * c.cols + i]) / ((j1 - j0) * DesignedCourse.CELL)
	return Vector2(gx, gz).length()


static func _edge_distance(ring: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	for i in ring.size():
		best = minf(best, p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p, ring[i], ring[(i + 1) % ring.size()])))
	return sqrt(best)
