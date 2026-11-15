class_name DesignedCourse
extends RefCounted
## A course made in the course designer: a height grid sculpted by hand,
## painted surface shapes, holes and trees. Saved as JSON (`.olc`, see
## docs/course-designer.md) under user://courses/, and played through
## DesignedCourseLoader like any other course.

const FORMAT := "openlinks-course"
const VERSION := 1
const EXTENSION := "olc"
const FOLDER := "user://courses"
const CELL := 2.0  ## metres between height samples
const MAX_HEIGHT := 150.0  ## heights are kept within +-this, in metres
const HEIGHT_ENCODING := "cm-delta-s16-deflate-base64"
## Course sizes offered for a new course, in metres.
const SIZES := [Vector2(600, 600), Vector2(1000, 800), Vector2(1400, 1000)]
const SIZE_NAMES := ["Small (600 x 600 m)", "Medium (1000 x 800 m)", "Large (1400 x 1000 m)"]
const TREE_IDS := ["tree_pine", "tree_broadleaf", "bush"]
const TREE_NAMES := ["Pine", "Broadleaf", "Bush"]
## How many of TREE_IDS are trees, for a mixed planting.
const TREE_KINDS := 2
## Metres round a hole within which its objects are placed one by one.
const HOLE_REACH := 60.0
## Trees further than this from the hole's line are only ever seen as
## impostors (a camera near the line is past the impostor distance from
## them), so the round draws them as impostors only: the deep woods of a
## forest course then cost almost nothing.
const FULL_TREE_REACH := 130.0

var course_name := "New course"
var author := ""
## The playable area, x and z. Everything outside is out of bounds.
var area := Rect2(-500, -400, 1000, 800)
var cols := 0
var rows := 0
## Ground heights before the shapes shape them (bunkers, ponds, tee pads).
var heights := PackedFloat32Array()
var shapes: Array[CourseShape] = []
var holes: Array[DesignedHole] = []
## Trees and other library objects; position.y is filled in from the terrain.
var objects: Array[PlacedObject] = []
## Cart paths and bridges.
var paths: Array[CoursePath] = []
## Field walls (dry-stone and mortared), each a line of (x, z) points:
## scenery, drawn by StoneWalls.
var walls: Array[PackedVector2Array] = []
## Buildings (the clubhouse, houses along the boundary), drawn by
## CourseBuildings and solid to the ball.
var buildings: Array[CourseBuilding] = []
## What the course knows about each library object it uses (DesignerObjects
## measures them when the player's files are there), so a course shared with
## someone without the files still has the right obstacles and stand-ins.
var object_info := {}
## Data credits a course made from real-world data must keep (the
## OpenStreetMap licence asks for its attribution), shown in the designer.
var credits := ""
## Dressed for a tournament (grandstands, ropes, crowds) rather than an
## everyday local club, which a course made in the designer or from a
## real club is unless its maker says so. Saved as "venue".
var tournament := false
## Where a real course came from: {"kind": "openstreetmap", "lat", "lon",
## "base_height"} (see docs/real-courses.md). Empty for hand-made courses.
var source := {}
## Where in the world it is set (Biome: "" parkland, "desert", "snow",
## "tropical"): the ground's colours between the holes, plants and the land
## round about.
var biome := ""
## The real land round the course, drawn to the horizon (Landscape): its
## grid's corner `origin` (x, z), `cell` metres between samples, `cols`,
## `rows` and `heights` (metres, on the same datum as `heights`). Empty
## for courses without one. Saved as given; the designer doesn't edit it.
var landscape := {}
var _landscape_saved := {}
## Sheer rock walls round raised ground (mesas sculpted into the heights):
## each a closed outline (x, z) at the foot of the wall's top edge, drawn
## by RockFormations as a bedded cliff. The heights make the wall itself.
var cliffs: Array[PackedVector2Array] = []
var _photo: Image
var _photo_tried := false
var _cover: Image
var _cover_tried := false


## A flat course of the given size, centred on the origin.
static func blank(size: Vector2) -> DesignedCourse:
	var c := DesignedCourse.new()
	c.area = Rect2(-size * 0.5, size)
	c._alloc()
	return c


## A new course with gently rolling ground and one finished par 4, so there
## is something to play and edit straight away.
static func starter(size := Vector2.ZERO) -> DesignedCourse:
	var c := blank(size if size != Vector2.ZERO else SIZES[1])
	for j in c.rows:
		for i in c.cols:
			var x := c.area.position.x + i * CELL
			var z := c.area.position.y + j * CELL
			c.heights[j * c.cols + i] = (2.2 * sin(x * 0.012 + 0.7) * cos(z * 0.010 + 1.3)
				+ 1.0 * sin((x + z) * 0.03 + 2.1) + 0.4 * sin(x * 0.07 - z * 0.05))
	var z0 := c.area.position.y + 80.0
	var hole := DesignedHole.new()
	hole.par = 4
	hole.tees = PackedVector2Array([Vector2(0, z0), Vector2(2, z0 + 25), Vector2(4, z0 + 50)])
	hole.route = PackedVector2Array([Vector2(8, z0 + 250)])
	hole.pin = Vector2(-18, z0 + 368)
	c.holes.append(hole)
	c.shapes.append(CourseShape.oval(Surface.Type.TEE, Vector2(2, z0 + 25), Vector2(5, 33)))
	c.shapes.append(CourseShape.strip(Surface.Type.FAIRWAY,
		PackedVector2Array([Vector2(2, z0 + 90), Vector2(8, z0 + 250), Vector2(-14, z0 + 345)]), 36.0))
	c.shapes.append(CourseShape.oval(Surface.Type.GREEN, Vector2(-16, z0 + 365), Vector2(14, 18), 0.4, 10))
	c.shapes.append(CourseShape.oval(Surface.Type.SAND, Vector2(26, z0 + 262), Vector2(6, 10), 0.3))
	c.shapes.append(CourseShape.oval(Surface.Type.SAND, Vector2(-36, z0 + 358), Vector2(5, 9), -0.2))
	c.shapes.append(CourseShape.oval(Surface.Type.WATER, Vector2(-42, z0 + 190), Vector2(22, 30), 0.5, 10))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2003
	var placed := 0
	while placed < 90:
		var x := rng.randf_range(-110.0, 110.0)
		var z := rng.randf_range(z0 - 30.0, z0 + 420.0)
		var p := Vector2(x, z)
		var clear := true
		for s in c.shapes:
			clear = clear and s.signed_distance(p) > 14.0
		if not clear:
			continue
		c.objects.append(PlacedObject.new(TREE_IDS[rng.randi() % TREE_KINDS], Vector3(x, 0, z), rng.randf_range(0, 360), rng.randf_range(0.8, 1.3)))
		placed += 1
	c.course_name = "My course"
	return c


func _alloc() -> void:
	cols = int(round(area.size.x / CELL)) + 1
	rows = int(round(area.size.y / CELL)) + 1
	heights = PackedFloat32Array()
	heights.resize(cols * rows)


## Height before shapes, bilinear between samples.
func base_height(x: float, z: float) -> float:
	var u := clampf((x - area.position.x) / CELL, 0.0, cols - 1.001)
	var v := clampf((z - area.position.y) / CELL, 0.0, rows - 1.001)
	var i := int(u)
	var j := int(v)
	var fu := u - i
	var fv := v - j
	var k := j * cols + i
	var a := lerpf(heights[k], heights[k + 1], fu)
	var b := lerpf(heights[k + cols], heights[k + cols + 1], fu)
	return lerpf(a, b, fv)


## Sample (i, j) nearest the point, clamped to the grid.
func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(roundi((p.x - area.position.x) / CELL), 0, cols - 1),
		clampi(roundi((p.y - area.position.y) / CELL), 0, rows - 1))


func sample_pos(i: int, j: int) -> Vector2:
	return area.position + Vector2(i, j) * CELL


## The ground under every sample within `radius` of `centre` is changed by
## `op` ("raise", "lower", "smooth", "flatten"); `amount` is metres at the
## centre for raise and lower, 0 to 1 for the others. `level` is the height
## to flatten to. Returns the changed samples as a rect of cells.
func sculpt(op: String, centre: Vector2, radius: float, amount: float, level := 0.0) -> Rect2i:
	var lo := cell_of(centre - Vector2.ONE * radius)
	var hi := cell_of(centre + Vector2.ONE * radius)
	var src := heights.duplicate() if op == "smooth" else heights
	for j in range(lo.y, hi.y + 1):
		for i in range(lo.x, hi.x + 1):
			var d := sample_pos(i, j).distance_to(centre)
			if d > radius:
				continue
			# Smooth falloff: full at the centre, nothing at the edge.
			var w := 0.5 + 0.5 * cos(PI * d / radius)
			var k := j * cols + i
			var h := heights[k]
			match op:
				"raise":
					h += amount * w
				"lower":
					h -= amount * w
				"flatten":
					h = lerpf(h, level, clampf(amount, 0.0, 1.0) * w)
				"smooth":
					var sum := 0.0
					var n := 0
					for dj in range(-2, 3):
						for di in range(-2, 3):
							var ii := clampi(i + di, 0, cols - 1)
							var jj := clampi(j + dj, 0, rows - 1)
							sum += src[jj * cols + ii]
							n += 1
					h = lerpf(h, sum / n, clampf(amount, 0.0, 1.0) * w)
			heights[k] = clampf(h, -MAX_HEIGHT, MAX_HEIGHT)
	return Rect2i(lo, hi - lo + Vector2i.ONE)


## The smallest shape containing `p` (a green rather than the fairway
## round it), or -1.
func shape_at(p: Vector2) -> int:
	var best := -1
	var best_area := INF
	for i in shapes.size():
		if shapes[i].contains(p) and shapes[i].area() < best_area:
			best = i
			best_area = shapes[i].area()
	return best


## What grows at `p` besides turf (CourseShape.cover): the smallest shape
## with a cover that contains it, or "".
func cover_at(p: Vector2) -> String:
	var best := ""
	var best_area := INF
	for s in shapes:
		if not s.cover.is_empty() and s.bounds().has_point(p) and s.contains(p) and s.area() < best_area:
			best = s.cover
			best_area = s.area()
	return best


## Trees within `radius` of `p`, nearest first.
func objects_near(p: Vector2, radius: float) -> Array[int]:
	var out: Array[int] = []
	for i in objects.size():
		if Vector2(objects[i].position.x, objects[i].position.z).distance_to(p) <= radius:
			out.append(i)
	out.sort_custom(func(a: int, b: int) -> bool:
		return Vector2(objects[a].position.x, objects[a].position.z).distance_squared_to(p) < Vector2(objects[b].position.x, objects[b].position.z).distance_squared_to(p))
	return out


## What the round plays: one HoleData per hole with at least one tee, all
## sharing one DesignedTerrain.
func to_course_data() -> CourseData:
	var terrain := DesignedTerrain.new(self)
	var data := CourseData.new()
	data.course_name = course_name
	data.tournament = tournament
	data.biome = biome
	data.landscape = not landscape.is_empty()
	if source.has("lat") and source.has("lon"):
		data.location = Vector2(float(source.lat), float(source.lon))
	for n in holes.size():
		var dh := holes[n]
		if dh.tees.is_empty():
			continue
		var h := HoleData.new()
		h.number = data.holes.size() + 1
		h.par = dh.par
		h.stroke_index = dh.stroke_index
		h.terrain = terrain
		for t in dh.tees:
			h.tees.append(Vector3(t.x, terrain.height_at(t.x, t.y), t.y))
		h.tee = h.tees[0]
		h.pin = Vector3(dh.pin.x, terrain.height_at(dh.pin.x, dh.pin.y), dh.pin.y)
		h.route = dh.route.duplicate()
		h.objects = _objects_for(dh, terrain)
		data.holes.append(h)
	return data


## True if `p` is within HOLE_REACH of the hole's line (back tee, aim
## points, pin): the objects the round places one by one for that hole.
## Trees further off are drawn batched by DesignedTerrain (impostors at a
## distance), which is far cheaper than a node each.
static func near_hole(dh: DesignedHole, p: Vector2, reach := HOLE_REACH) -> bool:
	if dh.tees.is_empty():
		return false
	var prev := dh.tees[0]
	var r2 := reach * reach
	for t in dh.tees:
		if p.distance_squared_to(t) <= r2:
			return true
	for q in dh.route:
		if p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p, prev, q)) <= r2:
			return true
		prev = q
	return p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p, prev, dh.pin)) <= r2


## The hole played as number `number` (holes without a tee are skipped,
## as in to_course_data()), or null.
func played_hole(number: int) -> DesignedHole:
	var n := 0
	for dh in holes:
		if dh.tees.is_empty():
			continue
		n += 1
		if n == number:
			return dh
	return null


## The trees near a hole (the round draws each hole's own objects).
func _objects_for(dh: DesignedHole, terrain: DesignedTerrain) -> Array[PlacedObject]:
	var out: Array[PlacedObject] = []
	for o in objects:
		# Rock formations and cacti are drawn for the whole course at once
		# (DesignedTerrain.build_visual).
		if RockFormations.is_rock(o.id) or DesertPlants.is_plant(o.id):
			continue
		if near_hole(dh, Vector2(o.position.x, o.position.z)):
			var shown := DesignerObjects.stand_in(o, object_info)
			if shown != null:
				shown.position.y = terrain.height_at(o.position.x, o.position.z)
				out.append(shown)
	return out


# --- Saving and loading -------------------------------------------------------

## Without `with_heights` the height grid is left out (for undo, which
## keeps its own copy).
func to_dict(with_heights := true) -> Dictionary:
	var shape_list: Array = []
	for s in shapes:
		if s.is_valid():
			shape_list.append(s.to_dict())
	var hole_list: Array = []
	for h in holes:
		hole_list.append(h.to_dict())
	var path_list: Array = []
	for p in paths:
		if p.is_valid():
			path_list.append(p.to_dict())
	refresh_object_info(with_heights)
	var object_list: Array = []
	for o in objects:
		object_list.append({"id": o.id, "x": snappedf(o.position.x, 0.01), "z": snappedf(o.position.z, 0.01),
			"yaw": snappedf(o.yaw_deg, 0.1), "scale": snappedf(o.scale, 0.01)})
	var out := {
		"format": FORMAT,
		"version": VERSION,
		"name": course_name,
		"author": author,
		"area": [area.position.x, area.position.y, area.size.x, area.size.y],
		"cell": CELL,
		"heights": _encode_heights() if with_heights else {},
		"shapes": shape_list,
		"holes": hole_list,
		"objects": object_list,
		"paths": path_list,
		"walls": walls.map(func(w: PackedVector2Array) -> Array:
			var flat := []
			for p in w:
				flat.append_array([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
			return flat),
		"object_info": object_info.duplicate(true),
		"credits": credits,
		"venue": "tournament" if tournament else "club",
		"source": source.duplicate(true),
	}
	if not buildings.is_empty():
		out["buildings"] = buildings.map(func(b: CourseBuilding) -> Dictionary: return b.to_dict())
	if not biome.is_empty():
		out["biome"] = biome
	if not _landscape_saved.is_empty():
		out["landscape"] = _landscape_saved.duplicate(true)
	if not cliffs.is_empty():
		var list := []
		for o in cliffs:
			var flat := []
			for p in o:
				flat.append_array([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
			list.append(flat)
		out["cliffs"] = list
	return out


func to_json() -> String:
	return JSON.stringify(to_dict(), "\t")


## Null if `d` isn't a designed course this version can read.
static func from_dict(d: Dictionary) -> DesignedCourse:
	if str(d.get("format", "")) != FORMAT or int(d.get("version", 0)) > VERSION:
		return null
	var a: Array = d.get("area", [])
	if a.size() != 4 or not is_equal_approx(float(d.get("cell", CELL)), CELL):
		return null
	var c := DesignedCourse.new()
	c.course_name = str(d.get("name", "Untitled"))
	c.author = str(d.get("author", ""))
	c.credits = str(d.get("credits", ""))
	c.tournament = str(d.get("venue", "club")) == "tournament"
	if d.get("source", {}) is Dictionary:
		c.source = d.get("source", {})
	c.biome = str(d.get("biome", ""))
	var land: Variant = d.get("landscape", {})
	if land is Dictionary and not (land as Dictionary).is_empty():
		c.landscape = _decode_landscape(land)
		if not c.landscape.is_empty():
			c._landscape_saved = land
	var cl: Variant = d.get("cliffs", [])
	if cl is Array:
		for o: Variant in cl:
			if not o is Array or (o as Array).size() < 8:
				continue
			var pts := PackedVector2Array()
			var flat: Array = o
			for i in range(0, flat.size() - 1, 2):
				pts.append(Vector2(float(flat[i]), float(flat[i + 1])))
			c.cliffs.append(pts)
	c.area = Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
	if c.area.size.x < CELL * 4 or c.area.size.y < CELL * 4 or c.area.size.x > 4000 or c.area.size.y > 4000:
		return null
	c._alloc()
	if not c._decode_heights(d.get("heights", {})):
		return null
	for s: Dictionary in _list(d, "shapes"):
		var shape := CourseShape.from_dict(s)
		if shape.is_valid():
			c.shapes.append(shape)
	for h: Dictionary in _list(d, "holes"):
		c.holes.append(DesignedHole.from_dict(h))
	for o: Dictionary in _list(d, "objects"):
		c.objects.append(PlacedObject.new(str(o.get("id", TREE_IDS[0])), Vector3(float(o.get("x", 0)), 0, float(o.get("z", 0))),
			float(o.get("yaw", 0)), float(o.get("scale", 1))))
	for p: Dictionary in _list(d, "paths"):
		var path := CoursePath.from_dict(p)
		if path.is_valid():
			c.paths.append(path)
	var wall_list: Variant = d.get("walls", [])
	for w: Variant in wall_list if wall_list is Array else []:
		if w is Array and (w as Array).size() >= 4:
			var line := PackedVector2Array()
			for i in range(0, (w as Array).size() - 1, 2):
				line.append(Vector2(float(w[i]), float(w[i + 1])))
			c.walls.append(line)
	var building_list: Variant = d.get("buildings", [])
	for b: Variant in building_list if building_list is Array else []:
		if b is Dictionary:
			var building := CourseBuilding.from_dict(b)
			if building.is_valid():
				c.buildings.append(building)
	var info: Variant = d.get("object_info", {})
	if info is Dictionary:
		for id: Variant in info:
			if info[id] is Dictionary:
				c.object_info[str(id)] = info[id]
	return c


## Measures every library object the course uses that the player's files
## have, keeping what was saved for the ones they don't.
func refresh_object_info(prune := true) -> void:
	var used := {}
	for o in objects:
		used[o.id] = true
	# Undo snapshots keep the rest, so an undone delete gets its info back.
	for id: String in object_info.keys():
		if prune and not used.has(id):
			object_info.erase(id)
	for id: String in used:
		var measured := DesignerObjects.measure(id)
		if not measured.is_empty():
			object_info[id] = measured


## The dictionaries in d[key], skipping anything else.
static func _list(d: Dictionary, key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var v: Variant = d.get(key, [])
	if v is Array:
		for item: Variant in v:
			if item is Dictionary:
				out.append(item)
	return out


static func from_json(text: String) -> DesignedCourse:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return null
	return from_dict(json.data)


## The course's aerial photo, kept beside the course file (source.photo),
## covering exactly `area` with its first pixel at the north-west (+x, +z)
## corner; null if it has none.
func photo_image() -> Image:
	if not _photo_tried:
		_photo_tried = true
		_photo = _sidecar(str(source.get("photo", "")))
	return _photo


## Sets the aerial photo directly (a freshly built course, or tests).
func set_photo(img: Image) -> void:
	_photo = img
	_photo_tried = true


## The land-cover colour picture kept beside the course (source.ground), in
## the photo's layout; used for the ground colours when there is no photo.
func ground_cover_image() -> Image:
	if not _cover_tried:
		_cover_tried = true
		_cover = _sidecar(str(source.get("ground", "")))
	return _cover


func set_ground_cover(img: Image) -> void:
	_cover = img
	_cover_tried = true


## What the ground takes its colours from: the photo, else the land cover.
func tint_image() -> Image:
	var p := photo_image()
	return p if p != null else ground_cover_image()


static func _sidecar(file: String) -> Image:
	var path := FOLDER.path_join(file)
	if file.is_empty() or file.get_file() != file or not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	return img if img != null and not img.is_empty() else null


## Reads a course file, plain JSON or gzipped (the built-in course ships
## gzipped to keep the download small).
static func load_file(path: String) -> DesignedCourse:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() > 2 and bytes[0] == 0x1f and bytes[1] == 0x8b:
		bytes = bytes.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	var text := bytes.get_string_from_utf8()
	if text.is_empty():
		return null
	return from_json(text)


func save_file(path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(to_json())
	f.close()
	return OK


## Where this course is saved by default: user://courses/<name>.olc.
func default_path() -> String:
	var file := course_name.strip_edges().validate_filename()
	if file.is_empty():
		file = "Untitled"
	return FOLDER.path_join(file + "." + EXTENSION)


## Where to save: the file named after the course, unless a different
## course already has it; then "Name 2", "Name 3" and so on. `own` is the
## file this course was opened from or last saved to.
func save_path(own := "") -> String:
	var base := default_path()
	var p := base
	var n := 2
	while p != own and FileAccess.file_exists(p):
		p = "%s %d.%s" % [base.get_basename(), n, EXTENSION]
		n += 1
	return p


## Saved designed courses, sorted by file name.
static func saved_paths() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(FOLDER)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.get_extension().to_lower() == EXTENSION:
			out.append(FOLDER.path_join(f))
	out.sort()
	return out


# Heights in centimetres, each stored as the difference from the one before,
# as little-endian int16, deflated and base64-encoded. Smooth ground makes
# small differences, which compress well.
func _encode_heights() -> Dictionary:
	var raw := PackedByteArray()
	raw.resize(heights.size() * 2)
	var prev := 0
	for k in heights.size():
		var cm := roundi(clampf(heights[k], -MAX_HEIGHT, MAX_HEIGHT) * 100.0)
		raw.encode_s16(k * 2, cm - prev)
		prev = cm
	return {"encoding": HEIGHT_ENCODING, "count": heights.size(), "data": Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))}


func _decode_heights(d: Variant) -> bool:
	if not d is Dictionary or str(d.get("encoding", "")) != HEIGHT_ENCODING or int(d.get("count", -1)) != heights.size():
		return false
	var raw := Marshalls.base64_to_raw(str(d.get("data", ""))).decompress(heights.size() * 2, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != heights.size() * 2:
		return false
	var cm := 0
	for k in heights.size():
		cm += raw.decode_s16(k * 2)
		heights[k] = cm * 0.01
	return true


const LAND_ENCODING := "dm-delta-s16-deflate-base64"


## The landscape as saved (decimetres, each the difference from the one
## before, as little-endian int16, deflated and base64-encoded), or {} if
## it can't be read.
static func _decode_landscape(d: Dictionary) -> Dictionary:
	var o: Variant = d.get("origin", [])
	var cols := int(d.get("cols", 0))
	var rows := int(d.get("rows", 0))
	var cell := float(d.get("cell", 0.0))
	var h: Variant = d.get("heights", {})
	if not o is Array or (o as Array).size() != 2 or cols < 2 or rows < 2 or cols * rows > 4000000 or cell <= 0.0:
		return {}
	if not h is Dictionary or str(h.get("encoding", "")) != LAND_ENCODING or int(h.get("count", -1)) != cols * rows:
		return {}
	var count := cols * rows
	var raw := Marshalls.base64_to_raw(str(h.get("data", ""))).decompress(count * 2, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != count * 2:
		return {}
	var heights := PackedFloat32Array()
	heights.resize(count)
	var dm := 0
	for k in count:
		dm += raw.decode_s16(k * 2)
		heights[k] = dm * 0.1
	return {"origin": Vector2(float(o[0]), float(o[1])), "cell": cell, "cols": cols, "rows": rows, "heights": heights}
