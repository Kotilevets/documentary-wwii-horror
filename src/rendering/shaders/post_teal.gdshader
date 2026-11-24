// Pass for stencil 2 (interactive objects, hiding spots, documents):
// muted blue-green (G and B kept with lowered saturation), never neon.
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled;
stencil_mode read, compare_equal, 2;

#include "res://src/rendering/shaders/film_common.gdshaderinc"

uniform float saturation : hint_range(0.0, 1.0) = 0.4;
// Minimal blue-green tint so that grey-textured props still read as interactive.
uniform vec3 tint_floor = vec3(0.72, 1.0, 0.95);
uniform float tint_floor_amount : hint_range(0.0, 1.0) = 0.6;
// Interactive objects are lifted a little so they read in the dark.
uniform float lift : hint_range(0.0, 0.4) = 0.12;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

void fragment() {
	vec3 src = screen_color(SCREEN_UV);
	float l = graded_luma(src) * (1.0 - lift) + lift;
	vec3 gb = vec3(min(src.r, l) * 0.8, max(src.g, l), max(src.b, l));
	vec3 c = mix(vec3(l), gb, saturation);
	c = mix(c, l * tint_floor, tint_floor_amount);
	ALBEDO = film_finish(c, SCREEN_UV, FRAGCOORD.xy, TIME);
}
