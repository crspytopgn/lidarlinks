class_name HoleMap
extends RefCounted
## A top-down map of a hole for the broadcast hole card and the Tour map: the
## ground sampled from the terrain, turned so the tee is at the bottom and
## the green at the top.
##
## The terrain is sampled once on a coarse grid (SAMPLES per map unit) into
## soft masks, and a shader draws the map from them on the GPU at RES pixels
## per map unit, once per hole: smooth curved edges, mowing stripes, shaded
## bunkers, hillshade and tree canopies with their shadows, in every renderer.
## The route, tee and pin are left to whoever draws the map.

## The map's size in map units (to_px works in these).
const WIDTH := 72
const HEIGHT := 160
## Terrain samples per map unit, and texture pixels per map unit.
const SAMPLES := 2
const RES := 5
## The flat colours, for code that wants one colour per ground type.
const COLORS := {
	Surface.Type.TEE: Color(0.42, 0.64, 0.27),
	Surface.Type.FAIRWAY: Color(0.42, 0.64, 0.27),
	Surface.Type.FRINGE: Color(0.45, 0.69, 0.29),
	Surface.Type.GREEN: Color(0.5, 0.74, 0.31),
	Surface.Type.ROUGH: Color(0.27, 0.42, 0.18),
	Surface.Type.DEEP_ROUGH: Color(0.18, 0.29, 0.13),
	Surface.Type.SAND: Color(0.91, 0.85, 0.69),
	Surface.Type.WATER: Color(0.18, 0.36, 0.48),
	Surface.Type.OUT_OF_BOUNDS: Color(0.12, 0.2, 0.1),
}
const TREE_WORDS := ["tree", "pine", "oak", "palm", "birch", "willow", "maple", "cherry", "bush", "shrub", "fir"]

const SHADER := """
shader_type canvas_item;
render_mode unshaded;

// r fairway or tee, g green or fringe, b sand, a water.
uniform sampler2D masks : filter_linear;
// r deep rough or out of bounds, g height (0..1), b tree cover.
uniform sampler2D aux : filter_linear;
uniform vec2 units = vec2(72.0, 160.0);
uniform float metres_per_unit = 3.0;
uniform float relief_m = 10.0;

vec3 lit(vec3 c, float k) { return c * k; }

void fragment() {
	vec2 uv = UV;
	// The course's ground is a raster too: a blur over about two samples
	// rounds its steps off before the edges are cut.
	vec2 st = 1.5 / vec2(textureSize(masks, 0));
	vec4 m = texture(masks, uv) * 0.2;
	vec4 x = texture(aux, uv);
	float deep_sum = x.r * 0.2;
	for (int k = 0; k < 8; k++) {
		float a = float(k) * 0.7854;
		vec2 o = vec2(cos(a), sin(a)) * st;
		m += texture(masks, uv + o) * 0.1;
		deep_sum += texture(aux, uv + o).r * 0.1;
	}
	x.r = deep_sum;
	vec2 px = uv * units;              // map units
	vec2 metres = px * metres_per_unit;
	float aa = fwidth(m.r) + 0.02;
	float fair = smoothstep(0.5 - aa, 0.5 + aa, m.r);
	float green = smoothstep(0.5 - fwidth(m.g) - 0.02, 0.5 + fwidth(m.g) + 0.02, m.g);
	float sand = smoothstep(0.5 - fwidth(m.b) - 0.02, 0.5 + fwidth(m.b) + 0.02, m.b);
	float water = smoothstep(0.5 - fwidth(m.a) - 0.02, 0.5 + fwidth(m.a) + 0.02, m.a);
	float deep = smoothstep(0.35, 0.65, x.r);
	// Fine grain, so wide areas aren't flat paint.
	float n = fract(sin(dot(floor(metres * 1.5), vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	vec3 c = mix(vec3(0.27, 0.42, 0.18), vec3(0.18, 0.29, 0.13), deep);
	vec3 fw = vec3(0.42, 0.64, 0.27) * (mod(floor(metres.x / 7.0), 2.0) < 1.0 ? 1.06 : 0.94);
	c = mix(c, fw, fair);
	// A lighter collar just round the green, then the green's own stripes.
	float collar = smoothstep(0.18, 0.5, m.g) * (1.0 - green);
	c = mix(c, vec3(0.45, 0.69, 0.29), collar);
	float gs = mod(floor((metres.x + metres.y) / 2.5), 2.0) < 1.0 ? 1.05 : 0.95;
	c = mix(c, vec3(0.5, 0.74, 0.31) * gs, green);
	// Sand, darker under the lip.
	float lip = smoothstep(0.5, 0.9, m.b);
	c = mix(c, vec3(0.91, 0.85, 0.69) * (0.8 + 0.2 * lip), sand);
	float deepw = smoothstep(0.5, 1.0, m.a);
	c = mix(c, mix(vec3(0.22, 0.42, 0.52), vec3(0.12, 0.26, 0.36), deepw), water);
	c *= 1.0 + n * 0.06 * (1.0 - water);
	// Hillshade from the height, lit from the top left.
	vec2 t = 1.0 / vec2(textureSize(aux, 0));
	float hx = texture(aux, uv + vec2(t.x, 0.0)).g - texture(aux, uv - vec2(t.x, 0.0)).g;
	float hy = texture(aux, uv + vec2(0.0, t.y)).g - texture(aux, uv - vec2(0.0, t.y)).g;
	float slope_scale = relief_m / (2.0 * metres_per_unit / float(textureSize(aux, 0).x) * units.x);
	float shade = clamp(1.0 + (-hx + hy) * slope_scale * 0.9, 0.72, 1.25);
	c *= mix(shade, 1.0, water);
	// Tree canopies: their shadow offset down and right, then the crown,
	// lit at the top left.
	float sh = texture(aux, uv - vec2(1.2, 1.2) * t).b;
	c *= 1.0 - 0.45 * smoothstep(0.3, 0.7, sh);
	float tree = x.b;
	float crown = smoothstep(0.42, 0.58, tree);
	float lit_side = texture(aux, uv + vec2(0.6, 0.6) * t).b - texture(aux, uv - vec2(0.6, 0.6) * t).b;
	vec3 leaf = vec3(0.15, 0.27, 0.12) * (1.0 + clamp(lit_side * 3.0, -0.35, 0.6)) * (1.0 + n * 0.25);
	c = mix(c, leaf, crown);
	COLOR = vec4(c, 1.0);
}
"""

static var _shader: Shader

var texture: Texture2D
## The viewport that draws the map once; freed with the map.
var _viewport: SubViewport
## Tee, route points and pin in map units, for drawing the line of the hole.
var route_px := PackedVector2Array()
## The map's frame: world x,z to pixels (to_px).
var _tee := Vector2.ZERO
var _side := Vector2.RIGHT
var _up := Vector2.UP
var _mid := Vector2.ZERO
var _metres_per_px := 1.0


static func make(hole: HoleData) -> Texture2D:
	return build(hole).texture


## The map and its frame, so shots can be marked on it (to_px).
static func build(hole: HoleData) -> HoleMap:
	var tee := Vector2(hole.tee.x, hole.tee.z)
	var pin := Vector2(hole.pin.x, hole.pin.z)
	var pts: Array[Vector2] = [tee]
	for r in hole.route:
		pts.append(r)
	pts.append(pin)
	var up := (pin - tee).normalized() if tee.distance_to(pin) > 1.0 else Vector2(0, 1)
	var side := Vector2(-up.y, up.x)  ## to the golfer's right (+x is left)
	# Extent of the route in the turned frame, plus a margin.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		var q := _turn(p - tee, side, up)
		lo = lo.min(q)
		hi = hi.max(q)
	var length := hi.y - lo.y + 50.0
	var metres_per_px := maxf(length / HEIGHT, (hi.x - lo.x + 60.0) / WIDTH)
	var mid := Vector2((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5)
	var map := HoleMap.new()
	map._tee = tee
	map._side = side
	map._up = up
	map._mid = mid
	map._metres_per_px = metres_per_px
	for q in pts:
		map.route_px.append(map.to_px_2d(q))
	var w := WIDTH * SAMPLES
	var h := HEIGHT * SAMPLES
	# Bytes written straight in (set_pixel is slow), and the heights on a
	# grid half as fine: the hillshade is soft anyway. About 4x quicker.
	var mask_bytes := PackedByteArray()
	mask_bytes.resize(w * h * 4)
	var aux_bytes := PackedByteArray()
	aux_bytes.resize(w * h * 4)
	var hw := w / 2
	var hh := h / 2
	var heights := PackedFloat32Array()
	heights.resize(hw * hh)
	var lo_h := INF
	var hi_h := -INF
	var step := map._side * map._metres_per_px / SAMPLES
	var down := -map._up * map._metres_per_px / SAMPLES
	var row_start := map.from_px(Vector2(0.5, 0.5) / SAMPLES)
	for py in h:
		var at := row_start + down * py
		for px in w:
			var s: int = hole.terrain.surface_at(at.x, at.y)
			var i := (py * w + px) * 4
			if s == Surface.Type.FAIRWAY or s == Surface.Type.TEE:
				mask_bytes[i] = 255
			elif s == Surface.Type.GREEN:
				mask_bytes[i + 1] = 255
			elif s == Surface.Type.FRINGE:
				mask_bytes[i + 1] = 107
			elif s == Surface.Type.SAND:
				mask_bytes[i + 2] = 255
			elif s == Surface.Type.WATER:
				mask_bytes[i + 3] = 255
			elif s == Surface.Type.DEEP_ROUGH or s == Surface.Type.OUT_OF_BOUNDS:
				aux_bytes[i] = 255
			if (px & 1) == 0 and (py & 1) == 0:
				var y := hole.terrain.height_at(at.x, at.y)
				heights[(py / 2) * hw + px / 2] = y
				lo_h = minf(lo_h, y)
				hi_h = maxf(hi_h, y)
			at += step
	var relief := maxf(hi_h - lo_h, 0.5)
	for py in h:
		for px in w:
			var hy := heights[mini(py / 2, hh - 1) * hw + mini(px / 2, hw - 1)]
			var i := (py * w + px) * 4
			aux_bytes[i + 1] = int((hy - lo_h) / relief * 255.0)
			aux_bytes[i + 3] = 255
	var masks := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, mask_bytes)
	var aux := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, aux_bytes)
	map._add_trees(hole, aux)
	map._render(masks, aux, metres_per_px, relief)
	return map


## Metres of course per map unit.
func metres_per_unit() -> float:
	return _metres_per_px


## Where a world point falls on the map, in map units.
func to_px(p: Vector3) -> Vector2:
	return to_px_2d(Vector2(p.x, p.z))


func to_px_2d(p: Vector2) -> Vector2:
	var q := _turn(p - _tee, _side, _up) - _mid
	return Vector2(WIDTH * 0.5 + q.x / _metres_per_px, HEIGHT * 0.5 - q.y / _metres_per_px)


## The world point (x, z) under map pixel `px`: to_px_2d backwards.
func from_px(px: Vector2) -> Vector2:
	var q := _mid + Vector2(px.x - WIDTH * 0.5, HEIGHT * 0.5 - px.y) * _metres_per_px
	return _tee + _side * q.x + _up * q.y


## Tree canopies into aux's blue channel, as soft discs.
func _add_trees(hole: HoleData, aux: Image) -> void:
	var w := aux.get_width()
	var h := aux.get_height()
	for o in hole.objects:
		var id := o.id.to_lower()
		var tree := false
		for word: String in TREE_WORDS:
			if id.contains(word):
				tree = true
				break
		if not tree:
			continue
		var c := to_px(o.position) * SAMPLES
		var r := (2.0 if id.contains("bush") or id.contains("shrub") else 4.5) * maxf(o.scale, 0.4) / _metres_per_px * SAMPLES
		if c.x < -r or c.y < -r or c.x > w + r or c.y > h + r:
			continue
		for y in range(maxi(0, floori(c.y - r - 1)), mini(h, ceili(c.y + r + 1))):
			for x in range(maxi(0, floori(c.x - r - 1)), mini(w, ceili(c.x + r + 1))):
				var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / maxf(r, 0.6)
				if d < 1.3:
					var col := aux.get_pixel(x, y)
					col.b = maxf(col.b, clampf(1.15 - d * 0.75, 0.0, 1.0))
					aux.set_pixel(x, y, col)


## Draws the map once on the GPU at RES pixels a map unit.
func _render(masks: Image, aux: Image, metres_per_px: float, relief: float) -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("masks", ImageTexture.create_from_image(masks))
	mat.set_shader_parameter("aux", ImageTexture.create_from_image(aux))
	mat.set_shader_parameter("units", Vector2(WIDTH, HEIGHT))
	mat.set_shader_parameter("metres_per_unit", metres_per_px)
	mat.set_shader_parameter("relief_m", relief)
	var root := (Engine.get_main_loop() as SceneTree).root if Engine.get_main_loop() is SceneTree else null
	if root == null:
		texture = ImageTexture.create_from_image(masks)
		return
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(WIDTH * RES, HEIGHT * RES)
	_viewport.disable_3d = true
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var rect := ColorRect.new()
	rect.size = Vector2(_viewport.size)
	rect.material = mat
	_viewport.add_child(rect)
	root.add_child.call_deferred(_viewport)
	texture = _viewport.get_texture()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_viewport):
		_viewport.queue_free()


static func _turn(v: Vector2, side: Vector2, up: Vector2) -> Vector2:
	return Vector2(v.dot(side), v.dot(up))
