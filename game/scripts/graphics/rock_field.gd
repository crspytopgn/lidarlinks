class_name RockField
extends Node3D
## Photoscanned boulders from the private Megascans pack (rocks/, see
## docs/megascans-pack.md) where real courses have stone: along the banks of
## ponds and creeks, and scattered through the deep rough and the woods off
## the line of play, with the odd outcrop far out. Nothing is placed within
## reach of the mown turf, so they're scenery only: the ball never meets
## them. Without the pack (and so always on the web) there are none.
##
## The stone follows where the course is (FreeAmbience's setting, from its
## real place): weathered beach boulders and sea-cliff outcrops on a links,
## red sandstone in the desert, mossy, lichened boulders in the woods and on
## parkland, which also gets the odd grey upland stone.

const MANIFEST := "rocks/rocks.json"
## The grid the hole's ground is searched on (metres).
const STEP := 3.0
## How far round the hole's tee-to-pin line rocks may go (metres).
const MARGIN := 70.0
## No rock nearer the mown turf, sand or green than this (metres).
const CLEAR := 7.0
## Chances per grid cell, at full quality: on a bank, in deep rough or the
## woods, and of an outcrop in deep rough well clear of play.
const BANK_CHANCE := 0.45
const ROUGH_CHANCE := 0.012
const OUTCROP_CHANCE := 0.0015
## Rocks drawn at each quality level (Low, Medium, High, Ultra), as a share.
const DENSITY_BY_QUALITY: Array[float] = [0.0, 0.4, 0.75, 1.0]
## Rocks sit partly buried, as real ones do: this share of their height.
const SINK := Vector2(0.15, 0.35)
## Rocks lie in little groups, as frost and glaciers leave them: up to
## this many more round each one, smaller, within a few metres.
const CLUSTER := 4

static var _rocks: Array = []
static var _loaded := false
static var _meshes := {}
static var _materials := {}


## The stone each setting (FreeAmbience.Setting) uses: on banks, in the
## rough and woods, and for outcrops; and how many rocks it has (desert
## courses are strewn with them).
const STYLES := {
	FreeAmbience.Setting.PARKLAND: {"bank": ["woodland", "upland"], "rough": ["woodland", "upland", "scatter"], "outcrop": ["dry_outcrop"], "more": 1.0},
	FreeAmbience.Setting.WOODLAND: {"bank": ["woodland"], "rough": ["woodland", "scatter"], "outcrop": ["dry_outcrop"], "more": 1.5},
	FreeAmbience.Setting.SEASIDE: {"bank": ["shore"], "rough": ["shore", "scatter"], "outcrop": ["shore_outcrop"], "more": 1.0},
	FreeAmbience.Setting.DESERT: {"bank": ["sandstone", "upland"], "rough": ["sandstone", "upland", "scatter"], "outcrop": ["dry_outcrop", "sandstone"], "more": 3.0},
}


## The pack's rocks: [{id, title, size: [x, y, z], kind}], kind being
## "shore", "shore_outcrop", "sandstone", "upland", "dry_outcrop",
## "woodland" or "scatter" (tools/megascans/rock_pack.gd). Empty without one.
static func rocks() -> Array:
	if not _loaded:
		_loaded = true
		var dir := FreeAssets.megascans_dir()
		if not dir.is_empty() and FileAccess.file_exists(dir + MANIFEST):
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + MANIFEST))
			if data is Dictionary and (data as Dictionary).get("rocks") is Array:
				_rocks = data["rocks"]
	return _rocks


static func available() -> bool:
	return not rocks().is_empty()


## A rock's mesh (real size, base at y = 0), loaded once; null if missing.
static func mesh(id: String) -> Mesh:
	if not _meshes.has(id):
		var path := FreeAssets.megascans_dir() + "rocks/" + id + ".res"
		_meshes[id] = ResourceLoader.load(path) as Mesh if FileAccess.file_exists(path) else null
	return _meshes[id]


## A rock's material from its scanned maps, made once.
static func material(id: String) -> Material:
	if not _materials.has(id):
		var m := StandardMaterial3D.new()
		m.albedo_texture = FreeAssets.megascans_texture(id + "_albedo.jpg", "rocks/")
		var n := FreeAssets.megascans_texture(id + "_normal.jpg", "rocks/", true)
		if n != null:
			m.normal_enabled = true
			m.normal_texture = n
		var r := FreeAssets.megascans_texture(id + "_rough.jpg", "rocks/")
		if r != null:
			m.roughness_texture = r
			m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.roughness = 1.0
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_materials[id] = m
	return _materials[id]


## The setting a course's rocks follow, as FreeAmbience picks it.
static func setting_of(course: CourseData) -> FreeAmbience.Setting:
	if course == null:
		return FreeAmbience.Setting.PARKLAND
	var at := FreeAmbience.location_of(course)
	var setting := FreeAmbience.setting_for_place(course.course_name, at)
	var place := FreeAmbience.known_place(course.course_name)
	if is_nan(course.location.x) and not place.is_empty() and place[3] >= 0:
		setting = place[3] as FreeAmbience.Setting
	return setting


## The rocks for `hole` at a quality level, or null when there are none.
static func build(hole: HoleData, quality: int, setting := FreeAmbience.Setting.PARKLAND) -> RockField:
	var density: float = DENSITY_BY_QUALITY[clampi(quality, 0, DENSITY_BY_QUALITY.size() - 1)]
	if density <= 0.0 or not available():
		return null
	var by_kind := {}
	for r: Dictionary in rocks():
		if not by_kind.has(r["kind"]):
			by_kind[r["kind"]] = []
		by_kind[r["kind"]].append(r)
	var spots := place(hole.terrain, hole.tee, hole.pin, density, hole.number * 7741 + 13, STYLES[setting])
	if spots.is_empty():
		return null
	var field := RockField.new()
	field.name = "RockField"
	var rng := RandomNumberGenerator.new()
	rng.seed = hole.number * 104729 + 7
	var per_rock := {}  # id -> Array[Transform3D]
	for s: Array in spots:
		var kinds: Array = s[1]
		var pick: Array = []
		for k: String in kinds:
			pick.append_array(by_kind.get(k, []))
		if pick.is_empty():
			continue
		var group := 1 + (rng.randi() % (CLUSTER + 1) if not kinds.has("shore_outcrop") and not kinds.has("dry_outcrop") else 0)
		var first: Vector3 = s[0]
		for g in group:
			var rock: Dictionary = pick[rng.randi() % pick.size()]
			var size: Array = rock["size"]
			# The first is the big one; the rest are smaller, round it.
			var scale := rng.randf_range(0.8, 1.2) if g == 0 else rng.randf_range(0.3, 0.65)
			var at := first
			if g > 0:
				var r := (float(size[0]) + 1.0) * rng.randf_range(0.6, 1.6)
				var a := rng.randf() * TAU
				at += Vector3(cos(a), 0.0, sin(a)) * r
				if t_blocked(hole.terrain, at):
					continue
			var b := Basis(Vector3.UP, rng.randf() * TAU)
			b = Basis(Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.0, 0.2)) * b
			at.y = hole.terrain.height_at(at.x, at.z) - rng.randf_range(SINK.x, SINK.y) * float(size[1]) * scale
			if not per_rock.has(rock["id"]):
				per_rock[rock["id"]] = []
			per_rock[rock["id"]].append(Transform3D(b.scaled(Vector3.ONE * scale), at))
	for id: String in per_rock:
		var m := mesh(id)
		if m == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m
		mm.instance_count = per_rock[id].size()
		for i in mm.instance_count:
			mm.set_instance_transform(i, per_rock[id][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = material(id)
		mmi.visibility_range_end = 450.0
		field.add_child(mmi)
	return field


## Where rocks go round the line from `tee` to `pin`: [[position, kinds]],
## the kinds that suit the spot. Deterministic for a seed.
static func place(t: CourseTerrain, tee: Vector3, pin: Vector3, density: float, seed_value: int, style: Dictionary = STYLES[FreeAmbience.Setting.PARKLAND]) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var lo := Vector2(minf(tee.x, pin.x), minf(tee.z, pin.z)) - Vector2.ONE * MARGIN
	var hi := Vector2(maxf(tee.x, pin.x), maxf(tee.z, pin.z)) + Vector2.ONE * MARGIN
	var out := []
	var z := lo.y
	while z <= hi.y:
		var x := lo.x
		while x <= hi.x:
			var p := Vector3(x + rng.randf_range(-1.2, 1.2), 0.0, z + rng.randf_range(-1.2, 1.2))
			var roll := rng.randf()
			x += STEP
			if _distance_to_segment(Vector2(p.x, p.z), Vector2(tee.x, tee.z), Vector2(pin.x, pin.z)) > MARGIN:
				continue
			var s := t.surface_at(p.x, p.z)
			if s != Surface.Type.DEEP_ROUGH and s != Surface.Type.OUT_OF_BOUNDS and s != Surface.Type.ROUGH:
				continue
			var play := _near_play(t, p, CLEAR)
			if play:
				continue
			if _near_surface(t, p, Surface.Type.WATER, 2.5):
				if roll < BANK_CHANCE * density:
					out.append([p, style["bank"]])
				continue
			if s == Surface.Type.ROUGH:
				continue
			var more: float = style["more"]
			if roll < OUTCROP_CHANCE * density * more and not _near_play(t, p, 25.0):
				out.append([p, style["outcrop"]])
			elif roll < ROUGH_CHANCE * density * more:
				# Dunes and heath on any course get the shore's stone.
				var cover := t.cover_at(p.x, p.z)
				out.append([p, STYLES[FreeAmbience.Setting.SEASIDE]["rough"] if cover == "dune" else style["rough"]])
		z += STEP
	return out


## Whether a group's smaller rock would land in play or in water.
static func t_blocked(t: CourseTerrain, p: Vector3) -> bool:
	var s := t.surface_at(p.x, p.z)
	return s == Surface.Type.WATER or _near_play(t, p, CLEAR - 2.0)


static func _near_play(t: CourseTerrain, p: Vector3, r: float) -> bool:
	for a in 8:
		var q := p + Vector3(cos(a * TAU / 8.0), 0.0, sin(a * TAU / 8.0)) * r
		var s := t.surface_at(q.x, q.z)
		if s == Surface.Type.TEE or s == Surface.Type.FAIRWAY or s == Surface.Type.FRINGE \
				or s == Surface.Type.GREEN or s == Surface.Type.SAND:
			return true
	return false


static func _near_surface(t: CourseTerrain, p: Vector3, want: int, r: float) -> bool:
	for a in 6:
		var q := p + Vector3(cos(a * TAU / 6.0), 0.0, sin(a * TAU / 6.0)) * r
		if t.surface_at(q.x, q.z) == want:
			return true
	return false


static func _distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var u := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return p.distance_to(a + ab * u)
