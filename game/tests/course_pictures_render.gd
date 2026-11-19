extends SceneTree
## Renders the built-in courses' pictures for the course pickers
## (CoursePictures.BUILT_IN) with the same camera the game uses for a played
## course (CourseSnapshot), and writes them to assets/ui/menu/ (or `out_dir`).
## Run with a real GPU driver, ideally Forward+ through lavapipe:
##
##   godot --path game --rendering-method forward_plus -s res://tests/course_pictures_render.gd -- [out_dir] [course_red_spire ...]
##
## Naming pictures renders only those (one course per run keeps a software
## renderer's memory down).

const WAIT_FRAMES := 30

var _out := ""
var _keys: Array = []
var _game: GolfRound
var _frames := 0
var _snap: CourseSnapshot


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else ProjectSettings.globalize_path(CoursePictures.ART_DIR)
	for key: String in CoursePictures.BUILT_IN:
		if args.size() < 2 or args.slice(1).has(CoursePictures.BUILT_IN[key]):
			_keys.append(key)
	GolfRound.wind_seed = 20031
	GraphicsSettings.force_look = GraphicsSettings.Look.PHOTOREAL
	print("renderer: %s" % RenderingServer.get_current_rendering_method())


func _process(_delta: float) -> bool:
	if _game == null:
		if _keys.is_empty():
			return true
		var key: String = _keys.pop_front()
		var setup := RoundSetup.single(key)
		setup.course_key = key
		GolfRound.setup = setup
		GolfRound.chosen_course = key
		_game = (load("res://scenes/main.tscn") as PackedScene).instantiate() as GolfRound
		root.add_child(_game)
		_frames = 0
		return false
	_frames += 1
	if _frames == 2:
		_game.graphics.dynamic_res = 0
		_game._apply_graphics()
	elif _frames == WAIT_FRAMES and _snap == null:
		var key := _game.round_setup.course_key
		_snap = CourseSnapshot.take(_game, key, _game.hole, _game.camera, _game.post)
		_snap.saved.connect(_on_saved)
	return false


func _on_saved(key: String, ok: bool) -> void:
	var dest := _out.path_join(str(CoursePictures.BUILT_IN[key]) + ".oljpg")
	if ok:
		DirAccess.copy_absolute(ProjectSettings.globalize_path(CoursePictures.file_for(key)), dest)
		CoursePictures.forget(key)
	print("%s: %s" % [dest, "saved" if ok else "FAILED"])
	_snap = null
	_game.queue_free()
	_game = null
