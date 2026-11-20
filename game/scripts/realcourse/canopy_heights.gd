class_name CanopyHeights
extends RefCounted
## Tree heights from Meta and the World Resources Institute's global canopy
## height map, version 2 (CC BY 4.0, AWS Open Data), for courses whose
## lidar has no surface model (Scotland, Wales, the US, everywhere
## Mapterhorn covers) or that have no lidar at all.
##
## The map is one 32768 px square Cloud-Optimised GeoTIFF per zoom 10 web
## mercator tile (1.19 m pixels), cut into 512 px Deflate tiles, heights in
## whole metres (255 for no data). Only the course's tiles are downloaded,
## with HTTP range requests: the header (1 KB), the tile offsets and sizes
## for the course's tile rows (a few KB), then each tile (1 to 3 MB for a
## 2.5 km course, where version 1's whole-width rows took 7 to 35 MB).
## Version 2 is Meta's DINOv3 model, which the 2025 release says is closer
## to lidar, above all in tall woods and over hedges.
##
## Desktop only: the bucket sends no cross-site headers, so a web page
## can't read it.
##
##     var c := CanopyHeights.new(box)
##     for p in c.parts: header, then index, then tiles (see RealCourseFetcher)

const URL := "https://dataforgood-fb-data.s3.amazonaws.com/forests/v2/global/dinov3_global_chm_v2_ml3/chm/%s.tif"
const ZOOM := 10
const SIZE := 32768  ## pixels a side of each file
const TILE := 512  ## pixels a side of each compressed tile
const HEADER_BYTES := 1024
const NODATA := 255
const CREDIT := "Tree heights: Meta and World Resources Institute, Global Canopy Height Map v2 (2025), CC BY 4.0"
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


## The file layout from its first HEADER_BYTES: {"offsets", "counts"}
## (file positions of the tile offset and byte count arrays), "entry" (4 or
## 8 bytes each), "across" (tiles a row) and "predictor", or {} for anything
## but the expected tiled TIFF or BigTIFF (8-bit, Deflate, TILE px tiles).
static func parse_header(b: PackedByteArray) -> Dictionary:
	if b.size() < 16 or b[0] != 0x49 or b[1] != 0x49:
		return {}
	var big := b.decode_u16(2) == 43
	if not big and b.decode_u16(2) != 42:
		return {}
	var ifd := b.decode_u64(8) if big else b.decode_u32(4)
	var n := b.decode_u64(ifd) if big and ifd + 8 <= b.size() else (b.decode_u16(ifd) if ifd + 2 <= b.size() else 0)
	var esize := 20 if big else 12
	var first := ifd + (8 if big else 2)
	var tags := {}
	var types := {}
	for k in n:
		var p := first + k * esize
		if p + esize > b.size():
			return {}
		var typ := b.decode_u16(p + 2)
		var count := b.decode_u64(p + 4) if big else b.decode_u32(p + 4)
		var value := b.decode_u64(p + 12) if big else b.decode_u32(p + 8)
		if count == 1 and typ == 3:
			value = b.decode_u16(p + 12 if big else p + 8)
		elif count == 1 and typ == 4 and big:
			value = b.decode_u32(p + 12)
		tags[b.decode_u16(p)] = value
		types[b.decode_u16(p)] = typ
	if int(tags.get(256, 0)) != SIZE or int(tags.get(257, 0)) != SIZE or int(tags.get(258, 0)) != 8:
		return {}
	if int(tags.get(259, 0)) != 8 or int(tags.get(322, 0)) != TILE or int(tags.get(323, 0)) != TILE:
		return {}
	if not tags.has(324) or not tags.has(325):
		return {}
	var entry := 8 if int(types[324]) == 16 else 4
	if entry != (8 if int(types[325]) == 16 else 4):
		return {}
	return {"offsets": int(tags[324]), "counts": int(tags[325]), "entry": entry, "across": SIZE / TILE,
		"predictor": int(tags.get(317, 1))}


## The part's tiles, [tile column, tile row] in the file.
static func tiles_for(part: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for ty in range(int(part["r0"]) / TILE, int(part["r1"]) / TILE + 1):
		for tx in range(int(part["c0"]) / TILE, int(part["c1"]) / TILE + 1):
			out.append(Vector2i(tx, ty))
	return out


## Byte range (first, last) of the `which` ("offsets" or "counts") entries
## for every tile in the part's tile rows.
static func index_range(header: Dictionary, which: String, part: Dictionary) -> Vector2i:
	var e := int(header["entry"])
	var across := int(header["across"])
	var first := int(header[which]) + e * across * (int(part["r0"]) / TILE)
	return Vector2i(first, int(header[which]) + e * across * (int(part["r1"]) / TILE + 1) - 1)


## Where tile `t` sits in the file, from index_range()'s offsets and counts
## (inclusive); x = -1 for a tile with no data (the sea).
static func tile_range(header: Dictionary, offsets: PackedByteArray, counts: PackedByteArray, part: Dictionary, t: Vector2i) -> Vector2i:
	var e := int(header["entry"])
	var k := ((t.y - int(part["r0"]) / TILE) * int(header["across"]) + t.x) * e
	if k < 0 or k + e > offsets.size() or k + e > counts.size():
		return Vector2i(-1, -1)
	var at := offsets.decode_u64(k) if e == 8 else offsets.decode_u32(k)
	var n := counts.decode_u64(k) if e == 8 else counts.decode_u32(k)
	if n == 0:
		return Vector2i(-1, -1)
	return Vector2i(at, at + n - 1)


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


## Inflates tile `t` (its bytes in `data`) into the part's `raster`,
## undoing the horizontal predictor; no data and implausible heights read
## as bare ground. False if the tile is damaged.
static func decode_tile(part: Dictionary, header: Dictionary, t: Vector2i, data: PackedByteArray, raster: GeoRaster) -> bool:
	var px := data.decompress_dynamic(TILE * TILE * 2, FileAccess.COMPRESSION_DEFLATE)
	if px.size() != TILE * TILE:
		return false
	var predict := int(header.get("predictor", 1)) == 2
	var c0 := int(part["c0"])
	var r0 := int(part["r0"])
	var i0 := maxi(c0, t.x * TILE)
	var i1 := mini(int(part["c1"]), t.x * TILE + TILE - 1)
	for j in range(maxi(r0, t.y * TILE), mini(int(part["r1"]), t.y * TILE + TILE - 1) + 1):
		var row := (j - t.y * TILE) * TILE
		var base := (j - r0) * raster.width - c0
		var acc := 0
		if predict:
			for i in i0 - t.x * TILE:
				acc = (acc + px[row + i]) & 255
		for i in range(i0, i1 + 1):
			var v := px[row + i - t.x * TILE]
			acc = ((acc + v) & 255) if predict else v
			raster.data[base + i] = float(acc) if acc <= 60 else 0.0
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
