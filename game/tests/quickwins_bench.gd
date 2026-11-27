extends SceneTree
## Temporary quickwins micro-benchmark (not part of the suite): flat-shot
## sims and the hot helpers, printed as ms per call. Run:
##   godot --headless --path game -s res://tests/quickwins_bench.gd

func _initialize() -> void:
	_bench_flat_standin()
	_bench_flat_links()
	_bench_rng()
	_bench_surface()
	_bench_obstacles()
	_bench_f32()
	_bench_yard_scale()
	quit(0)


func _synthetic_aero_exe() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(64)
	out.fill(0xCD)
	for table in 2:
		var b := PackedByteArray()
		b.resize(LinksAero.TABLE_BYTES)
		b.encode_u32(0, 11)
		b.encode_u32(4, 14)
		var q := 8
		for i in 11:
			b.encode_float(q, 30.0 * i)
			q += 4
		for i in 14:
			b.encode_float(q, 10.0 * i)
			q += 4
		b.encode_u32(q, 0x00401000)
		b.encode_u32(q + 4, 0x0040102c)
		b.encode_u32(q + 8, 0)
		q += 12
		for row in 11:
			for col in 14:
				b.encode_float(q, 0.2 + 0.01 * row + 0.001 * col if table == 0 else 0.01 * col)
				q += 4
		out.append_array(b)
		var pad := PackedByteArray()
		pad.resize(40)
		pad.fill(0xCD)
		out.append_array(pad)
	return out


func _bench_flat_standin() -> void:
	var flat := FlatTerrain.new(Surface.Type.FAIRWAY, 0.0)
	var launch: BallState = BallPhysics.make_launch(60.0, 12.0, 0.0, 6000.0, 0.0)
	launch.position = Vector3.ZERO
	var n := 20
	var t0 := Time.get_ticks_usec()
	var r: ShotResult = null
	for i in n:
		r = BallPhysics.simulate_shot(launch, flat, false, Vector3.ZERO, Vector3.ZERO)
	var us := Time.get_ticks_usec() - t0
	print("BENCH flat stand-in driver: %.2f ms/shot (n=%d) carry=%.2f total=%.2f" % [us / 1000.0 / n, n, r.carry_m, r.total_m])


func _bench_flat_links() -> void:
	var aero := LinksAero.from_exe(_synthetic_aero_exe())
	var flat := FlatTerrain.new(Surface.Type.FAIRWAY, 0.0)
	var launch: BallState = BallPhysics.make_launch(60.0, 12.0, 0.0, 6000.0, 0.0)
	launch.position = Vector3.ZERO
	var n := 20
	var t0 := Time.get_ticks_usec()
	var r: ShotResult = null
	for i in n:
		r = BallPhysics.simulate_shot(launch, flat, false, Vector3.ZERO, Vector3.ZERO, aero)
	var us := Time.get_ticks_usec() - t0
	print("BENCH flat links driver: %.2f ms/shot (n=%d) carry=%.2f total=%.2f" % [us / 1000.0 / n, n, r.carry_m, r.total_m])


func _bench_rng() -> void:
	var rng := LinksGround.Rng.new(LinksGround.Rng.seed_for(10.0, 20.0))
	var n := 200000
	var t0 := Time.get_ticks_usec()
	var acc := 0.0
	for i in n:
		acc += rng.next_fraction()
	var us := Time.get_ticks_usec() - t0
	print("BENCH rng next_fraction: %.3f us/call (n=%d) acc=%.3f last=%.6f" % [float(us) / n, n, acc, rng.next_fraction()])
	var rng2 := LinksGround.Rng.new(12345)
	t0 = Time.get_ticks_usec()
	var v := 0
	for i in n:
		v = rng2.next_u32()
	us = Time.get_ticks_usec() - t0
	print("BENCH rng next_u32: %.3f us/call (n=%d) last=%d" % [float(us) / n, n, v])


func _bench_surface() -> void:
	var n := 200000
	var t0 := Time.get_ticks_usec()
	var p: LinksGround.Params = null
	for i in n:
		p = LinksGround.surface_for_class(LinksGround.ROUGH)
	var us := Time.get_ticks_usec() - t0
	print("BENCH surface_for_class hit: %.3f us/call (n=%d) restitution=%.4f" % [float(us) / n, n, p.restitution])


func _bench_obstacles() -> void:
	var f := ObstacleField.new()
	f.add_cylinder(0, 10, 0.5, 0, 5, ObstacleField.Kind.SOLID)
	f.add_box(Vector3(20, 1, 0), Basis.IDENTITY, Vector3(1, 1, 2), ObstacleField.Kind.SOLID)
	f.add_cylinder(-30, 0, 4, 2, 10, ObstacleField.Kind.CANOPY)
	f.finalize()
	var n := 50000
	var t0 := Time.get_ticks_usec()
	var hits := 0
	for i in n:
		if not f.segment_hit(Vector3(0, 1, 0), Vector3(0, 1, 20)).is_empty():
			hits += 1
	var us := Time.get_ticks_usec() - t0
	print("BENCH obstacle segment_hit hit: %.3f us/call (n=%d) hits=%d" % [float(us) / n, n, hits])
	t0 = Time.get_ticks_usec()
	var misses := 0
	for i in n:
		if f.segment_hit(Vector3(0, 6, 0), Vector3(0, 6, 20)).is_empty():
			misses += 1
	us = Time.get_ticks_usec() - t0
	print("BENCH obstacle segment_hit miss: %.3f us/call (n=%d) misses=%d" % [float(us) / n, n, misses])
	var flat := FlatTerrain.new(Surface.Type.FAIRWAY, 0.0)
	flat.obstacles = f
	t0 = Time.get_ticks_usec()
	var hm := 0
	for i in n:
		if flat.obstacle_hit(Vector3(0, 6, 0), Vector3(0, 6, 20)).is_empty():
			hm += 1
	us = Time.get_ticks_usec() - t0
	print("BENCH terrain obstacle_hit miss: %.3f us/call (n=%d) misses=%d" % [float(us) / n, n, hm])
	var hit := ObstacleField.Hit.new()
	t0 = Time.get_ticks_usec()
	var hm2 := 0
	for i in n:
		if not f.segment_hit_into(Vector3(0, 1, 0), Vector3(0, 1, 20), hit):
			hm2 += 1
	us = Time.get_ticks_usec() - t0
	print("BENCH obstacle segment_hit_into hit: %.3f us/call (n=%d) nohits=%d frac=%.3f" % [float(us) / n, n, hm2, hit.fraction])
	t0 = Time.get_ticks_usec()
	var hm3 := 0
	for i in n:
		if not f.segment_hit_into(Vector3(0, 6, 0), Vector3(0, 6, 20), hit):
			hm3 += 1
	us = Time.get_ticks_usec() - t0
	print("BENCH obstacle segment_hit_into miss: %.3f us/call (n=%d) nohits=%d" % [float(us) / n, n, hm3])
	t0 = Time.get_ticks_usec()
	var hm4 := 0
	for i in n:
		if not flat.obstacle_hit_into(Vector3(0, 6, 0), Vector3(0, 6, 20), hit):
			hm4 += 1
	us = Time.get_ticks_usec() - t0
	print("BENCH terrain obstacle_hit_into miss: %.3f us/call (n=%d) nohits=%d" % [float(us) / n, n, hm4])


func _bench_f32() -> void:
	var n := 200000
	var c := LinksGround.Ctx.new()
	var t0 := Time.get_ticks_usec()
	var acc := 0.0
	for i in n:
		acc += LinksGround._f32c(c, 1.0 / 1200.0)
	var us := Time.get_ticks_usec() - t0
	print("BENCH links_ground _f32c: %.3f us/call (n=%d) acc=%.3f" % [float(us) / n, n, acc])


## One full yard-scale build: the five carry_yards sims _step_yard_scale
## used to run, one a frame, every time the club or lie changed. A cache
## hit costs none of these (0 sims, just set_yard_scale with the stored
## arrays), so this is the per-revisit saving.
func _bench_yard_scale() -> void:
	var model := StandardShotModel.new()
	var seven: Club = null
	for c in Club.standard_set():
		if c.short_name == "7i":
			seven = c
	var n := 5
	var t0 := Time.get_ticks_usec()
	var total := 0.0
	for i in n:
		for v in [0.25, 0.5, 0.75, 1.0]:
			total += GolfRound.carry_yards(model, seven, Surface.Type.FAIRWAY, false, v)
	var us := Time.get_ticks_usec() - t0
	print("BENCH yard scale build (7i, 4 samples): %.1f ms/build (n=%d) total=%.1f yd" % [us / 1000.0 / n, n, total])
