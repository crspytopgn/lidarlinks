extends RefCounted
## Every hole of every built-in course can be played: from the fairway line
## 70 and 130 m out (and a par 3's tee), full and part shots with the
## clubs for that distance, aimed at the pin, stop on the green at least
## twice.
## A green perched behind a wall no ball can clear (Red Spire's 2nd once sat
## 35 m up a sheer mesa) fails here.

const DISTANCES := [70.0, 130.0]
const POWERS := [0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9, 0.95, 1.0]

var failures: Array[String] = []


func check(cond: bool, what: String) -> void:
	if not cond:
		failures.append(what)


func run_all() -> Array[String]:
	AssetProviders.ensure_defaults()
	var paths: Array[String] = [PlaceholderCourseLoader.FILE]
	for p: String in PlaceholderCourseLoader.EPIC:
		paths.append(p)
	for path in paths:
		var course := AssetProviders.load_course(path)
		check(course != null and not course.holes.is_empty(), "%s loads" % path)
		if course == null:
			continue
		for hole in course.holes:
			_check_hole(path.get_file().get_basename(), hole)
	return failures


## Points on the hole's line `d` metres back from the pin (walking the route
## from the green toward the tee); null past the tee.
static func back_along(hole: HoleData, pin: Vector3, d: float) -> Variant:
	var line: Array[Vector2] = [Vector2(pin.x, pin.z)]
	for i in range(hole.route.size() - 1, -1, -1):
		if hole.route[i].distance_to(line[line.size() - 1]) > 5.0:
			line.append(hole.route[i])
	var tee := Vector2(hole.tee.x, hole.tee.z)
	if tee.distance_to(line[line.size() - 1]) > 5.0:
		line.append(tee)
	var left := d
	for i in line.size() - 1:
		var seg := line[i + 1] - line[i]
		if seg.length() >= left:
			var p := line[i] + seg.normalized() * left
			return Vector3(p.x, 0.0, p.y)
		left -= seg.length()
	return null


func _check_hole(course_name: String, hole: HoleData) -> void:
	var model := AssetProviders.shot_model
	var clubs := Club.standard_set()
	var t := hole.terrain
	var pin := hole.pins[0] if hole.pins.size() > 0 else hole.pin
	pin.y = t.height_at(pin.x, pin.z)
	var froms: Array[Vector3] = []
	for d: float in DISTANCES:
		var p: Variant = back_along(hole, pin, d)
		if p != null:
			froms.append(p)
	if hole.par == 3:
		froms.append(hole.tee)
	var tried := 0
	var total := 0
	var report := PackedStringArray()
	for from in froms:
		from.y = t.height_at(from.x, from.z)
		var lie := t.surface_at(from.x, from.z)
		if lie in [Surface.Type.WATER, Surface.Type.OUT_OF_BOUNDS]:
			continue
		if from.distance_to(hole.tee) < 1.0:
			lie = Surface.Type.TEE
		var d := Vector2(pin.x - from.x, pin.z - from.z).length()
		var aim := rad_to_deg(atan2(pin.x - from.x, pin.z - from.z))
		var on := 0
		for c in clubs:
			if c.is_putter or c.total_m < d * 0.9 or c.total_m > d * 1.5:
				continue
			for p: float in POWERS:
				if model is LinksShotModel:
					(model as LinksShotModel).computer = true
					(model as LinksShotModel).computer_ratings = null
				var r := model.simulate(model.launch(c, p, 0.0, aim, lie, from), t, pin, Vector3.ZERO)
				if r.outcome != ShotResult.Outcome.WATER and r.outcome != ShotResult.Outcome.OUT_OF_BOUNDS \
						and t.surface_at(r.rest.x, r.rest.z) == Surface.Type.GREEN:
					on += 1
		tried += 1
		total += on
		report.append("%.0f m: %d" % [d, on])
	# A hard green takes a few: Glacier Crown's 13th, a shallow plate over
	# water, takes 2 (the standard model CI runs rolls a mid iron about 25 m
	# on a green, where Links stops it in a few). The impossible ones all
	# scored 0 or 1: Red Spire's 2nd behind its 35 m wall, Glacier Crown's
	# greens tilted 10 to 19 % or behind a grove of pines.
	check(tried >= 1 and total >= 2, "%s hole %d: the green can't be reached (shots on it from %s)" % [course_name, hole.number, ", ".join(report)])
