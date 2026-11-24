// Local auxiliary police (Hilfspolizei): a cracked plaster mask instead of a
// face. The mask exists only in distorted perception: it shrinks to nothing
// as distortion falls, revealing the ordinary face mesh underneath.
shader_type spatial;

#include "res://src/rendering/shaders/enemy_distort.gdshaderinc"

float crack_lines(vec2 uv, float d) {
	float c = 0.0;
	for (int i = 0; i < 4; i++) {
		float fi = float(i);
		float line = uv.x * (2.0 + fi * 1.7) + sin(uv.y * (7.0 + fi * 3.1) + fi) * 0.35 - uv.y * (1.3 - fi * 0.6);
		float w = mix(0.004, 0.03, d);
		c = max(c, 1.0 - smoothstep(0.0, w, abs(fract(line) - 0.5)));
	}
	return c;
}

void vertex() {
	float d = distortion_strength();
	VERTEX *= smoothstep(0.12, 0.45, d);
	VERTEX = dix_distort(VERTEX, MODEL_MATRIX, d, TIME);
}

void fragment() {
	float c = crack_lines(UV, distortion_strength());
	ALBEDO = mix(vec3(0.82, 0.81, 0.78), vec3(0.05), c);
	ROUGHNESS = 0.95;
}
