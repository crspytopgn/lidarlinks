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

var fetcher: RealCourseFetcher
var busy := false
var _path := ""
var _old: Dictionary = {}


func _ready() -> void:
	fetcher = RealCourseFetcher.new()
	add_child(fetcher)
	fetcher.progress.connect(progress.emit)
	fetcher.failed.connect(_on_failed)
	fetcher.built.connect(_on_built)


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
	_path = path
	_old = {"name": c.course_name, "map_name": str(c.source.get("map_name", c.course_name)), "photo": str(c.source.get("photo", "")),
		"ground": str(c.source.get("ground", ""))}
	progress.emit("Updating %s..." % c.course_name)
	fetcher.build(place_of(c.source, c.course_name))


func cancel() -> void:
	fetcher.cancel()


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
