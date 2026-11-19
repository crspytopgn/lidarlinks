class_name ScannedSurfaces
extends RefCounted
## Scanned wood, asphalt and stone surfaces from the private Megascans pack
## (docs/megascans-pack.md): surfaces/surfaces.json, written by
## tools/megascans/build_surfaces.py, names one baked scan per slot, each
## with albedo, normal and roughness maps and its real size in metres.
## Without a pack (and always on the web) every call returns the fallback,
## so the flat materials stay.
##
## Slots: "path" (cart paths, asphalt), "deck" (a bridge's deck, its boards
## running along the image's x), "timber" (a bridge's boarded sides, boards
## along x), "bench" (the tee bench's slats).
##
## A slot can have regional versions, "path@us" and so on, picked by where
## the course is in the world (region_for, with the birdsong's place data):
## concrete cart paths in the US, grey tarmac in Britain. A region without
## its own version uses the plain slot.

const MANIFEST := "surfaces/surfaces.json"
const SLOTS := ["path", "deck", "timber", "bench"]
const REGIONS := ["uk", "europe", "us", "desert", "tropical", "south"]

## Where the region boxes are, (lat from, lat to, lon from, lon to), first
## match wins: Britain and Ireland; the rest of Europe and the
## Mediterranean; the tropics (Hawaii, the Caribbean, Cabo and Mexico's
## coasts); North America; Australia and New Zealand.
const REGION_BOXES := [
	[49.5, 61.0, -11.0, 2.0, "uk"],
	[35.0, 71.0, -11.0, 40.0, "europe"],
	[-23.5, 23.5, -180.0, 180.0, "tropical"],
	[24.0, 60.0, -170.0, -50.0, "us"],
	[-48.0, -10.0, 110.0, 180.0, "south"],
]

## The region of the course being played ("" for none: the plain slots).
static var region := ""

static var _slots := {}
static var _loaded := false
static var _mats := {}  ## key -> material


## The region for a course at `at` (lat, lon; NAN when unknown) of kind
## `setting` (FreeAmbience.Setting): desert courses are "desert" wherever
## they are.
static func region_for(at: Vector2, setting: int) -> String:
	if setting == FreeAmbience.Setting.DESERT:
		return "desert"
	if is_nan(at.x):
		return ""
	for box: Array in REGION_BOXES:
		if at.x >= box[0] and at.x <= box[1] and at.y >= box[2] and at.y <= box[3]:
			return box[4]
	return ""


## Sets the region from a course (FreeAmbience's place data).
## OL_SURFACE_REGION overrides it (to look at another region's scans).
static func use_course(course: CourseData) -> void:
	var forced := OS.get_environment("OL_SURFACE_REGION")
	if not forced.is_empty():
		region = forced
		return
	if course == null:
		region = ""
		return
	var at := FreeAmbience.location_of(course)
	var setting: int = FreeAmbience.setting_for_place(course.course_name, at)
	var place := FreeAmbience.known_place(course.course_name)
	if is_nan(course.location.x) and not place.is_empty() and place[3] >= 0:
		setting = int(place[3])
	region = region_for(at, setting)


## The pack's entry for `slot` in the current region, or {}.
static func entry(slot: String, from: Dictionary = slots()) -> Dictionary:
	if not region.is_empty() and from.has(slot + "@" + region):
		return from[slot + "@" + region]
	return from.get(slot, {})


## The pack's slots: name -> {"title", "albedo", "normal", "roughness", "size_m"}.
static func slots() -> Dictionary:
	if not _loaded:
		_loaded = true
		var dir := FreeAssets.pack_dir(MANIFEST)
		if not dir.is_empty() and FileAccess.file_exists(dir + MANIFEST):
			_slots = parse(FileAccess.get_file_as_string(dir + MANIFEST))
	return _slots


## The slots in a surfaces.json text; unknown slots and entries without an
## albedo are skipped.
static func parse(text: String) -> Dictionary:
	var out := {}
	var data: Variant = JSON.parse_string(text)
	var list: Variant = data.get("slots", {}) if data is Dictionary else {}
	if not list is Dictionary:
		return out
	for name: Variant in list:
		var s: Variant = list[name]
		var parts := str(name).split("@")
		if not SLOTS.has(parts[0]) or (parts.size() > 1 and not REGIONS.has(parts[1])):
			continue
		if not s is Dictionary or str(s.get("albedo", "")).is_empty():
			continue
		out[str(name)] = {"title": str(s.get("title", "")), "albedo": str(s["albedo"]),
			"normal": str(s.get("normal", "")), "roughness": str(s.get("roughness", "")),
			"size_m": clampf(float(s.get("size_m", 2.0)), 0.1, 20.0)}
	return out


static func has(slot: String) -> bool:
	return not entry(slot).is_empty()


## The scan for `slot` on a mesh whose UVs are in metres divided by
## `uv_metres` (so one UV unit spans `uv_metres` metres both ways), or
## `fallback` without one. `double_sided` for open strips seen from both sides.
static func uv_material(slot: String, uv_metres: float, fallback: Material, double_sided := false) -> Material:
	if not has(slot):
		return fallback
	var e := entry(slot)
	var key := "%s:%s:uv:%.2f:%s" % [slot, e["albedo"], uv_metres, double_sided]
	if not _mats.has(key):
		var m := _base(e, fallback)
		var reps := uv_metres / float(e["size_m"])
		m.uv1_scale = Vector3(reps, reps, 1.0)
		if double_sided:
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[key] = m
	return _mats[key]


## The scan for `slot` projected in the object's own space from three
## sides (for meshes without UVs, such as the props), or `fallback`.
## Vertex colours (the props' baked shade) darken it.
static func triplanar_material(slot: String, fallback: Material) -> Material:
	if not has(slot):
		return fallback
	var e := entry(slot)
	var key := "%s:%s:tri" % [slot, e["albedo"]]
	if not _mats.has(key):
		var m := _base(e, fallback)
		m.uv1_triplanar = true
		m.uv1_triplanar_sharpness = 4.0
		var reps := 1.0 / float(e["size_m"])
		m.uv1_scale = Vector3(reps, reps, reps)
		m.vertex_color_use_as_albedo = true
		_mats[key] = m
	return _mats[key]


static func _base(s: Dictionary, fallback: Material) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = FreeAssets.megascans_surface(s["albedo"])
	var n := FreeAssets.megascans_surface(s["normal"], true)
	if n != null:
		m.normal_enabled = true
		m.normal_texture = n
		m.normal_scale = 1.0
	var r := FreeAssets.megascans_surface(s["roughness"])
	m.roughness = 1.0
	if r != null:
		m.roughness_texture = r
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	elif fallback is BaseMaterial3D:
		m.roughness = (fallback as BaseMaterial3D).roughness
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m
