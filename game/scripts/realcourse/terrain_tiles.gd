class_name TerrainTiles
extends RefCounted
## Ground heights from the open "Terrarium" elevation tiles (the Mapzen
## terrain tiles on AWS Open Data). Each tile is a 256 px PNG in web
## mercator whose colour is the height: (R * 256 + G + B / 256) - 32768 m.
## The tiles merge the best open data for each place: national lidar where
## it is open (England, the US, New Zealand, Norway, Austria and others) and
## SRTM or EU-DEM elsewhere. See docs/real-courses.md.
##
## Usage: for_box() picks the tiles a box needs, add_tile() each PNG as it
## arrives, fill_missing() covers any that failed, then height_at() samples
## the mosaic.

const URL := "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/%d/%d/%d.png"
const TILE := 256
const MAX_ZOOM := 15  ## the finest level the tiles have
const MAX_TILES := 36
## Share of whole-metre pixels that marks rounded data: fine data has about
## 1 in 150 by chance; SRTM resampled to the tiles keeps a third or more
## (Royal County Down 36 %) on its flat shelves.
const WHOLE_SHARE := 0.1
## strip_objects(): the opening's window and its coarse cell, the cut that
## counts as a wood or a house (the data's noise is 1 to 2 m), how much more
## a slope needs (times the rise across half a window), and the most taken.
const OBJECT_WINDOW := 160.0  ## a golf course's tree lines and copses (BeamNG.Earth takes 400 m for city blocks; that reached a coast's shore)
const OBJECT_CELL := 10.0
const OBJECT_THRESHOLD := 2.0
const OBJECT_SLOPE_K := 0.35
const OBJECT_MAX_CUT := 30.0
const OBJECT_SHORE := 2.0  ## metres over the sea the cut stops at
## ...and the relief (highest less lowest opened ground over OBJECT_RELIEF)
## under which the cut is whole, over which there is none.
const OBJECT_RELIEF := 600.0
const OBJECT_FLAT := 40.0
const OBJECT_HILLS := 90.0

var zoom := MAX_ZOOM
var origin := Vector2i.ZERO  ## the top-left tile
var count := Vector2i.ONE  ## tiles across and down
var loaded := 0
var _h := PackedFloat32Array()
var _have := PackedByteArray()  ## per tile: 1 once its PNG is in


## Tiles covering the box (south, west, north, east in degrees), at the
## finest zoom that needs at most MAX_TILES.
static func for_box(south: float, west: float, north: float, east: float) -> TerrainTiles:
	var t := TerrainTiles.new()
	for z in range(MAX_ZOOM, 9, -1):
		var x0 := int(_tile_x(west, z))
		var y0 := int(_tile_y(north, z))
		var n := Vector2i(int(_tile_x(east, z)) - x0 + 1, int(_tile_y(south, z)) - y0 + 1)
		if n.x * n.y <= MAX_TILES or z == 10:
			t.zoom = z
			t.origin = Vector2i(x0, y0)
			t.count = n
			break
	t._h.resize(t.count.x * t.count.y * TILE * TILE)
	t._have.resize(t.count.x * t.count.y)
	return t


## URLs of every tile, in the order add_tile() takes their index.
func urls() -> PackedStringArray:
	var out := PackedStringArray()
	for j in count.y:
		for i in count.x:
			out.append(URL % [zoom, origin.x + i, origin.y + j])
	return out


## Decodes tile `index` (row by row from the top left) from its PNG bytes.
func add_tile(index: int, png: PackedByteArray) -> bool:
	var img := Image.new()
	if png.size() < 8 or png.slice(0, 4) != PackedByteArray([0x89, 0x50, 0x4E, 0x47]):
		return false
	if img.load_png_from_buffer(png) != OK or img.get_width() != TILE or img.get_height() != TILE:
		return false
	img.convert(Image.FORMAT_RGB8)
	set_tile_rgb(index, img.get_data())
	return true


## Fills tile `index` from raw RGB8 bytes (TILE * TILE * 3).
func set_tile_rgb(index: int, rgb: PackedByteArray) -> void:
	var w := count.x * TILE
	var ox := (index % count.x) * TILE
	var oy := floori(float(index) / count.x) * TILE
	for y in TILE:
		var row := (oy + y) * w + ox
		var src := y * TILE * 3
		for x in TILE:
			var k := src + x * 3
			_h[row + x] = rgb[k] * 256.0 + rgb[k + 1] + rgb[k + 2] / 256.0 - 32768.0
	if _have[index] == 0:
		_have[index] = 1
		loaded += 1


func complete() -> bool:
	return loaded == _have.size()


## Sets tiles that never arrived to the mean of the ones that did, so a
## failed download gives flat ground there instead of a pit.
func fill_missing() -> void:
	if complete():
		return
	var sum := 0.0
	var n := 0
	var w := count.x * TILE
	for index in _have.size():
		if _have[index] == 1:
			var ox := (index % count.x) * TILE
			var oy := floori(float(index) / count.x) * TILE
			for y in range(0, TILE, 16):
				for x in range(0, TILE, 16):
					sum += _h[(oy + y) * w + ox + x]
					n += 1
	var mean := sum / n if n > 0 else 0.0
	for index in _have.size():
		if _have[index] == 0:
			var ox := (index % count.x) * TILE
			var oy := floori(float(index) / count.x) * TILE
			for y in TILE:
				for x in TILE:
					_h[(oy + y) * w + ox + x] = mean


## Height in metres at a latitude and longitude, bilinear between pixels.
## Points outside the tiles read the nearest edge.
func height_at(lat: float, lon: float) -> float:
	var w := count.x * TILE
	var h := count.y * TILE
	# Pixel centres sit at +0.5. (Scalars, not a Vector2: tile coordinates
	# need more than 32-bit precision.)
	var u := clampf((_tile_x(lon, zoom) - origin.x) * TILE - 0.5, 0.0, w - 1.001)
	var v := clampf((_tile_y(lat, zoom) - origin.y) * TILE - 0.5, 0.0, h - 1.001)
	var i := int(u)
	var j := int(v)
	var fu := u - i
	var fv := v - j
	var k := j * w + i
	var a := lerpf(_h[k], _h[k + 1], fu)
	var b := lerpf(_h[k + w], _h[k + w + 1], fu)
	return lerpf(a, b, fv)


## The height step the tiles' source was rounded to: 1 m where most of
## their pixels are whole metres (SRTM and other open data stored as whole
## metres, which on flat links land reads as terraces a metre high and tens
## of metres wide), else 0.
func height_step() -> float:
	var n := 0
	var whole := 0
	for k in range(0, _h.size(), 97):
		if _have[_tile_of(k)] == 0:
			continue
		n += 1
		if absf(_h[k] - roundf(_h[k])) < 0.003:
			whole += 1
	return 1.0 if n >= 100 and whole >= n * WHOLE_SHARE else 0.0


## Takes the tree stands and buildings out of coarse ground. SRTM and the
## like measure the first thing the radar meets: a wood stands 5 to 20 m
## over the clearing beside it, so fairways cut through trees ran in
## trenches. A morphological opening (the lowest surface a window of
## OBJECT_WINDOW can reach from below) keeps the ground's shapes wider than
## the window; what it cuts beyond a threshold (higher on slopes, where a
## narrow knoll is real) is taken off where `is_object` (lat, lon) says
## woods or houses stand, softly at its edge. Dunes, banks and knolls in
## the open stay. `kind` (lat, lon) says 1 for woods and houses, 2 for
## water (left out of the opening: by a coast it would take everything down
## to the sea), 0 for open ground. (The method is BeamNG.Earth's
## dsmground.py, MIT.)
## Returns the most taken off anywhere, in metres.
func strip_objects(kind: Callable) -> float:
	var w := count.x * TILE
	var h := count.y * TILE
	var lat := tile_lat(origin.y + count.y * 0.5, zoom)
	var px := pixel_metres(lat)
	var k := maxi(1, roundi(OBJECT_CELL / px))  # pixels a coarse cell
	var cw := ceili(float(w) / k)
	var ch := ceili(float(h) / k)
	var cell := px * k
	var g := PackedFloat32Array()
	g.resize(cw * ch)
	var kinds := PackedByteArray()
	kinds.resize(cw * ch)
	var dry := PackedFloat32Array()
	dry.resize(cw * ch)
	for j in ch:
		var y := origin.y + (j * k + 0.5) / TILE
		var la := tile_lat(y, zoom)
		for i in cw:
			var q := j * cw + i
			g[q] = _h[mini(j * k, h - 1) * w + mini(i * k, w - 1)]
			kinds[q] = int(kind.call(la, tile_lon(origin.x + (i * k + 0.5) / TILE, zoom)))
			dry[q] = INF if kinds[q] == 2 else g[q]
	var r := maxi(1, roundi(OBJECT_WINDOW * 0.5 / cell))
	var eroded := _box_filter(dry, cw, ch, r, false)
	for q in eroded.size():
		if is_inf(eroded[q]):
			eroded[q] = -INF  # all water: no part in the dilation
	var opened := _box_filter(eroded, cw, ch, r, true)
	# The local relief of the opened ground: hills and cliffs (a village on
	# a bluff) are left alone, only fairly flat land is cut fully.
	var rr2 := maxi(1, roundi(OBJECT_RELIEF * 0.5 / cell))
	var high_in := opened.duplicate()
	var low_in := opened.duplicate()
	for q in opened.size():
		if is_inf(opened[q]) or kinds[q] == 2:
			high_in[q] = -INF
			low_in[q] = INF
	var top := _box_filter(high_in, cw, ch, rr2, true)
	var low := _box_filter(low_in, cw, ch, rr2, false)
	var cut := PackedFloat32Array()
	cut.resize(g.size())
	var rr := maxi(1, r / 2)
	for j in ch:
		for i in cw:
			var q := j * cw + i
			var c := g[q] - opened[q]
			if c <= OBJECT_THRESHOLD or kinds[q] != 1 or is_inf(opened[q]):
				continue
			# The opened ground's rise across half a window.
			var dx := opened[j * cw + mini(i + rr, cw - 1)] - opened[j * cw + maxi(i - rr, 0)]
			var dz := opened[mini(j + rr, ch - 1) * cw + i] - opened[maxi(j - rr, 0) * cw + i]
			var thr := OBJECT_THRESHOLD + OBJECT_SLOPE_K * sqrt(dx * dx + dz * dz) * 0.5
			var soft := clampf((c - thr) / OBJECT_THRESHOLD, 0.0, 1.0)
			soft *= clampf((OBJECT_HILLS - (top[q] - low[q])) / (OBJECT_HILLS - OBJECT_FLAT), 0.0, 1.0)
			if soft <= 0.0:
				continue
			# Never down to the sea: woods don't stand in it, and by a coast the
			# opening reaches the shore's own level (Teeth of the Dog's palms).
			cut[q] = clampf(minf(c, OBJECT_MAX_CUT) * soft, 0.0, maxf(0.0, g[q] - OBJECT_SHORE))
	# Back to the pixels, bilinear between the coarse cells, only where
	# one of a block's corners has a cut.
	var most := 0.0
	for j in ch:
		var j1 := mini(j + 1, ch - 1)
		for i in cw:
			var i1 := mini(i + 1, cw - 1)
			var c00 := cut[j * cw + i]
			var c10 := cut[j * cw + i1]
			var c01 := cut[j1 * cw + i]
			var c11 := cut[j1 * cw + i1]
			if c00 <= 0.0 and c10 <= 0.0 and c01 <= 0.0 and c11 <= 0.0:
				continue
			most = maxf(most, maxf(maxf(c00, c10), maxf(c01, c11)))
			for y in range(j * k, mini((j + 1) * k, h)):
				var fv := float(y - j * k) / k
				var row := y * w
				for x in range(i * k, mini((i + 1) * k, w)):
					var fu := float(x - i * k) / k
					_h[row + x] -= lerpf(lerpf(c00, c10, fu), lerpf(c01, c11, fu), fv)
	return most


## The running minimum (or maximum) over a (2r + 1) square, rows then
## columns, by van Herk's blocks (a few steps a sample, whatever r is).
static func _box_filter(a: PackedFloat32Array, cw: int, ch: int, r: int, take_max: bool) -> PackedFloat32Array:
	return _run_filter(_run_filter(a, cw, ch, r, take_max, true), cw, ch, r, take_max, false)


static func _run_filter(a: PackedFloat32Array, cw: int, ch: int, r: int, take_max: bool, along_rows: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(a.size())
	var n := cw if along_rows else ch
	var lines := ch if along_rows else cw
	var size := 2 * r + 1
	var line := PackedFloat32Array()
	line.resize(n + 2 * r)
	var pre := PackedFloat32Array()
	pre.resize(line.size())
	var suf := PackedFloat32Array()
	suf.resize(line.size())
	for l in lines:
		for t in line.size():
			var p := clampi(t - r, 0, n - 1)
			line[t] = a[l * cw + p] if along_rows else a[p * cw + l]
		for t in line.size():
			if t % size == 0:
				pre[t] = line[t]
			else:
				pre[t] = maxf(pre[t - 1], line[t]) if take_max else minf(pre[t - 1], line[t])
		for t in range(line.size() - 1, -1, -1):
			if t == line.size() - 1 or (t + 1) % size == 0:
				suf[t] = line[t]
			else:
				suf[t] = maxf(suf[t + 1], line[t]) if take_max else minf(suf[t + 1], line[t])
		for p in n:
			# The window [p, p + 2r] of the padded line.
			var v := maxf(suf[p], pre[p + 2 * r]) if take_max else minf(suf[p], pre[p + 2 * r])
			if along_rows:
				out[l * cw + p] = v
			else:
				out[p * cw + l] = v
	return out


func _tile_of(k: int) -> int:
	var w := count.x * TILE
	return (floori(float(k) / w) / TILE) * count.x + (k % w) / TILE


## Ground size of one pixel at a latitude, in metres.
func pixel_metres(lat: float) -> float:
	return 40075016.7 * cos(deg_to_rad(lat)) / (TILE * pow(2.0, zoom))


## Fractional tile column (web mercator) of a longitude at a zoom.
static func _tile_x(lon: float, z: int) -> float:
	return (lon + 180.0) / 360.0 * pow(2.0, z)


## Fractional tile row of a latitude at a zoom.
static func _tile_y(lat: float, z: int) -> float:
	var phi := deg_to_rad(clampf(lat, -85.0, 85.0))
	return (1.0 - log(tan(phi) + 1.0 / cos(phi)) / PI) * 0.5 * pow(2.0, z)


## Longitude of a (fractional) tile column at a zoom.
static func tile_lon(x: float, z: int) -> float:
	return x / pow(2.0, z) * 360.0 - 180.0


## Latitude of a (fractional) tile row at a zoom.
static func tile_lat(y: float, z: int) -> float:
	return rad_to_deg(atan(sinh(PI * (1.0 - 2.0 * y / pow(2.0, z)))))
