// Dithered cross-fade between a course tree's levels of detail in a
// MultiMesh (TreeFactory): the full mesh, the lite mesh of a scanned tree
// (from tree_lite_distance) and the impostor (from tree_impostor_distance).
// A hard switch made every tree crossing those distances pop as the camera
// moved, and blink back and forth when it hovered there (the golfer's idle
// camera). Now, over a band of LOD_FADE times the distance either side of
// the switch, each pixel of the tree belongs to one level or the other by a
// screen-space dither, so one level dissolves into the next. The two
// levels use complementary tests on the same threshold: no pixel is drawn
// twice or left as a hole.
global uniform float tree_impostor_distance;
global uniform float tree_lite_distance;

const float LOD_FADE = 0.08;

// 0 nearer than the band around switch distance d0, 1 past it.
float tree_lod_ramp(float d, float d0) {
	float w = d0 * LOD_FADE;
	return clamp((d - d0 + w) / (2.0 * w), 0.0, 1.0);
}

// A level drawn from switch `from` (it fades in there; < 0 for always)
// to switch `to` (it fades out there): x is the ramp in, y the ramp out.
vec2 tree_lod_span(float d, float from, float to) {
	return vec2(from < 0.0 ? 1.0 : tree_lod_ramp(d, from), tree_lod_ramp(d, to));
}

// The span of a MultiMesh tree's mesh in band `which` (see tree_leaves.gdshader).
vec2 tree_lod_band(float d, int which) {
	if (which == 1) {
		return tree_lod_span(d, -1.0, min(tree_lite_distance, tree_impostor_distance));
	}
	if (which == 2) {
		return tree_lod_span(d, tree_lite_distance, tree_impostor_distance);
	}
	return tree_lod_span(d, -1.0, tree_impostor_distance);
}

// True where this level draws nothing at all (fold its vertices away).
bool tree_lod_hidden(vec2 span) {
	return span.x <= 0.0 || span.y >= 1.0 || span.x <= span.y;
}

// True for a pixel of this level that the other level draws instead.
bool tree_lod_discard(vec2 span, vec2 frag) {
	if (span.x >= 1.0 && span.y <= 0.0) {
		return false;
	}
	// Interleaved gradient noise: an even threshold per pixel, no pattern.
	float t = fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));
	return t >= span.x || t < span.y;
}
