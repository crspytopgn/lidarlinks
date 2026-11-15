// A dry-stone wall's face (StoneWalls): courses of flattish stones laid
// without mortar, each a little proud of its neighbours with dark gaps
// between, worked out from UV (metres along the wall, metres up it). Each
// stone shows its own patch of a photoscanned rock (the Megascans pack's
// rock texture when present, else plain weathered grey with grain), so no
// two look alike. Forward+ and Compatibility.
shader_type spatial;
render_mode cull_disabled;

uniform bool has_rock = false;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 stone_colour : source_color = vec3(0.47, 0.46, 0.43);
uniform float course_height = 0.16; // metres per course of stones
uniform float rock_metres = 0.9; // how much of the rock scan one metre of stone shows

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 m = UV; // metres along, metres up
	// Courses of uneven height, and stones of uneven length within each.
	// The courses undulate along the wall, and every edge is ragged.
	float wy = m.y / course_height + (noise(vec2(m.x * 1.3, 0.5)) - 0.5) * 1.2
		+ (noise(m * vec2(9.0, 11.0)) - 0.5) * 0.35;
	float row = floor(wy);
	float rv = fract(wy);
	float len = mix(0.14, 0.55, hash(vec2(row, 3.1)));
	float sx = m.x / len + hash(vec2(row, 9.7)) * 7.0 + (noise(m * vec2(7.0, 13.0)) - 0.5) * 0.5;
	float col = floor(sx);
	float cu = fract(sx);
	vec2 cell = vec2(col, row);
	// How far inside its stone a point is (0 at the gap).
	float edge = min(min(cu, 1.0 - cu) * len, min(rv, 1.0 - rv) * course_height);
	float gap = 0.012 + 0.012 * hash(cell + 0.5);
	float inside = smoothstep(gap * 0.4, gap * 1.6, edge);
	// The stone's own face: a random patch of the scan, toned per stone.
	vec2 ruv = m / rock_metres + vec2(hash(cell), hash(cell + 3.3)) * 9.0;
	vec3 face = has_rock ? texture(rock_albedo, ruv).rgb : stone_colour * (0.85 + 0.3 * noise(m * 23.0));
	// Field-wall stone is grey: limestone, gritstone, granite.
	float l = dot(face, vec3(0.2126, 0.7152, 0.0722));
	face = mix(face, vec3(l) * vec3(1.0, 0.98, 0.94), 0.7);
	face *= mix(0.7, 1.2, hash(cell + 7.7));
	// Lichen on some stones, in the weather.
	face = mix(face, face * vec3(0.95, 1.0, 0.8) + vec3(0.03, 0.04, 0.0), step(0.75, hash(cell + 1.9)) * noise(m * 9.0));
	ALBEDO = mix(face * 0.18, face, inside);
	AO = mix(0.35, 1.0, inside);
	ROUGHNESS = 0.92;
	// Each stone bulges: tilt the normal toward its rim near the edges.
	vec2 to_rim = vec2((cu - 0.5) * len, (rv - 0.5) * course_height);
	vec2 tilt = to_rim / vec2(len, course_height) * (1.0 - smoothstep(0.0, 0.05, edge)) * 1.2;
	vec3 n = has_rock ? texture(rock_normal, ruv).rgb * 2.0 - 1.0 : vec3(0.0, 0.0, 1.0);
	n.xy += tilt;
	NORMAL_MAP = normalize(n) * 0.5 + 0.5;
}
