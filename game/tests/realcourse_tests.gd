extends RefCounted
## Checks for the real-course importer (game/scripts/realcourse/) on a small
## made-up map, so they need no network: GeoFrame, TerrainTiles decoding,
## and RealCourseBuilder turning OpenStreetMap-style data into a course.

var failures: Array[String] = []


func run_all() -> Array[String]:
	_test_scripts_compile()
	_test_geo_frame()
	_test_terrain_tiles()
	_test_simplify()
	_test_builder()
	_test_geo_raster()
	_test_strip_objects()
	_test_national_lidar()
	_test_photo_trees()
	_test_extra_trees()
	_test_photo_ground()
	_test_land_cover()
	_test_guesser()
	_test_detector()
	_test_megascans_cards()
	_test_stone_walls()
	_test_buildings()
	_test_real_world_fixes()
	_test_far_woods()
	_test_retries()
	_test_map_servers()
	_test_playable_on_a_hillside()
	_test_terraces_eased_out()
	_test_streams_hold_water()
	_test_island_green_kept_dry()
	_test_missing_holes_counted()
	_test_pin_off_a_bank()
	_test_unlabelled_courses_parted()
	_test_native_grass()
	_test_playability_steps()
	_test_courses_at_a_club()
	_test_boundary_by_name()
	_test_lines_of_play()
	_test_holes_checked_early()
	_test_search_ranking()
	_test_landscape()
	_test_tee_off_the_last_green()
	_test_pin_out_of_the_pond()
	_test_lidar_must_agree()
	return failures


func check(cond: bool, what: String) -> void:
	if not cond:
		failures.append(what)


func _test_scripts_compile() -> void:
	for path in ["res://scripts/realcourse/real_course_fetcher.gd", "res://scripts/realcourse/real_course_dialog.gd", "res://shaders/aerial_photo.gdshader"]:
		if path.ends_with(".gdshader"):
			check(load(path) is Shader, "%s loads" % path)
			continue
		var script: GDScript = load(path)
		check(script != null and script.can_instantiate(), "%s compiles" % path)


func _test_geo_frame() -> void:
	var f := GeoFrame.new(56.35, -2.81)
	var east := f.to_local(56.35, -2.80)
	var north := f.to_local(56.36, -2.81)
	check(east.x < -600.0 and east.x > -630.0 and absf(east.y) < 0.01, "0.01 deg east at 56 N is about 617 m, on -x: %s" % east)
	check(north.y > 1110.0 and north.y < 1115.0 and absf(north.x) < 0.01, "0.01 deg north is about 1113 m, on +z: %s" % north)
	var p := Vector2(-250.0, 400.0)
	check(f.to_local(f.lat_of(p), f.lon_of(p)).distance_to(p) < 0.001, "GeoFrame round trip")
	# To scale: metres per degree against the WGS84 ellipsoid's radii of
	# curvature (computed independently), within 1 cm in 1 km, on both sides
	# of the equator.
	for row in [[52.0, 111267.353, 68678.016], [33.5, 110913.388, 92922.544], [-34.0, 110922.386, 92384.786], [60.0, 111412.287, 55800.002]]:
		var g := GeoFrame.new(row[0], 10.0)
		var dn := g.to_local(row[0] + 0.01, 10.0).y
		var de := -g.to_local(row[0], 10.01).x
		check(absf(dn - row[1] * 0.01) < 0.01 and absf(de - row[2] * 0.01) < 0.01, "to scale at %s: %.3f m north, %.3f m east per 0.01 deg" % [row[0], dn, de])


func _test_terrain_tiles() -> void:
	var t := TerrainTiles.for_box(56.349, -2.812, 56.351, -2.808)
	check(t.zoom == TerrainTiles.MAX_ZOOM and t.count.x * t.count.y <= 4, "a small box needs a few zoom 15 tiles (%d, %s)" % [t.zoom, t.count])
	check(t.urls()[0].ends_with("/15/%d/%d.png" % [t.origin.x, t.origin.y]), "tile url")
	# Height 37.5 m everywhere: 37.5 + 32768 = 32805.5 = 128 * 256 + 37 + 128 / 256.
	var rgb := PackedByteArray()
	for k in TerrainTiles.TILE * TerrainTiles.TILE:
		rgb.append_array(PackedByteArray([128, 37, 128]))
	t.set_tile_rgb(0, rgb)
	check(not t.complete() or t.count == Vector2i.ONE, "one tile in")
	t.fill_missing()
	check(absf(t.height_at(56.35, -2.81) - 37.5) < 0.001, "terrarium decoding: %f" % t.height_at(56.35, -2.81))
	# A real PNG through add_tile.
	var img := Image.create_from_data(TerrainTiles.TILE, TerrainTiles.TILE, false, Image.FORMAT_RGB8, rgb)
	var t2 := TerrainTiles.for_box(56.349, -2.812, 56.351, -2.808)
	check(t2.add_tile(0, img.save_png_to_buffer()), "add_tile reads a PNG")
	check(not t2.add_tile(0, PackedByteArray([1, 2, 3])), "add_tile refuses junk")


func _test_simplify() -> void:
	var circle := PackedVector2Array()
	for i in 400:
		var a := TAU * i / 400.0
		circle.append(Vector2(cos(a), sin(a)) * 30.0)
	var s := RealCourseBuilder.simplify_ring(circle, 0.3)
	check(s.size() >= 8 and s.size() <= RealCourseBuilder.MAX_POINTS, "a 400-point circle simplifies to a few dozen points (%d)" % s.size())
	var line := RealCourseBuilder.simplify_line(PackedVector2Array([Vector2(0, 0), Vector2(5, 0.01), Vector2(10, 0), Vector2(10, 10)]), 0.5)
	check(line.size() == 3, "straight runs collapse (%d)" % line.size())
	# A bunker traced click by click, each click up to half a metre off:
	# smoothed, its edge no longer zigzags, and it keeps its size.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var traced := PackedVector2Array()
	for i in 60:
		var a := TAU * i / 60.0
		traced.append(Vector2(cos(a) * 12.0, sin(a) * 7.0) + Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5)))
	var smooth := RealCourseBuilder.smooth_ring(traced)
	var turns := 0.0
	for i in smooth.size():
		var d0 := smooth[(i + 1) % smooth.size()] - smooth[i]
		var d1 := smooth[(i + 2) % smooth.size()] - smooth[(i + 1) % smooth.size()]
		turns += absf(d0.angle_to(d1))
	check(turns < TAU * 1.15, "a smoothed bunker turns about once round, no zigzags (%.2f turns)" % (turns / TAU))
	var area_in := absf(RealCourseBuilder._ring_area(traced))
	check(absf(absf(RealCourseBuilder._ring_area(smooth)) - area_in) < area_in * 0.01, "smoothing keeps the bunker's area")
	# Roads through a course come in as tarmac at their real width.
	check(is_equal_approx(RealCourseBuilder.road_width({"highway": "residential"}), 5.5), "a residential road is 5.5 m of tarmac")
	check(is_equal_approx(RealCourseBuilder.road_width({"highway": "tertiary", "lanes": "2"}), 6.4), "two lanes are 6.4 m")
	check(RealCourseBuilder.road_width({"highway": "footway"}) == 0.0 and RealCourseBuilder.road_width({"highway": "footway", "surface": "asphalt"}) > 0.0, "only paved footpaths are tarmac")
	check(RealCourseBuilder.road_width({"highway": "service", "tunnel": "yes"}) == 0.0, "tunnels are left out")
	# A four-corner tee keeps its straight sides.
	var tee := RealCourseBuilder.smooth_ring(PackedVector2Array([Vector2(0, 0), Vector2(12, 0), Vector2(12, 20), Vector2(0, 20)]), 1.0, 1)
	var straight := 0
	for p in tee:
		if absf(p.x - 6.0) < 4.0 and absf(p.y) < 0.1:
			straight += 1
	check(tee.size() >= 60 and straight >= 6, "a four-corner tee keeps a straight front (%d points, %d on it)" % [tee.size(), straight])


## A made-up par 4 running north: tee at the south, green at the north,
## a fairway mapped as a two-part multipolygon, a bunker, a pond, a wood,
## a lone tree, a stream and a cart path, inside a golf course boundary.
func _test_builder() -> void:
	var lat0 := 51.0
	var lon0 := -1.0
	var f := GeoFrame.new(lat0, lon0)
	var els: Array = []
	els.append(_way({"leisure": "golf_course", "name": "Test Links"}, f, _rect(Vector2(-150, -250), Vector2(150, 250))))
	els.append(_way({"golf": "hole", "ref": "1", "par": "4", "handicap": "7"}, f, [Vector2(0, -200), Vector2(10, 0), Vector2(0, 160)], false))
	els.append(_way({"golf": "tee"}, f, _rect(Vector2(-6, -210), Vector2(6, -195))))
	els.append(_way({"golf": "tee"}, f, _rect(Vector2(-6, -180), Vector2(6, -170))))
	els.append(_way({"golf": "green"}, f, _rect(Vector2(-15, 145), Vector2(15, 175))))
	els.append({"type": "node", "lat": f.lat_of(Vector2(5, 165)), "lon": f.lon_of(Vector2(5, 165)), "tags": {"golf": "pin"}})
	els.append(_way({"golf": "bunker"}, f, _rect(Vector2(20, 120), Vector2(30, 135))))
	els.append(_way({"natural": "water"}, f, _rect(Vector2(-90, -50), Vector2(-60, -10))))
	els.append(_way({"natural": "wood", "leaf_type": "needleleaved"}, f, _rect(Vector2(60, -100), Vector2(120, 100))))
	els.append({"type": "node", "lat": f.lat_of(Vector2(-40, 40)), "lon": f.lon_of(Vector2(-40, 40)), "tags": {"natural": "tree", "height": "21"}})
	els.append(_way({"waterway": "stream"}, f, [Vector2(-150, 60), Vector2(0, 70), Vector2(150, 60)], false))
	els.append(_way({"golf": "cartpath"}, f, [Vector2(-30, -190), Vector2(-30, 140)], false))
	els.append(_way({"natural": "heath"}, f, _rect(Vector2(-140, 180), Vector2(-60, 240))))
	# The fairway as a multipolygon of two open ways that join into one ring.
	var left := [Vector2(-20, -150), Vector2(-20, 130), Vector2(20, 130)]
	var right := [Vector2(20, 130), Vector2(20, -150), Vector2(-20, -150)]
	els.append({"type": "relation", "tags": {"type": "multipolygon", "golf": "fairway"}, "members": [
		{"type": "way", "role": "outer", "geometry": _geom(f, left)},
		{"type": "way", "role": "outer", "geometry": _geom(f, right)},
	]})
	# A second course nearby whose hole must be left out.
	els.append(_way({"golf": "hole", "ref": "1"}, f, [Vector2(600, 0), Vector2(600, 300)], false))
	var b := RealCourseBuilder.new({"elements": els}, lat0, lon0)
	check(b.course_name == "Test Links", "the course takes the boundary's name (%s)" % b.course_name)
	check(b.area.size.x >= 300.0 + 2 * RealCourseBuilder.MARGIN - 4.0 and b.area.size.x <= 300.0 + 2 * RealCourseBuilder.MARGIN + 4.0,
		"area spans the boundary plus margins (%s)" % b.area)
	var gb := b.geo_box()
	check(gb[0] < lat0 and gb[2] > lat0 and gb[1] < lon0 and gb[3] > lon0, "geo box holds the course")
	# Ground rising 1 m per 100 m northwards.
	var c := b.build(func(lat: float, _lon: float) -> float: return 50.0 + (lat - lat0) * 1113.0)
	check(c.holes.size() == 1, "one hole (the other course's is left out): %d" % c.holes.size())
	check(c.credits.contains("OpenStreetMap"), "credits name OpenStreetMap")
	check(str(c.source.get("kind", "")) == "openstreetmap", "source recorded")
	if c.holes.size() == 1:
		var h := c.holes[0]
		var shift := b.frame.to_local(lat0, lon0)  # the course is centred on its boundary
		check(h.par == 4, "par from the tag")
		check(h.stroke_index == 7, "stroke index from the handicap tag")
		check(h.pin.distance_to(Vector2(5, 165) + shift) < 0.5, "pin from the golf=pin node: %s" % (h.pin - shift))
		check(h.tees.size() == 2, "both tee boxes found: %d" % h.tees.size())
		if h.tees.size() == 2:
			check(h.tees[0].distance_to(Vector2(0, -202.5) + shift) < 1.0, "back tee first: %s" % (h.tees[0] - shift))
		check(h.route.size() == 1, "the dogleg point is an aim point (%d)" % h.route.size())
	var counts := {}
	for s in c.shapes:
		if not s.guessed:
			counts[s.surface] = int(counts.get(s.surface, 0)) + 1
	check(counts.get(Surface.Type.FAIRWAY, 0) == 1, "the fairway relation became one area")
	check(counts.get(Surface.Type.GREEN, 0) == 1 and counts.get(Surface.Type.SAND, 0) == 1 and counts.get(Surface.Type.TEE, 0) == 2, "green, bunker, tees")
	check(counts.get(Surface.Type.WATER, 0) >= 2, "pond and stream are water (%d)" % counts.get(Surface.Type.WATER, 0))
	check(c.paths.size() == 1, "one cart path")
	var pines := 0
	var tall := false
	for o in c.objects:
		if o.id == "tree_pine":
			pines += 1
		if o.scale > 1.45:
			tall = true
	check(pines >= 60, "the needleleaved wood is filled with pines (%d)" % pines)
	check(tall, "the 21 m tree is drawn larger")
	# Heights are kept round zero, so the 5 m rise over the course stays.
	var south := c.base_height(0, c.area.position.y + 2)
	var north := c.base_height(0, c.area.end.y - 2)
	check(absf((north - south) - c.area.size.y / 100.0) < 0.1, "heights follow the ground (%f over %f m)" % [north - south, c.area.size.y])
	# It saves, loads and plays.
	var again := DesignedCourse.from_json(c.to_json())
	check(again != null and again.credits == c.credits and again.holes.size() == 1, "real course round trip")
	var shift2 := b.frame.to_local(lat0, lon0)
	check(again != null and again.cover_at(Vector2(-100, 210) + shift2) == "heath", "the heath keeps its cover through a save")
	var data := c.to_course_data()
	check(data.holes.size() == 1 and data.holes[0].terrain.cover_at(-100 + shift2.x, 210 + shift2.y) == "heath"
		and data.holes[0].terrain.cover_at(0 + shift2.x, 0 + shift2.y) == "", "cover_at: heath on the heath, nothing on the fairway")
	check(data.holes.size() == 1 and data.holes[0].terrain.surface_at(data.holes[0].pin.x, data.holes[0].pin.z) == Surface.Type.GREEN, "the pin is on a green")


func _test_megascans_cards() -> void:
	var cards := MegascansCards.parse(JSON.stringify({"cards": [
		{"uid": "a", "title": "Marram Grass", "kind": "grass", "height_m": 0.9, "roles": ["dune", "links_fescue"], "file": "cards/a.png"},
		{"uid": "b", "title": "Reed Grass", "kind": "reed", "height_m": 1.8, "roles": ["water_edge"], "file": "cards/b.png"},
		{"uid": "c", "title": "Log", "kind": "log", "file": "cards/c.png"},
		{"uid": "d", "kind": "shrub"},
	]}))
	check(cards.size() == 2, "unknown kinds and cards with no file are skipped (%d)" % cards.size())
	check(MegascansCards.for_cover("dune", cards).size() == 1 and MegascansCards.for_cover("wetland", cards)[0]["uid"] == "b", "cards picked by cover")
	check(MegascansCards.for_cover("heath", cards)[0]["uid"] == "a", "heath falls back to links fescue")
	check(MegascansCards.for_cover("", cards).is_empty() and MegascansCards.parse("nonsense").is_empty(), "no cover, no cards")


static func _rect(a: Vector2, b: Vector2) -> Array:
	return [a, Vector2(b.x, a.y), b, Vector2(a.x, b.y), a]


static func _geom(f: GeoFrame, pts: Array) -> Array:
	var out: Array = []
	for p: Vector2 in pts:
		out.append({"lat": f.lat_of(p), "lon": f.lon_of(p)})
	return out


static func _way(tags: Dictionary, f: GeoFrame, pts: Array, _closed := true) -> Dictionary:
	return {"type": "way", "tags": tags, "geometry": _geom(f, pts)}


## A 4 x 3 float GeoTIFF in strips, in both byte orders, plain and with the
## floating-point predictor and Deflate, as the lidar services send them.
func _test_geo_raster() -> void:
	var heights := PackedFloat32Array([10, 11, 12, 13, 20, 21, 22, 23, 30, 31, 32, 33])
	for be in [false, true]:
		for packed in [false, true]:
			var r := GeoRaster.from_tiff(_tiff(heights, 4, 3, be, packed))
			var what := "%s-endian%s" % ["big" if be else "little", " predictor+deflate" if packed else ""]
			check(r != null, "GeoTIFF reads (%s)" % what)
			if r == null:
				continue
			check(r.width == 4 and r.height == 3 and r.data == heights, "GeoTIFF samples (%s): %s" % [what, r.data])
			check(is_equal_approx(r.west, -1.0) and is_equal_approx(r.north, 51.0) and is_equal_approx(r.dlon, 0.001), "GeoTIFF position (%s)" % what)
			# The centre of pixel (1, 1) is 21 m.
			check(absf(r.sample(51.0 - 0.0015, -1.0 + 0.0015) - 21.0) < 0.001, "GeoTIFF sampling (%s)" % what)
	var bil := GeoRaster.from_bil(heights.to_byte_array(), 4, 3, [50.997, -1.0, 51.0, -0.996])
	check(bil != null and absf(bil.sample(51.0 - 0.0015, -1.0 + 0.0015) - 21.0) < 0.001, "BIL raster")
	var gappy := GeoRaster.from_bil(PackedFloat32Array([1, 2, -99999, 4]).to_byte_array(), 2, 2, [0.0, 0.0, 1.0, 1.0])
	check(is_nan(gappy.sample(0.5, 0.5)) and is_equal_approx(gappy.valid_fraction(), 0.75), "no-data pixels read as NAN")
	check(GeoRaster.from_tiff(PackedByteArray([1, 2, 3])) == null, "junk isn't a GeoTIFF")


func _test_strip_objects() -> void:
	# Flat ground at 10 m with a 120 m wood standing 15 m on it, and a dune
	# ridge as narrow standing 8 m in the open.
	var t := TerrainTiles.for_box(51.0, -1.0, 51.004, -0.996)
	t.zoom = 15
	t.count = Vector2i(1, 1)
	t._h.resize(TerrainTiles.TILE * TerrainTiles.TILE)
	t._have.resize(1)
	var px := t.pixel_metres(51.0)
	for y in TerrainTiles.TILE:
		for x in TerrainTiles.TILE:
			var hgt := 10.0
			if absf(x - 64) * px < 60.0 and absf(y - 128) * px < 60.0:
				hgt += 15.0
			if absf(x - 192) * px < 60.0 and absf(y - 128) * px < 60.0:
				hgt += 8.0
			t._h[y * TerrainTiles.TILE + x] = hgt
	var wood_lon := TerrainTiles.tile_lon(t.origin.x + 64.5 / TerrainTiles.TILE, 15)
	var dune_lon := TerrainTiles.tile_lon(t.origin.x + 192.5 / TerrainTiles.TILE, 15)
	var mid_lat := TerrainTiles.tile_lat(t.origin.y + 128.5 / TerrainTiles.TILE, 15)
	var woods := func(_lat: float, lon: float) -> int: return 1 if absf(lon - wood_lon) < absf(lon - dune_lon) else 0
	var most := t.strip_objects(woods)
	check(most > 10.0 and absf(t.height_at(mid_lat, wood_lon) - 10.0) < 1.5, "the wood comes off the ground (%.1f m taken, %.1f m left)" % [most, t.height_at(mid_lat, wood_lon)])
	check(absf(t.height_at(mid_lat, dune_lon) - 18.0) < 0.5, "the dune in the open stays (%.1f m)" % t.height_at(mid_lat, dune_lon))


func _test_national_lidar() -> void:
	check(str(NationalLidar.source_for(51.4, -0.3).get("id", "")) == "ea", "England uses the Environment Agency")
	check(str(NationalLidar.source_for(53.43, -6.12).get("id", "")) != "ea" and str(NationalLidar.source_for(50.1, -5.5).get("id", "")) == "ea", "Dublin is not England, Cornwall is")
	check(str(NationalLidar.source_for(52.2, 5.2).get("id", "")) == "ahn", "the Netherlands use AHN")
	check(str(NationalLidar.source_for(36.57, -121.95).get("id", "")) == "3dep", "California uses 3DEP")
	check(str(NationalLidar.source_for(-33.9, 151.2).get("id", "")) == "mapterhorn", "Sydney tries Mapterhorn")
	check(str(NationalLidar.source_for(56.34, -2.80).get("id", "")) == "mapterhorn", "St Andrews uses Mapterhorn")
	var eng := NationalLidar.sources_for(51.4, -0.3)
	check(eng.size() == 2 and eng[1]["id"] == "mapterhorn", "England falls back to Mapterhorn")
	check(str(NationalLidar.source_for(51.3, 4.55).get("id", "")) == "vl", "Flanders uses DHMV")
	check(str(NationalLidar.source_for(51.23, 6.85).get("id", "")) == "nrw", "Duesseldorf uses Geobasis NRW")
	check(str(NationalLidar.source_for(59.93, 10.75).get("id", "")) == "no", "Oslo uses Kartverket")
	check(str(NationalLidar.source_for(35.6, 139.7).get("id", "")) == "gsi", "Tokyo uses the GSI tiles")
	var both := NationalLidar.sources_for(51.4, 3.8)
	check(both.size() == 3 and both[1]["id"] == "ahn", "Zeeland falls back from Flanders to AHN")
	var vl := NationalLidar.new(_lidar_source("vl"), [51.30, 4.55, 51.302, 4.553])
	check(vl.url(vl.chunks[0], false).contains("BBOX=4.5500000,51.3000000,4.5530000,51.3020000"), "WCS 1.0 box is west, south, east, north")
	_test_gsi_tiles()
	_test_mapterhorn_tiles()
	_test_canopy_heights()
	check(RealCourseBuilder.ref_label("5 - #2") == "No. 2" and RealCourseBuilder.ref_label("A-7") == "A" and RealCourseBuilder.ref_label("12") == "" and RealCourseBuilder.ref_label("3 - TC") == "TC", "course labels in refs")
	var naip := AerialPhotos.new(_photo_source("naip"), [36.56, -121.96, 36.57, -121.94])
	var nu := naip.urls()
	check(naip.block() == 4 and nu.size() == naip.blocks_across().x * naip.blocks_across().y and nu[0].contains("size=1024,1024"), "NAIP asked for in 4 x 4 tile blocks")
	var l := NationalLidar.new(NationalLidar.source_for(51.4, -0.3), [51.40, -0.31, 51.42, -0.28])
	# About 2.1 km by 2.2 km at 1 m: 3 x 3 requests of at most 1000 px.
	check(l.chunks.size() == 9, "chunks: %d" % l.chunks.size())
	check(int(l.chunks[0]["cols"]) <= NationalLidar.CHUNK and int(l.chunks[0]["rows"]) <= NationalLidar.CHUNK, "chunk size")
	var u := l.url(l.chunks[0], false)
	check(u.contains("DTM_1m") and u.contains("subset=Lat(51.4000000,"), "WCS url: " + u)
	check(l.url(l.chunks[0], true).contains("FZ_DSM_1m"), "surface model url")
	# Canopy: a 12 m crown on flat ground, and a flat 8 m roof.
	var ground := PackedFloat32Array()
	var top := PackedFloat32Array()
	for j in 40:
		for i in 40:
			ground.append(5.0)
			var crown := maxf(0.0, 12.0 - Vector2(i - 10, j - 10).length() * 2.5)
			var roof := 8.0 if i >= 25 and i < 35 and j >= 25 and j < 35 else 0.0
			top.append(5.0 + maxf(crown, roof))
	var box := [51.0, -1.0, 51.0004, -0.9994]
	var chunk := {"box": box, "cols": 40, "rows": 40}
	var lt := NationalLidar.new(_lidar_source("ign"), box)
	check(lt.add(chunk, ground.to_byte_array(), false) and lt.add(chunk, top.to_byte_array(), true), "BIL chunks load")
	var trees := lt.find_trees()
	check(trees.size() == 1, "one tree found, the roof skipped (%d)" % trees.size())
	if trees.size() == 1:
		check(absf(float(trees[0]["height"]) - 12.0) < 0.01, "tree height from the canopy")
	# The browser build finds them a chunk at a time, between frames.
	var crowns: Array[Dictionary] = []
	var taken := {}
	for top_chunk in lt.dsm:
		lt.trees_in(top_chunk, crowns, taken)
	check(crowns.size() == trees.size(), "chunk-at-a-time tree search matches (%d)" % crowns.size())
	check(not RealCourseFetcher.light_mode(), "full-size builds off phones and tablets")


func _lidar_source(id: String) -> Dictionary:
	for s: Dictionary in NationalLidar.SOURCES:
		if s["id"] == id:
			return s
	return {}


## Japan's GSI elevation tiles: chunks per layer, the colour code, and the
## finest layer winning where it has heights.
func _test_gsi_tiles() -> void:
	var box := [35.600, 139.690, 35.610, 139.700]
	var l := NationalLidar.new(_lidar_source("gsi"), box)
	var zooms := {}
	for c in l.chunks:
		zooms[(c["tile"] as Vector3i).z] = true
	check(zooms.has(17) and zooms.has(15) and zooms.has(14), "a chunk per tile of each layer")
	check(l.url(l.chunks[0], false).begins_with("https://cyberjapandata.gsi.go.jp/xyz/dem1a_png/17/"), "finest layer first")
	# One coarse tile with heights 12.34 m and -1.5 m, and a fine tile
	# that is all no data.
	var fine := l.chunks[0]
	var coarse: Dictionary = {}
	var fbox: Array = fine["box"]
	for c in l.chunks:
		var t: Vector3i = c["tile"]
		var b: Array = c["box"]
		var mid_lat := (float(fbox[0]) + float(fbox[2])) * 0.5
		var mid_lon := (float(fbox[1]) + float(fbox[3])) * 0.5
		if t.z == 14 and mid_lat > b[0] and mid_lat < b[2] and mid_lon > b[1] and mid_lon < b[3]:
			coarse = c
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	var cm := 1234
	img.fill(Color8((cm >> 16) & 255, (cm >> 8) & 255, cm & 255))
	var neg := 0x1000000 - 150
	img.fill_rect(Rect2i(0, 0, 128, 256), Color8((neg >> 16) & 255, (neg >> 8) & 255, neg & 255))
	check(l.add(coarse, img.save_png_to_buffer(), false), "GSI tile loads")
	var empty := Image.create(256, 256, false, Image.FORMAT_RGB8)
	empty.fill(Color8(128, 0, 0))
	check(l.add(fine, empty.save_png_to_buffer(), false), "an empty fine tile loads")
	var cb: Array = coarse["box"]
	var fb: Array = fine["box"]
	var east := l.ground_at(lerpf(cb[0], cb[2], 0.5), lerpf(cb[1], cb[3], 0.9))
	var west := l.ground_at(lerpf(cb[0], cb[2], 0.5), lerpf(cb[1], cb[3], 0.1))
	check(absf(east - 12.34) < 0.001 and absf(west + 1.5) < 0.001, "GSI heights: %f %f" % [east, west])
	var under := l.ground_at(lerpf(fb[0], fb[2], 0.5), lerpf(fb[1], fb[3], 0.5))
	check(not is_nan(under), "no-data fine tile falls through to the coarse one")
	check(l.coverage() > 0.2, "coverage from the coarse tile: %f" % l.coverage())


## Mapterhorn: 512 px Terrarium WebP tiles, counted four to a 256 px
## tile against the cap.
func _test_mapterhorn_tiles() -> void:
	var box := [56.340, -2.810, 56.350, -2.795]
	var l := NationalLidar.new(_lidar_source("mapterhorn"), box)
	check(not l.chunks.is_empty() and int(l.chunks[0]["cols"]) == 512, "512 px tile chunks")
	check(l.url(l.chunks[0], false).begins_with("https://tiles.mapterhorn.com/16/"), "zoom 16 first")
	var big := NationalLidar.new(_lidar_source("mapterhorn"), [56.30, -2.90, 56.40, -2.70])
	for c in big.chunks:
		check((c["tile"] as Vector3i).z == 15, "a big box skips zoom 16")
		break
	# Height 12.5 m: 32780.5 = R 128, G 12, B 128.
	var img := Image.create(512, 512, false, Image.FORMAT_RGB8)
	img.fill(Color8(128, 12, 128))
	var c0: Dictionary = l.chunks[0]
	check(l.add(c0, img.save_webp_to_buffer(false), false), "WebP Terrarium tile loads")
	var b: Array = c0["box"]
	var h := l.ground_at(lerpf(b[0], b[2], 0.5), lerpf(b[1], b[3], 0.5))
	check(absf(h - 12.5) < 0.01, "Terrarium height: %f" % h)
	check(GeoRaster.from_terrarium(PackedByteArray([1, 2, 3]), b) == null, "junk is no tile")


## The canopy height map: which file and rows a course needs, the BigTIFF
## header, and a row round trip through Deflate and the predictor.
func _test_canopy_heights() -> void:
	check(CanopyHeights.quadkey(250, 158, 9) == "031133230", "quadkey for Gleneagles")
	var c := CanopyHeights.new([56.278, -3.760, 56.292, -3.735])
	check(c.parts.size() == 1 and c.parts[0]["key"] == "031133230", "one file for a course")
	var part: Dictionary = c.parts[0]
	var rows := int(part["r1"]) - int(part["r0"]) + 1
	check(rows > 2000 and rows < 3000, "rows for 1.6 km at 0.66 m: %d" % rows)
	# A BigTIFF header like the map's: 65536 px, 8 bit, Deflate, a strip a row.
	var h := PackedByteArray()
	h.resize(CanopyHeights.HEADER_BYTES)
	h.encode_u16(0, 0x4949)
	h.encode_u16(2, 43)
	h.encode_u64(8, 16)
	var tags := [[256, 4, 65536], [257, 4, 65536], [258, 3, 8], [259, 3, 8], [273, 16, 5000], [278, 3, 1], [279, 16, 9000], [317, 3, 2]]
	h.encode_u64(16, tags.size())
	for k in tags.size():
		var p := 24 + k * 20
		h.encode_u16(p, tags[k][0])
		h.encode_u16(p + 2, tags[k][1])
		h.encode_u64(p + 4, 1 if tags[k][1] != 16 else 65536)
		h.encode_u64(p + 12, tags[k][2])
	var header := CanopyHeights.parse_header(h)
	check(int(header.get("offsets", 0)) == 5000 and int(header.get("counts", 0)) == 9000, "header: %s" % header)
	check(CanopyHeights.offsets_range(header, part).x == 5000 + 8 * int(part["r0"]), "offset index range")
	h.encode_u64(24 + 2 * 20 + 12, 16)
	check(CanopyHeights.parse_header(h).is_empty(), "16-bit maps are refused")
	# Two rows: a 12 m tree at the part's first column, else bare.
	var c0 := int(part["c0"])
	var blob := PackedByteArray()
	var counts := PackedByteArray()
	var offsets := PackedByteArray()
	counts.resize(16)
	offsets.resize(16)
	for j in 2:
		var row := PackedByteArray()
		row.resize(CanopyHeights.SIZE)
		row[c0] = 12  # the predictor stores differences
		row[c0 + 1] = 256 - 12
		var z := row.compress(FileAccess.COMPRESSION_DEFLATE)
		offsets.encode_u64(j * 8, 100 + blob.size())
		counts.encode_u64(j * 8, z.size())
		blob.append_array(z)
	var block := CanopyHeights.rows_block(offsets, counts)
	check(int(block.get("start", 0)) == 100 and int(block.get("end", 0)) == 99 + blob.size(), "rows are one block")
	var small := part.duplicate()
	small["r1"] = int(small["r0"]) + 1
	var raster := CanopyHeights.raster_for(small)
	check(CanopyHeights.decode_rows(small, header, counts, blob, [0], raster, 0, 2), "rows decode")
	check(raster.data[0] == 12.0 and raster.data[1] == 0.0 and raster.data[raster.width] == 12.0, "predictor undone: %s %s" % [raster.data[0], raster.data[1]])
	check(absf(raster.west - TerrainTiles.tile_lon(250.0 + c0 / 65536.0, 9)) < 1e-9, "raster placed at its columns")
	# A cone-shaped crown is found once, at its top.
	var t := GeoRaster.new()
	t.width = 30
	t.height = 30
	t.west = -3.75
	t.north = 56.28
	t.dlon = 0.00001
	t.dlat = 0.000006
	t.data.resize(900)
	for j in 30:
		for i in 30:
			t.data[j * 30 + i] = maxf(0.0, 14.0 - roundf(Vector2(i - 15, j - 15).length()))
	var sm := PackedFloat32Array()
	sm.resize(900)
	CanopyHeights.smooth_rows(t, sm, 0, 30)
	var out: Array[Dictionary] = []
	CanopyHeights.crowns_in_rows(t, sm, out, {}, 0, 30)
	check(out.size() == 1 and float(out[0]["height"]) > 12.0, "one crown at the top (%d)" % out.size())


func _test_photo_trees() -> void:
	# A 100 x 100 m photo at 1 m: light fairway grass with a dark green
	# 12 m clump of trees in the middle.
	var img := Image.create(100, 100, false, Image.FORMAT_RGB8)
	img.fill(Color(0.55, 0.7, 0.35))
	img.fill_rect(Rect2i(44, 44, 12, 12), Color(0.12, 0.22, 0.1))
	var area := Rect2(-50, -50, 100, 100)
	var found := AerialPhotos.find_trees(img, area, PackedVector2Array([Vector2(-30, -30), Vector2(30, 30)]))
	check(found.size() >= 1 and found.size() <= 9, "the clump is found (%d cells)" % found.size())
	for p in found:
		check(p.length() < 10.0, "tree cells are on the clump: %s" % p)
	check(AerialPhotos.source_for(52.2, 5.2).get("id", "") == "pdok", "Dutch photos from PDOK")
	check(AerialPhotos.source_for(48.2, 16.3).get("id", "") == "basemap", "Vienna photos from basemap.at")
	check(AerialPhotos.source_for(35.6, 139.7).get("id", "") == "gsi", "Tokyo photos from GSI")
	check(AerialPhotos.source_for(48.1, 11.6).get("id", "") == "by", "Munich photos from Bavaria")
	check(AerialPhotos.source_for(52.2, 21.0).get("id", "") == "pl", "Warsaw photos from GUGiK")
	check(AerialPhotos.source_for(50.5, 4.9).get("id", "") == "wal", "Namur photos from Wallonia")
	check(AerialPhotos.source_for(-33.87, 151.2).get("id", "") == "nsw", "Sydney photos from NSW")
	check(AerialPhotos.source_for(-37.95, 145.05).get("id", "") == "vic", "Melbourne photos from Vicmap")
	check(AerialPhotos.source_for(-27.5, 153.0).get("id", "") == "qld", "Brisbane photos from Queensland")
	check(AerialPhotos.source_for(50.08, 14.42).get("id", "") == "cz", "Prague photos from CUZK")
	check(AerialPhotos.source_for(37.1, -8.2).get("id", "") == "pt", "Algarve photos from DGT")
	var us := AerialPhotos.sources_for(36.57, -121.95)
	check(us.size() == 2 and us[0]["id"] == "naip" and us[1]["id"] == "usgs", "US: full NAIP, then the basemap")
	for src in AerialPhotos.SOURCES:
		check(src["id"] != AerialPhotos.GUIDE["id"], "the Esri guide is never a build source")
	var guide := AerialPhotos.new(AerialPhotos.GUIDE, [56.340, -2.810, 56.345, -2.800])
	check(guide.urls()[0].contains("World_Imagery/MapServer/tile/%d/%d/%d" % [guide.zoom, guide.origin.y, guide.origin.x]), "guide tile url")
	var ee := AerialPhotos.new(AerialPhotos.source_for(59.437, 24.75), [59.436, 24.749, 59.438, 24.752])
	var eu := ee.urls()[0]
	var ty := (1 << ee.zoom) - 1 - ee.origin.y
	check(eu.ends_with("/%d/%d/%d.jpg" % [ee.zoom, ee.origin.x, ty]), "Estonia TMS rows from the south: " + eu)
	var vl := AerialPhotos.new(AerialPhotos.source_for(51.30, 4.55), [51.300, 4.550, 51.302, 4.553])
	var u := vl.urls()[0]
	var bb := u.get_slice("BBOX=", 1).get_slice("&", 0).split(",")
	check(bb.size() == 4 and absf(float(bb[2]) - float(bb[0]) - 305.748) < 0.01, "WMS tile box in web mercator metres: " + u)
	var white := Image.create(256, 256, false, Image.FORMAT_RGB8)
	white.fill(Color.WHITE)
	check(AerialPhotos.is_blank(white) and not vl.add_tile(0, white.save_jpg_to_buffer()), "white tiles from outside the country don't count")
	var grass := Image.create(256, 256, false, Image.FORMAT_RGB8)
	grass.fill(Color(0.3, 0.45, 0.2))
	grass.fill_rect(Rect2i(0, 0, 100, 100), Color(0.15, 0.25, 0.1))
	check(not AerialPhotos.is_blank(grass), "a photo with a wood in it isn't blank")


## Lidar trees replace the guessed wood fill, and keep off buildings.
func _test_extra_trees() -> void:
	var f := GeoFrame.new(51.0, -1.0)
	var els: Array = []
	els.append(_way({"leisure": "golf_course", "name": "Lidar Links"}, f, _rect(Vector2(-150, -150), Vector2(150, 150))))
	els.append(_way({"golf": "hole", "ref": "1", "par": "3"}, f, [Vector2(0, -80), Vector2(0, 80)], false))
	els.append(_way({"golf": "green"}, f, _rect(Vector2(-10, 70), Vector2(10, 90))))
	els.append(_way({"natural": "wood"}, f, _rect(Vector2(40, -100), Vector2(120, 100))))
	els.append(_way({"building": "yes"}, f, _rect(Vector2(-100, -20), Vector2(-80, 0))))
	var b := RealCourseBuilder.new({"elements": els}, 51.0, -1.0)
	b.lidar_trees = [
		{"lat": b.frame.lat_of(Vector2(60, 0)), "lon": b.frame.lon_of(Vector2(60, 0)), "height": 20.0},
		{"lat": b.frame.lat_of(Vector2(61, 1)), "lon": b.frame.lon_of(Vector2(61, 1)), "height": 18.0},
		{"lat": b.frame.lat_of(Vector2(-90, -10)), "lon": b.frame.lon_of(Vector2(-90, -10)), "height": 9.0},
		{"lat": b.frame.lat_of(Vector2(-50, 40)), "lon": b.frame.lon_of(Vector2(-50, 40)), "height": 11.0},
	]
	b.extra_credits.append("Lidar: test")
	check(b.course_names().is_empty(), "one course: no names to choose from")
	var c := b.build(func(_la: float, _lo: float) -> float: return 10.0)
	check(c.objects.size() == 2, "lidar trees only: the close pair is one tree, none on the building, no wood fill (%d)" % c.objects.size())
	check(c.credits.ends_with("Lidar: test."), "extra credits")
	# Two courses at one club, told apart by golf:course:name.
	var two: Array = [els[0]]
	for n in 18:
		for name in ["Old", "New"]:
			var x := -120.0 + n * 12.0 + (6.0 if name == "New" else 0.0)
			two.append(_way({"golf": "hole", "ref": str(n + 1), "golf:course:name": name}, f, [Vector2(x, -100), Vector2(x, 100)], false))
	var club := RealCourseBuilder.new({"elements": two}, 51.0, -1.0)
	check(Array(club.course_names()) == ["Old", "New"], "both courses named, the Old (the club's main course) first: %s" % club.course_names())
	club.course_filter = "Old"
	var old := club.build(func(_la: float, _lo: float) -> float: return 10.0)
	check(old.holes.size() == 18 and old.course_name == "Old", "the Old course alone (%d holes)" % old.holes.size())


## A strip GeoTIFF of float heights, 0.001 degree pixels from (51 N, 1 W).
static func _tiff(v: PackedFloat32Array, w: int, h: int, be: bool, packed: bool, u8 := false) -> PackedByteArray:
	var pixels := v.to_byte_array()
	if u8:
		pixels = PackedByteArray()
		for x in v:
			pixels.append(int(x))
	if packed:
		# Floating-point predictor: per row, bytes split into planes (most
		# significant first), then differenced.
		var out := PackedByteArray()
		for y in h:
			var row := PackedByteArray()
			row.resize(w * 4)
			for x in w:
				for byte in 4:
					var src := pixels[(y * w + x) * 4 + byte]
					# Planes run most significant byte first in either byte order.
					row[(3 - byte) * w + x] = src
			var prev := 0
			for k in row.size():
				var cur := row[k]
				row[k] = (cur - prev) & 0xFF
				prev = cur
			out.append_array(row)
		pixels = out.compress(FileAccess.COMPRESSION_DEFLATE)
	elif be:
		var swapped := PackedByteArray()
		for k in range(0, pixels.size(), 4):
			swapped.append_array([pixels[k + 3], pixels[k + 2], pixels[k + 1], pixels[k]])
		pixels = swapped
	var entries := [
		[256, 3, 1, w], [257, 3, 1, h], [258, 3, 1, 8 if u8 else 32], [259, 3, 1, 8 if packed else 1],
		[273, 4, 1, 0], [277, 3, 1, 1], [278, 3, 1, h], [279, 4, 1, pixels.size()],
		[317, 3, 1, 3 if packed else 1], [339, 3, 1, 1 if u8 else 3],
		[33550, 12, 3, [0.001, 0.001, 0.0]], [33922, 12, 6, [0.0, 0.0, 0.0, -1.0, 51.0, 0.0]],
	]
	var ifd_size := 2 + entries.size() * 12 + 4
	var extra_at := 8 + ifd_size
	var extra := PackedByteArray()
	var data_at := extra_at + 3 * 8 + 6 * 8
	var b := PackedByteArray()
	b.append_array([0x4D, 0x4D] if be else [0x49, 0x49])
	b.append_array(_be_or_le(42, 2, be))
	b.append_array(_be_or_le(8, 4, be))
	b.append_array(_be_or_le(entries.size(), 2, be))
	for e: Array in entries:
		b.append_array(_be_or_le(e[0], 2, be))
		b.append_array(_be_or_le(e[1], 2, be))
		b.append_array(_be_or_le(e[2], 4, be))
		if e[1] == 12:
			b.append_array(_be_or_le(extra_at + extra.size(), 4, be))
			for d: float in e[3]:
				var x := PackedByteArray()
				x.resize(8)
				x.encode_double(0, d)
				if be:
					x.reverse()
				extra.append_array(x)
		elif e[0] == 273:
			b.append_array(_be_or_le(data_at, 4, be))
		elif e[1] == 3:
			b.append_array(_be_or_le(e[3], 2, be) + PackedByteArray([0, 0]))
		else:
			b.append_array(_be_or_le(e[3], 4, be))
	b.append_array(PackedByteArray([0, 0, 0, 0]))
	b.append_array(extra)
	b.append_array(pixels)
	return b


static func _be_or_le(v: int, size: int, be: bool) -> PackedByteArray:
	var out := PackedByteArray()
	for k in size:
		out.append((v >> (8 * k)) & 0xFF)
	if be:
		out.reverse()
	return out


## The aerial photo tints the ground: a lot beyond the course, a little on
## the fairway, and the photo's west (+x) half lands on the west half.
func _test_photo_ground() -> void:
	var c := DesignedCourse.blank(Vector2(200, 200))
	var fairway := CourseShape.new()
	fairway.surface = Surface.Type.FAIRWAY
	fairway.points = PackedVector2Array([Vector2(-20, -20), Vector2(20, -20), Vector2(20, 20), Vector2(-20, 20)])
	c.shapes.append(fairway)
	var plain := DesignedTerrain.new(c)
	var oob := plain.ground_color_at(-90, 0)
	var mown := plain.ground_color_at(0, 0)
	# A dry, brown photo whose west (left, +x) half is lighter.
	var img := Image.create(200, 200, false, Image.FORMAT_RGB8)
	img.fill(Color(0.55, 0.45, 0.3))
	img.fill_rect(Rect2i(0, 0, 100, 200), Color(0.75, 0.65, 0.45))
	c.set_photo(img)
	var tinted := DesignedTerrain.new(c)
	var east := tinted.ground_color_at(-90, 0)
	var west := tinted.ground_color_at(90, 0)
	check(east.r / east.g > oob.r / oob.g + 0.2, "the field beyond the course turns brown: %s" % east)
	check(west.get_luminance() > east.get_luminance(), "the photo's west half is the course's +x half")
	var m := tinted.ground_color_at(0, 0)
	check(m.g > m.r and absf(m.r - mown.r) + absf(m.g - mown.g) + absf(m.b - mown.b) < 0.2, "the fairway stays green: %s" % m)


## Land cover: an 8-bit class GeoTIFF, trees where the class says so, and
## the ground picture in the photo's layout (north-west pixel first).
func _test_land_cover() -> void:
	var v := PackedFloat32Array()
	for j in 20:
		for i in 20:
			v.append(LandCover.TREES if i < 10 else LandCover.CROPS)
	var land := LandCover.new([50.98, -1.0, 51.0, -0.98])
	check(land.url().contains("bbox=-1.0000000,50.9800000,-0.9800000,51.0000000") and land.url().contains("pixelType=U8"), "land cover url")
	check(land.add(_tiff(v, 20, 20, false, false, true)), "8-bit class GeoTIFF loads")
	check(land.class_at(50.99, -0.995) == LandCover.TREES and land.class_at(50.99, -0.985) == LandCover.CROPS, "classes by place")
	check(absf(land.coverage() - 1.0) < 0.001, "coverage")
	var f := GeoFrame.new(50.99, -0.99)
	var area := Rect2(-800, -1200, 1600, 2400)
	var trees := land.tree_points(f, area)
	check(trees.size() == 200, "one tree per tree pixel: %d" % trees.size())
	var west_side := true
	for p in trees:
		west_side = west_side and p.x > 0.0
	check(west_side, "the trees are in the west (+x) half")
	var img := land.ground_image(f, Rect2(-600, -1000, 1200, 2000), 50.0)
	var nw := img.get_pixel(1, 1)
	var ne := img.get_pixel(img.get_width() - 2, 1)
	var want_nw: Color = LandCover.COLORS[LandCover.TREES]
	var want_ne: Color = LandCover.COLORS[LandCover.CROPS]
	check(absf(nw.r - want_nw.r) + absf(nw.g - want_nw.g) < 0.02 and absf(ne.r - want_ne.r) + absf(ne.g - want_ne.g) < 0.02, "ground picture: woods to the north-west, fields to the north-east")
	# The sea in the course's box (water in the east half) let in under
	# ground the tiles left 10 m up; the west half stays.
	var wv := PackedFloat32Array()
	for j in 20:
		for i in 20:
			wv.append(LandCover.WATER if i >= 10 else LandCover.RANGELAND)
	var wl := LandCover.new([50.98, -1.0, 51.0, -0.98])
	wl.add(_tiff(wv, 20, 20, false, false, true))
	var sc := DesignedCourse.blank(Vector2(600, 400))
	sc.shapes.clear()
	for k in sc.heights.size():
		sc.heights[k] = 10.0
	check(RealLandscape.sea_from_cover(sc, f, wl) == 0, "no sea, nothing let in")
	sc.source["sea"] = 0.0
	var mid := sc.area.get_center()
	check(RealLandscape.sea_from_cover(sc, f, wl) > 0, "the sea in the box is let in")
	check(sc.base_height(mid.x - 200.0, mid.y) < 0.0 and sc.base_height(mid.x + 200.0, mid.y) > 9.0, "under the water (east) only: %.1f, %.1f" % [sc.base_height(mid.x - 200.0, mid.y), sc.base_height(mid.x + 200.0, mid.y)])
	# A pond the map leaves out, from the land cover; none over the fairway.
	var pv := PackedFloat32Array()
	for j in 20:
		for i in 20:
			pv.append(LandCover.WATER if (i >= 8 and i < 12 and j >= 8 and j < 12) or (i >= 2 and i < 5 and j >= 8 and j < 12) else LandCover.RANGELAND)
	var pl := LandCover.new([50.98, -1.0, 51.0, -0.98])
	pl.add(_tiff(pv, 20, 20, false, false, true))
	var pc := DesignedCourse.blank(Vector2(1200, 1200))
	pc.shapes.clear()
	var west_pond := f.to_local(50.99, -0.9965)
	pc.shapes.append(CourseShape.new(Surface.Type.FAIRWAY, PackedVector2Array([west_pond + Vector2(-250, -300), west_pond + Vector2(250, -300), west_pond + Vector2(250, 300), west_pond + Vector2(-250, 300)])))
	check(RealCourseBuilder.add_ponds(pc, f, pl) == 1, "one pond from the land cover, none on the fairway")
	if pc.shapes.size() == 2:
		check(pc.shapes[1].surface == Surface.Type.WATER and pc.shapes[1].contains(f.to_local(50.99, -0.99)), "the pond is where the water is")
	# A links course with no photo: fescue between the holes, a first cut
	# round the fairway.
	var lk := DesignedCourse.blank(Vector2(600, 400))
	lk.shapes.clear()
	var fw := CourseShape.new(Surface.Type.FAIRWAY, PackedVector2Array([Vector2(-100, -20), Vector2(100, -20), Vector2(100, 20), Vector2(-100, 20)]))
	lk.shapes.append(fw)
	var none: Array[PackedVector2Array] = []
	check(RealCourseBuilder.links_fescue(lk, none) == 2, "fescue over the area and a cut round the fairway")
	var lr := DesignedCourse.blank(Vector2(600, 400))
	lr.shapes.clear()
	lr.shapes.append(CourseShape.new(Surface.Type.ROUGH, PackedVector2Array([Vector2(-200, -100), Vector2(200, -100), Vector2(200, 100), Vector2(-200, 100)])))
	RealCourseBuilder.links_fescue(lr, none)
	check(lr.shapes[0].surface == Surface.Type.DEEP_ROUGH, "the mapped rough on a links is fescue")
	# A beach the coarse tiles sank under the sea stands over it again.
	var bc := DesignedCourse.blank(Vector2(200, 200))
	bc.shapes.clear()
	bc.source["sea"] = 0.0
	bc.source["base_height"] = 0.0
	for k in bc.heights.size():
		bc.heights[k] = -1.0
	var strand := CourseShape.new(Surface.Type.SAND, PackedVector2Array([Vector2(-50, -50), Vector2(50, -50), Vector2(50, 50), Vector2(-50, 50)]))
	strand.cover = "beach"
	bc.shapes.append(strand)
	check(RealLandscape.raise_beaches(bc) > 0 and is_equal_approx(bc.base_height(0, 0), RealLandscape.BEACH_TOP) and bc.base_height(90, 90) < 0.0, "a beach stands over the sea, the sea beyond it stays")
	var lt := lk.to_course_data().holes[0].terrain if not lk.holes.is_empty() else null
	var deep := lk.shapes[1]
	var cut := lk.shapes[2]
	check(deep.surface == Surface.Type.DEEP_ROUGH and cut.surface == Surface.Type.ROUGH and cut.contains(Vector2(0, 28)) and not cut.contains(Vector2(0, 40)), "the first cut is 12 m wide")
	check(lt == null or lt.surface_at(0, 60) == Surface.Type.DEEP_ROUGH, "past the cut is fescue")


## A hole mapped only as a line gets a green, a tee, a fairway and bunkers
## at typical sizes, all marked guessed; a fully mapped hole gets nothing.
func _test_guesser() -> void:
	var c := DesignedCourse.blank(Vector2(600, 600))
	var h := DesignedHole.new()
	h.tees = PackedVector2Array([Vector2(0, -200)])
	h.pin = Vector2(0, 180)
	h.par = 4
	c.holes.append(h)
	var added := CourseGuesser.fill(c, 7)
	var by := {}
	for s in added:
		check(s.guessed, "guessed shapes are marked")
		by[s.surface] = int(by.get(s.surface, 0)) + 1
	check(by.get(Surface.Type.GREEN, 0) == 1 and by.get(Surface.Type.TEE, 0) == 1 and by.get(Surface.Type.FAIRWAY, 0) == 1, "green, tee and fairway: %s" % by)
	check(int(by.get(Surface.Type.SAND, 0)) >= 3, "greenside and fairway bunkers: %s" % by)
	var green: CourseShape = null
	var fairway: CourseShape = null
	for s in added:
		if s.surface == Surface.Type.GREEN:
			green = s
		elif s.surface == Surface.Type.FAIRWAY:
			fairway = s
	if green != null:
		var ring := green.outline()
		var a := absf(_ring_area_of(ring))
		check(a > 380.0 and a < 800.0, "green size: %.0f m2" % a)
		check(Geometry2D.is_point_in_polygon(h.pin, ring), "the pin is on the green")
		check(green.bounds().size.y > green.bounds().size.x, "the green is longer along the approach")
	if fairway != null:
		check(Geometry2D.is_point_in_polygon(Vector2(0, 30), fairway.outline()), "the fairway covers the landing area")
		check(fairway.bounds().size.x > 25.0 and fairway.bounds().size.x < 45.0, "fairway width: %.1f" % fairway.bounds().size.x)
		check(not Geometry2D.is_point_in_polygon(Vector2(0, -190), fairway.outline()), "no fairway at the tee")
	var saved := DesignedCourse.from_json(c.to_json())
	var kept := 0
	for s in saved.shapes:
		if s.guessed:
			kept += 1
	check(kept == added.size(), "the guessed mark is saved")
	check(CourseGuesser.fill(c, 7).is_empty(), "a hole with everything gets nothing more")


static func _ring_area_of(ring: PackedVector2Array) -> float:
	var a := 0.0
	for k in ring.size():
		var p := ring[k]
		var q := ring[(k + 1) % ring.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


## Greens, fairways and bunkers found in a photo take the place of
## guesses; without a photo, a lidar hollow alone is no bunker.
func _test_detector() -> void:
	var c := DesignedCourse.blank(Vector2(600, 600))
	var h := DesignedHole.new()
	h.tees = PackedVector2Array([Vector2(0, -150)])
	h.pin = Vector2(0, 180)
	h.par = 4
	c.holes.append(h)
	# 1 m photo: rough, a lighter round green of 13 m radius at the pin
	# (pixel (300 - x, 300 - z)), a bunker to its +x side, and a long sandy
	# track that isn't a bunker.
	var photo := Image.create(600, 600, false, Image.FORMAT_RGB8)
	photo.fill(Color(0.25, 0.4, 0.17))
	for j in 600:
		for i in 600:
			var p := Vector2(300 - i, 300 - j)
			if p.distance_to(h.pin) < 13.0:
				photo.set_pixel(i, j, Color(0.36, 0.6, 0.3))
			elif absf(p.x) < 15.0 and p.y > -60.0 and p.y < 160.0:
				photo.set_pixel(i, j, Color(0.33, 0.52, 0.24))
			elif Rect2(16, 176, 8, 6).has_point(p):
				photo.set_pixel(i, j, Color(0.86, 0.8, 0.64))
	photo.fill_rect(Rect2i(250, 80, 3, 100), Color(0.8, 0.76, 0.66))
	var added := CourseGuesser.fill(c, 5, photo)
	var green: CourseShape = null
	var sand: Array[CourseShape] = []
	for s in added:
		if s.surface == Surface.Type.GREEN:
			green = s
		elif s.surface == Surface.Type.SAND:
			sand.append(s)
	check(green != null and green.found, "the green is found in the photo")
	if green != null:
		var back := CourseShape.from_dict(green.to_dict())
		check(back.guessed and back.found, "a found shape is saved as found")
	var fairway: CourseShape = null
	for s in added:
		if s.surface == Surface.Type.FAIRWAY:
			fairway = s
	check(fairway != null and fairway.found, "the fairway is found in the photo")
	if fairway != null:
		var fb := fairway.bounds()
		check(absf(fb.size.x - 30.0) < 7.0 and fb.position.y > -80.0 and fb.end.y < 180.0, "found fairway in place: %s" % fb)
	if green != null:
		var a := absf(_ring_area_of(green.outline()))
		check(a > 420.0 and a < 650.0, "found green size: %.0f m2" % a)
	check(sand.size() == 1 and sand[0].found, "one bunker found, the track left out (%d)" % sand.size())
	if sand.size() == 1:
		check(sand[0].bounds().get_center().distance_to(Vector2(20, 179)) < 2.0, "bunker in place: %s" % sand[0].bounds().get_center())
	# Lidar: flat ground with a 0.8 m hollow beside the pin, no photo.
	var c2 := DesignedCourse.blank(Vector2(600, 600))
	c2.holes.append(h)
	for j in c2.rows:
		for i in c2.cols:
			var p := c2.sample_pos(i, j)
			c2.heights[j * c2.cols + i] = -0.8 if Rect2(-26, 176, 7, 5).has_point(p) else 0.0
	var sand2: Array[CourseShape] = []
	for s in CourseGuesser.fill(c2, 5):
		if s.surface == Surface.Type.SAND:
			sand2.append(s)
	check(not sand2.is_empty() and not sand2[0].found, "a lidar hollow alone isn't taken for a bunker")
	# A bright patch in pale dune ground, with no grass round it, is no
	# bunker; a bunker touching a pale track is still found on its own.
	var dune := Image.create(200, 200, false, Image.FORMAT_RGB8)
	dune.fill(Color(0.25, 0.4, 0.17))
	dune.fill_rect(Rect2i(20, 20, 60, 60), Color(0.72, 0.68, 0.58))
	dune.fill_rect(Rect2i(40, 40, 8, 6), Color(0.9, 0.86, 0.75))
	dune.fill_rect(Rect2i(130, 100, 8, 6), Color(0.9, 0.86, 0.75))
	dune.fill_rect(Rect2i(138, 102, 40, 2), Color(0.66, 0.62, 0.55))
	var area := Rect2(-100, -100, 200, 200)
	var rings := CourseDetector.find_sand(dune, area, Vector2.ZERO, 90.0)
	check(rings.size() == 1, "one bunker in grass, none in the dunes (%d)" % rings.size())
	if rings.size() == 1:
		var mid := CourseGuesser._ring_centre(rings[0])
		check(mid.distance_to(Vector2(100 - 134, 100 - 103)) < 2.0, "the bunker by the track: %s" % mid)
	# A close-up round the green is used in place of the course photo.
	var c3 := DesignedCourse.blank(Vector2(600, 600))
	c3.holes.append(h)
	var flat := Image.create(600, 600, false, Image.FORMAT_RGB8)
	flat.fill(Color(0.25, 0.4, 0.17))
	var near := Image.create(350, 350, false, Image.FORMAT_RGB8)
	near.fill(Color(0.25, 0.4, 0.17))
	var near_area := AerialPhotos.detail_area(h.pin)
	for j in 350:
		for i in 350:
			var p := Vector2(near_area.end.x - (i + 0.5) * 0.4, near_area.end.y - (j + 0.5) * 0.4)
			if p.distance_to(h.pin) < 13.0:
				near.set_pixel(i, j, Color(0.36, 0.6, 0.3))
	var found_green := false
	for s in CourseGuesser.fill(c3, 5, flat, [{"image": near, "area": near_area}]):
		if s.surface == Surface.Type.GREEN and s.found:
			found_green = true
			var a := absf(_ring_area_of(s.outline()))
			check(a > 450.0 and a < 620.0, "green from the close-up: %.0f m2" % a)
	check(found_green, "the green is found in the close-up")
	check(AerialPhotos.has_detail(_photo_source("pdok")) and not AerialPhotos.has_detail(_photo_source("usgs")), "close-ups where the service has them")
	check(AerialPhotos.new(_photo_source("pdok"), [52.0, 5.0, 52.001, 5.001], AerialPhotos.DETAIL_ZOOM).zoom == 18, "close-ups at zoom 18")


func _photo_source(id: String) -> Dictionary:
	for src in AerialPhotos.SOURCES:
		if src["id"] == id:
			return src
	return {}


func _test_stone_walls() -> void:
	var c := DesignedCourse.new()
	c.area = Rect2(0, 0, 200, 200)
	c.walls.append(PackedVector2Array([Vector2(1, 2), Vector2(30.5, 2), Vector2(40, 12.25)]))
	c._alloc()
	var back := DesignedCourse.from_dict(c.to_dict())
	check(back.walls.size() == 1 and back.walls[0].size() == 3 and back.walls[0][2].is_equal_approx(Vector2(40, 12.25)), "walls survive saving")
	var t := CourseTerrain.new()
	var lines: Array[PackedVector2Array] = [c.walls[0]]
	var w := StoneWalls.from_lines(lines, t)
	check(w != null and w.mesh.get_surface_count() == 1, "a wall mesh is built")
	w.free()
	var none: Array[PackedVector2Array] = []
	check(StoneWalls.from_lines(none, t) == null, "no walls, no mesh")
	check(RockField.place(t, Vector3.ZERO, Vector3(0, 0, 300), 1.0, 5).is_empty(), "no rocks off the course's rough")


## Mapped buildings: heights from the lidar (surface minus ground) where it
## has them, tags or typical heights otherwise; pitched roofs on small,
## simple outlines; saved, drawn and solid to the ball.
func _test_buildings() -> void:
	var f := GeoFrame.new(51.65, 0.01)
	var els: Array = []
	els.append(_way({"leisure": "golf_course", "name": "Roof Links"}, f, _rect(Vector2(-150, -150), Vector2(150, 150))))
	els.append(_way({"golf": "hole", "ref": "1", "par": "3"}, f, [Vector2(0, -80), Vector2(0, 80)], false))
	# A house 12 x 8 m whose roof the lidar sees rising 5 m to 9 m at its middle line.
	els.append(_way({"building": "house"}, f, _rect(Vector2(-100, -20), Vector2(-88, -12))))
	# A clubhouse, L-shaped: flat roof over the outline.
	els.append(_way({"building": "yes", "name": "Club House"}, f, [Vector2(60, 60), Vector2(90, 60), Vector2(90, 70), Vector2(70, 70), Vector2(70, 90), Vector2(60, 90), Vector2(60, 60)]))
	# A shed with no lidar under it and a tagged two-storey block.
	els.append(_way({"building": "shed"}, f, _rect(Vector2(100, -100), Vector2(104, -96))))
	els.append(_way({"building": "apartments", "building:levels": "4"}, f, _rect(Vector2(-130, 100), Vector2(-100, 120))))
	# Off the course area: left out.
	els.append(_way({"building": "house"}, f, _rect(Vector2(400, 400), Vector2(410, 410))))
	var b := RealCourseBuilder.new({"elements": els}, 51.65, 0.01)
	b.surface = func(la: float, lo: float) -> float:
		var p := b.frame.to_local(la, lo)
		if p.x > -101 and p.x < -87 and p.y > -21 and p.y < -11:
			return 10.0 + 9.0 - absf(p.y + 16.0)  # ridge along x at z = -16, 9 m up, 5 m at the walls
		return NAN
	var c := b.build(func(_la: float, _lo: float) -> float: return 10.0)
	check(c.buildings.size() == 4, "four buildings on the course (%d)" % c.buildings.size())
	var by_kind := {}
	for bl in c.buildings:
		by_kind[bl.kind] = bl
	var house: CourseBuilding = by_kind.get("house")
	check(house != null and house.roof == "gabled", "the house has a gabled roof")
	if house != null:
		check(absf(house.ridge - 8.7) < 0.6, "its ridge as the lidar sees it (%.1f)" % house.ridge)
		check(house.eave > 4.0 and house.eave < 7.0, "and its eaves below (%.1f)" % house.eave)
		var box := house.oriented_box()
		check(absf((box["half"] as Vector2).x - 6.0) < 0.1 and absf((box["half"] as Vector2).y - 4.0) < 0.1, "the oriented box fits the outline")
	var club: CourseBuilding = by_kind.get("clubhouse")
	check(club != null and club.roof == "flat", "the L-shaped clubhouse has a flat roof")
	var shed: CourseBuilding = by_kind.get("shed")
	check(shed != null and shed.ridge < 4.0, "a shed is low (%.1f)" % (shed.ridge if shed else 0.0))
	var block: CourseBuilding = by_kind.get("block")
	check(block != null and absf(block.eave - 11.9) < 0.1, "four storeys from the tag (%.1f)" % (block.eave if block else 0.0))
	var back := DesignedCourse.from_dict(c.to_dict())
	check(back.buildings.size() == 4 and back.buildings[0].roof == c.buildings[0].roof and back.buildings[0].points.size() == c.buildings[0].points.size(), "buildings survive saving")
	var t := CourseTerrain.new()
	var node := CourseBuildings.from_buildings(c.buildings, t)
	check(node != null and node.mesh.get_surface_count() == 1, "a building mesh is built")
	if node != null:
		node.free()
	var field := ObstacleField.new()
	for bl in c.buildings:
		CourseBuildings.add_obstacles(field, bl, t)
	field.finalize()
	var hit := field.segment_hit(Vector3(-110, 3, -16), Vector3(-80, 3, -16))
	check(not hit.is_empty(), "a ball flying into the house hits it")
	check(field.segment_hit(Vector3(-110, 30, -16), Vector3(-80, 30, -16)).is_empty(), "and one high above it doesn't")


## More lidar crowns than room: all near the holes, and the rest spread
## out so the woods reach the edge of the area.
func _test_far_woods() -> void:
	var f := GeoFrame.new(52.2, 5.2)
	var els: Array = []
	els.append(_way({"leisure": "golf_course", "name": "Wood Links"}, f, _rect(Vector2(-700, -100), Vector2(100, 100))))
	els.append(_way({"golf": "hole", "ref": "1", "par": "3"}, f, [Vector2(50, -80), Vector2(50, 80)], false))
	var b := RealCourseBuilder.new({"elements": els}, 52.2, 5.2)
	b.max_trees = 3000
	var crowns: Array[Dictionary] = []
	for i in 176:
		for j in 41:
			var p := Vector2(20.0 - i * 4.0, -80.0 + j * 4.0)
			crowns.append({"lat": b.frame.lat_of(p), "lon": b.frame.lon_of(p), "height": 15.0})
	b.lidar_trees = crowns
	var c := b.build(func(_la: float, _lo: float) -> float: return 1.0)
	var west := 0.0
	for o in c.objects:
		west = minf(west, o.position.x)
	check(c.objects.size() <= 3000, "within the tree limit")
	check(west < c.area.position.x + 10.0, "the woods reach the edge of the area (%.0f of %.0f)" % [west, c.area.position.x])


## West Essex (Nov 2026): a culverted drain was dug across a field as an open
## ditch, and hay meadows were drawn as mown rough.
func _test_real_world_fixes() -> void:
	var f := GeoFrame.new(51.65, 0.01)
	var els: Array = []
	els.append(_way({"leisure": "golf_course", "name": "Drain Links"}, f, _rect(Vector2(-150, -150), Vector2(150, 150))))
	els.append(_way({"golf": "hole", "ref": "1", "par": "3"}, f, [Vector2(0, -80), Vector2(0, 80)], false))
	els.append(_way({"waterway": "drain", "covered": "yes", "layer": "-1"}, f, [Vector2(-100, -100), Vector2(-100, 100)], false))
	els.append(_way({"waterway": "stream", "tunnel": "culvert"}, f, [Vector2(-60, -100), Vector2(-60, 100)], false))
	els.append(_way({"waterway": "ditch"}, f, [Vector2(100, -100), Vector2(100, 100)], false))
	els.append(_way({"landuse": "meadow"}, f, _rect(Vector2(-140, -140), Vector2(-110, -110))))
	var b := RealCourseBuilder.new({"elements": els}, 51.65, 0.01)
	var c := b.build(func(_la: float, _lo: float) -> float: return 10.0)
	var water := 0
	var meadow := 0
	for s in c.shapes:
		if s.surface == Surface.Type.WATER:
			water += 1
			check(s.outline()[0].x > 50.0, "only the open ditch is water")
		if s.surface == Surface.Type.DEEP_ROUGH and s.cover == "meadow":
			meadow += 1
	check(water > 0, "the open ditch is still dug")
	# With lidar: a ditch the ground shows is kept, one it doesn't (a piped
	# field drain) isn't dug.
	var line := PackedVector2Array([Vector2(0, -50), Vector2(0, 50)])
	var dip := func(la: float, lo: float) -> float: return 10.0 - (0.6 if absf(f.to_local(la, lo).x) < 1.0 else 0.0)
	var flat := func(_la: float, _lo: float) -> float: return 10.0
	check(RealCourseBuilder.is_open_ditch(line, 1.5, dip, f), "a ditch in the lidar is open")
	check(not RealCourseBuilder.is_open_ditch(line, 1.5, flat, f), "a drain the lidar can't see is piped")
	check(meadow == 1, "the hay meadow is long grass")


## The map servers are all asked at once and the wait is shown, and no
## download runs on a thread: a threaded HTTPRequest that times out makes
## Godot wait for its blocked thread, and the game froze for a minute or
## more building West Essex while a busy map server held on (Nov 2026).
func _test_map_servers() -> void:
	var q := RealCourseFetcher.overpass_query(51.62, 0.0, 51.64, 0.02)
	check(q.begins_with("[out:json][timeout:%d];" % RealCourseFetcher.OVERPASS_QUERY_SECS), "the query asks for the server time we wait for")
	check(RealCourseFetcher.OVERPASS_TIMEOUT > RealCourseFetcher.OVERPASS_QUERY_SECS, "the download waits longer than the server may think")
	check(RealCourseFetcher.OVERPASS_TRIES >= 2, "busy map servers are asked again")
	var f := RealCourseFetcher.new()
	var req := f._make_request(5.0)
	check(not req.use_threads, "downloads are polled, not threaded (a threaded timeout freezes the game)")
	check(req.timeout == 5.0, "the request keeps its timeout")
	f.free()
	var none: Array = [null, null]
	var reqs: Array = [null, null]
	check(RealCourseFetcher.overpass_status(none, reqs, 5.0).begins_with("Reading the course map"), "a short wait reads the map")
	var slow := RealCourseFetcher.overpass_status(none, reqs, 95.0)
	check(slow.contains("1:35") and slow.contains("busy"), "a long wait says how long and that the servers are busy (%s)" % slow)


## A lidar or tile download that stalls or meets a busy server is asked for
## again: one that never came was filled from the coarse tiles, and the
## ground there came out lumpy (West Essex, Nov 2026). The player is told
## when the lidar still didn't all arrive.
func _test_retries() -> void:
	var out := [[200, PackedByteArray()], [0, PackedByteArray()], [503, PackedByteArray()], [404, PackedByteArray()], [429, PackedByteArray()], null]
	var again := RealCourseFetcher.retry_list(out)
	check(again == PackedInt32Array([1, 2, 4, 5]), "stalled, 5xx, 429 and missing downloads are asked for again, not 200 or 404 (%s)" % again)
	check(RealCourseFetcher.TRIES >= 3, "ground heights get several tries")
	check(RealCourseFetcher.LIDAR_TIMEOUT < 120.0, "a stalled lidar request is given up on sooner than two minutes")
	check(CourseDesigner._lidar_note({}).is_empty(), "no lidar note when it all came")
	check(not CourseDesigner._lidar_note({"lidar_gaps": 1, "lidar_failed": ""}).is_empty(), "a note when part of the lidar is missing")
	check(not CourseDesigner._lidar_note({"lidar_gaps": 2, "lidar_failed": "EA"}).is_empty(), "a note when the lidar failed")


## A course on a mountainside (Crans-sur-Sierre's greens followed the slope
## at 8 to 13 %, where no ball stops) on speckled coarse ground (Sydney's
## open tiles tilted its greens up to 33 %) is shaped as a club would: every
## green holds a ball from the fairway (the check reach_tests.gd makes on
## the built-in courses), tees are level and the far side is untouched.
func _test_playable_on_a_hillside() -> void:
	var f := GeoFrame.new(46.3, 7.5)
	var els: Array = []
	els.append(_way({"leisure": "golf_course", "name": "Hillside"}, f, _rect(Vector2(-200, -300), Vector2(200, 300))))
	var holes := [[Vector2(-100, -250), Vector2(-100, 120), "4"], [Vector2(0, 120), Vector2(0, -40), "3"], [Vector2(100, -200), Vector2(100, 200), "4"]]
	for i in holes.size():
		var tee: Vector2 = holes[i][0]
		var pin: Vector2 = holes[i][1]
		els.append(_way({"golf": "hole", "ref": str(i + 1), "par": holes[i][2]}, f, [tee, pin], false))
		els.append(_way({"golf": "tee"}, f, _rect(tee - Vector2(6, 8), tee + Vector2(6, 8))))
		els.append(_way({"golf": "green"}, f, _rect(pin - Vector2(14, 14), pin + Vector2(14, 14))))
		var dir := (pin - tee).normalized()
		els.append(_way({"golf": "fairway"}, f, _rect((tee + dir * 30).min(pin - dir * 20) - Vector2(18, 0), (tee + dir * 30).max(pin - dir * 20) + Vector2(18, 0))))
	var b := RealCourseBuilder.new({"elements": els}, 46.3, 7.5)
	b.ground_smooth = 8.0
	# 11 % up toward the north and east, with metre-high speckle.
	var ground := func(la: float, lo: float) -> float:
		var p := f.to_local(la, lo)
		return 1200.0 + p.y * 0.11 - p.x * 0.04 + sin(p.x * 0.9) * cos(p.y * 1.3) * 0.8
	var c := b.build(ground)
	check(c.holes.size() == 3, "three holes on the hillside (%d)" % c.holes.size())
	check(int(b.playability.get("greens", 0)) == 3, "all three greens are graded (%s)" % b.playability)
	var data := c.to_course_data()
	var reach: RefCounted = load("res://tests/reach_tests.gd").new()
	AssetProviders.ensure_defaults()
	for h in data.holes:
		reach.call("_check_hole", "hillside", h)
		var t := h.terrain
		var pin := h.pin
		var tilt := Vector2(t.height_at(pin.x + 5, pin.z) - t.height_at(pin.x - 5, pin.z), t.height_at(pin.x, pin.z + 5) - t.height_at(pin.x, pin.z - 5)).length() / 10.0
		check(tilt < 0.035, "hole %d's green is graded to a gentle plate (%.1f %%)" % [h.number, tilt * 100.0])
		var tee_fall := absf(t.height_at(h.tee.x, h.tee.z + 5) - t.height_at(h.tee.x, h.tee.z - 5)) / 10.0
		check(tee_fall < 0.03, "hole %d's tee is level (%.1f %%)" % [h.number, tee_fall * 100.0])
	for failure: String in reach.get("failures"):
		check(false, failure)
	# Ground away from the greens and tees keeps the mountain's slope.
	var shift := b.frame.to_local(46.3, 7.5)
	var far_a := c.base_height(-170 + shift.x, -100 + shift.y)
	var far_b := c.base_height(-170 + shift.x, 0 + shift.y)
	check(absf((far_b - far_a) - 11.0) < 1.5, "the hillside away from the greens keeps its 11 %% (%.1f m in 100 m)" % (far_b - far_a))


## Ground rounded to whole metres (SRTM): a gentle 1 % fall reads as
## shelves 100 m wide with a 1 m step between them; unterrace gives back the
## slope with no step, and leaves a steep bank's shape. The tiles tell
## rounded data from fine data.
func _test_terraces_eased_out() -> void:
	var c := DesignedCourse.blank(Vector2(800, 800))
	var steep := DesignedCourse.blank(Vector2(400, 400))
	for j in c.rows:
		for i in c.cols:
			c.heights[j * c.cols + i] = floorf(c.sample_pos(i, j).x * 0.01)
	for j in steep.rows:
		for i in steep.cols:
			steep.heights[j * steep.cols + i] = roundf(steep.sample_pos(i, j).x * 0.2)
	CoursePlayability.unterrace(c, 1.0)
	CoursePlayability.unterrace(steep, 1.0)
	var jump := 0.0
	var off := 0.0
	var mid := c.rows / 2
	for i in range(c.cols / 4, c.cols * 3 / 4):
		var k := mid * c.cols + i
		jump = maxf(jump, absf(c.heights[k + 1] - c.heights[k]))
		off = maxf(off, absf(c.heights[k] - (c.sample_pos(i, mid).x * 0.01 - 0.5)))
	check(jump < 0.08, "no step left between the terraces (largest %.2f m between samples)" % jump)
	check(off < 0.35, "the eased ground follows the real fall (off by %.2f m)" % off)
	var rise := steep.heights[(steep.rows / 2) * steep.cols + steep.cols * 3 / 4] - steep.heights[(steep.rows / 2) * steep.cols + steep.cols / 4]
	check(absf(rise - 40.0) < 2.0, "a steep bank keeps its rise (%.1f m over 200 m)" % rise)
	var tiles := TerrainTiles.for_box(54.0, -6.0, 54.001, -5.999)
	var rgb := PackedByteArray()
	rgb.resize(TerrainTiles.TILE * TerrainTiles.TILE * 3)
	for k in TerrainTiles.TILE * TerrainTiles.TILE:
		rgb[k * 3] = 128
		rgb[k * 3 + 1] = 3 + k % 5
	tiles.set_tile_rgb(0, rgb)
	check(tiles.height_step() == 1.0, "whole-metre tiles are found rounded")
	for k in TerrainTiles.TILE * TerrainTiles.TILE:
		rgb[k * 3 + 2] = (k * 37) % 256
	tiles.set_tile_rgb(0, rgb)
	check(tiles.height_step() == 0.0, "fine tiles are not")


## A burn 3 m wide winding down a 2 % slope in tight bends: its outline
## doesn't cross itself, each piece falls no more than STREAM_PIECE_DROP,
## and along its middle the ground is dug under the water line (it used to
## show as a dark, jagged trench with hardly any water in it).
func _test_streams_hold_water() -> void:
	var c := DesignedCourse.blank(Vector2(300, 300))
	for j in c.rows:
		for i in c.cols:
			c.heights[j * c.cols + i] = 5.0 - c.sample_pos(i, j).y * 0.02
	var line := PackedVector2Array()
	for k in 25:
		line.append(Vector2(-20.0 + (k % 2) * 14.0, -120.0 + k * 10.0))
	var pieces := RealCourseBuilder.stream_pieces(c, RealCourseBuilder.smooth_line(line), RealCourseBuilder.STREAM_PIECE, RealCourseBuilder.STREAM_PIECE_DROP)
	check(pieces.size() >= 12, "a stream down a 2 %% slope is cut into short pieces (%d)" % pieces.size())
	var crossed := 0
	for piece in pieces:
		var lo := INF
		var hi := -INF
		for p in piece:
			lo = minf(lo, c.base_height(p.x, p.y))
			hi = maxf(hi, c.base_height(p.x, p.y))
		check(hi - lo <= RealCourseBuilder.STREAM_PIECE_DROP + 0.1, "a piece falls %.2f m" % (hi - lo))
		for w in [3.0, 12.0]:
			var shape := CourseShape.new(Surface.Type.WATER, RealCourseBuilder.ribbon(piece, w))
			if Geometry2D.triangulate_polygon(shape.outline()).is_empty():
				crossed += 1
			if w == 3.0:
				c.shapes.append(shape)
	check(crossed == 0, "no stream outline crosses itself (%d did)" % crossed)
	# A thin neck between two long sides: the curve through these few
	# points folds over; untangle_shapes respaces them.
	var neck := DesignedCourse.blank(Vector2(200, 200))
	neck.shapes.append(CourseShape.new(Surface.Type.FAIRWAY, PackedVector2Array([Vector2(-60, -2), Vector2(-1, -0.6), Vector2(60, -2), Vector2(60, 2), Vector2(1, 0.6), Vector2(-60, 2)])))
	var folded := Geometry2D.triangulate_polygon(neck.shapes[0].outline()).is_empty()
	RealCourseBuilder.untangle_shapes(neck)
	check(Geometry2D.triangulate_polygon(neck.shapes[0].outline()).size() > 0, "a folded outline is untangled (folded before: %s)" % folded)
	var t := DesignedTerrain.new(c)
	var dry := 0
	for k in pieces.size():
		var mid := pieces[k][pieces[k].size() / 2]
		if t.height_at(mid.x, mid.y) > t.water_level(c.shapes[k]) - 0.25:
			dry += 1
	var n := pieces.size()
	check(dry <= n / 10, "the burn's middle lies under its water (%d of %d pieces dry)" % [dry, n])


## A pond mapped round an island green with no inner ring (Leopard Creek's
## 18th): the green and a bank round it are cut out, joined to the shore by
## a causeway so the pond stays one shape; a green half in a pond trims it.
func _test_island_green_kept_dry() -> void:
	var pond := PackedVector2Array(_rect(Vector2(-60, -60), Vector2(60, 60))).slice(0, 4)
	var green := PackedVector2Array(_rect(Vector2(-12, -10), Vector2(12, 10))).slice(0, 4)
	var parts := RealCourseBuilder.dry_out(pond, [green])
	check(parts.size() == 1, "the pond stays one shape (%d)" % parts.size())
	var wet := 0
	for p in [Vector2(0, 0), Vector2(11, 9), Vector2(-11, 0)]:
		for part in parts:
			if Geometry2D.is_point_in_polygon(p, part):
				wet += 1
	check(wet == 0, "the green is dry")
	check(not parts.is_empty() and Geometry2D.is_point_in_polygon(Vector2(40, 40), parts[0]), "the rest is still water")
	var half := RealCourseBuilder.dry_out(pond, [PackedVector2Array(_rect(Vector2(50, -10), Vector2(80, 10))).slice(0, 4)])
	check(half.size() == 1 and not Geometry2D.is_point_in_polygon(Vector2(55, 0), half[0]), "a green half in the pond trims its edge")


## Bandon Dunes has holes 1, 9, 10 and 18 mapped: 14 of 18 are missing,
## and the build says so. Holes 1 and 3 of a nine leave 7.
func _test_missing_holes_counted() -> void:
	var f := GeoFrame.new(43.18, -124.39)
	for case: Array in [[["1", "9", "10", "18"], 14], [["1", "3"], 7], [["", ""], 0]]:
		var els: Array = []
		els.append(_way({"leisure": "golf_course", "name": "Dunes"}, f, _rect(Vector2(-500, -500), Vector2(500, 500))))
		var x := -300.0
		for ref: String in case[0]:
			els.append(_way({"golf": "hole", "ref": ref, "par": "4"}, f, [Vector2(x, -150), Vector2(x, 150)], false))
			x += 120.0
		var b := RealCourseBuilder.new({"elements": els}, 43.18, -124.39)
		check(not RealCourseBuilder.par_fits(4, 175.0) and RealCourseBuilder.par_fits(3, 263.0) and RealCourseBuilder.par_fits(4, 475.0) and not RealCourseBuilder.par_fits(5, 300.0), "a mapped par checked against the hole's length")
		check(b.missing_holes() == case[1], "holes %s: %d missing (%d)" % [case[0], case[1], b.missing_holes()])


## A pin mapped on a bank inside a green that holds a ball elsewhere goes
## to the gentlest spot near it, on the green; a pin on flat ground stays.
func _test_pin_off_a_bank() -> void:
	var c := DesignedCourse.blank(Vector2(200, 200))
	for j in c.rows:
		for i in c.cols:
			var p := c.sample_pos(i, j)
			c.heights[j * c.cols + i] = 3.0 + (0.08 * (p.x - 4.0) if p.x > 4.0 else 0.0)
	c.shapes.append(CourseShape.new(Surface.Type.GREEN, PackedVector2Array([Vector2(-16, -14), Vector2(16, -14), Vector2(16, 14), Vector2(-16, 14)])))
	var h := DesignedHole.new()
	h.par = 4
	h.pin = Vector2(10, 0)
	h.tees = PackedVector2Array([Vector2(0, -300)])
	c.holes.append(h)
	var flat := DesignedHole.new()
	flat.par = 4
	flat.pin = Vector2(-8, 4)
	flat.tees = PackedVector2Array([Vector2(-8, -300)])
	c.holes.append(flat)
	check(CoursePlayability.place_pins(c) == 1, "one pin moved")
	check(h.pin.x < 4.0 and h.pin.distance_to(Vector2(10, 0)) <= CoursePlayability.PIN_SEARCH, "the pin left the bank for the flat (%s)" % h.pin)
	check(flat.pin == Vector2(-8, 4), "a pin on flat ground stays")
	# A pond beside the green, south of it: the pin by the shore moves away.
	c.shapes.append(CourseShape.new(Surface.Type.WATER, PackedVector2Array([Vector2(-40, -40), Vector2(40, -40), Vector2(40, -15), Vector2(-40, -15)])))
	flat.pin = Vector2(-8, -10)
	check(CoursePlayability.place_pins(c) == 1, "the pin by the water moved")
	check(flat.pin.y > -15.0 + CoursePlayability.PIN_WATER - 0.01, "it keeps %.0f m from the water (%s)" % [CoursePlayability.PIN_WATER, flat.pin])


## The straw-coloured fescue between the holes in the photo (Whistling
## Straits) becomes deep rough, with the mown ground inside it left mown; a
## photo that's green all over gives none.
func _test_native_grass() -> void:
	var area := Rect2(-200, -200, 400, 400)
	var img := Image.create(200, 200, false, Image.FORMAT_RGB8)
	img.fill(Color(0.36, 0.55, 0.25))  # mown grass
	# Photo x runs from area.end.x, so columns 0 to 99 are x 200 down to 0.
	img.fill_rect(Rect2i(0, 0, 100, 200), Color(0.62, 0.58, 0.40))  # fescue
	img.fill_rect(Rect2i(40, 80, 30, 30), Color(0.36, 0.55, 0.25))  # a mown island
	var grass := PackedVector2Array([Vector2(-100, 0), Vector2(-120, 50)])
	var g := NativeGrass.new(img, area, [] as Array[PackedVector2Array], grass)
	check(g.ready(), "native grass reads the photo")
	g.rows(0, 1000)
	var found := g.rings()
	var rings: Array[PackedVector2Array] = found["rings"]
	check(rings.size() == 1, "one patch of fescue (%d)" % rings.size())
	if rings.size() == 1:
		check(Geometry2D.is_point_in_polygon(Vector2(150, -150), rings[0]) and not Geometry2D.is_point_in_polygon(Vector2(-100, 0), rings[0]), "it covers the straw half, not the mown one")
	var islands: Array[PackedVector2Array] = found["islands"]
	check(islands.size() == 1 and Geometry2D.is_point_in_polygon(Vector2(90, 10), islands[0]), "the mown island inside it stays mown")
	var straw_rough := CourseShape.new(Surface.Type.ROUGH, PackedVector2Array([Vector2(120, -150), Vector2(180, -150), Vector2(180, -90), Vector2(120, -90)]))
	var mown_rough := CourseShape.new(Surface.Type.ROUGH, PackedVector2Array([Vector2(-150, -150), Vector2(-90, -150), Vector2(-90, -90), Vector2(-150, -90)]))
	check(g.share_in(straw_rough) > 0.9 and g.share_in(mown_rough) < 0.1, "a mapped rough on the straw reads as native, one on the lawn doesn't")
	# Dark brown canyon scrub (Torrey Pines) and purple heather.
	var dark := Image.create(200, 200, false, Image.FORMAT_RGB8)
	dark.fill(Color(0.36, 0.55, 0.25))
	dark.fill_rect(Rect2i(0, 0, 100, 100), Color(0.30, 0.29, 0.24))
	dark.fill_rect(Rect2i(0, 120, 100, 80), Color(0.30, 0.20, 0.24))
	var sg := NativeGrass.new(dark, area, [] as Array[PackedVector2Array], grass, NativeGrass.Kind.SCRUB)
	sg.rows(0, 1000)
	var srings: Array[PackedVector2Array] = sg.rings()["rings"]
	var covers := []
	for r in srings:
		covers.append(sg.cover_of(r))
	covers.sort()
	check(srings.size() >= 1 and covers.has("heath") and covers.has("scrub"), "dark scrub and purple heather are found (%s)" % [covers])
	check(not NativeGrass.is_scrub(Color(0.12, 0.25, 0.10), sg.grass_sat, sg.grass_val), "dark green woods aren't scrub")
	check(NativeGrass.is_scrub(Color.from_hsv(0.28, 0.2, 0.28), 0.37, 0.41), "Torrey's grey-green canyon sage is scrub")
	var two: Array[PackedVector2Array] = [PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]), PackedVector2Array([Vector2(160, 0), Vector2(260, 0), Vector2(260, 100), Vector2(160, 100)]), PackedVector2Array([Vector2(900, 0), Vector2(1000, 0), Vector2(1000, 100), Vector2(900, 100)])]
	var grown := RealCourseBuilder.grown_rings(two, 50.0)
	check(grown.size() == 2 and Geometry2D.is_point_in_polygon(Vector2(130, 50), grown[0] if Geometry2D.is_point_in_polygon(Vector2(50, 50), grown[0]) else grown[1]) and Geometry2D.is_point_in_polygon(Vector2(-40, 50), grown[0] if Geometry2D.is_point_in_polygon(Vector2(50, 50), grown[0]) else grown[1]), "outlines grown 50 m merge where they meet (%d)" % grown.size())
	var green := Image.create(200, 200, false, Image.FORMAT_RGB8)
	green.fill(Color(0.36, 0.55, 0.25))
	var none := NativeGrass.new(green, area, [] as Array[PackedVector2Array], grass)
	none.rows(0, 1000)
	check((none.rings()["rings"] as Array).is_empty(), "a green photo gives no fescue")


## A club whose 27 holes have no numbers or course names (Royal Golf Dar
## Es Salam) is parted by how its holes follow on, green to next tee, and
## numbered in that order; holes numbered 1A to 18A and 1C to 18C (Jockey
## Club Argentino) are parted by their letter.
func _test_unlabelled_courses_parted() -> void:
	var f := GeoFrame.new(33.9, -6.9)
	var els: Array = []
	els.append(_way({"leisure": "golf_course", "name": "Royal Golf Test"}, f, _rect(Vector2(-1700, -900), Vector2(1700, 900))))
	var lines: Array = []
	for k in 18:
		lines.append([Vector2(-1600 + k * 170.0, -500), Vector2(-1600 + k * 170.0 + 150.0, -500)])
	for k in 9:
		lines.append([Vector2(-800 + k * 170.0, 500), Vector2(-800 + k * 170.0 + 150.0, 500)])
	var order := range(lines.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: int = order[i]
		order[i] = order[j]
		order[j] = t
	for i: int in order:
		els.append(_way({"golf": "hole", "par": "3"}, f, lines[i], false))
	var b := RealCourseBuilder.new({"elements": els}, 33.9, -6.9)
	var names := b.course_names()
	check(names.size() == 2, "27 unnumbered holes part into two courses (%s)" % names)
	if names.size() == 2:
		b.course_filter = names[0]
		var c := b.build(func(_la: float, _lo: float) -> float: return 10.0)
		check(c.holes.size() == 18, "the eighteen first (%d holes)" % c.holes.size())
		var in_order := true
		for k in range(1, c.holes.size()):
			if c.holes[k].tees[0].x < c.holes[k - 1].tees[0].x:
				in_order = false
		check(in_order, "its holes numbered in playing order")
	var two: Array = [els[0]]
	for k in 18:
		for letter in ["A", "C"]:
			var z := -500.0 if letter == "A" else 500.0
			two.append(_way({"golf": "hole", "ref": "%d%s" % [k + 1, letter], "par": "3"}, f, [Vector2(-1600 + k * 170.0, z), Vector2(-1600 + k * 170.0 + 150.0, z)], false))
	var jockey := RealCourseBuilder.new({"elements": two}, 33.9, -6.9)
	check(jockey.course_names().size() == 2, "holes 1A to 18A and 1C to 18C are two courses (%s)" % jockey.course_names())
	# Two courses both numbered 1 to 18 (Whistling Straits): each 1st
	# starts a course, the next number follows on from its last green.
	var twin: Array = [els[0]]
	for k in 18:
		for z in [-500.0, 500.0]:
			twin.append(_way({"golf": "hole", "ref": str(k + 1), "par": "3"}, f, [Vector2(-1600 + k * 170.0, z), Vector2(-1600 + k * 170.0 + 150.0, z)], false))
	var straits := RealCourseBuilder.new({"elements": twin}, 33.9, -6.9)
	var twin_names := straits.course_names()
	check(twin_names.size() == 2, "two courses both numbered 1 to 18 are parted (%s)" % twin_names)
	if twin_names.size() == 2:
		straits.course_filter = twin_names[1]
		var c2 := straits.build(func(_la: float, _lo: float) -> float: return 10.0)
		var one_row := c2.holes.size() == 18
		for h in c2.holes:
			if absf(h.tees[0].y - c2.holes[0].tees[0].y) > 1.0:
				one_row = false
		check(one_row, "each takes its own row of holes (%d holes)" % c2.holes.size())
	# 36 unnumbered holes in one run (the 18th green beside the next
	# course's 1st tee) are cut into two rounds of 18.
	var run: Array = [els[0]]
	for k in 36:
		var row := -500.0 if k < 18 else 500.0
		var x := -1600 + (k % 18) * 170.0
		run.append(_way({"golf": "hole", "par": "3"}, f, [Vector2(x, row), Vector2(x + 150.0, row)], false))
	run.append(_way({"golf": "hole", "par": "3"}, f, [Vector2(-1600 + 17 * 170.0 + 150.0, -500), Vector2(-1600, 500)], false))
	var long_run := RealCourseBuilder.new({"elements": run}, 33.9, -6.9)
	check(long_run.course_names().size() == 2, "a 37-hole run is two courses (%s)" % long_run.course_names())


## Each step on its own: smoothing keeps the mean and calms speckle, a tee
## too far for a par 3 is dropped while the hole has another, and a green
## already flat is left as measured.
func _test_playability_steps() -> void:
	var c := DesignedCourse.blank(Vector2(200, 200))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in c.heights.size():
		c.heights[k] = 5.0 + rng.randf_range(-1.0, 1.0)
	var before := _roughness(c)
	CoursePlayability.smooth_ground(c, 8.0)
	var mean := 0.0
	for h in c.heights:
		mean += h
	mean /= c.heights.size()
	check(_roughness(c) < before * 0.3, "smoothing calms the speckle (%.2f to %.2f)" % [before, _roughness(c)])
	check(absf(mean - 5.0) < 0.1, "smoothing keeps the ground's height (%.2f)" % mean)
	for k in c.heights.size():
		c.heights[k] = 2.0
	c.shapes.append(CourseShape.new(Surface.Type.GREEN, PackedVector2Array([Vector2(-15, -15), Vector2(15, -15), Vector2(15, 15), Vector2(-15, 15)])))
	check(CoursePlayability.grade_greens(c) == 0, "a flat green is left as it is")
	var h := DesignedHole.new()
	h.par = 3
	h.pin = Vector2(0, 0)
	h.tees = PackedVector2Array([Vector2(0, -245), Vector2(0, -180), Vector2(0, -140)])
	c.holes.append(h)
	var long := DesignedHole.new()
	long.par = 3
	long.pin = Vector2(50, 0)
	long.tees = PackedVector2Array([Vector2(50, -240)])
	c.holes.append(long)
	check(CoursePlayability.trim_par3_tees(c) == 1, "one tee dropped")
	check(h.tees.size() == 2 and h.tees[0].y == -180.0, "the 245 m back tee of a par 3 is dropped (%s)" % h.tees)
	check(long.tees.size() == 1, "a par 3's only tee stays")


static func _roughness(c: DesignedCourse) -> float:
	var sum := 0.0
	for j in range(1, c.rows - 1):
		for i in range(1, c.cols - 1):
			sum += absf(c.heights[j * c.cols + i] - c.heights[j * c.cols + i + 1])
	return sum / ((c.rows - 2) * (c.cols - 2))


## A club whose holes repeat their numbers is parted into its courses even
## when the map doesn't tag golf:course:name: by the holes' names (Golf
## National's "L'Aigle - Trou n°3"), by refs like "4/9" (Banff Springs) or by
## the courses' own outlines (Crans-sur-Sierre); and a few holes of a third
## course stay out of both.
func _test_courses_at_a_club() -> void:
	var f := GeoFrame.new(48.75, 2.07)
	for way in ["name", "ref", "outline"]:
		var els: Array = []
		els.append(_way({"leisure": "golf_course", "name": "Big Club"}, f, _rect(Vector2(-900, -700), Vector2(900, 700))))
		if way == "outline":
			els.append(_way({"leisure": "golf_course", "name": "West Course"}, f, _rect(Vector2(-880, -680), Vector2(-20, 680))))
			els.append(_way({"leisure": "golf_course", "name": "East Course"}, f, _rect(Vector2(20, -680), Vector2(880, 680))))
		for side in [-1, 1]:
			var count := 18 if side < 0 else 9
			for n in count:
				var x: float = side * (60.0 + (n % 6) * 130.0)
				var z := -600.0 + int(n / 6.0) * 400.0
				var tags := {"golf": "hole", "ref": str(n + 1), "par": "4"}
				if way == "name":
					tags["name"] = ("L'Albatros - Trou n°%d" if side < 0 else "L'Aigle - Trou n°%d") % (n + 1)
				elif way == "ref":
					tags["ref"] = "%d/%d" % [n + 1, count]
				els.append(_way(tags, f, [Vector2(x, z), Vector2(x, z + 330)], false))
		# Two stray holes of a short course, numbered like the others.
		els.append(_way({"golf": "hole", "ref": "5", "name": "Oiselet 5"}, f, [Vector2(-10, -650), Vector2(-10, -560)], false))
		els.append(_way({"golf": "hole", "ref": "6", "name": "Oiselet 6"}, f, [Vector2(10, -650), Vector2(10, -560)], false))
		var b := RealCourseBuilder.new({"elements": els}, 48.75, 2.07, "Big Club")
		var names := b.course_names()
		check(names.size() == 2, "%s: the club parts into two courses (%s)" % [way, names])
		if names.size() == 2:
			b.course_filter = names[0]
			var first := b.build(func(_a: float, _b: float) -> float: return 50.0)
			b.course_filter = names[1]
			var second := b.build(func(_a: float, _b: float) -> float: return 50.0)
			check(first.holes.size() == 18 and second.holes.size() == 9, "%s: 18 and 9 holes (%d, %d)" % [way, first.holes.size(), second.holes.size()])
			check(way != "name" or first.course_name.contains("Albatros"), "the course is named from its holes (%s)" % first.course_name)
	# A single course numbered once through stays whole.
	var one: Array = []
	one.append(_way({"leisure": "golf_course", "name": "One"}, f, _rect(Vector2(-500, -500), Vector2(500, 500))))
	for n in 18:
		one.append(_way({"golf": "hole", "ref": str(n + 1), "name": "Hole %d" % (n + 1)}, f, [Vector2(-400 + n * 45, -300), Vector2(-400 + n * 45, 100)], false))
	check(RealCourseBuilder.new({"elements": one}, 48.75, 2.07, "One").course_names().is_empty(), "a single course isn't parted")


## A name that finds the club's lodge rather than its course (Pebble Beach
## Golf Links is a restaurant on the map) gives the course named like it,
## not the pitch-and-putt next door.
func _test_boundary_by_name() -> void:
	var f := GeoFrame.new(36.57, -121.95)
	var els: Array = []
	els.append(_way({"leisure": "golf_course", "name": "The Hay"}, f, _rect(Vector2(-150, -100), Vector2(50, 100))))
	els.append(_way({"leisure": "golf_course", "name": "Pebble Beach Golf Course"}, f, _rect(Vector2(150, -900), Vector2(1200, 900))))
	for n in 9:
		els.append(_way({"golf": "hole", "ref": str(n + 1), "par": "3"}, f, [Vector2(-140 + n * 20, -80), Vector2(-140 + n * 20, -10)], false))
	for n in 18:
		els.append(_way({"golf": "hole", "ref": str(n + 1)}, f, [Vector2(200 + n * 50, -700), Vector2(200 + n * 50, -300)], false))
	var b := RealCourseBuilder.new({"elements": els}, 36.57, -121.95, "Pebble Beach Golf Links")
	check(b.course_name == "Pebble Beach Golf Links" and b.hole_count() == 18, "the course named like the place, not the short course beside it (%d holes)" % b.hole_count())
	var near := RealCourseBuilder.new({"elements": els}, 36.57, -121.95, "Cypress Point Club")
	check(near.hole_count() == 18, "with no name to match, a real course before the pitch-and-putt (%d holes)" % near.hole_count())
	check(RealCourseBuilder.name_words("The Royal Portrush Golf Club") == PackedStringArray(["portrush"]), "only a name's own words count")


## Trees the lidar or photo found on a hole's line of play are left out (a
## crown on the line 30 m out blocked Hirono's 12th).
func _test_lines_of_play() -> void:
	var lines: Array[PackedVector2Array] = [PackedVector2Array([Vector2(0, 0), Vector2(0, 200), Vector2(50, 350)])]
	var cells := RealCourseBuilder.line_cells(lines)
	check(RealCourseBuilder.on_line_of_play(Vector2(3, 100), cells), "a tree 3 m off the line is on it")
	check(RealCourseBuilder.on_line_of_play(Vector2(28, 280), cells), "on the dogleg's second leg too")
	check(not RealCourseBuilder.on_line_of_play(Vector2(20, 100), cells), "20 m off isn't")
	check(not RealCourseBuilder.on_line_of_play(Vector2(1, -5), cells), "behind the tee isn't")
	var f := GeoFrame.new(52.0, 5.0)
	var els: Array = []
	els.append(_way({"leisure": "golf_course", "name": "Woods"}, f, _rect(Vector2(-150, -250), Vector2(150, 250))))
	els.append(_way({"golf": "hole", "ref": "1", "par": "4"}, f, [Vector2(0, -200), Vector2(0, 150)], false))
	var b := RealCourseBuilder.new({"elements": els}, 52.0, 5.0)
	var shift := b.frame.to_local(52.0, 5.0)
	b.lidar_trees = [{"lat": f.lat_of(Vector2(-3, 0)), "lon": f.lon_of(Vector2(-3, 0)), "height": 15.0}, {"lat": f.lat_of(Vector2(-60, 0)), "lon": f.lon_of(Vector2(-60, 0)), "height": 15.0}]
	var c := b.build(func(_a: float, _b: float) -> float: return 10.0)
	var on_line := 0
	var off := false
	for o in c.objects:
		var p := Vector2(o.position.x, o.position.z) - shift
		if p.distance_to(Vector2(-3, 0)) < 1.0:
			on_line += 1
		if p.distance_to(Vector2(-60, 0)) < 1.0:
			off = true
	check(on_line == 0, "the lidar crown on the line is left out")
	check(off, "the lidar crown 60 m off is planted")


## A map with no holes says so at once, before minutes of ground, lidar and
## photo downloads (Chipping Sodbury, 2026-11-18), and a hole that runs off
## the ground built, or is a stub, is left out.
func _test_holes_checked_early() -> void:
	var f := GeoFrame.new(51.5, -2.4)
	var els: Array = []
	els.append(_way({"leisure": "golf_course", "name": "Unmapped"}, f, _rect(Vector2(-300, -300), Vector2(300, 300))))
	els.append(_way({"golf": "green"}, f, _rect(Vector2(-10, -10), Vector2(10, 10))))
	var b := RealCourseBuilder.new({"elements": els}, 51.5, -2.4)
	check(b.hole_count() == 0, "no holes are counted on an unmapped course")
	check(RealCourseFetcher.no_holes_text("Unmapped").contains("golf=hole"), "the message says what is missing")
	els.append(_way({"golf": "hole", "ref": "1"}, f, [Vector2(0, -100), Vector2(0, -92)], false))
	els.append(_way({"golf": "hole", "ref": "2"}, f, [Vector2(0, 0), Vector2(0, 5000)], false))
	els.append(_way({"golf": "hole", "ref": "3"}, f, [Vector2(50, -200), Vector2(50, 150)], false))
	check(RealCourseBuilder.new({"elements": els}, 51.5, -2.4).hole_count() == 1, "a stub and a hole running off the area are left out")


## Search results: golf courses first, the one named like the query first,
## in the order found otherwise; unnamed courses last.
func _test_search_ranking() -> void:
	var r := [
		{"name": "Pebble Beach Golf Links", "golf": false},
		{"name": "", "golf": true},
		{"name": "Spyglass Hill Golf Course", "golf": true},
		{"name": "Pebble Beach Golf Course", "golf": true},
		{"name": "Poppy Hills Golf Course", "golf": true},
	]
	var out := RealCourseFetcher.rank(r, "Pebble Beach Golf Links")
	var names: Array = out.map(func(d: Dictionary) -> String: return d["name"])
	check(names == ["Pebble Beach Golf Course", "Spyglass Hill Golf Course", "Poppy Hills Golf Course", "", "Pebble Beach Golf Links"], "search ranking (%s)" % [names])
	var club := [{"name": "The Carnoustie Burnside Course", "golf": true}, {"name": "The Carnoustie Buddon Course", "golf": true}, {"name": "The Carnoustie Championship Course", "golf": true}]
	check(str(RealCourseFetcher.rank(club, "Carnoustie Golf Links")[0]["name"]) == "The Carnoustie Championship Course", "a club's championship course first")
	var troon := [{"name": "Troon Lochgreen", "golf": true, "near": 900.0}, {"name": "Old Course", "golf": true, "near": 150.0}, {"name": "Royal Troon Golf Club", "golf": false}]
	check(str(RealCourseFetcher.rank(troon, "Royal Troon Golf Club")[0]["name"]) == "Old Course", "the Old Course round the club's clubhouse before the town's course")
	check(RealCourseBuilder.display_name({"name": "ملعب خور دبي للغولف", "name:en": "Dubai Creek Golf Course"}) == "Dubai Creek Golf Course", "an Arabic name gives way to its English one")
	check(RealCourseBuilder.display_name({"name": "Golf de Saint-Cloud", "name:en": "Saint-Cloud Golf Club"}) == "Golf de Saint-Cloud", "a Latin-script name is kept")
	check(RealCourseBuilder.display_name({"name": "霞ヶ関カンツリー倶楽部"}) == "霞ヶ関カンツリー倶楽部", "with no English name, its own")
	var tries := RealCourseFetcher.search_names("Real Club Valderrama")
	check("valderrama golf club" in Array(tries).map(func(t: String) -> String: return t.to_lower()), "a Spanish club name is also tried as a golf club (%s)" % tries)
	check(RealCourseFetcher.search_names("Royal County Down Golf Club")[0] == "Royal County Down Golf Course", "the other ending first")
	var kiawah := [{"name": "Kiawah Island Club - River Course", "golf": true}, {"name": "Cypress Point", "golf": false}]
	check(not RealCourseFetcher._has_named_golf(kiawah, "Cypress Point Club", false) and RealCourseFetcher._has_named_golf([{"name": "Cypress Point Golf Course", "golf": true}], "Cypress Point Golf Course", true), "a course in a district of the same name is not the club")
	var cypress := RealCourseFetcher.search_names("Cypress Point Club")
	check("Cypress Point Golf Course" in cypress and cypress.find("Cypress Point Golf Course") < cypress.find("cypress golf course") and not "Cabo del Golf Course" in RealCourseFetcher.search_names("Cabo del Sol Ocean Course"), "the name cut short a word at a time (%s)" % cypress)
	check(RealCourseBuilder.is_main_course("Sunningdale Old Course") and not RealCourseBuilder.is_main_course("Sunningdale New Course") and not RealCourseBuilder.is_main_course("Oldham Golf Club"), "a club's main course by name")
	var inside := {"lat": 46.31, "lon": 7.47, "box": ["46.30", "46.32", "7.46", "7.48"]}
	var off := {"lat": 46.32, "lon": 7.49, "box": ["46.315", "46.325", "7.485", "7.495"]}
	check(RealCourseFetcher.near_distance(inside, 46.305, 7.465) == 0.0 and RealCourseFetcher.near_distance(off, 46.305, 7.465) > 1000.0, "the course round the clubhouse is nearest")
	check(RealCourseBuilder.short_name("The Fairmont Banff Springs Golf Course") == "Fairmont Banff Springs", "short club name (%s)" % RealCourseBuilder.short_name("The Fairmont Banff Springs Golf Course"))


## The land round a real course to the horizon: it meets the course's own
## ground at its edge without a step, saves and loads, and a coast's sea
## floor gives the course a sea.
func _test_landscape() -> void:
	var f := GeoFrame.new(56.34, -2.80)
	var c := DesignedCourse.blank(Vector2(600, 400))
	c.source["base_height"] = 10.0
	for k in c.heights.size():
		c.heights[k] = 2.0
	var land := RealLandscape.new(f, c)
	check(land.count >= 400, "the land reaches 8 km each way (%d samples)" % land.count)
	var b := land.box()
	check(b[0] < 56.34 - 0.06 and b[2] > 56.34 + 0.06, "its box spans the land")
	# The sea floor east of the course (-x is east), rising land to the west.
	var height := func(lat: float, lon: float) -> float:
		var p := f.to_local(lat, lon)
		return -20.0 if p.x < -2000.0 else 15.0 + p.x * 0.01
	land.rows(0, land.count, height)
	check(land.has_sea(), "a sea floor nearby gives a sea")
	var again := DesignedCourse.from_json(c.to_json())
	land.apply(again)
	check(again.landscape.get("cols", 0) == land.count and float(again.source.get("sea", -1.0)) == 0.0, "the land and the sea are set")
	# The tiles' noisy sea surface over 0 by the shore is the sea too.
	var noisy := RealLandscape.new(f, DesignedCourse.from_json(c.to_json()))
	noisy.rows(0, noisy.count, func(lat: float, lon: float) -> float:
		var p := f.to_local(lat, lon)
		return -20.0 if p.x < -4000.0 else (0.8 if p.x < -2000.0 else 15.0 + p.x * 0.01))
	noisy.apply(DesignedCourse.from_json(c.to_json()))
	var shallow := noisy.heights[noisy.count / 2 * noisy.count + (noisy.count / 2 - roundi(3000.0 / RealLandscape.CELL))]
	check(shallow + float(c.source.get("base_height", 0.0)) <= RealLandscape.SEA_FLOOR + 0.01, "a noisy sea surface by the shore is let down (%.1f)" % shallow)
	var edge := land.heights[land.count / 2 * land.count + land.count / 2]
	check(absf(edge - 2.0) < 0.2, "inside the course it follows the course's ground (%.2f)" % edge)
	var round := DesignedCourse.from_json(JSON.stringify(_with_land(c, land)))
	check(round != null and not round.landscape.is_empty(), "the land saves and loads")
	if round != null and not round.landscape.is_empty():
		var hs: PackedFloat32Array = round.landscape["heights"]
		var far := land.count - 2
		check(absf(hs[land.count / 2 * land.count + far] - land.heights[land.count / 2 * land.count + far]) < 0.11, "heights keep to a decimetre")
	check(not is_nan(Landscape.sea_level(again)), "the course draws its sea")
	# A big lake's flat surface (Lake Michigan at 176.8 m by Whistling
	# Straits) gives the course the lake at its level, its surface let down
	# under the water; a flat plain on a whole metre doesn't.
	var lc := DesignedCourse.blank(Vector2(600, 400))
	lc.source["base_height"] = 190.0
	var lakeside := RealLandscape.new(f, lc)
	lakeside.rows(0, lakeside.count, func(lat: float, lon: float) -> float:
		var p := f.to_local(lat, lon)
		return 176.76 if p.x < -1500.0 else 190.0 + p.x * 0.004)
	check(not lakeside.has_sea() and absf(lakeside.lake_level() - 176.75) < 0.06, "a lake's flat surface is found (%.2f)" % lakeside.lake_level())
	lakeside.apply(lc)
	check(absf(float(lc.source.get("sea", -1.0)) - 176.75) < 0.06, "the course gets the lake")
	var far_east := lakeside.heights[lakeside.count / 2 * lakeside.count + 2]
	check(far_east + 190.0 < 176.76 - 1.5, "the lake's surface is let down under its water (%.1f)" % (far_east + 190.0))
	var plain := RealLandscape.new(f, lc)
	plain.rows(0, plain.count, func(lat: float, lon: float) -> float:
		var p := f.to_local(lat, lon)
		return 12.0 if p.x < -1500.0 else 14.0 + p.x * 0.004)
	check(is_nan(plain.lake_level()), "a flat plain on a whole metre isn't a lake")
	# A cliff the tiles smear 20 m up over the sea: the land cover's water
	# joined to the sea goes under it (Mauna Kea).
	var cliff_x := f.lon_of(Vector2(-2000.0, 0.0))
	var cv := PackedFloat32Array()
	for j in 40:
		for i in 40:
			cv.append(LandCover.WATER if -2.90 + (i + 0.5) * 0.005 > cliff_x else LandCover.RANGELAND)
	var cliffs := RealLandscape.new(f, DesignedCourse.from_json(c.to_json()))
	cliffs.cover = LandCover.new([56.30, -2.90, 56.38, -2.70])
	check(cliffs.cover.add(_tiff(cv, 40, 40, false, false, true)), "shore land cover loads")
	# (_tiff places its raster by Sussex: put this one on the cliffs' box.)
	cliffs.cover.raster.west = -2.90
	cliffs.cover.raster.north = 56.38
	cliffs.cover.raster.dlon = 0.005
	cliffs.cover.raster.dlat = 0.002
	cliffs.rows(0, cliffs.count, func(lat: float, lon: float) -> float:
		var p := f.to_local(lat, lon)
		return -20.0 if p.x < -4000.0 else (20.0 if p.x < -1000.0 else 30.0))
	cliffs.apply(DesignedCourse.from_json(c.to_json()))
	var mid_row := cliffs.count / 2 * cliffs.count
	var over_sea := cliffs.heights[mid_row + cliffs.count / 2 - roundi(3000.0 / RealLandscape.CELL)] + 10.0
	var on_cliff := cliffs.heights[mid_row + cliffs.count / 2 - roundi(1500.0 / RealLandscape.CELL)] + 10.0
	check(over_sea < 0.0 and on_cliff > 19.0, "the sea under a smeared cliff is let in, the cliff stays (%.1f, %.1f)" % [over_sea, on_cliff])
	# Tiles without a sea floor hold the sea flat at 0 (Barnbougle).
	var bc := DesignedCourse.blank(Vector2(600, 400))
	bc.source["base_height"] = 6.0
	var shore := RealLandscape.new(f, bc)
	shore.rows(0, shore.count, func(lat: float, lon: float) -> float:
		var p := f.to_local(lat, lon)
		return 0.0 if p.x < -1500.0 else 6.0 + p.x * 0.004)
	check(shore.has_sea() and shore.flat_sea(), "a flat surface at sea level is the sea")
	shore.apply(bc)
	check(float(bc.source.get("sea", -1.0)) == 0.0, "the course gets the flat sea")
	check(shore.heights[shore.count / 2 * shore.count + 2] + 6.0 < -1.0, "the flat sea's surface is let down under its water")
	var dc := DesignedCourse.blank(Vector2(600, 400))
	dc.source["base_height"] = 6.0
	var datum := RealLandscape.new(f, dc)
	datum.rows(0, datum.count, func(lat: float, lon: float) -> float:
		var p := f.to_local(lat, lon)
		return -1.8 if p.x < -1500.0 else 6.0 + p.x * 0.004)
	check(absf(datum.flat_sea_level() + 1.8) < 0.06, "a flat sea on the tiles' own datum (-1.8 m) is the sea (%.2f)" % datum.flat_sea_level())
	datum.apply(dc)
	check(absf(float(dc.source.get("sea", 9.0)) + 1.8) < 0.06, "the course gets the sea at that level")


static func _with_land(c: DesignedCourse, land: RealLandscape) -> Dictionary:
	land.apply(c)
	return c.to_dict()


## A hole drawn from the last green's middle with no tee mapped starts past
## that green, not on it.
func _test_tee_off_the_last_green() -> void:
	var f := GeoFrame.new(52.2, 5.2)
	var els: Array = []
	els.append(_way({"leisure": "golf_course", "name": "Greens"}, f, _rect(Vector2(-200, -300), Vector2(200, 300))))
	els.append(_way({"golf": "green"}, f, _rect(Vector2(-12, -212), Vector2(12, -188))))
	els.append(_way({"golf": "green"}, f, _rect(Vector2(-12, -12), Vector2(12, 12))))
	els.append(_way({"golf": "hole", "ref": "5", "par": "3"}, f, [Vector2(0, -200), Vector2(0, 0)], false))
	var b := RealCourseBuilder.new({"elements": els}, 52.2, 5.2)
	var c := b.build(func(_a: float, _b: float) -> float: return 3.0)
	var shift := b.frame.to_local(52.2, 5.2)
	check(c.holes.size() == 1 and c.holes[0].tees[0].y - shift.y > -188.0 + 5.0, "the tee is past the last green (%s)" % (c.holes[0].tees[0] - shift if c.holes.size() == 1 else Vector2.ZERO))
	var data := c.to_course_data()
	if data.holes.size() == 1:
		var t := data.holes[0].tee
		check(data.holes[0].terrain.surface_at(t.x, t.z) != Surface.Type.GREEN, "and not on a green")


## A hole line that ends in a pond with no green mapped puts its pin (and
## the green guessed round it) on the bank.
func _test_pin_out_of_the_pond() -> void:
	var f := GeoFrame.new(-25.4, 31.9)
	var els: Array = []
	els.append(_way({"leisure": "golf_course", "name": "Creek"}, f, _rect(Vector2(-200, -300), Vector2(200, 300))))
	els.append(_way({"natural": "water"}, f, _rect(Vector2(-30, 150), Vector2(30, 210))))
	els.append(_way({"golf": "hole", "ref": "1", "par": "4"}, f, [Vector2(0, -200), Vector2(0, 180)], false))
	var b := RealCourseBuilder.new({"elements": els}, -25.4, 31.9)
	var c := b.build(func(_a: float, _b: float) -> float: return 300.0)
	var shift := b.frame.to_local(-25.4, 31.9)
	check(c.holes.size() == 1 and c.holes[0].pin.y - shift.y < 150.0 - 8.0, "the pin is on the bank (%s)" % (c.holes[0].pin - shift if c.holes.size() == 1 else Vector2.ZERO))


## A lidar service that answers outside its country with zeros (England's
## over Northern Ireland) isn't taken for the ground, and the sea isn't let
## in over a course whose ground lies at sea level.
func _test_lidar_must_agree() -> void:
	var box: Array[float] = [54.21, -5.89, 54.23, -5.86]
	var hills := func(lat: float, lon: float) -> float: return 8.0 + (lat - 54.21) * 900.0 + (lon + 5.89) * 300.0
	var zeros := func(_lat: float, _lon: float) -> float: return 0.0
	var close := func(lat: float, lon: float) -> float: return float(hills.call(lat, lon)) + 0.7
	check(not RealCourseFetcher.lidar_agrees(zeros, hills, box), "a sheet of zeros isn't lidar")
	check(RealCourseFetcher.lidar_agrees(close, hills, box), "lidar near the tiles is taken")
	var canopy := func(lat: float, lon: float) -> float: return float(hills.call(lat, lon)) + 18.0
	check(RealCourseFetcher.lidar_agrees(hills, canopy, box), "lidar under tiles that measured the tree tops is taken")
	var c := DesignedCourse.blank(Vector2(200, 200))
	c.source["base_height"] = 0.0
	check(not RealLandscape.dry(c), "ground at sea level isn't dry")
	c.source["base_height"] = 6.0
	check(RealLandscape.dry(c), "ground 6 m up is")
