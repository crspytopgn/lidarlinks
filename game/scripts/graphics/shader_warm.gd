class_name ShaderWarm
extends RefCounted
## Builds shaders before they are needed. The graphics driver compiles a
## shader (and, on Forward+, a pipeline for each mesh layout and pass it
## meets) the first time something draws with it, and that frame stalls:
## a few milliseconds on the desktop, up to seconds in a Windows browser,
## which translates every shader for Direct3D. The tee and green views
## behind the loading card (GolfRound._warm_shaders) only catch what those
## views happen to show; this draws everything else once as well:
##
## - a copy of every mesh and multimesh in the scene with its own materials,
##   wherever it stands (a pond behind the camera, the far side of a hill),
## - every spatial shader the game has (res://shaders) on a quad, plain and
##   instanced, for effects that only appear later: divots, pitch marks,
##   the green grid, ball shadows, a splash,
##
## all in front of the camera (shrunk with the holder, so even a hole-wide
## mesh is a speck in view and nothing culls it), shrunk to nothing so
## they cover no pixel
## (a draw that covers no pixel still makes the driver build its shader),
## and casting sun shadows, which builds the shadow pass's versions too.
## Each mesh is drawn once per run: at a hole change only what the new hole
## brings that no hole before it had is drawn, for a frame.

## How far in front of the camera the copies stand (well inside the first
## shadow split) and how small they are drawn.
const DISTANCE := 1.5
const SCALE := 1.0e-6
## Most copies placed in one frame (the rest wait for the next).
const PER_FRAME := 400

## What has been drawn this run, by what the driver builds a shader or a
## pipeline for: the shaders (a ShaderMaterial's shader, or the material
## itself for a standard one), each surface's vertex layout and the kind of
## instance (a mesh, or a multimesh and its format), not the mesh itself,
## so a hole's hundreds of ground pieces on one shader are drawn once.
static var _done := {}
static var _shaders_done := false


## Copies of what in `root` hasn't been drawn yet this run, plus (the first
## time) the game's own shaders, as children of a new node, or null when
## there's nothing new. Add it in front of the camera (place()) for a frame
## or two, then free it.
static func build(root: Node) -> Node3D:
	var holder := Node3D.new()
	holder.name = "ShaderWarm"
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.name == &"ShaderWarm":
			continue
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			_copy_mesh(n as MeshInstance3D, holder)
		elif n is MultiMeshInstance3D:
			_copy_multimesh(n as MultiMeshInstance3D, holder)
	if not _shaders_done:
		_shaders_done = true
		for m in shader_materials():
			_add_quads(m, holder)
	if holder.get_child_count() == 0:
		holder.free()
		return null
	return holder


## Puts `holder`'s copies in a grid just in front of `camera`, shrunk to
## nothing. Call each frame the holder is kept, as the camera moves.
static func place(holder: Node3D, camera: Camera3D) -> void:
	var basis := camera.global_transform.basis
	var centre := camera.global_position - basis.z * DISTANCE
	holder.global_transform = Transform3D(basis.scaled(Vector3.ONE * SCALE), centre)


## Draws everything in `root` not drawn before, in front of `camera`, over
## a frame or two (PER_FRAME copies a frame), then frees the copies.
static func warm(root: Node, camera: Camera3D, tree: SceneTree) -> int:
	if camera == null or not camera.is_inside_tree() or OS.get_environment("OL_NO_SHADER_WARM") == "1":
		return 0
	var holder := build(root)
	if holder == null:
		return 0
	var copies := holder.get_children()
	var count := copies.size()
	for c in copies:
		holder.remove_child(c)
	camera.get_parent().add_child(holder)
	var i := 0
	while i < count:
		for k in range(i, mini(i + PER_FRAME, count)):
			holder.add_child(copies[k])
		i += PER_FRAME
		if is_instance_valid(camera) and camera.is_inside_tree():
			place(holder, camera)
		await tree.process_frame
		await tree.process_frame
	holder.queue_free()
	return count


## What the driver builds for `gi` drawing `mesh`: per surface its vertex
## layout and shader, then the overlay and whether it casts shadows.
static func _draw_key(gi: GeometryInstance3D, mesh: Mesh) -> Array:
	var key: Array = []
	for s in mesh.get_surface_count():
		var m: Material = gi.material_override
		if m == null and gi is MeshInstance3D:
			m = (gi as MeshInstance3D).get_surface_override_material(s)
		if m == null:
			m = mesh.surface_get_material(s)
		key.append(mesh.surface_get_format(s) if mesh is ArrayMesh else mesh.get_class())
		key.append(_shader_of(m))
	key.append(_shader_of(gi.material_overlay))
	key.append(gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	return key


## The shader a material draws with: a ShaderMaterial's own (and its next
## pass), else the material itself (a standard material's shader depends
## on which of its features are on, which only it knows).
static func _shader_of(m: Material) -> Array:
	if m == null:
		return []
	var out: Array = []
	if m is ShaderMaterial:
		var sh := (m as ShaderMaterial).shader
		out.append(sh.get_rid() if sh != null else RID())
	else:
		out.append(m.get_rid())
	if m.next_pass != null:
		out.append_array(_shader_of(m.next_pass))
	return out


static func _copy_mesh(src: MeshInstance3D, holder: Node3D) -> void:
	var mesh := src.mesh
	if mesh == null or mesh.get_surface_count() == 0 or src.skin != null:
		return  # skinned meshes (the golfer, the gallery) are on screen anyway
	var key := ["m", _draw_key(src, mesh)]
	if _done.has(key):
		return
	_done[key] = true
	var copy := MeshInstance3D.new()
	copy.mesh = mesh
	copy.material_override = src.material_override
	copy.material_overlay = src.material_overlay
	for s in mini(src.get_surface_override_material_count(), mesh.get_surface_count()):
		copy.set_surface_override_material(s, src.get_surface_override_material(s))
	_copy_settings(src, copy)
	holder.add_child(copy)


static func _copy_multimesh(src: MultiMeshInstance3D, holder: Node3D) -> void:
	var mm := src.multimesh
	if mm == null or mm.mesh == null or mm.mesh.get_surface_count() == 0:
		return
	var key := ["mm", mm.use_colors, mm.use_custom_data, mm.transform_format, _draw_key(src, mm.mesh)]
	if _done.has(key):
		return
	_done[key] = true
	var one := MultiMesh.new()
	one.transform_format = mm.transform_format
	one.use_colors = mm.use_colors
	one.use_custom_data = mm.use_custom_data
	one.mesh = mm.mesh
	one.instance_count = 1
	if mm.transform_format == MultiMesh.TRANSFORM_3D:
		one.set_instance_transform(0, Transform3D.IDENTITY)
	else:
		one.set_instance_transform_2d(0, Transform2D.IDENTITY)
	var copy := MultiMeshInstance3D.new()
	copy.multimesh = one
	copy.material_override = src.material_override
	copy.material_overlay = src.material_overlay
	_copy_settings(src, copy)
	holder.add_child(copy)


static func _copy_settings(src: GeometryInstance3D, copy: GeometryInstance3D) -> void:
	copy.cast_shadow = src.cast_shadow
	copy.transparency = src.transparency
	# Kept out of global illumination: a copy is a speck, not scenery.
	copy.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	copy.layers = src.layers
	# Instance uniforms (per-instance shader parameters) carry over too.
	for p: Dictionary in src.get_property_list():
		var name: String = p["name"]
		if name.begins_with("instance_shader_parameters/"):
			copy.set(name, src.get(name))


## A material for each spatial shader in res://shaders, with its defaults.
static func shader_materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	for file in ResourceLoader.list_directory("res://shaders"):
		if not file.ends_with(".gdshader"):
			continue
		var shader := load("res://shaders/" + file) as Shader
		if shader == null or shader.get_mode() != Shader.MODE_SPATIAL:
			continue
		var m := ShaderMaterial.new()
		m.shader = shader
		out.append(m)
	return out


## A quad drawn with `m`, plain and as a one-instance multimesh with
## colours and custom data (the form the crowd cards, grass and markers use).
static func _add_quads(m: Material, holder: Node3D) -> void:
	var quad := QuadMesh.new()
	quad.material = m
	var plain := MeshInstance3D.new()
	plain.mesh = quad
	plain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	plain.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	holder.add_child(plain)
	var one := MultiMesh.new()
	one.transform_format = MultiMesh.TRANSFORM_3D
	one.use_colors = true
	one.use_custom_data = true
	one.mesh = quad
	one.instance_count = 1
	one.set_instance_transform(0, Transform3D.IDENTITY)
	var multi := MultiMeshInstance3D.new()
	multi.multimesh = one
	multi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	multi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	holder.add_child(multi)


## Forgets what was drawn (tests, and a renderer change).
static func reset() -> void:
	_done.clear()
	_shaders_done = false
