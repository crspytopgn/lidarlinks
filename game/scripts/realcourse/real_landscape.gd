class_name RealLandscape
extends RefCounted
## The real land round a course built from the map, out to the horizon
## (DesignedCourse.landscape, drawn by Landscape): without it a real course
## sat on a flat green apron that showed from every high view and flyover.
## The coarse open elevation tiles give it, LAND_HALF metres each way from
## the course's middle; it follows the course's own ground inside the
## course and eases into the measured land over BLEND metres outside, so
## the two meet without a step. Where the tiles carry a sea floor (they
## measure under the sea) the course gets a sea at sea level.
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

var frame: GeoFrame
var course: DesignedCourse  ## the first course: its ground and datum
var origin := Vector2.ZERO
var count := 0  ## samples each way
var heights := PackedFloat32Array()  ## from the course's datum
var _deep := 0


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
			land -= base
			var dx := maxf(maxf(area.position.x - p.x, p.x - area.end.x), 0.0)
			var dz := maxf(maxf(area.position.y - p.y, p.y - area.end.y), 0.0)
			var w := smoothstep(0.0, BLEND, Vector2(dx, dz).length())
			heights[j * count + i] = lerpf(course.base_height(p.x, p.y), land, w)


## True when the land holds a sea.
func has_sea() -> bool:
	return _deep >= heights.size() * SEA_SHARE


## Gives `c` (a course of the club, on the same frame) the land.
func apply(c: DesignedCourse) -> void:
	var saved := encode()
	c.landscape = DesignedCourse._decode_landscape(saved)
	c._landscape_saved = saved
	if has_sea() and dry(c):
		c.source["sea"] = 0.0


## True when hardly any of the course's own ground lies below sea level: the
## sea can't be let in over a course whose heights are wrong, or a polder.
static func dry(c: DesignedCourse) -> bool:
	var base := float(c.source.get("base_height", 0.0))
	var low := 0
	var n := 0
	for k in range(0, c.heights.size(), 37):
		n += 1
		if c.heights[k] + base < 0.3:
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
