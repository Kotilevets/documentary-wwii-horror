// The brightness test (Настройки -> Яркость, BrightnessPanel): two windows
// of an izba at night on black, their panes at the darkest tones the game
// draws. They go through the same brightness lift and grain as the 3D
// picture (film_common.gdshaderinc) and, like it, perceptual -> linear ->
// the screen's sRGB, so what the player sees here is what the night looks
// like. The left window should be barely visible, the right one gone.
shader_type canvas_item;

global uniform float g_brightness;
// Width / height of the rect (set by BrightnessPanel).
uniform float aspect = 2.9;
// Pane tones in the graded (perceptual) space, before the lift.
uniform float near_level = 0.06;
uniform float far_level = 0.025;
uniform float grain = 0.019;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Four panes of a window, frame and cross left black. p: -1..1 in the window.
float panes(vec2 p) {
	vec2 a = abs(p);
	if (max(a.x, a.y) > 0.86) {
		return 0.0;
	}
	return step(0.08, a.x) * step(0.08, a.y);
}

float to_screen(float c) {
	float lin = pow(max(c, 0.0), 2.2);
	return lin <= 0.0031308 ? lin * 12.92 : 1.055 * pow(lin, 1.0 / 2.4) - 0.055;
}

void fragment() {
	vec2 q = vec2(UV.x * aspect, UV.y);
	float half_size = 0.34;
	vec2 left = vec2(aspect * 0.3, 0.5);
	vec2 right = vec2(aspect * 0.7, 0.5);
	float c = near_level * panes((q - left) / half_size) + far_level * panes((q - right) / half_size);
	c = pow(clamp(c, 0.0, 1.0), 1.0 / max(g_brightness, 0.1));
	c += (hash12(FRAGCOORD.xy + floor(TIME * 24.0) * 37.0) - 0.5) * grain;
	COLOR = vec4(vec3(to_screen(clamp(c, 0.0, 1.0))), 1.0);
}
