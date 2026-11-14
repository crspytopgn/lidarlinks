shader_type spatial;
// A realistic person's body (tools/golfer/rocketbox.py): skin and clothes
// painted in one photographed texture. The player's colours replace the
// shirt's, trousers' and shoes' (the regions map: R shirt, G trousers,
// B shoes), keeping the cloth's own folds and weave: the new colour is
// scaled by how much lighter or darker each texel is than its garment's
// median (region_means, linear luminance).
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

#include "res://shaders/golfer_occlusion.gdshaderinc"
#include "res://shaders/golfer_flex.gdshaderinc"

uniform sampler2D texture_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D texture_normal : hint_roughness_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal = false;
uniform sampler2D regions : hint_default_black, filter_linear_mipmap;
uniform vec4 top : source_color = vec4(1.0);
uniform vec4 bottom : source_color = vec4(1.0);
uniform vec4 shoes : source_color = vec4(1.0);
uniform vec3 region_means = vec3(0.2);
// 0 keeps the person's own clothes, 1 the player's colours.
uniform float recolour = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float rim = 0.12;
// Soft terminator: light wraps a little past the edge where a surface
// turns from the sun, as it does through cloth fibres and skin, so the lit
// and shaded halves of a shirt meet in a soft band, not a ruled line.
uniform float wrap : hint_range(0.0, 1.0) = 0.3;

vec3 dye(vec3 tex, vec3 target, float mean) {
	float lum = dot(tex, vec3(0.2126, 0.7152, 0.0722));
	// Folds and weave as brightness around the new colour, held in a sane
	// range so a seam or a highlight doesn't burn out.
	// 0.8: the creator's cloth texture averages that, so a colour looks the
	// same on both kinds of golfer.
	// 1.8: the folds deeper than the source's, as a light colour
	// in the sun otherwise reads flat next to the photographed original.
	return target * 0.7 * clamp(pow(lum / max(mean, 0.01), 1.8), 0.15, 1.8);
}

// Skin, 1, where the regions map has none of the shirt, trousers or shoes.
float skin_of(vec3 r) {
	return 1.0 - clamp(max(r.r, max(r.g, r.b)) * 2.0, 0.0, 1.0);
}

void vertex() {
	float skin = flex_on > 0.0 ? skin_of(textureLod(regions, UV, 3.0).rgb * recolour) : 0.0;
	flex_v = vec4(UV2.x, UV2.y * skin, COLOR.b * skin, 0.0);
	flex_cs = COLOR.rg * 2.0 - 1.0;
	VERTEX += NORMAL * flex_swell(flex_v, flex_cs);
	occ_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	occ_normal = mat3(MODEL_MATRIX) * NORMAL;
}

varying float rim_amount;

void fragment() {
	vec3 tex = texture(texture_albedo, UV).rgb;
	vec3 m = texture(regions, UV).rgb * recolour;
	vec4 flex = flex_fragment(flex_v * vec4(1.0, skin_of(m), skin_of(m), 1.0), flex_cs, NORMAL, VIEW_MATRIX);
	NORMAL = flex.xyz;
	vec3 c = tex;
	c = mix(c, dye(tex, top.rgb, region_means.x), m.r);
	c = mix(c, dye(tex, bottom.rgb, region_means.y), m.g);
	c = mix(c, dye(tex, shoes.rgb, region_means.z), m.b);
	// No brighter than real white cloth (GolferSurface.WHITEST): the deep
	// folds' highlights on a light colour otherwise reach pure white.
	c *= min(1.0, 0.8 / max(max(c.r, c.g), max(c.b, 1e-3)));
	float occ = body_occlusion(occ_pos, occ_normal);
	AO = occ * people_fill(occ_normal);
	ALBEDO = c * mix(1.0, occ, contact_share) * flex.w * people_light.x;
	if (flex_debug > 0.0) {
		ALBEDO = flex_debug_colour(flex_v, flex_cs);
	}
	if (use_normal) {
		NORMAL_MAP = texture(texture_normal, UV).rgb;
	}
	ROUGHNESS = roughness;
	SPECULAR = 0.3;
	// The fibres' rim light shows on dark cloth, but on light cloth only
	// adds a glowing halo round the outline (GolferSurface.cloth_rim).
	rim_amount = rim * (1.0 - 0.75 * clamp(dot(c, vec3(0.2126, 0.7152, 0.0722)) / 0.8, 0.0, 1.0));
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float d = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	DIFFUSE_LIGHT += d * ATTENUATION * LIGHT_COLOR / PI;
	// A faint cloth sheen (GGX, Schlick Fresnel at SPECULAR 0.3).
	float nl = max(ndl, 0.0);
	float nv = max(dot(NORMAL, VIEW), 1e-3);
	vec3 h = normalize(VIEW + LIGHT);
	float nh = max(dot(NORMAL, h), 0.0);
	float a = ROUGHNESS * ROUGHNESS;
	float a2 = a * a;
	float den = nh * nh * (a2 - 1.0) + 1.0;
	float dist = a2 / (PI * den * den);
	float k = a * 0.5;
	float vis = 0.25 / ((nl * (1.0 - k) + k) * (nv * (1.0 - k) + k));
	float f0 = 0.024;
	float fres = f0 + (1.0 - f0) * pow(1.0 - max(dot(LIGHT, h), 0.0), 5.0);
	SPECULAR_LIGHT += nl * dist * vis * fres * ATTENUATION * LIGHT_COLOR;
	// The fibres' rim, as Godot's RIM with RIM_TINT 0.7.
	float r = pow(1.0 - nv, 4.0) * rim_amount * clamp(ndl + 0.3, 0.0, 1.0);
	DIFFUSE_LIGHT += r * mix(vec3(1.0), ALBEDO, 0.7) / max(ALBEDO, vec3(0.05)) * ATTENUATION * LIGHT_COLOR / PI;
}
