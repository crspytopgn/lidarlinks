// Shared by the land round the course (landscape.gdshader) and the rock
// formations (rock_formation.gdshader): value noise, and the colour of
// bedded rock. Sandstone cliffs on the Colorado Plateau read as stacked
// horizontal beds of slightly different reds and buffs, a metre to a few
// metres thick, that wander a little in height, streaked from the rims down
// by dark desert varnish where water runs. Works in Forward+ and
// Compatibility (no derivatives beyond fwidth, no texture arrays).

float strata_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float strata_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(strata_hash(i), strata_hash(i + vec2(1.0, 0.0)), f.x),
		mix(strata_hash(i + vec2(0.0, 1.0)), strata_hash(i + vec2(1.0)), f.x), f.y);
}

float strata_fbm(vec2 p) {
	return strata_noise(p) * 0.55 + strata_noise(p * 2.03 + vec2(5.2, 1.3)) * 0.3 + strata_noise(p * 4.1 + vec2(1.7, 9.2)) * 0.15;
}

// Rock colour at world position `w` on a face whose outward normal is `n`:
// beds between `rock_a` and `rock_b`, thicker and thinner sets, the bed
// lines wandering by a metre or two; varnish streaks down steep faces;
// paler, dustier where the face tilts up (ledges catch sand). `scale` is 1
// for formations seen from tens of metres and larger for distant cliffs
// (fewer, thicker beds, so they don't shimmer).
vec3 strata_color(vec3 w, vec3 n, vec3 rock_a, vec3 rock_b, float scale) {
	float wander = strata_fbm(w.xz / (40.0 * scale)) * 3.0 * scale;
	float y = w.y + wander;
	// Beds of uneven thickness (noise up the height, not a regular sine),
	// grouped into lighter and darker sets.
	float beds = strata_noise(vec2(y * 0.9 / scale, 0.5));
	float sets = strata_noise(vec2(y * 0.13 / scale, 3.5));
	float big = strata_fbm(vec2(y / (9.0 * scale), 0.5));
	float t = clamp(beds * 0.45 + sets * 0.5 + big * 0.45 - 0.2, 0.0, 1.0);
	vec3 c = mix(rock_a, rock_b, smoothstep(0.2, 0.9, t));
	// A few thin darker partings between beds.
	float parting = smoothstep(0.93, 0.99, strata_noise(vec2(y * 2.3 / scale, 9.1)));
	c *= 1.0 - 0.12 * parting;
	// Desert varnish: a few broad dark streaks down the steep faces, from
	// the rims down, fading out at their feet.
	float steep = 1.0 - smoothstep(0.35, 0.7, abs(n.y));
	// Streaks hang straight down: a noise over the ground plan only, so
	// curved faces don't swirl them.
	float streak = strata_noise(w.xz / (7.0 * scale) + vec2(0.0, y / (120.0 * scale)));
	streak *= strata_noise(w.xz / (19.0 * scale) + vec2(3.1, y / (40.0 * scale)));
	c *= 1.0 - steep * 0.22 * smoothstep(0.45, 0.8, streak);
	// Ledges and gentle tops collect pale dust and sand.
	float up = smoothstep(0.55, 0.9, n.y);
	c = mix(c, rock_b * 1.08, up * 0.45 / scale);
	// Patches of lighter and darker rock.
	c *= 0.86 + 0.28 * strata_fbm(w.xz / (13.0 * scale) + w.y / (17.0 * scale));
	return c;
}
