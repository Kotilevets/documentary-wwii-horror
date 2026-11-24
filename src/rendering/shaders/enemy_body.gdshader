// Enemy body, helmet, greatcoat: dark matte cloth with distortion.
shader_type spatial;

#include "res://src/rendering/shaders/enemy_distort.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.16, 0.16, 0.15);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.85;

void vertex() {
	VERTEX = dix_distort(VERTEX, MODEL_MATRIX, distortion_strength(), TIME);
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = roughness_value;
}
