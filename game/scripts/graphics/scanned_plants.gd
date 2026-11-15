class_name ScannedPlants
extends Node3D
## Real scanned plants (MegascansPlants, the private pack) round the tee and
## the green of the hole being played: beds of ferns, wild grasses,
## wildflowers and reeds on the long grass beside and behind the tee boxes
## and on the banks round the green, where the camera stands and the flat
## plant cards (FescueField) would read as cut-outs. Near the camera each
## plant is its detailed mesh, then a lighter one, which dissolves into
## the plant cards further off (shaders/scanned_plant.gdshader). Which plants
## grow follows the course's place (FreeAmbience's setting: parkland,
## woodland, seaside or desert): ferns where it is wooded and green, marram
## on a links, dry grasses and rushes in the desert; ferns under tree crowns
## and reeds by water anywhere they grow. Visual only. Off without a pack
## (always on the web) and at Low grass; density and reach follow the Grass
## setting.

## Per Grass level (Off, Low, Medium, High): plants per square metre of a
## bed, where the near mesh hands over to the mid one, and where the mid
## one has gone (the cards carry on from there).
const DENSITY := [0.0, 0.0, 0.8, 1.4]
const NEAR_END := [0.0, 0.0, 7.0, 11.0]
const FAR_END := [0.0, 0.0, 22.0, 30.0]
## How far round the tee and the green the beds grow (m), and how much of
## the long grass there is bed: soft-edged patches BED_SCALE m across.
const TEE_REACH := 30.0
const GREEN_REACH := 34.0
const BED_SCALE := 9.0
const BED_FROM := 0.56
## Plain rough grows beds only under trees and by water, this far from the
## line of play (tee to pin, m) and from the tee and the pin; the deep
## rough grows them anywhere.
const ROUGH_OFF_LINE := 16.0
const ROUGH_CLEAR := 18.0
## No bed within this of a mown or sandy surface (m), except reeds by water.
const EDGE_CLEAR := 1.4
## A stand of one plant is about this across (m), as plants grow in patches.
const STAND_M := 3.5
## What grows where, by FreeAmbience.Setting: groups (MegascansPlants.GROUPS)
## with their weights in the beds out in the open.
const FLORA := {
	FreeAmbience.Setting.PARKLAND: {"grass": 0.5, "fern": 0.25, "flower": 0.25},
	FreeAmbience.Setting.WOODLAND: {"fern": 0.6, "grass": 0.25, "flower": 0.15},
	FreeAmbience.Setting.SEASIDE: {"dune": 0.6, "grass": 0.3, "flower": 0.1},
	FreeAmbience.Setting.DESERT: {"dune": 0.4, "grass": 0.4, "wet": 0.2},
}
## Warm places (FreeAmbience.is_warm) dry the ferns out of the open beds.
const WARM_FERN := 0.3
## Under a tree crown (out to this many crown radii) the beds are ferns
## where ferns grow at all, and within REED_REACH m of water they are reeds.
const CROWN_REACH := 1.2
const REED_REACH := 3.0
## Plants per centre (tee or green) picked from each group, so a bed has a
## few kinds rather than one of everything.
const KINDS_PER_GROUP := 2
## Variants of each plant used (each is a draw call per cell and band).
const VARIANTS_USED := 2
## The beds are drawn in square cells this wide (m), each switched on only
## while the camera is near enough for it (visibility ranges).
const CELL := 12.0

var level := 0
var setting: FreeAmbience.Setting = FreeAmbience.Setting.PARKLAND
var warm := false
var instances := 0  ## plants placed for this hole
var _terrain: CourseTerrain


func _init() -> void:
	name = "ScannedPlants"


## True when the pack has 3D plants to grow.
static func available() -> bool:
	return not MegascansPlants.plants().is_empty()


## The kind of place for a course, as the ambience hears it.
func set_place(course: CourseData) -> void:
	var at := FreeAmbience.location_of(course)
	setting = FreeAmbience.setting_for_place(course.course_name if course != null else "", at)
	var place := FreeAmbience.known_place(course.course_name if course != null else "")
	if course != null and is_nan(course.location.x) and not place.is_empty() and place[3] >= 0:
		setting = place[3] as FreeAmbience.Setting
	warm = FreeAmbience.is_warm(at)


## Grows the beds round `hole`'s tees and green, replacing the last hole's.
func setup(hole: HoleData, grass_level: int) -> void:
	for c in get_children():
		c.queue_free()
	instances = 0
	level = clampi(grass_level, 0, DENSITY.size() - 1) if available() else 0
	if hole == null or hole.terrain == null or DENSITY[level] <= 0.0:
		return
	var t := hole.terrain
	_terrain = t
	var crowns := t.obstacles.canopies() if t.obstacles != null else PackedVector3Array()
	var line := [Vector2(hole.tee.x, hole.tee.z), Vector2(hole.pin.x, hole.pin.z)]
	var centres: Array[Vector3] = [hole.tee]
	for tee in hole.tees:
		if Vector2(tee.x - hole.tee.x, tee.z - hole.tee.z).length() > 12.0:
			centres.append(tee)
	var reach: Array[float] = []
	for c in centres:
		reach.append(TEE_REACH)
	centres.append(hole.pin)
	reach.append(GREEN_REACH)
	for i in centres.size():
		var spots := place(t, centres[i], reach[i], DENSITY[level], line, crowns, hole.number * 101 + i)
		_grow(spots, centres[i], reach[i], hole.number * 31 + i)


## The plants round one centre: {"x", "z", "group", "yaw", "scale", "pick"}
## per plant, deterministic for a seed.
func place(t: CourseTerrain, centre: Vector3, reach: float, density: float, line: Array, crowns: PackedVector3Array, seed: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Array[Dictionary] = []
	var near_crowns := PackedVector3Array()
	for c in crowns:
		if Vector2(c.x - centre.x, c.y - centre.z).length() < reach + c.z * CROWN_REACH:
			near_crowns.append(c)
	var tries := roundi(PI * reach * reach * density)
	for i in tries:
		var d := sqrt(rng.randf()) * reach
		var a := rng.randf() * TAU
		var x := centre.x + cos(a) * d
		var z := centre.z + sin(a) * d
		var yaw := rng.randf() * TAU
		var scale := rng.randf_range(0.8, 1.25)
		var pick := rng.randf()
		var group := spot_group(t, x, z, line, near_crowns, pick)
		if not group.is_empty():
			out.append({"x": x, "z": z, "group": group, "yaw": yaw, "scale": scale, "pick": pick})
	return out


## What grows at (x, z): a group of MegascansPlants.GROUPS, or "" for
## nothing (mown, in play, or between the beds).
func spot_group(t: CourseTerrain, x: float, z: float, line: Array, crowns: PackedVector3Array, pick: float) -> String:
	var s := t.surface_at(x, z)
	if s != Surface.Type.DEEP_ROUGH and s != Surface.Type.ROUGH:
		return ""
	var by_water := false
	for k in 6:
		var ang := k * TAU / 6.0
		var e := t.surface_at(x + cos(ang) * REED_REACH, z + sin(ang) * REED_REACH)
		if e == Surface.Type.WATER:
			by_water = true
			break
	var under := false
	for c in crowns:
		if Vector2(x - c.x, z - c.y).length() < c.z * CROWN_REACH:
			under = true
			break
	if s == Surface.Type.ROUGH:
		# The plain rough is kept: only the ground under trees and by water
		# grows plants there, and not right by the tee or the green.
		var p := Vector2(x, z)
		if t.first_cut_at(x, z) or not (under or by_water) or _off_line(p, line) < ROUGH_OFF_LINE \
				or p.distance_to(line[0]) < ROUGH_CLEAR or p.distance_to(line[1]) < ROUGH_CLEAR:
			return ""
	if not by_water:
		for k in 4:
			var ang := k * TAU / 4.0 + 0.4
			var e := t.surface_at(x + cos(ang) * EDGE_CLEAR, z + sin(ang) * EDGE_CLEAR)
			if e != Surface.Type.DEEP_ROUGH and e != Surface.Type.ROUGH:
				return ""
	# Beds: soft patches of the long grass, more of it under trees.
	var bed := FescueField._value_noise(Vector2(x, z) / BED_SCALE + Vector2(3.7, 1.9)) + (0.25 if under else 0.0)
	if bed < BED_FROM + 0.1 * pick:
		return ""
	if by_water and has_group("wet"):
		return "wet"
	if under and setting != FreeAmbience.Setting.DESERT and has_group("fern"):
		return "fern"
	return group_for(_stand_hash(x, z))


## The open-bed group for a stand's random number `r` in this place.
func group_for(r: float) -> String:
	var weights: Dictionary = FLORA[setting]
	var total := 0.0
	var w := {}
	for g: String in weights:
		if not has_group(g):
			continue
		var v: float = weights[g] * (WARM_FERN if g == "fern" and warm else 1.0)
		w[g] = v
		total += v
	if total <= 0.0:
		return ""
	var acc := 0.0
	for g: String in w:
		acc += w[g] / total
		if r < acc:
			return g
	return w.keys().back()


static func has_group(group: String) -> bool:
	return not MegascansPlants.for_group(group).is_empty()


static func _stand_hash(x: float, z: float) -> float:
	var stand := Vector2i(floori(x / STAND_M), floori(z / STAND_M))
	return float(absi(hash(stand)) % 10007) / 10007.0


## Distance (m) from p to the segment line[0]-line[1].
static func _off_line(p: Vector2, line: Array) -> float:
	var a: Vector2 = line[0]
	var b: Vector2 = line[1]
	var ab := b - a
	var u := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * u)


## Builds the MultiMeshes for one centre's spots: per plant, variant and
## level of detail, culled as a whole once the camera is past its reach.
func _grow(spots: Array[Dictionary], centre: Vector3, reach: float, seed: int) -> void:
	if spots.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "Beds"
	add_child(holder)
	# The kinds this centre grows: a couple per group, by seed.
	var kinds := {}
	for g: String in ["fern", "grass", "flower", "dune", "wet"]:
		var list := MegascansPlants.for_group(g)
		if list.is_empty():
			continue
		var picked: Array[Dictionary] = []
		var start := absi(hash([seed, g])) % list.size()
		for k in mini(KINDS_PER_GROUP, list.size()):
			picked.append(list[(start + k) % list.size()])
		kinds[g] = picked
	var bufs := {}  ## [cell, uid, variant] -> Array of floats, relative to the cell's middle
	var by_uid := {}
	var t := _terrain
	for s in spots:
		var picked: Array = kinds.get(s["group"], [])
		if picked.is_empty():
			continue
		var stand := _stand_hash(s["x"] + 1.7, s["z"] - 2.3)
		var plant: Dictionary = picked[int(stand * picked.size()) % picked.size()]
		var variant := int(float(s["pick"]) * 997.0) % mini(int(plant["variants"]), VARIANTS_USED)
		var x: float = s["x"]
		var z: float = s["z"]
		var cell := Vector2i(floori(x / CELL), floori(z / CELL))
		var mid := (Vector2(cell) + Vector2(0.5, 0.5)) * CELL
		var key := [cell, plant["uid"], variant]
		by_uid[plant["uid"]] = plant
		if not bufs.has(key):
			bufs[key] = []
		var yaw: float = s["yaw"]
		var sc: float = s["scale"]
		var c := t.ground_color_at(x, z)
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc)
		var y := t.height_at(x, z) - 0.02
		(bufs[key] as Array).append_array([
			basis.x.x, basis.y.x, basis.z.x, x - mid.x,
			basis.x.y, basis.y.y, basis.z.y, y - centre.y,
			basis.x.z, basis.y.z, basis.z.z, z - mid.y,
			c.r, c.g, c.b, s["pick"],
		])
	var near_end: float = NEAR_END[level]
	var far_end: float = FAR_END[level]
	var margin := CELL * 0.75
	for key: Array in bufs:
		var plant: Dictionary = by_uid[key[1]]
		var meshes := MegascansPlants.meshes(plant)
		if meshes.is_empty():
			continue
		var pair: Array = meshes[mini(key[2], meshes.size() - 1)]
		var buffer := PackedFloat32Array(bufs[key])
		var mid := (Vector2(key[0]) + Vector2(0.5, 0.5)) * CELL
		for band in 2:
			var mesh: ArrayMesh = pair[band]
			var mat := mesh.surface_get_material(0) as ShaderMaterial
			mat.set_shader_parameter("near_end", near_end)
			mat.set_shader_parameter("far_end", far_end)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = mesh
			@warning_ignore("integer_division")
			mm.instance_count = buffer.size() / 16
			mm.buffer = buffer
			var inst := MultiMeshInstance3D.new()
			inst.multimesh = mm
			# Only the detailed plants right by the camera cast shadows.
			inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if band == 0 and level >= 3 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# A cell draws a band only while some of it can be in that band
			# (the shader dithers each plant in and out within it), so the
			# far cells cost nothing and the near mesh is drawn only close by.
			if band == 0:
				inst.visibility_range_end = near_end + margin
			else:
				inst.visibility_range_begin = maxf(near_end - margin, 0.0)
				inst.visibility_range_end = far_end + margin
			inst.position = Vector3(mid.x, centre.y, mid.y)
			holder.add_child(inst)
			if band == 0:
				instances += mm.instance_count
