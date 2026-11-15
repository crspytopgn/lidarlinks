class_name MegascansDebris
extends RefCounted
## The woodland-floor debris in the private Megascans pack
## (docs/megascans-pack.md), listed in debris/debris.json by
## tools/megascans/debris_pack.py: two litter atlases (leaves, needles) and
## scanned props (leaf piles, fallen pine branches, twigs, cones, logs,
## stumps), each with the trees it lies under. DebrisField places them.
## Empty without a pack, and always on the web.

const MANIFEST := "debris/debris.json"
const KINDS := ["leaves", "pine_branches", "twigs", "cones", "log", "stump"]
const UNDER := ["broadleaf", "conifer", "any"]

static var _data := {}
static var _loaded := false
static var _meshes := {}  ## mesh file -> ArrayMesh (or null when unreadable)


## {"litter": {kind: {"albedo", "normal", "size_m"}}, "props": [prop]}; each
## prop is {"uid", "title", "kind", "under", "mesh", "albedo", "normal", "cutout"}.
static func pack() -> Dictionary:
	if not _loaded:
		_loaded = true
		var dir := FreeAssets.megascans_dir()
		if not dir.is_empty() and FileAccess.file_exists(dir + MANIFEST):
			_data = parse(FileAccess.get_file_as_string(dir + MANIFEST))
		else:
			_data = parse("")
	return _data


## The pack in a debris.json text; bad entries are skipped.
static func parse(text: String) -> Dictionary:
	var out := {"litter": {}, "props": [] as Array[Dictionary]}
	var data: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if not data is Dictionary:
		return out
	var litter: Variant = data.get("litter", {})
	if litter is Dictionary:
		for kind: Variant in litter:
			var l: Variant = litter[kind]
			if (kind == "leaves" or kind == "needles") and l is Dictionary and not str(l.get("albedo", "")).is_empty():
				out["litter"][kind] = {"albedo": str(l["albedo"]), "normal": str(l.get("normal", "")),
					"size_m": clampf(float(l.get("size_m", 2.5)), 0.5, 8.0)}
	var props: Array[Dictionary] = out["props"]
	var list: Variant = data.get("props", [])
	for p: Variant in list if list is Array else []:
		if not p is Dictionary or not KINDS.has(str(p.get("kind", ""))) or str(p.get("mesh", "")).is_empty() or str(p.get("albedo", "")).is_empty():
			continue
		var under := str(p.get("under", "any"))
		props.append({"uid": str(p.get("uid", p["mesh"])), "title": str(p.get("title", "")), "kind": str(p["kind"]),
			"under": under if UNDER.has(under) else "any", "mesh": str(p["mesh"]), "albedo": str(p["albedo"]),
			"normal": str(p.get("normal", "")), "cutout": bool(p.get("cutout", false))})
	return out


## The props of `kind` that lie under a conifer (or broadleaf) tree.
static func props_for(kind: String, conifer: bool, from: Array = pack()["props"]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in from:
		if p["kind"] == kind and (p["under"] == "any" or (p["under"] == "conifer") == conifer):
			out.append(p)
	return out


## A prop's mesh (metres, standing on y = 0), or null when it can't be read.
static func mesh(prop: Dictionary) -> ArrayMesh:
	var file: String = prop["mesh"]
	if _meshes.has(file):
		return _meshes[file]
	var m: ArrayMesh = null
	var dir := FreeAssets.megascans_dir()
	if not dir.is_empty() and FileAccess.file_exists(dir + file):
		var f := FileAccess.open(dir + file, FileAccess.READ)
		var d: Variant = f.get_var() if f != null else null
		if d is Dictionary:
			m = build_mesh(d)
	_meshes[file] = m
	return m


## An ArrayMesh from an .olmesh Dictionary (tools/megascans/debris_meshes.gd).
static func build_mesh(d: Dictionary) -> ArrayMesh:
	var pos: Variant = d.get("pos")
	var idx: Variant = d.get("idx")
	if not pos is PackedVector3Array or not idx is PackedInt32Array or (pos as PackedVector3Array).is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = d.get("nrm")
	arrays[Mesh.ARRAY_TANGENT] = d.get("tan")
	arrays[Mesh.ARRAY_TEX_UV] = d.get("uv")
	arrays[Mesh.ARRAY_INDEX] = idx
	var n: int = (pos as PackedVector3Array).size()
	for k in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV]:
		var a: Variant = arrays[k]
		if a == null or a.size() != n:
			return null
	var tan: Variant = arrays[Mesh.ARRAY_TANGENT]
	if not tan is PackedFloat32Array or (tan as PackedFloat32Array).size() != n * 4:
		arrays[Mesh.ARRAY_TANGENT] = null
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


static func texture(file: String) -> Texture2D:
	return FreeAssets.megascans_pack_texture(file, file.ends_with("_n.jpg"))
