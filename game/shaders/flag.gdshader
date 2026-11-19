// The pin flag (main.gd _add_flag). The mesh is a flat plane in local x/y,
// its left edge on the pole; this shader swings it round the pole to fly
// downwind, lifts it from hanging limp to standing out as the wind gets
// up, and runs a travelling ripple down it. The wind and the ripple phase
// come from FlagMotion (graphics/flag_motion.gd) each frame: the wind
// carries the visual gusts eased by the cloth's inertia, and the phase is
// integrated there so a gust never makes the ripple jump. Tuned against
// tour footage: a light breeze barely lifts the flag, 10 mph flies it at
// about 55 degrees with a lazy wave, 20 mph holds it straight out with a
// small quick ripple and a flicking tail. Works in Forward+ and
// Compatibility.
shader_type spatial;
render_mode cull_disabled;

global uniform vec2 flag_wind; // eased air velocity at the flag, m/s (x, z)
global uniform float flag_phase; // ripple cycles, 0..1
uniform float flag_length = 0.51; // 20 in, the usual tour flag
uniform float flag_height = 0.36; // 14 in
uniform vec4 albedo : source_color = vec4(0.86, 0.07, 0.05, 1.0);

varying float fold;

void vertex() {
	float u = clamp(VERTEX.x / flag_length + 0.5, 0.0, 1.0); // 0 at the pole
	float v = clamp(0.5 - VERTEX.y / flag_height, 0.0, 1.0); // 0 at the top
	float speed = length(flag_wind);
	vec2 dir = speed > 0.05 ? flag_wind / speed : vec2(0.6, 0.8);
	// Under about 1 m/s the flag hangs; 4.5 m/s (10 mph) flies it at about
	// 55 degrees; 9 m/s (20 mph) and over holds it all but straight out.
	float lift = pow(clamp((speed - 0.6) / 8.4, 0.0, 1.0), 0.6);
	float theta = mix(0.1, 1.45, lift); // angle from hanging straight down
	vec3 out_dir = vec3(dir.x * sin(theta), -cos(theta), dir.y * sin(theta));
	vec3 side = vec3(-dir.y, 0.0, dir.x);
	// About one wave along the flag when it flies, a longer lazier one
	// when it hangs. The cloth is held at the pole and the wave grows to
	// the free edge; the corners lead the middle a little.
	float k = 6.2832 * mix(0.55, 1.05, lift);
	float calm = clamp(speed / 2.0, 0.0, 1.0); // dead air: no ripple at all
	float amp = mix(0.035, 0.026, lift) * calm * u * sqrt(u);
	float phase = u * k - flag_phase * 6.2832 + v * 0.9;
	// The tail flicks at twice the rate once the flag is out.
	float flick = sin(2.0 * phase + 0.7) * 0.006 * lift * u * u * u;
	vec3 p = vec3(0.0, -v * flag_height, 0.0) + out_dir * (u * flag_length) + side * (sin(phase) * amp + flick);
	// The free edge sags a little below the top seam in a light wind.
	p.y -= u * u * v * (1.0 - lift) * 0.04;
	VERTEX = p;
	float slope = cos(phase) * k * amp / flag_length;
	NORMAL = normalize(side - out_dir * slope);
	fold = cos(phase);
}

void fragment() {
	// The troughs of each ripple catch a little less light.
	ALBEDO = albedo.rgb * (0.9 + 0.1 * fold);
	ROUGHNESS = 0.85;
	// Thin cloth: the sun shows through it from behind, as on TV.
	BACKLIGHT = albedo.rgb * 0.6;
}
