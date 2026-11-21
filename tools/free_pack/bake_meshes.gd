extends SceneTree
## The mesh step of tools/free_pack/free_pack.py bake: reads JOBS (a JSON
## list written by free_pack.py) and cuts each Poly Haven glTF down with
## Godot's own simplifier (which keeps UV seams) into OUT:
##
## - "rock": each piece (a mesh node of the set) as rocks/<id>.res, an
##   ArrayMesh at real size, base at y = 0, centred, with LODs (RockField);
## - "plant": up to VARIANTS mesh nodes as the variants of one
##   foliage/plants/<asset>.olplant, each with a near and a mid level
##   (format at the top of tools/megascans/plant_meshes.py);
## - "debris": every mesh node merged into debris/<asset>.olmesh, a
##   store_var Dictionary of packed arrays (MegascansDebris.build_mesh).
##
## Prints one JSON line per output ("BAKED {...}") for free_pack.py.
##
##     godot --headless -s tools/free_pack/bake_meshes.gd -- JOBS OUT


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- JOBS OUT")
		quit(1)
		return
	var jobs: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var out := args[1].path_join("")
	for job: Dictionary in jobs:
		var parts := _parts(str(job["gltf"]))
		if parts.is_empty():
			print("failed: ", job["gltf"])
			continue
		match str(job["kind"]):
			"rock":
				_rock(job, parts, out)
			"plant":
				_plant(job, parts, out)
			"debris":
				_debris(job, parts, out)
	quit()


## The glTF's mesh nodes in world space: [{name, arrays}], biggest first.
static func _parts(path: String) -> Array[Dictionary]:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var out: Array[Dictionary] = []
	if doc.append_from_file(path, st) != OK:
		return out
	var scene := doc.generate_scene(st)
	for n: ImporterMeshInstance3D in scene.find_children("*", "ImporterMeshInstance3D", true, false):
		var xf: Transform3D = n.transform
		var p := n.get_parent()
		while p is Node3D:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var b := xf.basis.orthonormalized()
		var pos := PackedVector3Array()
		var nrm := PackedVector3Array()
		var uv := PackedVector2Array()
		var idx := PackedInt32Array()
		for s in n.mesh.get_surface_count():
			var a := n.mesh.get_surface_arrays(s)
			var base := pos.size()
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var nm: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
			var t: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
			for i in v.size():
				pos.append(xf * v[i])
				nrm.append((b * (nm[i] if i < nm.size() else Vector3.UP)).normalized())
				uv.append(t[i] if i < t.size() else Vector2.ZERO)
			for i: int in a[Mesh.ARRAY_INDEX]:
				idx.append(base + i)
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for v in pos:
			lo = lo.min(v)
			hi = hi.max(v)
		out.append({"name": str(n.name), "pos": pos, "nrm": nrm, "uv": uv, "idx": idx, "size": hi - lo, "lo": lo, "hi": hi})
	scene.free()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["size"] as Vector3).x * (a["size"] as Vector3).y * (a["size"] as Vector3).z > (b["size"] as Vector3).x * (b["size"] as Vector3).y * (b["size"] as Vector3).z)
	return out


## The part centred on x, z and standing on y = 0, scaled down to max_h.
static func _settle(p: Dictionary, max_h := 0.0) -> Dictionary:
	var lo: Vector3 = p["lo"]
	var hi: Vector3 = p["hi"]
	var shift := Vector3((lo.x + hi.x) * 0.5, lo.y, (lo.z + hi.z) * 0.5)
	var k := max_h / (hi.y - lo.y) if max_h > 0.0 and hi.y - lo.y > max_h else 1.0
	var pos := (p["pos"] as PackedVector3Array).duplicate()
	for i in pos.size():
		pos[i] = (pos[i] - shift) * k
	var q := p.duplicate()
	q["pos"] = pos
	q["size"] = (hi - lo) * k
	return q


## The part's triangles cut to about `tris` (the simplifier's level
## nearest it), with tangents: {pos, nrm, tan, uv, idx}.
static func _cut(p: Dictionary, tris: int) -> Dictionary:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = p["pos"]
	arrays[Mesh.ARRAY_NORMAL] = p["nrm"]
	arrays[Mesh.ARRAY_TEX_UV] = p["uv"]
	arrays[Mesh.ARRAY_INDEX] = p["idx"]
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var full := p["idx"] as PackedInt32Array
	var idx := full
	if full.size() / 3 > tris:
		im.generate_lods(25.0, 60.0, [])
		var best := absf(log(full.size() / 3.0 / tris))
		for l in im.get_surface_lod_count(0):
			var lod := im.get_surface_lod_indices(0, l)
			var off := absf(log(maxf(lod.size() / 3.0, 1.0) / tris))
			if off < best:
				best = off
				idx = lod
	var a := im.get_surface_arrays(0)
	var src_pos := a[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var src_nrm := a[Mesh.ARRAY_NORMAL] as PackedVector3Array
	var src_uv := a[Mesh.ARRAY_TEX_UV] as PackedVector2Array
	var remap := {}
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in idx:
		if not remap.has(i):
			remap[i] = remap.size()
			st.set_normal(src_nrm[i])
			st.set_uv(src_uv[i])
			st.add_vertex(src_pos[i])
	for i in idx:
		st.add_index(remap[i])
	st.generate_tangents()
	var b := st.commit_to_arrays()
	return {"pos": b[Mesh.ARRAY_VERTEX], "nrm": b[Mesh.ARRAY_NORMAL], "tan": PackedFloat32Array(b[Mesh.ARRAY_TANGENT]),
		"uv": b[Mesh.ARRAY_TEX_UV], "idx": PackedInt32Array(b[Mesh.ARRAY_INDEX])}


static func _arrays(m: Dictionary) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = m["pos"]
	arrays[Mesh.ARRAY_NORMAL] = m["nrm"]
	arrays[Mesh.ARRAY_TANGENT] = m["tan"]
	arrays[Mesh.ARRAY_TEX_UV] = m["uv"]
	arrays[Mesh.ARRAY_INDEX] = m["idx"]
	return arrays


func _rock(job: Dictionary, parts: Array[Dictionary], out: String) -> void:
	DirAccess.make_dir_recursive_absolute(out + "rocks")
	var asset := str(job["asset"])
	# Pebbles are left out: RockField's rocks are boulders.
	var big: Array[Dictionary] = []
	for p in parts:
		var sz: Vector3 = p["size"]
		if maxf(sz.x, maxf(sz.y, sz.z)) >= float(job.get("min_m", 0.5)) and maxf(sz.x, sz.z) <= float(job.get("max_m", 25.0)):
			big.append(p)
	var n := mini(int(job.get("pieces", 1)), big.size())
	for k in n:
		var p := _settle(big[k])
		var m := _cut(p, int(job.get("tris", 3000)))
		var im := ImporterMesh.new()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, _arrays(m))
		im.generate_lods(25.0, 60.0, [])
		var id := asset if n == 1 else "%s_%d" % [asset, k + 1]
		ResourceSaver.save(im.get_mesh(), out + "rocks/" + id + ".res", ResourceSaver.FLAG_COMPRESS)
		var size: Vector3 = p["size"]
		print("BAKED ", JSON.stringify({"kind": "rock", "asset": asset, "id": id, "size": [size.x, size.y, size.z],
			"tris": (m["idx"] as PackedInt32Array).size() / 3}))


func _plant(job: Dictionary, parts: Array[Dictionary], out: String) -> void:
	DirAccess.make_dir_recursive_absolute(out + "foliage/plants")
	var asset := str(job["asset"])
	# The biggest few, as the plant's variants; tiny sprigs are left out.
	# Those the simplifier can bring near the budget first (it can't cut
	# some cards of separate blades at all), then the rest.
	var keep: Array[Dictionary] = []
	var top: Vector3 = parts[0]["size"]
	var near_max := int(job.get("near", 2400)) * 3 / 2
	for pass_k in 2:
		for p in parts:
			var light := (p["idx"] as PackedInt32Array).size() / 3 <= near_max or (_cut(p, int(job.get("near", 2400)))["idx"] as PackedInt32Array).size() / 3 <= near_max
			if keep.size() < int(job.get("variants", 4)) and not keep.has(p) and (p["size"] as Vector3).y >= top.y * 0.35 and (light or (pass_k == 1 and keep.size() < 2)):
				keep.append(p)
	var data := PackedByteArray()
	data.append_array(_u32(keep.size()))
	var height := 0.0
	var tris := []
	for p in keep:
		var s := _settle(p)
		height = maxf(height, (s["size"] as Vector3).y)
		var levels := [_cut(s, int(job.get("near", 2400))), _cut(s, int(job.get("mid", 700)))]
		data.append_array(_u32(levels.size()))
		for m: Dictionary in levels:
			var pos := m["pos"] as PackedVector3Array
			var nrm := m["nrm"] as PackedVector3Array
			var uv := m["uv"] as PackedVector2Array
			var idx := m["idx"] as PackedInt32Array
			# Counter-clockwise from the front, as the Megascans baker
			# writes them (MegascansPlants._mesh turns them round).
			for t in range(0, idx.size() - 2, 3):
				var swap := idx[t + 1]
				idx[t + 1] = idx[t + 2]
				idx[t + 2] = swap
			data.append_array(_u32(pos.size()))
			data.append_array(_u32(idx.size()))
			var fl := PackedFloat32Array()
			fl.resize(pos.size() * 8)
			for i in pos.size():
				fl[i * 8] = pos[i].x
				fl[i * 8 + 1] = pos[i].y
				fl[i * 8 + 2] = pos[i].z
				fl[i * 8 + 3] = nrm[i].x
				fl[i * 8 + 4] = nrm[i].y
				fl[i * 8 + 5] = nrm[i].z
				fl[i * 8 + 6] = uv[i].x
				fl[i * 8 + 7] = uv[i].y
			data.append_array(fl.to_byte_array())
			data.append_array(idx.to_byte_array())
			tris.append(idx.size() / 3)
	var f := FileAccess.open(out + "foliage/plants/" + asset + ".olplant", FileAccess.WRITE)
	f.store_buffer("OLPLANT1".to_ascii_buffer())
	f.store_32(data.size())
	f.store_buffer(data.compress(FileAccess.COMPRESSION_DEFLATE))
	f.close()
	print("BAKED ", JSON.stringify({"kind": "plant", "asset": asset, "variants": keep.size(), "height_m": height, "tris": tris}))


func _debris(job: Dictionary, parts: Array[Dictionary], out: String) -> void:
	DirAccess.make_dir_recursive_absolute(out + "debris")
	var asset := str(job["asset"])
	# All the pieces, merged, as one prop.
	var all := {"pos": PackedVector3Array(), "nrm": PackedVector3Array(), "uv": PackedVector2Array(), "idx": PackedInt32Array()}
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var total := 0
	for p in parts:
		total += (p["idx"] as PackedInt32Array).size() / 3
	var cut_parts: Array[Dictionary] = []
	for p in parts:
		var share := maxi(12, roundi(float(job.get("tris", 2000)) * (p["idx"] as PackedInt32Array).size() / 3.0 / maxf(total, 1)))
		cut_parts.append(_cut(p, share))
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var tan := PackedFloat32Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for c in cut_parts:
		var base := pos.size()
		pos.append_array(c["pos"])
		nrm.append_array(c["nrm"])
		tan.append_array(c["tan"])
		uv.append_array(c["uv"])
		for i: int in c["idx"]:
			idx.append(i + base)
	for v in pos:
		lo = lo.min(v)
		hi = hi.max(v)
	var settled := _settle({"pos": pos, "lo": lo, "hi": hi}, float(job.get("max_h", 0.0)))
	var m := {"pos": settled["pos"], "nrm": nrm, "tan": tan, "uv": uv, "idx": idx}
	all = m
	var f := FileAccess.open(out + "debris/" + asset + ".olmesh", FileAccess.WRITE)
	f.store_var(all)
	f.close()
	var size: Vector3 = settled["size"]
	print("BAKED ", JSON.stringify({"kind": "debris", "asset": asset, "size": [size.x, size.y, size.z], "tris": (m["idx"] as PackedInt32Array).size() / 3}))


static func _u32(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, v)
	return b
