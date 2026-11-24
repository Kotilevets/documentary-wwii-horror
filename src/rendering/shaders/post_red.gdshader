// Pass for stencil 1 (blood, Nazi insignia, signal flares):
// keep the red channel, mute G and B for a deep cinematic red.
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled;
stencil_mode read, compare_equal, 1;

#include "res://src/rendering/shaders/film_common.gdshaderinc"

uniform float gb_mute : hint_range(0.0, 1.0) = 0.18;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

void fragment() {
	vec3 src = screen_color(SCREEN_UV);
	float l = graded_luma(src);
	float r = s_curve(levels(max(src.r, luma(src))), contrast * 0.6);
	vec3 c = vec3(max(r, l), l * gb_mute, l * gb_mute);
	ALBEDO = film_finish(c, SCREEN_UV, FRAGCOORD.xy, TIME);
}
