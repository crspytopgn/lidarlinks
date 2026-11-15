class_name CourseBuilding
extends RefCounted
## A building on a course (the clubhouse, houses along the boundary, barns),
## from OpenStreetMap's building outlines on a course built from a map.
## Drawn by CourseBuildings and solid to the ball. Heights are metres above
## the lowest ground under the outline.

## Roof shapes CourseBuildings can draw.
const ROOFS := ["flat", "gabled", "hipped"]
const MIN_HEIGHT := 2.2
const MAX_HEIGHT := 60.0

## The outline, (x, z) points, counter-clockwise or not, not closed.
var points := PackedVector2Array()
## Top of the walls (the eaves) and of the roof (the ridge).
var eave := 6.0
var ridge := 8.5
var roof := "gabled"
## What it is: "house", "clubhouse", "shed", "barn", "block" or "other";
## sets its windows and colours.
var kind := "house"


func _init(p_points := PackedVector2Array(), p_eave := 6.0, p_ridge := 8.5, p_roof := "gabled", p_kind := "house") -> void:
	points = p_points
	eave = clampf(p_eave, MIN_HEIGHT, MAX_HEIGHT)
	ridge = clampf(maxf(p_ridge, eave), eave, MAX_HEIGHT + 10.0)
	roof = p_roof if p_roof in ROOFS else "flat"
	kind = p_kind


func is_valid() -> bool:
	return points.size() >= 3 and absf(area()) >= 4.0


func area() -> float:
	var a := 0.0
	for i in points.size():
		var p := points[i]
		var q := points[(i + 1) % points.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


func bounds() -> Rect2:
	var r := Rect2(points[0], Vector2.ZERO)
	for p in points:
		r = r.expand(p)
	return r


## The smallest rectangle round the outline, at any angle:
## {"centre": Vector2, "axis": Vector2 (unit, along the long side),
## "half": Vector2 (half length along axis, half width)}.
func oriented_box() -> Dictionary:
	return min_box(points)


static func min_box(pts: PackedVector2Array) -> Dictionary:
	var hull := Geometry2D.convex_hull(pts)
	var best := {}
	var best_area := INF
	for i in hull.size() - 1:
		var e := hull[i + 1] - hull[i]
		if e.length_squared() < 1e-6:
			continue
		var u := e.normalized()
		var v := Vector2(-u.y, u.x)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in hull:
			var a := Vector2(p.dot(u), p.dot(v))
			lo = lo.min(a)
			hi = hi.max(a)
		var size := hi - lo
		if size.x * size.y < best_area:
			best_area = size.x * size.y
			var mid := (lo + hi) * 0.5
			var centre := u * mid.x + v * mid.y
			if size.x >= size.y:
				best = {"centre": centre, "axis": u, "half": size * 0.5}
			else:
				best = {"centre": centre, "axis": v, "half": Vector2(size.y, size.x) * 0.5}
	if best.is_empty():
		var r := Rect2(pts[0], Vector2.ZERO)
		for p in pts:
			r = r.expand(p)
		best = {"centre": r.get_center(), "axis": Vector2.RIGHT, "half": r.size * 0.5}
	return best


## How much of its oriented box the outline fills (1 for a rectangle).
func squareness() -> float:
	var b := oriented_box()
	var h: Vector2 = b["half"]
	return absf(area()) / maxf(4.0 * h.x * h.y, 0.01)


func to_dict() -> Dictionary:
	var flat := []
	for p in points:
		flat.append_array([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
	return {"points": flat, "eave": snappedf(eave, 0.1), "ridge": snappedf(ridge, 0.1), "roof": roof, "kind": kind}


static func from_dict(d: Dictionary) -> CourseBuilding:
	var pts := PackedVector2Array()
	var flat: Variant = d.get("points", [])
	if flat is Array:
		for i in range(0, (flat as Array).size() - 1, 2):
			pts.append(Vector2(float(flat[i]), float(flat[i + 1])))
	return CourseBuilding.new(pts, float(d.get("eave", 6.0)), float(d.get("ridge", 8.5)), str(d.get("roof", "flat")), str(d.get("kind", "house")))
