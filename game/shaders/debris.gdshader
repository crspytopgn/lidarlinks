// The woodland floor under tree lines (DebrisField), from the private
// Megascans pack: leaf and needle litter patches draped on the ground, and
// scanned leaf piles, fallen branches, cones, logs and stumps. Albedo (with
// opacity as alpha where the scan has one) and a normal map; lit like the
// ground around it (the baked tree shade, the cloud shadows and the
// Compatibility shade fill), so a log in a wood's shade sits in that shade.
// Each piece dissolves out by a screen-space dither over the last
// fade_band metres before fade_end, so nothing pops. Forward+ and
// Compatibility.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// True for scans cut out by their opacity (litter, leaf piles, branches).
uniform bool cutout = false;
uniform float fade_end = 60.0;
uniform float fade_band = 10.0;
// A colour grade per kind (DebrisField.TONE): Megascans' autumn litter is
// bright orange, a course's summer floor a darker, duller brown.
uniform vec3 tone = vec3(1.0);
uniform float saturation = 1.0;
uniform float brightness = 1.0;

#include "res://shaders/ground_shade.gdshaderinc"

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dist = length(VERTEX);
	if (dist > fade_end) {
		discard;
	}
	float fade = clamp((fade_end - dist) / fade_band, 0.0, 1.0);
	float t = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (t >= fade) {
		discard;
	}
	vec4 c = texture(albedo_tex, UV);
	if (cutout) {
		// Smaller mips thin the edges under the alpha test: hold them up.
		vec2 texels = vec2(textureSize(albedo_tex, 0));
		float lod = log2(max(max(length(dFdx(UV) * texels), length(dFdy(UV) * texels)), 1.0));
		if (c.a * (1.0 + lod * 0.08) < 0.5) {
			discard;
		}
	}
	float luma = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 col = mix(vec3(luma), c.rgb, saturation) * tone * brightness;
	vec3 albedo = min(col, vec3(0.8));
	ALBEDO = albedo * shade_fill.a * ground_shading(world_pos.xz, dist);
	EMISSION = albedo * shade_fill.rgb;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	ROUGHNESS = 0.9;
	SPECULAR = 0.25;
}
