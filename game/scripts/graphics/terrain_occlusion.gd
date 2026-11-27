class_name TerrainOcclusion
extends RefCounted
## Whether the ground hides a thing from a viewpoint: the terrain itself
## as an occluder (hollows, cliffs, the far side of a hill). A sight line
## counts as blocked only when the ground rises CLEARANCE above it at a
## sampled point, so a line that just grazes a ridge, or a ridge narrower
## than the sample step, never culls — those stay visible, and the cull is
## re-checked as the camera moves, so a thing hidden for a moment comes
## back the moment the camera rounds the hill. Nothing is culled near the
## camera (the caller keeps a minimum distance); this only ever hides
## things far enough away that a brief pop would read as the trees
## thinning into the haze.
##
## The tests use _RidgeTerrain (run_tests.gd): a 12 m ridge 15 m short of
## a 230 m target.

## Metres between height samples along a sight line: fine enough that a
## ridge a dozen metres wide is sampled on its crest, not straddled.
const STEP := 4.0
## Most samples on one sight line (past 320 m the step grows instead).
const MAX_SAMPLES := 80
## How far above the sight line the ground must rise to count as
## blocking it: covers the height grid's own steps and a ridge the
## samples straddle, and keeps a line that only grazes a crest visible.
const CLEARANCE := 2.0


## True when the ground between `from` and `to` rises `clearance` above
## the straight sight line between them, so `to` cannot be seen from
## `from`. False without a terrain, or over too short a sight line to
## sample. A sampled point that the ground clears is proof the line is
## blocked; a ridge the samples miss only ever leaves the thing visible.
static func hidden_by_terrain(terrain: CourseTerrain, from: Vector3, to: Vector3, clearance := CLEARANCE) -> bool:
	if terrain == null:
		return false
	var dist := Vector2(to.x - from.x, to.z - from.z).length()
	if dist < 1.0:
		return false
	var samples := clampi(ceili(dist / STEP), 4, MAX_SAMPLES)
	for i in range(1, samples):
		var t := float(i) / samples
		var line := lerpf(from.y, to.y, t)
		if terrain.height_at(lerpf(from.x, to.x, t), lerpf(from.z, to.z, t)) > line + clearance:
			return true
	return false


## True when a batch of things round `centre` (within `reach` metres of
## it, none taller than `height` above the ground there) is hidden from
## `camera`: the sight lines to the top of the centre and of the four
## points `reach` out along x and z must all be blocked. One point would
## hide a cell whose far trees still show over the crest; all five have
## to be blocked before the whole batch goes. Each point is judged by the
## ground under it, so a batch on a slope is not hidden by its low side
## nor kept by its high one.
static func batch_hidden(terrain: CourseTerrain, camera: Vector3, centre: Vector3, reach: float, height: float, clearance := CLEARANCE) -> bool:
	if terrain == null:
		return false
	var top := Vector3(centre.x, terrain.height_at(centre.x, centre.z) + height, centre.z)
	# The centre first: most batches are visible, and one sight line
	# settles those. Only a hidden centre pays for the four edges.
	if not hidden_by_terrain(terrain, camera, top, clearance):
		return false
	var points := [
		centre + Vector3(reach, 0.0, 0.0) + Vector3.UP * height,
		centre + Vector3(-reach, 0.0, 0.0) + Vector3.UP * height,
		centre + Vector3(0.0, 0.0, reach) + Vector3.UP * height,
		centre + Vector3(0.0, 0.0, -reach) + Vector3.UP * height,
	]
	# Each edge point is judged by the ground under it, so a batch on a
	# slope is not hidden by its low side nor kept by its high one.
	for p in points:
		var at := Vector3(p.x, terrain.height_at(p.x, p.z) + height, p.z)
		if not hidden_by_terrain(terrain, camera, at, clearance):
			return false
	return true
