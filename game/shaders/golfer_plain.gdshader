shader_type spatial;
// A golfer's plain parts (the cap, the glove, a person's modelled hair):
// one colour, or a texture, lit like the rest of the body
// (golfer_person.gdshader) rather than as a StandardMaterial3D. As those,
// a white cap took none of the web's people_light, so it glowed brighter
// than the face under it, flat, with no shade under its brim.
render_mode blend_mix, depth_draw_opaque, cull_back;

#include "res://shaders/golfer_plain.gdshaderinc"
