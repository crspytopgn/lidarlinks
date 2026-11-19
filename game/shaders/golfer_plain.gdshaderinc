// The body of golfer_plain.gdshader and golfer_plain_two_sided.gdshader
// (a cap's brim is seen from both sides); see golfer_plain.gdshader.

#include "res://shaders/golfer_occlusion.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal = false;
uniform sampler2D texture_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_scale = 1.0;
uniform vec2 uv_scale = vec2(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float specular : hint_range(0.0, 1.0) = 0.3;
uniform float rim = 0.1;
uniform float wrap : hint_range(0.0, 1.0) = 0.3;

varying float rim_amount;

void vertex() {
	occ_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	occ_normal = mat3(MODEL_MATRIX) * NORMAL;
}

void fragment() {
	people_geo = NORMAL;
	vec2 uv = UV * uv_scale;
	vec3 c = albedo.rgb * texture(texture_albedo, uv).rgb;
	float occ = body_occlusion(occ_pos, occ_normal);
	AO = occ * people_fill(occ_normal);
	ALBEDO = c * mix(1.0, occ, contact_share) * people_light.x;
	if (use_normal) {
		NORMAL_MAP = texture(texture_normal, uv).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	EMISSION = people_ground_bounce(ALBEDO, occ_normal, occ);
	ROUGHNESS = roughness;
	SPECULAR = specular;
	rim_amount = rim;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float shade = people_shadow(ATTENUATION, dot(normalize(people_geo), LIGHT));
	float d = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	DIFFUSE_LIGHT += d * shade * LIGHT_COLOR / PI;
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
	float f0 = 0.08 * specular;
	float fres = f0 + (1.0 - f0) * pow(1.0 - max(dot(LIGHT, h), 0.0), 5.0);
	SPECULAR_LIGHT += nl * dist * vis * fres * shade * LIGHT_COLOR;
	float r = pow(1.0 - nv, 4.0) * rim_amount * clamp(ndl + 0.3, 0.0, 1.0);
	DIFFUSE_LIGHT += r * mix(vec3(1.0), ALBEDO, 0.7) / max(ALBEDO, vec3(0.05)) * shade * LIGHT_COLOR / PI;
}
