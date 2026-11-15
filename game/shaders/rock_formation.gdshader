// The sandstone formations of desert courses (RockFormations): bedded,
// varnished rock (rock_strata.gdshaderinc) at the scale of towers seen from
// tens of metres, with the free cliff photoscan (FreeAssets "cliff") laid
// over it close up for grain and cracks, projected from the three axes so
// the procedural meshes need no UVs. COLOR.r darkens the rubble at a
// formation's foot. Cloud shadows drift over it as over the ground.
// Works in Forward+ and Compatibility.
shader_type spatial;
render_mode cull_back;

#include "res://shaders/ground_shade.gdshaderinc"
#include "res://shaders/rock_strata.gdshaderinc"

uniform vec3 rock_color : source_color = vec3(0.66, 0.33, 0.19);
uniform vec3 rock2_color : source_color = vec3(0.8, 0.55, 0.38);
uniform bool has_detail = false;
uniform sampler2D detail_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_normal : filter_linear_mipmap, repeat_enable;
uniform vec3 detail_mean = vec3(0.5);
uniform float detail_metres = 6.0; // one tile of the photoscan
uniform float detail_fade = 450.0; // metres: beyond, the strata alone

varying vec3 world;
varying vec3 wnormal;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(wnormal);
	vec3 c = strata_color(world, n, rock_color, rock2_color, 1.0);
	c *= COLOR.r;
	float dist = distance(world, CAMERA_POSITION_WORLD);
	if (has_detail) {
		float near = 1.0 - smoothstep(detail_fade * 0.5, detail_fade, dist);
		if (near > 0.0) {
			vec3 w = pow(abs(n), vec3(4.0));
			w /= (w.x + w.y + w.z);
			vec2 ux = world.zy / detail_metres;
			vec2 uy = world.xz / detail_metres;
			vec2 uz = world.xy / detail_metres;
			vec3 tex = texture(detail_albedo, ux).rgb * w.x + texture(detail_albedo, uy).rgb * w.y + texture(detail_albedo, uz).rgb * w.z;
			// The photo's light and dark, not its colour: the strata set that.
			float lum = dot(tex, vec3(0.3, 0.59, 0.11)) / max(dot(detail_mean, vec3(0.3, 0.59, 0.11)), 0.05);
			// A second, larger sampling breaks the tiling and adds the
			// broader cracks and pocks of a real face; contrast raised so it
			// reads in shade too, where the bumps don't.
			vec3 big = texture(detail_albedo, ux * 0.27 + 0.31).rgb * w.x + texture(detail_albedo, uy * 0.27 + 0.31).rgb * w.y + texture(detail_albedo, uz * 0.27 + 0.31).rgb * w.z;
			float lum2 = dot(big, vec3(0.3, 0.59, 0.11)) / max(dot(detail_mean, vec3(0.3, 0.59, 0.11)), 0.05);
			lum = pow(clamp(lum, 0.3, 1.8), 1.35) * mix(1.0, clamp(lum2, 0.5, 1.5), 0.6);
			c *= mix(1.0, clamp(lum, 0.3, 1.7), near * 0.9);
			// The scan's bumps, in world space (whiteout blend; the meshes
			// have no tangents).
			vec3 tx = texture(detail_normal, ux).xyz * 2.0 - 1.0;
			vec3 ty = texture(detail_normal, uy).xyz * 2.0 - 1.0;
			vec3 tz = texture(detail_normal, uz).xyz * 2.0 - 1.0;
			tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
			ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
			tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
			vec3 wn = normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
			NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(wn, 0.0)).xyz, near * 0.8));
			// Cracks and pockets hold shade even out of the sun.
			float cavity = smoothstep(0.55, 0.98, dot(wn, n));
			c *= mix(1.0, 0.45 + 0.55 * cavity, near * 0.7);
		}
	}
	c *= cloud_light(world.xz);
	ALBEDO = c;
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
}
