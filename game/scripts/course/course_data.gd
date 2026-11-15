class_name CourseData
extends RefCounted
## A loaded course.

var course_name := ""
## Dressed for a tournament (grandstands, gallery ropes and crowds, when
## the broadcast look is on), or false for an everyday local club.
var tournament := true
var holes: Array[HoleData] = []
## Trees, plants, 3D objects and spectators read from the course file (null
## for courses that have none; their holes may list objects instead).
var objects: CourseObjects
## The course's horizon panorama (hills and trees round the course), or null.
var horizon: Image
## The cloud sky the course asks for: skyNN.btc in PANSKY.LIB (1 to 12), or
## 0 for none (CourseBackdrop then uses its default).
var sky := 0
## Where in the world the course is, (latitude, longitude) in degrees, for
## a course built from a real place; NAN when not known.
var location := Vector2(NAN, NAN)
## Where in the world it is set (Biome), and whether it draws the real land
## round it to the horizon (Landscape) in place of FarScenery's rings.
var biome := ""
var landscape := false
## Reads a named entry from the course file (for its ambient sounds); an
## empty Callable for courses without one.
var read_entry: Callable


func pars() -> Array[int]:
	var out: Array[int] = []
	for h in holes:
		out.append(h.par)
	return out
