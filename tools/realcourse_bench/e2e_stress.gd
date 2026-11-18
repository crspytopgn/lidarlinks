extends SceneTree
# Dev tool: stresses the real-course fetcher on one saved place (PLACE, a
# search result as e2e.sh saves it; OVERPASS as e2e.sh serves it).
#   MODE=cancel   cancels builds at several points, then builds in full
#   MODE=offline  every download fails (a dead proxy)
#   MODE=tiles    the map answers, every other download fails
# Prints each outcome and how long it took; STRESS FAIL lines are problems.
var f: RealCourseFetcher
var place: Dictionary
var outcome := ""
var t_end := 0

func _initialize() -> void:
	place = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("PLACE")))
	f = RealCourseFetcher.new()
	f.servers = OS.get_environment("OVERPASS").split(",")
	var mode := OS.get_environment("MODE")
	if mode in ["offline", "tiles"]:
		f.configure_request = func(r: HTTPRequest) -> void:
			r.set_https_proxy("127.0.0.1", 9)
			if mode == "offline":
				r.set_http_proxy("127.0.0.1", 9)
	elif OS.get_environment("HTTPS_PROXY") != "":
		var ca := X509Certificate.new()
		ca.load("/root/.ccr/ca-bundle.crt")
		var hp := OS.get_environment("HTTPS_PROXY").trim_prefix("http://").trim_suffix("/")
		var host := hp.get_slice(":", 0) if not hp.contains("@") else hp.get_slice("@", 1).get_slice(":", 0)
		var port := int(hp.get_slice(":", hp.count(":")))
		f.configure_request = func(r: HTTPRequest) -> void:
			r.set_https_proxy(host, port)
			r.set_tls_options(TLSOptions.client(ca))
	root.add_child(f)
	f.failed.connect(func(t: String) -> void: outcome = "failed: " + t; t_end = Time.get_ticks_msec())
	f.built.connect(func(c: DesignedCourse, _s: Dictionary) -> void: outcome = "built %s, %d holes" % [c.course_name, c.holes.size()]; t_end = Time.get_ticks_msec())
	await process_frame
	if mode == "cancel":
		for delay: float in [0.3, 2.0, 5.0, 9.0, 14.0, 20.0, 30.0]:
			outcome = ""
			var t0 := Time.get_ticks_msec()
			f.build(place)
			await create_timer(delay).timeout
			var tc := Time.get_ticks_msec()
			if outcome.is_empty():
				f.cancel()
			while outcome.is_empty() and Time.get_ticks_msec() - tc < 30000:
				await process_frame
			print("cancel at %.1fs: %s after %d ms; busy %s; requests left %d" % [delay, outcome, t_end - tc, f.busy, f.get_child_count()])
			if outcome.is_empty() or (not outcome.begins_with("failed: Cancelled") and not outcome.begins_with("built")) or t_end - tc > 3000 or f.busy:
				print("STRESS FAIL cancel at %.1f s" % delay)
			await create_timer(1.0).timeout
			if f.get_child_count() > 0:
				print("STRESS FAIL %d requests still open after cancel" % f.get_child_count())
	outcome = ""
	var t1 := Time.get_ticks_msec()
	f.build(place)
	while outcome.is_empty() and Time.get_ticks_msec() - t1 < 900000:
		await process_frame
	print("%s build: %s in %d ms" % [mode, outcome, Time.get_ticks_msec() - t1])
	quit()
