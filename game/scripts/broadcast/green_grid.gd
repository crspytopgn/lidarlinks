class_name GreenGrid
extends MeshInstance3D
## The TV green-reading grid: lines a metre apart draped over the real
## terrain round the ball and the hole, coloured by how steep the ground is,
## with dots running downhill through each square, faster where it is
## steeper, as PGA Tour 2K25's grid shows the fall. It reads the slopes
## the physics uses (CourseTerrain.normal_at); it doesn't predict the putt,
## so reading the break is still up to the player.
##
## Three looks (`style`): Links 2003's plain yellow grid, its grid coloured
## by height (low blue, high red), and the TV grid: see-through white
## lines, as TV green reads and PGA Tour 2K25 draw them, warming to amber
## and then red where the green gets steep, with the running dots.
## The Links looks keep the game's own bright colours. Every look has a
## soft dark edge (the shader's halo) so it reads on a sunlit green; at
## alpha 0.2 with no edge the TV grid all but vanished from the putting
## camera and the Green Analyzer.
##
## The lines are thin ribbons (shaders/green_grid.gdshader) with soft,
## anti-aliased edges, drawn in short pieces that follow the turf, rather
## than one-pixel GL lines, which neither renderer smooths: those broke
## into stair steps and dashes where they dipped into the turf.

enum Style { YELLOW, HEIGHT, SLOPE }

const SPACING := 1.0
const MARGIN := 4.0  ## metres past the ball and the hole
const MAX_HALF := 18.0
const LIFT := 0.01
## Pieces each metre of line is drawn in, so it follows the turf's curve.
const PIECES := 4
## The lines' width on the turf (m); the shader keeps them a pixel or so
## wide however far off they are.
const LINE_WIDTH := 0.025
const SHADER := preload("res://shaders/green_grid.gdshader")
const FLAT := Color(1.0, 1.0, 1.0, 0.42)
const MEDIUM := Color(1.0, 0.86, 0.45, 0.58)
const STEEP := Color(1.0, 0.45, 0.32, 0.75)
const STEEP_PERCENT := 4.0
## The flowing dots: one streamline seeded in each square, followed
## downhill for up to FLOW_LENGTH metres, with a dot running along it.
const FLOW_LENGTH := 0.85
const FLOW_STEP := 0.05
const FLOW_WIDTH := 3.2  ## times LINE_WIDTH
const FLOW_BASE_SPEED := 0.18
const FLOW_SPEED_PER_PERCENT := 0.1
const FLOW_MAX_SPEED := 0.9
const FLOW_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const YELLOW := Color(1.0, 0.9, 0.2, 0.7)
const LOW := Color(0.2, 0.45, 1.0, 0.75)
const MIDDLE := Color(0.35, 0.9, 0.4, 0.75)
const HIGH := Color(1.0, 0.3, 0.2, 0.8)
## Below this spread of heights (m) the height colours show it as flat.
const LEVEL_SPREAD := 0.05

var style: Style = Style.SLOPE
var _low := 0.0
var _high := 0.0

var _mesh := ArrayMesh.new()
## The mesh being built: arrays filled by _piece, then one surface.
var _verts := PackedVector3Array()
var _colors := PackedColorArray()
var _normals := PackedVector3Array()
var _uvs := PackedVector2Array()
var _uv2s := PackedVector2Array()
## Height and line colour at each point the lines pass through, by its
## place on the grid in 1 / PIECES metre steps: each point is shared by
## two pieces of its line and often by a crossing line, and reading the
## terrain once for it made the build several times faster.
var _points := {}
var _x0 := 0.0
var _z0 := 0.0


func _init() -> void:
	mesh = _mesh
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("width", LINE_WIDTH)
	mat.render_priority = 10
	material_override = mat
	visible = false


## Slope in percent (rise over run) where the ground has normal `n`.
static func slope_percent(n: Vector3) -> float:
	return 100.0 * Vector2(n.x, n.z).length() / maxf(n.y, 0.01)


## Height colours: blue at the lowest point of the grid, green, red at the
## highest. `f` is 0 (lowest) to 1.
static func height_color(f: float) -> Color:
	f = clampf(f, 0.0, 1.0)
	return LOW.lerp(MIDDLE, f * 2.0) if f < 0.5 else MIDDLE.lerp(HIGH, f * 2.0 - 1.0)


static func slope_color(percent: float) -> Color:
	var f := clampf(percent / STEEP_PERCENT, 0.0, 1.0)
	return FLAT.lerp(MEDIUM, f * 2.0) if f < 0.5 else MEDIUM.lerp(STEEP, f * 2.0 - 1.0)


## How fast the dots run downhill (m/s) on a slope of `percent`: a walk on
## a gentle green, quicker as it steepens, as the TV and PGA Tour 2K grids
## show it. The pace is ours.
static func flow_speed(percent: float) -> float:
	return clampf(FLOW_BASE_SPEED + FLOW_SPEED_PER_PERCENT * percent, FLOW_BASE_SPEED, FLOW_MAX_SPEED)


## The grid is built in tiles TILE metres square on the course's own metre
## grid, kept while the hole and its pin stay the same, so a read is put
## together from tiles already built instead of read off the terrain again.
## The tiles round the hole are built ahead (prewarm), a little a frame
## from the moment the hole starts, so the grid is up the instant the
## player reaches the green; a second putt reuses them all.
const TILE := 2
## How far round the hole the tiles are built ahead (metres).
const WARM_RADIUS := 22.0
## Milliseconds a frame spent building tiles ahead, and building the tiles a
## read still lacks once the player is on the green.
const WARM_SLICE_MS := 1.5
const SLICE_MS := 4.0
## Milliseconds a read may spend finishing its last few tiles at once,
## rather than over the frames after (0 in tests to see the spread build).
var now_ms := 8.0

## What the tiles were built for: [terrain, style, pin]; the tiles; tiles
## still to build ahead, nearest the hole first.
var _cache_key := []
var _tiles := {}
var _warm: Array[Vector2i] = []
## What the grid on show was built for, so asking again for the same grid
## (a club change, the aim settling) costs nothing.
var _built_key := []
## A read waiting on tiles: its key and tile range, or empty.
var _job := {}


## Builds the tiles round `pin` ahead of the player reaching the green, a
## little a frame. Asking again for the same hole does nothing.
func prewarm(terrain: CourseTerrain, pin: Vector3) -> void:
	if _use_cache(terrain, pin) and not _warm.is_empty():
		set_process(true)


## Shows the grid over the square that holds `ball` and `pin`: at once from
## the tiles built ahead, else as soon as the missing tiles are built (a few
## milliseconds a frame, so a big green never stalls one). The old grid
## stays up meanwhile. (Not on a worker thread: the caddie's planning
## crashed there, as Godot 4.4's script arrays aren't safe to share across
## threads.)
func build_async(terrain: CourseTerrain, ball: Vector3, pin: Vector3) -> void:
	var key := [terrain, ball, pin, style]
	if not _job.is_empty():
		if key == _job.key:
			return
	elif key == _built_key:
		return
	_use_cache(terrain, pin)
	_job = _range(terrain, ball, pin)
	_job.key = key
	if _build_missing(_job, Time.get_ticks_usec() + int(now_ms * 1000.0)):
		_show(_job)
	else:
		set_process(true)


func _process(_delta: float) -> void:
	if not _job.is_empty():
		if _build_missing(_job, Time.get_ticks_usec() + int(SLICE_MS * 1000.0)):
			_show(_job)
		return
	if _warm.is_empty():
		set_process(false)
		return
	var deadline := Time.get_ticks_usec() + int(WARM_SLICE_MS * 1000.0)
	var terrain: CourseTerrain = _cache_key[0]
	while not _warm.is_empty() and Time.get_ticks_usec() < deadline:
		var t: Vector2i = _warm.pop_back()
		if not _tiles.has(t):
			_tiles[t] = _build_tile(terrain, t)


## Rebuilds the grid over the square that holds `ball` and `pin`, now.
func build(terrain: CourseTerrain, ball: Vector3, pin: Vector3) -> void:
	_apply(_build_arrays(terrain, ball, pin))
	_built_key = [terrain, ball, pin, style]


func _apply(arrays: Array) -> void:
	_mesh.clear_surfaces()
	if not arrays.is_empty() and not (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
		_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## The grid's mesh arrays over the square that holds `ball` and `pin`.
func _build_arrays(terrain: CourseTerrain, ball: Vector3, pin: Vector3) -> Array:
	_job = {}  # a build now replaces one waiting on tiles
	_use_cache(terrain, pin)
	var job := _range(terrain, ball, pin)
	_build_missing(job, -1)
	return _join(job)


## Keeps the tiles when they were built for this terrain, look and pin, else
## starts again: the height colours run from the lowest to the highest point
## round the hole, so a read keeps its colours from putt to putt. Returns
## true when it started again.
func _use_cache(terrain: CourseTerrain, pin: Vector3) -> bool:
	var key := [terrain, style, pin]
	if key == _cache_key:
		return false
	_cache_key = key
	_tiles.clear()
	_built_key = []
	if style == Style.HEIGHT:
		_low = INF
		_high = -INF
		var r := int(ceil(WARM_RADIUS / SPACING))
		for a in range(-r, r + 1):
			for b in range(-r, r + 1):
				var y := terrain.height_at(pin.x + a * SPACING, pin.z + b * SPACING)
				_low = minf(_low, y)
				_high = maxf(_high, y)
	# Tiles round the hole, nearest last (popped first).
	_warm.clear()
	var side := float(TILE) * SPACING
	var reach := int(ceil(WARM_RADIUS / side))
	var at := Vector2i(floori(pin.x / side), floori(pin.z / side))
	var centre := Vector2(pin.x, pin.z)
	for i in range(-reach, reach + 1):
		for j in range(-reach, reach + 1):
			var t := at + Vector2i(i, j)
			if (Vector2(t) * side + Vector2.ONE * side * 0.5).distance_to(centre) <= WARM_RADIUS + side:
				_warm.append(t)
	_warm.sort_custom(func(p: Vector2i, q: Vector2i) -> bool:
		return (Vector2(p) * side).distance_squared_to(centre) > (Vector2(q) * side).distance_squared_to(centre))
	return true


## The tiles over the square that holds `ball` and `pin`.
func _range(_terrain: CourseTerrain, ball: Vector3, pin: Vector3) -> Dictionary:
	var centre := (ball + pin) * 0.5
	var half := clampf(Vector2(ball.x - pin.x, ball.z - pin.z).length() * 0.5 + MARGIN, 6.0, MAX_HALF)
	var a0 := floori((centre.x - half) / SPACING)
	var b0 := floori((centre.z - half) / SPACING)
	var cells := int(ceil(half * 2.0 / SPACING))
	return {"from": Vector2i(floori(float(a0) / TILE), floori(float(b0) / TILE)),
		"to": Vector2i(floori(float(a0 + cells - 1) / TILE), floori(float(b0 + cells - 1) / TILE))}


## Builds the tiles `job` still lacks until `deadline_us` (-1: all). True
## once it has them all.
func _build_missing(job: Dictionary, deadline_us: int) -> bool:
	var terrain: CourseTerrain = _cache_key[0]
	var from: Vector2i = job.from
	var to: Vector2i = job.to
	for i in range(from.x, to.x + 1):
		for j in range(from.y, to.y + 1):
			var t := Vector2i(i, j)
			if _tiles.has(t):
				continue
			if deadline_us >= 0 and Time.get_ticks_usec() > deadline_us:
				return false
			_tiles[t] = _build_tile(terrain, t)
	return true


func _show(job: Dictionary) -> void:
	_built_key = job.key
	_apply(_join(job))
	_job = {}


## The mesh arrays of `job`'s tiles, with the closing lines along its far
## edges.
func _join(job: Dictionary) -> Array:
	var from: Vector2i = job.from
	var to: Vector2i = job.to
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var parts := [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array(), PackedVector2Array()]
	for i in range(from.x, to.x + 1):
		for j in range(from.y, to.y + 1):
			var tile: Dictionary = _tiles[Vector2i(i, j)]
			_join_part(parts, tile.body)
			if i == to.x:
				_join_part(parts, tile.edge_x)
			if j == to.y:
				_join_part(parts, tile.edge_z)
	arrays[Mesh.ARRAY_VERTEX] = parts[0]
	arrays[Mesh.ARRAY_NORMAL] = parts[1]
	arrays[Mesh.ARRAY_COLOR] = parts[2]
	arrays[Mesh.ARRAY_TEX_UV] = parts[3]
	arrays[Mesh.ARRAY_TEX_UV2] = parts[4]
	return arrays


static func _join_part(parts: Array, part: Array) -> void:
	for k in 5:
		parts[k].append_array(part[k])


## One tile: its lines (those along its near edges and through it), its
## streamlines, and the lines that close it along its far x and z edges,
## kept apart as only the tiles at the far edge of a read draw them.
func _build_tile(terrain: CourseTerrain, t: Vector2i) -> Dictionary:
	_x0 = 0.0
	_z0 = 0.0
	_points.clear()
	var a0 := t.x * TILE
	var b0 := t.y * TILE
	for i in TILE:
		for j in TILE:
			var a := a0 + i
			var b := b0 + j
			_segment(terrain, Vector2i(a * PIECES, b * PIECES), Vector2i(0, 1))
			_segment(terrain, Vector2i(a * PIECES, b * PIECES), Vector2i(1, 0))
	if style == Style.SLOPE:
		for i in TILE:
			for j in TILE:
				var a := a0 + i
				var b := b0 + j
				_flow(terrain, Vector2((a + 0.5) * SPACING, (b + 0.5) * SPACING), hash(Vector2i(a, b)))
	var body := _take()
	for j in TILE:
		_segment(terrain, Vector2i((a0 + TILE) * PIECES, (b0 + j) * PIECES), Vector2i(0, 1))
	var edge_x := _take()
	for i in TILE:
		_segment(terrain, Vector2i((a0 + i) * PIECES, (b0 + TILE) * PIECES), Vector2i(1, 0))
	var edge_z := _take()
	_points.clear()
	return {"body": body, "edge_x": edge_x, "edge_z": edge_z}


## The pieces built so far, as [verts, normals, colours, uvs, uv2s]; the
## build starts afresh.
func _take() -> Array:
	var part := [_verts, _normals, _colors, _uvs, _uv2s]
	_verts = PackedVector3Array()
	_colors = PackedColorArray()
	_normals = PackedVector3Array()
	_uvs = PackedVector2Array()
	_uv2s = PackedVector2Array()
	return part

## A streamline from `c` downhill, with its running dot (see the shader).
## It bends with the green, following the fall from step to step.
func _flow(terrain: CourseTerrain, c: Vector2, seed: int) -> void:
	var n := terrain.normal_at(c.x, c.y)
	var pct := slope_percent(n)
	if pct < GreenRead.FLAT_PERCENT:
		return
	# Start half a streamline uphill so the dot runs through the square's
	# middle.
	var start := c - Vector2(n.x, n.z).normalized() * FLOW_LENGTH * 0.5
	var pts: Array[Vector2] = [start]
	var p := start
	var travelled := 0.0
	while travelled < FLOW_LENGTH - 1e-4:
		var f := GreenRead.fall(terrain, p.x, p.y)
		if f.length() * 100.0 < GreenRead.FLAT_PERCENT:
			break
		p += f.normalized() * FLOW_STEP
		travelled += FLOW_STEP
		pts.append(p)
	if pts.size() < 3:
		return
	var col := slope_color(pct)
	col = Color(FLOW_COLOR.lerp(col, 0.5), FLOW_COLOR.a)
	var rate := flow_speed(pct) / travelled
	var phase := float(absi(hash(seed)) % 16) * 2.0
	# Each point's height read once: it ends one piece and starts the next.
	var prev := Vector3(pts[0].x, terrain.height_at(pts[0].x, pts[0].y) + LIFT, pts[0].y)
	for i in pts.size() - 1:
		var s0 := float(i) / (pts.size() - 1)
		var s1 := float(i + 1) / (pts.size() - 1)
		var next := Vector3(pts[i + 1].x, terrain.height_at(pts[i + 1].x, pts[i + 1].y) + LIFT, pts[i + 1].y)
		_add_piece(prev, next, col, col, FLOW_WIDTH, Vector2(phase + s0, rate), Vector2(phase + s1, rate))
		prev = next


## One metre of grid line from grid point `k` (1 / PIECES metre steps)
## one step of `dir` at a time.
func _segment(terrain: CourseTerrain, k: Vector2i, dir: Vector2i) -> void:
	var prev: Array = _point(terrain, k)
	for i in PIECES:
		var next: Array = _point(terrain, k + dir * (i + 1))
		_add_piece(prev[0], next[0], prev[1], next[1])
		prev = next


## [position on the turf, line colour] at grid point `k`.
func _point(terrain: CourseTerrain, k: Vector2i) -> Array:
	var got: Variant = _points.get(k)
	if got != null:
		return got
	var p := Vector2(_x0 + float(k.x) * SPACING / PIECES, _z0 + float(k.y) * SPACING / PIECES)
	var pt := [Vector3(p.x, terrain.height_at(p.x, p.y) + LIFT, p.y), _colour_at(terrain, p)]
	_points[k] = pt
	return pt


func _colour_at(terrain: CourseTerrain, p: Vector2) -> Color:
	match style:
		Style.SLOPE:
			return slope_color(slope_percent(terrain.normal_at(p.x, p.y)))
		Style.HEIGHT:
			var spread := _high - _low
			return MIDDLE if spread < LEVEL_SPREAD else height_color((terrain.height_at(p.x, p.y) - _low) / spread)
	return YELLOW


## One straight piece of line from `a` to `b` on the turf: a quad the
## shader widens across the screen (UV.x is the edge, -1 or +1; the normal
## carries the way the line runs, UV.y how much wider than LINE_WIDTH).
## `flow_a` and `flow_b` are the flowing dot's UV2 at each end (none on the
## plain lines). `pa` and `pb` are already lifted off the turf.
func _add_piece(pa: Vector3, pb: Vector3, col_a: Color, col_b: Color, wide := 1.0, flow_a := Vector2.ZERO, flow_b := Vector2.ZERO) -> void:
	var run := (pb - pa).normalized()
	_verts.append_array([pa, pa, pb, pa, pb, pb])
	_colors.append_array([col_a, col_a, col_b, col_a, col_b, col_b])
	_normals.append_array([run, run, run, run, run, run])
	_uvs.append_array([Vector2(-1.0, wide), Vector2(1.0, wide), Vector2(1.0, wide), Vector2(-1.0, wide), Vector2(1.0, wide), Vector2(-1.0, wide)])
	_uv2s.append_array([flow_a, flow_a, flow_b, flow_a, flow_b, flow_b])
