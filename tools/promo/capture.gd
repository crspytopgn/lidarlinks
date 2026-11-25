extends SceneTree
## Dev tool (tools/promo/capture.sh): films one promo clip from the real
## game with Godot's Movie Maker. Godot writes every frame (and the sound)
## at a fixed 30 fps whatever the render speed, so slow software rendering
## still gives smooth footage. Frames outside a take are painted solid
## magenta, and cut.py keeps only the takes.
##
##   godot --path game --rendering-method forward_plus --fixed-fps 30 \
##     --write-movie /tmp/promo/NAME/f.png --resolution 1920x1080 \
##     -s $PWD/tools/promo/capture.gd -- clip=tools/promo/clips/NAME.gd [course=PATH] [key=value...]
##
## A clip is a script (extends RefCounted) with `func run(c) -> void`
## (it may await);
## `c` is this capture: c.game (the round), c.arg(), c.frames(), c.take(),
## c.cut(), c.hud(), c.camera_at(). Nothing here is shipped.

var game: GolfRound
var args := {}
var _mask: ColorRect
var _cam: Camera3D
var _takes := 0


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		args[a.get_slice("=", 0)] = a.get_slice("=", 1) if a.contains("=") else "1"
	_mask = ColorRect.new()
	_mask.color = Color(1, 0, 1)
	_mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	layer.layer = 128
	layer.add_child(_mask)
	root.add_child(layer)
	GolfRound.wind_seed = int(arg("seed", "20031"))
	GolfRound.record_rounds = false
	GraphicsSettings.force_look = GraphicsSettings.Look.PHOTOREAL
	GraphicsSettings.ignore_pixel_budget = true
	GolfRound.chosen_course = arg("course", "")
	if arg("scene", "") != "":
		_run_scene.call_deferred()
		return
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate() as GolfRound
	root.add_child(game)
	_run.call_deferred()


func arg(key: String, default := "") -> String:
	return args.get(key, default)


## Waits n frames (n / 30 s of game time under Movie Maker).
func frames(n: int) -> void:
	for i in n:
		await process_frame


func seconds(s: float) -> void:
	await frames(roundi(s * 30.0))


## Starts a take: the frames from here on are kept.
func take() -> void:
	if root.disable_3d:
		# 3D was off between takes (it is slow in software): warm it up.
		root.disable_3d = false
		await frames(15)
	_takes += 1
	print("PROMO TAKE %d" % _takes)
	_mask.visible = false


## Ends a take.
func cut() -> void:
	_mask.visible = true
	root.disable_3d = true


func hud(on: bool) -> void:
	if game != null and game.hud != null:
		(game.hud.get_parent() as CanvasLayer).visible = on


## A camera of our own, looking from `from` at `at`.
func camera_at(from: Vector3, at: Vector3, fov := 40.0) -> Camera3D:
	if _cam == null:
		_cam = Camera3D.new()
		root.add_child(_cam)
	_cam.fov = fov
	_cam.look_at_from_position(from, at)
	_cam.make_current()
	return _cam


## Gives the view back to the round's own cameras.
func release_camera() -> void:
	if _cam != null:
		_cam.clear_current(false)
		if game != null and game.camera != null:
			game.camera.make_current()


## Where the next shot from the ball would end, at `power` and `accuracy`,
## worked out the way play_shot does for a human player (nothing moves).
func predict(power: float, accuracy := 0.0) -> ShotResult:
	var g := game
	var club := g.clubs[g.club_index]
	var rec := ShotRecord.new()
	rec.index = g.record.shots.size()
	rec.player = g.shooter
	rec.club = g.club_index
	rec.club_name = club.short_name
	rec.aim_deg = g.aim_deg
	rec.power = power
	rec.accuracy = accuracy
	rec.lie = g.lie
	rec.from = g.ball_at
	rec.skill = g.graphics.skill
	rec.power_profile = g.graphics.power_profile
	rec.chip = g._chip and not club.is_putter
	if not club.is_putter:
		var setup := g.shape.to_setup(club.short_name)
		rec.ball_position = setup.ball_position
		rec.face = setup.face
		rec.stance = setup.stance
		rec.backspin = g.shape.backspin(not g.broadcast)
	rec.wind_level = g.wind.level
	rec.wind = g.wind.velocity()
	return RoundReplay.run_shot(g.shot_model.fresh(), rec, club, g.hole.terrain, g.hole.pin, rec.wind, g.round_seed)


## The power (searched in small steps around `guess`) that holes the putt,
## or -1.
func holing_power(guess: float) -> float:
	for i in 80:
		var p := guess * (1.0 + (0.005 * ceili(i / 2.0) * (1 if i % 2 == 0 else -1)))
		if predict(p).outcome == ShotResult.Outcome.HOLED:
			return p
	return -1.0


## Puts the ball `metres` from the pin on the line back to the tee (or along
## `back`, a flat direction away from the pin) and readies the shot there.
func ball_from_pin(metres: float, back := Vector3.ZERO) -> void:
	var g := game
	var pin := g.hole.pin
	if back == Vector3.ZERO:
		back = Vector3(g.hole.tee.x - pin.x, 0.0, g.hole.tee.z - pin.z).normalized()
	var at := pin + back * metres
	at.y = g.hole.terrain.height_at(at.x, at.z)
	g.ball_at = at
	g._prepare_shot(true)


## Waits for one-off bakes (crowd, tree impostors) to finish.
func settle() -> void:
	var n := 0
	while CrowdImpostors.baking() or n < 20:
		n = 0 if CrowdImpostors.baking() else n + 1
		await process_frame


func _run() -> void:
	await frames(3)
	game.graphics.dynamic_res = 0
	if arg("time", "") != "":
		game.graphics.time_of_day = int(arg("time"))
	if arg("presentation", "") != "":
		game.graphics.presentation = int(arg("presentation"))
	game.graphics.quality = GraphicsSettings.Quality.ULTRA
	# No how-to panels in the promo.
	game.graphics.swing_help = false
	if arg("grid", "") != "":
		game.graphics.putting_grid = int(arg("grid"))
	game._apply_graphics()
	if arg("time", "") != "":
		game._relight()
	if arg("rain", "") != "" or arg("cloud", "") != "":
		game.weather = RoundWeather.fine()
		game.weather.cloud = float(arg("cloud", "0.2"))
		game.weather.rain = int(arg("rain", "0")) as RoundWeather.Rain
		game._show_weather()
	await _clip_run()


func _run_scene() -> void:
	var node := (load(arg("scene")) as PackedScene).instantiate()
	root.add_child(node)
	await frames(3)
	await _clip_run(node)


func _clip_run(node: Node = null) -> void:
	var clip: GDScript = load(ProjectSettings.globalize_path("res://").path_join("..").path_join(arg("clip")).simplify_path())
	var o: Variant = clip.new()
	if node != null:
		await o.run(self, node)
	else:
		await o.run(self)
	cut()
	await frames(2)
	print("PROMO DONE %d takes" % _takes)
	quit(0)
