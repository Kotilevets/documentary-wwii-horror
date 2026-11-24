// "Distorted perception" of enemies (docs/GAMEPLAY_AND_SHADERS.md, 2).
// Grotesque in the spirit of Otto Dix "Der Krieg" (1924): unnaturally tall,
// angular silhouettes, helmet fused with the skull, thin torso, twitching.
// Strength = g_distortion (panic * IllusionFactor) * per-instance grotesque.

global uniform float g_distortion;
// Feet of the enemy in world space; set by enemy.gd every frame.
instance uniform vec3 feet_origin;
// 1.0 = full grotesque, 0.0 = ordinary person (Enemy.reveal()).
instance uniform float grotesque = 1.0;

float distortion_strength() {
	return clamp(g_distortion * grotesque, 0.0, 1.0);
}

vec3 dix_distort_world(vec3 w, float d, float t) {
	vec3 rel = w - feet_origin;
	float h = max(rel.y, 0.0);
	float head = smoothstep(1.35, 1.6, h);
	float torso = smoothstep(0.7, 1.2, h) * (1.0 - head);
	// Unnaturally tall.
	rel.y = h * (1.0 + 0.55 * d);
	// Helmet grows into the skull: the head stretches further and narrows.
	rel.y += head * (h - 1.35) * 1.1 * d;
	rel.xz *= 1.0 - 0.22 * d * head;
	// Thin, sunken torso.
	rel.xz *= 1.0 - 0.3 * d * torso;
	// Angular facets: snap the horizontal outline to a coarse grid.
	vec2 q = round(rel.xz * 6.0) / 6.0;
	rel.xz = mix(rel.xz, q, 0.65 * d);
	// Nervous twitching.
	rel.x += sin(t * 9.0 + h * 7.0) * 0.03 * d;
	rel.z += sin(t * 6.3 + h * 5.0) * 0.02 * d;
	return feet_origin + rel;
}

// Object-space vertex -> distorted object-space vertex.
vec3 dix_distort(vec3 v, mat4 model, float d, float t) {
	vec3 w = (model * vec4(v, 1.0)).xyz;
	w = dix_distort_world(w, d, t);
	return (inverse(model) * vec4(w, 1.0)).xyz;
}
