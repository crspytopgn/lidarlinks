class_name Biome
extends RefCounted
## Where in the world a designed course is set, for the courses that aren't
## temperate parkland (the epic built-in courses, docs/epic-courses.md):
## the colour and texture of the ground between the holes, whether grass
## grows there (desert hardpan, snow and lava are bare), and the colours of the real land round the course
## (Landscape). Saved per course as DesignedCourse.biome; "" is parkland,
## which keeps every default.
##
## The mown surfaces (tees, fairways, greens) stay green everywhere: desert
## and mountain courses are irrigated. What changes is the rough beyond the
## first band, the out of bounds and the land to the horizon.

const PARKLAND := ""
const DESERT := "desert"
const SNOW := "snow"
const TROPICAL := "tropical"
## A mountain course in summer (as the real Alpine courses are played):
## parkland turf, meadow and spruce woods round the holes, snow only on
## the high peaks across the valley.
const ALPINE := "alpine"

## Ground colours that replace DesignedTerrain.COLORS, by Surface.Type.
## Desert: the red sand of the Colorado Plateau's valley floors (sRGB about
## 190, 115, 75 in photos of Castle Valley and Monument Valley in sun), the
## semi-rough a sparser, drier green. Snow: old snow, blue-white.
static var GROUND := {
	DESERT: {
		Surface.Type.ROUGH: Color(0.26, 0.38, 0.15),
		Surface.Type.DEEP_ROUGH: Color(0.62, 0.36, 0.17),
		Surface.Type.OUT_OF_BOUNDS: Color(0.6, 0.35, 0.17),
	},
	SNOW: {
		Surface.Type.DEEP_ROUGH: Color(0.86, 0.89, 0.93),
		Surface.Type.OUT_OF_BOUNDS: Color(0.84, 0.87, 0.92),
	},
	# Tropical: a Hawaiian lava coast, the rough a lush green and beyond it
	# bare black a'a lava (sRGB about 40, 37, 35 in photos of the Kohala
	# coast courses).
	TROPICAL: {
		Surface.Type.ROUGH: Color(0.20, 0.42, 0.14),
		Surface.Type.DEEP_ROUGH: Color(0.15, 0.135, 0.13),
		Surface.Type.OUT_OF_BOUNDS: Color(0.14, 0.13, 0.125),
	},
}
## Surfaces drawn as bare ground (the sand texture, tinted by GROUND) with no
## grass blades on them: desert hardpan and snow.
static var BARE := {
	DESERT: [Surface.Type.DEEP_ROUGH, Surface.Type.OUT_OF_BOUNDS],
	SNOW: [Surface.Type.DEEP_ROUGH, Surface.Type.OUT_OF_BOUNDS],
	TROPICAL: [Surface.Type.DEEP_ROUGH, Surface.Type.OUT_OF_BOUNDS],
}
## How much of the deep rough's fescue and wild grass still grows: sparse
## bunch grass and scrub in the desert, none through snow.
static var WILD_GRASS := {DESERT: 0.12, SNOW: 0.0, TROPICAL: 1.0}
## The colour wild grass takes in each biome (dry sage scrub in the desert).
static var WILD_TINT := {DESERT: Color(0.4, 0.41, 0.3)}

## The land round the course (landscape.gdshader): ground on gentle slopes
## low and high, rock on steep ones (two tones, for the strata), plants on
## the gentle ground (how much), snow above a height (metres over the
## course; very high for none), and the sea below one (or none).
static var LAND := {
	PARKLAND: {low = Color(0.16, 0.24, 0.09), high = Color(0.2, 0.26, 0.12), rock = Color(0.38, 0.36, 0.33),
		rock2 = Color(0.3, 0.29, 0.27), plants = Color(0.07, 0.12, 0.05), cover = 0.6, snow_from = 99999.0, sea = -99999.0},
	DESERT: {low = Color(0.58, 0.34, 0.21), high = Color(0.48, 0.27, 0.17), rock = Color(0.52, 0.2, 0.1),
		rock2 = Color(0.66, 0.34, 0.18), plants = Color(0.2, 0.22, 0.13), cover = 0.35, snow_from = 99999.0, sea = -99999.0},
	SNOW: {low = Color(0.86, 0.89, 0.94), high = Color(0.92, 0.94, 0.97), rock = Color(0.32, 0.31, 0.31),
		rock2 = Color(0.42, 0.41, 0.4), plants = Color(0.05, 0.09, 0.06), cover = 0.55, snow_from = 40.0, sea = -99999.0},
	# Alpine summer: meadow on the valley sides, dark spruce and larch
	# forest, grey limestone and gneiss crags, snow above about 2,800 m (some
	# 1,300 m over a course at 1,500 m, as from Crans across the Rhone).
	ALPINE: {low = Color(0.2, 0.28, 0.11), high = Color(0.25, 0.28, 0.16), rock = Color(0.42, 0.41, 0.39),
		rock2 = Color(0.55, 0.54, 0.52), plants = Color(0.06, 0.1, 0.06), cover = 0.65, snow_from = 1300.0, sea = -99999.0},
	# Tropical: the Kohala coast's old lava under golden fountain grass
	# (a dark grey slab from the tee before: bare black a'a reads that way
	# only close up), greening up the mountain's wetter slopes.
	TROPICAL: {low = Color(0.34, 0.29, 0.19), high = Color(0.24, 0.3, 0.15), rock = Color(0.13, 0.12, 0.12),
		rock2 = Color(0.22, 0.2, 0.19), plants = Color(0.08, 0.16, 0.05), cover = 0.45, snow_from = 99999.0, sea = 0.0},
}


## The biome of the ground `terrain` plays on ("" unless it is a designed
## course that names one).
static func of(terrain: Object) -> String:
	if terrain is DesignedTerrain:
		return (terrain as DesignedTerrain).course.biome
	return PARKLAND


static func ground_color(biome: String, surface: int, fallback: Color) -> Color:
	var g: Dictionary = Biome.GROUND.get(biome, {})
	return g.get(surface, fallback)


static func is_bare(biome: String, surface: int) -> bool:
	var b: Array = Biome.BARE.get(biome, [])
	return b.has(surface)


static func wild_grass(biome: String) -> float:
	return float(Biome.WILD_GRASS.get(biome, 1.0))


static func land(biome: String) -> Dictionary:
	return Biome.LAND.get(biome, Biome.LAND[PARKLAND])
