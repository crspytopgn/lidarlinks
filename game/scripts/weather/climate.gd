class_name Climate
extends RefCounted
## The weather a course gets, from where it is in the world: its climate
## zone (from latitude and longitude, the kind of place it is and its biome)
## and the month. Each zone has summer and winter values, eased between by
## the month (the southern hemisphere's summer is in January). The numbers
## are rounded climate normals for a typical golf course in each zone (days
## with rain, cloud cover, mean wind at 10 m, morning fog, daytime high), in
## our own words from public climate summaries; Links 2003 had no weather of
## its own beyond the wind.

enum Zone { TEMPERATE, MARITIME, CONTINENTAL, SUBTROPICAL, MEDITERRANEAN, DESERT, TROPICAL, ALPINE }

const ZONE_NAMES := ["Temperate", "Maritime", "Continental", "Humid subtropical", "Mediterranean", "Desert", "Tropical trade wind", "Mountain"]

## Per zone, [summer, winter] for: cloud (0 clear to 1 overcast, the mean),
## rain (chance a round is wet), drizzle (of wet rounds, the share that are
## drizzle rather than rain), wind (mean m/s at 10 m), fog (chance of a
## misty round), temp (daytime high, degrees C).
const NORMALS := {
	Zone.TEMPERATE: {cloud = [0.45, 0.65], rain = [0.25, 0.35], drizzle = [0.5, 0.6], wind = [3.5, 4.5], fog = [0.08, 0.18], temp = [23.0, 7.0]},
	Zone.MARITIME: {cloud = [0.6, 0.75], rain = [0.35, 0.5], drizzle = [0.65, 0.55], wind = [4.5, 6.5], fog = [0.1, 0.15], temp = [18.0, 7.0]},
	Zone.CONTINENTAL: {cloud = [0.4, 0.6], rain = [0.3, 0.25], drizzle = [0.3, 0.5], wind = [3.5, 4.8], fog = [0.08, 0.12], temp = [28.0, 1.0]},
	Zone.SUBTROPICAL: {cloud = [0.45, 0.4], rain = [0.35, 0.22], drizzle = [0.2, 0.45], wind = [3.0, 4.0], fog = [0.06, 0.14], temp = [32.0, 16.0]},
	Zone.MEDITERRANEAN: {cloud = [0.12, 0.45], rain = [0.03, 0.25], drizzle = [0.5, 0.4], wind = [4.0, 4.0], fog = [0.22, 0.12], temp = [26.0, 15.0]},
	Zone.DESERT: {cloud = [0.1, 0.22], rain = [0.04, 0.07], drizzle = [0.2, 0.4], wind = [3.8, 3.2], fog = [0.0, 0.02], temp = [40.0, 19.0]},
	Zone.TROPICAL: {cloud = [0.35, 0.42], rain = [0.18, 0.28], drizzle = [0.6, 0.5], wind = [6.0, 5.5], fog = [0.0, 0.02], temp = [30.0, 27.0]},
	Zone.ALPINE: {cloud = [0.45, 0.6], rain = [0.3, 0.2], drizzle = [0.4, 0.5], wind = [3.5, 4.5], fog = [0.15, 0.2], temp = [22.0, -2.0]},
}
## A course by the sea is windier (sea breezes, no shelter) and mistier.
const SEASIDE_WIND := 1.3
const SEASIDE_FOG := 1.4


## The climate zone of a course at `at` (latitude, longitude; NAN when not
## known), of kind `setting` (FreeAmbience.Setting) and biome (Biome).
static func zone_for(at: Vector2, setting: int, biome: String) -> Zone:
	if biome == Biome.SNOW or biome == Biome.ALPINE:
		return Zone.ALPINE
	if biome == Biome.DESERT or setting == FreeAmbience.Setting.DESERT:
		return Zone.DESERT
	if biome == Biome.TROPICAL:
		return Zone.TROPICAL
	if is_nan(at.x):
		return Zone.TEMPERATE
	var lat := at.x
	var lon := at.y
	var alat := absf(lat)
	if alat < 23.5:
		return Zone.TROPICAL
	# North America.
	if lon < -50.0 and lat > 0.0:
		if lon < -104.0 and lon > -117.0 and lat > 36.0:
			return Zone.ALPINE  # the Rockies and the high basins (Banff, Castle Pines)
		if lon <= -117.0:
			return Zone.MARITIME if lat > 42.0 else Zone.MEDITERRANEAN  # the Pacific coast
		if lon < -104.0:
			return Zone.DESERT if lat < 36.0 else Zone.CONTINENTAL
		return Zone.CONTINENTAL if lat > 37.0 else Zone.SUBTROPICAL
	# Europe and North Africa.
	if lon > -25.0 and lon < 45.0 and lat > 0.0:
		if lat < 44.0:
			return Zone.MEDITERRANEAN
		if lon < 10.0:
			return Zone.MARITIME
		return Zone.CONTINENTAL
	# Australia and New Zealand.
	if lat < 0.0 and lon > 110.0:
		if lon > 165.0:
			return Zone.MARITIME if lat < -38.0 else Zone.SUBTROPICAL  # New Zealand
		return Zone.SUBTROPICAL if lat > -34.0 else Zone.MEDITERRANEAN
	# East Asia.
	if lon > 100.0 and lat > 0.0:
		return Zone.SUBTROPICAL if lat < 34.0 else Zone.CONTINENTAL
	return Zone.TEMPERATE


## How far into summer `month` (1 to 12) is at latitude `lat`: 1 at
## midsummer (July north, January south), 0 at midwinter. NAN latitude
## counts as northern.
static func summer(month: int, lat: float) -> float:
	var peak := 1.0 if not is_nan(lat) and lat < 0.0 else 7.0
	return 0.5 + 0.5 * cos(TAU * (float(month) - peak) / 12.0)


## The zone's normals for `month`: cloud, rain, drizzle, wind (m/s), fog
## and temp, eased between summer and winter; a seaside course gets more
## wind and fog.
static func normals(zone: Zone, month: int, lat: float, seaside := false) -> Dictionary:
	var s := summer(month, lat)
	var z: Dictionary = NORMALS[zone]
	var out := {}
	for k: String in z:
		var pair: Array = z[k]
		out[k] = lerpf(float(pair[1]), float(pair[0]), s)
	if seaside:
		out.wind = float(out.wind) * SEASIDE_WIND
		out.fog = minf(float(out.fog) * SEASIDE_FOG, 0.5)
	return out


## The zone and normals for a course this month (the player's clock).
static func for_course(course: CourseData, month := 0) -> Dictionary:
	var at := FreeAmbience.location_of(course)
	var setting := FreeAmbience.setting_for_place(course.course_name, at) if course != null else FreeAmbience.Setting.PARKLAND
	var place := FreeAmbience.known_place(course.course_name) if course != null else []
	if course != null and is_nan(course.location.x) and not place.is_empty() and int(place[3]) >= 0:
		setting = int(place[3]) as FreeAmbience.Setting
	if month <= 0:
		month = int(Time.get_date_dict_from_system().month)
	var zone := zone_for(at, setting, course.biome if course != null else "")
	var n := normals(zone, month, at.x, setting == FreeAmbience.Setting.SEASIDE)
	n.zone = zone
	n.month = month
	n.lat = at.x
	n.lon = at.y
	return n
