// Feldgendarmerie gorget (Ringkragen): under distortion its upper edge grows
// trap teeth. Use a BoxMesh with width subdivisions (>= 16).
shader_type spatial;

#include "res://src/rendering/shaders/enemy_distort.gdshaderinc"

uniform float teeth_count = 9.0;
uniform float teeth_height = 0.09;

void vertex() {
	float d = distortion_strength();
	if (VERTEX.y > 0.0) {
		float saw = 1.0 - abs(fract(VERTEX.x * teeth_count * 2.0) - 0.5) * 2.0;
		VERTEX.y += saw * teeth_height * d;
	}
	VERTEX = dix_distort(VERTEX, MODEL_MATRIX, d, TIME);
}

void fragment() {
	ALBEDO = vec3(0.55);
	METALLIC = 0.9;
	ROUGHNESS = 0.35;
}
