extends SceneTree
## Second step of tools/megascans/debris_pack.py: reads each Megascans FBX in
## PACK/debris/mesh_jobs.json, cuts it down to about the job's triangle count
## (Godot's own LOD simplifier, which keeps UV seams), and writes it as
## PACK/debris/<id>.olmesh for DebrisField: a store_var Dictionary of packed
## arrays (pos, nrm, tan, uv, idx), metres, +y up, standing on y = 0 and
## centred on x, z (no taller than the job's max_h). A "split" job (Small Pine Cones: one cone per surface)
## lays its pieces out as a little scatter on the ground.
##
##     godot --headless --path game -s tools/megascans/debris_meshes.gd -- PACK_DIR


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- PACK_DIR")
		quit(1)
		return
	var pack := args[0].path_join("")
	var jobs: Variant = JSON.parse_string(FileAccess.get_file_as_string(pack + "debris/mesh_jobs.json"))
	if not jobs is Array:
		push_error("no mesh_jobs.json; run debris_pack.py first")
		quit(1)
		return
	for job: Dictionary in jobs:
		var out := pack + str(job["out"])
		if FileAccess.file_exists(out):
			continue
		var mesh := bake(str(job["fbx"]), int(job["tris"]), bool(job.get("split", false)), float(job.get("max_h", 0.0)))
		if mesh.is_empty():
			print("failed: ", job["fbx"])
			continue
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_var(mesh)
		print("%-60s %5d tris" % [str(job["out"]), (mesh["idx"] as PackedInt32Array).size() / 3])
	quit()


## The FBX's surfaces merged into one mesh of about `tris` triangles.
static func bake(path: String, tris: int, split: bool, max_h := 0.0) -> Dictionary:
	var doc := FBXDocument.new()
	var state := FBXState.new()
	if doc.append_from_file(path, state) != OK:
		return {}
	var parts: Array[Dictionary] = []
	var total := 0
	for gm: GLTFMesh in state.get_meshes():
		var im: ImporterMesh = gm.mesh
		for s in im.get_surface_count():
			total += (im.get_surface_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	for gm: GLTFMesh in state.get_meshes():
		var im: ImporterMesh = gm.mesh
		im.generate_lods(25.0, 60.0, [])
		for s in im.get_surface_count():
			var a := im.get_surface_arrays(s)
			var full := a[Mesh.ARRAY_INDEX] as PackedInt32Array
			# This surface's share of the target.
			var want := maxi(12, roundi(float(tris) * full.size() / 3.0 / maxf(total, 1)))
			# The level nearest the target, by ratio.
			var idx := full
			var best := absf(log(full.size() / 3.0 / want))
			for l in im.get_surface_lod_count(s):
				var lod := im.get_surface_lod_indices(s, l)
				var off := absf(log(maxf(lod.size() / 3.0, 1.0) / want))
				if off < best:
					best = off
					idx = lod
			parts.append(_part(a, idx))
	if parts.is_empty():
		return {}
	if split:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for p in parts:
			_lay(p, Vector3(rng.randf_range(-0.35, 0.35), 0.0, rng.randf_range(-0.35, 0.35)), rng.randf() * TAU)
	return _settle(_merge(parts), max_h)


## The vertices `idx` uses, with tangents.
static func _part(a: Array, idx: PackedInt32Array) -> Dictionary:
	var pos := a[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var nrm := a[Mesh.ARRAY_NORMAL] as PackedVector3Array
	var uv := a[Mesh.ARRAY_TEX_UV] as PackedVector2Array
	var remap := {}
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in idx:
		if not remap.has(i):
			remap[i] = remap.size()
			st.set_normal(nrm[i] if i < nrm.size() else Vector3.UP)
			st.set_uv(uv[i] if i < uv.size() else Vector2.ZERO)
			st.add_vertex(pos[i])
	for i in idx:
		st.add_index(remap[i])
	st.generate_tangents()
	var b := st.commit_to_arrays()
	var tan := PackedFloat32Array(b[Mesh.ARRAY_TANGENT])
	return {"pos": b[Mesh.ARRAY_VERTEX], "nrm": b[Mesh.ARRAY_NORMAL], "tan": tan, "uv": b[Mesh.ARRAY_TEX_UV], "idx": PackedInt32Array(b[Mesh.ARRAY_INDEX])}


## Lays a piece on its side at `at`, turned `yaw` (a cone lies on the ground).
static func _lay(p: Dictionary, at: Vector3, yaw: float) -> void:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for v: Vector3 in p["pos"]:
		lo = lo.min(v)
		hi = hi.max(v)
	var c := (lo + hi) * 0.5
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5)
	var pos := p["pos"] as PackedVector3Array
	var nrm := p["nrm"] as PackedVector3Array
	var tan := p["tan"] as PackedFloat32Array
	for i in pos.size():
		pos[i] = basis * (pos[i] - c) + at
		nrm[i] = basis * nrm[i]
		var t := basis * Vector3(tan[i * 4], tan[i * 4 + 1], tan[i * 4 + 2])
		tan[i * 4] = t.x
		tan[i * 4 + 1] = t.y
		tan[i * 4 + 2] = t.z
	p["pos"] = pos
	p["nrm"] = nrm
	p["tan"] = tan


static func _merge(parts: Array[Dictionary]) -> Dictionary:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var tan := PackedFloat32Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for p in parts:
		var base := pos.size()
		pos.append_array(p["pos"])
		nrm.append_array(p["nrm"])
		tan.append_array(p["tan"])
		uv.append_array(p["uv"])
		for i: int in p["idx"]:
			idx.append(i + base)
	return {"pos": pos, "nrm": nrm, "tan": tan, "uv": uv, "idx": idx}


## Centred on x, z and standing on y = 0; scaled down to `max_h` m tall
## when it stands higher (a 2.4 m snag reads as a pillar beside a fairway).
static func _settle(m: Dictionary, max_h := 0.0) -> Dictionary:
	var pos := m["pos"] as PackedVector3Array
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for v in pos:
		lo = lo.min(v)
		hi = hi.max(v)
	var shift := Vector3((lo.x + hi.x) * 0.5, lo.y, (lo.z + hi.z) * 0.5)
	var k := max_h / (hi.y - lo.y) if max_h > 0.0 and hi.y - lo.y > max_h else 1.0
	for i in pos.size():
		pos[i] = (pos[i] - shift) * k
	m["pos"] = pos
	return m
