class_name RealLandscape
extends RefCounted
## The real land round a course built from the map, out to the horizon
## (DesignedCourse.landscape, drawn by Landscape): without it a real course
## sat on a flat green apron that showed from every high view and flyover.
## The coarse open elevation tiles give it, LAND_HALF metres each way from
## the course's middle; it follows the course's own ground inside the
## course and eases into the measured land over BLEND metres outside, so
## the two meet without a step. Where the tiles carry a sea floor (they
## measure under the sea) the course gets a sea at sea level, and where
## they hold a big lake's flat surface (Lake Michigan's 176.8 m beside
## Whistling Straits) it gets the lake at its level: without it the lake
## showed as a flat field at the foot of the bluffs.
##
## Usage: box() for the tiles to fetch, then rows() a band at a time, then
## apply() to each course of the club.

const CELL := 40.0  ## metres between samples
const LAND_HALF := 8000.0  ## metres each way from the course's middle
const BLEND := 160.0  ## metres outside the course over which the land eases into it
## A sea when this share of the land lies this deep (polders and lakes
## don't reach it; the sea floor a few kilometres out does).
const SEA_SHARE := 0.02
const SEA_DEPTH := -8.0
## Or when this share of it is one flat surface at sea level: tiles without
## a sea floor hold the sea at 0 (Barnbougle's Bass Strait, Al Mouj's Gulf).
const SEA_FLAT_SHARE := 0.08
const SEA_FLAT_LOW := -3.0
const SEA_FLAT_HIGH := 0.5
## A lake when this share of the land is one flat surface (to LAKE_FLAT
## metres) with hardly any land below it: the tiles hold big lakes level.
const LAKE_SHARE := 0.03
const LAKE_FLAT := 0.05
const LAKE_SHORE := 0.6  ## metres over its level that ground may be its water surface
const LAKE_STEEP := 4.0
## The tiles' sea surface near the shore is often a metre or so of noise
## over 0 (Ballybunion's Atlantic was land): ground this low joined to the
## sea floor is the sea, let down to SEA_FLOOR.
const SEA_SHORE := 1.5
const SEA_FLOOR := -1.5
const PLAY_LOW_SHARE := 0.15  ## of the play's points that may dip under the sea
const PLAY_CLEAR := 1.0  ## metres the middle of the play stands over it
const LINKS_REACH := 1000.0  ## metres from the course the sea makes it links

var frame: GeoFrame
var course: DesignedCourse  ## the first course: its ground and datum
var origin := Vector2.ZERO
var count := 0  ## samples each way
var heights := PackedFloat32Array()  ## from the course's datum
var _deep := 0
var _levels := {}  ## samples by their height in LAKE_FLAT steps
var _lake_sunk := false
var _sea_flooded := false
## Land cover round the course (optional): its water joined to the sea is
## let down under it, where cliffs smear the tiles out over the sea.
var cover: LandCover = null
var _cover_sunk := false


func _init(p_frame: GeoFrame, p_course: DesignedCourse) -> void:
	frame = p_frame
	course = p_course
	count = int(LAND_HALF * 2.0 / CELL) + 1
	var mid := course.area.get_center()
	origin = ((mid - Vector2.ONE * LAND_HALF) / CELL).round() * CELL
	heights.resize(count * count)


## South, west, north, east in degrees: the tiles needed.
func box() -> Array[float]:
	var a := origin
	var b := origin + Vector2.ONE * (count - 1) * CELL
	var lats := [frame.lat_of(a), frame.lat_of(b)]
	var lons := [frame.lon_of(a), frame.lon_of(b)]
	return [lats.min(), lons.min(), lats.max(), lons.max()]


## Rows j0 to j1 from `height` (Callable(lat, lon) -> metres above sea level).
func rows(j0: int, j1: int, height: Callable) -> void:
	var base := float(course.source.get("base_height", 0.0))
	var area := course.area
	for j in range(j0, mini(j1, count)):
		for i in count:
			var p := origin + Vector2(i, j) * CELL
			var land := float(height.call(frame.lat_of(p), frame.lon_of(p)))
			if land < SEA_DEPTH:
				_deep += 1
			var key := roundi(land / LAKE_FLAT)
			_levels[key] = int(_levels.get(key, 0)) + 1
			land -= base
			var dx := maxf(maxf(area.position.x - p.x, p.x - area.end.x), 0.0)
			var dz := maxf(maxf(area.position.y - p.y, p.y - area.end.y), 0.0)
			var w := smoothstep(0.0, BLEND, Vector2(dx, dz).length())
			heights[j * count + i] = lerpf(course.base_height(p.x, p.y), land, w)


## True when the land holds a sea.
func has_sea() -> bool:
	return _deep >= heights.size() * SEA_SHARE or flat_sea()


## True when the sea's surface is held flat near 0 (with or without a sea
## floor past it): it is let down under its water like a lake's.
func flat_sea() -> bool:
	return not is_nan(flat_sea_level())


## The level of a sea held flat (to a decimetre) near 0 by tiles without a
## sea floor, over SEA_FLAT_SHARE of the land, or NAN. Teeth of the Dog's
## Caribbean sits at -1.8 m (the tiles' datum), Barnbougle's at 0.
func flat_sea_level() -> float:
	var lo := roundi(SEA_FLAT_LOW / LAKE_FLAT)
	var hi := roundi(SEA_FLAT_HIGH / LAKE_FLAT)
	var best := 0
	var at := 0
	for k in range(lo, hi + 1):
		var n := 0
		for d in range(-2, 3):
			n += int(_levels.get(k + d, 0))
		if n > best:
			best = n
			at = k
	if best < heights.size() * SEA_FLAT_SHARE:
		return NAN
	var peak := at
	for d in range(-2, 3):
		if int(_levels.get(at + d, 0)) > int(_levels.get(peak, 0)):
			peak = at + d
	return peak * LAKE_FLAT


## The level of a big lake round the course (metres above sea level), or
## NAN: the commonest height, when it covers LAKE_SHARE of the land and
## hardly any land lies below it, and it is above sea level. A level on a
## whole metre is taken for flat land in tiles rounded to whole metres
## (SRTM: a river plain reads as one flat sheet), not a lake.
func lake_level() -> float:
	var best := 0
	var key := 0
	for k: int in _levels:
		if int(_levels[k]) > best:
			best = _levels[k]
			key = k
	var n := heights.size()
	if best < n * LAKE_SHARE:
		return NAN
	var level := key * LAKE_FLAT
	if level < 1.0 or absf(level - roundf(level)) < 0.1:
		return NAN
	var below := 0
	for k: int in _levels:
		if k * LAKE_FLAT < level - 0.5:
			below += int(_levels[k])
	return level if below <= best * 0.1 else NAN


## Gives `c` (a course of the club, on the same frame) the land.
func apply(c: DesignedCourse) -> void:
	var lake := flat_sea_level() if has_sea() else lake_level()
	if not is_nan(lake) and not _lake_sunk:
		# The lake's flat surface lowered under its water, so the two don't
		# flicker through each other.
		_lake_sunk = true
		var base := float(course.source.get("base_height", 0.0))
		for k in heights.size():
			heights[k] = under_lake(heights[k] + base, lake) - base
	if has_sea() and not flat_sea() and not _sea_flooded:
		_sea_flooded = true
		flood_sea()
	if cover != null and has_sea() and not _cover_sunk:
		_cover_sunk = true
		sea_from_land_cover(flat_sea_level() if flat_sea() else 0.0)
	var saved := encode()
	c.landscape = DesignedCourse._decode_landscape(saved)
	c._landscape_saved = saved
	if flat_sea():
		if dry(c, lake, -1.0):
			c.source["sea"] = lake
			sink_lake(c, lake)
	elif has_sea() and dry(c):
		c.source["sea"] = 0.0
		sink_lake(c, 0.0)
	elif not is_nan(lake) and dry(c, lake, -1.0):
		c.source["sea"] = lake
		sink_lake(c, lake)


## Samples the land cover has as water, joined (through more of them) to
## the sea already in the land, let down under the sea at `sea`: the open
## tiles smear cliffs out over the water (Mauna Kea's lava coast, Durness)
## and the shore test alone can't reach past them. Returns the samples let
## down.
func sea_from_land_cover(sea: float) -> int:
	var base := float(course.source.get("base_height", 0.0))
	var near := course.area
	var wet := PackedByteArray()
	wet.resize(heights.size())
	var todo := PackedInt32Array()
	for k in heights.size():
		var p := origin + Vector2(k % count, k / count) * CELL
		if near.has_point(p):
			continue
		if heights[k] + base < sea - 0.5:
			wet[k] = 2  # the sea already
			todo.append(k)
		elif cover.class_at(frame.lat_of(p), frame.lon_of(p)) == LandCover.WATER:
			wet[k] = 1
	var at := 0
	var n := 0
	while at < todo.size():
		var k := todo[at]
		at += 1
		var i := k % count
		var j := k / count
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ni := i + d.x
			var nj := j + d.y
			if ni < 0 or nj < 0 or ni >= count or nj >= count:
				continue
			var nk := nj * count + ni
			if wet[nk] != 1:
				continue
			wet[nk] = 2
			todo.append(nk)
			heights[nk] = minf(heights[nk], sea + SEA_FLOOR - base)
			n += 1
	return n


## The low ground joined to the sea floor (under SEA_DEPTH) let down under
## the sea; the course and the land easing into it are left. Returns the
## samples let down.
func flood_sea() -> int:
	var base := float(course.source.get("base_height", 0.0))
	var near := course.area
	var seen := PackedByteArray()
	seen.resize(heights.size())
	var todo := PackedInt32Array()
	for k in heights.size():
		if heights[k] + base < SEA_DEPTH:
			seen[k] = 1
			todo.append(k)
	var at := 0
	var sunk := 0
	while at < todo.size():
		var k := todo[at]
		at += 1
		var i := k % count
		var j := k / count
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ni := i + d.x
			var nj := j + d.y
			if ni < 0 or nj < 0 or ni >= count or nj >= count:
				continue
			var nk := nj * count + ni
			if seen[nk] == 1 or heights[nk] + base > SEA_SHORE:
				continue
			seen[nk] = 1
			if near.has_point(origin + Vector2(ni, nj) * CELL):
				continue
			todo.append(nk)
			if heights[nk] + base > SEA_FLOOR:
				heights[nk] = SEA_FLOOR - base
				sunk += 1
	return sunk


## The sea inside the course's own box, where its heights stand it above
## the water: open tiles smear the land out over the sea by a coast
## (Ballybunion's Atlantic was a field 10 m up). Where the land cover
## (10 m) has water joined to the box's edge, away from the play areas, the
## ground is let down under the sea. Returns the samples let down.
static func sea_from_cover(c: DesignedCourse, frame: GeoFrame, cover: LandCover) -> int:
	if not c.source.has("sea"):
		return 0
	var sea := float(c.source["sea"])
	var base := float(c.source.get("base_height", 0.0))
	var step := maxi(1, roundi(LandCover.RES / DesignedCourse.CELL))
	var cw := ceili(float(c.cols) / step)
	var ch := ceili(float(c.rows) / step)
	var wet := PackedByteArray()
	wet.resize(cw * ch)
	var play: Array[CourseShape] = []
	for s in c.shapes:
		if s.is_valid() and s.surface in [Surface.Type.FAIRWAY, Surface.Type.GREEN, Surface.Type.TEE, Surface.Type.SAND]:
			play.append(s)
	for cj in ch:
		for ci in cw:
			var p := c.sample_pos(mini(ci * step + step / 2, c.cols - 1), mini(cj * step + step / 2, c.rows - 1))
			if cover.class_at(frame.lat_of(p), frame.lon_of(p)) != LandCover.WATER:
				continue
			var dry_play := false
			for s in play:
				if s.bounds().grow(LandCover.RES).has_point(p) and s.signed_distance(p) < LandCover.RES:
					dry_play = true
					break
			if not dry_play:
				wet[cj * cw + ci] = 1
	# Joined to the edge: the sea comes in from outside.
	var todo := PackedInt32Array()
	var seen := PackedByteArray()
	seen.resize(cw * ch)
	for k in wet.size():
		var ci := k % cw
		var cj := k / cw
		if wet[k] == 1 and (ci == 0 or cj == 0 or ci == cw - 1 or cj == ch - 1):
			seen[k] = 1
			todo.append(k)
	var at := 0
	while at < todo.size():
		var k := todo[at]
		at += 1
		var ci := k % cw
		var cj := k / cw
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ni := ci + d.x
			var nj := cj + d.y
			if ni < 0 or nj < 0 or ni >= cw or nj >= ch:
				continue
			var nk := nj * cw + ni
			if wet[nk] == 1 and seen[nk] == 0:
				seen[nk] = 1
				todo.append(nk)
	var n := 0
	var floor_h := sea + SEA_FLOOR - base
	for k in todo:
		var ci := k % cw
		var cj := k / cw
		for j in range(cj * step, mini((cj + 1) * step, c.rows)):
			for i in range(ci * step, mini((ci + 1) * step, c.cols)):
				var q := j * c.cols + i
				if c.heights[q] > floor_h:
					c.heights[q] = floor_h
					n += 1
	return n


## True when the course has the sea (not a lake) within LINKS_REACH of its
## box: links land.
static func by_the_sea(c: DesignedCourse) -> bool:
	if not c.source.has("sea") or absf(float(c.source["sea"]) - 0.5 * (SEA_FLAT_LOW + SEA_FLAT_HIGH)) > 0.5 * (SEA_FLAT_HIGH - SEA_FLAT_LOW) or c.landscape.is_empty():
		return false
	var land: Dictionary = c.landscape
	var o: Vector2 = land["origin"]
	var cell := float(land["cell"])
	var cols := int(land["cols"])
	var rows_n := int(land["rows"])
	var hs: PackedFloat32Array = land["heights"]
	var base := float(c.source.get("base_height", 0.0))
	var box := c.area.grow(LINKS_REACH)
	var i0 := clampi(floori((box.position.x - o.x) / cell), 0, cols - 1)
	var i1 := clampi(ceili((box.end.x - o.x) / cell), 0, cols - 1)
	var j0 := clampi(floori((box.position.y - o.y) / cell), 0, rows_n - 1)
	var j1 := clampi(ceili((box.end.y - o.y) / cell), 0, rows_n - 1)
	var wet := 0
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			if hs[j * cols + i] + base < float(c.source["sea"]) - 0.5:
				wet += 1
	return wet >= 20


## Lets the course's own ground down under a lake where it is the lake's
## water surface (lidar measures it a little above the tiles' level:
## Whistling Straits' shore showed a flat green shelf over the water).
static func sink_lake(c: DesignedCourse, lake: float) -> int:
	var base := float(c.source.get("base_height", 0.0))
	var n := 0
	for k in c.heights.size():
		var h := c.heights[k] + base
		var low := under_lake(h, lake)
		if low < h:
			c.heights[k] = low - base
			n += 1
	return n


## Ground `h` near a lake's `level` steepened down under its water: the
## same above LAKE_SHORE over it, LAKE_STEEP times as far under below,
## so the water's flat surface in the data goes under and the shore keeps
## its line (a fixed drop drew it as a sawtooth on the 2 m grid).
static func under_lake(h: float, level: float) -> float:
	var top := level + LAKE_SHORE
	return h if h >= top else top - (top - h) * LAKE_STEEP


## True when hardly any of the course's own ground lies below sea level
## (or the lake's `level`, counting from `margin` above it): the sea can't
## be let in over a course whose heights are wrong, or a polder. A lake
## counts from a metre under its level, since the course's own ground
## (lidar) takes in the lake's water surface along its shore.
static func dry(c: DesignedCourse, level := 0.0, margin := 0.3) -> bool:
	var base := float(c.source.get("base_height", 0.0))
	var low := 0
	var n := 0
	# The play areas, where there are any: a course's box takes in the sea
	# beside it (Kingsbarns' is half North Sea). Holes along the shore may
	# dip under in coarse tiles (Teeth of the Dog), so most of the play
	# must stand well clear of the water and only a few points under it;
	# wrong heights (zeros) or a polder put most of it low.
	var hs := PackedFloat32Array()
	for s in c.shapes:
		if s.surface in [Surface.Type.FAIRWAY, Surface.Type.GREEN, Surface.Type.TEE]:
			for p in s.points:
				var h := c.base_height(p.x, p.y) + base
				hs.append(h)
				if h < level + margin:
					low += 1
	n = hs.size()
	if n >= 20:
		hs.sort()
		return low <= n * PLAY_LOW_SHARE and hs[n / 2] >= level + PLAY_CLEAR
	low = 0
	n = 0
	for k in range(0, c.heights.size(), 37):
		n += 1
		if c.heights[k] + base < level + margin:
			low += 1
	return n > 0 and low <= n * 0.01


## As DesignedCourse saves it (LAND_ENCODING).
func encode() -> Dictionary:
	var raw := PackedByteArray()
	raw.resize(heights.size() * 2)
	var last := 0
	for k in heights.size():
		var dm := clampi(roundi(heights[k] * 10.0), -300000, 300000)
		raw.encode_s16(k * 2, clampi(dm - last, -32767, 32767))
		last += clampi(dm - last, -32767, 32767)
	return {"origin": [origin.x, origin.y], "cell": CELL, "cols": count, "rows": count,
		"heights": {"encoding": DesignedCourse.LAND_ENCODING, "count": heights.size(),
			"data": Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))}}
