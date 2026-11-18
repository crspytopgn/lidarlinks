// The look effects drawn over the 3D view, like a ReShade preset: contrast-
// adaptive sharpening (after AMD's CAS), colour grading, vignette and film
// grain. One full-screen pass that reads the rendered frame, so it works the
// same in Forward+ and in Compatibility (the web build). PostProcess sets
// the uniforms from GraphicsSettings.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float sharpen = 0.0; // 0 to 1
uniform float exposure = 1.0;
uniform float contrast = 1.0;
uniform float saturation = 1.0;
uniform vec3 tint = vec3(1.0); // white balance
uniform vec3 shadow_tint = vec3(1.0); // colour of the darks, for the film look
uniform float vignette = 0.0;
uniform float grain = 0.0;
uniform float curve = 0.0; // filmic S-curve: deeper shadows, brighter highlights
// Heat shimmer: on a warm day the air over the course boils, and a long
// lens looking down the hole shows it as a rippling wobble on the far
// fairway, the green and the tree line, never on the ground at your feet.
// The 3D view's depth isn't readable here in Compatibility, so distance is
// worked out from the row's angle below the level horizon and the
// camera's height over the ground (flat ground assumed).
uniform float shimmer = 0.0; // displacement in pixels at 1080p, 0 = off
uniform float horizon_y = 0.5; // screen y (0 top, 1 bottom) of the level horizon
uniform float fov_radians = 0.7; // the camera's vertical field of view
uniform float eye_height = 2.0; // metres above the ground
// The learned grade (tools/grade/fit_grade.py): a 32x32x32 colour lookup
// fitted so the sky, turf, trees and sand of our renders land on the
// colours measured in real golf photos. Laid out as 32 slices of 32x32
// side by side (1024x32): red across a slice, green down, blue by slice.
uniform sampler2D grade_lut : filter_linear, repeat_disable;
uniform float lut_mix = 0.0; // 0 = off
// Contrast after the grade, on luminance round a mid grey so colours keep
// their hue (PostProcess: Photoreal in Compatibility). 1 = none.
uniform float finish_contrast = 1.0;
// The time of day's look, after the grade (Scenery TIMES warm, cool, pop):
// sunlit tones tinted `grade_warm.rgb` and shade `grade_cool`, as a
// photographer's split tone (golden sunlit turf against cooler shade, the
// warm glow of GSPro's and TV golf's late light), and colour lifted by
// `grade_warm.a`. The blue sky keeps its blue. (1, 1, 1, 1) and (1, 1, 1)
// leave the picture as it is.
global uniform vec4 grade_warm;
global uniform vec3 grade_cool;
// The broadcast finish (Photoreal), after everything else in the grade:
// TV golf and PGA Tour 2K25 show a clean, fresh green with deep shade, where
// our frames read olive and milky (quality pass, 2026-11-17: 2K25's shaded
// turf measures about 0.16 luminance with a blue-green cast, ours about
// 0.35). `punch_green` turns yellow-greens (turf, leaves) towards green, as
// a fraction of the hue circle; `punch_black` sets the black point (the
// milky veil lifted); `punch_gamma` deepens the mid-darks; `punch_sat`
// puts back the colour the darker shade takes. All 0 or 1 = off.
uniform float punch_green = 0.0;
uniform float punch_black = 0.0;
uniform float punch_gamma = 1.0;
uniform float punch_sat = 1.0;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// The least of the drawn colour the grade keeps in the darks.
const float DARK_FLOOR = 0.5;
// With the broadcast finish on, the floor drops to this, so the shade can
// deepen (the hard black streak it guards against came from stacking the
// S-curve and finish contrast at full strength).
const float PUNCH_DARK_FLOOR = 0.3;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

vec3 lut_lookup(vec3 c) {
	const float N = 32.0;
	c = clamp(c, 0.0, 1.0);
	float b = c.b * (N - 1.0);
	float b0 = floor(b);
	float b1 = min(b0 + 1.0, N - 1.0);
	vec2 at = vec2((c.r * (N - 1.0) + 0.5) / (N * N), (c.g * (N - 1.0) + 0.5) / N);
	vec3 lo = texture(grade_lut, at + vec2(b0 / N, 0.0)).rgb;
	vec3 hi = texture(grade_lut, at + vec2(b1 / N, 0.0)).rgb;
	return mix(lo, hi, b - b0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	if (shimmer > 0.0) {
		float below = (uv.y - horizon_y) * fov_radians; // radians below level
		float dist = below > 0.0 ? eye_height / tan(max(below, 1e-4)) : 1e4;
		// From about 120 m out, and a few degrees up into the trees and
		// hills; the sky above is smooth, so nothing shows there anyway.
		float heat = smoothstep(120.0, 450.0, dist) * (1.0 - smoothstep(0.02, 0.07, -below));
		if (heat > 0.0) {
			// Cells of about 12 by 5 pixels at 1080p (the air lies in thin
			// layers) rising slowly, as hot air does.
			float scale = 1080.0 * SCREEN_PIXEL_SIZE.y;
			vec2 q = FRAGCOORD.xy * scale / vec2(12.0, 5.0) + vec2(TIME * 0.7, TIME * 3.0);
			vec2 wobble = vec2(value_noise(q), value_noise(q * 1.7 + vec2(41.0, 17.0))) - 0.5;
			uv += wobble * vec2(1.0, 0.5) * shimmer * heat * SCREEN_PIXEL_SIZE / scale;
		}
	}
	vec3 c = texture(screen_tex, uv).rgb;
	vec3 c0 = c;
	if (sharpen > 0.0) {
		vec2 px = SCREEN_PIXEL_SIZE;
		vec3 n = texture(screen_tex, uv + vec2(0.0, -px.y)).rgb;
		vec3 s = texture(screen_tex, uv + vec2(0.0, px.y)).rgb;
		vec3 e = texture(screen_tex, uv + vec2(px.x, 0.0)).rgb;
		vec3 w = texture(screen_tex, uv + vec2(-px.x, 0.0)).rgb;
		vec3 lo = min(c, min(min(n, s), min(e, w)));
		vec3 hi = max(c, max(max(n, s), max(e, w)));
		// Sharpen less where the neighbourhood already has strong contrast,
		// so edges don't ring.
		vec3 amp = sqrt(clamp(min(lo, 1.0 - hi) / max(hi, vec3(1e-4)), 0.0, 1.0));
		vec3 k = -amp / mix(8.0, 5.0, sharpen);
		c = clamp((c + (n + s + e + w) * k) / (1.0 + 4.0 * k), 0.0, 1.0);
	}
	c *= exposure * tint;
	float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(vec3(luma), c, saturation);
	c = mix(c * shadow_tint, c, smoothstep(0.0, 0.5, luma));
	c = (c - 0.5) * contrast + 0.5;
	if (curve > 0.0) {
		// On luminance, so colours keep their hue.
		float l = max(dot(c, vec3(0.2126, 0.7152, 0.0722)), 1e-4);
		float lc = clamp(l, 0.0, 1.0);
		float s_curve = lc * lc * (3.0 - 2.0 * lc);
		c *= mix(l, s_curve, curve) / l;
	}
	if (lut_mix > 0.0) {
		c = mix(c, lut_lookup(c), lut_mix);
	}
	if (finish_contrast != 1.0) {
		float l = max(dot(c, vec3(0.2126, 0.7152, 0.0722)), 1e-4);
		float lt = clamp((l - 0.48) * finish_contrast + 0.48, 0.0, 1.0);
		c *= lt / l;
	}
	if (grade_warm != vec4(1.0) || grade_cool != vec3(1.0)) {
		const vec3 W = vec3(0.2126, 0.7152, 0.0722);
		float l = max(dot(c, W), 1e-4);
		float t = smoothstep(0.25, 0.75, l);
		// Sky: blue well above red and green.
		float sky = smoothstep(0.04, 0.16, c.b - max(c.r, c.g));
		vec3 tone = mix(vec3(1.0), mix(grade_cool, grade_warm.rgb, t), 1.0 - sky);
		vec3 g = c * tone;
		float lg = max(dot(g, W), 1e-4);
		g = mix(vec3(lg), g, mix(grade_warm.a, 1.0, sky));
		c = max(g * (l / max(dot(g, W), 1e-4)), vec3(0.0));
	}
	if (punch_green > 0.0) {
		// Yellow-greens (hue near 72 degrees, 47 to 97) turn greener; greys, skin,
		// sand and sky are left alone.
		vec3 h = rgb2hsv(c);
		float w = clamp(1.0 - abs(h.x - 0.2) / 0.07, 0.0, 1.0) * clamp(h.y * 3.0, 0.0, 1.0);
		h.x += punch_green * w;
		c = hsv2rgb(h);
	}
	if (punch_black > 0.0 || punch_gamma != 1.0 || punch_sat != 1.0) {
		const vec3 W = vec3(0.2126, 0.7152, 0.0722);
		float l = max(dot(c, W), 1e-4);
		float lt = pow(clamp((l - punch_black) / (1.0 - punch_black), 0.0, 1.0), punch_gamma);
		c *= lt / l;
		float l2 = dot(c, W);
		c = max(vec3(l2) + (c - vec3(l2)) * punch_sat, vec3(0.0));
	}
	// The grade deepens the darks, but no further than DARK_FLOOR of what
	// the renderer drew: the S-curve, the learned grade and the finish
	// contrast together took the shaded side of the golfer's trousers from
	// about 0.1 to pure black, a hard black streak down the leg.
	c = max(c, c0 * (punch_black > 0.0 ? PUNCH_DARK_FLOOR : DARK_FLOOR));
	vec2 d = uv - 0.5;
	c *= 1.0 - vignette * smoothstep(0.15, 0.75, dot(d, d) * 2.0);
	c += (hash(FRAGCOORD.xy + fract(TIME) * 913.0) - 0.5) * grain;
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
