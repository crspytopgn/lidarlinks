class_name CourseLibrary
extends RefCounted
## The player's courses as the Courses page (CoursesPanel) manages them:
## what each one is, adding course files, deleting the player's own copies
## and hiding the game's courses from the course lists. See
## docs/course-library.md.
##
## Built-in courses ship with the game and update with it, so they can't be
## deleted or hidden. Courses in the player's Links 2003 folder are their own
## game files: they are hidden, never deleted. Everything kept under
## user://courses (designs, real courses, added course files) can be deleted.

## Added Links course files (.crz, .rng and companions) on desktop.
const ADDED_FOLDER := "user://courses/added"
const SETTINGS_SECTION := "courses"

enum Kind { BUILT_IN, DESIGN, REAL, GAME, ADDED }

const KIND_LABELS := {
	Kind.BUILT_IN: "Built in",
	Kind.DESIGN: "Your design",
	Kind.REAL: "Real course",
	Kind.GAME: "Links 2003",
	Kind.ADDED: "Added course",
}


## One row per course: {"path", "name", "kind", "holes", "deletable",
## "hideable", "updatable", "hidden", "note"}. `game_courses` are the game's
## course files (desktop paths, or the browser's stored relative paths);
## `web_added` the ones among them the player added in the browser.
static func entries(game_courses: PackedStringArray, web_added := PackedStringArray()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append({"path": "", "name": PlaceholderCourseLoader.NAME, "kind": Kind.BUILT_IN, "holes": 9,
		"deletable": false, "hideable": false, "updatable": false, "hidden": false,
		"note": "Comes with the game and updates with it."})
	var hidden := hidden_paths()
	for p in game_courses:
		var added := p.begins_with(ADDED_FOLDER) or web_added.has(p)
		out.append({"path": p, "name": p.get_file().get_basename(), "kind": Kind.ADDED if added else Kind.GAME,
			"holes": 0, "deletable": added, "hideable": not added, "updatable": false,
			"hidden": hidden.has(p), "note": _game_note(added, hidden.has(p))})
	for p in DesignedCourse.saved_paths():
		out.append(design_entry(p))
	return out


static func _game_note(added: bool, hidden: bool) -> String:
	if added:
		return ""
	if hidden:
		return "Hidden from the course lists. Show puts it back."
	return "From your Links 2003 files. Hide takes it off the course lists; the file stays."


## The row for a saved .olc course, read without building its ground.
static func design_entry(path: String) -> Dictionary:
	var d := read_header(path)
	var source: Dictionary = d.get("source", {}) if d.get("source", {}) is Dictionary else {}
	var real := str(source.get("kind", "")) == "openstreetmap"
	var holes: int = (d.get("holes", []) as Array).size() if d.get("holes", []) is Array else 0
	var e := {"path": path, "name": str(d.get("name", path.get_file().get_basename())), "kind": Kind.REAL if real else Kind.DESIGN,
		"holes": holes, "deletable": true, "hideable": false, "updatable": real, "hidden": false, "note": ""}
	if d.is_empty():
		e["note"] = "This file can't be read."
	elif real:
		e["note"] = RealCourseUpdate.age_note(source)
	return e


## The course file's JSON as a Dictionary ({} if it isn't one).
static func read_header(path: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() > 2 and bytes[0] == 0x1f and bytes[1] == 0x8b:
		bytes = bytes.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


## Course files the player added on desktop, sorted.
static func added_courses() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(ADDED_FOLDER)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.get_extension().to_lower() in CourseFiles.EXTENSIONS:
			out.append(ADDED_FOLDER.path_join(f))
	out.sort()
	return out


# --- Hiding ----------------------------------------------------------------------

static func hidden_paths() -> PackedStringArray:
	var cfg := ConfigFile.new()
	cfg.load(GameFolder.SETTINGS_PATH)
	return PackedStringArray(cfg.get_value(SETTINGS_SECTION, "hidden", PackedStringArray()))


static func set_hidden(path: String, hide: bool) -> void:
	var list := hidden_paths()
	if hide and not list.has(path):
		list.append(path)
	elif not hide and list.has(path):
		list.remove_at(list.find(path))
	var cfg := ConfigFile.new()
	cfg.load(GameFolder.SETTINGS_PATH)
	cfg.set_value(SETTINGS_SECTION, "hidden", list)
	cfg.save(GameFolder.SETTINGS_PATH)


## `paths` without the hidden ones.
static func shown(paths: PackedStringArray) -> PackedStringArray:
	var hidden := hidden_paths()
	if hidden.is_empty():
		return paths
	var out := PackedStringArray()
	for p in paths:
		if not hidden.has(p):
			out.append(p)
	return out


# --- Deleting --------------------------------------------------------------------

## Deletes a course kept under user://courses: a saved design with its photo
## and ground pictures (unless another course shares them), or an added
## course file with its companions. Returns OK or the error.
static func delete_course(path: String) -> Error:
	if not path.begins_with(DesignedCourse.FOLDER + "/"):
		return ERR_UNAUTHORIZED
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var extra: Array[String] = []
	if path.get_extension().to_lower() == DesignedCourse.EXTENSION:
		var source: Variant = read_header(path).get("source", {})
		if source is Dictionary:
			var shared := _sidecars_in_use(path)
			for key in ["photo", "ground"]:
				var f := str((source as Dictionary).get(key, ""))
				if not f.is_empty() and not shared.has(f) and f.get_file() == f:
					extra.append(DesignedCourse.FOLDER.path_join(f))
	else:
		extra = companions(path)
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		return err
	for f in extra:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	return OK


## The photo and ground files other saved courses use (a club's courses
## share one photo).
static func _sidecars_in_use(except: String) -> Dictionary:
	var used := {}
	for p in DesignedCourse.saved_paths():
		if p == except:
			continue
		var source: Variant = read_header(p).get("source", {})
		if source is Dictionary:
			for key in ["photo", "ground"]:
				var f := str((source as Dictionary).get(key, ""))
				if not f.is_empty():
					used[f] = true
	return used


## Files beside a course file with its base name and a companion extension.
static func companions(path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return out
	var stem := path.get_file().get_basename().to_lower()
	for f in dir.get_files():
		if f.get_basename().to_lower() == stem and f.get_extension().to_lower() in CourseFiles.COMPANIONS:
			out.append(path.get_base_dir().path_join(f))
	return out


# --- Adding ------------------------------------------------------------------------

## What the desktop Add button takes.
const ADD_FILTERS := ["*.olc ; OpenLinks course", "*.crz, *.rng ; Links course", "*.zip ; Course download"]


## Adds the course file at `src` (desktop): an OpenLinks .olc (with its
## photo if it sits beside it), a Links .crz/.rng with its companions, or a
## course's .zip download. Returns {"ok", "message", "paths"}.
static func add_file(src: String) -> Dictionary:
	match src.get_extension().to_lower():
		DesignedCourse.EXTENSION, "json":
			return add_design(FileAccess.get_file_as_bytes(src), src.get_file(), src.get_base_dir())
		"crz", "rng":
			var files: Array[String] = [src]
			files.append_array(companions(src))
			var paths := PackedStringArray()
			for f in files:
				var to := ADDED_FOLDER.path_join(f.get_file())
				DirAccess.make_dir_recursive_absolute(ADDED_FOLDER)
				if DirAccess.copy_absolute(f, to) != OK:
					return {"ok": false, "message": "Couldn't copy %s." % f.get_file(), "paths": paths}
				if f == src:
					paths.append(to)
			return {"ok": true, "message": "Added %s." % src.get_file().get_basename(), "paths": paths}
		"zip":
			return add_zip(src)
	return {"ok": false, "message": "%s isn't a course file (.olc, .crz, .rng or .zip)." % src.get_file(), "paths": PackedStringArray()}


## Saves an .olc course's bytes under user://courses, under a free name.
## `photo_dir` is where to look for its photo and ground pictures.
static func add_design(bytes: PackedByteArray, file_name: String, photo_dir := "") -> Dictionary:
	if bytes.size() > 2 and bytes[0] == 0x1f and bytes[1] == 0x8b:
		bytes = bytes.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	var c := DesignedCourse.from_json(bytes.get_string_from_utf8())
	if c == null:
		return {"ok": false, "message": "%s isn't an OpenLinks course file." % file_name, "paths": PackedStringArray()}
	var target := c.save_path()
	if not photo_dir.is_empty() and photo_dir != DesignedCourse.FOLDER:
		for key in ["photo", "ground"]:
			var f := str(c.source.get(key, ""))
			if f.is_empty() or f.get_file() != f:
				continue
			var from := photo_dir.path_join(f)
			# Named after the new file, so it can't take another course's.
			var to_name := target.get_file().get_basename() + (".photo.jpg" if key == "photo" else ".ground.png")
			if FileAccess.file_exists(from) and DirAccess.copy_absolute(from, DesignedCourse.FOLDER.path_join(to_name)) == OK:
				c.source[key] = to_name
			else:
				c.source.erase(key)
	var err := c.save_file(target)
	if err != OK:
		return {"ok": false, "message": "Couldn't save %s (%s)." % [c.course_name, error_string(err)], "paths": PackedStringArray()}
	return {"ok": true, "message": "Added %s." % c.course_name, "paths": PackedStringArray([target])}


## Unpacks the course files in a .zip download into ADDED_FOLDER, and any
## .olc course among them as a design.
static func add_zip(src: String) -> Dictionary:
	var zip := ZIPReader.new()
	if zip.open(src) != OK:
		return {"ok": false, "message": "%s isn't a zip file." % src.get_file(), "paths": PackedStringArray()}
	var paths := PackedStringArray()
	var names := PackedStringArray()
	for entry in zip.get_files():
		var base := entry.get_file()
		var ext := base.get_extension().to_lower()
		if base.is_empty() or base.begins_with("._"):
			continue
		if ext == DesignedCourse.EXTENSION:
			var r := add_design(zip.read_file(entry), base)
			if r["ok"]:
				paths.append_array(r["paths"])
				names.append(base.get_basename())
		elif ext in CourseFiles.EXTENSIONS or ext in CourseFiles.COMPANIONS:
			DirAccess.make_dir_recursive_absolute(ADDED_FOLDER)
			var to := ADDED_FOLDER.path_join(base)
			var f := FileAccess.open(to, FileAccess.WRITE)
			if f == null:
				continue
			f.store_buffer(zip.read_file(entry))
			f.close()
			if ext in CourseFiles.EXTENSIONS:
				paths.append(to)
				names.append(base.get_basename())
	zip.close()
	if paths.is_empty():
		return {"ok": false, "message": "No course was found in %s." % src.get_file(), "paths": paths}
	return {"ok": true, "message": "Added %s." % ", ".join(names), "paths": paths}
