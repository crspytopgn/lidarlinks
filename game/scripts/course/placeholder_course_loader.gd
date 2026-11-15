class_name PlaceholderCourseLoader
extends CourseLoader
## The built-in course, Kettle Hollow: a parkland nine laid on real ground
## (lidar of glacial farmland), so a round can be played before any
## original course can be read. Built by tools/homecourse/ into a designer
## course file (see docs/home-course.md), so it plays through the same
## DesignedTerrain as courses made in the designer and can be opened there.

const PATH := "placeholder://openlinks-nine"
const FILE := "res://assets/courses/home.olc"
const NAME := "Kettle Hollow"
## The epic built-in courses (docs/epic-courses.md, built by
## tools/homecourse/build_epic_course.py, or a real course's mapped layout
## dressed by tools/homecourse/dress_real_course.py): designer files played
## by DesignedCourseLoader, listed after Kettle Hollow. Path -> display name.
const EPIC := {
	"res://assets/courses/red_spire.olc": "Red Spire",
	"res://assets/courses/vermilion_ridge.olc": "Vermilion Ridge",
	"res://assets/courses/glacier_crown.olc": "Glacier Crown",
	"res://assets/courses/ember_coast.olc": "Ember Coast",
}

static var _parsed: DesignedCourse


func can_load(path: String) -> bool:
	return path == PATH or path.is_empty()


func load_course(_path: String) -> CourseData:
	var designed := source()
	if designed == null:
		push_error("The built-in course is missing: %s" % FILE)
		return CourseData.new()
	return designed.to_course_data()


## The built-in course as a designer course, parsed once.
static func source() -> DesignedCourse:
	if _parsed == null:
		_parsed = DesignedCourse.load_file(FILE)
		# The built-in course is the tour's showcase: dressed for an event.
		if _parsed != null:
			_parsed.tournament = true
	return _parsed
