class_name RealCourseUpdate
extends Node
## "Update" on the Courses page: builds a saved real course again from the
## same place with the newest builder (RealCourseFetcher.BUILDER_VERSION),
## and saves it over the old file under the same name, so new detection,
## trees, walls and so on reach courses built before them. Changes made to
## the course in the designer are replaced, which the page says first.

signal progress(text: String)
## ok is false if the build failed or was cancelled; `text` says what happened.
signal finished(ok: bool, text: String)

## Seconds without any progress before an update is given up on. Waiting
## for a busy map server or a download still reports progress every frame,
## so this only trips when the build has truly stopped moving.
const STALL_SECS := 150.0
## Seconds Cancel waits for the build to stop before letting go of it.
const CANCEL_GRACE := 3.0

var fetcher: RealCourseFetcher
var busy := false
## The step shown last, and when (msec).
var step := ""
var started_ms := 0
var _last_progress_ms := 0
var _run := 0
var _path := ""
var _old: Dictionary = {}


func _ready() -> void:
	_new_fetcher()


func _new_fetcher() -> void:
	fetcher = RealCourseFetcher.new()
	add_child(fetcher)
	fetcher.progress.connect(_on_progress)
	fetcher.failed.connect(_on_failed)
	fetcher.built.connect(_on_built)


func _on_progress(text: String) -> void:
	step = text
	_last_progress_ms = Time.get_ticks_msec()
	progress.emit(text)


func _process(_delta: float) -> void:
	if busy and Time.get_ticks_msec() - _last_progress_ms > STALL_SECS * 1000.0:
		_let_go("The update stopped at \"%s\" and was given up on. The course is as it was; try again in a few minutes." % step.trim_suffix("..."))


## Records on a freshly built course what's needed to build it again: the
## place picked, the course's name in the map and the builder version.
static func stamp(c: DesignedCourse, place: Dictionary) -> void:
	c.source["place"] = {
		"name": str(place.get("name", "")),
		"lat": float(place.get("lat", 0.0)),
		"lon": float(place.get("lon", 0.0)),
		"box": (place.get("box", []) as Array).map(func(v: Variant) -> float: return float(v)) if place.get("box", []) is Array else [],
		"golf": bool(place.get("golf", false)),
	}
	c.source["map_name"] = c.course_name
	c.source["builder"] = RealCourseFetcher.BUILDER_VERSION
	c.source["built"] = Time.get_date_string_from_system()


## The place to build from: the one saved, or for a course built before
## places were saved, its centre (searched round, as for a picked point).
static func place_of(source: Dictionary, course_name: String) -> Dictionary:
	if source.get("place", null) is Dictionary:
		return source["place"]
	return {"name": course_name, "lat": float(source.get("lat", 0.0)), "lon": float(source.get("lon", 0.0)), "box": [], "golf": false}


## True if the course was built with an older builder than this one.
static func is_outdated(source: Dictionary) -> bool:
	return int(source.get("builder", 1)) < RealCourseFetcher.BUILDER_VERSION


## A line for the Courses page about when it was built.
static func age_note(source: Dictionary) -> String:
	var when := str(source.get("built", ""))
	var built := "Built %s" % when if not when.is_empty() else "Built"
	if is_outdated(source):
		return built + " with an older builder. Update it for the newest features."
	return built + " with the newest builder."


## Builds the course at `path` again. Ends with finished.
func run(path: String) -> void:
	if busy:
		return
	var c := DesignedCourse.load_file(path)
	if c == null or str(c.source.get("kind", "")) != "openstreetmap":
		finished.emit(false, "That isn't a real course, so there's nothing to update.")
		return
	busy = true
	_run += 1
	started_ms = Time.get_ticks_msec()
	_last_progress_ms = started_ms
	step = ""
	_path = path
	_old = {"name": c.course_name, "map_name": str(c.source.get("map_name", c.course_name)), "photo": str(c.source.get("photo", "")),
		"ground": str(c.source.get("ground", ""))}
	progress.emit("Updating %s..." % c.course_name)
	fetcher.build(place_of(c.source, c.course_name))


## Stops the update. If the build doesn't stop within CANCEL_GRACE seconds
## it is let go of anyway, so the page is never left waiting on it.
func cancel() -> void:
	if not busy:
		return
	fetcher.cancel()
	var run := _run
	get_tree().create_timer(CANCEL_GRACE).timeout.connect(func() -> void:
		if busy and run == _run:
			_let_go("Update cancelled; the course is as it was."))


## Ends the update now with `text`; the old build, if it ever finishes, is
## ignored and freed (a fresh fetcher takes its place).
func _let_go(text: String) -> void:
	var old := fetcher
	old.progress.disconnect(_on_progress)
	old.failed.disconnect(_on_failed)
	old.built.disconnect(_on_built)
	old.failed.connect(func(_t: String) -> void: old.queue_free())
	old.built.connect(func(_c: DesignedCourse, _s: Dictionary) -> void: old.queue_free())
	old.cancel()
	_new_fetcher()
	busy = false
	finished.emit(false, text)


func _on_failed(text: String) -> void:
	if not busy:
		return
	busy = false
	finished.emit(false, "Update cancelled; the course is as it was." if text == "Cancelled." else text + " The course is as it was.")


func _on_built(c: DesignedCourse, summary: Dictionary) -> void:
	busy = false
	# A club with several courses builds them all: keep the one this was.
	var pick := c
	var others: Array = summary.get("others", [])
	for o: DesignedCourse in [c] + others:
		if o.course_name == _old["map_name"]:
			pick = o
	if pick != c:
		# Its own area, so it can't use the first course's pictures.
		summary = summary.duplicate()
		summary.erase("photo")
		summary.erase("ground_cover")
	pick.course_name = _old["name"]
	for key in ["photo", "ground"]:
		pick.source.erase(key)
	keep_images(pick, summary, _path)
	# No new pictures (another course at the club): keep the old ones.
	if not pick.source.has("photo") and not pick.source.has("ground"):
		for key in ["photo", "ground"]:
			if not str(_old[key]).is_empty():
				pick.source[key] = _old[key]
	var err := pick.save_file(_path)
	if err != OK:
		finished.emit(false, "Couldn't save the updated course (%s)." % error_string(err))
		return
	finished.emit(true, "Updated %s: %d holes, %d areas, %d trees." % [pick.course_name, pick.holes.size(), pick.shapes.size(), pick.objects.size()])


## Saves a freshly built course's aerial photo and land-cover picture beside
## `target` (its .olc path) and points the course at them. Shared with the
## designer's Real course button.
static func keep_images(c: DesignedCourse, summary: Dictionary, target: String) -> void:
	var photo: Image = summary.get("photo", null)
	if photo != null:
		var file := target.get_basename().get_file() + ".photo.jpg"
		DirAccess.make_dir_recursive_absolute(DesignedCourse.FOLDER)
		if photo.save_jpg(DesignedCourse.FOLDER.path_join(file), 0.85) == OK:
			c.source["photo"] = file
		c.set_photo(photo)
	var cover: Image = summary.get("ground_cover", null)
	if photo == null and cover != null:
		var gfile := target.get_basename().get_file() + ".ground.png"
		DirAccess.make_dir_recursive_absolute(DesignedCourse.FOLDER)
		if cover.save_png(DesignedCourse.FOLDER.path_join(gfile)) == OK:
			c.source["ground"] = gfile
		c.set_ground_cover(cover)
