extends SceneTree
## Bakes Megascans rock scans into the private pack's rocks/ (RockField,
## docs/megascans-pack.md). SRC holds one folder per scan with mesh.fbx
## (the _High FBX) and albedo/normal/rough.jpg (2K, see rock_prep.py).
## Copy into game/tests/tmp/ and run:
##   godot --headless --path game -s res://tests/tmp/rock_pack.gd -- SRC PACK
## Writes rocks/<id>.res (an ArrayMesh with LODs, real size, base at y = 0),
## its three textures and rocks.json. Never commit the output.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var src: String = args[0]
	var out: String = args[1].path_join("rocks")
	DirAccess.make_dir_recursive_absolute(out)
	var list := []
	for d in DirAccess.get_directories_at(src):
		var doc := FBXDocument.new()
		var st := FBXState.new()
		if doc.append_from_file(src.path_join(d).path_join("mesh.fbx"), st) != OK:
			continue
		var scene := doc.generate_scene(st)
		var n: ImporterMeshInstance3D = scene.find_children("*", "ImporterMeshInstance3D", true, false)[0]
		var xf: Transform3D = n.transform
		var p := n.get_parent()
		while p is Node3D:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var arrays := n.mesh.get_surface_arrays(0)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var nm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var tg: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		var aabb := AABB(xf * v[0], Vector3.ZERO)
		for i in v.size():
			v[i] = xf * v[i]
			aabb = aabb.expand(v[i])
		var shift := Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
		var b := xf.basis.orthonormalized()
		for i in v.size():
			v[i] -= shift
			nm[i] = (b * nm[i]).normalized()
			if tg.size() == v.size() * 4:
				var t := (b * Vector3(tg[i * 4], tg[i * 4 + 1], tg[i * 4 + 2])).normalized()
				tg[i * 4] = t.x; tg[i * 4 + 1] = t.y; tg[i * 4 + 2] = t.z
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = nm
		if tg.size() == v.size() * 4:
			arrays[Mesh.ARRAY_TANGENT] = tg
		var im := ImporterMesh.new()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if tg.size() != v.size() * 4:
			var surf := SurfaceTool.new()
			surf.create_from_arrays(arrays)
			surf.generate_tangents()
			im.clear()
			im.add_surface(Mesh.PRIMITIVE_TRIANGLES, surf.commit_to_arrays())
		im.generate_lods(25.0, 60.0, [])
		var mesh := im.get_mesh()
		var id := d.right(8)
		ResourceSaver.save(mesh, out.path_join(id + ".res"), ResourceSaver.FLAG_COMPRESS)
		for t in ["albedo", "normal", "rough"]:
			DirAccess.copy_absolute(src.path_join(d).path_join(t + ".jpg"), out.path_join("%s_%s.jpg" % [id, t]))
		var title := d.left(d.length() - 9)
		list.append({"id": id, "title": title, "size": [aabb.size.x, aabb.size.y, aabb.size.z], "kind": _kind(title)})
		print(id, " ", title, " ", aabb.size, " lods=", mesh.surface_get_lod_count(0) if mesh.has_method("surface_get_lod_count") else -1)
		scene.free()
	var f := FileAccess.open(out.path_join("rocks.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"source": "Quixel Megascans", "rocks": list}, "\t"))
	quit()

func _kind(t: String) -> String:
	if t.contains("Beach_Cliff") or t.contains("Beach_Rock_Formation"):
		return "shore_outcrop"
	if t.contains("Huge"):
		return "dry_outcrop"
	if t.contains("Scattered") or t.contains("Small_10"):
		return "scatter"
	if t.contains("Mossy") or t.contains("Forest") or t.contains("Lichen"):
		return "woodland"
	if t.contains("Beach"):
		return "shore"
	if t.contains("Sandstone"):
		return "sandstone"
	return "upland"
