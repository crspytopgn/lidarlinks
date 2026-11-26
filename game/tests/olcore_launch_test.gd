extends SceneTree
## Parity test for the native Links launch and swing primitives
## (OlcorePhysics.links_launch / links_apply_swing / links_mouse_swing and
## friends) against the GDScript port. Run after importing, with the
## extension built:
##   godot --headless --path game -s res://tests/olcore_launch_test.gd
## Prints "OLCORE LAUNCH TEST PASSED" and exits 0 when every native
## primitive matches the GDScript port on the cases run_tests.gd pins
## (links_launch_matches_olcore, links_swing_matches_olcore), or
## "OLCORE LAUNCH TEST: native not available" and exits 0 when the
## extension is absent.

var _failures := 0
var _physics = null


func _initialize() -> void:
	if not ClassDB.class_exists("OlcorePhysics"):
		print("OLCORE LAUNCH TEST: native not available (GDScript fallback)")
		quit(0)
		return
	_physics = ClassDB.instantiate("OlcorePhysics")
	_check_launch()
	_check_apply_lie()
	_check_meter_contact()
	_check_apply_swing()
	_check_computer_miss()
	_check_computer_putt_miss()
	_check_mouse_swing()
	if OlcoreShotModel.use_native_enabled():
		_check_model_launch()
	else:
		print("  (model launch not checked: run with -- --native-physics for it)")
	if _failures == 0:
		print("OLCORE LAUNCH TEST PASSED")
		quit(0)
	else:
		print("OLCORE LAUNCH TEST FAILED: %d failures" % _failures)
		quit(1)


## The made-up club table of test_links_launch in libs/olcore/tests, as
## run_tests.gd builds it.
func _synthetic_clubs() -> LinksLaunch:
	var exe := PackedByteArray()
	exe.resize(36)
	exe.fill(0x11)
	var rows: Array[Callable] = [
		func(i: int) -> float: return 1.5 + 0.2 * i,
		func(i: int) -> float: return 2.0 + 0.01 * i,
		func(i: int) -> float: return 10.0 + 2.0 * i if i < 7 else 14.0 + 4.0 * (i - 7),
		func(i: int) -> float: return 0.05 + 0.01 * i,
		func(i: int) -> float: return 10.0 + 0.5 * i,
	]
	for row in rows:
		for i in 20:
			var at := exe.size()
			exe.resize(at + 4)
			exe.encode_float(at, row.call(i) if i < 19 else 0.0)
	return LinksLaunch.from_exe(exe)


func _native_clubs(t: LinksLaunch):
	var clubs = ClassDB.instantiate("OlcoreClubs")
	if not clubs.set_table(t.spin, t.speed, t.loft_deg, t.glance, t.ball_position):
		_failures += 1
		print("  FAIL: native club table rejected")
	return clubs


static func _strike_dict(s: LinksLaunch.Strike) -> Dictionary:
	return {"club": s.club, "aim": s.aim, "power": s.power, "face_error": s.face_error,
			"path_error": s.path_error, "speed_scale": s.speed_scale, "spin_scale": s.spin_scale,
			"loft_scale": s.loft_scale, "setup_ball_position": s.setup.ball_position,
			"setup_face": s.setup.face, "setup_stance": s.setup.stance,
			"ground_normal": s.ground_normal}


static func _lie_dict(p: LinksGround.Params) -> Dictionary:
	return {"ground_class": p.ground_class, "restitution": p.restitution,
			"impact_friction": p.impact_friction, "skid_friction": p.skid_friction,
			"impact_drag": p.impact_drag, "roll_resistance": p.roll_resistance,
			"stop_speed": p.stop_speed, "spin_grip": p.spin_grip, "lie_spin": p.lie_spin,
			"lie_power": p.lie_power}


static func _swing_dict(w: LinksLaunch.SwingInput) -> Dictionary:
	return {"method": w.method, "skill": w.skill, "contact": w.contact, "full_power": w.full_power,
			"mouse_face_deg": w.mouse_face_deg, "mouse_path_deg": w.mouse_path_deg,
			"mouse_loft": w.mouse_loft, "left_handed": w.left_handed, "chip": w.chip,
			"teed_up": w.teed_up}


static func _ratings_dict(g: LinksLaunch.GolferRatings) -> Dictionary:
	return {"tee": g.tee, "woods": g.woods, "long_irons": g.long_irons, "mid_irons": g.mid_irons,
			"short_irons": g.short_irons, "wedges": g.wedges, "chips": g.chips,
			"max_power": g.max_power, "steady": g.steady, "long_putts": g.long_putts,
			"short_putts": g.short_putts}


static func _stroke_dict(m: LinksMouse.Stroke) -> Dictionary:
	return {"skill": m.skill, "shot": m.shot, "club": m.club, "speed": m.speed, "drift": m.drift,
			"drift_before": m.drift_before, "down": m.down, "backswing": m.backswing,
			"straight": m.straight}


func _check_launch() -> void:
	var t := _synthetic_clubs()
	if t == null:
		_failures += 1
		print("  FAIL: synthetic club table not found")
		return
	var clubs = _native_clubs(t)
	var cases: Array = []
	var s := LinksLaunch.Strike.new()
	cases.append([s, [0, 195.679363, 24.503551, 73.860581, 0, 0], "square driver"])
	s = LinksLaunch.Strike.new()
	s.club = 12
	s.aim = 0.4
	s.power = 85
	s.face_error = 0.03
	s.path_error = -0.02
	s.setup.ball_position = 6
	s.setup.face = 33
	s.setup.stance = 27
	cases.append([s, [-60.178063, 130.934603, 58.414966, 135.705451, 62.62540, -0.570758], "set-up iron"])
	s = LinksLaunch.Strike.new()
	s.club = 5
	s.aim = -1.2
	s.power = 70
	s.face_error = -0.05
	s.path_error = 0.04
	s.spin_scale = 0.9
	s.speed_scale = 1.05
	s.loft_scale = 1.1
	s.setup.face = 26
	s.setup.stance = 32
	s.ground_normal = Vector3(0.2, -0.1, sqrt(1 - 0.05))
	cases.append([s, [130.663751, 47.660517, 18.457195, 27.686730, -73.138883, -7.141661], "on a slope"])
	s = LinksLaunch.Strike.new()
	s.club = 18
	s.aim = 2.5
	s.power = 60
	s.setup.ball_position = 1
	s.ground_normal = Vector3(-0.3, 0.25, sqrt(1 - 0.09 - 0.0625))
	cases.append([s, [-24.752554, -31.449690, 48.410392, -62.535463, 46.668793, -1.656532], "steep slope"])
	for c in cases:
		var strike: LinksLaunch.Strike = c[0]
		var want: Array = c[1]
		var native: Dictionary = _physics.links_launch(clubs, _strike_dict(strike))
		if native.is_empty():
			_failures += 1
			print("  FAIL: links_launch empty for %s" % c[2])
			continue
		var got := [(native.velocity as Vector3).x, (native.velocity as Vector3).y,
				(native.velocity as Vector3).z, (native.spin as Vector3).x, (native.spin as Vector3).y,
				(native.spin as Vector3).z]
		for i in 6:
			_check_near(got[i], want[i], 2e-3, "launch %s [%d]" % [c[2], i])
	# The putter's own launch, and tilting it onto a slope.
	var p := LinksLaunch.Strike.new()
	p.club = LinksLaunch.PUTTER
	p.power = 10.0
	p.aim = 0.2
	var gd: Array = LinksLaunch.putt(p)
	var native_putt: Dictionary = _physics.links_putt(_strike_dict(p))
	_check_near((native_putt.velocity as Vector3).x, gd[0].x, 2e-3, "putt velocity x")
	_check_near((native_putt.velocity as Vector3).y, gd[0].y, 2e-3, "putt velocity y")
	_check_near((native_putt.spin as Vector3).x, gd[1].x, 2e-3, "putt spin x")
	var n := Vector3(0.1, -0.05, sqrt(1 - 0.0125))
	_check_vec(_physics.links_putt_slope(gd[0], n), LinksLaunch.putt_slope(gd[0], n), 1e-6,
			"putt slope")
	# A bad table and a bad club are rejected, not silently wrong.
	var bad_clubs = ClassDB.instantiate("OlcoreClubs")
	_check(_physics.links_launch(bad_clubs, _strike_dict(LinksLaunch.Strike.new())).is_empty(),
			"links_launch without a table is empty")
	var bad := LinksLaunch.Strike.new()
	bad.club = 19
	_check(_physics.links_launch(clubs, _strike_dict(bad)).is_empty(),
			"links_launch with the putter is empty")


func _check_apply_lie() -> void:
	var fresh := LinksLaunch.Strike.new()
	fresh.face_error = 0.05
	var native2: Dictionary = _physics.links_apply_lie(_strike_dict(fresh),
			_lie_dict(LinksGround.surface_for_class(LinksGround.ROUGH)))
	var ns: Dictionary = native2.strike
	_check_near(ns.spin_scale, 0.406505, 1e-6, "rough spin")
	_check_near(ns.speed_scale, 0.927315, 1e-6, "rough speed")
	_check_near(ns.face_error, 0.05, 1e-9, "rough keeps the face")
	for c in [[0, 0.4, 1.5, 1.0], [3, 0.38, 1.25, 1.0], [10, 0.333333, 0.666667, 1.0],
			[-3, 0.7, 1.2, 1.0], [-5, 0.9, 1.0, 1.0], [-8, 0.705, 0.7, 0.73]]:
		var t := LinksLaunch.Strike.new()
		t.face_error = 0.05
		var out: Dictionary = _physics.links_apply_lie(_strike_dict(t),
				_lie_dict(LinksGround.surface_for_class(LinksGround.SAND)), c[0])
		var st: Dictionary = out.strike
		_check_near(st.face_error, 0.0, 1e-9, "sand drops the face error")
		_check_near(st.speed_scale, c[1], 1e-5, "sand speed %d" % c[0])
		_check_near(st.spin_scale, c[2], 1e-5, "sand spin %d" % c[0])
		_check_near(st.loft_scale, c[3], 1e-6, "sand loft %d" % c[0])


func _check_meter_contact() -> void:
	for c in [[16.0, 0, 0], [16.0, 1, 1], [16.0, 3, 0], [17.0, 3, 1], [-30.0, 3, -1], [10.0, 2, 0]]:
		_check(_physics.links_meter_contact(c[0], c[1]) == c[2], "meter contact %s" % [c])


func _check_apply_swing() -> void:
	var cases := [
		[LinksGround.ROUGH, 13, 3, false, -1, 100.0, 12345, false, false, 0.073820061, 98.9875, 0.011343904, 0.006179939, 0.306505, 0.897315, 1.0],
		[LinksGround.FAIRWAY, 0, 2, false, 1, 100.0, 777, false, false, 0.117637011, 98.105, 0.010139626, -0.037637011, 0.9, 0.902034979, 1.0],
		[LinksGround.DIRT, 7, 1, false, 2, 90.0, 99, false, false, 0.148869219, 90.0, 0.01, -0.068869219, 0.92, 0.9728, 1.0],
		[LinksGround.ROUGH, 11, 3, true, -2, 100.0, 5, false, false, 0.1, 100.0, 0.043633231, -0.06981317, 0.25, 0.927315, 0.95],
		[LinksGround.SAND, 17, 3, false, -1, 100.0, 42, true, false, 0.1, 94.8025, 0.0, 0.0, 1.416666667, 0.393333333, 1.0],
		[LinksGround.FAIRWAY, 0, 3, false, 1, 100.0, 2003, false, true, 0.116496095, 97.3625, 0.011466077, -0.036406095, 1.0, 1.0, 1.0],
	]
	for c in cases:
		var s := LinksLaunch.Strike.new()
		s.club = c[1]
		s.power = c[5]
		s.aim = 0.1
		s.face_error = 0.01
		s.path_error = -0.02
		var w := LinksLaunch.SwingInput.new()
		w.method = LinksLaunch.Method.MOUSE if c[3] else LinksLaunch.Method.POWERSTROKE
		w.skill = c[2]
		w.contact = c[4]
		w.mouse_face_deg = 2.5
		w.mouse_path_deg = -4.0
		w.mouse_loft = 0.95
		w.left_handed = c[7]
		w.teed_up = c[8]
		var rng := LinksLaunch.Rand.new(c[6])
		LinksLaunch.apply_swing(s, w, LinksGround.surface_for_class(c[0]), rng)
		var gd := [s.aim, s.power, s.face_error, s.path_error, s.spin_scale, s.speed_scale, s.loft_scale]
		var native: Dictionary = _physics.links_apply_swing(_strike_dict(_fresh_strike(c[1], c[5])),
				_swing_dict(w), _lie_dict(LinksGround.surface_for_class(c[0])), c[6])
		if native.is_empty():
			_failures += 1
			print("  FAIL: links_apply_swing empty for case %d" % cases.find(c))
			continue
		var ns: Dictionary = native.strike
		var got := [ns.aim, ns.power, ns.face_error, ns.path_error, ns.spin_scale, ns.speed_scale,
				ns.loft_scale]
		for i in got.size():
			_check_near(got[i], c[9 + i], 1e-6, "swing case %d value %d" % [cases.find(c), i])
			_check_near(got[i], gd[i], 1e-6, "swing case %d matches GDScript %d" % [cases.find(c), i])
		_check(int(native.rng_state) == rng.state, "swing case %d rand state" % cases.find(c))


static func _fresh_strike(club: int, power: float) -> LinksLaunch.Strike:
	var s := LinksLaunch.Strike.new()
	s.club = club
	s.power = power
	s.aim = 0.1
	s.face_error = 0.01
	s.path_error = -0.02
	return s


func _check_computer_miss() -> void:
	var cpu := [
		[80, 100, false, false, 12, false, LinksGround.FAIRWAY, 100.0, 300.0, 12345, 101.21875, 0.3125, 0.0],
		[70, 100, false, true, 0, false, LinksGround.FAIRWAY, 100.0, 1200.0, 777, 98.5175018, 0.0, 0.375],
		[60, 100, false, false, 3, false, LinksGround.ROUGH, 100.0, 600.0, 99, 103.9375, 0.0, 1.875],
		[95, 90, false, false, 8, false, LinksGround.SAND, 100.0, 450.0, 2003, 100.474998, 0.474999994, 0.0],
		[40, 100, true, false, 17, false, LinksGround.DEEP_GRASS, 60.0, 120.0, 5, 56.360939, 0.0, 3.9312501],
		[65, 100, false, false, 14, true, LinksGround.PATH, 30.0, 90.0, 42, 23.4375, 0.0, -1.125],
	]
	for c in cpu:
		var g := LinksLaunch.GolferRatings.even(c[0])
		g.max_power = c[1]
		g.steady = c[2]
		if c[3]:
			g.tee = 85
		var w := LinksLaunch.ComputerSwing.new()
		w.power = c[7]
		var rng := LinksLaunch.Rand.new(c[9])
		LinksLaunch.computer_miss(w, g, c[4], c[3], c[5], c[6], c[8], rng)
		var gd := [w.power, w.face_deg, w.path_deg]
		var native: Dictionary = _physics.links_computer_miss(
				{"power": c[7], "face_deg": 0.0, "path_deg": 0.0}, _ratings_dict(g), c[4], c[3], c[5],
				c[6], c[8], c[9])
		if native.is_empty():
			_failures += 1
			print("  FAIL: links_computer_miss empty for case %d" % cpu.find(c))
			continue
		var ns: Dictionary = native.swing
		var got := [ns.power, ns.face_deg, ns.path_deg]
		for i in got.size():
			_check_near(got[i], c[10 + i], 1e-4, "computer miss case %d value %d" % [cpu.find(c), i])
			_check_near(got[i], gd[i], 1e-5, "computer miss case %d matches GDScript %d" % [cpu.find(c), i])
		_check(int(native.rng_state) == rng.state, "computer miss case %d rand state" % cpu.find(c))


func _check_computer_putt_miss() -> void:
	var cputts := [
		[80, 90, false, 20.0, LinksGround.GREEN, 12345, 8.0, 7.75, 0.266666681],
		[95, 95, false, 40.0, LinksGround.FAIRWAY, 777, 15.0, 15.0375004, 0.0],
		[60, 85, false, 5.0, LinksGround.GREEN, 99, 3.0, 3.03686643, -0.0166666675],
		[40, 70, true, 10.0, LinksGround.ROUGH, 2003, 6.0, 5.66666651, 0.76666671],
		[85, 100, false, 4.5, LinksGround.GREEN, 42, 2.5, 2.5, 0.0],
		[70, 60, false, 2.6, LinksGround.GREEN, 5, 1.5, 1.5625, -0.0250000022],
	]
	for c in cputts:
		var cg := LinksLaunch.GolferRatings.new()
		cg.long_putts = c[0]
		cg.short_putts = c[1]
		cg.steady = c[2]
		var cw := LinksLaunch.ComputerSwing.new()
		cw.power = c[6]
		var rng := LinksLaunch.Rand.new(c[5])
		LinksLaunch.computer_putt_miss(cw, cg, c[4], c[3], rng)
		var native: Dictionary = _physics.links_computer_putt_miss(
				{"power": c[6], "face_deg": 0.0, "path_deg": 0.0}, _ratings_dict(cg), c[4], c[3], c[5])
		if native.is_empty():
			_failures += 1
			print("  FAIL: links_computer_putt_miss empty for case %d" % cputts.find(c))
			continue
		var ns: Dictionary = native.swing
		_check_near(ns.power, c[7], 1e-4, "computer putt %d power" % cputts.find(c))
		_check_near(ns.power, cw.power, 1e-6, "computer putt %d matches GDScript" % cputts.find(c))
		_check_near(deg_to_rad(ns.path_deg), c[8], 1e-5, "computer putt %d path" % cputts.find(c))
		_check(int(native.rng_state) == rng.state, "computer putt %d rand state" % cputts.find(c))


func _check_mouse_swing() -> void:
	var strokes := [
		[3, LinksMouse.Shot.FULL, 0, 1920, 11, 20, 12, 90, 0, -4.772966, 0.0, 0.0, 90, 0.297828, 31.626182, 0.0, 0.0, 0.157841, 0],
		[1, LinksMouse.Shot.FULL, 9, 1100, 5, 15, 10, 70, 3, -3.412456, -0.45, -0.27, 70, 0.152596, 11.886348, 0.004837,
				-0.117355, 0.071311, 0],
		[2, LinksMouse.Shot.PUTT, 19, 1920, 7, 12, 6, 40, -2, -0.592555, 0.24, 0.0, 40, 0.034813, 1.0, -0.360105,
				0.398950, 0.033288, 0],
		[0, LinksMouse.Shot.CHIP, 16, 800, 3, 10, 8, 50, 1, -0.884124, -0.04, 0.0, 50, 0.064996, 1.522239, 0.000077,
				-0.021463, 0.064996, 0],
		[3, LinksMouse.Shot.FULL, 4, 1920, 9, 30, 15, 110, -6, -8.128368, 1.8, 1.2, 127, 0.626433, 77.270356, -1.1742,
				-0.825252, 0.517093, 1],
		[2, LinksMouse.Shot.FULL, 12, 1920, 21, 25, 14, 100, 12, -7.405264, -2.16, -1.44, 127, 0.428111, 46.535126,
				0.244594, -0.477122, 0.355657, 0],
	]
	for c in strokes:
		var i := strokes.find(c)
		var mc := LinksMouse.MouseClub.new(c[0], c[1], c[2], LinksMouse.meter_for(c[3]))
		var mr := LinksLaunch.Rand.new(c[4])
		for k in c[5]:
			mc.step(0, c[6], mr)
		for k in 40:
			if mc.done():
				break
			mc.step(c[8], -c[7], mr)
		_check(mc.phase == LinksMouse.Phase.IMPACT, "mouse swing %d strikes" % i)
		if mc.phase != LinksMouse.Phase.IMPACT:
			continue
		var st := mc.stroke
		var state_before := mr.state
		var gd: LinksMouse.Outcome = LinksMouse.swing(st, mr)
		var native: Dictionary = _physics.links_mouse_swing(_stroke_dict(st), state_before)
		if native.is_empty():
			_failures += 1
			print("  FAIL: links_mouse_swing empty for case %d" % i)
			continue
		var out: Dictionary = native.outcome
		_check_near(out.power, c[14], 1e-5, "mouse swing %d power" % i)
		_check_near(out.face_deg, c[15], 1e-5, "mouse swing %d face" % i)
		_check_near(out.path_deg, c[16], 1e-5, "mouse swing %d path" % i)
		_check_near(out.loft, c[17], 1e-5, "mouse swing %d loft" % i)
		_check(bool(out.whiff) == gd.whiff and int(out.quality) == gd.quality,
				"mouse swing %d whiff/quality" % i)
		_check_near(out.power, gd.power, 1e-6, "mouse swing %d matches GDScript power" % i)
		_check_near(out.face_deg, gd.face_deg, 1e-6, "mouse swing %d matches GDScript face" % i)
		_check_near(out.path_deg, gd.path_deg, 1e-6, "mouse swing %d matches GDScript path" % i)
		_check_near(out.loft, gd.loft, 1e-6, "mouse swing %d matches GDScript loft" % i)
		_check(int(native.rng_state) == mr.state, "mouse swing %d rand state" % i)
	var wild := LinksMouse.Stroke.new()
	wild.drift = -19.0
	wild.down = 80
	wild.speed = 8.0
	var miss_gd: LinksMouse.Outcome = LinksMouse.swing(wild, LinksLaunch.Rand.new(1))
	var miss: Dictionary = _physics.links_mouse_swing(_stroke_dict(wild), 1)
	_check(not (miss.outcome as Dictionary).is_empty() and bool((miss.outcome as Dictionary).whiff)
			and (miss.outcome as Dictionary).power == 0.0, "mouse swing misses past 18")
	_check(miss_gd.whiff and miss_gd.power == 0.0, "mouse swing misses past 18 (GDScript)")


## The whole launch through OlcoreShotModel (native) against the inner
## LinksShotModel (GDScript), across clubs, lies, skills, computer and
## mouse swings. The native path must build the same BallState: the same
## draws, in the same order, from the same seed.
func _check_model_launch() -> void:
	var t := _synthetic_clubs()
	if t == null:
		_failures += 1
		print("  FAIL: synthetic club table not found")
		return
	var links := LinksShotModel.new(null, t)
	var model := OlcoreShotModel.new(links)
	var by_name := {}
	for c in Club.standard_set():
		by_name[c.short_name] = c
	# club, power, accuracy, aim, lie, computer, ratings, chip, mouse, skill, seed.
	var cases := [
		["Dr", 1.0, 0.0, 0.0, Surface.Type.TEE, false, false, false, false, 3, 12345],
		["7i", 0.8, 0.3, -5.0, Surface.Type.FAIRWAY, false, false, false, false, 3, 777],
		["PW", 0.6, -0.4, 10.0, Surface.Type.ROUGH, false, false, false, false, 1, 99],
		["SW", 0.7, 0.2, 0.0, Surface.Type.SAND, false, false, false, false, 2, 42],
		["Dr", 1.05, 0.0, 0.0, Surface.Type.TEE, false, false, false, false, 3, 2003],
		["5i", 0.9, -0.1, 3.0, Surface.Type.FAIRWAY, true, false, false, false, 3, 5],
		["7i", 0.9, 0.1, -3.0, Surface.Type.ROUGH, true, true, false, false, 3, 12345],
		["PW", 0.5, 0.0, 0.0, Surface.Type.FAIRWAY, true, true, true, false, 3, 777],
		["LW", 0.8, 0.0, 0.0, Surface.Type.FAIRWAY, false, false, true, false, 3, 99],
		["7i", 0.85, 0.25, 2.0, Surface.Type.FAIRWAY, false, false, false, true, 0, 42],
		["Pt", 0.5, 0.1, 0.0, Surface.Type.GREEN, false, false, false, false, 3, 12345],
		["Pt", 0.8, -0.2, 0.0, Surface.Type.GREEN, true, true, false, false, 3, 777],
		["Pt", 0.6, 0.0, 0.0, Surface.Type.GREEN, false, false, false, true, 2, 99],
	]
	for c in cases:
		var i := cases.find(c)
		links.skill = c[9]
		links.computer = c[5]
		links.computer_ratings = LinksLaunch.GolferRatings.even(80) if c[6] else null
		links.to_hole_m = 150.0
		links.chip = c[7]
		if c[8]:
			var mouse := LinksMouse.Outcome.new()
			mouse.power = 90.0
			mouse.face_deg = 2.0
			mouse.path_deg = -3.0
			links.mouse_swing = mouse
		else:
			links.mouse_swing = null
		model.setup = LinksLaunch.Setup.new()
		model.setup.face = 33
		model.setup.stance = 27
		model.setup.ball_position = 6
		model.backspin = 0
		var from := Vector3(10.0, 0.5, -20.0)
		links.rng = LinksLaunch.Rand.new(c[10])
		var native: BallState = model.launch(by_name[c[0]], c[1], c[2], c[3], c[4], from)
		var state_after_native: int = links.rng.state
		links.rng = LinksLaunch.Rand.new(c[10])
		var gd: BallState = links.launch(by_name[c[0]], c[1], c[2], c[3], c[4], from)
		_check_vec(native.velocity, gd.velocity, 1e-3, "model launch %d velocity" % i)
		_check_vec(native.spin, gd.spin, 1e-2, "model launch %d spin" % i)
		_check(native.on_ground == gd.on_ground, "model launch %d on_ground" % i)
		_check(native.position == gd.position, "model launch %d position" % i)
		_check(links.rng.state == state_after_native, "model launch %d rand state" % i)


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failures += 1
		print("  FAIL: %s" % what)


func _check_near(got: float, want: float, tol: float, what: String) -> void:
	if absf(got - want) > tol:
		_failures += 1
		print("  FAIL: %s: got %.6f want %.6f (tol %.6f)" % [what, got, want, tol])


func _check_vec(got: Vector3, want: Vector3, tol: float, what: String) -> void:
	_check_near(got.x, want.x, tol, what + " x")
	_check_near(got.y, want.y, tol, what + " y")
	_check_near(got.z, want.z, tol, what + " z")
