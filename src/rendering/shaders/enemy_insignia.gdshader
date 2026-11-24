// Red elements on enemies (armband, cap band, collar tabs): stencil 1,
// distorted together with the body.
shader_type spatial;
stencil_mode write, compare_always, 1;

#include "res://src/rendering/shaders/enemy_distort.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.62, 0.05, 0.04);

void vertex() {
	VERTEX = dix_distort(VERTEX, MODEL_MATRIX, distortion_strength(), TIME);
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = 0.8;
}
