class_name FrameBenchmark
extends Node
## Measures what each graphics feature costs on this machine. Start the
## game with `res://scenes/main.tscn -- --benchmark`: the placeholder round
## opens, the camera holds the first tee, and each case below is drawn for a
## few seconds with v-sync and dynamic resolution off. Tree levels only
## change on a new hole, so they aren't cases. The GPU and CPU time
## per frame of each case go to the log and user://benchmark.txt, then the
## game quits. Each case changes one thing from the device's own look.

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
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var g := _game.graphics
	g.dynamic_res = 0
	for k: String in KEYS:
		_base[k] = g.get(k)
	var lines := PackedStringArray()
	lines.append("OpenLinks2003 benchmark: %s, %s, %s, window %s, look %s" % [OS.get_name(), RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method(), get_window().size, GraphicsSettings.LOOK_NAMES[g.look]])
	lines.append("case | gpu ms | cpu ms | frame ms | fps | 3D scale | draws")
	var base_gpu := 0.0
	for c: Array in CASES:
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
		t = 0.0
		while t < MEASURE:
			await tree.process_frame
			t += get_process_delta_time()
			gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
			cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
			draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			frames += 1
		frames = maxi(frames, 1)
		gpu /= frames
		if c == CASES[0]:
			base_gpu = gpu
		var line := "%s | %.2f (%+.2f) | %.2f | %.2f | %.0f | %.2f | %.0f" % [c[0], gpu, gpu - base_gpu, cpu / frames, 1000.0 * t / frames, frames / t, get_viewport().scaling_3d_scale, draws / frames]
		print(line)
		lines.append(line)
	GraphicsSettings.ignore_pixel_budget = false
	var f := FileAccess.open("user://benchmark.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
	print("benchmark written to %s" % ProjectSettings.globalize_path("user://benchmark.txt"))
	tree.quit()
