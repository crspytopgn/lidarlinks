class_name NativeGrass
extends RefCounted
## The unmown native grass between the holes, read from the course's aerial
## photo. OpenStreetMap maps a course's fairways, greens and bunkers but
## seldom the fescue round them, so a links or dune course (Whistling
## Straits' 1,400 bunkers sit in it) came out as bunkers on a mown lawn.
## In the photo the fescue is straw and olive beside the mown grass's
## green: cells of the course whose colour is that much yellower than its
## fairways, and not dark (trees, shade) or grey (sand, paths, water),
## become deep rough, drawn as tall fescue. The fairways, greens, tees,
## bunkers and mapped rough are painted over it, so only the ground the map
## leaves out takes it.
##
## Usage: new(), then rows() a band at a time (a big course has a quarter
## of a million cells), then rings() for the outlines.

const CELL := 4.0  ## metres per cell
const HUE_DROP := 0.045  ## how much yellower than the fairways (hue, 0..1)
const MIN_VALUE := 0.3  ## darker is trees or shade
const MAX_VALUE := 0.85  ## brighter is sand or paths
const MIN_SAT := 0.14  ## greyer is sand, paths or water
const MIN_CELLS := 40  ## smallest patch kept (640 m2)
const MIN_SHARE := 0.04  ## of the course's cells, or none is taken

## What is looked for: STRAW (fescue, meadow: lighter than the fairways)
## or SCRUB (scrub, heather, sage: darker, browner or purple, Torrey Pines'
## canyons, Sunningdale's heather), drawn with its own cover.
enum Kind { STRAW, SCRUB }
const SCRUB_MIN_VALUE := 0.15  ## darker is woods' shade
const SCRUB_DARKER := 0.07  ## than the fairways
const SCRUB_GREYER := 0.7  ## of the fairways' saturation, at most
const SCRUB_MIN_SAT := 0.06  ## greyer is rock, tarmac, water

var kind := Kind.STRAW
var photo: Image
var area: Rect2
var boundary: Array[PackedVector2Array] = []
var grass_hue := 0.0
var grass_sat := 0.0
var grass_val := 0.0
var cols := 0
var rows_n := 0
var mask := PackedByteArray()
var _found := 0


## `grass` are course points on fairways, for the mown grass's colour;
## without any (or a photo) nothing is found.
func _init(p_photo: Image, p_area: Rect2, p_boundary: Array[PackedVector2Array], grass: PackedVector2Array, p_kind := Kind.STRAW) -> void:
	kind = p_kind
	photo = p_photo
	area = p_area
	boundary = p_boundary
	cols = maxi(1, ceili(area.size.x / CELL))
	rows_n = maxi(1, ceili(area.size.y / CELL))
	mask.resize(cols * rows_n)
	if photo == null or photo.is_empty() or grass.is_empty():
		cols = 0
		rows_n = 0
		return
	var hues := PackedFloat32Array()
	var sats := PackedFloat32Array()
	var vals := PackedFloat32Array()
	for p in grass:
		var c := _colour(p)
		if c.s > MIN_SAT:
			hues.append(c.h)
			sats.append(c.s)
			vals.append(c.v)
	if hues.is_empty():
		cols = 0
		rows_n = 0
		return
	hues.sort()
	sats.sort()
	vals.sort()
	grass_hue = hues[hues.size() / 2]
	grass_sat = sats[sats.size() / 2]
	grass_val = vals[vals.size() / 2]


## True when there is anything to read.
func ready() -> bool:
	return cols > 0


## Reads rows j0 to j1 of cells.
func rows(j0: int, j1: int) -> void:
	for j in range(j0, mini(j1, rows_n)):
		var z := area.position.y + (j + 0.5) * CELL
		for span in _inside(z):
			var i0 := maxi(0, floori((span.x - area.position.x) / CELL))
			var i1 := mini(cols - 1, floori((span.y - area.position.x) / CELL))
			for i in range(i0, i1 + 1):
				var p := Vector2(area.position.x + (i + 0.5) * CELL, z)
				var col := _colour(p)
				if is_scrub(col, grass_sat, grass_val) if kind == Kind.SCRUB else is_native(col, grass_hue):
					mask[j * cols + i] = 1
					_found += 1


## True for a photo colour that reads as native grass beside mown grass of
## hue `grass`.
static func is_native(c: Color, grass: float) -> bool:
	return c.v >= MIN_VALUE and c.v <= MAX_VALUE and c.s >= MIN_SAT and c.h < grass - HUE_DROP and c.h > 0.05


## True for a photo colour that reads as scrub, sage or heather beside mown
## grass of saturation `sat` and value `val`: darker and greyer than it, but
## not as dark as the woods' shade. (Its hue says little: Torrey Pines'
## canyon sage is greener than the fairways in the photo, heather purple.)
static func is_scrub(c: Color, sat: float, val: float) -> bool:
	return c.v >= SCRUB_MIN_VALUE and c.v <= val - SCRUB_DARKER and c.s >= SCRUB_MIN_SAT and c.s <= sat * SCRUB_GREYER


## The cover a scrub patch is drawn with: heather where it is purple or red
## brown, scrub otherwise.
func cover_of(ring: PackedVector2Array) -> String:
	var b := Rect2(ring[0], Vector2.ZERO)
	for q in ring:
		b = b.expand(q)
	var purple := 0
	var n := 0
	for k in 25:
		var p := b.position + b.size * Vector2((k % 5 + 0.5) / 5.0, (k / 5 + 0.5) / 5.0)
		if Geometry2D.is_point_in_polygon(p, ring):
			n += 1
			var c := _colour(p)
			if c.h > 0.8 or c.h < 0.08:
				purple += 1
	return "heath" if n > 0 and purple * 2 > n else "scrub"


## The outlines of the patches found, outer rings and the mown islands in
## them ({"rings", "islands"}); empty when too little of the course is
## native (a parkland course with a few brown patches).
func rings() -> Dictionary:
	var outer: Array[PackedVector2Array] = []
	var islands: Array[PackedVector2Array] = []
	var out := {"rings": outer, "islands": islands}
	if not ready():
		return out
	var inside := 0
	for j in rows_n:
		var z := area.position.y + (j + 0.5) * CELL
		for span in _inside(z):
			inside += maxi(0, floori((span.y - span.x) / CELL))
	_tidy()
	var kept := 0
	for v in mask:
		kept += v
	if inside == 0 or kept < inside * MIN_SHARE:
		return out
	var unit := 0.0
	for loop in _loops():
		var ring := PackedVector2Array()
		for q: Vector2i in loop:
			ring.append(area.position + Vector2(q) * CELL)
		var a := _signed_area(ring)
		if absf(a) < MIN_CELLS * CELL * CELL:
			continue
		if unit == 0.0:
			unit = _signed_area(PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]))
		ring = RealCourseBuilder.smooth_ring(RealCourseBuilder.simplify_ring(ring, CELL * 0.6), 3.0, 2)
		if ring.size() < 3:
			continue
		if signf(a) == signf(unit):
			outer.append(ring)
		else:
			islands.append(ring)
	return out


## Share of a shape's cells that are native grass (after rings(), so the
## tidied patches): a mapped rough that is mostly straw in the photo is
## native rough (Torrey Pines' canyon rough), not a mown second cut.
func share_in(shape: CourseShape) -> float:
	if not ready():
		return 0.0
	var b := shape.bounds()
	var i0 := maxi(0, floori((b.position.x - area.position.x) / CELL))
	var i1 := mini(cols - 1, floori((b.end.x - area.position.x) / CELL))
	var j0 := maxi(0, floori((b.position.y - area.position.y) / CELL))
	var j1 := mini(rows_n - 1, floori((b.end.y - area.position.y) / CELL))
	var inside := 0
	var native := 0
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var p := area.position + (Vector2(i, j) + Vector2(0.5, 0.5)) * CELL
			if shape.contains(p):
				inside += 1
				native += mask[j * cols + i]
	return float(native) / inside if inside > 0 else 0.0


## Course points' photo colour, the mean of 4 pixels round it.
func _colour(p: Vector2) -> Color:
	var r := Vector2(area.size.x / photo.get_width(), area.size.y / photo.get_height())
	var sum := Color(0, 0, 0)
	for o: Vector2 in [Vector2(-0.25, -0.25), Vector2(0.25, -0.25), Vector2(-0.25, 0.25), Vector2(0.25, 0.25)]:
		var q := p + o * CELL
		var x := clampi(floori((area.end.x - q.x) / r.x), 0, photo.get_width() - 1)
		var y := clampi(floori((area.end.y - q.y) / r.y), 0, photo.get_height() - 1)
		sum += photo.get_pixel(x, y)
	return Color(sum.r / 4.0, sum.g / 4.0, sum.b / 4.0)


## Spans of x inside the course outline along z (the whole area without one).
func _inside(z: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if boundary.is_empty():
		out.append(Vector2(area.position.x, area.end.x))
		return out
	var xs := PackedFloat32Array()
	for ring in boundary:
		var n := ring.size()
		for k in n:
			var a := ring[k]
			var b := ring[(k + 1) % n]
			if (a.y <= z) != (b.y <= z):
				xs.append(a.x + (z - a.y) * (b.x - a.x) / (b.y - a.y))
	xs.sort()
	for k in range(0, xs.size() - 1, 2):
		out.append(Vector2(xs[k], xs[k + 1]))
	return out


## A majority filter (a cell takes what most of its 3 x 3 has), then
## patches under MIN_CELLS dropped.
func _tidy() -> void:
	var m := mask.duplicate()
	for j in range(1, rows_n - 1):
		for i in range(1, cols - 1):
			var n := 0
			for dj in range(-1, 2):
				for di in range(-1, 2):
					n += mask[(j + dj) * cols + i + di]
			m[j * cols + i] = 1 if n >= 5 else 0
	mask = m
	var seen := PackedByteArray()
	seen.resize(mask.size())
	for k in mask.size():
		if mask[k] == 0 or seen[k] == 1:
			continue
		var patch := PackedInt32Array([k])
		seen[k] = 1
		var at := 0
		while at < patch.size():
			var q := patch[at]
			at += 1
			var qi := q % cols
			var qj := q / cols
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ni := qi + d.x
				var nj := qj + d.y
				if ni < 0 or nj < 0 or ni >= cols or nj >= rows_n:
					continue
				var nk := nj * cols + ni
				if mask[nk] == 1 and seen[nk] == 0:
					seen[nk] = 1
					patch.append(nk)
		if patch.size() < MIN_CELLS:
			for q in patch:
				mask[q] = 0


func _on(i: int, j: int) -> bool:
	return i >= 0 and j >= 0 and i < cols and j < rows_n and mask[j * cols + i] == 1


## The patches' edges between cells, joined into loops of cell corners:
## every in cell's side that faces an out cell, turning the same way round
## each patch (its holes the other way).
func _loops() -> Array:
	var next := {}  ## corner -> corners its edges lead to
	for j in rows_n:
		for i in cols:
			if mask[j * cols + i] == 0:
				continue
			if not _on(i, j - 1):
				_edge(next, Vector2i(i, j), Vector2i(i + 1, j))
			if not _on(i + 1, j):
				_edge(next, Vector2i(i + 1, j), Vector2i(i + 1, j + 1))
			if not _on(i, j + 1):
				_edge(next, Vector2i(i + 1, j + 1), Vector2i(i, j + 1))
			if not _on(i - 1, j):
				_edge(next, Vector2i(i, j + 1), Vector2i(i, j))
	var loops: Array = []
	while not next.is_empty():
		var start: Vector2i = next.keys()[0]
		var loop: Array[Vector2i] = [start]
		var at := start
		while true:
			var outs: Array = next.get(at, [])
			if outs.is_empty():
				break
			var to: Vector2i = outs.pop_back()
			if outs.is_empty():
				next.erase(at)
			if to == start:
				break
			loop.append(to)
			at = to
		if loop.size() >= 4:
			loops.append(loop)
	return loops


static func _edge(next: Dictionary, a: Vector2i, b: Vector2i) -> void:
	if not next.has(a):
		next[a] = []
	(next[a] as Array).append(b)


static func _signed_area(ring: PackedVector2Array) -> float:
	var a := 0.0
	for k in ring.size():
		var p := ring[k]
		var q := ring[(k + 1) % ring.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5
