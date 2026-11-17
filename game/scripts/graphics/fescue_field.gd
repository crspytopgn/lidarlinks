class_name FescueField
extends Node3D
## Tall fescue on the course's deep rough, out to a long way from the
## camera. Out of play a course lets its slopes grow long: fine grey-green
## grass 40 to 75 cm tall, some of it straw, with pale seed heads above. Without it the
## built-in course's hills read as green felt from the tee (most of a hole's
## ground is deep rough). Each tuft is three crossed cards from the fescue
## atlas (FreeAssets "fescue.png", tools/grass/fescue_atlas.py), in 32 m
## chunks built a couple per frame as the camera moves, like GrassField's
## near tufts, which it takes over from past about 20 m so a ball in the
## rough near the camera is never hidden. Visual only. Off without the atlas
## or with the Grass setting off; reach and density follow that setting.
##
## Under and around each tree crown it also grows an understory: taller,
## denser and darker brush on the rough there, so a wood's edge reads as a
## wall of undergrowth (as on GSPro's community courses and real parkland)
## rather than a picket line of bare trunks on a mown lawn.

const SHADER := preload("res://shaders/fescue.gdshader")
const CHUNK := 32.0
const BUILDS_PER_FRAME := 2
## Per Grass level (Off, Low, Medium, High): tufts per square metre of deep
## rough, and how far out they grow.
const DENSITY := [0.0, 0.4, 0.6, 0.8]
const RADIUS := [0.0, 90.0, 140.0, 180.0]
const SURFACES := [Surface.Type.DEEP_ROUGH]
## Understory, per Grass level: tufts per square metre of a crown's
## footprint. It grows on the deep rough out to UNDER_REACH_DEEP crown radii
## from the trunk, and on the plain rough only under the crown itself.
const UNDER_DENSITY := [0.0, 0.5, 0.8, 1.1]
const UNDER_REACH_DEEP := 1.3
const UNDER_REACH_ROUGH := 0.9
## Scanned plant cards (MegascansCards, private pack, desktop only): a
## stand of one plant is about this many metres across, a meadow flower
## turns up in this share of a golden drift, the cards' own colour against
## the ground's (shaders/fescue.gdshader ground_pull), and the cards left
## out because they read badly or don't belong on a temperate course.
const STAND_M := 6.0
const FLOWER_SHARE := 0.07
const CARD_GROUND_PULL := 0.6
const CARD_SKIP := ["Boston Fern", "Grass Clumps", "Kikuyu Grass", "Red Fountain Grass", "Basket Grass", "Ribbon Grass", "Rubber Bush", "Giant Reed", "Dead Shrubs"]
## Crowns smaller than this (bushes) get none: a bush is its own brush.
const UNDER_MIN_RADIUS := 1.5
## Understory tufts: height range (m), width against height, and how much
## darker than the open rough (shade under the crown).
const UNDER_HEIGHT := Vector2(1.1, 2.1)
const UNDER_WIDTH := Vector2(1.8, 2.6)
const UNDER_SHADE := 0.72
## Native grass: golden drifts on the deep rough. The noise's feature size
## (m), the noise level a drift starts at (shaders/terrain.gdshader
## native_at mirrors these) and the width of its soft edge,
## how much denser than plain fescue a drift grows, its tufts' height range
## and their colours (sRGB, picked per tuft).
const NATIVE_SCALE := 70.0
const NATIVE_FROM := 0.5
const NATIVE_EDGE := 0.12
## Banks and mound sides grow long and go to seed first (a course mows the
## flat): how much the slope (1 - normal y) adds to the drift noise.
const NATIVE_SLOPE := 1.6
const NATIVE_DENSITY := 2.4
const NATIVE_HEIGHT := Vector2(0.6, 1.1)
const NATIVE_STRAW := Color(0.64, 0.56, 0.4)
const NATIVE_GOLD := Color(0.58, 0.51, 0.34)
const NATIVE_RUSSET := Color(0.55, 0.44, 0.32)
## Reeds round ponds: tufts on the bank within REED_REACH m of the water,
## per square metre against the fescue's density, their heights and green.
const REED_DENSITY := 2.5
const REED_REACH := 2.5
const REED_HEIGHT := Vector2(1.1, 1.9)
const REED_COLOUR := Color(0.42, 0.5, 0.26)
## Meadow plants (the drawn meadow atlas, tools/grass/meadow_atlas.py,
## public): broad-leaved rosettes, daisies, buttercups and yarrow among
## the long grass, as in real rough and the Godot forest scenes Michael
## pointed to (2026-11-17), so a hillside reads as living ground rather
## than one even fur. Plants per square metre of deep rough per
## the Grass level (Off, Low, Medium, High) out to MEADOW_RADIUS m from
## the camera, in MEADOW_CHUNK m chunks, in patches MEADOW_SCALE m across (more where the
## noise is high), their card height range (m; the plants fill the lower
## part of the card), how much they take the ground's colour, and the
## share of each atlas cell (daisies, buttercups, rosette, yarrow).
const MEADOW_UID := "_meadow"
const MEADOW_DENSITY := [0.0, 0.5, 0.9, 1.3]
const MEADOW_RADIUS := [0.0, 45.0, 65.0, 85.0]
const MEADOW_CHUNK := 16.0
const MEADOW_SCALE := 18.0
const MEADOW_HEIGHT := Vector2(0.55, 0.95)
const MEADOW_GROUND_PULL := 0.3
const MEADOW_CELLS := [0.25, 0.17, 0.36, 0.22]
## Where meadow plants start to grow in from the camera (m): nearer than the
## fescue (shaders/fescue.gdshader near_start, near_end).
const MEADOW_NEAR := Vector2(5.0, 14.0)
## Sward: a low carpet of drawn grass cards (tools/grass/sward_atlas.py,
## a couple of hundred fine blades a card) on the deep rough right
## round the camera, under GrassField's 3D blades. Those are a dozen a tuft,
## so on their own the near rough read as sparse dark spikes on the ground
## texture; real rough close up is a mat where you see grass, not soil. Per
## Grass level: cards per square metre and the ring's radius (m), in
## SWARD_CHUNK m chunks; card heights (m), and how much a card takes the
## ground's colour. Not on the plain rough: from the player's height, short
## crossed cards there read as green stars on the ground.
const SWARD_UID := "_sward"
const SWARD_DENSITY := [0.0, 5.0, 8.0, 11.0]
const SWARD_RADIUS := [0.0, 12.0, 18.0, 24.0]
const SWARD_CHUNK := 8.0
const SWARD_HEIGHT := Vector2(0.17, 0.36)
const SWARD_GROUND_PULL := 0.9
const SWARD_GROUND_PULL_FORWARD := 0.6
## The sward's colour cast on Forward+ (shaders/fescue.gdshader warmth):
## cooler than the fescue's dry warm cast, as fresh grass is.
const SWARD_FORWARD_WARMTH := Vector3(0.97, 1.02, 0.95)
const SWARD_COMPAT_BRIGHTNESS := 0.95
## The ground normal's x and z, times this and the tuft's height, are the
## card's up axis x and z (see build_chunk and shaders/fescue.gdshader).
const NORMAL_LEAN := 0.01
## A far tuft's brightness against a near one's (shaders/fescue.gdshader
## far_gain), per renderer.
const FAR_GAIN_COMPAT := 1.2
const FAR_GAIN_FORWARD_PLUS := 0.7

var terrain: CourseTerrain
var level := 0
var _chunks := {}  ## Vector2i -> Node3D of MultiMeshInstance3Ds (null for an empty chunk)
var _crowns := {}  ## Vector2i chunk -> PackedVector3Array of crowns centred in it
var _meadow := {}  ## Vector2i meadow chunk -> MultiMeshInstance3D (null for an empty chunk)
var _sward := {}  ## Vector2i sward chunk -> MultiMeshInstance3D (null for an empty chunk)

static var _mesh: ArrayMesh
static var _mat: ShaderMaterial
static var _buf := PackedFloat32Array()  ## the chunk build_chunk is filling
static var _card_bufs := {}  ## card uid -> Array of floats, the chunk's tufts drawn from that card
static var _card_mats := {}  ## card uid -> ShaderMaterial
static var _card_meshes := {}  ## card uid -> ArrayMesh
## The private pack's plant cards by dresser role ({} without a pack); see
## dress_cards().
static var dress := {}


func _init() -> void:
	name = "Fescue"


## True when the fescue atlas is there to draw with.
static func available() -> bool:
	return FreeAssets.tree_texture("fescue.png") != null


func setup(t: CourseTerrain, grass_level: int) -> void:
	terrain = t
	level = clampi(grass_level, 0, DENSITY.size() - 1) if available() else 0
	for node in _chunks.values():
		if node != null:
			node.queue_free()
	_chunks.clear()
	for ring: Dictionary in [_meadow, _sward]:
		for node in ring.values():
			if node != null:
				node.queue_free()
		ring.clear()
	_crowns = crowns_by_chunk(t.obstacles if t != null else null)
	dress = dress_cards(MegascansCards.cards())
	var r: float = RADIUS[level]
	material().set_shader_parameter("far_start", r * 0.7)
	material().set_shader_parameter("far_end", r)


func update_around(eye: Vector3) -> void:
	if terrain == null or level == 0:
		return
	material().set_shader_parameter("camera_pos", eye)
	for m: ShaderMaterial in _card_mats.values():
		m.set_shader_parameter("camera_pos", eye)
	var r: float = RADIUS[level]
	var here := Vector2(eye.x, eye.z)
	for key: Vector2i in _chunks.keys():
		if _centre(key).distance_to(here) > r + CHUNK:
			var node: Node = _chunks[key]
			if node != null:
				node.queue_free()
			_chunks.erase(key)
	var wanted: Array[Vector2i] = []
	var reach := ceili(r / CHUNK)
	var at := Vector2i(floori(eye.x / CHUNK), floori(eye.z / CHUNK))
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var key := at + Vector2i(dx, dz)
			if not _chunks.has(key) and _centre(key).distance_to(here) < r + CHUNK * 0.71:
				wanted.append(key)
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _centre(a).distance_squared_to(here) < _centre(b).distance_squared_to(here))
	for i in mini(BUILDS_PER_FRAME, wanted.size()):
		var key := wanted[i]
		var meshes := build_chunk(terrain, key, DENSITY[level], _crowns.get(key, PackedVector3Array()), UNDER_DENSITY[level], dress)
		var node: Node3D = null
		if not meshes.is_empty():
			node = Node3D.new()
			for mm in meshes:
				var inst := MultiMeshInstance3D.new()
				inst.multimesh = mm
				inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				node.add_child(inst)
			add_child(node)
		_chunks[key] = node
	_update_meadow(here)


## The meadow plants' and the sward's chunks round the camera at `here`
## (x, z): each ring's chunks dropped past its radius, built nearest
## first, a couple a frame.
func _update_meadow(here: Vector2) -> void:
	if meadow_available():
		_update_ring(_meadow, MEADOW_UID, MEADOW_CHUNK, MEADOW_RADIUS[level], here,
			func(key: Vector2i) -> MultiMesh: return build_meadow_chunk(terrain, key, MEADOW_DENSITY[level]))
	if sward_available():
		_update_ring(_sward, SWARD_UID, SWARD_CHUNK, SWARD_RADIUS[level], here,
			func(key: Vector2i) -> MultiMesh: return build_sward_chunk(terrain, key, SWARD_DENSITY[level]))


func _update_ring(ring: Dictionary, uid: String, size: float, r: float, here: Vector2, build: Callable) -> void:
	if r <= 0.0:
		return
	for key: Vector2i in ring.keys():
		if ((Vector2(key) + Vector2(0.5, 0.5)) * size).distance_to(here) > r + size:
			var node: Node = ring[key]
			if node != null:
				node.queue_free()
			ring.erase(key)
	var wanted: Array[Vector2i] = []
	var reach := ceili(r / size)
	var at := Vector2i(floori(here.x / size), floori(here.y / size))
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var key := at + Vector2i(dx, dz)
			if not ring.has(key) and ((Vector2(key) + Vector2(0.5, 0.5)) * size).distance_to(here) < r + size * 0.71:
				wanted.append(key)
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (Vector2(a) * size).distance_squared_to(here) < (Vector2(b) * size).distance_squared_to(here))
	if _card_mats.has(uid):
		# The cards sink away towards the edge of their ring.
		var m: ShaderMaterial = _card_mats[uid]
		m.set_shader_parameter("far_start", r * 0.6)
		m.set_shader_parameter("far_end", r)
	for i in mini(BUILDS_PER_FRAME, wanted.size()):
		var mm: MultiMesh = build.call(wanted[i])
		var inst: MultiMeshInstance3D = null
		if mm != null:
			inst = MultiMeshInstance3D.new()
			inst.multimesh = mm
			inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(inst)
		ring[wanted[i]] = inst


## Sward cards for one SWARD_CHUNK square: an even carpet on the deep
## rough; null where none grow.
static func build_sward_chunk(t: CourseTerrain, key: Vector2i, density: float) -> MultiMesh:
	var biome := Biome.of(t)
	if Biome.wild_grass(biome) <= 0.0 or not sward_available():
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) + 9137
	_card_bufs = {}
	# One card per grid cell, but jittered across two cells: a tight grid
	# lined up into faint rows across the slope from the player's height,
	# and pure random scatter left bare patches between clumps.
	var side := maxi(1, roundi(SWARD_CHUNK * sqrt(density)))
	var cell := SWARD_CHUNK / side
	var origin := Vector2(key) * SWARD_CHUNK
	for i in side * side:
		var x := origin.x + (i % side + rng.randf_range(-0.5, 1.5)) * cell
		var z := origin.y + (floorf(float(i) / side) + rng.randf_range(-0.5, 1.5)) * cell
		var yaw := rng.randf() * TAU
		var size := rng.randf()
		var pick := rng.randf()
		var surface := t.surface_at(x, z)
		if surface != Surface.Type.DEEP_ROUGH or Biome.is_bare(biome, surface):
			continue
		var h := lerpf(SWARD_HEIGHT.x, SWARD_HEIGHT.y, size)
		var c := t.ground_color_at(x, z)
		var native := native_at(x, z, t.normal_at(x, z).y)
		if native > 0.0:
			c = c.lerp(native_colour(pick), native * GrassField.NATIVE_BLEND)
		# Wider than tall: a patch of sward, not a tuft.
		_put(t, x, z, yaw, h * rng.randf_range(2.0, 2.9), h, c, pick, -0.01, SWARD_UID)
	var rows: Array = _card_bufs.get(SWARD_UID, [])
	_card_bufs = {}
	if rows.is_empty():
		return null
	var mesh := _card_mesh(SWARD_UID, {})
	return _multimesh(PackedFloat32Array(rows), mesh) if mesh != null else null


## Meadow plants for one MEADOW_CHUNK square: on the deep rough, in soft
## patches; null where none grow (or the biome has no wild grass).
static func build_meadow_chunk(t: CourseTerrain, key: Vector2i, density: float) -> MultiMesh:
	var wild := Biome.wild_grass(Biome.of(t))
	if wild <= 0.0 or not meadow_available():
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) + 4211
	_buf = PackedFloat32Array()
	_card_bufs = {}
	var origin := Vector2(key) * MEADOW_CHUNK
	for i in roundi(MEADOW_CHUNK * MEADOW_CHUNK * density * wild):
		var x := origin.x + rng.randf() * MEADOW_CHUNK
		var z := origin.y + rng.randf() * MEADOW_CHUNK
		var yaw := rng.randf() * TAU
		var keep := rng.randf()
		var which := rng.randf()
		var phase := rng.randf()
		var h := rng.randf_range(MEADOW_HEIGHT.x, MEADOW_HEIGHT.y)
		if t.surface_at(x, z) != Surface.Type.DEEP_ROUGH:
			continue
		var patch := _value_noise(Vector2(x + 911.0, z - 377.0) / MEADOW_SCALE)
		if keep > smoothstep(0.2, 0.65, patch):
			continue
		_put(t, x, z, yaw, h * rng.randf_range(0.9, 1.2), h, t.ground_color_at(x, z), meadow_pick(which, phase), -0.02, MEADOW_UID)
	var rows: Array = _card_bufs.get(MEADOW_UID, [])
	_card_bufs = {}
	if rows.is_empty():
		return null
	var mesh := _card_mesh(MEADOW_UID, {})
	return _multimesh(PackedFloat32Array(rows), mesh) if mesh != null else null


func chunk_count() -> int:
	return _chunks.size()


static func _centre(key: Vector2i) -> Vector2:
	return (Vector2(key) + Vector2(0.5, 0.5)) * CHUNK


## The tree crowns of `field` big enough for an understory, bucketed by the
## chunk their trunk stands in.
static func crowns_by_chunk(field: ObstacleField) -> Dictionary:
	var out := {}
	if field == null:
		return out
	for c: Vector3 in field.canopies():
		if c.z < UNDER_MIN_RADIUS:
			continue
		var key := Vector2i(floori(c.x / CHUNK), floori(c.y / CHUNK))
		if not out.has(key):
			out[key] = PackedVector3Array()
		var list: PackedVector3Array = out[key]
		list.append(c)
		out[key] = list
	return out


## The tufts of one chunk, or null with no deep rough or understory in it:
## fescue on its deep rough (in golden drifts of native grass where
## native_at() says so), reeds round its ponds, then brush under the
## `crowns` (x, z, radius) whose trunks stand in it. With `cards` (from
## dress_cards) the drifts, reeds, brush and mapped cover grow scanned
## plants, a stand of one kind every few metres. Deterministic. One
## MultiMesh per atlas used (the fescue's first, if any).
static func build_chunk(t: CourseTerrain, key: Vector2i, density: float, crowns := PackedVector3Array(), under_density := 0.0, cards := {}) -> Array[MultiMesh]:
	# Sparse bunch grass and scrub in the desert, none through snow (Biome).
	var biome := Biome.of(t)
	var wild := Biome.wild_grass(biome)
	if wild <= 0.0:
		var none: Array[MultiMesh] = []
		return none
	density *= wild
	under_density *= wild
	var tint: Color = Biome.WILD_TINT.get(biome, Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) + 77
	_buf = PackedFloat32Array()
	_card_bufs = {}
	var origin := Vector2(key) * CHUNK
	# Fescue, thicker and taller in the native drifts (the extra tries only
	# land where native_at is high).
	var tries := roundi(CHUNK * CHUNK * density * NATIVE_DENSITY)
	for i in tries:
		var x := origin.x + rng.randf() * CHUNK
		var z := origin.y + rng.randf() * CHUNK
		var yaw := rng.randf() * TAU
		var keep := rng.randf()
		var pick := rng.randf()
		var tone := rng.randf()
		var grow := rng.randf()
		if not SURFACES.has(t.surface_at(x, z)):
			continue
		var native := native_at(x, z, t.normal_at(x, z).y)
		if keep * NATIVE_DENSITY > 1.0 + (NATIVE_DENSITY - 1.0) * native:
			continue
		var h := lerpf(rng.randf_range(0.4, 0.75), lerpf(NATIVE_HEIGHT.x, NATIVE_HEIGHT.y, grow), native)
		var c := t.ground_color_at(x, z)
		if tint.a > 0.0:
			c = tint.lerp(native_colour(tone), 0.08)
		elif native > 0.0:
			c = c.lerp(native_colour(tone), native)
		if not cards.is_empty():
			var cover := t.cover_at(x, z)
			var role := ""
			if not cover.is_empty():
				role = "cover:" + cover
			elif native > 0.5:
				role = "flower" if grow < FLOWER_SHARE else "links_fescue"
			var card := card_for(cards, role, x, z)
			if not card.is_empty():
				var ch: float = card["height_m"] * rng.randf_range(0.8, 1.2)
				_put(t, x, z, yaw, ch * rng.randf_range(1.0, 1.3), ch, c, pick, -0.03, card["uid"])
				continue
		_put(t, x, z, yaw, h * lerpf(rng.randf_range(1.0, 1.3), rng.randf_range(1.6, 2.2), native), h, c, pick, -0.03)
	# Reeds: tall tufts on the bank, the ground just short of the water.
	for i in roundi(CHUNK * CHUNK * density * REED_DENSITY):
		var x := origin.x + rng.randf() * CHUNK
		var z := origin.y + rng.randf() * CHUNK
		var yaw := rng.randf() * TAU
		var h := rng.randf_range(REED_HEIGHT.x, REED_HEIGHT.y)
		var pick := rng.randf()
		var tone := rng.randf()
		var s := t.surface_at(x, z)
		if s == Surface.Type.WATER or s == Surface.Type.GREEN or s == Surface.Type.TEE or s == Surface.Type.FAIRWAY or s == Surface.Type.SAND:
			continue
		var wet := false
		for k in 6:
			var a := k * TAU / 6.0
			if t.surface_at(x + cos(a) * REED_REACH, z + sin(a) * REED_REACH) == Surface.Type.WATER:
				wet = true
				break
		if not wet:
			continue
		var reed := card_for(cards, "water_edge", x, z)
		if not reed.is_empty():
			h = reed["height_m"] * rng.randf_range(0.8, 1.2)
		_put(t, x, z, yaw, h * rng.randf_range(0.7, 1.0), h, REED_COLOUR.lerp(native_colour(tone), 0.35), pick, -0.05, reed.get("uid", ""))
	for crown in crowns:
		var reach := crown.z * UNDER_REACH_DEEP
		var count := roundi(PI * reach * reach * under_density)
		for i in count:
			# Uniform over the disc out to `reach`.
			var d := sqrt(rng.randf()) * reach
			var ang := rng.randf() * TAU
			var x := crown.x + cos(ang) * d
			var z := crown.y + sin(ang) * d
			var yaw := rng.randf() * TAU
			var h := rng.randf_range(UNDER_HEIGHT.x, UNDER_HEIGHT.y)
			var w := h * rng.randf_range(UNDER_WIDTH.x, UNDER_WIDTH.y)
			var pick := rng.randf()
			var s := t.surface_at(x, z)
			if not (s == Surface.Type.DEEP_ROUGH or (s == Surface.Type.ROUGH and d < crown.z * UNDER_REACH_ROUGH)):
				continue
			var brush := card_for(cards, "woodland_edge", x, z)
			if not brush.is_empty():
				h = brush["height_m"] * rng.randf_range(1.0, 1.6)
				w = h * rng.randf_range(1.0, 1.4)
			_put(t, x, z, yaw, w, h, t.ground_color_at(x, z) * UNDER_SHADE, pick, -0.05, brush.get("uid", ""))
	var out: Array[MultiMesh] = []
	if not _buf.is_empty():
		out.append(_multimesh(_buf, _shared_mesh()))
	for uid: String in _card_bufs:
		var mesh := _card_mesh(uid, cards)
		if mesh != null:
			out.append(_multimesh(PackedFloat32Array(_card_bufs[uid]), mesh))
	_buf = PackedFloat32Array()
	_card_bufs = {}
	return out


static func _multimesh(buffer: PackedFloat32Array, mesh: Mesh) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	@warning_ignore("integer_division")
	mm.instance_count = buffer.size() / 16
	mm.buffer = buffer
	mm.set_meta("buffer", buffer)
	return mm


## The pack's cards by dresser role: "links_fescue" (the golden drifts),
## "flower" (meadow flowers sprinkled in them), "water_edge" (reeds),
## "woodland_edge" (brush under crowns) and "cover:<cover>" for each mapped
## cover (CourseTerrain.cover_at). Each card is {"uid", "height_m", "card"}.
static func dress_cards(all: Array[Dictionary]) -> Dictionary:
	var ok := all.filter(func(c: Dictionary) -> bool: return not CARD_SKIP.has(c["title"]))
	var typed: Array[Dictionary] = []
	typed.assign(ok)
	var out := {}
	if typed.is_empty():
		return out
	out["links_fescue"] = MegascansCards.for_role("links_fescue", typed)
	out["flower"] = MegascansCards.for_role("meadow", MegascansCards.for_kind("flower", typed))
	out["water_edge"] = MegascansCards.for_role("water_edge", typed)
	out["woodland_edge"] = MegascansCards.for_role("woodland_edge", typed)
	for cover: String in MegascansCards.COVER_ROLES:
		out["cover:" + cover] = MegascansCards.for_cover(cover, typed)
	for k: String in out.keys():
		if (out[k] as Array).is_empty():
			out.erase(k)
	return out


## The card for `role` at (x, z): one plant per stand of about STAND_M, so
## kinds grow in patches as real ones do. {} when the role has none.
static func card_for(cards: Dictionary, role: String, x: float, z: float) -> Dictionary:
	var list: Array = cards.get(role, [])
	if list.is_empty():
		return {}
	var stand := Vector2i(floori(x / STAND_M), floori(z / STAND_M))
	return list[absi(hash([stand, role])) % list.size()]


## True when the drawn sward atlas is there.
static func sward_available() -> bool:
	return FreeAssets.tree_texture("sward.png") != null


## True when the drawn meadow atlas is there.
static func meadow_available() -> bool:
	return FreeAssets.tree_texture("meadow.png") != null


## The instance pick (shaders/fescue.gdshader: the atlas cell is
## floor(fract(pick * 4) * 4), the sway phase the pick itself) for a
## meadow plant: the cell chosen by `which` (0 to 1) by MEADOW_CELLS'
## shares, and `phase` (0 to 1) spreading the sway.
static func meadow_pick(which: float, phase: float) -> float:
	var cell := 0
	var acc := 0.0
	for k in MEADOW_CELLS.size():
		acc += MEADOW_CELLS[k]
		cell = k
		if which < acc:
			break
	return (floorf(phase * 4.0) + (cell + 0.5) / 4.0) / 4.0


static func _card_mesh(uid: String, cards: Dictionary) -> ArrayMesh:
	if _card_meshes.has(uid):
		return _card_meshes[uid]
	var tex: Texture2D = null
	if uid == MEADOW_UID:
		tex = FreeAssets.tree_texture("meadow.png")
	elif uid == SWARD_UID:
		tex = FreeAssets.tree_texture("sward.png")
	for list: Array in cards.values():
		for c: Dictionary in list:
			if c["uid"] == uid:
				tex = MegascansCards.atlas(c)
				break
		if tex != null:
			break
	var mesh: ArrayMesh = null
	if tex != null:
		var mat := material().duplicate() as ShaderMaterial
		mat.set_shader_parameter("atlas", tex)
		mat.set_shader_parameter("ground_pull", MEADOW_GROUND_PULL if uid == MEADOW_UID else CARD_GROUND_PULL)
		if uid == SWARD_UID:
			# Right up to the camera: it is the near rough.
			mat.set_shader_parameter("near_start", 0.0)
			mat.set_shader_parameter("near_end", 0.01)
			# Forward+ lights the turf texture olive, and a carpet pulled
			# that far towards it read olive too: keep more of the atlas's
			# fresh green there.
			mat.set_shader_parameter("ground_pull", SWARD_GROUND_PULL_FORWARD if GraphicsSettings.is_forward_plus() else SWARD_GROUND_PULL)
			if GraphicsSettings.is_forward_plus():
				mat.set_shader_parameter("warmth", SWARD_FORWARD_WARMTH)
			# Not the fescue's lift: a carpet this dense read acid lime.
			mat.set_shader_parameter("brightness", 1.0 if GraphicsSettings.is_forward_plus() else SWARD_COMPAT_BRIGHTNESS)
		if uid == MEADOW_UID:
			# Knee-high at most: they can come in nearer than the fescue.
			mat.set_shader_parameter("near_start", MEADOW_NEAR.x)
			mat.set_shader_parameter("near_end", MEADOW_NEAR.y)
		_card_mats[uid] = mat
		mesh = tuft_mesh()
		mesh.surface_set_material(0, mat)
	_card_meshes[uid] = mesh
	return mesh


## How much the deep rough at (x, z), where the ground's normal has y `up`,
## is a drift of golden native grass, 0 to 1: broad patches, more on banks, as a course lets its out-of-play ground grow and go
## to seed (the warm straw against green turf that makes GSPro's and real
## heathland courses look so good), with soft edges.
static func native_at(x: float, z: float, up := 1.0) -> float:
	var q := Vector2(x, z) / NATIVE_SCALE
	var v := 0.65 * _value_noise(q) + 0.35 * _value_noise(q * 2.03 + Vector2(17.1, 9.7)) + NATIVE_SLOPE * (1.0 - up)
	return smoothstep(NATIVE_FROM, NATIVE_FROM + NATIVE_EDGE, v)


## shaders/terrain.gdshader's hash and value_noise, so the ground under a
## drift and the drift's tufts agree.
static func _hash(p: Vector2) -> float:
	p = Vector2(p.x * 123.34, p.y * 456.21)
	p = p - p.floor()
	var d := p.dot(p + Vector2(45.32, 45.32))
	p += Vector2(d, d)
	var r := p.x * p.y
	return r - floorf(r)


static func _value_noise(p: Vector2) -> float:
	var i := p.floor()
	var f := p - i
	var u := f * f * (Vector2(3, 3) - 2.0 * f)
	var a := _hash(i)
	var b := _hash(i + Vector2(1, 0))
	var c := _hash(i + Vector2(0, 1))
	var d := _hash(i + Vector2(1, 1))
	return lerpf(lerpf(a, b, u.x), lerpf(c, d, u.x), u.y)


## A native tuft's colour (sRGB) for `tone` 0 to 1: straw, olive gold or
## russet, as long grass in seed is.
static func native_colour(tone: float) -> Color:
	if tone < 0.55:
		return NATIVE_STRAW.lerp(NATIVE_GOLD, tone / 0.55)
	return NATIVE_GOLD.lerp(NATIVE_RUSSET, (tone - 0.55) / 0.45)


## Adds one tuft (yaw, width `w`, height `h`, sRGB ground colour `c`,
## atlas pick, sunk `sink` m) at (x, z) to the chunk being built, drawn
## from the plant card `card` (a uid) or else the fescue atlas.
static func _put(t: CourseTerrain, x: float, z: float, yaw: float, w: float, h: float, c: Color, pick: float, sink: float, card := "") -> void:
	# The ground's slope rides along in the card's up axis as a tiny lean
	# (NORMAL_LEAN of the height, under a centimetre), so the shader can
	# light the tuft as the ground under it is lit.
	var up := t.normal_at(x, z)
	var cs := cos(yaw)
	var sn := sin(yaw)
	var row := [
		cs * w, 0.0, sn * w, x,
		up.x * NORMAL_LEAN * h, h, up.z * NORMAL_LEAN * h, t.height_at(x, z) + sink,
		-sn * w, 0.0, cs * w, z,
		c.r, c.g, c.b, pick,
	]
	if card.is_empty():
		_buf.append_array(PackedFloat32Array(row))
	else:
		if not _card_bufs.has(card):
			_card_bufs[card] = []
		(_card_bufs[card] as Array).append_array(row)


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = SHADER
		_mat.set_shader_parameter("atlas", FreeAssets.tree_texture("fescue.png"))
		# Compatibility has no sky fill: lift the cards as GrassField does.
		_mat.set_shader_parameter("brightness", 1.0 if GraphicsSettings.is_forward_plus() else 1.25)
		# Far tufts against their own near brightness, so a distant bank
		# matches the sunlit ground beside it (tuned on hole 2's hillside).
		_mat.set_shader_parameter("far_gain", FAR_GAIN_FORWARD_PLUS if GraphicsSettings.is_forward_plus() else FAR_GAIN_COMPAT)
	return _mat


static func _shared_mesh() -> ArrayMesh:
	if _mesh == null:
		_mesh = tuft_mesh()
		_mesh.surface_set_material(0, material())
	return _mesh


## Three cards 1 m wide and 1 m tall crossed at 60 degrees, standing on
## the origin; UV (0, 0) at the top left, as the atlas cells.
static func tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var a := float(k) / 3.0 * PI
		var side := Vector3(cos(a), 0.0, sin(a)) * 0.5
		var corners := [[-side, Vector2(0, 1)], [side, Vector2(1, 1)], [side + Vector3.UP, Vector2(1, 0)], [-side + Vector3.UP, Vector2(0, 0)]]
		for i: int in [0, 2, 1, 0, 3, 2]:
			st.set_normal(Vector3.UP)
			st.set_uv(corners[i][1])
			st.add_vertex(corners[i][0])
	return st.commit()
