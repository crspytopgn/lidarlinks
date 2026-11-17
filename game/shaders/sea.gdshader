// The open sea round a coastal course (Landscape): deep ocean blue, a
// paler band of sky reflected toward the horizon (Fresnel), sun glitter
// on moving swell, and the same distance haze as the land, so far off it
// meets the sky as real sea does instead of a grey wall (the pond water's
// own shader takes the course's fog, which buried the sea in grey).
// Works in Forward+ and Compatibility.
shader_type spatial;
render_mode cull_disabled, fog_disabled;

uniform vec3 deep_color : source_color = vec3(0.04, 0.2, 0.36);
uniform vec3 shallow_color : source_color = vec3(0.07, 0.3, 0.38);
uniform vec3 sky_color : source_color = vec3(0.55, 0.7, 0.86);
uniform vec3 haze_color : source_color = vec3(0.7, 0.78, 0.86);
uniform float fog_density = 0.0005;
uniform float air_share = 0.4;
uniform float full_air = 300.0;
uniform float brightness = 1.0;

varying vec3 world;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y);
}
float swell(vec2 p, float t) {
	return vn(p / 9.0 + vec2(t * 0.05, t * 0.03)) * 0.6 + vn(p / 3.1 - vec2(t * 0.11, -t * 0.07)) * 0.3 + vn(p / 1.2 + vec2(t * 0.2, t * 0.13)) * 0.1;
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world.xz;
	float dist = distance(world, CAMERA_POSITION_WORLD);
	// Swell normals, calming with distance so the far sea doesn't shimmer.
	float calm = 1.0 - smoothstep(200.0, 2500.0, dist);
	float e = 0.4;
	float t = TIME;
	float sx = swell(p + vec2(e, 0.0), t) - swell(p - vec2(e, 0.0), t);
	float sz = swell(p + vec2(0.0, e), t) - swell(p - vec2(0.0, e), t);
	vec3 n = normalize(vec3(-sx * 1.6 * calm, 1.0, -sz * 1.6 * calm));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 view = normalize(CAMERA_POSITION_WORLD - world);
	float fres = pow(1.0 - clamp(dot(view, n), 0.0, 1.0), 4.0);
	vec3 water = mix(deep_color, shallow_color, 0.25 * vn(p / 60.0));
	vec3 c = mix(water, sky_color, clamp(0.05 + 0.45 * fres, 0.0, 1.0)) * brightness;
	float air = min(dist, full_air) + max(dist - full_air, 0.0) * air_share;
	float haze = 1.0 - exp(-fog_density * air);
	// The reflected sky is light the water sends, not lit by the sun.
	ALBEDO = water * 0.35 * (1.0 - haze);
	EMISSION = c * 0.75 * (1.0 - haze) + haze_color * haze;
	ROUGHNESS = 0.08;
	SPECULAR = 0.6;
	METALLIC = 0.0;
}
