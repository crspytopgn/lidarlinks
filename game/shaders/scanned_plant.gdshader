// A real scanned plant (ScannedPlants, the private Megascans pack): ferns,
// wild grasses, wildflowers and reeds round the tees and greens, drawn as
// their own photographed leaves and blades rather than flat cards. Each
// MultiMesh draws one level of detail of one variant: band 0 the near
// mesh, out to near_end; band 1 the lighter mid mesh from there to
// far_end. The two hand over with the trees' dithered cross-fade
// (tree_lod.gdshaderinc), and the mid mesh dissolves the same way into the
// plant cards (FescueField) further off. INSTANCE_CUSTOM.rgb is the
// ground's colour under the plant (sRGB), .a a random number for its
// sway and tone. Forward+ and Compatibility.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
// Normal map in rgb (OpenGL), translucency in a.
uniform sampler2D normal_tex : filter_linear_mipmap_anisotropic;
uniform bool has_normal = true;
uniform float plant_height = 0.7;
uniform int band = 0;
uniform float near_end = 12.0;
uniform float far_end = 32.0;
uniform float brightness = 1.0;
// The scan's exposure brought to the course's (MegascansPlants.gain).
uniform float gain = 1.0;
// How far the plant's colour leans to the ground's: the scans were shot
// in their own light and season, and a little of the course's own colour
// sits them on it.
uniform float ground_pull = 0.18;
// Light through the leaves, against their colour.
uniform float translucency = 0.55;
uniform float saturation = 0.8;
// How far the leaves' normals lean to straight up (see the fragment).
uniform float up_lean = 0.5;

global uniform vec2 wind_vector;
global uniform float foliage_sway;

#include "res://shaders/ground_shade.gdshaderinc"
#include "res://shaders/tree_lod.gdshaderinc"

varying vec2 lod_span;
varying vec2 root_xz;
varying vec3 ground_col;
varying float rnd;
varying float up;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	root_xz = root.xz;
	rnd = INSTANCE_CUSTOM.a;
	float d = distance(root, MAIN_CAM_INV_VIEW_MATRIX[3].xyz);
	lod_span = band == 0 ? tree_lod_span(d, -1.0, near_end) : tree_lod_span(d, near_end, far_end);
	if (tree_lod_hidden(lod_span)) {
		VERTEX = vec3(0.0);
	}
	up = clamp(VERTEX.y / max(plant_height, 0.05), 0.0, 1.5);
	if (foliage_sway > 0.0) {
		// The plant bends from its root with the wind and each frond or
		// blade sways a little on its own, more towards the tips.
		float phase = rnd * 37.7 + dot(root.xz, vec2(0.13, 0.11));
		float gust = 0.6 + 0.4 * sin(TIME * 1.3 + phase);
		vec3 lv = VERTEX;
		vec2 own = vec2(sin(TIME * 1.9 + phase + lv.x * 3.0), cos(TIME * 1.6 + phase + lv.z * 3.0)) * 0.025;
		vec2 bend = (wind_vector * 0.012 * gust + own) * up * up * plant_height * foliage_sway;
		vec3 world_off = vec3(bend.x, -dot(bend, bend) * 0.5, bend.y);
		VERTEX += inverse(mat3(MODEL_MATRIX)) * world_off;
	}
	vec3 c = INSTANCE_CUSTOM.rgb;
	ground_col = mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, step(c, vec3(0.04045)));
}

void fragment() {
	if (tree_lod_discard(lod_span, FRAGCOORD.xy)) {
		discard;
	}
	vec4 t = texture(albedo_tex, UV);
	// Smaller mips thin the blades under the alpha test: hold them up.
	vec2 texels = vec2(textureSize(albedo_tex, 0));
	float lod = log2(max(max(length(dFdx(UV) * texels), length(dFdy(UV) * texels)), 1.0));
	if (t.a * (1.0 + lod * 0.12) < 0.5) {
		discard;
	}
	vec3 c = t.rgb * gain;
	// Each plant a little lighter or darker, greener or drier.
	c *= mix(0.86, 1.08, rnd) * mix(vec3(1.0), vec3(1.04, 1.02, 0.9), step(0.7, fract(rnd * 7.3)));
	float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
	vec3 ground_hue = ground_col / max(dot(ground_col, vec3(0.2126, 0.7152, 0.0722)), 0.001);
	c = mix(c, ground_hue * luma, ground_pull);
	// The scans' young blades are a vivid lime that reads neon against
	// the course: hold their saturation to a real meadow's.
	c = mix(vec3(dot(c, vec3(0.2126, 0.7152, 0.0722))), c, saturation);
	// The base of a plant is in its own shade.
	c *= mix(0.55, 1.0, smoothstep(0.0, 0.6, up));
	vec3 albedo = min(c * brightness, vec3(0.8));
	float light = ground_shading(root_xz, length(VERTEX));
	ALBEDO = albedo * shade_fill.a * light;
	EMISSION = albedo * shade_fill.rgb;
	// Lit half as the ground under it is: a clump's leaves face every way,
	// and left to their own normals the ones turned from the sun go near
	// black in Forward+, where photos show a clump softly lit by the sky.
	vec3 sky_up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	// (Godot has already turned a back face's normal to the viewer.)
	NORMAL = normalize(mix(NORMAL, sky_up, up_lean));
	float tr = 0.5;
	if (has_normal) {
		vec4 n = texture(normal_tex, UV);
		NORMAL_MAP = n.rgb;
		NORMAL_MAP_DEPTH = 0.8;
		tr = n.a;
	}
	BACKLIGHT = albedo * translucency * (0.4 + tr) * light;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
}
