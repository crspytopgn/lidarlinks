class_name RealCourseFetcher
extends Node
## Finds a real golf course by name and builds it as a DesignedCourse, all
## from free, open data fetched by the game itself (desktop and browser):
##
## 1. Nominatim (OpenStreetMap's search) turns the name into places.
## 2. The Overpass API returns the course's mapped holes, fairways, greens,
##    tees, bunkers, water, woods, trees and cart paths.
## 3. The Terrain Tiles on AWS give the ground heights (national lidar where
##    it is open, see docs/real-courses.md).
##
## search() emits `found`; build() emits `progress` then `built` or `failed`.

signal found(results: Array)  ## [{"name", "label", "lat", "lon", "box", "golf"}]
signal progress(text: String)
signal built(course: DesignedCourse, summary: Dictionary)
signal failed(text: String)
## search() couldn't reach the search service (rather than finding nothing).
signal search_failed(text: String)

const NOMINATIM := "https://nominatim.openstreetmap.org/search?format=jsonv2&limit=10&accept-language=en&q=%s"
## Golf courses within a box (west, north, east, south), for a name that
## finds the club's buildings rather than its course.
const NOMINATIM_NEAR := "https://nominatim.openstreetmap.org/search?format=jsonv2&limit=10&accept-language=en&q=golf%%20course&bounded=1&viewbox=%.5f,%.5f,%.5f,%.5f"
## Places found by name that are looked round for golf courses, and how far
## (degrees of latitude; about 2.2 km).
const NEAR_LOOKUPS := 2
const NEAR_DEGREES := 0.02
const NOMINATIM_GAP_MS := 1100
const OVERPASS := [
	"https://overpass-api.de/api/interpreter",
	"https://overpass.private.coffee/api/interpreter",
	"https://maps.mail.ru/osm/tools/overpass/api/interpreter",
]
const USER_AGENT := "LidarLinks course importer (+https://github.com/crspytopgn/lidarlinks)"
## Metres searched round a place that isn't itself a mapped golf course.
const POINT_RADIUS := 1500.0
const PARALLEL := 6  ## downloads at once
## Rounds of tries for the ground heights: failed downloads are asked for
## again, after RETRY_WAIT seconds (longer each round).
const TRIES := 4
const RETRY_WAIT := 2.0
## Seconds a lidar request may take: a good answer takes a few seconds, and
## a stalled one isn't worth two minutes when it can be asked for again.
const LIDAR_TIMEOUT := 45.0
## Metres the lidar's middle height may differ from the coarse tiles'
## before it is taken for a service with no real data there.
const LIDAR_AGREE_M := 30.0
## Seconds the map servers may take over the course map: a busy public
## server can take a minute and a half over a big club, so the query asks
## for up to OVERPASS_QUERY_SECS and the download allows a little more.
const OVERPASS_QUERY_SECS := 180
const OVERPASS_TIMEOUT := 210.0
## Rounds of asking every map server, and the wait before the next round.
const OVERPASS_TRIES := 2
const OVERPASS_RETRY_WAIT := 5.0
## Bytes read from each download per frame.
const DOWNLOAD_CHUNK := 1 << 20
const MAX_DETAILS := 40  ## close-ups of greens fetched at most
## Phones and tablets in the browser have far less memory (an iPad's Safari
## drops the page's graphics when it runs short, leaving a black screen),
## so they build a lighter course: fewer trees and no green close-ups.
const LIGHT_MAX_TREES := 2500
## Milliseconds of work between drawn frames, so the progress keeps moving
## in the single-threaded browser build.
const FRAME_BUDGET_MS := 60
## Lidar pixels read per step when finding the trees.
const LIDAR_PIXELS_PER_STEP := 60000
## Metres from the clubhouse found by name within which a course called
## only "Old Course" or "Championship" is taken as the club's.
const MAIN_NEAR := 800.0
## Metres from what the full name found within which a course found by one
## of its words is taken.
const WORD_NEAR := 20000.0
## Metres round the course the land cover is read for the sea under cliffs.
const SHORE_REACH := 2500.0
## Land samples shaped per step (RealLandscape).
const LAND_SAMPLES_PER_STEP := 8000
## Goes up whenever a build gives a better course (new detection, trees,
## walls...): courses built before it offer "Update" on the Courses page.
## Saved in each course's source as "builder" (RealCourseUpdate).
const BUILDER_VERSION := 9  ## 5: big lakes as water, native grass from the photo; 6: seas under cliffs, scrub, ponds from the land cover, Ireland off England's lidar; 7: beaches, woods out of the tile ground; 8: lidar ground without faint grid lines; 9: tree heights v2, more photo services, dormant photos
## How long a cached answer is trusted: a day for the search and the map
## (places and mapping change), a month for ground heights, lidar, photos
## and land cover (the ground doesn't). 404s are cached too: a tile service
## has no tile where it has no data, and asking again won't change that.
const FETCH_CACHE_TTL_SHORT := 86400
const FETCH_CACHE_TTL_LONG := 30 * 86400
## Where fetched course data is kept between builds, keyed by the request,
## so rebuilding a course (or building the club's next one) reuses the
## ground heights, lidar, photos and map instead of downloading them again.
## Capped, oldest first out; the tests point it elsewhere.
static var fetch_cache_dir := "user://realcourse_cache"
static var fetch_cache_enabled := true
static var fetch_cache_max_bytes := 256 * 1024 * 1024

var busy := false
## Use national lidar and aerial photos where they cover the course.
var use_lidar := true
var use_photos := true
## Use the global canopy height map for trees where lidar has none (desktop).
var use_canopy := true
var use_land_cover := true
## Draw the real land round the course to the horizon (RealLandscape).
var use_landscape := true
## Called with each HTTPRequest before it is sent (tools use it to set a
## proxy); empty in the game.
var configure_request: Callable
## Overpass servers, all asked at once (see _overpass).
var servers: Array = OVERPASS.duplicate()
## Per-server limits, back-off and circuit breaker for every download.
var door := NetDoor.new()
var _last_object_cut := 0.0  ## metres of wood or house taken off the coarse ground
var _last_summary := {}
var _cancelled := false
var _last_yield := 0
var _last_search := -100000


## True on a phone or tablet browser: build lighter courses there.
static func light_mode() -> bool:
	if not OS.has_feature("web"):
		return false
	# iPadOS Safari says it is a Mac, so a touch screen counts too.
	return OS.has_feature("web_ios") or OS.has_feature("web_android") or DisplayServer.is_touchscreen_available()


## Stops a build in progress; it ends with `failed`.
func cancel() -> void:
	if busy:
		_cancelled = true
		for c in get_children():
			var req := c as HTTPRequest
			if req != null:
				# cancel_request() is silent; the waiting step needs its answer.
				req.set_meta("dropped", true)
				req.cancel_request()
				req.request_completed.emit(HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray())


## Looks up places matching `query`, golf courses first.
func search(query: String) -> void:
	if busy:
		return
	busy = true
	var q := query.strip_edges()
	var results: Variant = await _search_once(q)
	if results == null:
		busy = false
		search_failed.emit("Couldn't reach OpenStreetMap's search. Check the connection and try again.")
		return
	var short := RealCourseBuilder.short_name(q)
	if not _has_named_golf(results, q, false) and not short.is_empty():
		# The club's full name may not be on the map at all, or only as its
		# clubhouse, a road or a district: "Cypress Point Club" finds the
		# Kiawah course in a Cypress Point district (its course is
		# "Cypress Point Golf Course"), "Royal County Down Golf Club" finds
		# nothing (its course is "Royal County Down Golf Course"). Other
		# endings first, then the name cut short, then its distinctive
		# words as a golf club ("Real Club Valderrama" finds nothing;
		# "Valderrama Golf Club" finds the course).
		var tried := {q.to_lower(): true}
		var anchors: Array = _naming(results, q)
		var near_tried := false
		for name: String in search_names(q):
			if tried.has(name.to_lower()):
				continue
			tried[name.to_lower()] = true
			var words := RealCourseBuilder.name_words(name)
			if words.size() == 1 and not anchors.is_empty() and not near_tried:
				# Before one word alone, the golf courses round the places the
				# fuller names found (the clubhouse of Royal Troon, the Cabo
				# del Sol district): "troon golf course" finds the town's
				# public courses, "ocean golf course" one in Spain.
				near_tried = true
				var ring: Array = await _golf_near(anchors)
				if not ring.is_empty():
					results = ring + anchors
					break
			var other: Variant = await _search_once(name)
			if other == null:
				continue
			if words.size() == 1:
				# One word alone matches anything with it in its address
				# ("Earth golf course" found a course in Blue Earth County):
				# keep only golf courses with the word in their own name,
				# near the places the fuller names found.
				var seen: Array = anchors
				other = (other as Array).filter(func(r: Dictionary) -> bool:
					if not r["golf"] or not words[0] in RealCourseBuilder.name_words(str(r["name"])):
						return false
					if seen.is_empty():
						return true
					for f: Dictionary in seen:
						if near_distance(r, float(f["lat"]), float(f["lon"])) < WORD_NEAR:
							return true
					return false)
			if _has_named_golf(other, name, true):
				results = other
				break
			if anchors.is_empty() and not _naming(other, name).is_empty():
				anchors = _naming(other, name)
				if not _has_golf(results):
					results = anchors
	if not _has_golf(results):
		var more: Variant = await _search_once(q + (" course" if q.to_lower().contains("golf") else " golf course"))
		if more != null and _has_golf(more):
			results = more + results
	if not _has_golf(results):
		# The name often finds the clubhouse, its restaurant or its road
		# rather than the course (Pebble Beach Golf Links is mapped as a
		# restaurant, the course as "Pebble Beach Golf Course"): look for
		# golf courses round the first places found.
		results = await _golf_near(results) + results
	busy = false
	found.emit(rank(results, q))


## Other names to search for a club whose name found nothing, best first:
## its name with the usual endings, alone, then its distinctive words as a
## golf club or course.
static func search_names(q: String) -> PackedStringArray:
	var short := RealCourseBuilder.short_name(q)
	var core := " ".join(RealCourseBuilder.name_words(q))
	var out := PackedStringArray()
	var names := [short + " Golf Course", short + " Golf Club", short + " Golf Links", short]
	# Its name cut short a word at a time, as a golf course ("Cypress Point
	# Club" is mapped as "Cypress Point Golf Course", "Cabo del Sol Ocean
	# Course" as "Cabo del Sol"), down to two words.
	var tokens := short.split(" ", false)
	for n in range(tokens.size() - 1, 1, -1):
		if tokens[n - 1].to_lower() in ["de", "del", "la", "le", "of", "the", "golf", "and", "&"]:
			continue
		var head := " ".join(tokens.slice(0, n))
		names.append(head + " Golf Course")
		names.append(head)
	names.append_array([core + " Golf Club", core + " Golf Course"])
	# Each word alone, the last (often the town) first: the search wants
	# every word in the name, and "Engadine Golf Club Samedan" is mapped as
	# "Golfcourse Samedan".
	var words := RealCourseBuilder.name_words(q)
	if words.size() >= 2:
		for k in range(words.size() - 1, maxi(words.size() - 4, -1), -1):
			names.append(words[k] + " golf course")
	for name: String in names:
		if not core.is_empty() and not name in out:
			out.append(name)
	return out


## Golf courses first, those named most like the query first among them,
## else in the order found (a stable sort: sort_custom alone shuffled equal
## places, and once offered the course next door first).
static func rank(results: Array, query: String) -> Array:
	var words := RealCourseBuilder.name_words(query)
	var keyed: Array = []
	for i in results.size():
		var r: Dictionary = results[i]
		var own := RealCourseBuilder.name_words(str(r["name"]))
		var matched := 0
		for w in words:
			if w in own:
				matched += 1
		var score := (1000 if r["golf"] else 0) + matched * 10 + (0 if str(r["name"]).is_empty() else 1)
		# A club's main course, when its courses all match the query
		# ("Carnoustie Golf Links" found the Burnside before the
		# Championship).
		var lower := str(r["name"])
		if r["golf"] and RealCourseBuilder.is_main_course(lower):
			score += 5
			# The club's main course found round its clubhouse, named only
			# "Old Course" (Royal Troon's, beside the town's Lochgreen):
			# as good as named after the club.
			if float(r.get("near", INF)) < MAIN_NEAR:
				score += 10 * words.size()
		keyed.append([score, i, r])
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	return keyed.map(func(k: Array) -> Dictionary: return k[2])


## Fetches and builds the course at a search result.
func build(place: Dictionary) -> void:
	if busy:
		return
	busy = true
	_cancelled = false
	_last_yield = Time.get_ticks_msec()
	var course := await _build(place)
	busy = false
	if _cancelled:
		_cancelled = false
		failed.emit("Cancelled.")
	elif course != null:
		built.emit(course, _last_summary)


## Lets a frame be drawn if this step has run for a while.
func _breathe() -> void:
	if Time.get_ticks_msec() - _last_yield >= FRAME_BUDGET_MS:
		await get_tree().process_frame
		_last_yield = Time.get_ticks_msec()


## Shows `text`, then lets the browser draw it before a long step.
func _step(text: String) -> void:
	progress.emit(text)
	await get_tree().process_frame
	await get_tree().process_frame
	_last_yield = Time.get_ticks_msec()



func _build(place: Dictionary) -> DesignedCourse:
	var lat := float(place["lat"])
	var lon := float(place["lon"])
	var box: Array = place.get("box", [])
	var s: float
	var w: float
	var n: float
	var e: float
	if place.get("golf", false) and box.size() == 4:
		# Nominatim boxes are south, north, west, east.
		s = float(box[0]) - 0.002
		n = float(box[1]) + 0.002
		w = float(box[2]) - 0.003
		e = float(box[3]) + 0.003
	else:
		var f := GeoFrame.new(lat, lon)
		# +x is west.
		s = f.lat_of(Vector2(0, -POINT_RADIUS))
		n = f.lat_of(Vector2(0, POINT_RADIUS))
		w = f.lon_of(Vector2(POINT_RADIUS, 0))
		e = f.lon_of(Vector2(-POINT_RADIUS, 0))
	progress.emit("Reading the course map from OpenStreetMap...")
	var data := await _overpass(overpass_query(s, w, n, e))
	if _cancelled:
		return null
	if data.is_empty():
		failed.emit("Couldn't reach OpenStreetMap's map server. Check the connection and try again in a minute.")
		return null
	await _step("Reading the map...")
	var builder := RealCourseBuilder.new(data, lat, lon, str(place.get("name", "")))
	if builder.hole_count() == 0:
		# Say so now, not after minutes of ground, lidar and photos.
		failed.emit(no_holes_text(builder.course_name))
		return null
	var light := light_mode()
	if light:
		builder.max_trees = LIGHT_MAX_TREES
	_last_object_cut = 0.0
	var gb := builder.geo_box()
	var tiles := TerrainTiles.for_box(gb[0], gb[1], gb[2], gb[3])
	var urls := tiles.urls()
	var answers := await _fetch_all(urls, "Fetching the ground heights", TRIES)
	if _cancelled:
		return null
	for i in urls.size():
		if answers[i][0] == 200:
			tiles.add_tile(i, answers[i][1])
			await _breathe()
	if tiles.loaded == 0:
		failed.emit("Couldn't fetch the ground heights. Check the connection and try again.")
		return null
	tiles.fill_missing()
	var height := tiles.height_at
	var ground_name := "open elevation tiles"

	# National lidar: the first service that covers the course.
	var lidar: NationalLidar = null
	var lidar_gaps := 0  ## lidar ground chunks that never arrived
	var lidar_outside := 0  ## services that answered with no data for the course
	var lidar_sources := NationalLidar.sources_for(lat, lon) if use_lidar else ([] as Array[Dictionary])
	for src in lidar_sources:
		lidar = NationalLidar.new(src, gb)
		var lidar_urls := PackedStringArray()
		for c in lidar.chunks:
			lidar_urls.append(lidar.url(c, false))
		if lidar.has_dsm():
			for c in lidar.chunks:
				lidar_urls.append(lidar.url(c, true))
		# Lidar services can stall on a request for minutes and then drop
		# it (the Environment Agency's did on half of them in Nov 2026), so
		# a shorter wait and a few tries: a chunk that never came was
		# filled from the coarse tiles, and the ground there came out
		# lumpy and wrong.
		var got := await _fetch_all(lidar_urls, "Fetching " + str(src["name"]), TRIES, LIDAR_TIMEOUT)
		if _cancelled:
			return null
		var dtm_missing := 0
		for i in lidar.chunks.size():
			# A tile service has no tile where it has no data.
			if got[i][0] != 200 and not (lidar.chunks[i].has("tile") and got[i][0] == 404):
				dtm_missing += 1
		for i in got.size():
			if got[i][0] == 200:
				if i % 4 == 0:
					await _step("Reading the lidar (%d of %d)..." % [i + 1, got.size()])
				var k := i % lidar.chunks.size()
				lidar.add(lidar.chunks[k], got[i][1], i >= lidar.chunks.size())
				got[i] = [0, PackedByteArray()]  # free the download
				await _breathe()
		lidar_gaps = dtm_missing
		var covers := lidar.coverage() >= 0.25 and lidar_agrees(lidar.ground_at, tiles.height_at, gb)
		if dtm_missing == 0 and not covers:
			lidar_outside += 1  # every chunk came, with no data here: outside its country
		if covers:
			height = lidar.ground_at
			builder.lidar_ground = true
			ground_name = src["name"]
			builder.extra_credits.append(src["credit"])
			if lidar.has_dsm() and not lidar.dsm.is_empty():
				var crowns: Array[Dictionary] = []
				var taken := {}
				for k in lidar.dsm.size():
					await _step("Finding the trees in the lidar (%d of %d)..." % [k + 1, lidar.dsm.size()])
					if _cancelled:
						return null
					# A band of rows at a time: a 0.5 m raster in one go held
					# the game still for two seconds (Hilversum).
					var top: GeoRaster = lidar.dsm[k]
					var chm := PackedFloat32Array()
					chm.resize(top.width * top.height)
					var band := maxi(1, LIDAR_PIXELS_PER_STEP / maxi(top.width, 1))
					for j in range(0, top.height, band):
						lidar.canopy_rows(top, chm, j, mini(j + band, top.height))
						await _breathe()
					for j in range(0, top.height, band / 2):
						lidar.crowns_in_rows(top, chm, crowns, taken, j, mini(j + band / 2, top.height))
						await _breathe()
					if _cancelled:
						return null
				builder.lidar_trees = crowns
				builder.surface = lidar.surface_at
			break
		lidar = null

	# Trees from the global canopy height map where the lidar found none.
	if use_canopy and builder.lidar_trees.is_empty() and CanopyHeights.available():
		var crowns := await _canopy_trees(gb)
		if _cancelled:
			return null
		if not crowns.is_empty():
			builder.lidar_trees = crowns
			builder.extra_credits.append(CanopyHeights.CREDIT)

	# Aerial photos: the first open service with photos of the course.
	var photo: Image = null
	var photo_sources := AerialPhotos.sources_for(lat, lon) if use_photos else ([] as Array[Dictionary])
	for psrc in photo_sources:
		var photos := AerialPhotos.new(psrc, gb)
		var purls := photos.urls()
		var pgot := await _fetch_all(purls, "Fetching the aerial photo (%s)" % psrc["name"], TRIES)
		if _cancelled:
			return null
		for i in purls.size():
			if pgot[i][0] == 200:
				photos.add_tile(i, pgot[i][1])
				await _breathe()
		pgot.clear()
		if photos.loaded * 2 < purls.size():
			continue
		await _step("Putting the aerial photo together...")
		photo = photos.course_photo(builder.frame, builder.area)
		builder.extra_credits.append(psrc["credit"])
		for t in builder.lidar_trees:
			t["leaf"] = photos.leaf_at(t["lat"], t["lon"])
		if photo != null and builder.lidar_trees.is_empty():
			await _step("Finding the trees in the photo...")
			builder.photo_trees = AerialPhotos.find_trees(photo, builder.area, builder.grass_points())
		if photo != null and AerialPhotos.has_detail(psrc) and not light:
			builder.details = await _fetch_details(psrc, builder)
			if _cancelled:
				return null
		break

	# Land cover everywhere: trees the map lacks and, without a photo, the
	# ground colours round the course.
	var cover: Image = null
	var land_cover: LandCover = null
	if use_land_cover:
		var land := LandCover.new(gb)
		var lgot := await _fetch_all(PackedStringArray([land.url()]), "Fetching the land cover", TRIES)
		if _cancelled:
			return null
		await _step("Reading the land cover...")
		if lgot[0][0] == 200 and land.add(lgot[0][1]) and land.coverage() >= 0.25:
			builder.extra_credits.append(LandCover.CREDIT)
			land_cover = land
			if builder.lidar_trees.is_empty() and builder.photo_trees.is_empty():
				builder.land_trees = land.tree_points(builder.frame, builder.area)
			if photo == null:
				cover = land.ground_image(builder.frame, builder.area)

	builder.photo = photo
	var dormant := photo != null and NativeGrass.new(photo, builder.area, [] as Array[PackedVector2Array], builder.grass_points()).is_dormant()
	if (photo == null or dormant) and use_photos:
		# No aerial photo, or one flown with the fairways dormant: the
		# (summer) satellite image, for the native grass only.
		var sat := AerialPhotos.new(AerialPhotos.SATELLITE, gb)
		var surls := sat.urls()
		var sgot := await _fetch_all(surls, "Fetching the satellite image", TRIES)
		if _cancelled:
			return null
		for i in surls.size():
			if sgot[i][0] == 200:
				sat.add_tile(i, sgot[i][1])
		if sat.loaded * 2 >= surls.size():
			await _step("Reading the satellite image...")
			builder.native_photo = sat.course_photo(builder.frame, builder.area)
			builder.extra_credits.append(AerialPhotos.SATELLITE["credit"])
	if lidar == null:
		# Open elevation tiles: speckled, and stepped at their edges.
		builder.ground_smooth = clampf(tiles.pixel_metres(lat) * 2.0, 4.0, 10.0)
		builder.ground_step = tiles.height_step()
		# Whole-metre tiles are SRTM and the like, which stand on the woods'
		# and houses' tops: taken off where the land cover has them.
		if builder.ground_step > 0.0 and land_cover != null:
			await _step("Taking the woods out of the ground...")
			var lc := land_cover
			_last_object_cut = tiles.strip_objects(func(la: float, lo: float) -> int:
				var k := lc.class_at(la, lo)
				return 2 if k == LandCover.WATER else (1 if k in [LandCover.TREES, LandCover.BUILT] else 0))
	await _step("Building %s..." % builder.course_name)
	if _cancelled:
		return null
	# A club with several courses gives one designed course each; the
	# first is opened, the others saved alongside.
	var names := builder.course_names()
	var others: Array[DesignedCourse] = []
	if not names.is_empty():
		builder.course_filter = names[0]
	var course := await _build_course(builder, height, tiles.height_at)
	if course == null:
		return null
	var first_summary := builder.summary.duplicate()
	for k in range(1, names.size()):
		await _step("Building %s..." % names[k])
		if _cancelled:
			return null
		builder.course_filter = names[k]
		var more := await _build_course(builder, height, tiles.height_at)
		if more == null:
			return null
		if not more.holes.is_empty():
			others.append(more)
	builder.course_filter = names[0] if not names.is_empty() else ""
	if use_landscape:
		await _add_landscape(builder, [course] + others)
		if _cancelled:
			return null
		if land_cover != null:
			await _step("Letting the sea in...")
			for c: DesignedCourse in [course] + others:
				RealLandscape.sea_from_cover(c, builder.frame, land_cover)
		for c: DesignedCourse in [course] + others:
			RealLandscape.raise_beaches(c, builder.frame, land_cover)
		if land_cover != null:
			await _step("Finding the ponds the map leaves out...")
			for c: DesignedCourse in [course] + others:
				RealCourseBuilder.add_ponds(c, builder.frame, land_cover)
		# A links course by the sea with no photo to read its fescue from.
		if builder.photo == null:
			var none: Array[PackedVector2Array] = []
			for c: DesignedCourse in [course] + others:
				if RealLandscape.by_the_sea(c):
					RealCourseBuilder.links_fescue(c, none)
	# What the Courses page needs to build it again with a newer builder.
	for c: DesignedCourse in [course] + others:
		RealCourseUpdate.stamp(c, place)
	_last_summary = first_summary
	_last_summary["ground"] = ground_name
	_last_summary["ground_terraced"] = builder.ground_step > 0.0
	_last_summary["woods_cut"] = snappedf(_last_object_cut, 0.1)
	if not lidar_sources.is_empty() and (lidar == null or lidar_gaps > 0) and not (lidar == null and lidar_outside == lidar_sources.size()):
		# Say so, rather than leave coarse ground looking like the lidar's.
		_last_summary["lidar_failed"] = str(lidar_sources[0]["name"]) if lidar == null else ""
		_last_summary["lidar_gaps"] = lidar_gaps
	_last_summary["lidar_trees"] = builder.lidar_trees.size()
	_last_summary["photo_trees"] = builder.photo_trees.size()
	if photo != null:
		_last_summary["photo"] = photo
	if cover != null:
		_last_summary["ground_cover"] = cover
	_last_summary["land_trees"] = builder.land_trees.size()
	_last_summary["close_ups"] = builder.details.size()
	if not others.is_empty():
		_last_summary["others"] = others
	if lidar == null:
		_last_summary["metres_per_pixel"] = snappedf(tiles.pixel_metres(lat), 0.1)
	if course.holes.is_empty():
		failed.emit(no_holes_text(builder.course_name))
		return null
	return course


static func no_holes_text(course_name: String) -> String:
	return "OpenStreetMap has no holes mapped for %s yet (each hole is a line from tee to green, tagged golf=hole). Try another course, or map it at openstreetmap.org." % course_name


## The real land round the course out to the horizon (RealLandscape), for
## each of the club's courses; left out if its tiles don't come.
func _add_landscape(builder: RealCourseBuilder, courses: Array) -> void:
	var land := RealLandscape.new(builder.frame, courses[0])
	var b := land.box()
	var tiles := TerrainTiles.for_box(b[0], b[1], b[2], b[3])
	var urls := tiles.urls()
	var got := await _fetch_all(urls, "Fetching the land round the course", TRIES)
	if _cancelled:
		return
	for i in urls.size():
		if got[i][0] == 200:
			tiles.add_tile(i, got[i][1])
			await _breathe()
	if tiles.loaded * 4 < urls.size() * 3:
		return  # a patchwork horizon is worse than none
	tiles.fill_missing()
	# The land cover along the shore round the course, for the sea under
	# cliffs (RealLandscape.sea_from_land_cover).
	if use_land_cover:
		var r := courses[0].area.grow(SHORE_REACH) as Rect2
		var lats := [builder.frame.lat_of(r.position), builder.frame.lat_of(r.end)]
		var lons := [builder.frame.lon_of(r.position), builder.frame.lon_of(r.end)]
		var shore := LandCover.new([lats.min(), lons.min(), lats.max(), lons.max()])
		var sgot := await _fetch_all(PackedStringArray([shore.url()]), "Fetching the shore", TRIES)
		if _cancelled:
			return
		if sgot[0][0] == 200 and shore.add(sgot[0][1]):
			land.cover = shore
	await _step("Shaping the land round the course...")
	var band := maxi(1, LAND_SAMPLES_PER_STEP / land.count)
	for j in range(0, land.count, band):
		land.rows(j, j + band, tiles.height_at)
		await _breathe()
		if _cancelled:
			return
	for c: DesignedCourse in courses:
		land.apply(c)


## Builds the builder's course a step at a time, drawing frames between;
## null if cancelled.
func _build_course(builder: RealCourseBuilder, height: Callable, fallback: Callable) -> DesignedCourse:
	var c := builder.start_build()
	for step in builder.build_steps(c, height, fallback):
		step.call()
		await _breathe()
		if _cancelled:
			return null
	return c


## True unless the lidar's ground is plainly not the ground: outside its
## country a service may answer with zeros rather than no data (England's
## does over Northern Ireland, Wales and southern Scotland, and Royal County
## Down came out as a flat sheet at sea level, flooded). Mostly zeros where
## the coarse tiles see land above 2 m, or tens of metres off them overall,
## isn't lidar. (A few metres off is normal: where the tiles come from SRTM
## they measure the tree tops, as over Hilversum's woods.)
static func lidar_agrees(lidar: Callable, coarse: Callable, box: Array[float], grid := 12) -> bool:
	var ours := PackedFloat32Array()
	var theirs := PackedFloat32Array()
	var zeros := 0
	for j in grid:
		for i in grid:
			var lat := lerpf(box[0], box[2], (j + 0.5) / grid)
			var lon := lerpf(box[1], box[3], (i + 0.5) / grid)
			var h := float(lidar.call(lat, lon))
			if is_nan(h):
				continue
			ours.append(h)
			theirs.append(float(coarse.call(lat, lon)))
			if absf(h) < 0.01:
				zeros += 1
	if ours.size() < grid:
		return false
	ours.sort()
	theirs.sort()
	var mid := ours.size() / 2
	if zeros * 2 > ours.size() and theirs[mid] > 2.0:
		return false
	return absf(ours[mid] - theirs[mid]) < LIDAR_AGREE_M


## Close-up photos round the greens the map leaves unfinished
## (RealCourseBuilder.detail_spots), from the photo service `psrc`, all
## fetched in one go: [{"image", "area"}].
func _fetch_details(psrc: Dictionary, builder: RealCourseBuilder) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var spots := builder.detail_spots()
	if spots.size() > MAX_DETAILS:
		spots = spots.slice(0, MAX_DETAILS)
	var parts: Array[AerialPhotos] = []
	var all_urls := PackedStringArray()
	for spot in spots:
		var a := AerialPhotos.detail_area(spot)
		var part := AerialPhotos.new(psrc, AerialPhotos.geo_box_of(builder.frame, a), AerialPhotos.DETAIL_ZOOM)
		parts.append(part)
		all_urls.append_array(part.urls())
	if all_urls.is_empty():
		return out
	var got := await _fetch_all(all_urls, "Fetching close-ups of the greens")
	if _cancelled:
		return out
	var at := 0
	for k in parts.size():
		var part := parts[k]
		var n := part.urls().size()
		for i in n:
			if got[at + i][0] == 200:
				part.add_tile(i, got[at + i][1])
		at += n
		if part.loaded * 4 < n * 3:
			continue
		var a := AerialPhotos.detail_area(spots[k])
		var img := part.course_photo(builder.frame, a, AerialPhotos.DETAIL_RES)
		if img != null:
			out.append({"image": img, "area": a})
	return out


## The Overpass query for everything a course needs in a box.
static func overpass_query(s: float, w: float, n: float, e: float) -> String:
	var bb := "(%.6f,%.6f,%.6f,%.6f)" % [s, w, n, e]
	return ("[out:json][timeout:%d];(" % OVERPASS_QUERY_SECS +
		"nwr[\"golf\"]%s;" % bb +
		"nwr[\"leisure\"=\"golf_course\"]%s;" % bb +
		"nwr[\"natural\"~\"^(water|wood|scrub|heath|wetland|dune|grassland)$\"]%s;" % bb +
		"way[\"natural\"=\"tree_row\"]%s;" % bb +
		"way[\"barrier\"~\"^(wall|dry_stone_wall|stone_wall|hedge)$\"]%s;" % bb +
		"nwr[\"landuse\"~\"^(forest|reservoir|basin)$\"]%s;" % bb +
		"node[\"natural\"=\"tree\"]%s;" % bb +
		"way[\"waterway\"~\"^(river|stream|canal|ditch|drain)$\"]%s;" % bb +
		"way[\"building\"]%s;" % bb +
		"way[\"highway\"~\"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service|track|footway|path|cycleway|bridleway)$\"]%s;" % bb +
		");out geom;")


## The places Nominatim finds for `q`; null if it couldn't be reached.
func _search_once(q: String) -> Variant:
	return await _search_url(NOMINATIM % q.uri_encode())


## Golf courses round (lat, lon); null if the search couldn't be reached.
func _search_near(lat: float, lon: float) -> Variant:
	var dlon := NEAR_DEGREES / maxf(cos(deg_to_rad(lat)), 0.1)
	return await _search_url(NOMINATIM_NEAR % [lon - dlon, lat + NEAR_DEGREES, lon + dlon, lat - NEAR_DEGREES])


## Metres from (lat, lon) to a found place: 0 inside its box, else to its
## middle.
static func near_distance(place: Dictionary, lat: float, lon: float) -> float:
	var box: Array = place.get("box", [])
	if box.size() == 4 and lat >= float(box[0]) and lat <= float(box[1]) and lon >= float(box[2]) and lon <= float(box[3]):
		return 0.0
	return GeoFrame.new(lat, lon).to_local(float(place["lat"]), float(place["lon"])).length()


func _search_url(url: String) -> Variant:
	# Nominatim asks for a second between requests.
	var wait := _last_search + NOMINATIM_GAP_MS - Time.get_ticks_msec()
	if wait > 0:
		await get_tree().create_timer(wait / 1000.0).timeout
	_last_search = Time.get_ticks_msec()
	var res := await _http_get(url)
	if res[0] != 200:
		return null
	var out: Array[Dictionary] = []
	var parsed: Variant = JSON.parse_string((res[1] as PackedByteArray).get_string_from_utf8())
	if not parsed is Array:
		return null
	for r: Variant in parsed:
		if not r is Dictionary:
			continue
		var golf: bool = str(r.get("type", "")) == "golf_course"
		out.append({
			"name": str(r.get("name", "")),
			"label": str(r.get("display_name", "")),
			"lat": float(r.get("lat", 0)),
			"lon": float(r.get("lon", 0)),
			"box": r.get("boundingbox", []),
			"golf": golf,
		})
	return out


static func _has_golf(results: Array) -> bool:
	for r in results:
		if r["golf"]:
			return true
	return false

## Golf courses round the first places found, nearest first round each.
func _golf_near(places: Array) -> Array:
	var near: Array = []
	for r: Dictionary in places.slice(0, NEAR_LOOKUPS):
		var more: Variant = await _search_near(float(r["lat"]), float(r["lon"]))
		if more == null:
			continue
		var golf: Array[Dictionary] = []
		for m: Dictionary in more:
			if m["golf"] and not near.any(func(o: Dictionary) -> bool: return o["label"] == m["label"]):
				m["near"] = near_distance(m, float(r["lat"]), float(r["lon"]))
				golf.append(m)
		# The course round the clubhouse first (Crans-sur-Sierre's club is
		# a point inside its Ballesteros course, with another club's nine a
		# mile off).
		golf.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["near"] < b["near"])
		near.append_array(golf)
	return near


## The places found whose address holds every word of the name ("Cabo del
## Sol Ocean" finds an Ocean Basket restaurant on a Sol Plaatje road in
## South Africa).
static func _naming(results: Variant, name: String) -> Array:
	var words := RealCourseBuilder.name_words(name)
	return (results as Array).filter(func(r: Dictionary) -> bool:
		var label := str(r.get("label", r.get("name", ""))).to_lower()
		for w in words:
			if not label.contains(w):
				return false
		return true)


## Whether a golf course among the results carries the name's words in its
## own name (any of them, or all with every_word), not just in its address.
static func _has_named_golf(results: Array, name: String, every_word: bool) -> bool:
	var words := RealCourseBuilder.name_words(name)
	for r in results:
		if not r["golf"]:
			continue
		if words.is_empty():
			return true
		var own := RealCourseBuilder.name_words(str(r["name"]))
		var shared := 0
		for w in words:
			if w in own:
				shared += 1
		if shared == words.size() or (shared > 0 and not every_word):
			return true
	return false



## The Overpass answer; {} if no server gives one. Every server is asked
## at once and the first full answer wins, because the public servers are
## often busy: one may sit on a query for minutes, or drop it, while
## another answers. If none answer, they are all asked again, up to
## OVERPASS_TRIES rounds. Progress shows the time waited and the data
## received, so a slow server never looks like a frozen game.
func _overpass(query: String) -> Dictionary:
	var body := "data=" + query.uri_encode()
	var headers := ["Content-Type: application/x-www-form-urlencoded"]
	for round in OVERPASS_TRIES:
		if _cancelled:
			break
		if round > 0:
			progress.emit("The map servers are busy; asking them again (try %d of %d)..." % [round + 1, OVERPASS_TRIES])
			await get_tree().create_timer(OVERPASS_RETRY_WAIT * round).timeout
			if _cancelled:
				break
		var answers: Array = []
		answers.resize(servers.size())
		var reqs: Array[HTTPRequest] = []
		var done := [0]
		for i in servers.size():
			var req := _make_request(OVERPASS_TIMEOUT)
			reqs.append(req)
			_overpass_into(req, str(servers[i]), body, headers, answers, i, done)
		var started := Time.get_ticks_msec()
		var won := {}
		while not _cancelled and won.is_empty() and done[0] < servers.size():
			await get_tree().process_frame
			for a: Variant in answers:
				if a is Dictionary and not (a as Dictionary).is_empty():
					won = a
					break
			if won.is_empty():
				progress.emit(overpass_status(answers, reqs, (Time.get_ticks_msec() - started) / 1000.0))
		if won.is_empty():
			for a: Variant in answers:
				if a is Dictionary and not (a as Dictionary).is_empty():
					won = a
					break
		# Stop the slower servers: their answers aren't needed.
		for req in reqs:
			if is_instance_valid(req) and req.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
				req.set_meta("dropped", true)
				req.cancel_request()
				req.request_completed.emit(HTTPRequest.RESULT_REQUEST_FAILED, 0, PackedStringArray(), PackedByteArray())
		if not won.is_empty():
			return won
	return {}


## One server's Overpass answer into answers[i]: the parsed map, or {}.
func _overpass_into(req: HTTPRequest, url: String, body: String, headers: Array, answers: Array, i: int, done: Array) -> void:
	var res := await _send(req, url, HTTPClient.METHOD_POST, body, headers)
	var got := {}
	if res[0] == 200:
		var parsed: Variant = JSON.parse_string((res[1] as PackedByteArray).get_string_from_utf8())
		if parsed is Dictionary and parsed.get("elements", null) is Array:
			got = parsed
	answers[i] = got
	done[0] += 1


## The progress line while waiting for the map servers: what has arrived
## so far, or how long they have been thinking.
static func overpass_status(answers: Array, reqs: Array, secs: float) -> String:
	var bytes := 0
	for i in reqs.size():
		if answers[i] == null and is_instance_valid(reqs[i]):
			bytes = maxi(bytes, (reqs[i] as HTTPRequest).get_downloaded_bytes())
	if bytes >= 100000:
		return "Reading the course map from OpenStreetMap (%.1f MB received)..." % (bytes / 1048576.0)
	if secs < 20.0:
		return "Reading the course map from OpenStreetMap..."
	return "Waiting for OpenStreetMap's map servers (%d:%02d). They are busy; this can take a few minutes..." % [int(secs) / 60, int(secs) % 60]


## Fetches every URL, PARALLEL at a time; [[code, bytes], ...] in order.
## Over `tries` rounds, the ones that failed (no answer, or a server error
## or rate limit) are asked for again; `timeout` is seconds per request.
## Tree crowns from CanopyHeights for the box (south, west, north, east):
## only the course's tiles are downloaded, and read one at a time between
## frames. Empty if the map can't be read.
func _canopy_trees(box: Array) -> Array[Dictionary]:
	var crowns: Array[Dictionary] = []
	var taken := {}
	var canopy := CanopyHeights.new(box)
	for part in canopy.parts:
		var url: String = part["url"]
		await _step("Fetching the tree heights...")
		var head := await fetch_range(url, Vector2i(0, CanopyHeights.HEADER_BYTES - 1))
		var header := CanopyHeights.parse_header(head)
		if header.is_empty():
			return crowns
		var offsets := await fetch_range(url, CanopyHeights.index_range(header, "offsets", part))
		var counts := await fetch_range(url, CanopyHeights.index_range(header, "counts", part))
		if offsets.is_empty() or counts.is_empty() or _cancelled:
			return crowns
		var tiles := CanopyHeights.tiles_for(part)
		var ranges: Array[Vector2i] = []
		for t in tiles:
			ranges.append(CanopyHeights.tile_range(header, offsets, counts, part, t))
		var got := await fetch_ranges(url, ranges, "Fetching the tree heights")
		if _cancelled:
			return crowns
		var raster := CanopyHeights.raster_for(part)
		var band := maxi(1, LIDAR_PIXELS_PER_STEP / 4 / maxi(raster.width, 1) * 4)
		for k in tiles.size():
			if ranges[k].x < 0:
				continue  # the sea: bare
			if (got[k] as PackedByteArray).is_empty() or not CanopyHeights.decode_tile(part, header, tiles[k], got[k], raster):
				return crowns
			if k % 4 == 0:
				await _step("Reading the tree heights (%d%%)..." % (100 * k / tiles.size()))
			await _breathe()
			if _cancelled:
				return crowns
		got.clear()
		var smooth := PackedFloat32Array()
		smooth.resize(raster.width * raster.height)
		await _step("Finding the trees in the tree heights...")
		for j in range(0, raster.height, band):
			CanopyHeights.smooth_rows(raster, smooth, j, mini(j + band + 1, raster.height))
			await _breathe()
		for j in range(0, raster.height, band):
			CanopyHeights.crowns_in_rows(raster, smooth, crowns, taken, j, mini(j + band, raster.height))
			await _breathe()
			if _cancelled:
				return crowns
	return crowns


## Bytes `r.x` to `r.y` (inclusive) of `url`, or empty on any failure.
func fetch_range(url: String, r: Vector2i, timeout := LIDAR_TIMEOUT) -> PackedByteArray:
	for attempt in TRIES:
		var got := await _request(url, HTTPClient.METHOD_GET, "", ["Range: bytes=%d-%d" % [r.x, r.y]], timeout)
		if int(got[0]) == 206 and (got[1] as PackedByteArray).size() == r.y - r.x + 1:
			return got[1]
		if int(got[0]) != 0 and int(got[0]) < 500:
			break
	return PackedByteArray()


## Byte ranges of one file, PARALLEL at a time, each asked for again on a
## failure (fetch_range); an empty array for a failed range or one with x < 0.
func fetch_ranges(url: String, ranges: Array[Vector2i], label: String) -> Array:
	var out: Array = []
	out.resize(ranges.size())
	var state := [0, 0]  # started, finished
	var todo: Array[int] = []
	for i in ranges.size():
		if ranges[i].x < 0:
			out[i] = PackedByteArray()
		else:
			todo.append(i)
	while (state[0] < todo.size() and not _cancelled) or state[0] > state[1]:
		while state[0] - state[1] < PARALLEL and state[0] < todo.size() and not _cancelled:
			_range_into(url, ranges[todo[state[0]]], out, todo[state[0]], state)
			state[0] += 1
		await get_tree().process_frame
		progress.emit("%s (%d of %d)...%s" % [label, state[1], todo.size(), door.waiting_note(Time.get_ticks_msec())])
	for i in out.size():
		if out[i] == null:
			out[i] = PackedByteArray()
	return out


func _range_into(url: String, r: Vector2i, out: Array, i: int, state: Array) -> void:
	out[i] = await fetch_range(url, r)
	state[1] += 1


## Downloads `urls` a few at a time, asking again for failures: one
## [code, bytes] per url (the designer's satellite guide uses it).
func fetch_urls(urls: PackedStringArray, label: String) -> Array:
	return await _fetch_all(urls, label, TRIES)


func _fetch_all(urls: PackedStringArray, label: String, tries := 1, timeout := 120.0) -> Array:
	var out: Array = []
	out.resize(urls.size())
	var todo := PackedInt32Array()
	for i in urls.size():
		todo.append(i)
	for round in tries:
		if round > 0:
			todo = retry_list(out)
			if todo.is_empty() or _cancelled:
				break
			progress.emit("%s: asking again for %d of %d..." % [label, todo.size(), urls.size()])
			await get_tree().create_timer(RETRY_WAIT * round).timeout
		var next := 0
		var running := 0
		var done := [0]
		while (next < todo.size() and not _cancelled) or running > 0:
			while running < PARALLEL and next < todo.size() and not _cancelled:
				var i := todo[next]
				next += 1
				running += 1
				_fetch_into(urls[i], out, i, done, timeout)
			await get_tree().process_frame
			running = (next - done[0])
			progress.emit("%s (%d of %d)...%s" % [label, done[0], todo.size(), door.waiting_note(Time.get_ticks_msec())])
	return out


## The indices of the answers in `out` worth asking for again: none came,
## or the server was busy or failed (5xx, 408, 429). A 4xx says the
## request itself is wrong, and asking again won't change it.
static func retry_list(out: Array) -> PackedInt32Array:
	var again := PackedInt32Array()
	for i in out.size():
		var code := int(out[i][0]) if out[i] is Array and not (out[i] as Array).is_empty() else 0
		if code == 0 or code >= 500 or code == 408 or code == 429:
			again.append(i)
	return again


func _fetch_into(url: String, out: Array, i: int, done: Array, timeout := 120.0) -> void:
	out[i] = await _request(url, HTTPClient.METHOD_GET, "", [], timeout)
	done[0] += 1


func _http_get(url: String) -> Array:
	return await _request(url, HTTPClient.METHOD_GET, "", [])


## [status code (0 on failure), body bytes].
func _request(url: String, method: int, body: String, headers: Array, timeout := 120.0) -> Array:
	return await _send(_make_request(timeout), url, method, body, headers)


## A new HTTPRequest child, ready for _send.
func _make_request(timeout: float) -> HTTPRequest:
	var req := HTTPRequest.new()
	req.timeout = timeout
	# Polled each frame, not on a thread: when a threaded request times out
	# (or is cancelled) Godot waits for its thread, which sits in a blocking
	# read until the server lets go, freezing the game for a minute or more
	# (seen on West Essex with a busy map server). Big chunks keep it fast.
	req.use_threads = false
	req.download_chunk_size = DOWNLOAD_CHUNK
	add_child(req)
	if configure_request.is_valid():
		configure_request.call(req)
	return req


## Sends `req` and frees it; [status code (0 on failure), body bytes].
## A cached answer (see _fetch_cache_lookup) comes back without asking the
## server, and doesn't spend the server's rate limit.
func _send(req: HTTPRequest, url: String, method: int, body: String, headers: Array) -> Array:
	var cache_key := ""
	if fetch_cache_enabled:
		cache_key = _fetch_cache_key(url, method, body, headers)
		var hit := _fetch_cache_lookup(cache_key, url)
		if not hit.is_empty():
			req.queue_free()
			return hit
	if not OS.has_feature("web"):
		headers = headers + ["User-Agent: " + USER_AGENT]
	var host := NetDoor.host_of(url)
	while true:
		var wait := door.wait_ms(host, Time.get_ticks_msec())
		if _cancelled or wait < 0:
			# A server failing again and again is left alone for a while.
			req.queue_free()
			return [0, PackedByteArray()]
		if wait == 0:
			break
		await get_tree().create_timer(minf(wait, 250) / 1000.0).timeout
	var id := door.started(host, Time.get_ticks_msec())
	var err := req.request(url, PackedStringArray(headers), method, body)
	if err != OK:
		door.finished(host, id, 0, PackedStringArray(), Time.get_ticks_msec())
		req.queue_free()
		return [0, PackedByteArray()]
	var res: Array = await req.request_completed
	var dropped := req.has_meta("dropped")  # we stopped it: not the server's fault
	req.queue_free()
	if dropped:
		door.dropped(host, id)
		return [0, PackedByteArray()]
	var ok: bool = res[0] == HTTPRequest.RESULT_SUCCESS
	door.finished(host, id, int(res[1]) if ok else 0, res[2] if ok else PackedStringArray(), Time.get_ticks_msec())
	if not ok:
		return [0, PackedByteArray()]
	if fetch_cache_enabled and not cache_key.is_empty() and int(res[1]) in [200, 206, 404]:
		_fetch_cache_store(cache_key, int(res[1]), res[3])
	return [res[1], res[3]]


## The cache entry for a request: the SHA-256 of its method, URL, body and
## byte range, so the same tile asked for twice is one entry and a different
## range is another. "" when the hash can't be started.
static func _fetch_cache_key(url: String, method: int, body: String, headers: Array) -> String:
	var range := ""
	for h in headers:
		if str(h).to_lower().begins_with("range:"):
			range = str(h)
			break
	var ctx := HashingContext.new()
	if ctx.start(HashingContext.HASH_SHA256) != OK:
		return ""
	ctx.update(("%d\n%s\n%s\n%s" % [method, url, body, range]).to_utf8_buffer())
	return ctx.finish().hex_encode()


static func _fetch_cache_path(key: String) -> String:
	return fetch_cache_dir.path_join(key + ".bin")


static func _fetch_cache_ttl(url: String) -> int:
	if url.contains("nominatim") or url.contains("overpass"):
		return FETCH_CACHE_TTL_SHORT
	return FETCH_CACHE_TTL_LONG


## A cached answer for `key`, [code, body], or [] on a miss or a stale one.
## The file is a u32 status, a u64 time saved (unix) and the body.
static func _fetch_cache_lookup(key: String, url: String) -> Array:
	if key.is_empty() or not fetch_cache_enabled:
		return []
	var f := FileAccess.open(_fetch_cache_path(key), FileAccess.READ)
	if f == null:
		return []
	var head := f.get_buffer(12)
	if head.size() < 12:
		return []
	var code := head.decode_u32(0)
	if not code in [200, 206, 404]:
		return []
	if Time.get_unix_time_from_system() - int(head.decode_u64(4)) > _fetch_cache_ttl(url):
		return []
	return [code, f.get_buffer(f.get_length() - 12)]


static func _fetch_cache_store(key: String, code: int, body: PackedByteArray) -> void:
	if key.is_empty() or not fetch_cache_enabled:
		return
	DirAccess.make_dir_recursive_absolute(fetch_cache_dir)
	var head := PackedByteArray()
	head.resize(12)
	head.encode_u32(0, code)
	head.encode_u64(4, Time.get_unix_time_from_system())
	var f := FileAccess.open(_fetch_cache_path(key), FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(head)
	f.store_buffer(body)
	f.close()  # close before pruning: the prune reads the file back, and
	# a still-open write handle keeps it from opening again
	_fetch_cache_prune()


## Drops the oldest entries until the cache fits its cap.
static func _fetch_cache_prune() -> void:
	var dir := DirAccess.open(fetch_cache_dir)
	if dir == null:
		return
	var entries: Array = []
	var total := 0
	for name in dir.get_files():
		if not name.ends_with(".bin"):
			continue
		var p := fetch_cache_dir.path_join(name)
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var head := f.get_buffer(12)
		entries.append([int(head.decode_u64(4)) if head.size() == 12 else 0, f.get_length(), p])
		total += f.get_length()
	if total <= fetch_cache_max_bytes:
		return
	entries.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for e in entries:
		if total <= fetch_cache_max_bytes:
			break
		DirAccess.remove_absolute(e[2])
		total -= int(e[1])
