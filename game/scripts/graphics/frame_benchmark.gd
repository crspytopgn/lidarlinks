class_name FrameBenchmark
extends Node
## Measures what each graphics feature costs on this machine. Start the
## game with `res://scenes/main.tscn -- --benchmark`: the placeholder round
## opens, the camera holds the first tee, and each case below is drawn for a
## few seconds with v-sync and dynamic resolution off. Tree levels only
## change on a new hole, so they aren't cases. The GPU and CPU time
## per frame of each case go to the log and user://benchmark.txt, then the
## game quits. Each case changes one thing from the device's own look.
## Before the cases it lists what the scene is made of (scene_breakdown);
## `--scene-only` stops after that and the device's own look, `--play-only`
## skips the cases, `--no-vsync` times the play without v-sync, and
## `--course=PATH` (res://, user:// or a file path) plays that course.

const WARM := 1.5
const MEASURE := 3.0
## name, then the settings to change ("shadows", "hard_shadows" and
## "native" are switches outside GraphicsSettings).
const CASES := [
	["default look", {}],
	["native resolution (no pixel budget)", {"native": true}],
	["SSAO off", {"ssao": false}],
	["sun shadows off", {"shadows": false}],
	["hard sun shadows", {"hard_shadows": true}],
	["MSAA off", {"msaa": 0}],
	["post effects off", {"sharpen": 0, "bloom": 0, "vignette": 0, "grain": 0}],
	["grass off", {"grass": 0}],
	["cloud shadows and wind off", {"cloud_shadows": false, "foliage_wind": false}],
	["Medium quality", {"quality": GraphicsSettings.Quality.MEDIUM}],
	["Low quality", {"quality": GraphicsSettings.Quality.LOW}],
]
const KEYS := ["quality", "msaa", "render_scale", "ssao", "sharpen", "bloom", "vignette", "grain", "grass", "trees", "cloud_shadows", "foliage_wind", "dynamic_res", "dof", "upscaler", "lighting"]

## Seconds of automatic play (shots, ball flight, camera moves, the next
## hole) timed frame by frame with v-sync back on, as a player sees it:
## averages hide hitches, so this reports percentiles and the worst frames.
const PLAY_SECONDS := 90.0
const WAIT := {GolfRound.State.AIM: 1.5, GolfRound.State.SWING: 1.5, GolfRound.State.COMPUTER: 1.5, GolfRound.State.SHOT_RESULT: 2.0, GolfRound.State.DROP: 1.0, GolfRound.State.DRIVE: 1.0, GolfRound.State.HOLE_DONE: 2.0}

var _game: GolfRound
var _base := {}


static func wanted() -> bool:
	return OS.get_cmdline_user_args().has("--benchmark")


## `-- --benchmark --look=natural` measures a preset look (LOOK_NAMES,
## lower case, spaces as _) instead of the saved settings. Call before the
## settings load.
static func prepare() -> void:
	if not wanted():
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--course="):
			GolfRound.chosen_course = arg.trim_prefix("--course=")
		if arg.begins_with("--look="):
			var name := arg.trim_prefix("--look=").replace("_", " ")
			for i in GraphicsSettings.LOOK_NAMES.size():
				if GraphicsSettings.LOOK_NAMES[i].to_lower() == name:
					GraphicsSettings.force_look = i


func _init(game: GolfRound) -> void:
	_game = game


func _ready() -> void:
	_run()


func _run() -> void:
	var tree := get_tree()
	var waited := 0.0
	while waited < 90.0 and (_game.hole == null or _game.state != GolfRound.State.AIM):
		await tree.process_frame
		waited += get_process_delta_time()
	for i in 60:
		await tree.process_frame
	_game.camera.end_flyover()
	_game.hud.hand_over.close()
	# The far ground's detail levels are worked out over the first frames.
	waited = 0.0
	while waited < 180.0 and tree.get_node_count_in_group("lod_refiner") > 0:
		await tree.process_frame
		waited += get_process_delta_time()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var g := _game.graphics
	g.dynamic_res = 0
	for k: String in KEYS:
		_base[k] = g.get(k)
	var lines := PackedStringArray()
	lines.append("LidarLinks benchmark: %s, %s, %s, window %s, look %s" % [OS.get_name(), RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method(), get_window().size, GraphicsSettings.LOOK_NAMES[g.look]])
	for line in scene_breakdown(_game, get_viewport().get_camera_3d()):
		print(line)
		lines.append(line)
	if await _views():
		tree.quit()
		return
	if OS.get_cmdline_user_args().has("--shadow-casters"):
		for line in await shadow_casters(_game):
			print(line)
			lines.append(line)
	var only_default := OS.get_cmdline_user_args().has("--scene-only")
	lines.append("case | gpu ms | cpu ms | frame ms | fps | 3D scale | draws | k prims")
	var base_gpu := 0.0
	var args := OS.get_cmdline_user_args()
	for c: Array in [] if args.has("--play-only") else CASES:
		var change: Dictionary = c[1]
		for k: String in KEYS:
			g.set(k, _base[k])
		GraphicsSettings.ignore_pixel_budget = change.get("native", false)
		for k: String in change:
			if k in KEYS:
				g.set(k, change[k])
		_game._apply_graphics()
		_game.scenery.sun.shadow_enabled = change.get("shadows", true)
		if change.get("hard_shadows", false):
			_game.scenery.sun.light_angular_distance = 0.0
			_game.scenery._sun_angle = 0.0
		var t := 0.0
		while t < WARM:
			await tree.process_frame
			t += get_process_delta_time()
		var gpu := 0.0
		var cpu := 0.0
		var frames := 0
		var draws := 0.0
		var prims := 0.0
		t = 0.0
		while t < MEASURE:
			await tree.process_frame
			t += get_process_delta_time()
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
			draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			frames += 1
		frames = maxi(frames, 1)
		gpu /= frames
		if c == CASES[0]:
			base_gpu = gpu
		var line := "%s | %.2f (%+.2f) | %.2f | %.2f | %.0f | %.2f | %.0f | %.0f" % [c[0], gpu, gpu - base_gpu, cpu / frames, 1000.0 * t / frames, frames / t, get_viewport().scaling_3d_scale, draws / frames, prims / frames / 1000.0]
		print(line)
		lines.append(line)
		if only_default:
			tree.quit()
			return
	GraphicsSettings.ignore_pixel_budget = false
	for k: String in KEYS:
		g.set(k, _base[k])
	_game._apply_graphics()
	_game.scenery.sun.shadow_enabled = true
	lines.append_array(await _play(PLAY_SECONDS))
	var f := FileAccess.open("user://benchmark.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
	print("benchmark written to %s" % ProjectSettings.globalize_path("user://benchmark.txt"))
	tree.quit()


func _play(seconds: float) -> PackedStringArray:
	var tree := get_tree()
	# `--no-vsync`: a virtual display (the cloud's) has no refresh to wait for.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED if OS.get_cmdline_user_args().has("--no-vsync") else DisplayServer.VSYNC_ENABLED)
	var out := PackedStringArray()
	var times: Array[float] = []
	var spikes: Array = []  ## [ms, state, process ms, draws, time]
	var state := _game.state
	var in_state := 0.0
	var start := Time.get_ticks_usec()
	var last := start
	while (last - start) < seconds * 1.0e6:
		await tree.process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		times.append(ms)
		if ms > 20.0:
			spikes.append([ms, GolfRound.State.keys()[_game.state], Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), (now - start) / 1.0e6])
		if _game.state != state:
			state = _game.state
			in_state = 0.0
		in_state += ms / 1000.0
		if WAIT.has(state) and in_state > WAIT[state]:
			in_state = 0.0
			_game.auto_play_step()
	var sorted := times.duplicate()
	sorted.sort()
	var n := sorted.size()
	var pct := func(p: float) -> float: return sorted[clampi(int(p * n), 0, n - 1)]
	var over := func(limit: float) -> int: return times.filter(func(t: float) -> bool: return t > limit).size()
	out.append("play %.0f s, v-sync on: %d frames, p50 %.1f ms, p95 %.1f, p99 %.1f, max %.1f; frames over 20 ms: %d, over 33 ms: %d, over 100 ms: %d" % [seconds, n, pct.call(0.5), pct.call(0.95), pct.call(0.99), sorted[n - 1], over.call(20.0), over.call(33.0), over.call(100.0)])
	spikes.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for sp: Array in spikes.slice(0, 15):
		out.append("spike %.1f ms at %.1f s, state %s, script %.1f ms, draws %d" % [sp[0], sp[4], sp[1], sp[2], sp[3]])
	for line in out:
		print(line)
	return out


## What the scene is made of, grouped by the script that owns each piece
## (the nearest ancestor with a script): visible meshes, their surfaces
## (draw calls before culling), instances, triangles drawn and how many cast
## sun shadows, plus how many distinct materials there are (each a shader
## the renderer compiles the first time it's seen). Hardware-independent,
## so cloud runs show the same costs a phone would pay.
static func scene_breakdown(root: Node, cam: Camera3D = null) -> PackedStringArray:
	var groups := {}
	var planes: Array[Plane] = cam.get_frustum() if cam != null else []
	var mats := {}
	var shaders := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not n is GeometryInstance3D or not (n as Node3D).is_visible_in_tree():
			continue
		var gi := n as GeometryInstance3D
		var mesh: Mesh = null
		var count := 1
		if gi is MeshInstance3D:
			mesh = (gi as MeshInstance3D).mesh
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null:
			var mm := (gi as MultiMeshInstance3D).multimesh
			mesh = mm.mesh
			count = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		if mesh == null or count == 0:
			continue
		var owner_name := _owner_name(gi, root)
		var mesh_name := mesh.resource_name if mesh.resource_name != "" else mesh.resource_path.get_file()
		if mesh_name != "" and owner_name.contains("@"):
			owner_name += " (%s)" % mesh_name
		var row: Array = groups.get(owner_name, [0, 0, 0, 0.0, 0, 0, 0, 0.0])
		var tris := 0
		for s in mesh.get_surface_count():
			var arrays_len := 0
			if mesh is ArrayMesh:
				var a := (mesh as ArrayMesh).surface_get_array_index_len(s)
				arrays_len = a if a > 0 else (mesh as ArrayMesh).surface_get_array_len(s)
			tris += arrays_len / 3
			var m: Material = gi.material_override if gi.material_override != null else mesh.surface_get_material(s)
			if gi is MeshInstance3D and (gi as MeshInstance3D).get_surface_override_material(s) != null:
				m = (gi as MeshInstance3D).get_surface_override_material(s)
			if m != null:
				mats[m.get_rid()] = true
				if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
					shaders[(m as ShaderMaterial).shader.get_rid()] = true
		row[0] += 1
		row[1] += mesh.get_surface_count()
		row[2] += count
		row[3] += float(tris) * count
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			row[4] += mesh.get_surface_count()
		if gi.visibility_range_end > 0.0:
			row[5] += 1
		if cam != null and _in_view(gi, cam, planes):
			row[6] += mesh.get_surface_count()
			row[7] += float(tris) * count
		groups[owner_name] = row
	var keys := groups.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return groups[a][1] > groups[b][1])
	var out := PackedStringArray()
	out.append("scene by owner | nodes | surfaces | instances | k tris | shadow surfaces | with visibility range | in view surfaces | in view k tris (LOD0)")
	for k: String in keys:
		var r: Array = groups[k]
		out.append("%s | %d | %d | %d | %.0f | %d | %d | %d | %.0f" % [k, r[0], r[1], r[2], r[3] / 1000.0, r[4], r[5], r[6], r[7] / 1000.0])
	out.append("distinct materials %d, shaders %d" % [mats.size(), shaders.size()])
	return out


## `--view=x,y,z,tx,ty,tz,PATH` (any number): draws the scene from the
## camera at x, y, z looking at tx, ty, tz, or at the ball's spot from
## the first tee with `--view=tee,PATH`, and saves the frame to PATH (png),
## for before and after comparisons of a change. True if there were any
## (the benchmark then ends).
func _views() -> bool:
	var tree := get_tree()
	var any := false
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("--view="):
			continue
		any = true
		var parts := arg.trim_prefix("--view=").split(",")
		var round_cam := get_viewport().get_camera_3d()
		var cam: Camera3D = null
		if parts.size() >= 7:
			# A camera of its own: the round's camera moves itself each frame.
			cam = Camera3D.new()
			cam.fov = round_cam.fov
			cam.near = round_cam.near
			cam.far = round_cam.far
			cam.attributes = round_cam.attributes
			_game.add_child(cam)
			cam.global_position = Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())
			cam.look_at(Vector3(parts[3].to_float(), parts[4].to_float(), parts[5].to_float()))
			cam.make_current()
		for i in 40:
			await tree.process_frame
		get_viewport().get_texture().get_image().save_png(parts[parts.size() - 1])
		if cam != null:
			round_cam.make_current()
			cam.queue_free()
		print("view saved to %s" % parts[parts.size() - 1])
	return any


## What each owner's sun shadow casters cost in the shadow pass: their
## shadows are switched off one owner at a time and the draws and
## primitives the frame loses are listed (`--shadow-casters`).
func shadow_casters(root: Node) -> PackedStringArray:
	var tree := get_tree()
	var groups := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is GeometryInstance3D and (n as Node3D).is_visible_in_tree() \
				and (n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			var k := _owner_name(n, root)
			if not groups.has(k):
				groups[k] = []
			groups[k].append(n)
	var measure := func() -> Vector2:
		for i in 3:
			await tree.process_frame
		var sum := Vector2.ZERO
		for i in 4:
			await tree.process_frame
			sum += Vector2(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		return sum / 4.0
	var base: Vector2 = await measure.call()
	var rows: Array = []
	for k: String in groups:
		var saved: Array = []
		for gi: GeometryInstance3D in groups[k]:
			saved.append(gi.cast_shadow)
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var off: Vector2 = await measure.call()
		for i in groups[k].size():
			(groups[k][i] as GeometryInstance3D).cast_shadow = saved[i]
		rows.append([k, groups[k].size(), base.x - off.x, (base.y - off.y) / 1000.0])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[3] > b[3])
	var out := PackedStringArray()
	out.append("shadow casters by owner | nodes | shadow draws | shadow k prims (frame %d draws, %.0fk prims)" % [base.x, base.y / 1000.0])
	for r: Array in rows:
		out.append("%s | %d | %.0f | %.0f" % r)
	return out


## In the camera's frustum and inside its visibility range (roughly, by the
## box's centre), so drawn this frame.
static func _in_view(gi: GeometryInstance3D, cam: Camera3D, planes: Array[Plane]) -> bool:
	var box := gi.global_transform * gi.get_aabb()
	var d := cam.global_position.distance_to(box.get_center())
	if gi.visibility_range_end > 0.0 and d > gi.visibility_range_end + gi.visibility_range_end_margin:
		return false
	if gi.visibility_range_begin > 0.0 and d < gi.visibility_range_begin - gi.visibility_range_begin_margin:
		return false
	for pl in planes:
		# Outside if the whole box is on the plane's outer side.
		var c := box.get_center()
		var e := box.size * 0.5
		var r := absf(pl.normal.x) * e.x + absf(pl.normal.y) * e.y + absf(pl.normal.z) * e.z
		if pl.distance_to(c) > r:
			return false
	return true


static func _owner_name(n: Node, root: Node) -> String:
	var p := n
	var path: Array[String] = []  ## names on the way up, nearest first
	while p != null and p != root:
		var s: Script = p.get_script()
		if s != null and p != n.get_parent() or s != null and p == n:
			var g := s.get_global_name()
			return String(g) if g != &"" else s.resource_path.get_file()
		path.push_front(String(p.name).rstrip("0123456789@"))
		p = p.get_parent()
	# Built straight into the round: name the two pieces it hangs from.
	return "/".join(path.slice(0, 3))

