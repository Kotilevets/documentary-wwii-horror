// View from a hiding spot through narrow gaps between boards.
// Drawn on a CanvasLayer above the 3D image: black boards and colourless
// light in the gaps when a torch beam passes over (leak). No colours.
// Dust: boots on the boards over a cellar shake grey specks loose; they
// fall past the gaps, seen best where light comes through (Player.dust).
// Band: the torch spot passing along the gaps (TraumaEcho, the cellar of
// Act I remembered on the road); -1 - off, the whole gap takes the leak.
shader_type canvas_item;

uniform bool vertical = false;
uniform float slit_width = 0.12;
uniform float slit_count = 3.0;
uniform float leak = 0.0;
uniform float dust = 0.0;
uniform float dust_time = 0.0;
uniform float band = -1.0;
uniform float band_width = 0.18;

float hash(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

// Falling grit: at most one grain per cell, drawn as a short vertical
// streak (it falls), of uneven brightness; 16:9 cells.
float specks(vec2 uv, float t) {
	vec2 grid = vec2(64.0, 36.0);
	vec2 p = uv;
	p.y -= t * 0.09;
	vec2 cell = floor(p * grid);
	float h = hash(cell.x * 13.1 + cell.y * 71.7);
	vec2 c = vec2(hash(cell.x * 5.3 + cell.y * 1.9), hash(cell.y * 3.7 + cell.x * 9.2));
	vec2 q = fract(p * grid) - c;
	q.y *= 0.4;
	float bright = 0.45 + 0.55 * hash(cell.x * 2.9 + cell.y * 17.3);
	return step(h, 0.3) * bright * (1.0 - smoothstep(0.05, 0.11, length(q)));
}

void fragment() {
	float along = vertical ? UV.y : UV.x;
	float across = vertical ? UV.x : UV.y;
	float cell = across * slit_count;
	float id = floor(cell);
	float f = fract(cell);
	// Uneven board edges.
	float wobble = (hash(id + floor(along * 18.0)) - 0.5) * 0.03;
	float half_w = slit_width * 0.5 * (0.7 + 0.6 * hash(id * 3.7));
	float d = abs(f - 0.5 + wobble);
	float open = 1.0 - smoothstep(half_w - 0.015, half_w + 0.015, d);
	// Torch light through the gaps: brightest at the middle of a gap,
	// with dust flicker along it.
	float core = 1.0 - smoothstep(0.0, half_w + 0.015, d);
	float flicker = 0.85 + 0.15 * hash(floor(along * 40.0) + floor(TIME * 12.0));
	float spot = band < -0.5 ? 1.0 : mix(0.2, 1.0, exp(-pow((along - band) / band_width, 2.0)));
	float light = open * leak * spot * (0.55 + 0.45 * core) * flicker;
	vec3 pm = vec3(0.92) * light;
	float a = 1.0 - open + light;
	// Dust: seen where the light falls through - in and just by the gaps,
	// hardly in the dark under the boards; a fine haze sifts along the gap.
	float near = 1.0 - smoothstep(half_w, half_w * 3.0 + 0.1, d);
	float haze = (1.0 - smoothstep(half_w * 0.5, half_w + 0.08, d))
			* (0.4 + 0.6 * hash(floor(along * 90.0) + floor(dust_time * 14.0)));
	float s = dust * (specks(UV, dust_time) * (0.06 + 0.94 * near) + 0.22 * haze);
	s = clamp(s, 0.0, 1.0);
	pm = pm * (1.0 - s) + vec3(0.62) * s;
	a = a * (1.0 - s) + s;
	COLOR = vec4(pm / max(a, 0.001), clamp(a, 0.0, 1.0));
}
