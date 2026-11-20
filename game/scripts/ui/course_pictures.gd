class_name CoursePictures
extends RefCounted
## Small pictures of the courses for the course pickers (round setup, the
## Courses page, Tournament and Career). A course is keyed by its course-list
## key: "" for Kettle Hollow, otherwise the path the setup list holds.
##
## The built-in courses ship a picture (assets/ui/menu/course_*.oljpg,
## rendered in the game by tests/course_pictures_render.gd). Every other
## course gets its picture the first time it is played: CourseSnapshot
## renders the opening hole from a camera high over the tee and saves it
## under user://course_pictures/. Until then the pickers draw a plain
## placeholder card (CoursePicture). Pictures are only ever made from the
## game's own rendering, never from map or satellite photos.

const DIR := "user://course_pictures"
const ART_DIR := "res://assets/ui/menu/"
## The saved picture's size (16:9).
const SIZE := Vector2i(480, 270)
const QUALITY := 0.86
## The built-in courses' pictures: key -> file in ART_DIR (no extension).
const BUILT_IN := {
	"": "course_kettle_hollow",
	"res://assets/courses/red_spire.olc": "course_red_spire",
	"res://assets/courses/vermilion_ridge.olc": "course_vermilion_ridge",
	"res://assets/courses/glacier_crown.olc": "course_glacier_crown",
	"res://assets/courses/ember_coast.olc": "course_ember_coast",
}

static var _cache := {}


## The course's picture, or null when it has none yet.
static func texture_for(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var tex: Texture2D = null
	var bytes := PackedByteArray()
	if BUILT_IN.has(key):
		bytes = FileAccess.get_file_as_bytes(ART_DIR + str(BUILT_IN[key]) + ".oljpg")
	if bytes.is_empty() and FileAccess.file_exists(file_for(key)):
		bytes = FileAccess.get_file_as_bytes(file_for(key))
	if not bytes.is_empty():
		var img := Image.new()
		if img.load_jpg_from_buffer(bytes) == OK:
			tex = ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## Where a played course's picture is saved.
static func file_for(key: String) -> String:
	return DIR.path_join(key.md5_text() + ".jpg")


## True when the course should be photographed on this round: it has no
## shipped picture, and its saved one is missing or older than the course
## file (an Update rebuilt it, or it was edited in the designer).
static func needs_picture(key: String) -> bool:
	if BUILT_IN.has(key):
		return false
	var file := file_for(key)
	if not FileAccess.file_exists(file):
		return true
	if FileAccess.file_exists(key):
		return FileAccess.get_modified_time(key) > FileAccess.get_modified_time(file)
	return false


## Saves `img` (any size, ideally twice SIZE for smooth edges) as the
## course's picture.
static func save(key: String, img: Image) -> Error:
	if img == null or img.is_empty():
		return ERR_INVALID_DATA
	DirAccess.make_dir_recursive_absolute(DIR)
	var pic := img.duplicate() as Image
	if pic.is_compressed():
		pic.decompress()
	pic.convert(Image.FORMAT_RGB8)
	pic.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
	var err := pic.save_jpg(file_for(key), QUALITY)
	_cache.erase(key)
	return err


## Drops a course's saved picture (the course was deleted).
static func forget(key: String) -> void:
	_cache.erase(key)
	if FileAccess.file_exists(file_for(key)):
		DirAccess.remove_absolute(file_for(key))
