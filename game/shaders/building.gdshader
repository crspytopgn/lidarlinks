// A course's buildings (CourseBuildings): walls of brick or render with
// rows of windows, and roofs of slate or clay tiles, worked out from UV
// (metres along and up a wall; along and up the slope of a roof) so no
// texture is needed. COLOR carries each building's wall or roof colour,
// UV2.y says which part (0 wall, 1 pitched roof, 2 flat roof) and UV2.x
// the windows (0 none, 1 a house's, 2 a clubhouse's or block's).
// Forward+ and Compatibility.
shader_type spatial;
render_mode cull_back;

uniform float storey = 2.8; // metres per floor

varying float part;
varying float windows;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	part = UV2.y;
	windows = UV2.x;
}

void fragment() {
	vec2 m = UV;
	vec3 base = COLOR.rgb;
	float wear = noise(m * 0.7) * 0.5 + noise(m * 3.1) * 0.25;
	if (part < 0.5) {
		// Brick (reddish or yellow) shows its courses; pale walls are render.
		float l = dot(base, vec3(0.2126, 0.7152, 0.0722));
		float brick = 1.0 - smoothstep(0.45, 0.6, l);
		vec2 b = m / vec2(0.225, 0.075);
		b.x += step(1.0, mod(floor(b.y), 2.0)) * 0.5;
		vec2 f = fract(b);
		float mortar = (1.0 - step(0.06, f.y)) + (1.0 - step(0.03, f.x));
		vec3 c = base * mix(0.86, 1.12, hash(floor(b))) ;
		c = mix(c, vec3(0.62, 0.6, 0.55), clamp(mortar, 0.0, 1.0) * 0.6);
		// Render: weathered and a little grainy, never paper white.
		vec3 render = base * (0.88 + 0.1 * wear + 0.06 * (noise(m * 37.0) - 0.5));
		vec3 wall = mix(render, c, brick);
		if (COLOR.a < 0.75) {
			// Clapboard siding: boards 0.18 m deep, each shading to a dark
			// line under the lap of the one above.
			float lap = fract(m.y / 0.18);
			wall = base * (0.9 + 0.08 * wear) * mix(0.62, 1.0, smoothstep(0.0, 0.12, lap)) * mix(1.04, 0.96, lap);
		}
		// Darker at the foot (splash and damp).
		wall *= mix(0.72, 1.0, smoothstep(-0.2, 0.6, m.y));
		ALBEDO = wall;
		ROUGHNESS = 0.9;
		if (windows > 0.5) {
			// Windows on each floor: about 1.2 m wide every 3.3 m on a
			// house, wider and closer on a clubhouse or block.
			bool big = windows > 1.5;
			float bay = big ? 2.6 : 3.3;
			float w = big ? 1.7 : 1.15;
			float h = big ? 1.7 : 1.25;
			float fl = floor(m.y / storey);
			float y = m.y - fl * storey;
			float x = mod(m.x + 0.9, bay);
			float on = step(0.0, m.y) * step(abs(x - bay * 0.5), w * 0.5) * step(abs(y - 1.55), h * 0.5);
			float frame = on * (1.0 - step(abs(x - bay * 0.5), w * 0.5 - 0.07) * step(abs(y - 1.55), h * 0.5 - 0.07));
			// Not every bay has a window, and some are lit or curtained.
			float has = step(0.18, hash(vec2(floor((m.x + 0.9) / bay), fl) + base.rg * 13.0));
			on *= has;
			frame *= has;
			// Glass: dark, with the sky's light toward the top of the pane
			// and a net curtain or blind in some.
			float py = clamp((y - 1.55) / h + 0.5, 0.0, 1.0);
			vec3 glass = mix(vec3(0.04, 0.05, 0.06), vec3(0.2, 0.23, 0.27), py * py);
			glass = mix(glass, vec3(0.55, 0.53, 0.5), step(0.75, hash(vec2(floor((m.x + 0.9) / bay), fl + 4.0))) * 0.6);
			ALBEDO = mix(ALBEDO, glass, on - frame);
			ALBEDO = mix(ALBEDO, vec3(0.88, 0.88, 0.85), frame);
			ROUGHNESS = mix(ROUGHNESS, 0.08, on - frame);
			SPECULAR = mix(0.5, 0.9, on - frame);
			// The window sits back in the wall a little.
			AO = 1.0 - 0.35 * frame;
		}
	} else if (part < 1.5) {
		// Roof tiles or slates: rows up the slope, staggered joints.
		vec2 t = m / vec2(0.28, 0.2);
		t.x += step(1.0, mod(floor(t.y), 2.0)) * 0.5;
		vec2 f = fract(t);
		float edge = smoothstep(0.0, 0.18, f.y);
		vec3 c = base * mix(0.85, 1.12, hash(floor(t)));
		c *= mix(0.7, 1.0, edge) * mix(0.9, 1.0, smoothstep(0.0, 0.06, min(f.x, 1.0 - f.x)));
		// Moss and weathering.
		c = mix(c, c * vec3(0.85, 1.0, 0.7), smoothstep(0.55, 0.85, wear) * 0.6);
		ALBEDO = c;
		ROUGHNESS = 0.8;
	} else {
		// Flat roof: felt or membrane, streaked.
		ALBEDO = base * (0.75 + 0.3 * wear);
		ROUGHNESS = 0.85;
	}
}
