extends SceneTree
# Dev tool: audits a built real course: per hole the tee and pin surfaces,
# the green's slope at the pin, par against length, trees on the line of
# play and the reach check of game/tests/reach_tests.gd; then shapes that
# don't triangulate. Run alone: godot --headless --path game -s
# $PWD/tools/realcourse_bench/e2e_audit.gd -- course.olc

static func audit(c: DesignedCourse) -> void:
	AssetProviders.ensure_defaults()
	var data := c.to_course_data()
	var reach: Variant = load("res://tests/reach_tests.gd").new()
	var lines := PackedStringArray()
	var bad := 0
	for i in data.holes.size():
		var h: HoleData = data.holes[i]
		var dh: DesignedHole = c.holes[i]
		var t := h.terrain
		var pin := h.pins[0] if h.pins.size() > 0 else h.pin
		var notes := PackedStringArray()
		var tee_s := t.surface_at(h.tee.x, h.tee.z)
		if tee_s != Surface.Type.TEE: notes.append("tee on %s" % Surface.Type.keys()[tee_s])
		var pin_s := t.surface_at(pin.x, pin.z)
		if pin_s != Surface.Type.GREEN: notes.append("pin on %s" % Surface.Type.keys()[pin_s])
		# green slope round the pin (8 m)
		var hx := (t.height_at(pin.x + 4, pin.z) - t.height_at(pin.x - 4, pin.z)) / 8.0
		var hz := (t.height_at(pin.x, pin.z + 4) - t.height_at(pin.x, pin.z - 4)) / 8.0
		var slope := Vector2(hx, hz).length()
		if slope > 0.04: notes.append("pin slope %.1f%%" % (slope * 100))
		var L := dh.length_m()
		if (h.par == 3 and L > 230) or (h.par == 4 and (L < 200 or L > 480)) or (h.par == 5 and L < 380): notes.append("par %d at %.0f m" % [h.par, L])
		var nf0: int = reach.failures.size()
		reach._check_hole(c.course_name, h)
		if reach.failures.size() > nf0: notes.append("UNREACHABLE " + reach.failures[-1].get_slice("(", 1))
		# trees within 8 m of the line tee->route->pin
		var line := PackedVector2Array([Vector2(h.tee.x, h.tee.z)])
		for r in dh.route: line.append(r)
		line.append(Vector2(pin.x, pin.z))
		var blocked := 0
		var surf := {}
		for o in c.objects:
			if not str(o.id).begins_with("tree") : continue
			var p := Vector2(o.position.x, o.position.z)
			for k in line.size() - 1:
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p, line[k], line[k + 1])) < 8.0 and p.distance_to(line[0]) > 15.0:
					blocked += 1
					var su := t.surface_at(p.x, p.y)
					surf[su] = int(surf.get(su, 0)) + 1
					break
		if blocked > 0: notes.append("%d trees on the line %s" % [blocked, str(surf.keys().map(func(k: int) -> String: return "%s:%d" % [Surface.Type.keys()[k], surf[k]]))])
		if not notes.is_empty(): bad += 1
		lines.append("  hole %2d par %d %4.0f m: %s" % [i + 1, h.par, L, "ok" if notes.is_empty() else ", ".join(notes)])
	# shapes
	var tiny := 0
	var selfx := 0
	for s in c.shapes:
		var ring := s.outline()
		if ring.size() < 3: continue
		if absf(_area(ring)) < 2.0: tiny += 1
		if Geometry2D.triangulate_polygon(ring).is_empty(): selfx += 1
	print("AUDIT %s: %d holes, %d with problems; shapes %d (tiny %d, bad polygons %d), trees %d, buildings %d, paths %d, area %s" % [c.course_name, data.holes.size(), bad, c.shapes.size(), tiny, selfx, c.objects.size(), c.buildings.size(), c.paths.size(), c.area.size])
	for l in lines: print(l)

static func _area(r: PackedVector2Array) -> float:
	var a := 0.0
	for i in r.size():
		a += r[i].cross(r[(i + 1) % r.size()])
	return a * 0.5


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		audit(DesignedCourse.load_file(args[0]))
		quit()
