class_name MegascansPlants
extends RefCounted
## The real 3D plants of the private Megascans pack (docs/megascans-pack.md):
## ferns, wild grasses, wildflowers and reeds, cut down for the game by
## tools/megascans/plant_meshes.py into foliage/plants/<uid>.olplant (up
## to four variants, each a near and a mid level of detail) with their
## colour and normal maps, and listed in foliage/plants.json. ScannedPlants
## grows them round the tees and greens. Empty without a pack, and always
## on the web.

const MANIFEST := "foliage/plants.json"
const SHADER := preload("res://shaders/scanned_plant.gdshader")
## The scans are shot at very different exposures (mean linear luminance of
## the leaves from 0.006 for a shaded fern to 0.3 for dry marram): each is
## brought towards this, a sunlit meadow plant's, within GAIN.
const TARGET_LUMA := 0.07
const GAIN := Vector2(0.6, 5.0)
## A plant's group, from words in its title (first match wins): what the
## dresser picks by (ScannedPlants.FLORA).
const GROUPS := [
	["fern", "fern"],
	["reed", "wet"], ["rush", "wet"], ["cotton", "wet"], ["sedge", "wet"],
	["marram", "dune"], ["xeric", "dune"],
	["poppy", "flower"], ["nettle", "flower"], ["dandelion", "flower"], ["clover", "flower"], ["buttercup", "flower"],
	["grass", "grass"],
]

## Widest a plant's textures are loaded (the pack bakes 2048): 1024 is
## plenty for a knee-high plant a few metres off and keeps a dozen plants
## to about 70 MB of video memory.
static var texture_size := 1024
static var _plants: Array[Dictionary] = []
static var _loaded := false
static var _meshes := {}  ## uid -> Array (per variant) of [near, mid] ArrayMesh, or null


## Every plant: {"uid", "title", "kind", "group", "height_m", "roles", "variants", "file"}.
static func plants() -> Array[Dictionary]:
	if not _loaded:
		_loaded = true
		var dir := FreeAssets.megascans_dir()
		if not dir.is_empty() and FileAccess.file_exists(dir + MANIFEST):
			_plants = parse(FileAccess.get_file_as_string(dir + MANIFEST))
	return _plants


## The plants in a plants.json text; bad entries are skipped.
static func parse(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var data: Variant = JSON.parse_string(text)
	var list: Array = data.get("plants", []) if data is Dictionary else []
	for p: Variant in list:
		if not p is Dictionary or str(p.get("file", "")).is_empty() or int(p.get("variants", 0)) < 1:
			continue
		var title := str(p.get("title", ""))
		out.append({"uid": str(p.get("uid", "")), "title": title, "kind": str(p.get("kind", "grass")),
			"group": group_of(title), "height_m": clampf(float(p.get("height_m", 0.6)), 0.05, 4.0),
			"roles": PackedStringArray(p.get("roles", [])), "variants": int(p["variants"]),
			"file": str(p["file"]), "normal": bool(p.get("normal", true)),
			"luma": clampf(float(p.get("luma", TARGET_LUMA)), 0.002, 1.0)})
	return out


## A plant's group by its title: fern, wet, dune, flower or grass.
static func group_of(title: String) -> String:
	var t := title.to_lower()
	for g: Array in GROUPS:
		if t.contains(g[0]):
			return g[1]
	return "grass"


static func for_group(group: String, from: Array[Dictionary] = plants()) -> Array[Dictionary]:
	return from.filter(func(p: Dictionary) -> bool: return p["group"] == group)


## The plant's meshes, per variant [near, mid], each with the plant's
## material for that band; [] when its files can't be read.
static func meshes(plant: Dictionary) -> Array:
	var uid: String = plant["uid"]
	if _meshes.has(uid):
		return _meshes[uid]
	var out := []
	var dir := FreeAssets.megascans_dir()
	var albedo := FreeAssets.megascans_texture(str(plant["file"]) + "_albedo.png", "foliage/", false, texture_size)
	var normal := FreeAssets.megascans_texture(str(plant["file"]) + "_normal.png", "foliage/", true, texture_size) if plant.get("normal", true) else null
	var levels := read(dir + "foliage/" + str(plant["file"]) + ".olplant") if not dir.is_empty() else []
	if albedo != null and not levels.is_empty():
		var mats := [material(albedo, normal, float(plant["height_m"]), 0), material(albedo, normal, float(plant["height_m"]), 1)]
		for m: ShaderMaterial in mats:
			m.set_shader_parameter("gain", gain(float(plant.get("luma", TARGET_LUMA))))
		for variant: Array in levels:
			var pair := []
			for band in 2:
				var mesh: ArrayMesh = variant[mini(band, variant.size() - 1)].duplicate()
				mesh.surface_set_material(0, mats[band])
				pair.append(mesh)
			out.append(pair)
	_meshes[uid] = out
	return out


## How much a plant's colour is scaled for its scan's mean luminance.
static func gain(luma: float) -> float:
	return clampf(TARGET_LUMA / maxf(luma, 0.001), GAIN.x, GAIN.y)


static func material(albedo: Texture2D, normal: Texture2D, height: float, band: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("albedo_tex", albedo)
	m.set_shader_parameter("normal_tex", normal)
	m.set_shader_parameter("has_normal", normal != null)
	m.set_shader_parameter("plant_height", height)
	m.set_shader_parameter("band", band)
	# Compatibility has no sky fill: lift the plants as the cards are.
	m.set_shader_parameter("brightness", 1.0)
	m.set_shader_parameter("translucency", 0.55 if GraphicsSettings.is_forward_plus() else 0.3)
	return m


## The meshes of an .olplant file: per variant, its levels of detail as
## ArrayMeshes (no material), or [] when it can't be read.
static func read(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 12 or f.get_buffer(8).get_string_from_ascii() != "OLPLANT1":
		return []
	var size := f.get_32()
	var d := f.get_buffer(f.get_length() - f.get_position()).decompress(size, FileAccess.COMPRESSION_DEFLATE)
	if d.size() != size:
		return []
	return decode(d)


## The variants in an .olplant's (inflated) data.
static func decode(d: PackedByteArray) -> Array:
	var out := []
	var o := 0
	var nv := d.decode_u32(o)
	o += 4
	for v in nv:
		var nl := d.decode_u32(o)
		o += 4
		var levels: Array[ArrayMesh] = []
		for l in nl:
			var n := d.decode_u32(o)
			var ni := d.decode_u32(o + 4)
			o += 8
			if o + n * 32 + ni * 4 > d.size():
				return []
			var fl := d.slice(o, o + n * 32).to_float32_array()
			o += n * 32
			var idx := d.slice(o, o + ni * 4).to_int32_array()
			o += ni * 4
			levels.append(_mesh(fl, idx))
		out.append(levels)
	return out


static func _mesh(fl: PackedFloat32Array, idx: PackedInt32Array) -> ArrayMesh:
	@warning_ignore("integer_division")
	var n := fl.size() / 8
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var uv := PackedVector2Array()
	pos.resize(n)
	nor.resize(n)
	uv.resize(n)
	for i in n:
		var b := i * 8
		pos[i] = Vector3(fl[b], fl[b + 1], fl[b + 2])
		nor[i] = Vector3(fl[b + 3], fl[b + 4], fl[b + 5])
		uv[i] = Vector2(fl[b + 6], fl[b + 7])
	# The baker writes counter-clockwise triangles; Godot's front faces
	# wind clockwise.
	for t in range(0, idx.size() - 2, 3):
		var k := idx[t + 1]
		idx[t + 1] = idx[t + 2]
		idx[t + 2] = k
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = nor
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.generate_tangents()
	return st.commit()
