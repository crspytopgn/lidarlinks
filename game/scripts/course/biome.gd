class_name Biome
extends RefCounted
## Where in the world a designed course is set, for the courses that aren't
## temperate parkland (the epic built-in courses, docs/epic-courses.md):
## the colour and texture of the ground between the holes, whether grass
## grows there, and the colours of the real land round the course
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

## Ground colours that replace DesignedTerrain.COLORS, by Surface.Type.
## Desert: the red sand of the Colorado Plateau's valley floors (sRGB about
## 190, 115, 75 in photos of Castle Valley and Monument Valley in sun), the
## semi-rough a sparser, drier green. Snow: old snow, blue-white.
const GROUND := {
	DESERT: {
		Surface.Type.ROUGH: Color(0.26, 0.38, 0.15),
		Surface.Type.DEEP_ROUGH: Color(0.6, 0.36, 0.22),
		Surface.Type.OUT_OF_BOUNDS: Color(0.57, 0.34, 0.21),
	},
	SNOW: {
		Surface.Type.DEEP_ROUGH: Color(0.86, 0.89, 0.93),
		Surface.Type.OUT_OF_BOUNDS: Color(0.84, 0.87, 0.92),
	},
	TROPICAL: {
		Surface.Type.ROUGH: Color(0.20, 0.42, 0.14),
		Surface.Type.DEEP_ROUGH: Color(0.17, 0.36, 0.11),
	},
}
## Surfaces drawn as bare ground (the sand texture, tinted by GROUND) with no
## grass blades on them: desert hardpan and snow.
const BARE := {
	DESERT: [Surface.Type.DEEP_ROUGH, Surface.Type.OUT_OF_BOUNDS],
	SNOW: [Surface.Type.DEEP_ROUGH, Surface.Type.OUT_OF_BOUNDS],
}
## How much of the deep rough's fescue and wild grass still grows: sparse
## bunch grass and scrub in the desert, none through snow.
const WILD_GRASS := {DESERT: 0.12, SNOW: 0.0, TROPICAL: 1.0}
## The colour wild grass takes in each biome (dry sage scrub in the desert).
const WILD_TINT := {DESERT: Color(0.4, 0.41, 0.3)}

## The land round the course (landscape.gdshader): ground on gentle slopes
## low and high, rock on steep ones (two tones, for the strata), plants on
## the gentle ground (how much), snow above a height (metres over the
## course; very high for none), and the sea below one (or none).
const LAND := {
	PARKLAND: {low = Color(0.16, 0.24, 0.09), high = Color(0.2, 0.26, 0.12), rock = Color(0.38, 0.36, 0.33),
		rock2 = Color(0.3, 0.29, 0.27), plants = Color(0.07, 0.12, 0.05), cover = 0.6, snow_from = 99999.0, sea = -99999.0},
	DESERT: {low = Color(0.58, 0.34, 0.21), high = Color(0.52, 0.31, 0.2), rock = Color(0.52, 0.2, 0.1),
		rock2 = Color(0.66, 0.34, 0.18), plants = Color(0.2, 0.22, 0.13), cover = 0.35, snow_from = 99999.0, sea = -99999.0},
	SNOW: {low = Color(0.86, 0.89, 0.94), high = Color(0.92, 0.94, 0.97), rock = Color(0.32, 0.31, 0.31),
		rock2 = Color(0.42, 0.41, 0.4), plants = Color(0.05, 0.09, 0.06), cover = 0.55, snow_from = 40.0, sea = -99999.0},
	TROPICAL: {low = Color(0.14, 0.3, 0.09), high = Color(0.18, 0.32, 0.12), rock = Color(0.13, 0.12, 0.12),
		rock2 = Color(0.22, 0.2, 0.19), plants = Color(0.05, 0.14, 0.04), cover = 0.8, snow_from = 99999.0, sea = 0.0},
}


## The biome of the ground `terrain` plays on ("" unless it is a designed
## course that names one).
static func of(terrain: Object) -> String:
	if terrain is DesignedTerrain:
		return (terrain as DesignedTerrain).course.biome
	return PARKLAND


static func ground_color(biome: String, surface: int, fallback: Color) -> Color:
	var g: Dictionary = GROUND.get(biome, {})
	return g.get(surface, fallback)


static func is_bare(biome: String, surface: int) -> bool:
	var b: Array = BARE.get(biome, [])
	return b.has(surface)


static func wild_grass(biome: String) -> float:
	return float(WILD_GRASS.get(biome, 1.0))


static func land(biome: String) -> Dictionary:
	return LAND.get(biome, LAND[PARKLAND])
