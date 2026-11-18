class_name RealCourseBuilder
extends RefCounted
## Turns a real golf course's OpenStreetMap data (an Overpass API answer
## with `out geom`) and real ground heights into a DesignedCourse, ready to
## play or polish in the course designer. See docs/real-courses.md.
##
##     var b := RealCourseBuilder.new(overpass_json, lat, lon)
##     # fetch heights for b.geo_box() ...
##     var course := b.build(func(lat: float, lon: float) -> float: ...)

const MARGIN := 80.0  ## metres of ground kept round the course boundary
const MAX_SIZE := 3600.0  ## largest course side, metres
const SEARCH_RADIUS := 1500.0  ## metres round the picked point with no boundary
## Trees at most. Woods round a course are drawn far off as impostors
## without sun shadows, so a forest course's lidar woods can be planted in
## full (West Essex, in Epping Forest, has about 25,000 crowns; at 6000 its
## woods beyond the holes were bare grass).
const MAX_TREES := 30000
## Metres from a hole's line within which every lidar crown is planted.
const FULL_WOOD_REACH := 150.0
const LAND_TREE_CLEAR := 25.0  ## metres from a hole's line kept free of land-cover trees
const NEAR_CELL := 8.0  ## metres, for spacing checks between trees
const WOOD_SPACING := 9.0  ## metres between trees in a wood
const ROW_SPACING := 7.0  ## metres between trees in a tree row
const LOW_GROUND := -12.0  ## heights below this (sea floor) are raised to it
const MAX_POINTS := 90  ## control points per area at most
const STREAM_PIECE := 60.0  ## streams are split so each piece has its own water line
const STREAM_PIECE_DROP := 0.3  ## metres a piece's ground may fall along it
const CHAIN_REACH := 150.0  ## metres from a green to the next hole's tee, chaining unnumbered holes
const CHAIN_REACH_FAR := 400.0  ## then joining what's left of the chains
const GREEN_BANK := 3.0  ## metres of dry bank kept round a green in a pond
const TEE_BANK := 2.0
const BRIDGE := 3.0  ## metres: the causeway out to a green inside a pond
## Metres either side of a hole's line of play kept free of found trees
## (crowns the lidar or photo put on the line: Hirono's 12th had 93).
const LINE_CLEAR := 8.0
## Work per build step (build_steps): height samples, and buildings.
const HEIGHT_SAMPLES_PER_STEP := 40000
const BUILDINGS_PER_STEP := 120
const MAX_GREEN_STEPS := 24  ## the greens are graded over this many steps
const CREDITS := "Course layout from OpenStreetMap, (c) OpenStreetMap contributors, ODbL 1.0 (openstreetmap.org/copyright). Ground heights from the Terrain Tiles on AWS Open Data (Mapzen), which merge national lidar and open elevation data; see docs/real-courses.md for each source."

## Simplification tolerance per surface, metres.
const TOLERANCE := {
	Surface.Type.GREEN: 0.3, Surface.Type.TEE: 0.3, Surface.Type.SAND: 0.3,
	Surface.Type.FRINGE: 0.4, Surface.Type.FAIRWAY: 0.6, Surface.Type.ROUGH: 1.0,
	Surface.Type.WATER: 0.8, Surface.Type.DEEP_ROUGH: 1.5, Surface.Type.OUT_OF_BOUNDS: 1.5,
}
const GOLF_SURFACES := {
	"green": Surface.Type.GREEN, "tee": Surface.Type.TEE, "fairway": Surface.Type.FAIRWAY,
	"bunker": Surface.Type.SAND, "water_hazard": Surface.Type.WATER,
	"lateral_water_hazard": Surface.Type.WATER, "rough": Surface.Type.ROUGH,
	"fringe": Surface.Type.FRINGE, "out_of_bounds": Surface.Type.OUT_OF_BOUNDS,
}
const STREAM_WIDTHS := {"river": 12.0, "canal": 8.0, "stream": 3.0, "ditch": 1.5, "drain": 1.5}

var course_name := ""
var frame: GeoFrame
var area := Rect2()
## What was found, for the status line: holes, areas, trees, paths.
var summary := {}
## Trees planted at most (lower for phones and tablets in the browser).
var max_trees := MAX_TREES

var _pick := Vector2.ZERO  ## the picked point, local
var _boundary: Array[PackedVector2Array] = []  ## golf course outlines, local
var _polys: Array[Dictionary] = []  ## {"surface", "ring"} or {"wood", "ring", "leaf"}
var _holes: Array[Dictionary] = []  ## {"ref", "par", "line"}
var _trees: Array[Dictionary] = []  ## {"p", "leaf", "height"}
var _rows: Array[Dictionary] = []  ## tree rows: {"line", "leaf"}
var _streams: Array[Dictionary] = []  ## {"line", "width"}
## OpenStreetMap barrier values drawn as stone walls.
const WALLS := ["wall", "dry_stone_wall", "stone_wall"]
var _paths: Array[Dictionary] = []  ## {"line", "width", "bridge"}: cart paths and roads
var _walls: Array[PackedVector2Array] = []  ## field walls
var _pins: PackedVector2Array = []
var _buildings: Array[Dictionary] = []  ## {"ring", "box"}, grown 2 m
var _footprints: Array[Dictionary] = []  ## {"ring", "tags"}: building outlines as mapped
## The lidar's surface model, Callable(lat, lon) -> metres above sea level
## (NAN where it has none), for the buildings' real heights; or none.
var surface := Callable()
## True when the ground heights are lidar (fine enough to see a ditch).
var lidar_ground := false
var _region := ""  ## ScannedSurfaces region of the course, for buildings

## Extra trees found by the fetcher, planted after the mapped ones: from
## the lidar canopy height ({"lat", "lon", "height"}), and from the aerial
## photo (course points). With lidar trees, woods aren't filled by guesswork.
var lidar_trees: Array[Dictionary] = []
var photo_trees := PackedVector2Array()
## Trees from the land cover (LandCover.tree_points), used when there are
## no lidar or photo trees, outside the mapped woods.
var land_trees := PackedVector2Array()
## The course photo (AerialPhotos.course_photo), for finding greens,
## fairways and bunkers the map lacks.
var photo: Image
## Close-up photos round greens the map leaves unfinished, for finding the
## green and its bunkers: {"image", "area"} (see detail_spots()).
var details: Array[Dictionary] = []
var _guessed: Array[Dictionary] = []  ## CourseGuesser's shapes: {"ring", "box"}
## With several courses at one club (golf:course:name on the holes),
## build only this one; empty builds every hole.
var course_filter := ""
## Extra credits for the data sources the fetcher used.
var extra_credits: PackedStringArray = []
## Metres to smooth the ground over: coarse open elevation tiles (no lidar)
## are speckled and step at their tile edges (CoursePlayability).
var ground_smooth := 0.0
## The step the ground's source was rounded to (TerrainTiles.height_step):
## its terraces are eased out (CoursePlayability.unterrace).
var ground_step := 0.0
## What CoursePlayability changed in the last build: {"greens", "tees", "par3_tees"}.
var playability := {}
## Every golf course outline in the map: {"name", "box", "rings"}.
var _all_boundaries: Array[Dictionary] = []
## Lines of play (each tee along its route to the pin) kept clear of the
## trees the lidar, photo or land cover found.
var _lines := {}  ## line_cells() of them
var _clear_cells := {}  ## box_cells() of the play areas and buildings trees keep off
var _wood_cells := {}  ## box_cells() of the woods, for _leaf_at
var _ground_cache := PackedFloat32Array()  ## the heights as read, for the club's other courses
var _ground_base := 0.0
var _rng := RandomNumberGenerator.new()
var _near := {}  ## Vector2i cell -> planted tree points


## `data` is the Overpass answer; (lat, lon) is the place picked, which
## chooses the golf course when there are several.
func _init(data: Dictionary, lat: float, lon: float, p_name := "") -> void:
	course_name = p_name
	_rng.seed = hash(Vector2(lat, lon))
	var elements: Array = data.get("elements", []) if data.get("elements", []) is Array else []
	# A first frame at the picked point finds the boundary; the final frame
	# is centred on the course so the area sits round the origin.
	frame = GeoFrame.new(lat, lon)
	var boundaries := _find_boundaries(elements)
	_all_boundaries = boundaries
	var box := Rect2()
	var best := {}
	if not boundaries.is_empty():
		best = _pick_boundary(boundaries, elements, p_name)
		box = best["box"]
		if course_name.is_empty():
			course_name = str(best["name"])
	else:
		box = _feature_box(elements)
	if box.size == Vector2.ZERO:
		box = Rect2(-Vector2.ONE * 300.0, Vector2.ONE * 600.0)
	box = box.grow(MARGIN)
	var centre := box.get_center()
	var size := Vector2(minf(box.size.x, MAX_SIZE), minf(box.size.y, MAX_SIZE))
	frame = GeoFrame.new(frame.lat_of(centre), frame.lon_of(centre))
	_pick = frame.to_local(lat, lon)
	size = (size / DesignedCourse.CELL).ceil() * DesignedCourse.CELL
	area = Rect2(-size * 0.5, size)
	# Clamp a huge boundary round the picked point.
	if box.size.x > MAX_SIZE or box.size.y > MAX_SIZE:
		var slack := (box.size - size).max(Vector2.ZERO) * 0.5
		var shift := (_pick - area.get_center()).clamp(-slack, slack)
		area.position += shift.snapped(Vector2.ONE * DesignedCourse.CELL)
	if course_name.is_empty():
		course_name = "Real course"
	if not best.is_empty():
		for ring: PackedFloat64Array in best["geo_rings"]:
			_boundary.append(_local_ring(ring))
	for b in _all_boundaries:
		var rings: Array[PackedVector2Array] = []
		for ring: PackedFloat64Array in b["geo_rings"]:
			rings.append(_local_ring(ring))
		b["rings"] = rings
	_read(elements)
	_group_holes()


## The courses at the club when its holes make up more than one (each with
## at least nine holes), most holes first; empty for a single course. When
## only one has nine holes, it alone is named, so the odd holes of another
## course mapped alongside it stay out of it.
func course_names() -> PackedStringArray:
	var counts := {}
	for d in _holes:
		if not str(d["course"]).is_empty():
			counts[d["course"]] = int(counts.get(d["course"], 0)) + 1
	var names: Array = counts.keys().filter(func(n: String) -> bool: return counts[n] >= 9)
	# Most holes first, then the longest (a club's championship course
	# before its second eighteen, Royal County Down's before Annesley).
	var length := {}
	for d in _holes:
		var line: PackedVector2Array = d["line"]
		for k in line.size() - 1:
			length[d["course"]] = float(length.get(d["course"], 0.0)) + line[k].distance_to(line[k + 1])
	# Of two full courses, the one named as the club's main course first
	# (Sunningdale's Old before its longer New).
	var main := {}
	for n: String in names:
		main[n] = 1 if is_main_course(n) else 0
	names.sort_custom(func(a: String, b: String) -> bool:
		if counts[a] != counts[b]:
			return counts[a] > counts[b]
		if main[a] != main[b]:
			return main[a] > main[b]
		return length[a] > length[b] or (length[a] == length[b] and a < b))
	if names.size() == 1 and int(counts[names[0]]) < _holes.size() and _duplicate_refs(_holes):
		return PackedStringArray(names)
	return PackedStringArray(names) if names.size() > 1 else PackedStringArray()


## A map feature's name for the game's English text: its own name, or its
## name:en where the own name is in another script (Dubai Creek's is
## Arabic, with an English name beside it).
static func display_name(t: Dictionary) -> String:
	var own := str(t.get("name", ""))
	var en := str(t.get("name:en", ""))
	if en.is_empty() or own.is_empty():
		return own if not own.is_empty() else en
	var latin := 0
	var other := 0
	for i in own.length():
		var u := own.unicode_at(i)
		if u > 0x24F and u != 0x2019 and u != 0x2013:
			other += 1
		elif u > 0x40:
			latin += 1
	return en if other > latin else own


## True for a name a club gives its main course: its Championship or Old
## course.
static func is_main_course(name: String) -> bool:
	var words := name.to_lower().replace("-", " ").split(" ", false)
	return "championship" in words or "old" in words


## Mapped holes on the chosen course (all its courses for a club).
func hole_count() -> int:
	return _holes.size()


## Gives holes without a golf:course:name the course they belong to, when
## the club's holes repeat their numbers: from the hole's own name ("L'Aigle -
## Trou n°3" at Golf National), a ref like "4/9" (Banff Springs' 9 beside its
## 18), or the smaller course outline round it (Crans-sur-Sierre's two
## courses inside the club's).
func _group_holes() -> void:
	var untagged: Array[Dictionary] = []
	for d in _holes:
		if str(d["course"]).is_empty():
			untagged.append(d)
	var numbered := untagged.any(func(d: Dictionary) -> bool: return _ref_number(str(d["ref"])) < 1000)
	if untagged.size() < 10 or not (_duplicate_refs(untagged) or (untagged.size() > 18 and not numbered)):
		return
	for way: Callable in [_course_from_name, _course_from_ref, _course_from_letter, _course_from_outline]:
		var keys := {}
		for d in untagged:
			var k: String = way.call(d)
			if not k.is_empty():
				keys[k] = int(keys.get(k, 0)) + 1
		# Worth it when it parts the holes into courses without repeats.
		var good := keys.size() >= 2 and keys.values().any(func(n: int) -> bool: return n >= 9)
		if not good:
			continue
		for d in untagged:
			d["course"] = way.call(d)
		return
	if numbered and _duplicate_refs(untagged) and _course_from_numbers(untagged):
		return
	_course_from_chains(untagged)


## Parts a club whose courses are both numbered 1 to 18 with nothing else
## to tell them apart (Whistling Straits, Los Angeles Country Club): each
## number 1 starts a course, and each next number goes to the course whose
## last green is nearest its tee. False when there aren't 2 or more 1sts.
func _course_from_numbers(holes: Array[Dictionary]) -> bool:
	var by_number := {}
	var top := 0
	for d in holes:
		var n := _ref_number(str(d["ref"]))
		if n >= 1000:
			continue
		if not by_number.has(n):
			by_number[n] = []
		(by_number[n] as Array).append(d)
		top = maxi(top, n)
	var firsts: Array = by_number.get(1, [])
	if firsts.size() < 2:
		return false
	var names: Array[String] = []
	var last: Array[Vector2] = []
	for k in firsts.size():
		var name := "%s (course %s)" % [short_name(course_name), "ABCDEFGH"[mini(k, 7)]]
		names.append(name)
		var line: PackedVector2Array = firsts[k]["line"]
		last.append(line[line.size() - 1])
		firsts[k]["course"] = name
	for n in range(2, top + 1):
		var left: Array = (by_number.get(n, []) as Array).duplicate()
		var taken := {}
		while not left.is_empty():
			var best := INF
			var bi := 0
			var bc := 0
			for i in left.size():
				var tee: Vector2 = (left[i]["line"] as PackedVector2Array)[0]
				for c in names.size():
					if taken.has(c) and taken.size() < names.size():
						continue
					var d := last[c].distance_to(tee)
					if d < best:
						best = d
						bi = i
						bc = c
			var hole: Dictionary = left[bi]
			hole["course"] = names[bc]
			var line: PackedVector2Array = hole["line"]
			last[bc] = line[line.size() - 1]
			taken[bc] = true
			left.remove_at(bi)
	for d in holes:
		if str(d["course"]).is_empty():
			d["course"] = names[0]
	return true


## Parts holes with nothing to tell their courses apart (Royal Golf Dar
## Es Salam's 45 have no numbers or names) by how they follow on: each
## green leads to the nearest tee not yet taken within CHAIN_REACH, so the
## holes join into the courses' rounds, numbered in playing order. Chains
## of at least 9 holes become courses; the rest stay with the first.
func _course_from_chains(holes: Array[Dictionary]) -> void:
	var n := holes.size()
	var next := PackedInt32Array()
	var prev := PackedInt32Array()
	next.resize(n)
	prev.resize(n)
	next.fill(-1)
	prev.fill(-1)
	# The near links first, then the broken chains joined up over a longer
	# walk (Dar Es Salam's walks from green to tee run to 220 m).
	for reach in [CHAIN_REACH, CHAIN_REACH_FAR]:
		var pairs: Array = []
		for i in n:
			if next[i] >= 0:
				continue
			var li: PackedVector2Array = holes[i]["line"]
			var end := li[li.size() - 1]
			for j in n:
				if i == j or prev[j] >= 0:
					continue
				var lj: PackedVector2Array = holes[j]["line"]
				var d := end.distance_to(lj[0])
				if d < reach:
					pairs.append([d, i, j])
		pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		for p: Array in pairs:
			var i: int = p[1]
			var j: int = p[2]
			if next[i] >= 0 or prev[j] >= 0:
				continue
			# No loops: j's chain mustn't already lead to i.
			var k := j
			while k >= 0 and k != i:
				k = next[k]
			if k == i:
				continue
			next[i] = j
			prev[j] = i
	var chains: Array = []
	for i in n:
		if prev[i] < 0:
			var chain: Array[int] = []
			var k := i
			while k >= 0:
				chain.append(k)
				k = next[k]
			chains.append(chain)
	# A chain can run on from one course's 18th green to another's 1st tee:
	# longer chains are cut into rounds of 18, a short end kept on the last.
	var rounds: Array = []
	for chain: Array in chains:
		var k := 0
		while chain.size() - k >= 9:
			var size := 18 if chain.size() - k >= 27 else chain.size() - k
			rounds.append(chain.slice(k, k + size))
			k += size
	chains = rounds
	chains.sort_custom(func(a: Array, b: Array) -> bool: return a.size() > b.size())
	var in_rounds := 0
	for chain: Array in chains:
		in_rounds += chain.size()
	if chains.is_empty() or (chains.size() < 2 and n - in_rounds < 9):
		return
	var letter := 0
	for chain: Array in chains:
		if chain.size() < 9:
			continue
		var name := "%s (course %s)" % [short_name(course_name), "ABCDEFGH"[mini(letter, 7)]]
		letter += 1
		for k in chain.size():
			holes[chain[k]]["course"] = name
			holes[chain[k]]["ref"] = str(k + 1)
	# Short leftovers make one more course when there are 9 of them (the
	# third nine), or join the first.
	var spare: Array[Dictionary] = []
	for d in holes:
		if str(d["course"]).is_empty():
			spare.append(d)
	var rest: String = holes[(chains[0] as Array)[0]]["course"]
	if spare.size() >= 9:
		rest = "%s (course %s)" % [short_name(course_name), "ABCDEFGH"[mini(letter, 7)]]
	for k in spare.size():
		spare[k]["course"] = rest
		if spare.size() >= 9:
			spare[k]["ref"] = str(k + 1)


## "12A" gives the club's "A" course (Jockey Club Argentino numbers its
## two courses' holes 1A to 18A and 1C to 18C); empty for a plain number.
func _course_from_letter(d: Dictionary) -> String:
	var m := RegEx.create_from_string("^\\s*\\d+\\s*([A-Za-z]{1,2})\\s*$").search(str(d["ref"]))
	return "%s (course %s)" % [short_name(course_name), m.get_string(1).to_upper()] if m != null else ""


static func _duplicate_refs(holes: Array[Dictionary]) -> bool:
	var seen := {}
	for d in holes:
		var n := _ref_number(d["ref"])
		if n < 1000 and seen.has(n):
			return true
		seen[n] = true
	return false


## The course part of a hole's name: "L'Albatros - Trou n°7" gives
## "L'Albatros"; empty if the name has no number or nothing besides it.
func _course_from_name(d: Dictionary) -> String:
	var n := str(d.get("name", ""))
	var digits := RegEx.create_from_string("\\d+")
	if digits.search(n) == null:
		return ""
	var words := RegEx.create_from_string("(?i)\\b(hole|holes|trou|loch|hoyo|buca|hål|hul|bahn|green|no|nr|n°|#)\\b")
	var rest := words.sub(digits.sub(n, "", true), "", true)
	for ch in ["n°", "#", "°", ".", "(", ")"]:
		rest = rest.replace(ch, " ")
	rest = rest.strip_edges().trim_suffix("-").trim_suffix(":").trim_suffix(",").strip_edges()
	rest = rest.trim_prefix("-").strip_edges()
	if rest.length() < 2:
		return ""
	return "%s, %s" % [short_name(course_name), rest] if not rest.to_lower().contains(course_name.to_lower()) else rest


## A club's name without the words every club has, to name its courses
## by: "The Fairmont Banff Springs Golf Course" gives "Fairmont Banff
## Springs".
static func short_name(club: String) -> String:
	var out := club.strip_edges()
	for w: String in [" Golf Course", " Golf Club", " Golf Links", " Country Club", " Golf & Country Club", " Golf and Country Club", " Golf Resort"]:
		if out.to_lower().ends_with(w.to_lower()):
			out = out.left(out.length() - w.length())
	if out.to_lower().begins_with("the ") and out.length() > 12:
		out = out.substr(4)
	return out


## "4/9" gives "9 holes"; empty for a plain number.
func _course_from_ref(d: Dictionary) -> String:
	var ref := str(d["ref"])
	if not ref.contains("/"):
		return ""
	var of := ref.get_slice("/", 1).strip_edges()
	return "%s (%s holes)" % [short_name(course_name), of] if of.is_valid_int() else ""


## The name of the smallest course outline round the hole's green that
## isn't the whole club's.
func _course_from_outline(d: Dictionary) -> String:
	var line: PackedVector2Array = d["line"]
	var end := line[line.size() - 1]
	var best := ""
	var best_area := INF
	for b in _all_boundaries:
		if str(b["name"]).is_empty() or b["rings"] == _boundary:
			continue
		for r: PackedVector2Array in b["rings"]:
			if Geometry2D.is_point_in_polygon(end, r) and absf(_ring_area(r)) < best_area:
				best_area = absf(_ring_area(r))
				best = str(b["name"])
	return best


## The box the ground heights are needed for: south, west, north, east.
func geo_box() -> Array[float]:
	var lats := [frame.lat_of(area.position), frame.lat_of(area.end)]
	# +x is west, so the area's low x is the east side.
	var lons := [frame.lon_of(area.position), frame.lon_of(area.end)]
	return [lats.min(), lons.min(), lats.max(), lons.max()]


## The course. `height` is a Callable(lat, lon) -> metres above sea level
## (NAN where it has no data, filled from `fallback`).
func build(height: Callable, fallback := Callable()) -> DesignedCourse:
	var c := start_build()
	for step in build_steps(c, height, fallback):
		step.call()
	return c


## An empty course for build_steps to fill.
func start_build() -> DesignedCourse:
	var c := DesignedCourse.new()
	c.course_name = (course_filter if not course_filter.is_empty() else course_name).substr(0, 40)
	c.author = "OpenStreetMap contributors"
	c.credits = CREDITS
	for extra in extra_credits:
		c.credits += " " + extra + "."
	c.source = {"kind": "openstreetmap", "lat": snappedf(frame.lat0, 0.0000001), "lon": snappedf(frame.lon0, 0.0000001)}
	c.area = area
	c._alloc()
	return c


## The build of `c` as steps of a fraction of a second each, called in
## order, so the game can draw frames between them: a club the size of Golf
## National built in one go held the game still for 8 seconds.
func build_steps(c: DesignedCourse, height: Callable, fallback := Callable()) -> Array[Callable]:
	var steps: Array[Callable] = []
	var fill := {"gaps": PackedInt32Array(), "diff": 0.0, "n": 0}
	# The other courses of a club share the ground: it is read once.
	var cached := _ground_cache.size() == c.heights.size()
	var rows := maxi(1, HEIGHT_SAMPLES_PER_STEP / c.cols)
	if not cached:
		for j0 in range(0, c.rows, rows):
			steps.append(_fill_height_rows.bind(c, j0, mini(j0 + rows, c.rows), height, fallback, fill))
	if not cached:
		steps.append(func() -> void:
			_finish_heights(c, fallback, fill)
			if ground_smooth > 0.0:
				CoursePlayability.smooth_ground(c, ground_smooth))
		if ground_step > 0.0:
			steps.append(func() -> void: CoursePlayability.unterrace(c, ground_step))
	steps.append(func() -> void:
		if cached:
			c.heights = _ground_cache.duplicate()
			c.source["base_height"] = _ground_base
		else:
			_ground_cache = c.heights.duplicate()
			_ground_base = c.source["base_height"]
		if lidar_ground:
			_streams = _streams.filter(func(d: Dictionary) -> bool: return not d["small"] or is_open_ditch(d["line"], d["width"], height, frame))
		_add_shapes(c)
		_add_holes(c)
		# Paths first: sandy tracks found in the photo aren't bunkers.
		_add_paths(c)
		_add_walls(c)
		_region = ScannedSurfaces.region_for(Vector2(frame.lat0, frame.lon0), -1))
	for k in range(0, _footprints.size(), BUILDINGS_PER_STEP):
		steps.append(_add_buildings.bind(c, height, k, mini(k + BUILDINGS_PER_STEP, _footprints.size())))
	var counts := {"detected": 0}
	steps.append(func() -> void:
		_guessed.clear()
		for s in CourseGuesser.fill(c, hash(c.course_name), photo, details):
			if s.found:
				counts["detected"] += 1
			var ring := s.outline()
			var r := Rect2(ring[0], Vector2.ZERO)
			for p in ring:
				r = r.expand(p)
			_guessed.append({"ring": ring, "box": r}))
	# As a club's builder would have shaped it: greens that hold a ball
	# (one a step: St Andrews' double greens are big), level tees, par 3s a
	# driver reaches.
	steps.append(func() -> void:
		untangle_shapes(c)
		playability = {"greens": 0, "tees": CoursePlayability.level_tees(c), "par3_tees": CoursePlayability.trim_par3_tees(c)}
		var greens: Array[CourseShape] = []
		for s in c.shapes:
			if s.surface == Surface.Type.GREEN:
				greens.append(s)
		playability["todo"] = greens)
	for k in MAX_GREEN_STEPS:
		steps.append(func() -> void:
			var todo: Array[CourseShape] = playability["todo"]
			for g in range(k, todo.size(), MAX_GREEN_STEPS):
				if CoursePlayability.grade_green(c, todo[g]):
					playability["greens"] += 1)
	steps.append(func() -> void:
		playability.erase("todo")
		playability["pins"] = CoursePlayability.place_pins(c))
	steps.append(func() -> void:
		var lines: Array[PackedVector2Array] = []
		for h in c.holes:
			for t in h.tees:
				var line := PackedVector2Array([t])
				line.append_array(h.route)
				line.append(h.pin)
				lines.append(line)
		_lines = line_cells(lines)
		_add_trees(c)
		var detected: int = counts["detected"]
		summary = {"missing_holes": missing_holes(), "greens_graded": playability["greens"], "holes": c.holes.size(), "areas": c.shapes.size(), "trees": c.objects.size(), "paths": c.paths.size(), "buildings": c.buildings.size(), "guessed": _guessed.size() - detected, "detected": detected})
	return steps


# --- Reading the OpenStreetMap data --------------------------------------------

## Every leisure=golf_course outline: {"name", "box", "geo_rings", "rings"}.
func _find_boundaries(elements: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Variant in elements:
		if not e is Dictionary or str(_tags(e).get("leisure", "")) != "golf_course":
			continue
		var rings := _geo_rings(e)
		if rings.is_empty():
			continue
		var local: Array[PackedVector2Array] = []
		for r in rings:
			local.append(_local_ring(r))
		var box := Rect2(local[0][0], Vector2.ZERO)
		for l in local:
			for p in l:
				box = box.expand(p)
		out.append({"name": display_name(_tags(e)), "box": box, "geo_rings": rings, "rings": local})
	return out


## The course boundary meant: the one named like the place picked, else the
## one with the most mapped holes (up to 18), then the smallest round the
## picked point (the origin of the first frame), then the nearest; so a
## clubhouse found by name next to a pitch-and-putt (Pebble Beach's lodge
## beside The Hay) still gives the real course.
func _pick_boundary(boundaries: Array[Dictionary], elements: Array, place := "") -> Dictionary:
	var ends := PackedVector2Array()
	for e: Variant in elements:
		if e is Dictionary and str(_tags(e).get("golf", "")) == "hole":
			var g := _geo_points(e)
			if g.size() >= 4:
				ends.append(frame.to_local(g[g.size() - 2], g[g.size() - 1]))
	var words := name_words(place)
	var best: Dictionary = boundaries[0]
	var best_score := -INF
	for b in boundaries:
		var holes := 0
		for p in ends:
			for r: PackedVector2Array in b["rings"]:
				if Geometry2D.is_point_in_polygon(p, r):
					holes += 1
					break
		var inside := false
		var d := INF
		for r: PackedVector2Array in b["rings"]:
			if Geometry2D.is_point_in_polygon(Vector2.ZERO, r):
				inside = true
			for i in r.size():
				d = minf(d, Geometry2D.get_closest_point_to_segment(Vector2.ZERO, r[i], r[(i + 1) % r.size()]).length())
		var matched := 0
		var own := name_words(str(b["name"]))
		for w in words:
			if w in own:
				matched += 1
		# Name first, then a real course, then round the point (the
		# smallest), then the nearest.
		var score := matched * 1e8 + mini(holes, 18) * 1e5
		score += 5e4 - minf((b["box"] as Rect2).get_area() / 1e3, 4e4) if inside else -minf(d, 9e4)
		if score > best_score:
			best_score = score
			best = b
	return best


## The distinctive words of a place's name (lower case, without the words
## every club has), for matching it to a course's name.
static func name_words(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var common := ["golf", "club", "course", "links", "country", "the", "and", "royal", "resort", "society", "championship", "real", "campo", "golfe", "golfclub", "des", "del", "los", "las"]
	for w in text.to_lower().replace("-", " ").replace(",", " ").replace("&", " ").replace("'", " ").split(" ", false):
		if w.length() >= 3 and not w in common:
			out.append(w)
	return out


## Bounds of the golf features within SEARCH_RADIUS of the picked point.
func _feature_box(elements: Array) -> Rect2:
	var box := Rect2()
	var first := true
	for e: Variant in elements:
		if not e is Dictionary or not _tags(e).has("golf"):
			continue
		var g := _geo_points(e)
		for k in range(0, g.size(), 2):
			var l := frame.to_local(g[k], g[k + 1])
			if l.length() > SEARCH_RADIUS:
				continue
			box = Rect2(l, Vector2.ZERO) if first else box.expand(l)
			first = false
	return box


func _read(elements: Array) -> void:
	for e: Variant in elements:
		if not e is Dictionary:
			continue
		var t := _tags(e)
		var type := str(e.get("type", ""))
		var golf := str(t.get("golf", ""))
		var natural := str(t.get("natural", ""))
		if type == "node":
			var p := frame.to_local(float(e.get("lat", 0)), float(e.get("lon", 0)))
			if not area.has_point(p):
				continue
			if natural == "tree":
				_trees.append({"p": p, "leaf": str(t.get("leaf_type", "")), "height": _metres(t.get("height", ""))})
			elif golf == "pin":
				_pins.append(p)
			continue
		var closed := _is_area(e)
		if golf == "hole" and type == "way":
			var line := _local_line(_geo_points(e))
			if line.size() >= 2 and _in_course(line):
				_holes.append({"ref": str(t.get("ref", "")), "par": str(t.get("par", "")), "si": str(t.get("handicap", "")),
					"course": str(t.get("golf:course:name", "")), "name": str(t.get("name", "")), "line": line})
		elif golf == "cartpath" or str(t.get("golf_cart", "")) == "designated":
			if not closed:
				_paths.append({"line": _local_line(_geo_points(e)), "width": maxf(_metres(t.get("width", "")), 2.5), "bridge": _is_bridge(t)})
		elif t.has("highway") and type == "way" and not closed:
			# Roads and paved paths through the course: tarmac, played as a
			# cart path (hard bounce and roll, free relief).
			var w := road_width(t)
			if w > 0.0:
				_paths.append({"line": _local_line(_geo_points(e)), "width": w, "bridge": _is_bridge(t)})
		elif GOLF_SURFACES.has(golf) and closed:
			_add_poly(e, {"surface": GOLF_SURFACES[golf]})
		elif natural == "water" or t.has("water") or str(t.get("landuse", "")) in ["reservoir", "basin"]:
			if closed:
				_add_poly(e, {"surface": Surface.Type.WATER})
		elif natural in ["scrub", "heath", "wetland", "dune"] and closed:
			# Played as deep rough; the cover says what grows there.
			_add_poly(e, {"surface": Surface.Type.DEEP_ROUGH, "cover": natural})
		elif (natural == "grassland" or str(t.get("landuse", "")) == "meadow") and closed:
			# Hay meadows round a course: long grass, not
			# the mown rough the course is otherwise drawn with.
			_add_poly(e, {"surface": Surface.Type.DEEP_ROUGH, "cover": "meadow"})
		elif (natural == "wood" or str(t.get("landuse", "")) == "forest") and closed:
			_add_poly(e, {"wood": true, "leaf": str(t.get("leaf_type", ""))})
		elif t.has("building") and closed:
			for g in _geo_rings(e):
				_footprints.append({"ring": _local_ring(g), "tags": t})
				for ring in Geometry2D.offset_polygon(_local_ring(g), 2.0):
					var r := Rect2(ring[0], Vector2.ZERO)
					for p in ring:
						r = r.expand(p)
					if r.intersects(area):
						_buildings.append({"ring": ring, "box": r})
		elif str(t.get("barrier", "")) in WALLS and type == "way":
			_walls.append(_local_line(_geo_points(e)))
		elif natural == "tree_row" and type == "way":
			_rows.append({"line": _local_line(_geo_points(e)), "leaf": str(t.get("leaf_type", ""))})
		elif STREAM_WIDTHS.has(str(t.get("waterway", ""))) and type == "way" and not _underground(t):
			var w := _metres(t.get("width", ""))
			_streams.append({"line": _local_line(_geo_points(e)), "width": w if w > 0.5 else float(STREAM_WIDTHS[str(t["waterway"])]),
				"small": str(t["waterway"]) in ["ditch", "drain"]})


## Adds each outer ring of `e`, clipped to the course area.
func _add_poly(e: Dictionary, info: Dictionary) -> void:
	var rect := PackedVector2Array([area.position, Vector2(area.end.x, area.position.y), area.end, Vector2(area.position.x, area.end.y)])
	for g in _geo_rings(e):
		var ring := _local_ring(g)
		if ring.size() < 3:
			continue
		var r := Rect2(ring[0], Vector2.ZERO)
		for p in ring:
			r = r.expand(p)
		if not r.intersects(area):
			continue
		var pieces: Array[PackedVector2Array] = [ring]
		if not area.encloses(r):
			pieces.clear()
			for clipped in Geometry2D.intersect_polygons(ring, rect):
				pieces.append(clipped)
		for piece in pieces:
			var d := info.duplicate()
			d["ring"] = piece
			_polys.append(d)


## True when a hole line starts or ends inside the chosen course boundary
## (or there is no boundary).
func _in_course(line: PackedVector2Array) -> bool:
	# Both ends on the ground built (a huge club is cut to MAX_SIZE).
	if not area.has_point(line[0]) or not area.has_point(line[line.size() - 1]):
		return false
	if line[0].distance_to(line[line.size() - 1]) < 20.0:
		return false  # a stub, not a hole
	if _boundary.is_empty():
		return true
	for r in _boundary:
		if Geometry2D.is_point_in_polygon(line[0], r) or Geometry2D.is_point_in_polygon(line[line.size() - 1], r):
			return true
	return false


static func _tags(e: Dictionary) -> Dictionary:
	var t: Variant = e.get("tags", {})
	return t if t is Dictionary else {}


## A closed way, or a multipolygon relation, that is an area.
static func _is_area(e: Dictionary) -> bool:
	var type := str(e.get("type", ""))
	if type == "relation":
		return str(_tags(e).get("type", "")) in ["multipolygon", "boundary"]
	if type != "way":
		return false
	var g := _geo_points(e)
	return g.size() >= 8 and _same(g, 0, g, g.size() - 2)


## Lat, lon, lat, lon... of a way's geometry, or of a node. 64-bit, as a
## Vector2 would round them to tens of centimetres.
static func _geo_points(e: Dictionary) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if str(e.get("type", "")) == "node":
		out.append_array([float(e.get("lat", 0)), float(e.get("lon", 0))])
		return out
	var geom: Variant = e.get("geometry", [])
	if geom is Array:
		for p: Variant in geom:
			if p is Dictionary and p.has("lat"):
				out.append_array([float(p["lat"]), float(p["lon"])])
	if str(e.get("type", "")) == "relation":
		var members: Variant = e.get("members", [])
		if members is Array:
			for m: Variant in members:
				if m is Dictionary:
					out.append_array(_geo_points(m))
	return out


## The outer rings of a closed way or a multipolygon relation (as
## _geo_points). Relation members are joined end to end into rings.
static func _geo_rings(e: Dictionary) -> Array[PackedFloat64Array]:
	var out: Array[PackedFloat64Array] = []
	var type := str(e.get("type", ""))
	if type == "way":
		if _is_area(e):
			out.append(_geo_points(e))
		return out
	if type != "relation":
		return out
	var parts: Array[PackedFloat64Array] = []
	var members: Variant = e.get("members", [])
	if not members is Array:
		return out
	for m: Variant in members:
		if m is Dictionary and str(m.get("type", "")) == "way" and str(m.get("role", "outer")) in ["outer", ""]:
			var pts := _geo_points(m)
			if pts.size() >= 4:
				parts.append(pts)
	while not parts.is_empty():
		var ring: PackedFloat64Array = parts.pop_back()
		var grew := true
		while grew and not _same(ring, 0, ring, ring.size() - 2):
			grew = false
			for k in parts.size():
				var p := parts[k]
				var end := ring.size() - 2
				if _same(p, 0, ring, end):
					ring.append_array(p.slice(2))
				elif _same(p, p.size() - 2, ring, end):
					ring.append_array(_reversed(p).slice(2))
				else:
					continue
				parts.remove_at(k)
				grew = true
				break
		if ring.size() >= 8 and _same(ring, 0, ring, ring.size() - 2):
			out.append(ring)
	return out


## True when point i of `a` and point j of `b` (indices into the flat
## arrays) are the same node.
static func _same(a: PackedFloat64Array, i: int, b: PackedFloat64Array, j: int) -> bool:
	return absf(a[i] - b[j]) < 1e-9 and absf(a[i + 1] - b[j + 1]) < 1e-9


static func _reversed(g: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for k in range(g.size() - 2, -1, -2):
		out.append_array([g[k], g[k + 1]])
	return out


func _local_line(geo: PackedFloat64Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in range(0, geo.size() - 1, 2):
		out.append(frame.to_local(geo[k], geo[k + 1]))
	return out


## A closed ring in local metres, without the repeated last point.
func _local_ring(geo: PackedFloat64Array) -> PackedVector2Array:
	var out := _local_line(geo)
	if out.size() > 1 and out[0].distance_to(out[out.size() - 1]) < 0.01:
		out.remove_at(out.size() - 1)
	return out


## A length tag ("12", "12 m", "40'") in metres, or 0.
static func _metres(v: Variant) -> float:
	var s := str(v).strip_edges().to_lower()
	if s.is_empty():
		return 0.0
	var feet := s.ends_with("'") or s.ends_with("ft")
	var n := s.trim_suffix("m").trim_suffix("ft").trim_suffix("'").strip_edges()
	if not n.is_valid_float():
		return 0.0
	return n.to_float() * (0.3048 if feet else 1.0)


# --- Building the course --------------------------------------------------------

## `height` may return NAN where its data has gaps (lidar has none under
## water and some buildings, and stops at borders); those samples take the
## `fallback` heights, shifted by the mean difference between the two where
## both exist, so the seams don't step.
func _fill_height_rows(c: DesignedCourse, j0: int, j1: int, height: Callable, fallback: Callable, fill: Dictionary) -> void:
	var gaps: PackedInt32Array = fill["gaps"]
	var diff: float = fill["diff"]
	var diff_n: int = fill["n"]
	for j in range(j0, j1):
		for i in c.cols:
			var p := c.sample_pos(i, j)
			var lat := frame.lat_of(p)
			var lon := frame.lon_of(p)
			var h := float(height.call(lat, lon))
			var k := j * c.cols + i
			if is_nan(h):
				gaps.append(k)
				h = float(fallback.call(lat, lon)) if fallback.is_valid() else 0.0
			elif fallback.is_valid() and i % 8 == 0 and j % 8 == 0:
				diff += h - float(fallback.call(lat, lon))
				diff_n += 1
			c.heights[k] = h
	fill["gaps"] = gaps
	fill["diff"] = diff
	fill["n"] = diff_n


func _finish_heights(c: DesignedCourse, _fallback: Callable, fill: Dictionary) -> void:
	var gaps: PackedInt32Array = fill["gaps"]
	var diff: float = fill["diff"]
	var diff_n: int = fill["n"]
	if diff_n > 0:
		var shift := diff / diff_n
		for k in gaps:
			c.heights[k] += shift
	var lo := INF
	var hi := -INF
	for k in c.heights.size():
		c.heights[k] = maxf(c.heights[k], LOW_GROUND)
		lo = minf(lo, c.heights[k])
		hi = maxf(hi, c.heights[k])
	# Heights are stored round zero, within +-MAX_HEIGHT.
	var base := (lo + hi) * 0.5
	for k in c.heights.size():
		c.heights[k] = clampf(c.heights[k] - base, -DesignedCourse.MAX_HEIGHT, DesignedCourse.MAX_HEIGHT)
	c.source["base_height"] = snappedf(base, 0.01)


func _add_shapes(c: DesignedCourse) -> void:
	# Greens and tees with a bank round them, kept out of the water: a pond
	# mapped round an island or peninsula green without its inner ring
	# (Leopard Creek's 18th) drowned the green.
	var dry: Array[PackedVector2Array] = []
	for surface: int in [Surface.Type.GREEN, Surface.Type.TEE]:
		for ring in _rings_of(surface):
			var grown := Geometry2D.offset_polygon(ring, GREEN_BANK if surface == Surface.Type.GREEN else TEE_BANK)
			if not grown.is_empty():
				dry.append(grown[0])
	for d in _polys:
		if d.has("wood"):
			continue
		var surface: int = d["surface"]
		var pts: PackedVector2Array
		if surface == Surface.Type.SAND:
			# Mappers trace a bunker click by click, half a metre off either
			# way, and the spline through those clicks drew a wavy edge.
			pts = smooth_ring(d["ring"])
		elif surface == Surface.Type.TEE:
			# A tee is mostly mapped as four corners, and the spline through
			# four points bulged it into a lumpy oval: points every metre
			# keep its sides straight, with mown, rounded corners.
			pts = smooth_ring(d["ring"], 1.0, 1)
		else:
			pts = simplify_ring(d["ring"], TOLERANCE.get(surface, 0.5))
		var parts: Array[PackedVector2Array] = [pts]
		if surface == Surface.Type.WATER:
			parts = dry_out(pts, dry)
		for part in parts:
			if part.size() >= 3:
				var shape := CourseShape.new(surface, part)
				shape.cover = str(d.get("cover", ""))
				c.shapes.append(shape)
	for s in _streams:
		var line: PackedVector2Array = s["line"]
		for piece in stream_pieces(c, smooth_line(simplify_line(line, 0.8)), STREAM_PIECE, STREAM_PIECE_DROP):
			if piece.size() >= 2 and area.grow(-2.0).has_point(piece[0]):
				var ring := ribbon(piece, s["width"])
				if ring.size() >= 3:
					c.shapes.append(CourseShape.new(Surface.Type.WATER, ring))


func _add_holes(c: DesignedCourse) -> void:
	# Holes in number order; ones without a number keep their map order.
	var order: Array[Dictionary] = []
	for d in _holes:
		if course_filter.is_empty() or d["course"] == course_filter:
			order.append(d)
	for i in order.size():
		order[i]["index"] = i
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := _ref_number(a["ref"])
		var rb := _ref_number(b["ref"])
		return ra < rb if ra != rb else a["index"] < b["index"])
	var greens := _rings_of(Surface.Type.GREEN)
	var tees := _rings_of(Surface.Type.TEE)
	var water := _rings_of(Surface.Type.WATER)
	for d in order:
		var line: PackedVector2Array = d["line"]
		# Mappers draw holes tee to green; turn round any drawn backwards.
		if _near_ring(greens, line[0], 25.0) >= 0 and _near_ring(greens, line[line.size() - 1], 25.0) < 0:
			line = line.duplicate()
			line.reverse()
		var h := DesignedHole.new()
		var end := line[line.size() - 1]
		var g := _near_ring(greens, end, 40.0)
		h.pin = end
		if g < 0:
			# No green mapped and the line ends in a pond (Leopard Creek's
			# 11th): the green the guesser draws goes on the bank.
			var back := line[line.size() - 2]
			h.pin = off_greens(end, back, water, Vector2.INF, 10.0)
		if g >= 0:
			h.pin = _centroid(greens[g])
			for p in _pins:
				if Geometry2D.is_point_in_polygon(p, greens[g]):
					h.pin = p
		h.tees = _tees_for(line, h.pin, tees)
		# Lines drawn from the last green's middle, with no tee mapped, put
		# the tee (and the tee box guessed round it) on that green
		# (Hilversum's 5th, Portrush's 16th): it goes on past the green.
		for t in h.tees.size():
			h.tees[t] = off_greens(h.tees[t], h.pin, greens, h.pin)
		var bends := simplify_line(line, 8.0)
		for k in range(1, bends.size() - 1):
			if h.route.size() < 3:
				h.route.append(bends[k])
		var par := int(d["par"]) if str(d["par"]).is_valid_int() else 0
		h.par = clampi(par, 3, 6) if par > 0 else DesignedHole.par_for_length(h.length_m())
		if not par_fits(h.par, h.length_m()):
			# A mistagged par: Teeth of the Dog's 175 m 13th is mapped as a 4.
			h.par = DesignedHole.par_for_length(h.length_m())
		# OpenStreetMap's handicap tag is the stroke index on the scorecard.
		h.stroke_index = clampi(int(d["si"]), 0, 36) if str(d["si"]).is_valid_int() else 0
		c.holes.append(h)


## `p` moved toward `toward` until it is 6 m clear of every green but the
## one round `pin`; as it was if it isn't on one, or the hole is too short.
static func off_greens(p: Vector2, toward: Vector2, greens: Array[PackedVector2Array], pin: Vector2, clear := 6.0) -> Vector2:
	var dir := (toward - p).normalized()
	var length := p.distance_to(toward)
	var q := p
	var moved := 0.0
	var boxes: Array[Rect2] = []
	for r in greens:
		var b := Rect2(r[0], Vector2.ZERO)
		for v in r:
			b = b.expand(v)
		boxes.append(b.grow(clear))
	while moved < length * 0.4:
		var on := false
		for k in greens.size():
			var r := greens[k]
			if boxes[k].has_point(q) and not (pin.is_finite() and Geometry2D.is_point_in_polygon(pin, r)) and (Geometry2D.is_point_in_polygon(q, r) or _ring_distance(r, q) < clear):
				on = true
				break
		if not on:
			return q
		q += dir * 2.0
		moved += 2.0
	return p


static func _ring_distance(r: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	for i in r.size():
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, r[i], r[(i + 1) % r.size()])))
	return best


## Tee boxes along the start of a hole, back to forward (at most three).
func _tees_for(line: PackedVector2Array, pin: Vector2, tees: Array[PackedVector2Array]) -> PackedVector2Array:
	var start := line[0]
	var dir := (line[1] - start).normalized()
	# Tee boxes sit on the line's first leg, from a little behind its start
	# to a little ahead (mappers start the line at one of the tees).
	var a := start - dir * 60.0
	var b := start + dir * minf(start.distance_to(line[1]) * 0.5, 80.0)
	var full := start.distance_to(pin)
	var found: Array[Vector2] = []
	for r in tees:
		var p := _centroid(r)
		if p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) < 15.0 and p.distance_to(pin) > full * 0.7:
			found.append(p)
	if found.is_empty():
		found.append(start)
	found.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.distance_to(pin) > q.distance_to(pin))
	var out := PackedVector2Array()
	if found.size() <= DesignedHole.MAX_TEES:
		out.append_array(PackedVector2Array(found))
	else:
		out.append_array(PackedVector2Array([found[0], found[int(found.size() * 0.5)], found[found.size() - 1]]))
	return out


func _add_paths(c: DesignedCourse) -> void:
	for d in _paths:
		var pts := simplify_line(d["line"], 0.5)
		var inside := PackedVector2Array()
		for p in pts:
			if area.has_point(p):
				inside.append(p)
			elif inside.size() >= 2:
				c.paths.append(CoursePath.new(inside, d["width"], d["bridge"]))
				inside = PackedVector2Array()
			else:
				inside.clear()
		if inside.size() >= 2:
			c.paths.append(CoursePath.new(inside, d["width"], d["bridge"]))


## Building kinds by their building=* tag (CourseBuilding.kind).
const BUILDING_KINDS := {
	"house": "house", "detached": "house", "semidetached_house": "house", "terrace": "house",
	"bungalow": "bungalow", "residential": "house", "farmhouse": "house", "cabin": "shed",
	"garage": "shed", "garages": "shed", "shed": "shed", "hut": "shed", "carport": "shed",
	"greenhouse": "shed", "kiosk": "shed", "toilets": "shed", "service": "shed", "roof": "shed",
	"barn": "barn", "farm_auxiliary": "barn", "stable": "barn", "cowshed": "barn", "sports_hall": "barn",
	"clubhouse": "clubhouse", "pavilion": "clubhouse",
	"apartments": "block", "commercial": "block", "industrial": "block", "retail": "block",
	"office": "block", "school": "block", "hotel": "block", "hospital": "block", "public": "block",
	"church": "block", "warehouse": "barn",
}
## Typical heights without lidar or tags: kind -> [eave, ridge] (metres).
const BUILDING_HEIGHTS := {
	"house": [5.3, 8.6], "bungalow": [2.8, 5.6], "shed": [2.3, 3.2], "barn": [4.5, 8.0],
	"clubhouse": [4.6, 8.4], "block": [9.0, 9.0], "other": [3.5, 6.0],
}


## The mapped buildings inside the area, as tall as the lidar sees them
## (surface minus ground) where it covers them, else as tagged or typical
## for their kind, with pitched roofs on houses and other small buildings.
func _add_buildings(c: DesignedCourse, height: Callable, from := 0, to := -1) -> void:
	for f in _footprints.slice(from, to if to >= 0 else _footprints.size()):
		var ring: PackedVector2Array = f["ring"]
		if ring.size() >= 4 and ring[0].is_equal_approx(ring[ring.size() - 1]):
			ring = ring.slice(0, ring.size() - 1)
		if ring.size() < 3:
			continue
		var inside := true
		for p in ring:
			if not area.grow(-1.0).has_point(p):
				inside = false
				break
		if not inside:
			continue
		var b := building_from(ring, f["tags"], _lidar_heights(ring, height), _region)
		if b.is_valid():
			c.buildings.append(b)


## A building from its outline, OSM tags and lidar heights above the ground
## at points inside it (sorted, possibly empty).
static func building_from(ring: PackedVector2Array, t: Dictionary, lidar: PackedFloat32Array, region := "") -> CourseBuilding:
	var b := CourseBuilding.new(ring)
	var tag := str(t.get("building", "yes"))
	var size := absf(b.area())
	var kind: String = BUILDING_KINDS.get(tag, "")
	var name := str(t.get("name", "")).to_lower()
	if str(t.get("club", "")) == "golf" or str(t.get("golf", "")) == "clubhouse" or name.contains("club") and (name.contains("house") or name.contains("golf")):
		kind = "clubhouse"
	if kind.is_empty():
		kind = "shed" if size < 30.0 else ("house" if size < 220.0 else "other")
	b.kind = kind
	var hb: Array = BUILDING_HEIGHTS.get(kind, BUILDING_HEIGHTS["other"])
	if region == "us" and kind == "house":
		hb = [4.0, 7.2]  # American suburbs: one and two storeys, lower pitch
	var eave: float = hb[0]
	var ridge: float = hb[1]
	var levels := str(t.get("building:levels", ""))
	if levels.is_valid_float():
		eave = maxf(float(levels), 1.0) * 2.9 + 0.3
		ridge = eave + (3.0 if kind in ["house", "clubhouse", "bungalow"] else 0.0)
	var pitched := ridge > eave + 0.5
	var tagged := _tag_metres(t.get("height", ""))
	if tagged > 0.0:
		ridge = tagged
		eave = minf(eave, ridge)
	elif lidar.size() >= 6 and lidar[int(lidar.size() * 0.5)] >= CourseBuilding.MIN_HEIGHT:
		# The roof as the lidar sees it. A pitched roof's points spread
		# evenly from the eaves to the ridge, so the 15th and 65th
		# percentiles give both, leaving out the top third, where branches
		# over the roof and chimneys are.
		var lo := lidar[int(lidar.size() * 0.15)]
		var mid := lidar[int(lidar.size() * 0.65)]
		pitched = mid - lo > 0.5
		if pitched:
			var rise := (mid - lo) / 0.5
			eave = lo - rise * 0.15
			ridge = eave + rise
		else:
			eave = lidar[int(lidar.size() * 0.5)]
			ridge = eave
	var shape := str(t.get("roof:shape", ""))
	match shape:
		"flat", "skillion", "dome", "onion":
			pitched = false
		"gabled", "half-hipped", "gambrel", "saltbox", "mansard", "hipped", "pyramidal":
			pitched = true
	if not pitched or b.squareness() < 0.78 or size > 1200.0:
		# Flat roofs, and complex outlines a pitched roof over the
		# rectangle round them wouldn't fit.
		b.roof = "flat"
		b.eave = clampf(ridge if not pitched else lerpf(eave, ridge, 0.3), CourseBuilding.MIN_HEIGHT, CourseBuilding.MAX_HEIGHT)
		b.ridge = b.eave
		return b
	var box := b.oriented_box()
	var half: Vector2 = box["half"]
	# Keep the roof's pitch between about 20 and 45 degrees.
	var rise := clampf(ridge - eave, half.y * 0.36, half.y)
	b.ridge = clampf(maxf(ridge, CourseBuilding.MIN_HEIGHT + rise), CourseBuilding.MIN_HEIGHT, CourseBuilding.MAX_HEIGHT)
	b.eave = clampf(b.ridge - rise, CourseBuilding.MIN_HEIGHT, CourseBuilding.MAX_HEIGHT)
	if shape in ["hipped", "pyramidal"]:
		b.roof = "hipped"
	elif shape.is_empty():
		# British houses are mostly gabled along their long side; square
		# ones and bungalows are often hipped.
		b.roof = "hipped" if half.x < half.y * 1.25 or kind == "bungalow" else "gabled"
	else:
		b.roof = "gabled"
	return b


static func _tag_metres(v: Variant) -> float:
	var s := str(v).replace("m", "").strip_edges()
	return float(s) if s.is_valid_float() else 0.0


## Lidar heights above the ground at points about a metre apart inside the
## outline (kept 0.8 m in from the walls), sorted; empty without lidar.
func _lidar_heights(ring: PackedVector2Array, height: Callable) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if not surface.is_valid():
		return out
	var inner := Geometry2D.offset_polygon(ring, -0.8)
	if inner.is_empty():
		return out
	var poly: PackedVector2Array = inner[0]
	var r := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(p)
	var step := maxf(1.0, sqrt(r.get_area() / 400.0))
	var z := r.position.y + step * 0.5
	while z < r.end.y:
		var x := r.position.x + step * 0.5
		while x < r.end.x:
			var p := Vector2(x, z)
			if Geometry2D.is_point_in_polygon(p, poly):
				var lat := frame.lat_of(p)
				var lon := frame.lon_of(p)
				var top := float(surface.call(lat, lon))
				var ground := float(height.call(lat, lon))
				if not is_nan(top) and not is_nan(ground):
					out.append(top - ground)
			x += step
		z += step
	out.sort()
	return out


## Mapped walls, cut to the course area.
func _add_walls(c: DesignedCourse) -> void:
	for line in _walls:
		var inside := PackedVector2Array()
		for p in simplify_line(line, 0.3):
			if area.has_point(p):
				inside.append(p)
			else:
				if inside.size() >= 2:
					c.walls.append(inside)
				inside = PackedVector2Array()
		if inside.size() >= 2:
			c.walls.append(inside)


## The width in metres of a mapped road or path that is drawn as tarmac,
## or 0 to leave it out: tunnels, and unpaved tracks and footpaths (most
## footpaths across a course are just mown grass). From its width or lanes
## tags where mapped, else a typical width for its class (UK and US road
## standards: about 3.2 m a lane).
static func road_width(t: Dictionary) -> float:
	if str(t.get("tunnel", "no")) != "no" or str(t.get("covered", "no")) == "yes" or str(t.get("area", "no")) == "yes":
		return 0.0
	var hw := str(t.get("highway", ""))
	var surface := str(t.get("surface", ""))
	var paved := surface in ["asphalt", "paved", "concrete", "concrete:plates", "concrete:lanes", "paving_stones", "sett", "chipseal", "metal"]
	var typical := {"motorway": 11.0, "trunk": 9.0, "primary": 7.5, "secondary": 7.0, "tertiary": 6.5,
		"unclassified": 5.5, "residential": 5.5, "living_street": 5.0, "service": 3.5}
	var base := 0.0
	if typical.has(hw):
		# A road mapped as unpaved is a farm or maintenance track.
		if surface in ["unpaved", "gravel", "dirt", "grass", "ground", "earth", "compacted", "fine_gravel", "sand", "mud"]:
			return 0.0
		base = typical[hw]
		if hw == "service" and str(t.get("service", "")) == "parking_aisle":
			base = 5.0
	elif hw == "track":
		base = 3.0 if paved else 0.0
	elif hw in ["footway", "path", "cycleway", "bridleway"]:
		base = 1.8 if paved else 0.0
	if base <= 0.0:
		return 0.0
	var w := _metres(t.get("width", ""))
	if w <= 0.0 and str(t.get("lanes", "")).is_valid_int():
		w = int(str(t.get("lanes", ""))) * 3.2
	return clampf(w if w > 0.0 else base, CoursePath.MIN_WIDTH, CoursePath.MAX_WIDTH)


## Whether the lidar ground shows a mapped ditch or drain as one: lower
## than the ground a few metres either side along a good part of it. Field
## drains are often mapped as ditches, and some are piped without a tag
## saying so (West Essex, Nov 2026); cutting those into the ground made
## long straight trenches across fields.
static func is_open_ditch(line: PackedVector2Array, width: float, height: Callable, f: GeoFrame) -> bool:
	var at := func(p: Vector2) -> float: return float(height.call(f.lat_of(p), f.lon_of(p)))
	var off := width * 0.5 + 3.0
	var dips := 0
	var n := 0
	for i in range(1, line.size()):
		var a := line[i - 1]
		var b := line[i]
		var len := a.distance_to(b)
		if len < 0.5:
			continue
		var d := (b - a) / len
		var side := Vector2(-d.y, d.x) * off
		var s := 2.0
		while s < len - 2.0 or (n == 0 and s < len):
			var p := a + d * s
			var mid: float = at.call(p)
			var l: float = at.call(p + side)
			var r: float = at.call(p - side)
			s += 4.0
			if is_nan(mid) or is_nan(l) or is_nan(r):
				continue
			n += 1
			if (l + r) * 0.5 - mid > 0.12:
				dips += 1
	return n == 0 or float(dips) / n >= 0.35


## True for a culverted or piped watercourse (tunnel, covered, below
## ground), which mustn't be cut into the ground as an open ditch.
static func _underground(t: Dictionary) -> bool:
	return str(t.get("tunnel", "no")) not in ["no", ""] or str(t.get("covered", "no")) == "yes" \
			or str(t.get("location", "")) == "underground" or str(t.get("layer", "0")).begins_with("-")


static func _is_bridge(t: Dictionary) -> bool:
	return str(t.get("bridge", "no")) not in ["no", ""]


func _add_trees(c: DesignedCourse) -> void:
	var clear := _play_rings()
	_clear_cells = box_cells(clear + _buildings)
	_near.clear()
	# Mapped trees and tree rows are where they are, on the line or not.
	for t in _trees:
		_plant(c, t["p"], t["leaf"], t["height"], clear, 0.0, false)
	for r in _rows:
		var line: PackedVector2Array = r["line"]
		for p in _resample(line, ROW_SPACING):
			_plant(c, p, r["leaf"], 0.0, clear, 0.0, false)
	# Lidar crowns are real trees, typed by the wood they stand in (if any).
	# A wooded course has tens of thousands, more than MAX_TREES, so the ones
	# nearest the holes go in first and deep woods are left thinner.
	var found: Array[Dictionary] = []
	for t in lidar_trees:
		var p := frame.to_local(t["lat"], t["lon"])
		found.append({"p": p, "h": t["height"], "leaf": str(t.get("leaf", "")), "d": _hole_distance(p, c.holes)})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["d"] < b["d"])
	# Every crown near the holes. Farther off, when there are more crowns
	# than room for them, a share of them evenly (grown a little to fill
	# the gaps), so the woods reach the edge of the area rather than
	# stopping in a ring round the holes (Hilversum has 40,000).
	var near := 0
	while near < found.size() and found[near]["d"] <= FULL_WOOD_REACH:
		near += 1
	for i in near:
		var t: Dictionary = found[i]
		_plant(c, t["p"], t["leaf"] if not str(t["leaf"]).is_empty() else _leaf_at(t["p"]), t["h"], clear, 3.0)
	var room := max_trees - c.objects.size()
	var far := found.size() - near
	# Every k-th crown by distance, so the ones kept spread evenly out to
	# the edge of the area.
	var k := 1.0 if far <= room or room <= 0 else float(far) / room * 1.05
	var grow := clampf(sqrt(k), 1.0, 1.35)
	var next := float(near)
	while int(next) < found.size():
		var t: Dictionary = found[int(next)]
		_plant(c, t["p"], t["leaf"] if not str(t["leaf"]).is_empty() else _leaf_at(t["p"]), t["h"] * grow, clear, 3.0)
		next += k
	if not lidar_trees.is_empty():
		return
	for p in photo_trees:
		_plant(c, p, _leaf_at(p), 0.0, clear, 4.0)
	_add_land_trees(c, clear)
	# Woods are filled on a jittered grid, thinned to keep within MAX_TREES.
	var wood_area := 0.0
	for d in _polys:
		if d.has("wood"):
			wood_area += absf(_ring_area(d["ring"]))
	var left := maxi(max_trees - c.objects.size(), 0)
	if left == 0 or wood_area <= 0.0:
		return
	var spacing := maxf(WOOD_SPACING, sqrt(wood_area / left))
	for d in _polys:
		if not d.has("wood"):
			continue
		var ring: PackedVector2Array = d["ring"]
		var r := Rect2(ring[0], Vector2.ZERO)
		for p in ring:
			r = r.expand(p)
		var z := r.position.y + spacing * 0.5
		while z < r.end.y:
			var x := r.position.x + spacing * 0.5
			while x < r.end.x:
				var p := Vector2(x, z) + Vector2(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.4, 0.4)) * spacing
				if Geometry2D.is_point_in_polygon(p, ring):
					_plant(c, p, d["leaf"], 0.0, clear, spacing * 0.5)
				x += spacing
			z += spacing


## Land-cover trees outside the mapped woods (which are filled below),
## nearest the holes first. Only without lidar or photo trees.
func _add_land_trees(c: DesignedCourse, clear: Array[Dictionary]) -> void:
	if not photo_trees.is_empty():
		return
	var found: Array[Dictionary] = []
	for p in land_trees:
		var in_wood := not _wood_at(p).is_empty()
		var d := _hole_distance(p, c.holes)
		# At 10 m, tree-lined fairways read as woods: keep the line of play
		# clear even where its fairway isn't mapped.
		if not in_wood and d > LAND_TREE_CLEAR:
			found.append({"p": p, "d": d})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["d"] < b["d"])
	# Keep room for the mapped woods.
	var budget := max_trees >> 1
	for t in found:
		if budget <= 0:
			break
		var before := c.objects.size()
		_plant(c, t["p"], _leaf_at(t["p"]), 0.0, clear, 5.0)
		budget -= c.objects.size() - before


## Distance from a point to the nearest hole's line of play.
static func _hole_distance(p: Vector2, holes: Array[DesignedHole]) -> float:
	var best := INF
	for h in holes:
		if h.tees.is_empty():
			continue
		var prev := h.tees[0]
		for q in h.route:
			best = minf(best, p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p, prev, q)))
			prev = q
		best = minf(best, p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p, prev, h.pin)))
	return sqrt(best)


## The leaf type of the wood a point is in, or "".
func _leaf_at(p: Vector2) -> String:
	return str(_wood_at(p).get("leaf", ""))


## The mapped wood round `p` ({"ring", "box", "leaf"}), or {}.
func _wood_at(p: Vector2) -> Dictionary:
	if _wood_cells.is_empty():
		var woods: Array = []
		for d in _polys:
			if d.has("wood"):
				var ring: PackedVector2Array = d["ring"]
				var r := Rect2(ring[0], Vector2.ZERO)
				for q in ring:
					r = r.expand(q)
				woods.append({"ring": ring, "box": r, "leaf": d["leaf"]})
		_wood_cells = box_cells(woods)
		_wood_cells[Vector2i(1 << 30, 0)] = []  # built, even with no woods
	for d: Dictionary in _wood_cells.get(Vector2i((p / LINE_CELL).floor()), []):
		if (d["box"] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, d["ring"]):
			return d
	return {}


## Course points on fairways, for the photo's grass colour.
func grass_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	for r in _rings_of(Surface.Type.FAIRWAY):
		var p := _centroid(r)
		if Geometry2D.is_point_in_polygon(p, r) and area.has_point(p):
			out.append(p)
	return out


## Plants a tree unless it would stand on a fairway, green, tee, bunker or
## in water (OpenStreetMap woods often overlap the play areas a little).
func _plant(c: DesignedCourse, p: Vector2, leaf: String, height: float, clear: Array[Dictionary], gap := 0.0, found := true) -> void:
	if c.objects.size() >= max_trees or not area.grow(-2.0).has_point(p):
		return
	if found and on_line_of_play(p, _lines):
		return
	# The play areas (`clear`) and buildings, by their cells.
	for d: Dictionary in _clear_cells.get(Vector2i((p / LINE_CELL).floor()), []):
		if (d["box"] as Rect2).has_point(p) and Geometry2D.is_point_in_polygon(p, d["ring"]):
			return
	# Keep `gap` metres from trees already planted (a lidar crown that is
	# also a mapped tree is planted once).
	var cell := Vector2i((p / NEAR_CELL).floor())
	if gap > 0.0:
		for dj in range(-1, 2):
			for di in range(-1, 2):
				for q: Vector2 in _near.get(cell + Vector2i(di, dj), []):
					if q.distance_to(p) < gap:
						return
	if not _near.has(cell):
		_near[cell] = []
	_near[cell].append(p)
	var id: String
	match leaf:
		"needleleaved":
			id = DesignedCourse.TREE_IDS[0]
		"broadleaved":
			id = DesignedCourse.TREE_IDS[1]
		_:
			id = DesignedCourse.TREE_IDS[0 if _rng.randf() < 0.35 else 1]
	var s := clampf(height / 14.0, 0.5, 2.0) if height > 0.0 else _rng.randf_range(0.8, 1.3)
	c.objects.append(PlacedObject.new(id, Vector3(p.x, 0, p.y), _rng.randf_range(0, 360), s))


## The play areas trees keep off, grown 2 m, with their bounds.
const LINE_CELL := 32.0

## The lines of play's pieces by the LINE_CELL cells within LINE_CLEAR of
## them: Vector2i -> [[a, b, tee], ...], so on_line_of_play looks at a few.
static func line_cells(lines: Array[PackedVector2Array]) -> Dictionary:
	var out := {}
	for line in lines:
		for k in line.size() - 1:
			var a := line[k]
			var b := line[k + 1]
			var lo := ((a.min(b) - Vector2.ONE * LINE_CLEAR) / LINE_CELL).floor()
			var hi := ((a.max(b) + Vector2.ONE * LINE_CLEAR) / LINE_CELL).floor()
			for j in range(int(lo.y), int(hi.y) + 1):
				for i in range(int(lo.x), int(hi.x) + 1):
					var key := Vector2i(i, j)
					if not out.has(key):
						out[key] = []
					out[key].append([a, b, line[0]])
	return out


## {"ring", "box"} areas by the LINE_CELL cells their boxes touch, so a
## tree looks at a few rather than every green, bunker and house (Pebble
## Beach has 77,000 trees in its photo and 600 such areas).
static func box_cells(areas: Array) -> Dictionary:
	var out := {}
	for d: Dictionary in areas:
		var b: Rect2 = d["box"]
		for j in range(floori(b.position.y / LINE_CELL), floori(b.end.y / LINE_CELL) + 1):
			for i in range(floori(b.position.x / LINE_CELL), floori(b.end.x / LINE_CELL) + 1):
				var key := Vector2i(i, j)
				if not out.has(key):
					out[key] = []
				out[key].append(d)
	return out


## True when `p` stands within LINE_CLEAR of a line of play (line_cells),
## past the first 10 m from its tee.
static func on_line_of_play(p: Vector2, cells: Dictionary) -> bool:
	for seg: Array in cells.get(Vector2i((p / LINE_CELL).floor()), []):
		var q := Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1])
		if q.distance_to(p) < LINE_CLEAR and q.distance_to(seg[2]) > 10.0:
			return true
	return false


func _play_rings() -> Array[Dictionary]:
	var out: Array[Dictionary] = _guessed.duplicate()
	for d in _polys:
		if d.has("wood") or not d["surface"] in [Surface.Type.FAIRWAY, Surface.Type.GREEN, Surface.Type.TEE, Surface.Type.SAND, Surface.Type.WATER]:
			continue
		for g in Geometry2D.offset_polygon(d["ring"], 2.0):
			var r := Rect2(g[0], Vector2.ZERO)
			for p in g:
				r = r.expand(p)
			out.append({"ring": g, "box": r})
	return out


func _rings_of(surface: int) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for d in _polys:
		if not d.has("wood") and d["surface"] == surface:
			out.append(d["ring"])
	return out


## The ring containing `p`, else the nearest within `radius`, else -1.
static func _near_ring(rings: Array[PackedVector2Array], p: Vector2, radius: float) -> int:
	var best := -1
	var best_d := radius
	for k in rings.size():
		var r := rings[k]
		if Geometry2D.is_point_in_polygon(p, r):
			return k
		for i in r.size():
			var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, r[i], r[(i + 1) % r.size()]))
			if d < best_d:
				best_d = d
				best = k
	return best


## Where close-up photos would help: the green end of each hole whose
## green or bunkers aren't mapped.
func detail_spots() -> PackedVector2Array:
	var greens := _rings_of(Surface.Type.GREEN)
	var sands := _rings_of(Surface.Type.SAND)
	var out := PackedVector2Array()
	for d in _holes:
		var line: PackedVector2Array = d["line"]
		if line.size() < 2:
			continue
		var end := line[line.size() - 1]
		if _near_ring(greens, line[0], 25.0) >= 0 and _near_ring(greens, end, 25.0) < 0:
			end = line[0]
		var sand := false
		for r in sands:
			var p := _centroid(r)
			for k in range(1, line.size()):
				if p.distance_to(Geometry2D.get_closest_point_to_segment(p, line[k - 1], line[k])) < 45.0:
					sand = true
		if (_near_ring(greens, end, 20.0) < 0 or not sand) and area.has_point(end):
			out.append(end)
	return out


## The hole number in a ref: its first run of digits ("4/9" is hole 4).
static func _ref_number(ref: String) -> int:
	var digits := ""
	for ch in ref:
		if ch >= "0" and ch <= "9":
			digits += ch
		elif not digits.is_empty():
			break
	return int(digits) if not digits.is_empty() else 1000


static func _ring_area(r: PackedVector2Array) -> float:
	var a := 0.0
	for i in r.size():
		a += r[i].cross(r[(i + 1) % r.size()])
	return a * 0.5


static func _centroid(r: PackedVector2Array) -> Vector2:
	var a := _ring_area(r)
	if absf(a) < 0.01:
		var m := Vector2.ZERO
		for p in r:
			m += p
		return m / maxi(r.size(), 1)
	var c := Vector2.ZERO
	for i in r.size():
		var p := r[i]
		var q := r[(i + 1) % r.size()]
		c += (p + q) * p.cross(q)
	return c / (6.0 * a)


## Points every `step` metres along a line, ends included.
static func _resample(line: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if line.is_empty():
		return out
	out.append(line[0])
	var carry := 0.0
	for i in range(1, line.size()):
		var a := line[i - 1]
		var b := line[i]
		var seg := a.distance_to(b)
		var t := step - carry
		while t <= seg:
			out.append(a.lerp(b, t / seg))
			t += step
		carry = seg - (t - step)
	return out


## A line cut into pieces about `length` metres long (sharing their ends).
## A stream's line cut into pieces each with its own water line: at most
## `length` long and falling at most `drop` over the ground `c` has (a
## piece's water sits at its lowest bank, so on a slope a long piece left
## its top end's water far down a trench).
static func stream_pieces(c: DesignedCourse, line: PackedVector2Array, length: float, drop: float) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var dense := PackedVector2Array()
	for i in line.size():
		if i > 0:
			var n := ceili(line[i - 1].distance_to(line[i]) / 4.0)
			for k in range(1, n):
				dense.append(line[i - 1].lerp(line[i], float(k) / n))
		dense.append(line[i])
	var piece := PackedVector2Array()
	var run := 0.0
	var lo := INF
	var hi := -INF
	for i in dense.size():
		var h := c.base_height(dense[i].x, dense[i].y)
		if i > 0:
			run += dense[i - 1].distance_to(dense[i])
		if piece.size() >= 2 and (run > length or maxf(hi, h) - minf(lo, h) > drop):
			out.append(piece)
			piece = PackedVector2Array([dense[i - 1]])
			run = dense[i - 1].distance_to(dense[i])
			lo = c.base_height(dense[i - 1].x, dense[i - 1].y)
			hi = lo
		piece.append(dense[i])
		lo = minf(lo, h)
		hi = maxf(hi, h)
	if piece.size() >= 2:
		out.append(piece)
	for k in out.size():
		out[k] = simplify_line(out[k], 0.3)
	return out


## The outline of a `width` wide ribbon along `line`, round at its bends
## and ends (offset by miters, a stream's tight bends folded over themselves
## into jagged, crossed outlines).
static func ribbon(line: PackedVector2Array, width: float) -> PackedVector2Array:
	var best := PackedVector2Array()
	var area := 0.0
	for ring: PackedVector2Array in Geometry2D.offset_polyline(line, width * 0.5, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND):
		var a := absf(_ring_area(ring))  # the outline, not a hole in it
		if a > area:
			area = a
			best = ring
	# Evenly spaced: the outline is drawn as a curve through these points,
	# which overshot across a thin ribbon where an arc's short steps met a
	# long side.
	return smooth_ring(best, clampf(width * 0.5, 0.75, 3.0), 0) if best.size() > 3 else best


## Whether a mapped par could be right for a hole this long (metres):
## the longest par 3s and shortest par 4s and 5s of real courses, with room.
static func par_fits(par: int, length: float) -> bool:
	match par:
		3:
			return length <= 270.0
		4:
			return length >= 200.0 and length <= 520.0
		5:
			return length >= 380.0
	return true


## How many holes of the course aren't on the map: of 18 (or 9, when no
## hole is numbered past 9) by the mapped holes' numbers; 0 when none is
## numbered. Bandon Dunes has 4 of its 18 mapped.
func missing_holes() -> int:
	var seen := {}
	for d in _holes:
		if course_filter.is_empty() or d["course"] == course_filter:
			var n := _ref_number(str(d["ref"]))
			if n >= 1 and n <= 18:
				seen[n] = true
	if seen.is_empty():
		return 0
	var of := 18 if seen.keys().max() > 9 or seen.size() > 9 else 9
	return of - seen.size()


## Respaces the points of every shape whose drawn outline crosses itself
## (the curve through a few uneven points overshoots: a narrow green or a
## fairway's thin neck folded over, and the 2 m grid then drew it in
## jagged bits); returns how many.
static func untangle_shapes(c: DesignedCourse) -> int:
	var fixed := 0
	for s in c.shapes:
		if s.points.size() < 4 or not Geometry2D.triangulate_polygon(s.outline()).is_empty():
			continue
		var b := s.bounds()
		for spacing: float in [clampf(minf(b.size.x, b.size.y) * 0.15, 0.75, 4.0), 0.75]:
			var pts := smooth_ring(s.points, spacing, 0)
			var test := CourseShape.new(s.surface, pts)
			if not Geometry2D.triangulate_polygon(test.outline()).is_empty():
				s.points = pts
				s.changed()
				fixed += 1
				break
	return fixed


## `ring` with each of `dry` cut out of it, as rings without holes (a
## shape has none): a dry area wholly inside is joined to the nearest shore
## by a causeway BRIDGE metres wide, as an island green's walkway.
static func dry_out(ring: PackedVector2Array, dry: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	var parts: Array[PackedVector2Array] = [ring]
	var box := _ring_box(ring)
	for hole in dry:
		if not box.intersects(_ring_box(hole)):
			continue
		var next: Array[PackedVector2Array] = []
		for part in parts:
			var cut := Geometry2D.clip_polygons(part, hole)
			if _holed(cut):
				var c := _ring_box(hole).get_center()
				var shore := c
				var best := INF
				for i in part.size():
					var q := Geometry2D.get_closest_point_to_segment(c, part[i], part[(i + 1) % part.size()])
					if q.distance_squared_to(c) < best:
						best = q.distance_squared_to(c)
						shore = q
				var dir := (shore - c).normalized()
				var side := dir.orthogonal() * BRIDGE * 0.5
				var far := shore + dir * 2.0
				var band := PackedVector2Array([c - side, far - side, far + side, c + side])
				var both := Geometry2D.merge_polygons(hole, band)
				cut = Geometry2D.clip_polygons(part, both[0]) if both.size() == 1 else cut
				if _holed(cut):
					next.append(part)  # left as it was
					continue
			for r in cut:
				if absf(_ring_area(r)) >= 4.0:
					next.append(r)
		parts = next
	return parts


## True when the clipped rings hold a hole (a ring inside another).
static func _holed(rings: Array[PackedVector2Array]) -> bool:
	for a in rings:
		for b in rings:
			if a != b and Geometry2D.is_point_in_polygon(a[0], b):
				return true
	return false


static func _ring_box(ring: PackedVector2Array) -> Rect2:
	var r := Rect2(ring[0], Vector2.ZERO)
	for p in ring:
		r = r.expand(p)
	return r


## Chaikin's corner cutting on an open line, ends kept: a stream's mapped
## line bends in sharp corners every few metres.
static func smooth_line(line: PackedVector2Array, passes := 2) -> PackedVector2Array:
	for _p in passes:
		if line.size() < 3:
			return line
		var out := PackedVector2Array([line[0]])
		for i in line.size() - 1:
			out.append(line[i].lerp(line[i + 1], 0.25))
			out.append(line[i].lerp(line[i + 1], 0.75))
		out.append(line[line.size() - 1])
		line = out
	return line


## Douglas-Peucker simplification of an open line.
static func simplify_line(line: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	if line.size() <= 2:
		return line
	var keep := PackedByteArray()
	keep.resize(line.size())
	keep[0] = 1
	keep[line.size() - 1] = 1
	var stack: Array[Vector2i] = [Vector2i(0, line.size() - 1)]
	while not stack.is_empty():
		var s: Vector2i = stack.pop_back()
		var best := -1
		var best_d := tolerance
		for i in range(s.x + 1, s.y):
			var d := line[i].distance_to(Geometry2D.get_closest_point_to_segment(line[i], line[s.x], line[s.y]))
			if d > best_d:
				best_d = d
				best = i
		if best >= 0:
			keep[best] = 1
			stack.append(Vector2i(s.x, best))
			stack.append(Vector2i(best, s.y))
	var out := PackedVector2Array()
	for i in line.size():
		if keep[i] == 1:
			out.append(line[i])
	return out


## A closed ring as a clean, flowing outline, the way a bunker's edge is
## really cut: control points every `spacing` metres along it (fewer on a
## big one, at most MAX_POINTS), smoothed with `passes` rounds of Taubin
## smoothing (which, unlike plain averaging, doesn't shrink it), then
## scaled back to the ring's own area. Even spacing also keeps the designer's
## spline from overshooting where a short side meets a long one. Wiggles
## shorter than a few spacings go; the bays and fingers of the shape stay.
static func smooth_ring(ring: PackedVector2Array, spacing := 1.5, passes := 4) -> PackedVector2Array:
	var n := ring.size()
	if n >= 2 and ring[0].is_equal_approx(ring[n - 1]):
		ring = ring.slice(0, n - 1)
		n -= 1
	if n < 3:
		return ring
	var perimeter := 0.0
	for i in n:
		perimeter += ring[i].distance_to(ring[(i + 1) % n])
	var count := clampi(roundi(perimeter / spacing), 8, MAX_POINTS)
	var step := perimeter / count
	# Even resample along the ring.
	var pts := PackedVector2Array()
	var seg := 0
	var seg_start := 0.0
	for k in count:
		var want := k * step
		while seg < n - 1 and seg_start + ring[seg].distance_to(ring[(seg + 1) % n]) < want:
			seg_start += ring[seg].distance_to(ring[(seg + 1) % n])
			seg += 1
		var a := ring[seg]
		var b := ring[(seg + 1) % n]
		var seg_len := a.distance_to(b)
		pts.append(a.lerp(b, clampf((want - seg_start) / seg_len, 0.0, 1.0) if seg_len > 0.0 else 0.0))
	var at := absf(_ring_area(ring))
	for _pass in passes:
		for f: float in [0.5, -0.53]:
			var next := PackedVector2Array()
			next.resize(count)
			for i in count:
				var mid := (pts[(i - 1 + count) % count] + pts[(i + 1) % count]) * 0.5
				next[i] = pts[i] + (mid - pts[i]) * f
			pts = next
	# Back to the mapped area, about the centre.
	var now := absf(_ring_area(pts))
	if now > 0.0 and at > 0.0:
		var centre := Vector2.ZERO
		for p in pts:
			centre += p
		centre /= count
		var k := sqrt(at / now)
		for i in count:
			pts[i] = centre + (pts[i] - centre) * k
	return pts


## A closed ring simplified to the tolerance, loosened until it has at most
## MAX_POINTS points, so outlines stay quick to shape and easy to edit.
static func simplify_ring(ring: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	if ring.size() <= 4:
		return ring
	# Split at the point furthest from the first, so both halves are open lines.
	var far := 0
	for i in ring.size():
		if ring[i].distance_squared_to(ring[0]) > ring[far].distance_squared_to(ring[0]):
			far = i
	var tol := tolerance
	var out := ring
	for _attempt in 8:
		var a := simplify_line(ring.slice(0, far + 1), tol)
		var tail := ring.slice(far)
		tail.append(ring[0])
		var b := simplify_line(tail, tol)
		out = a.slice(0, a.size() - 1) + b.slice(0, b.size() - 1)
		if out.size() <= MAX_POINTS:
			break
		tol *= 1.6
	return out if out.size() >= 3 else ring
