extends RefCounted
## Checks for the course designer's data side: DesignedCourse, CourseShape,
## DesignedTerrain and DesignedCourseLoader. run_tests.gd calls run_all() and
## reports what it returns; it also opens the designer scene and plays a
## round on a designed course.

const TEST_PATH := "user://designer_test.olc"

var failures: Array[String] = []


func run_all() -> Array[String]:
	_test_scripts_compile()
	_test_shapes()
	_test_starter_surfaces()
	_test_save_round_trip()
	_test_sculpt()
	_test_ground_lods()
	_test_height_bounds()
	_test_edit_surfaces()
	_test_trees()
	_test_loader()
	_test_objects()
	_test_paths()
	_test_object_info()
	_test_bad_files()
	_test_water_surface()
	_test_splat_and_stakes()
	_test_tee_pads()
	_test_epic_courses()
	return failures


## The epic built-in courses load and play: a biome, the land round them,
## rock formations and cacti that the ball hits, none of them on a tee,
## fairway or green, and every pin reachable over open ground.
func _test_epic_courses() -> void:
	for path: String in PlaceholderCourseLoader.EPIC:
		var name := str(PlaceholderCourseLoader.EPIC[path])
		var designed := DesignedCourse.load_file(path)
		check(designed != null, "%s loads" % name)
		if designed == null:
			continue
		check(not designed.biome.is_empty(), "%s has a biome" % name)
		var land := designed.landscape
		check(not land.is_empty() and int(land.cols) * int(land.rows) == (land.heights as PackedFloat32Array).size(), "%s has its landscape" % name)
		var course := DesignedCourseLoader.new().load_course(path)
		check(course != null and course.holes.size() in [9, 18] and course.landscape and course.biome == designed.biome, "%s plays its holes" % name)
		check(CourseFiles.display_name(path) == name + " (built in)", "%s is listed as built in" % name)
		var terrain := DesignedTerrain.new(designed)
		var rocks := 0
		var plants := 0
		for o in designed.objects:
			if RockFormations.is_rock(o.id):
				rocks += 1
			elif DesertPlants.is_plant(o.id):
				plants += 1
			else:
				continue
			var s := terrain.surface_at(o.position.x, o.position.z)
			check(not s in [Surface.Type.TEE, Surface.Type.FAIRWAY, Surface.Type.GREEN, Surface.Type.FRINGE, Surface.Type.SAND],
				"%s: %s at (%.0f, %.0f) stands on %s" % [name, o.id, o.position.x, o.position.z, Surface.Type.keys()[s]])
		if designed.biome == Biome.DESERT:
			check(rocks >= 10 and plants >= 500, "%s has formations and cacti (%d, %d)" % [name, rocks, plants])
		# The formations are solid: a ball flying into the first tower stops.
		for o in designed.objects:
			if o.id != "rock_spire":
				continue
			var y := terrain.height_at(o.position.x, o.position.z)
			var c := Vector3(o.position.x, y + 10.0, o.position.z)
			check(not terrain.obstacles.segment_hit(c + Vector3(60, 0, 0), c).is_empty(), "%s: a spire stops the ball" % name)
			break
		check(Biome.is_bare(designed.biome, Surface.Type.DEEP_ROUGH) == (designed.biome in [Biome.DESERT, Biome.SNOW, Biome.TROPICAL]), "%s: bare ground follows the biome" % name)
		var mesh := RockFormations.mesh_for(designed.objects.filter(func(o: PlacedObject) -> bool: return o.id == "rock_arch")[0]) if designed.biome == Biome.DESERT else null
		check(mesh == null or mesh.get_faces().size() > 3000, "%s: the arch has a mesh" % name)
		if name == "Red Spire":
			check(designed.cliffs.size() >= 3, "%s has mesas with rock walls (%d)" % [name, designed.cliffs.size()])
			var round_trip := DesignedCourse.from_dict(designed.to_dict())
			check(round_trip != null and round_trip.cliffs.size() == designed.cliffs.size(), "%s keeps its cliffs when saved" % name)
			if not designed.cliffs.is_empty():
				var wall := RockFormations.cliff_mesh(terrain, designed.cliffs[0], 1)
				check(wall.get_faces().size() > 3000, "%s: a cliff has a mesh" % name)
		var visual := terrain.build_visual()
		check(visual.get_node_or_null("Landscape") != null and visual.get_node_or_null("Apron") == null, "%s: the landscape replaces the apron" % name)
		visual.free()


## Tee boxes are raised level pads with mown banks, and the ball plays the
## same triangles that are drawn.
func _test_tee_pads() -> void:
	var c := DesignedCourse.blank(Vector2(200, 200))
	# Ground falling 6 % toward -z, as on a hillside.
	for j in c.rows:
		for i in c.cols:
			c.heights[j * c.cols + i] = 0.06 * c.sample_pos(i, j).y
	var t := DesignedTerrain.new(c)
	var tee := CourseShape.oval(Surface.Type.TEE, Vector2(0, 0), Vector2(7, 4.5), 0.3, 12)
	c.shapes.append(tee)
	t.update_surfaces(tee.bounds())
	var level := TeePads.level_of(c, tee)
	check(t._pads.pads.size() == 1, "one tee pad insert")
	for p in [Vector2(0, 0), Vector2(3, 1), Vector2(-4, -1), Vector2(1, -2.5)]:
		check(absf(t.height_at(p.x, p.y) - level) < 0.005, "the tee top is level at %s" % p)
	check(absf(level - c.base_height(0, 0) - TeePads.RAISE) < 0.08, "raised about %.2f m above the ground" % TeePads.RAISE)
	# Down each side from the edge: a clean shoulder, banks no steeper than
	# 1 in 3, and the ground untouched beyond the bank.
	for dir in [Vector2(0, -1), Vector2(0, 1), Vector2(1, 0), Vector2(-1, 0), Vector2(0.7, -0.7)]:
		var edge := Vector2.ZERO
		while tee.signed_distance(edge) < 0.0:
			edge += dir * 0.02
		var steepest := 0.0
		var prev := t.height_at(edge.x, edge.y)
		for k in range(1, 70):
			var q: Vector2 = edge + dir * (k * 0.1)
			var y := t.height_at(q.x, q.y)
			steepest = maxf(steepest, absf(y - prev) / 0.1)
			prev = y
		check(steepest <= 0.34, "bank no steeper than 1 in 3 toward %s (%.2f)" % [dir, steepest])
		var far: Vector2 = edge + dir * (TeePads.REACH + 0.5)
		check(absf(t.height_at(far.x, far.y) - c.base_height(far.x, far.y)) < 0.002, "ground untouched beyond the bank")
		if dir == Vector2(0, -1):
			var below: Vector2 = edge + dir
			check(t.height_at(below.x, below.y) < level - 0.15, "a clean drop off the low side's shoulder")
	# The insert joins the grid with no step.
	var pad: TeePads.Pad = t._pads.pads[0]
	var lo := c.sample_pos(pad.cells.position.x, pad.cells.position.y)
	var hi := c.sample_pos(pad.cells.end.x, pad.cells.end.y)
	var worst := 0.0
	for k in 41:
		var f := k / 40.0
		for e in [[Vector2(lerpf(lo.x, hi.x, f), lo.y), Vector2(0, 1)], [Vector2(lerpf(lo.x, hi.x, f), hi.y), Vector2(0, -1)],
				[Vector2(lo.x, lerpf(lo.y, hi.y, f)), Vector2(1, 0)], [Vector2(hi.x, lerpf(lo.y, hi.y, f)), Vector2(-1, 0)]]:
			var a: Vector2 = e[0] + e[1] * 0.01
			var b: Vector2 = e[0] - e[1] * 0.01
			worst = maxf(worst, absf(t.height_at(a.x, a.y) - t.height_at(b.x, b.y)))
	check(worst < 0.003, "the pad joins the ground round it (%.4f m)" % worst)
	var missed := 0
	for k in 400:
		var q := Vector2(lerpf(lo.x, hi.x, randf()), lerpf(lo.y, hi.y, randf()))
		if is_nan(pad.height_at(q)):
			missed += 1
	check(missed == 0, "the ball finds the pad's triangles everywhere on it (%d missed)" % missed)
	# What is drawn is what the ball plays: every vertex and triangle middle
	# of the ground mesh over the pad is at height_at().
	var off := 0.0
	var covered := 0.0
	var backwards := 0
	var n := t.chunk_count()
	for cj in n.y:
		for ci in n.x:
			var arrays := t.chunk_mesh(Vector2i(ci, cj)).surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for k in range(0, idx.size(), 3):
				var m := (verts[idx[k]] + verts[idx[k + 1]] + verts[idx[k + 2]]) / 3.0
				if m.x < lo.x or m.x > hi.x or m.z < lo.y or m.z > hi.y:
					continue
				off = maxf(off, absf(t.height_at(m.x, m.z) - m.y))
				var ab := Vector2(verts[idx[k + 1]].x - verts[idx[k]].x, verts[idx[k + 1]].z - verts[idx[k]].z)
				var ac := Vector2(verts[idx[k + 2]].x - verts[idx[k]].x, verts[idx[k + 2]].z - verts[idx[k]].z)
				covered += absf(ab.cross(ac)) * 0.5
				if ab.cross(ac) < 0.0:
					backwards += 1
				for e in 3:
					var v := verts[idx[k + e]]
					off = maxf(off, absf(t.height_at(v.x, v.z) - v.y))
	check(off < 0.001, "the drawn tee is the one the ball plays (%.4f m)" % off)
	check(backwards == 0, "every triangle over the pad faces up (%d face down)" % backwards)
	var rect_area := (hi.x - lo.x) * (hi.y - lo.y)
	check(absf(covered - rect_area) < rect_area * 0.001, "the ground over the pad has no holes (%.1f of %.1f m2)" % [covered, rect_area])
	# Moving the tee moves its pad.
	var old := tee.bounds()
	tee.translate(Vector2(40, 0))
	t.update_surfaces(old.merge(tee.bounds()))
	check(absf(t.height_at(0, 0) - c.base_height(0, 0)) < 0.002, "a moved tee leaves the ground as it was")
	check(absf(t.height_at(40, 0) - TeePads.level_of(c, tee)) < 0.005, "and its pad goes with it")


## The ground's splat map is the surface raster, and ponds get stakes.
func _test_splat_and_stakes() -> void:
	var poly := PackedVector2Array([Vector2(0, 0), Vector2(60, 0), Vector2(60, 40), Vector2(0, 40)])
	var pts := DesignedTerrain.stake_points(poly, 10.0)
	check(pts.size() == 20 and pts[0] == Vector2.ZERO and pts[1].is_equal_approx(Vector2(10, 0)), "stakes every 10 m round a 200 m outline")
	var c := DesignedCourse.starter()
	var t := DesignedTerrain.new(c)
	var mat := t.material()
	var splat := mat.get_shader_parameter("splat_tex") as Texture2D
	check(mat.get_shader_parameter("has_splat") == true and splat != null, "the ground has a splat map")
	if splat != null:
		var codes: Vector2i = mat.get_shader_parameter("splat_codes")
		check(codes.x == ceili(c.area.size.x / DesignedTerrain.RES) and splat.get_width() >= codes.x, "splat map at the raster's 0.5 m")
		var block: Vector2i = mat.get_shader_parameter("green_edge_size")
		check(splat.get_width() >= block.x * DesignedTerrain.EDGE_BLOCKS.size(), "edge distances for greens, bunkers and tees")
	var stakes := t.build_stakes()
	check(stakes != null and stakes.multimesh.instance_count > 5, "the starter pond has hazard stakes")
	if stakes != null:
		stakes.free()


## A pond's water carries how far each vertex is from the bank, for the
## shallows and shoreline.
func _test_water_surface() -> void:
	var poly := PackedVector2Array([Vector2(0, 0), Vector2(60, 0), Vector2(60, 40), Vector2(0, 40)])
	var m := DesignedTerrain.water_surface_mesh(poly, 1.5)
	var verts: PackedVector3Array = m[0]
	var open: PackedColorArray = m[1]
	var indices: PackedInt32Array = m[2]
	check(verts.size() > poly.size() and indices.size() >= 6 and indices.size() % 3 == 0, "water: grid inside the outline (%d vertices)" % verts.size())
	check(open[0].r == 0.0 and open[2].r == 0.0, "water: open is 0 on the bank")
	var deepest := 0.0
	for c in open:
		deepest = maxf(deepest, c.r)
	check(deepest == 1.0, "water: open water in the middle")
	check(is_equal_approx(verts[verts.size() - 1].y, 1.5), "water: at its level")


func check(cond: bool, what: String) -> void:
	if not cond:
		failures.append(what)


func _test_scripts_compile() -> void:
	for path in ["res://scripts/designer/course_designer.gd", "res://scripts/designer/designer_panel.gd",
			"res://scripts/designer/designer_camera.gd", "res://scripts/designer/designer_files.gd",
			"res://scripts/designer/designed_terrain.gd", "res://scripts/designer/designer_objects.gd", "res://scripts/designer/course_path.gd", "res://scripts/course/designed_course_loader.gd"]:
		var script: GDScript = load(path)
		check(script != null and script.can_instantiate(), "%s compiles" % path)


func _test_shapes() -> void:
	var square := CourseShape.new(Surface.Type.GREEN, PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)]))
	check(square.contains(Vector2(5, 5)), "a square shape contains its centre")
	check(not square.contains(Vector2(15, 5)), "and not a point outside")
	check(square.signed_distance(Vector2(5, 5)) < -3.0, "inside is negative")
	check(square.signed_distance(Vector2(20, 5)) > 8.0, "outside is positive")
	check(square.outline().size() == 4 * CourseShape.SUBDIVISIONS, "smoothed outline")
	check(square.area() > 100.0 and square.area() < 150.0, "area of the smoothed square: %f" % square.area())
	var n := square.insert_point(Vector2(5, -1))
	check(n == 1 and square.points.size() == 5, "a point goes into the nearest edge")
	check(square.nearest_point(Vector2(10.5, 10.2), 2.0) == 3, "nearest control point")
	var back := CourseShape.from_dict(square.to_dict())
	check(back.surface == Surface.Type.GREEN and back.points == square.points, "shape survives to_dict")


func _starter_points(c: DesignedCourse) -> Dictionary:
	var z0 := c.area.position.y + 80.0
	return {
		"green": Vector2(-16, z0 + 365), "bunker": Vector2(26, z0 + 262), "pond": Vector2(-42, z0 + 190),
		"fairway": Vector2(8, z0 + 230), "tee": Vector2(2, z0 + 25),
	}


func _test_starter_surfaces() -> void:
	var c := DesignedCourse.starter()
	var data := c.to_course_data()
	check(data.holes.size() == 1, "the starter course has a hole")
	if data.holes.is_empty():
		return
	var h := data.holes[0]
	var t := h.terrain as DesignedTerrain
	check(t != null, "holes use a DesignedTerrain")
	check(h.tees.size() == 3, "three tees")
	for tee in h.tees:
		check(t.surface_at(tee.x, tee.z) == Surface.Type.TEE, "tee %s is on the tee box" % tee)
		check(absf(tee.y - t.height_at(tee.x, tee.z)) < 1e-3, "tee height")
	check(t.surface_at(h.pin.x, h.pin.z) == Surface.Type.GREEN, "the pin is on the green")
	check(h.par == 4 and h.length_m() > 330.0 and h.length_m() < 400.0, "par 4 of %d m" % roundi(h.length_m()))
	var pts := _starter_points(c)
	check(t.surface_at(pts.fairway.x, pts.fairway.y) == Surface.Type.FAIRWAY, "fairway")
	check(t.surface_at(pts.bunker.x, pts.bunker.y) == Surface.Type.SAND, "bunker")
	check(t.surface_at(pts.pond.x, pts.pond.y) == Surface.Type.WATER, "pond")
	check(t.surface_at(c.area.position.x + 3, c.area.position.y + 3) == Surface.Type.ROUGH, "rough elsewhere")
	check(t.surface_at(c.area.end.x + 5, 0) == Surface.Type.OUT_OF_BOUNDS, "out of bounds off the course")
	# The bunker is dug in below the ground round it.
	var b: Vector2 = pts.bunker
	check(t.height_at(b.x, b.y) < c.base_height(b.x, b.y) - 0.5, "bunker is dug in")
	# The pond's bed is under its water line.
	var pond := -1
	for i in c.shapes.size():
		if c.shapes[i].surface == Surface.Type.WATER:
			pond = i
	var p: Vector2 = pts.pond
	check(pond >= 0 and t.height_at(p.x, p.y) < t.water_level(c.shapes[pond]) - 0.5, "pond bed under the water")
	# Tee pads are level.
	var tee2: Vector2 = pts.tee
	check(absf(t.height_at(tee2.x, tee2.y + 10) - t.height_at(tee2.x, tee2.y - 10)) < 0.05, "tee box is level")
	# A fringe ring round the green.
	var g: Vector2 = pts.green
	var edge := g
	while t.surface_at(edge.x, edge.y) == Surface.Type.GREEN:
		edge.y -= 0.25
	check(t.surface_at(edge.x, edge.y - 0.6) == Surface.Type.FRINGE, "fringe round the green")
	# A first cut beside the fairway: drawn and grown shorter, played as rough.
	var f: Vector2 = pts.fairway
	var side := f
	while t.surface_at(side.x, side.y) == Surface.Type.FAIRWAY:
		side.x += 0.25
	var cut := side + Vector2(0.75, 0.0)
	var beyond := side + Vector2(DesignedTerrain.FIRST_CUT_WIDTH + 2.0, 0.0)
	check(t.surface_at(cut.x, cut.y) == Surface.Type.ROUGH and t.first_cut_at(cut.x, cut.y), "first cut beside the fairway plays as rough")
	check(not t.first_cut_at(beyond.x, beyond.y) and not t.first_cut_at(f.x, f.y), "first cut only in a band at the fairway's edge")
	var visual := t.build_visual()
	var n := t.chunk_count()
	# Plus the node that works out the far ground's levels (refine_lods).
	check(visual.get_child_count() == n.x * n.y + 4 and visual.get_node_or_null("LodRefiner") != null, "a mesh per chunk, the apron, the paths, the water and the far levels' worker")
	var water := visual.get_child(visual.get_child_count() - 1)
	check(water.find_children("*", "MeshInstance3D", false, false).size() == 1, "one pond mesh")
	check(water.get_node_or_null("Stakes") != null, "and its hazard stakes")
	visual.free()


func _test_save_round_trip() -> void:
	var c := DesignedCourse.starter()
	c.course_name = "Round trip"
	c.author = "Tests"
	var text := c.to_json()
	check(text.length() < 600000, "the save file is compact: %d bytes" % text.length())
	var back := DesignedCourse.from_json(text)
	check(back != null, "a saved course loads")
	if back == null:
		return
	check(back.course_name == "Round trip" and back.author == "Tests", "name and author")
	check(back.area == c.area and back.heights.size() == c.heights.size(), "area and grid")
	var worst := 0.0
	for k in range(0, c.heights.size(), 97):
		worst = maxf(worst, absf(back.heights[k] - c.heights[k]))
	check(worst <= 0.0051, "heights to the centimetre (worst %f)" % worst)
	check(back.shapes.size() == c.shapes.size(), "shapes")
	check(back.holes.size() == 1 and back.holes[0].tees == c.holes[0].tees and back.holes[0].pin == c.holes[0].pin, "holes")
	check(back.objects.size() == c.objects.size(), "trees")
	var t1 := DesignedTerrain.new(c)
	var t2 := DesignedTerrain.new(back)
	var same := true
	for p: Vector2 in _starter_points(c).values():
		same = same and t1.surface_at(p.x, p.y) == t2.surface_at(p.x, p.y)
	check(same, "same surfaces after loading")


func _test_sculpt() -> void:
	var c := DesignedCourse.blank(Vector2(200, 200))
	var t := DesignedTerrain.new(c)
	var cells := c.sculpt("raise", Vector2(10, 10), 12.0, 2.0)
	t.update_heights(cells)
	check(absf(t.height_at(10, 10) - 2.0) < 0.05, "raise lifts the centre by the amount: %f" % t.height_at(10, 10))
	check(absf(t.height_at(10, 30)) < 1e-4, "and leaves ground outside the brush alone")
	check(t.height_at(16, 10) > 0.3 and t.height_at(16, 10) < 1.7, "with a smooth falloff")
	cells = c.sculpt("smooth", Vector2(10, 10), 12.0, 1.0)
	t.update_heights(cells)
	check(t.height_at(10, 10) < 1.95, "smoothing takes the top off")
	cells = c.sculpt("flatten", Vector2(10, 10), 20.0, 1.0, 0.5)
	t.update_heights(cells)
	check(absf(t.height_at(10, 10) - 0.5) < 0.01, "flatten levels the centre")
	c.sculpt("raise", Vector2(0, 0), 5.0, 1000.0)
	check(c.base_height(0, 0) <= DesignedCourse.MAX_HEIGHT, "heights stay in range")


## max_height_in() never under-reads the ground (tee pads and fresh sculpting
## included), and the Links flight's ground search answers the same with it
## as without it.
func _test_height_bounds() -> void:
	# Its own copy: the sculpting below must not reach the shared built-in course.
	var t := DesignedTerrain.new(DesignedCourse.load_file(PlaceholderCourseLoader.FILE))
	var c := t.course
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var a := c.area
	var tee := c.holes[0].tees[0]
	t.update_heights(c.sculpt("raise", tee + Vector2(30, 0), 20.0, 3.0))
	var low := 0
	for k in 400:
		# Half round the first tee (its pad and the fresh hill), half anywhere.
		var p := tee + Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40)) if k % 2 == 0 \
				else a.position + Vector2(rng.randf() * a.size.x, rng.randf() * a.size.y)
		var q := p + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
		var top := t.max_height_in(minf(p.x, q.x), minf(p.y, q.y), maxf(p.x, q.x), maxf(p.y, q.y))
		for s in 9:
			var x := p.lerp(q, s / 8.0)
			if t.height_at(x.x, x.y) > top:
				low += 1
	check(low == 0, "the height bound is never under the ground (%d under)" % low)
	var g := LinksGround.TerrainGround.new(t)
	var plain := _PlainGround.new(t)
	var differ := 0
	var skipped := 0
	for k in 400:
		var p := tee + Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 60))
		var base := t.height_at(p.x, p.y)
		var from := LinksGround._to_game(Vector3(p.x, base + rng.randf_range(-0.5, 4.0), p.y))
		var to := from + Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 1))
		var with := LinksGround._ground_crossing(g, from, to)
		if with != LinksGround._ground_crossing(plain, from, to):
			differ += 1
		if minf(from.z, to.z) > g.max_height(from.x, from.y, to.x, to.y) + LinksGround.CLEAR_MARGIN:
			skipped += 1
	check(differ == 0, "the ground search answers the same with the bound (%d differ)" % differ)
	check(skipped > 50, "and the bound lets it skip steps clear of the ground (%d)" % skipped)
	# Steps low over the ground (a ball hopping along it): clear_above() only
	# says so when every point along them is above it, and the search answers
	# the same with it.
	var wrong := 0
	var clear := 0
	differ = 0
	for k in 600:
		var p := tee + Vector2(rng.randf_range(-60, 60), rng.randf_range(-60, 60))
		var q := p + Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))
		var a3 := Vector3(p.x, t.height_at(p.x, p.y) + rng.randf_range(-0.02, 0.25), p.y)
		var b3 := Vector3(q.x, t.height_at(q.x, q.y) + rng.randf_range(-0.02, 0.25), q.y)
		if t.clear_above(a3, b3, 0.003):
			clear += 1
			for s in 65:
				var x := a3.lerp(b3, s / 64.0)
				if x.y - t.height_at(x.x, x.z) <= 0.002:
					wrong += 1
					break
		var from := LinksGround._to_game(a3)
		var to := LinksGround._to_game(b3)
		if LinksGround._ground_crossing(g, from, to) != LinksGround._ground_crossing(plain, from, to):
			differ += 1
	check(wrong == 0, "clear_above() is never wrong (%d wrong)" % wrong)
	check(clear > 100, "and clears most low steps (%d of 600)" % clear)
	check(differ == 0, "low steps: the ground search answers the same (%d differ)" % differ)


## TerrainGround without its height bound or clearance test.
class _PlainGround extends LinksGround.TerrainGround:
	func max_height(_x0: float, _y0: float, _x1: float, _y1: float) -> float:
		return INF

	func clear_above(_p: Vector3, _q: Vector3, _margin: float) -> bool:
		return false


## Far ground gets coarser detail levels (DesignedTerrain.refine_lods):
## flat, plain ground switches almost at once, a hill only when its error
## is tiny on screen, painted ground keeps its detail, and skirts hang
## between chunks but not off the course's edge.
func _test_ground_lods() -> void:
	var c := DesignedCourse.blank(Vector2(300, 300))
	var t := DesignedTerrain.new(c)
	t.update_heights(c.sculpt("raise", Vector2(0, 0), 60.0, 6.0))
	var n := t.chunk_count()
	for j in n.y:
		for i in n.x:
			t.chunk_mesh(Vector2i(i, j))
	check(not t.refine_lods(0.0) or n.x * n.y == 1, "levels are worked out a little at a time")
	t.refine_lods(1e9)
	var flat: PackedFloat32Array = t.lod_keys.get(Vector2i(0, 0), PackedFloat32Array())
	check(flat.size() == DesignedTerrain.LOD_STEPS.size(), "flat ground gets every level: %s" % flat)
	check(flat.size() > 0 and flat[0] < 0.01, "and switches as soon as it is a pixel off: %s" % flat)
	var hill: PackedFloat32Array = t.lod_keys.get(t.chunk_count() / 2, PackedFloat32Array())
	check(hill.size() > 0 and hill[-1] > flat[-1], "a hill switches later than flat ground: %s" % hill)
	for k: Vector2i in t.lod_keys:
		var keys: PackedFloat32Array = t.lod_keys[k]
		for q in range(1, keys.size()):
			check(keys[q] > keys[q - 1], "each level switches farther out than the last")
	# Sun shadows: flat ground never shades itself, a hill does once the
	# sun is lower than its slopes.
	check(t.steepness.get(Vector2i(0, 0), INF) < 0.01, "flat ground has no slope")
	check(not DesignedTerrain.casts_sun_shadow(t.steepness[Vector2i(0, 0)], tan(deg_to_rad(5.0))), "flat ground casts no sun shadow even at sunset")
	var steep: float = t.steepness.get(t.chunk_count() / 2, 0.0)
	check(steep > 0.05, "the hill has slopes: %f" % steep)
	check(DesignedTerrain.casts_sun_shadow(steep, steep * 0.5) and not DesignedTerrain.casts_sun_shadow(steep, steep * 2.0), "a hill casts sun shadows only when the sun is lower than its slopes")
	# Skirts: an inner chunk's edge has them, the course's edge doesn't.
	var corner := t.chunk_mesh(Vector2i(0, 0))
	var arrays := corner.surface_get_arrays(0)
	var lowest := INF
	for v: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
		lowest = minf(lowest, v.y)
	check(lowest < -DesignedTerrain.SKIRT_DROP, "skirts hang below the ground")
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var on_edge := 0
	for q in idx.size():
		var v := verts[idx[q]]
		# Skirt vertices on the course's edge, other than the corners of
		# the inner sides' skirts.
		var side := DesignedTerrain.CHUNK * DesignedCourse.CELL
		var o := c.area.position
		if v.y < -1.0 and (v.x < o.x + 0.01 and v.z > o.y + 0.01 and v.z < o.y + side - 0.01 or v.z < o.y + 0.01 and v.x > o.x + 0.01 and v.x < o.x + side - 0.01):
			on_edge += 1
	check(on_edge == 0, "no skirt hangs off the course's edge: %d" % on_edge)
	# Painted ground (a bunker in the corner chunk) keeps its detail until
	# the coarser cells are far smaller than a pixel.
	var bunker := CourseShape.oval(Surface.Type.SAND, c.area.position + Vector2(30, 30), Vector2(6, 6))
	c.shapes.append(bunker)
	t.update_surfaces(bunker.bounds())
	t.chunk_mesh(Vector2i(0, 0))
	t.refine_lods(1e9)
	var painted: PackedFloat32Array = t.lod_keys.get(Vector2i(0, 0), PackedFloat32Array())
	check(painted.size() > 0 and painted[0] >= DesignedCourse.CELL * DesignedTerrain.LOD_ATTRIBUTE_SHARE * 2.0 - 0.01, "painted ground switches only far out: %s" % painted)


func _test_edit_surfaces() -> void:
	var c := DesignedCourse.blank(Vector2(200, 200))
	var t := DesignedTerrain.new(c)
	var bunker := CourseShape.oval(Surface.Type.SAND, Vector2(0, 0), Vector2(6, 6))
	c.shapes.append(bunker)
	t.update_surfaces(bunker.bounds())
	check(t.surface_at(0, 0) == Surface.Type.SAND, "a new bunker shows up")
	check(t.height_at(0, 0) < -0.5, "and is dug in")
	var old := bunker.bounds()
	bunker.translate(Vector2(40, 0))
	t.update_surfaces(old.merge(bunker.bounds()))
	check(t.surface_at(0, 0) == Surface.Type.ROUGH, "a moved bunker leaves rough behind")
	check(absf(t.height_at(0, 0)) < 1e-4, "and level ground")
	check(t.surface_at(40, 0) == Surface.Type.SAND, "and is where it was moved to")
	check(c.shape_at(Vector2(40, 0)) == 0 and c.shape_at(Vector2(0, 0)) == -1, "shape_at")


func _test_trees() -> void:
	var c := DesignedCourse.starter()
	var t := DesignedTerrain.new(c)
	check(c.objects.size() == 90, "the starter course has trees")
	check(t.obstacles.size() == 2 * c.objects.size(), "a trunk and a canopy per tree")
	var o := c.objects[0]
	var y := t.height_at(o.position.x, o.position.z)
	var hit := t.obstacle_hit(Vector3(o.position.x - 5, y + 1.0, o.position.z), Vector3(o.position.x + 5, y + 1.0, o.position.z))
	check(not hit.is_empty(), "a ball hits a tree trunk")
	var data := c.to_course_data()
	check(not data.holes[0].objects.is_empty(), "the hole lists the trees near it")


func _test_loader() -> void:
	var c := DesignedCourse.starter()
	check(c.save_file(TEST_PATH) == OK, "saves")
	var loader := DesignedCourseLoader.new()
	check(loader.can_load(TEST_PATH) and loader.can_load("x/Y.OLC") and not loader.can_load("a.crz"), "can_load")
	var course := AssetProviders.load_course(TEST_PATH)
	check(course != null and course.course_name == c.course_name, "AssetProviders loads a designed course")
	check(course != null and course.holes.size() == 1 and course.holes[0].terrain is DesignedTerrain, "with its hole")
	check(CourseFiles.display_name(TEST_PATH) == "designer_test (your design)", "shown as a design")
	DirAccess.remove_absolute(TEST_PATH)
	var blank := DesignedCourse.blank(Vector2(100, 100))
	blank.save_file(TEST_PATH)
	check(loader.load_course(TEST_PATH) == null, "a course without holes isn't playable")
	DirAccess.remove_absolute(TEST_PATH)


func _test_bad_files() -> void:
	check(DesignedCourse.from_json("not json") == null, "garbage is refused")
	check(DesignedCourse.from_json("{\"format\": \"something else\"}") == null, "other JSON is refused")
	var d := DesignedCourse.starter().to_dict()
	d.version = DesignedCourse.VERSION + 1
	check(DesignedCourse.from_dict(d) == null, "newer versions are refused")
	d = DesignedCourse.starter().to_dict()
	d.heights.count = 5
	check(DesignedCourse.from_dict(d) == null, "a height grid of the wrong size is refused")
	d = DesignedCourse.starter().to_dict()
	d.shapes = [{"surface": "Green", "points": [0, 0, 1]}, "junk"]
	var c := DesignedCourse.from_dict(d)
	check(c != null and c.shapes.is_empty(), "broken shapes are skipped")


func _test_objects() -> void:
	var cats := DesignerObjects.categories()
	check(not cats.is_empty() and cats[0].items.size() == 3, "the built-in trees and bush come first")
	var field := ObstacleField.new()
	DesignerObjects.add_obstacles(field, PlacedObject.new("tree_pine", Vector3(0, 0, 0)), 0.0)
	DesignerObjects.add_obstacles(field, PlacedObject.new("Nothing like this.btx", Vector3(20, 0, 0)), 0.0)
	field.finalize()
	check(field.size() == 3, "a trunk and canopy for a tree, a post for an object the library doesn't know")
	check(not field.segment_hit(Vector3(15, 1, 0), Vector3(25, 1, 0)).is_empty(), "the unknown object still stops the ball")
	var bush := ObstacleField.new()
	DesignerObjects.add_obstacles(bush, PlacedObject.new("bush", Vector3(0, 0, 0)), 0.0)
	bush.finalize()
	check(bush.size() == 1 and not bush.segment_hit(Vector3(-5, 0.8, 0), Vector3(5, 0.8, 0)).is_empty(), "a bush catches a low ball")
	check(bush.segment_hit(Vector3(-5, 3.0, 0), Vector3(5, 3.0, 0)).is_empty(), "and not one over it")
	var node := AssetProviders.object_library.instantiate("bush") if AssetProviders.object_library != null else null
	check(AssetProviders.object_library == null or node != null, "the built-in bush can be drawn")
	if node != null:
		node.free()


func _test_paths() -> void:
	var c := DesignedCourse.blank(Vector2(200, 200))
	var cart := CoursePath.new(PackedVector2Array([Vector2(-50, -20), Vector2(0, 0), Vector2(50, 20)]), 3.0)
	var span := CoursePath.new(PackedVector2Array([Vector2(-20, 60), Vector2(20, 60)]), 3.0, true)
	c.paths.append(cart)
	c.paths.append(span)
	var t := DesignedTerrain.new(c)
	check(t.surface_at(0, 0) == Surface.Type.FAIRWAY, "a cart path plays as fairway")
	check(t.surface_at(0, 5) == Surface.Type.ROUGH, "rough beside the path")
	check(t.free_drop_at(0, 0) and not t.free_drop_at(0, 5), "a free drop from the cart path")
	var y := t.height_at(0, 60)
	check(not t.obstacle_hit(Vector3(0, y + 3.0, 60), Vector3(0, y + 0.1, 60)).is_empty(), "a ball lands on the bridge deck")
	check(t.obstacle_hit(Vector3(0, y + 3.0, 70), Vector3(0, y + 0.1, 70)).is_empty(), "and nowhere else")
	var bridge := t._path_mesh(span)
	var rails := bridge.mesh.surface_get_arrays(1)[Mesh.ARRAY_VERTEX] as PackedVector3Array if bridge.mesh.get_surface_count() == 2 else PackedVector3Array()
	var top := -INF
	for v in rails:
		top = maxf(top, v.y)
	var deck := -INF
	for v in bridge.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
		deck = maxf(deck, v.y)
	check(not rails.is_empty() and absf(top - deck - (DesignedTerrain.RAIL_TOP + 0.05)) < 0.05, "a bridge has post-and-rail sides at railing height (%.2f m)" % (top - deck))
	bridge.free()
	var back := DesignedCourse.from_json(c.to_json())
	check(back != null and back.paths.size() == 2, "paths are saved")
	if back != null and back.paths.size() == 2:
		check(back.paths[0].points == cart.points and is_equal_approx(back.paths[0].width, 3.0) and not back.paths[0].bridge, "a path's points and width")
		check(back.paths[1].bridge, "a bridge stays a bridge")
	check(CoursePath.new(PackedVector2Array([Vector2(1, 1)])).is_valid() == false, "a path needs two points")
	var visual := t.build_paths()
	check(visual.get_child_count() == 2, "a mesh per path")
	visual.free()


func _test_object_info() -> void:
	# A course made with the player's game files, opened without them: the
	# saved sizes keep its obstacles, and its trees get built-in stand-ins.
	var c := DesignedCourse.blank(Vector2(200, 200))
	c.objects.append(PlacedObject.new("Oak big.btx", Vector3(0, 0, 0), 0.0, 1.0))
	c.objects.append(PlacedObject.new("Barn.mdl", Vector3(40, 0, 0), 90.0, 1.0))
	c.object_info = {
		"Oak big.btx": {"kind": "tree", "size": [12.0, 20.0, 12.0], "centre": [0.0, 10.0, 0.0]},
		"Barn.mdl": {"kind": "model", "size": [10.0, 6.0, 20.0], "centre": [0.0, 3.0, 0.0]},
		"Unused.btx": {"kind": "solid", "size": [1.0, 1.0, 1.0], "centre": [0.0, 0.5, 0.0]},
	}
	var d := c.to_dict()
	check(not (d.object_info as Dictionary).has("Unused.btx"), "unused object sizes aren't saved")
	var back := DesignedCourse.from_dict(d)
	check(back != null and back.object_info.has("Barn.mdl") and back.object_info.has("Oak big.btx"), "object sizes are saved")
	if back == null:
		return
	var tree := DesignerObjects.stand_in(back.objects[0], back.object_info)
	check(tree != null and tree.id == "tree_broadleaf" and is_equal_approx(tree.scale, 2.0), "a missing tree gets a built-in one of its height")
	check(DesignerObjects.stand_in(back.objects[1], back.object_info) == null, "a missing building isn't drawn")
	var t := DesignedTerrain.new(back)
	var y := t.height_at(40, 0)
	# The barn is turned 90 degrees, so its 20 m length runs along x.
	check(not t.obstacle_hit(Vector3(40 + 8, y + 3, -10), Vector3(40 + 8, y + 3, 10)).is_empty(), "the barn is as long as it was measured")
	check(t.obstacle_hit(Vector3(40 + 12, y + 3, -10), Vector3(40 + 12, y + 3, 10)).is_empty(), "and no longer")
	check(t.obstacle_hit(Vector3(40, y + 7, -10), Vector3(40, y + 7, 10)).is_empty(), "and no taller")
	var ty := t.height_at(0, 0)
	check(not t.obstacle_hit(Vector3(-10, ty + 12, 0), Vector3(10, ty + 12, 0)).is_empty(), "the tree's canopy is where it was measured")
