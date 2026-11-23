// Soft shading where the golfer's own body crowds the light out: the shirt
// under and between the arms, the inside of the arms, between the legs,
// the armpits and under the chin. A real body is never lit evenly all
// over, and without this the free golfer looks like a cut-out painted in
// flat colours, the early-2000s game look, above all on Compatibility,
// which has no screen-space ambient occlusion at all.
//
// Each limb and the trunk is a capsule (GolferCloth.occluders sets them
// every frame from the posed skeleton, in world space). A capsule the
// surface faces, close by, blocks some of its sky: about (cos angle) times
// (radius / distance)^1.5 of it, between the share a sphere covers
// (power 2) and a long cylinder's (power 1).
// A surface on the capsule's own limb faces away from it, so a limb never
// darkens itself. On the shaded side it takes ambient light (AO); some of
// the sun as well (contact_share), as limbs pressed together shade each
// other there more than the sun's shadow map can resolve.

const int OCCLUDERS = 11;
uniform vec4 occ_a[11]; // xyz one end, w radius
uniform vec4 occ_b[11]; // xyz the other end
uniform float occ_strength = 0.0; // 0 off (until GolferCloth sets it)
uniform float contact_share = 0.7;

varying vec3 occ_pos;
varying vec3 occ_normal;

// Set at the end of vertex() (a function may not assign varyings):
//   occ_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
//   occ_normal = mat3(MODEL_MATRIX) * NORMAL;

// 1 fully open to the sky, less where the body closes it in, at world
// position `p` facing `n`: body_occlusion(occ_pos, occ_normal).
float body_occlusion(vec3 p, vec3 normal) {
	if (occ_strength <= 0.0) {
		return 1.0;
	}
	vec3 n = normalize(normal);
	float open = 1.0;
	for (int i = 0; i < OCCLUDERS; i++) {
		vec3 a = occ_a[i].xyz;
		float r = occ_a[i].w;
		vec3 ab = occ_b[i].xyz - a;
		float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
		vec3 d = a + ab * t - p;
		float l = max(length(d), 1e-4);
		float facing = clamp(dot(n, d) / l, 0.0, 1.0);
		open *= 1.0 - facing * pow(min(r / l, 1.0), 1.5) * occ_strength;
	}
	return clamp(open, 0.3, 1.0);
}

// Daylight on a person in Compatibility (the web build). At Photoreal,
// Scenery lifts that renderer's exposure (COMPAT_EXPOSURE_LIFT) and its fill
// light for the turf, and the fill is one flat colour from every side (no
// sky light, no SSAO). On a person that reads as pale, washed-out skin, flat
// shading and light trousers bright enough to bloom at their edges.
// people_light (Scenery.apply_people_light) takes it back for people:
// x scales the albedo (undoing the exposure lift), y the fill light, and
// z how much more of the fill comes from above than below, as a real
// sky's does. (1, 1, 0) leaves them as they are (Forward+, Classic).
global uniform vec3 people_light;

// The share of the fill light a surface facing world normal `normal` gets:
// most from the sky above, less but not none from below (sunlit turf
// bounces a good share back up onto the legs and under the arms).
float people_fill(vec3 normal) {
	float up = normalize(normal).y * 0.5 + 0.5;
	return people_light.y * mix(1.0, mix(0.7, 1.3, up), people_light.z);
}

// Sunlight bounced off the turf onto a person's shaded side, as EMISSION
// (Compatibility at Photoreal only: Scenery.people_bounce is zero
// elsewhere, where the sky light carries the ground's colour). The flat
// fill there is the sky's blue from every side, so the shade on khaki
// trousers or a face went a cold blue-grey against the warm sunlit side,
// a two-tone cut-out. Real shade on a golf course is warmed by the grass
// below; most on faces turned down or sideways.
global uniform vec3 people_bounce;

vec3 people_ground_bounce(vec3 base, vec3 world_normal, float occ) {
	float down = 0.5 - 0.5 * normalize(world_normal).y;
	return base * people_bounce * down * occ;
}

// Sky light in the shade for people, and the sun's share of the light
// (Scenery.people_sky). Neither renderer lights a person's shade the way
// the open sky does: the flat fill is weak against the sun, so a navy
// shirt went from pale blue on its sunlit side to near black on its
// shaded side, and a golfer stepping into a tree's shadow went near black
// while the turf round his feet (lifted by shade_fill) stayed a mid green.
// rgb is added as emission (a share of the albedo, as the turf's
// shade_fill is), a scales the sun in light(), so the sunlit side keeps its
// brightness and only the shade and the shaded side lift.
// (0, 0, 0, 1) leaves people as they were (Classic lighting).
global uniform vec4 people_sky;

vec3 people_sky_fill(vec3 base, float occ) {
	return base * people_sky.rgb * occ;
}

// The sun's shadow map on a person, in light(): `att` is ATTENUATION,
// `ndl` the surface's own (not normal mapped) facing to the sun,
// dot(people_geo, LIGHT). The map can't resolve a body's own shadow where
// it turns away from the sun: across that terminator its texels, lifted
// by the normal bias, land on and off the surface, and the trousers and
// shirt showed ragged lit and shaded tongues down their sides. Light
// falling off with N.L already darkens that band, so the map's say fades
// in only once the surface faces the sun; a limb's shadow across the
// body, the bag's and a tree's still fall where it does.
float people_shadow(float att, float ndl) {
	return mix(1.0, att, smoothstep(0.0, 0.35, ndl));
}

// The surface's own normal (view space) for people_shadow: set it in
// fragment() from NORMAL before any NORMAL_MAP.
varying vec3 people_geo;
