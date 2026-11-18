class_name CanopyHeights
extends RefCounted
## Tree heights from Meta and the World Resources Institute's global 1 m
## canopy height map (CC BY 4.0, AWS Open Data), for courses whose lidar
## has no surface model (Scotland, Wales, the US, everywhere Mapterhorn
## covers) or that have no lidar at all.
##
## The map is one 65536 px square GeoTIFF per zoom 9 web mercator tile
## (about 500 MB each), one Deflate-compressed row per strip, heights in
## whole metres. Only what the course needs is downloaded, with HTTP range
## requests: the header (1 KB), the course rows' offsets and sizes (a few
## KB) and those rows themselves, which are contiguous in the file (7 to
## 35 MB for a 2.5 km course). Each row is the whole tile's width, so only
## the course's columns are kept.
##
## Desktop only: the bucket sends no cross-site headers, so a web page
## can't read it.
##
##     var c := CanopyHeights.new(box)
##     for p in c.parts: header, then index, then rows (see RealCourseFetcher)

const URL := "https://dataforgood-fb-data.s3.amazonaws.com/forests/v1/alsgedi_global_v6_float/chm/%s.tif"
const ZOOM := 9
const SIZE := 65536  ## pixels a side of each file
const HEADER_BYTES := 1024
const CREDIT := "Tree heights: Meta and World Resources Institute, High Resolution Canopy Height Maps (2024), CC BY 4.0"
const MAX_ROWS := 6000  ## about 7 km at the equator: bigger boxes are skipped

## One per file the box touches: {"key", "url", "x", "y", "r0", "r1", "c0", "c1"}
## (rows and columns inclusive, in that file's pixels).
var parts: Array[Dictionary] = []


static func available() -> bool:
	return not OS.has_feature("web")


## The parts covering `box` (south, west, north, east).
func _init(box: Array) -> void:
	var fx0 := TerrainTiles._tile_x(box[1], ZOOM)
	var fx1 := TerrainTiles._tile_x(box[3], ZOOM)
	var fy0 := TerrainTiles._tile_y(box[2], ZOOM)
	var fy1 := TerrainTiles._tile_y(box[0], ZOOM)
	for ty in range(int(fy0), int(fy1) + 1):
		for tx in range(int(fx0), int(fx1) + 1):
			var r0 := clampi(floori((fy0 - ty) * SIZE), 0, SIZE - 1)
			var r1 := clampi(ceili((fy1 - ty) * SIZE), 0, SIZE - 1)
			var c0 := clampi(floori((fx0 - tx) * SIZE), 0, SIZE - 1)
			var c1 := clampi(ceili((fx1 - tx) * SIZE), 0, SIZE - 1)
			if r1 <= r0 or c1 <= c0 or r1 - r0 >= MAX_ROWS:
				continue
			var key := quadkey(tx, ty, ZOOM)
			parts.append({"key": key, "url": URL % key, "x": tx, "y": ty, "r0": r0, "r1": r1, "c0": c0, "c1": c1})


static func quadkey(x: int, y: int, z: int) -> String:
	var q := ""
	for i in range(z - 1, -1, -1):
		q += str(((x >> i) & 1) + (((y >> i) & 1) << 1))
	return q


## The file layout from its first HEADER_BYTES: {"offsets", "counts"} (file
## positions of the strip offset and byte count arrays), or {} for anything
## but the expected BigTIFF (8-bit, Deflate, a strip per row).
static func parse_header(b: PackedByteArray) -> Dictionary:
	if b.size() < 16 or b[0] != 0x49 or b[1] != 0x49 or b.decode_u16(2) != 43:
		return {}
	var ifd := b.decode_u64(8)
	if ifd + 8 > b.size():
		return {}
	var n := b.decode_u64(ifd)
	var tags := {}
	for k in n:
		var p := ifd + 8 + k * 20
		if p + 20 > b.size():
			return {}
		var typ := b.decode_u16(p + 2)
		var count := b.decode_u64(p + 4)
		var value := b.decode_u64(p + 12)
		if count == 1 and typ == 3:
			value = b.decode_u16(p + 12)
		elif count == 1 and typ == 4:
			value = b.decode_u32(p + 12)
		tags[b.decode_u16(p)] = value
	if int(tags.get(256, 0)) != SIZE or int(tags.get(257, 0)) != SIZE or int(tags.get(258, 0)) != 8:
		return {}
	if int(tags.get(259, 0)) != 8 or int(tags.get(278, 0)) != 1 or not tags.has(273) or not tags.has(279):
		return {}
	return {"offsets": int(tags[273]), "counts": int(tags[279]), "predictor": int(tags.get(317, 1))}


## Byte range (first, last) of the strip offsets for a part's rows.
static func offsets_range(header: Dictionary, part: Dictionary) -> Vector2i:
	return Vector2i(int(header["offsets"]) + 8 * int(part["r0"]), int(header["offsets"]) + 8 * (int(part["r1"]) + 1) - 1)


static func counts_range(header: Dictionary, part: Dictionary) -> Vector2i:
	return Vector2i(int(header["counts"]) + 8 * int(part["r0"]), int(header["counts"]) + 8 * (int(part["r1"]) + 1) - 1)


## Where a part's rows sit in the file, from its offsets and counts:
## {"start", "end"} (inclusive), or {} if they aren't one block.
static func rows_block(offsets: PackedByteArray, counts: PackedByteArray) -> Dictionary:
	var n := offsets.size() / 8
	if n == 0 or counts.size() != offsets.size():
		return {}
	var start := offsets.decode_u64(0)
	var pos := start
	for k in n:
		if offsets.decode_u64(k * 8) != pos:
			return {}
		pos += counts.decode_u64(k * 8)
	return {"start": start, "end": pos - 1}


## A raster for a part's columns and rows, ready for decode_rows().
static func raster_for(part: Dictionary) -> GeoRaster:
	var r := GeoRaster.new()
	var x := float(part["x"])
	var y := float(part["y"])
	r.width = int(part["c1"]) - int(part["c0"]) + 1
	r.height = int(part["r1"]) - int(part["r0"]) + 1
	r.nodata = -9999.0
	r.data.resize(r.width * r.height)
	r.west = TerrainTiles.tile_lon(x + float(part["c0"]) / SIZE, ZOOM)
	r.north = TerrainTiles.tile_lat(y + float(part["r0"]) / SIZE, ZOOM)
	var east := TerrainTiles.tile_lon(x + float(int(part["c1"]) + 1) / SIZE, ZOOM)
	var south := TerrainTiles.tile_lat(y + float(int(part["r1"]) + 1) / SIZE, ZOOM)
	r.dlon = (east - r.west) / r.width
	r.dlat = (r.north - south) / r.height
	return r


## Inflates rows j0 to j1 (of the part's rows) from `rows` (the block
## rows_block() named) into `raster`, undoing the horizontal predictor.
## False if a row is damaged.
static func decode_rows(part: Dictionary, header: Dictionary, counts: PackedByteArray, rows: PackedByteArray, pos: Array, raster: GeoRaster, j0: int, j1: int) -> bool:
	var c0 := int(part["c0"])
	var c1 := int(part["c1"])
	var predict := int(header.get("predictor", 1)) == 2
	for j in range(j0, j1):
		var size := counts.decode_u64(j * 8)
		var at: int = pos[0]
		pos[0] = at + size
		if at + size > rows.size():
			return false
		var row := rows.slice(at, at + size).decompress_dynamic(SIZE * 2, FileAccess.COMPRESSION_DEFLATE)
		if row.size() != SIZE:
			return false
		var base := j * raster.width
		var acc := 0
		if predict:
			for i in c0:
				acc = (acc + row[i]) & 255
		for i in range(c0, c1 + 1):
			acc = ((acc + row[i]) & 255) if predict else row[i]
			raster.data[base + i - c0] = float(acc) if acc <= 60 else 0.0
	return true


## Rows j0 to j1 of `smooth` (raster.width * raster.height): the whole-metre
## heights averaged over a plus of pixels, so a crown has one top rather than
## a flat plateau for NationalLidar.crowns_in_rows().
static func smooth_rows(raster: GeoRaster, smooth: PackedFloat32Array, j0: int, j1: int) -> void:
	var w := raster.width
	var d := raster.data
	for j in range(maxi(j0, 1), mini(j1, raster.height - 1)):
		for i in range(1, w - 1):
			var k := j * w + i
			smooth[k] = (d[k] * 4.0 + d[k - 1] + d[k + 1] + d[k - w] + d[k + w]) / 8.0


## The crowns whose tops sit in rows j0 to j1 of `smooth` (smooth_rows over
## all of it), appended to `out` as {"lat", "lon", "height"}: the highest
## pixel within 1.5 m (ties go to the first in reading order), at least
## `min_height` tall, one per `spacing` metres. The map has no buildings,
## so unlike the lidar's there is no roof test.
static func crowns_in_rows(raster: GeoRaster, smooth: PackedFloat32Array, out: Array[Dictionary], taken: Dictionary, j0: int, j1: int, min_height := 3.0, spacing := 4.0) -> void:
	var w := raster.width
	var h := raster.height
	var m_px := maxf(raster.dlat * 111000.0, 0.1)
	var r := clampi(roundi(1.5 / m_px), 1, 4)
	for j in range(maxi(j0, r), mini(j1, h - r)):
		for i in range(r, w - r):
			var c := smooth[j * w + i]
			if c < min_height:
				continue
			var peak := true
			for dj in range(-r, r + 1):
				for di in range(-r, r + 1):
					var v := smooth[(j + dj) * w + i + di]
					if v > c or (v == c and (dj < 0 or (dj == 0 and di < 0))):
						peak = false
						break
				if not peak:
					break
			if not peak:
				continue
			var lat := raster.pixel_lat(j)
			var lon := raster.pixel_lon(i)
			var cell := Vector2i(floori(lat * 111000.0 / spacing), floori(lon * 111000.0 * cos(deg_to_rad(lat)) / spacing))
			if taken.has(cell):
				continue
			taken[cell] = true
			out.append({"lat": lat, "lon": lon, "height": c})
