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
## A lake when this share of the land is one flat surface (to LAKE_FLAT
## metres) with hardly any land below it: the tiles hold big lakes level.
const LAKE_SHARE := 0.03
const LAKE_FLAT := 0.05
const LAKE_SHORE := 0.6  ## metres above or below its level the course's ground may be its water
const LAKE_SINK := 3.0  ## metres its surface in the tiles is let down under the water

var frame: GeoFrame
var course: DesignedCourse  ## the first course: its ground and datum
var origin := Vector2.ZERO
var count := 0  ## samples each way
var heights := PackedFloat32Array()  ## from the course's datum
var _deep := 0
var _levels := {}  ## samples by their height in LAKE_FLAT steps
var _lake_sunk := false


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
	return _deep >= heights.size() * SEA_SHARE


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
	var lake := NAN if has_sea() else lake_level()
	if not is_nan(lake) and not _lake_sunk:
		# The lake's flat surface lowered under its water, so the two don't
		# flicker through each other.
		_lake_sunk = true
		var base := float(course.source.get("base_height", 0.0))
		for k in heights.size():
			if absf(heights[k] + base - lake) <= LAKE_FLAT * 1.5:
				heights[k] -= LAKE_SINK
	var saved := encode()
	c.landscape = DesignedCourse._decode_landscape(saved)
	c._landscape_saved = saved
	if has_sea() and dry(c):
		c.source["sea"] = 0.0
	elif not is_nan(lake) and dry(c, lake, -1.0):
		c.source["sea"] = lake
		sink_lake(c, lake)


## Lets the course's own ground down under a lake where it is the lake's
## flat water surface (lidar measures it a little above the tiles' level:
## Whistling Straits' shore showed a flat green shelf over the water).
static func sink_lake(c: DesignedCourse, lake: float) -> int:
	var base := float(c.source.get("base_height", 0.0))
	var sunk := PackedInt32Array()
	for j in range(1, c.rows - 1):
		for i in range(1, c.cols - 1):
			var k := j * c.cols + i
			var h := c.heights[k]
			if absf(h + base - lake) > LAKE_SHORE:
				continue
			var flat := true
			for o in [-1, 1, -c.cols, c.cols]:
				if absf(c.heights[k + o] - h) > 0.08:
					flat = false
					break
			if flat:
				sunk.append(k)
	for k in sunk:
		c.heights[k] -= LAKE_SINK
	return sunk.size()


## True when hardly any of the course's own ground lies below sea level
## (or the lake's `level`, counting from `margin` above it): the sea can't
## be let in over a course whose heights are wrong, or a polder. A lake
## counts from a metre under its level, since the course's own ground
## (lidar) takes in the lake's water surface along its shore.
static func dry(c: DesignedCourse, level := 0.0, margin := 0.3) -> bool:
	var base := float(c.source.get("base_height", 0.0))
	var low := 0
	var n := 0
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
