// The green-reading grid's lines (GreenGrid), drawn as thin ribbons with
// soft, anti-aliased edges instead of one-pixel GL lines, which neither
// renderer smooths: those broke into stair steps and dashes, worst on the
// web build without MSAA.
//
// Each line is a strip of quads along the ground. A vertex carries its spot
// on the line (VERTEX), the way the line runs (NORMAL) and which edge it is
// (UV.x, -1 or +1); here the strip is widened across the screen so the line
// keeps `width` metres (painted on the turf) but never thins below about a
// pixel and a quarter, as the old lines' pixel, a touch fainter there. The whole line is
// drawn a little towards the camera (same place on screen, nearer in
// depth) so it rides on the turf instead of dipping into it in dashes.
// Works in Forward+ and Compatibility.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, skip_vertex_transform, fog_disabled;

// The line's width on the ground, metres.
uniform float width = 0.02;
// UV.y: this line's width as a multiple of `width` (the downhill ticks are wider).
// Never narrower than this on screen (pixels); a line held at it is drawn
// a little fainter. The wide pieces (the running dots) keep
// `min_pixels * dot_min_scale`, so they still read as dots far off.
uniform float min_pixels = 1.75;
uniform float dot_min_scale = 2.0;
// A soft dark edge round every line and dot (pixels each side, and its
// strength next to the line's own alpha), so pale lines still stand out
// on a sunlit green, as TV graphics outline theirs.
uniform float halo_pixels = 1.0;
uniform float halo = 0.4;
uniform vec3 halo_colour = vec3(0.02, 0.05, 0.02);
// How much nearer the camera to draw the line, as a share of its distance.
uniform float pull = 0.004;

// The flowing dots (UV2.y > 0): UV2.x is how far along its streamline the
// vertex is (0 to 1) plus twice a whole number that sets the dot's phase,
// in sixteenths; UV2.y is how many times a second a dot runs its length.
varying float flow_s;
varying float flow_rate;
varying float flow_phase;
varying float across;
varying float half_px;
varying float coverage;

void vertex() {
	float k = floor(UV2.x * 0.5);
	flow_s = UV2.x - k * 2.0;
	flow_phase = k / 16.0;
	flow_rate = UV2.y;
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec4 ahead = MODELVIEW_MATRIX * vec4(VERTEX + NORMAL * 0.05, 1.0);
	vec4 clip = PROJECTION_MATRIX * view;
	vec4 clip_b = PROJECTION_MATRIX * ahead;
	vec2 size = VIEWPORT_SIZE;
	vec2 dir = (clip_b.xy / clip_b.w - clip.xy / clip.w) * size;
	dir = length(dir) > 1e-5 ? normalize(dir) : vec2(1.0, 0.0);
	vec2 perp = vec2(-dir.y, dir.x);
	// The line's width in pixels where it is.
	float px = width * UV.y * PROJECTION_MATRIX[1][1] * size.y * 0.5 / max(clip.w, 1e-4);
	float least = min_pixels * (UV.y > 1.5 ? dot_min_scale : 1.0);
	float drawn = max(px, least);
	// Far lines held at their least width fade back: drawn at full
	// strength the far side of the green became a dense white wire mesh,
	// where 2K25's and TV's grids fade into the turf with distance. Not
	// too far, though: at 0.35 the whole grid vanished from the Green
	// Analyzer's views from above.
	coverage = mix(0.6, 1.0, clamp(px / least, 0.0, 1.0));
	half_px = drawn * 0.5;
	// The dark edge, then one pixel more each side for the soft edge.
	float out_px = half_px + halo_pixels + 1.0;
	across = UV.x * out_px;
	clip.xy += perp * UV.x * out_px * 2.0 / size * clip.w;
	// Nearer in depth: the same spot on screen, a little in front.
	vec4 pulled = PROJECTION_MATRIX * vec4(view.xyz * (1.0 - pull), 1.0);
	clip.z = pulled.z / pulled.w * clip.w;
	POSITION = clip;
}

void fragment() {
	float d = abs(across);
	float edge = clamp(half_px + 0.5 - d, 0.0, 1.0);
	float rim = clamp(half_px + halo_pixels + 0.5 - d, 0.0, 1.0);
	float a = COLOR.a;
	if (flow_rate > 0.0) {
		// A dot running downhill along its streamline, faster where the
		// green is steeper, with a faint trail that thickens downhill so a
		// still frame shows the way too. The streamline fades in and out
		// at its ends so dots don't pop.
		float head = fract(TIME * flow_rate + flow_phase);
		float behind = head - flow_s;
		behind += behind < -0.5 ? 1.0 : 0.0;
		float dot_a = smoothstep(0.0, 0.02, behind + 0.02) * (1.0 - smoothstep(0.05, 0.12, behind));
		float trail = 0.25 + 0.3 * flow_s;
		float ends = smoothstep(0.0, 0.12, flow_s) * smoothstep(1.0, 0.85, flow_s);
		a *= max(dot_a, trail) * ends;
	}
	// The line over its dark edge.
	float line_a = a * edge * coverage;
	float rim_a = halo * a * rim * coverage * (1.0 - line_a);
	float total = line_a + rim_a;
	ALBEDO = total > 1e-4 ? (COLOR.rgb * line_a + halo_colour * rim_a) / total : COLOR.rgb;
	ALPHA = total;
}
