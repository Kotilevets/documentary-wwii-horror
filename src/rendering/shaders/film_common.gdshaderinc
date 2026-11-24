// Shared look for all three post-process passes
// (docs/GAMEPLAY_AND_SHADERS.md, section 1).
// The screen copy is linear HDR; grading happens in perceptual (gamma 2.2)
// space and the result is converted back to linear for output.
// The level's Environment must use the Linear tonemapper so this pass
// stays the final grade.

global uniform float g_panic;
global uniform float g_sepia;
global uniform float g_heartbeat;
global uniform float g_air;
// The player's brightness (Настройки -> Яркость, GameState.brightness()):
// a gamma lift of the dark tones, 1.0 = as graded.
global uniform float g_brightness;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

// Levels: input black / white points in perceptual space (night exposure).
uniform float level_black : hint_range(0.0, 0.5) = 0.04;
uniform float level_white : hint_range(0.2, 1.0) = 0.62;
uniform float contrast : hint_range(0.0, 1.0) = 0.7;
uniform float grain_calm : hint_range(0.0, 0.3) = 0.045;
uniform float grain_panic : hint_range(0.0, 0.3) = 0.11;

const vec3 LUMA = vec3(0.299, 0.587, 0.114);
const vec3 SEPIA_TONE = vec3(1.07, 0.86, 0.62);

vec3 to_perceptual(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2));
}

vec3 to_linear(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(2.2));
}

// Screen pixel in perceptual space.
vec3 screen_color(vec2 uv) {
	return to_perceptual(textureLod(screen_tex, uv, 0.0).rgb);
}

float luma(vec3 c) {
	return dot(c, LUMA);
}

float levels(float x) {
	return clamp((x - level_black) / max(level_white - level_black, 0.001), 0.0, 1.0);
}

// S-shaped contrast around mid-grey; strength 0 = identity.
float s_curve(float x, float strength) {
	x = clamp(x, 0.0, 1.0);
	float s = x * x * (3.0 - 2.0 * x);
	return mix(x, s, strength);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Procedural grain that changes 24 times per second, like projected film.
float film_grain(vec2 frag, float time) {
	float frame = floor(time * 24.0);
	return hash12(frag + frame * 37.0) - 0.5;
}

// Darkening of the frame: base vignette + panic "tunnel" + heartbeat pulse
// + lack of air while holding the breath. Returns a multiplier 0..1.
float frame_darkening(vec2 uv) {
	vec2 d = uv - 0.5;
	d.x *= 1.35;
	float r = length(d);
	float tunnel_radius = mix(0.62, 0.3, g_panic) - g_heartbeat * 0.05 * (0.4 + g_panic);
	float v = smoothstep(tunnel_radius + 0.38, tunnel_radius, r);
	float air_dark = smoothstep(1.0, 0.0, g_air) * smoothstep(0.15, 0.6, r);
	return clamp(v * (1.0 - 0.8 * air_dark), 0.0, 1.0);
}

// The player's brightness: shadows lift, black and white stay where they are.
vec3 brightness_lift(vec3 c) {
	return pow(clamp(c, 0.0, 1.0), vec3(1.0 / max(g_brightness, 0.1)));
}

// Graded perceptual color -> final linear output: brightness, grain, darkening.
vec3 film_finish(vec3 c, vec2 uv, vec2 frag, float time) {
	c = brightness_lift(c);
	float amount = mix(grain_calm, grain_panic, g_panic) * (0.4 + 0.6 * luma(c));
	c += film_grain(frag, time) * amount;
	c *= frame_darkening(uv);
	return to_linear(clamp(c, 0.0, 1.0));
}

// Contrast-graded luminance (levels + S-curve).
float graded_luma(vec3 c) {
	return s_curve(levels(luma(c)), contrast);
}

// Black & white or warm sepia (g_sepia = 0..1) from a graded luminance.
vec3 mono_grade(float l) {
	float sep = mix(l, s_curve(l, 0.3), 0.5) * 0.95 + 0.04;
	return mix(vec3(l), sep * SEPIA_TONE, g_sepia);
}
