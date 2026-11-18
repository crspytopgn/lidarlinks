extends SceneTree
# Dev tool: what a built real course shows from above, for look_check.py
# to compare with an aerial picture of the real place. Writes
# <out>.png (one byte a cell, the codes below) and <out>.json (the grid's
# geo corners). Run: godot --headless --path game -s
# $PWD/tools/realcourse_bench/look_export.gd -- course.olc out
#
# Codes: 0 mown grass, 1 fescue (deep rough), 2 sand, 3 water, 4 trees,
# 5 outside the course's own ground (the landscape: land), 6 landscape
# water (under the sea or lake level), 7 the course's ground but more than
# NEAR from any fairway, green, tee or bunker (roads, houses, fields),
# 8 mapped rough.

const CELL := 6.0
const MARGIN := 300.0  ## metres of the landscape beyond the course looked at
const NEAR := 50.0


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	AssetProviders.ensure_defaults()
	var c := DesignedCourse.load_file(a[0])
	var frame := GeoFrame.new(float(c.source.get("lat", 0.0)), float(c.source.get("lon", 0.0)))
	var data := c.to_course_data()
	var t: CourseTerrain = data.holes[0].terrain
	var base := float(c.source.get("base_height", 0.0))
	var sea := Landscape.sea_level(c)
	var box := c.area.grow(MARGIN)
	var w := ceili(box.size.x / CELL)
	var h := ceili(box.size.y / CELL)
	var img := Image.create(w, h, false, Image.FORMAT_R8)
	# Tree crowns by cell.
	var crowns := {}
	for o in c.objects:
		var q := Vector2i(((Vector2(o.position.x, o.position.z) - box.position) / CELL).floor())
		crowns[q] = true
	var land: Dictionary = c.landscape
	for j in h:
		for i in w:
			var p := box.position + (Vector2(i, j) + Vector2(0.5, 0.5)) * CELL
			var code := 0
			if c.area.has_point(p):
				var s := t.surface_at(p.x, p.y)
				if s == Surface.Type.WATER:
					code = 3
				elif s == Surface.Type.SAND:
					code = 2
				elif crowns.has(Vector2i(i, j)):
					code = 4
				elif s == Surface.Type.DEEP_ROUGH:
					code = 1
				elif s == Surface.Type.ROUGH:
					code = 8
				elif s in [Surface.Type.FAIRWAY, Surface.Type.GREEN, Surface.Type.TEE, Surface.Type.FRINGE] and near_play(c, p):
					code = 9
			else:
				code = 5
				if not is_nan(sea) and not land.is_empty() and _land_height(land, p) < sea:
					code = 6
			img.set_pixel(i, j, Color8(code, 0, 0))
	# Cells near the play areas: the course itself.
	var near := PackedByteArray()
	near.resize(w * h)
	var reach := ceili(NEAR / CELL)
	# The mapped play shapes themselves (the ground between them reads as
	# fairway in surface_at when nothing else covers it).
	for s in c.shapes:
		if not s.is_valid() or not s.surface in [Surface.Type.FAIRWAY, Surface.Type.GREEN, Surface.Type.TEE, Surface.Type.SAND]:
			continue
		var b: Rect2 = s.bounds()
		var q0 := Vector2i(((b.position - box.position) / CELL).floor())
		var q1 := Vector2i(((b.end - box.position) / CELL).ceil())
		for j in range(maxi(0, q0.y), mini(h, q1.y + 1)):
			for i in range(maxi(0, q0.x), mini(w, q1.x + 1)):
				if near[j * w + i] == 0 and s.contains(box.position + (Vector2(i, j) + Vector2(0.5, 0.5)) * CELL):
					near[j * w + i] = 1
	# Grown by `reach` cells each way (a square, one pass across, one down).
	for pass_n in 2:
		var grown := PackedByteArray()
		grown.resize(w * h)
		for j in h:
			for i in w:
				if near[j * w + i] == 0:
					continue
				for d in range(-reach, reach + 1):
					var ii := i + d if pass_n == 0 else i
					var jj := j if pass_n == 0 else j + d
					if ii >= 0 and jj >= 0 and ii < w and jj < h:
						grown[jj * w + ii] = 1
		near = grown
	for j in h:
		for i in w:
			var code := img.get_pixel(i, j).r8
			if (code <= 2 or code >= 8) and near[j * w + i] == 0:
				img.set_pixel(i, j, Color8(7, 0, 0))
	img.save_png(a[1] + ".png")
	# Row 0 is box.position.y (south... whichever way +z runs): give the
	# geo position of each corner cell's centre.
	var corners := {}
	for k: String in ["00", "10", "01", "11"]:
		var p := box.position + Vector2((w - 1) * int(k[0]) + 0.5, (h - 1) * int(k[1]) + 0.5) * CELL
		corners[k] = [frame.lat_of(p), frame.lon_of(p)]
	var fairway := []
	for s in c.shapes:
		if s.surface == Surface.Type.FAIRWAY and s.is_valid():
			var b := s.bounds()
			var q := ((b.get_center() - box.position) / CELL).floor()
			if s.contains(b.get_center()):
				fairway.append([int(q.x), int(q.y)])
	var f := FileAccess.open(a[1] + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"w": w, "h": h, "cell": CELL, "corners": corners, "fairway_cells": fairway, "name": c.course_name, "sea": sea if not is_nan(sea) else null}))
	f.close()
	quit()


static func _land_height(land: Dictionary, p: Vector2) -> float:
	var o: Vector2 = land["origin"]
	var cell := float(land["cell"])
	var cols := int(land["cols"])
	var rows := int(land["rows"])
	var hs: PackedFloat32Array = land["heights"]
	var i := clampi(roundi((p.x - o.x) / cell), 0, cols - 1)
	var j := clampi(roundi((p.y - o.y) / cell), 0, rows - 1)
	return hs[j * cols + i]


## True inside a mapped fairway, green or tee (surface_at also calls the
## unmapped ground between them fairway).
static func near_play(c: DesignedCourse, p: Vector2) -> bool:
	for s in c.shapes:
		if s.surface in [Surface.Type.FAIRWAY, Surface.Type.GREEN, Surface.Type.TEE] and s.bounds().has_point(p) and s.contains(p):
			return true
	return false
