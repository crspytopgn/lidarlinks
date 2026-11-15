// The real land round a course, out to the horizon (Landscape): one lit
// height-field mesh coloured by slope and height for its biome (Biome.LAND),
// so a red-rock valley shows bedded sandstone walls and pale sand floors, a
// mountain course rock, forest and snow. Distance haze is its own (the
// scene's fog is set for the course and would bury land kilometres off): the
// first FULL_AIR metres take the scene's fog as it is, beyond that a share
// `air_share` of it, as FarScenery does. Cloud shadows drift over it like
// the course. Works in Forward+ and Compatibility.
shader_type spatial;
render_mode cull_back, fog_disabled;

#include "res://shaders/ground_shade.gdshaderinc"
#include "res://shaders/rock_strata.gdshaderinc"

uniform vec3 low_color : source_color = vec3(0.7, 0.43, 0.27);
uniform vec3 high_color : source_color = vec3(0.62, 0.42, 0.3);
uniform vec3 rock_color : source_color = vec3(0.66, 0.33, 0.19);
uniform vec3 rock2_color : source_color = vec3(0.8, 0.55, 0.38);
uniform vec3 plant_color : source_color = vec3(0.24, 0.27, 0.16);
uniform float cover = 0.25; // how much of the gentle ground has plants on it
uniform float top = 600.0; // metres: the low colour gives way to the high one by here
uniform float snow_from = 99999.0;
uniform vec3 haze_color : source_color = vec3(0.7, 0.78, 0.86);
uniform float fog_density = 0.0005;
uniform float air_share = 0.33;
uniform float full_air = 300.0;
uniform float brightness = 1.0;

varying vec3 world;
varying vec3 wnormal;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnormal);
	vec3 n_geo = n;
	float slope = 1.0 - n.y;
	float big = strata_fbm(world.xz / 220.0);
	float mid = strata_fbm(world.xz / 47.0 + 3.7);
	// Gentle ground: low to high, broken into patches.
	vec3 ground = mix(low_color, high_color, smoothstep(0.0, top, world.y + (big - 0.5) * top * 0.4));
	ground *= 0.88 + 0.24 * mid;
	// Plants dot the gentle ground (scrub, woods), thinning up slopes.
	float plants = smoothstep(1.0 - cover, 1.0 - cover * 0.4, strata_fbm(world.xz / 19.0 + 11.0) * 0.6 + mid * 0.4);
	plants *= 1.0 - smoothstep(0.12, 0.3, slope);
	ground = mix(ground, plant_color, plants * 0.85);
	// Rock wherever it is steep: bedded and varnished, at the scale of
	// cliffs seen from a kilometre or more.
	float rock = smoothstep(0.07, 0.2, slope + (big - 0.5) * 0.08);
	// Crags: the 40 m grid smooths cliffs into slopes, so the rock gets
	// buttresses and gullies in its shading, from the slope of a noise
	// that runs down the fall line.
	if (rock > 0.0) {
		vec2 q = world.xz / 26.0 + vec2(0.0, world.y / 30.0);
		float e = 0.35;
		float gx = strata_fbm(q + vec2(e, 0.0)) - strata_fbm(q - vec2(e, 0.0));
		float gz = strata_fbm(q + vec2(0.0, e)) - strata_fbm(q - vec2(0.0, e));
		vec3 bumped = normalize(n + vec3(-gx, 0.0, -gz) * 1.2 * rock);
		NORMAL = normalize((VIEW_MATRIX * vec4(bumped, 0.0)).xyz);
		n = bumped;
	}
	vec3 c = mix(ground, strata_color(world, n_geo, rock_color, rock2_color, 3.0), rock);
	// Snow on everything but the steepest rock above the snow line.
	float snow = smoothstep(snow_from - 25.0, snow_from + 25.0, world.y + (big - 0.5) * 80.0) * (1.0 - smoothstep(0.45, 0.7, slope));
	c = mix(c, vec3(0.9, 0.92, 0.96), snow);
	float dist = distance(world, CAMERA_POSITION_WORLD);
	c *= cloud_light(world.xz) * brightness;
	float air = min(dist, full_air) + max(dist - full_air, 0.0) * air_share;
	float haze = 1.0 - exp(-fog_density * air);
	ALBEDO = c * (1.0 - haze);
	EMISSION = haze_color * haze;
	ROUGHNESS = mix(0.95, 0.75, snow);
	SPECULAR = 0.2;
}
