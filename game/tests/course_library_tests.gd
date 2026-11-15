extends RefCounted
## Checks for the Courses page: CourseLibrary (adding, deleting, hiding),
## RealCourseUpdate (rebuilding a real course) and CoursesPanel. run_tests.gd
## calls run_all() and reports what it returns.

var failures: Array[String] = []


func run_all() -> Array[String]:
	_test_add_and_delete_design()
	_test_shared_photo()
	_test_added_links_course()
	_test_zip()
	_test_hiding()
	_test_real_update()
	_test_panel()
	return failures


func check(cond: bool, what: String) -> void:
	if not cond:
		failures.append(what)


static func _course(course_name: String) -> DesignedCourse:
	var c := DesignedCourse.blank(Vector2(120, 120))
	c.course_name = course_name
	return c


static func _kind_of(path: String) -> int:
	for e in CourseLibrary.entries(PackedStringArray()):
		if e["path"] == path:
			return int(e["kind"])
	return -1


func _test_add_and_delete_design() -> void:
	var r := CourseLibrary.add_design(_course("Library Test").to_json().to_utf8_buffer(), "Library Test.olc")
	check(r["ok"], "library: an .olc course is added")
	var path: String = (r["paths"] as PackedStringArray)[0] if r["ok"] else ""
	check(DesignedCourse.saved_paths().has(path), "library: the added course is among the saved courses")
	check(_kind_of(path) == CourseLibrary.Kind.DESIGN, "library: listed as your design")
	var built_in: Dictionary = CourseLibrary.entries(PackedStringArray())[0]
	check(built_in["kind"] == CourseLibrary.Kind.BUILT_IN and not built_in["deletable"] and not built_in["hideable"], "library: the built-in course can't be deleted or hidden")
	# Added again: a second file, not over the first.
	var again := CourseLibrary.add_design(_course("Library Test").to_json().to_utf8_buffer(), "Library Test.olc")
	check(again["ok"] and (again["paths"] as PackedStringArray)[0] != path, "library: adding the same course twice keeps both")
	for p in [path, (again["paths"] as PackedStringArray)[0]]:
		check(CourseLibrary.delete_course(p) == OK and not FileAccess.file_exists(p), "library: a design is deleted")
	check(not CourseLibrary.add_design("not a course".to_utf8_buffer(), "x.olc")["ok"], "library: a bad file isn't added")
	check(CourseLibrary.delete_course("res://assets/courses/home.olc") == ERR_UNAUTHORIZED, "library: nothing outside user://courses is deleted")


## A club's courses share one photo: it goes with the last of them.
func _test_shared_photo() -> void:
	var photo := DesignedCourse.FOLDER.path_join("Shared Test.photo.jpg")
	var img := Image.create(8, 8, false, Image.FORMAT_RGB8)
	DirAccess.make_dir_recursive_absolute(DesignedCourse.FOLDER)
	img.save_jpg(photo)
	var paths: Array[String] = []
	for n in ["Shared Test", "Shared Test East"]:
		var c := _course(n)
		c.source = {"kind": "openstreetmap", "photo": photo.get_file()}
		var p := c.save_path()
		c.save_file(p)
		paths.append(p)
	check(_kind_of(paths[0]) == CourseLibrary.Kind.REAL, "library: listed as a real course")
	CourseLibrary.delete_course(paths[0])
	check(FileAccess.file_exists(photo), "library: a shared photo stays while another course uses it")
	CourseLibrary.delete_course(paths[1])
	check(not FileAccess.file_exists(photo), "library: the photo goes with the last course using it")


func _test_added_links_course() -> void:
	var src_dir := "user://library_test_src"
	DirAccess.make_dir_recursive_absolute(src_dir)
	for f in ["TESTLIB.crz", "TESTLIB.sha", "OTHER.sha"]:
		var w := FileAccess.open(src_dir.path_join(f), FileAccess.WRITE)
		w.store_string("x")
		w.close()
	var r := CourseLibrary.add_file(src_dir.path_join("TESTLIB.crz"))
	var added := CourseLibrary.ADDED_FOLDER.path_join("TESTLIB.crz")
	check(r["ok"] and CourseLibrary.added_courses().has(added), "library: a .crz is added")
	check(FileAccess.file_exists(CourseLibrary.ADDED_FOLDER.path_join("TESTLIB.sha")), "library: its shadows come with it")
	check(not FileAccess.file_exists(CourseLibrary.ADDED_FOLDER.path_join("OTHER.sha")), "library: another course's files don't")
	var e: Dictionary = {}
	for row in CourseLibrary.entries(CourseLibrary.added_courses()):
		if row["path"] == added:
			e = row
	check(e.get("kind", -1) == CourseLibrary.Kind.ADDED and e.get("deletable", false), "library: an added course can be deleted")
	check(CourseLibrary.delete_course(added) == OK and not FileAccess.file_exists(CourseLibrary.ADDED_FOLDER.path_join("TESTLIB.sha")), "library: deleted with its companions")
	check(not CourseLibrary.add_file(src_dir.path_join("OTHER.sha"))["ok"], "library: a lone .sha isn't a course")
	for f in ["TESTLIB.crz", "TESTLIB.sha", "OTHER.sha"]:
		DirAccess.remove_absolute(src_dir.path_join(f))


func _test_zip() -> void:
	var zip_path := "user://library_test.zip"
	var z := ZIPPacker.new()
	z.open(zip_path)
	for f in ["pack/ZIPLIB.crz", "pack/ZIPLIB.tip", "pack/readme.txt", "__MACOSX/pack/._ZIPLIB.crz"]:
		z.start_file(f)
		z.write_file("x".to_utf8_buffer())
		z.close_file()
	z.start_file("Zip Design.olc")
	z.write_file(_course("Zip Design").to_json().to_utf8_buffer())
	z.close_file()
	z.close()
	var r := CourseLibrary.add_file(zip_path)
	check(r["ok"] and (r["paths"] as PackedStringArray).size() == 2, "library: a zip's course and design are added")
	check(FileAccess.file_exists(CourseLibrary.ADDED_FOLDER.path_join("ZIPLIB.tip")), "library: a zip's companions are unpacked")
	check(not FileAccess.file_exists(CourseLibrary.ADDED_FOLDER.path_join("readme.txt")), "library: other files in the zip are left")
	for p in r["paths"]:
		CourseLibrary.delete_course(p)
	DirAccess.remove_absolute(zip_path)


func _test_hiding() -> void:
	var p := "/games/links/Courses/HIDE.crz"
	CourseLibrary.set_hidden(p, true)
	CourseLibrary.set_hidden(p, true)
	check(CourseLibrary.hidden_paths().count(p) == 1, "library: hidden once")
	check(not CourseLibrary.shown(PackedStringArray([p, "/x/KEEP.crz"])).has(p), "library: hidden courses leave the lists")
	var e: Dictionary = CourseLibrary.entries(PackedStringArray([p]))[1 + PlaceholderCourseLoader.EPIC.size()]
	check(e["hidden"] and e["hideable"] and not e["deletable"], "library: the player's game files are hidden, never deleted")
	CourseLibrary.set_hidden(p, false)
	check(CourseLibrary.shown(PackedStringArray([p])).has(p), "library: shown again")


## Update keeps the course's name and file, takes the new build, and knows
## the place it came from.
func _test_real_update() -> void:
	var place := {"name": "Test Links", "lat": 51.5, "lon": -0.1, "box": ["51.49", "51.51", "-0.11", "-0.09"], "golf": true}
	var old := _course("Test Links")
	RealCourseUpdate.stamp(old, place)
	old.source["kind"] = "openstreetmap"
	old.source["builder"] = 1
	check(RealCourseUpdate.is_outdated(old.source), "update: an older build is outdated")
	check(RealCourseUpdate.age_note(old.source).contains("older"), "update: the page says so")
	var p2 := RealCourseUpdate.place_of(old.source, old.course_name)
	check(is_equal_approx(float(p2["lat"]), 51.5) and (p2["box"] as Array).size() == 4 and float((p2["box"] as Array)[0]) == 51.49, "update: the saved place")
	var legacy := RealCourseUpdate.place_of({"kind": "openstreetmap", "lat": 10.0, "lon": 20.0}, "Old One")
	check(legacy["name"] == "Old One" and not legacy["golf"] and float(legacy["lon"]) == 20.0, "update: a course built before places were saved is searched round its centre")
	old.course_name = "My Renamed Links"
	var path := old.save_path()
	old.save_file(path)
	var u := RealCourseUpdate.new()
	u.busy = true
	u._path = path
	u._old = {"name": old.course_name, "map_name": "Test Links", "photo": "", "ground": ""}
	var fresh := _course("Test Links")
	fresh.source["kind"] = "openstreetmap"
	RealCourseUpdate.stamp(fresh, place)
	fresh.shapes.append(CourseShape.oval(Surface.Type.GREEN, Vector2.ZERO, Vector2(10, 8), 0.0, 12))
	var other := _course("Test Links East")
	other.source["kind"] = "openstreetmap"
	var results: Array = []
	u.finished.connect(func(ok: bool, text: String) -> void: results.append([ok, text]))
	u._on_built(other, {"others": [fresh]})
	check(results.size() == 1 and results[0][0], "update: finished")
	var saved := DesignedCourse.load_file(path)
	check(saved != null and saved.course_name == "My Renamed Links", "update: the course keeps its name")
	check(saved != null and saved.shapes.size() == 1, "update: the club's matching course is the one kept")
	check(saved != null and not RealCourseUpdate.is_outdated(saved.source), "update: now built with the newest builder")
	check(DesignedCourse.saved_paths().count(path) == 1, "update: saved over the same file")
	u.free()
	CourseLibrary.delete_course(path)


func _test_panel() -> void:
	var panel := CoursesPanel.new()
	panel._ready()
	panel.open(PackedStringArray(["/games/links/Courses/PANEL.crz"]))
	check(panel._list.get_child_count() == panel.entries().size(), "courses page: a row per course")
	check(panel.entries().size() >= 2 + PlaceholderCourseLoader.EPIC.size(), "courses page: the built-in courses and the game's")
	panel.free()
