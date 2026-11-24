// Pass for the unmarked world (stencil 0): hard B&W or warm sepia.
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled;
stencil_mode read, compare_equal, 0;

#include "res://src/rendering/shaders/film_common.gdshaderinc"

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

void fragment() {
	vec3 c = mono_grade(graded_luma(screen_color(SCREEN_UV)));
	ALBEDO = film_finish(c, SCREEN_UV, FRAGCOORD.xy, TIME);
}
