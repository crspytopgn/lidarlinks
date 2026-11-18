extends SceneTree
# Dev tool (e2e.sh): builds one real course as the game does and audits it.
# Args: query. Env: SLUG names the output (/tmp/rc/SLUG.olc); OVERPASS is a
# comma-separated list of map servers (e2e.sh serves the OSM data locally);
# PLACE is a saved search result to build without searching; SEARCHOUT
# saves the first search result there and stops. Behind a proxy
# (HTTPS_PROXY, as in the cloud containers) it uses /root/.ccr/ca-bundle.crt.
var f: RealCourseFetcher
var max_gap := 0
var gap_step := ""
var last := 0
var step := ""
var t0 := 0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	f = RealCourseFetcher.new()
	if OS.get_environment("OVERPASS") != "":
		f.servers = OS.get_environment("OVERPASS").split(",")
	if OS.get_environment("HTTPS_PROXY") != "" and OS.get_environment("NOPROXY") == "":
		var ca := X509Certificate.new()
		ca.load("/root/.ccr/ca-bundle.crt")
		var hp := OS.get_environment("HTTPS_PROXY").trim_prefix("http://").trim_suffix("/")
		var host := hp.get_slice(":", 0) if not hp.contains("@") else hp.get_slice("@", 1).get_slice(":", 0)
		var port := int(hp.get_slice(":", hp.count(":")))
		f.configure_request = func(r: HTTPRequest) -> void:
			r.set_https_proxy(host, port)
			r.set_tls_options(TLSOptions.client(ca))
	root.add_child(f)
	process_frame.connect(_tick)
	f.progress.connect(func(t: String) -> void:
		if t.get_slice("(", 0) != step.get_slice("(", 0): print("  [%5.1fs] %s" % [(Time.get_ticks_msec() - t0) / 1000.0, t])
		step = t)
	f.search_failed.connect(func(t: String) -> void: print("FAILED ", t); _end(1))
	f.failed.connect(func(t: String) -> void: print("FAILED ", t); _end(1))
	f.found.connect(func(r: Array) -> void:
		for p in r.slice(0, 3): print("found ", p["golf"], " ", p["label"])
		if r.is_empty(): print("FAILED nothing found"); _end(1); return
		var pick: Dictionary = r[0]
		if OS.get_environment("SEARCHOUT") != "":
			var fa := FileAccess.open(OS.get_environment("SEARCHOUT"), FileAccess.WRITE)
			fa.store_string(JSON.stringify(pick))
			fa.close()
			_end(0)
			return
		t0 = Time.get_ticks_msec()
		f.built.connect(func(c: DesignedCourse, s: Dictionary) -> void:
			var ss := s.duplicate()
			ss.erase("photo"); ss.erase("ground_cover"); ss.erase("others")
			print("BUILT in %d ms: %s" % [Time.get_ticks_msec() - t0, ss])
			if s.has("photo"):
				var file := c.default_path().get_basename().get_file() + ".photo.jpg"
				DirAccess.make_dir_recursive_absolute(DesignedCourse.FOLDER)
				(s["photo"] as Image).save_jpg(DesignedCourse.FOLDER.path_join(file), 0.85)
				c.source["photo"] = file
			if s.has("ground_cover"):
				c.set_ground_cover(s["ground_cover"])
			c.save_file("/tmp/rc/" + OS.get_environment("SLUG") + ".olc")
			for o: DesignedCourse in s.get("others", []):
				print("  other course: %s, %d holes" % [o.course_name, o.holes.size()])
			var audit: GDScript = load(get_script().resource_path.get_base_dir().path_join("e2e_audit.gd"))
			audit.call("audit", c)
			_end(0))
		f.build(pick))
	await process_frame
	t0 = Time.get_ticks_msec()
	last = Time.get_ticks_msec()
	if OS.get_environment("PLACE") != "":
		var place: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("PLACE")))
		f.found.emit([place])
	else:
		f.search(a[0])

func _tick() -> void:
	var now := Time.get_ticks_msec()
	if now - last > max_gap and t0 > 0:
		max_gap = now - last
		gap_step = step
	last = now

func _end(code: int) -> void:
	print("MAXGAP %d ms during '%s'" % [max_gap, gap_step])
	quit(code)
