class_name SmoulderSmoke
extends CPUParticles3D
## Grey smoke still rising from a burned house (B&W category: no embers,
## no orange - the colour rule allows no fire colour). Alpha-hash material,
## because blended transparency is wiped out by the post-processing quads
## (docs/ARCHITECTURE.md, "Рендер").

@export var height: float = 9.0
@export var wind: Vector3 = Vector3(0.35, 0.0, 0.15)


func _ready() -> void:
	amount = 110
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lifetime = height / 0.7
	preprocess = lifetime
	emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	emission_box_extents = Vector3(1.0, 0.2, 0.9)
	direction = Vector3.UP
	spread = 12.0
	gravity = wind
	initial_velocity_min = 0.5
	initial_velocity_max = 0.9
	scale_amount_min = 1.6
	scale_amount_max = 2.8
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.4))
	grow.add_point(Vector2(1.0, 2.6))
	scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(0.55, 0.55, 0.55, 0.0))
	fade.set_color(1, Color(0.35, 0.35, 0.35, 0.0))
	fade.add_point(0.12, Color(0.5, 0.5, 0.5, 0.45))
	fade.add_point(0.6, Color(0.42, 0.42, 0.42, 0.25))
	color_ramp = fade

	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var puff := GradientTexture2D.new()
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	puff.gradient = g
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = puff
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = m
	mesh = quad
	emitting = true
