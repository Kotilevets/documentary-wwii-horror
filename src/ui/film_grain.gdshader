// Menu background: black, archive film grain, a soft vignette, a rare
// flicker. Black and white only (CLAUDE.md, 2).
shader_type canvas_item;

uniform float grain : hint_range(0.0, 0.3) = 0.07;
uniform float base : hint_range(0.0, 0.3) = 0.05;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float t = floor(TIME * 24.0);
	float n = hash(FRAGCOORD.xy * 0.5 + t * 17.0) - 0.5;
	vec2 c = UV - 0.5;
	float vig = smoothstep(0.85, 0.2, length(c * vec2(1.4, 1.0)));
	float flicker = 1.0 + 0.04 * sin(TIME * 9.0) * step(0.97, hash(vec2(t, 3.0)));
	float v = (base * vig + n * grain) * flicker;
	COLOR = vec4(vec3(max(v, 0.0)), 1.0);
}
