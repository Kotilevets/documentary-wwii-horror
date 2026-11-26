class_name SearchlightTower
extends Node3D
## Watchtower of a transit camp (Dulag) with a searchlight sweeping the
## ground. A boy caught in the beam for `exposure_needed` seconds raises the
## alarm: a shout, the beam locks on him, every enemy within alarm_radius
## runs to the spot. Crouching does not help in the light - only cover
## (anything on layer 1 hiding his head, both shoulders and knee from the
## lamp: the enemy's points, Enemy.sight_points) or timing.

signal alarm_raised(position: Vector3)

@export var height: float = 6.0
## Sweep around the tower's -Z: +- amplitude degrees, one period in seconds.
@export var sweep_amplitude: float = 55.0
@export var sweep_period: float = 14.0
@export var tilt_down: float = 14.0
@export var beam_range: float = 40.0
@export var beam_angle: float = 9.0
@export var exposure_needed: float = 0.7
@export var alarm_radius: float = 40.0
@export var lock_time: float = 5.0

var exposure := 0.0
var lamp: SpotLight3D
var _pivot: Node3D
var _t := 0.0
var _lock := 0.0


func _ready() -> void:
	add_to_group("searchlights")
	_build_tower()
	_pivot = Node3D.new()
	_pivot.position = Vector3(0, height + 1.2, 0)
	add_child(_pivot)
	lamp = SpotLight3D.new()
	lamp.light_color = Color(1, 1, 1)
	lamp.light_energy = 14.0
	lamp.spot_range = beam_range
	lamp.spot_angle = beam_angle
	lamp.spot_attenuation = 0.4
	lamp.shadow_enabled = true
	lamp.rotation_degrees.x = -tilt_down
	_pivot.add_child(lamp)
	var housing := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.22
	cm.bottom_radius = 0.26
	cm.height = 0.5
	housing.mesh = cm
	housing.rotation_degrees.x = 90.0
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.25, 0.25, 0.25)
	housing.material_override = hm
	lamp.add_child(housing)


func _build_tower() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.33, 0.3, 0.26)
	mat.roughness = 0.95
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var post := CSGBox3D.new()
		post.size = Vector3(0.2, height, 0.2)
		post.position = Vector3(corner.x * 1.1, height * 0.5, corner.y * 1.1)
		post.use_collision = true
		post.material = mat
		add_child(post)
	var deck := CSGBox3D.new()
	deck.size = Vector3(2.8, 0.15, 2.8)
	deck.position = Vector3(0, height, 0)
	deck.use_collision = true
	deck.material = mat
	add_child(deck)
	var rail := CSGBox3D.new()
	rail.size = Vector3(2.8, 1.0, 2.8)
	rail.position = Vector3(0, height + 0.55, 0)
	rail.material = mat
	var hollow := CSGBox3D.new()
	hollow.operation = CSGShape3D.OPERATION_SUBTRACTION
	hollow.size = Vector3(2.6, 1.2, 2.6)
	rail.add_child(hollow)
	add_child(rail)


func _physics_process(delta: float) -> void:
	_t += delta
	var p := Stealth.player as Player
	if _lock > 0.0 and p != null:
		_lock -= delta
		_aim_at(p.head.global_position, delta)
	else:
		_pivot.rotation.y = sweep_yaw(_t)
	if p == null:
		return
	if in_beam(p):
		exposure += delta
		PanicSystem.apply_continuous(0.5, delta)
		if exposure >= exposure_needed and _lock <= 0.0:
			raise_alarm(p.global_position)
	else:
		exposure = maxf(exposure - delta * 0.5, 0.0)


## The sweep's heading at the tower's time `at` (s): the same every period,
## so TraumaEcho can look ahead (docs/ARCHITECTURE.md, «Вторжение памяти»).
func sweep_yaw(at: float) -> float:
	return deg_to_rad(sweep_amplitude) * sin(TAU * at / sweep_period)


## The cone (`widen` times the drawn one) is over `point`, in range; walls
## are not looked at.
func covers(point: Vector3, widen: float = 1.0) -> bool:
	var from := lamp.global_position
	var to := point - from
	if to.length() > beam_range:
		return false
	var axis := -lamp.global_transform.basis.z
	return rad_to_deg(axis.angle_to(to.normalized())) <= lamp.spot_angle * widen


## Will the sweeping cone be over `point` `ahead` seconds from now? A beam
## held on someone after an alarm - yes, it is not sweeping.
func will_cover(point: Vector3, ahead: float, widen: float = 1.0) -> bool:
	if _lock > 0.0:
		return true
	var keep := _pivot.rotation.y
	_pivot.rotation.y = sweep_yaw(_t + ahead)
	var over := covers(point, widen)
	_pivot.rotation.y = keep
	return over


func _aim_at(target: Vector3, delta: float) -> void:
	var local := _pivot.global_transform.affine_inverse() * target
	var yaw := atan2(-local.x, -local.z)
	_pivot.rotation.y = lerp_angle(_pivot.rotation.y, _pivot.rotation.y + yaw, minf(6.0 * delta, 1.0))


## True when the boy is lit: one of his points - the head, both shoulders
## (the enemy's, Player.sight_points_from) or the knee - inside the cone, in
## range, nothing in between. A wire post hides his head, not the boy
## (docs/ARCHITECTURE.md, "Пересыльный лагерь").
func in_beam(p: Player) -> bool:
	if p.is_hidden:
		return false
	var from := lamp.global_position
	var axis := -lamp.global_transform.basis.z
	var points := p.sight_points_from(from)
	points.append(p.global_position + Vector3.UP * 0.3)
	for point in points:
		var to: Vector3 = point - from
		if to.length() > beam_range:
			continue
		# The drawn cone (spot_angle is the half-angle): the alarm, the light
		# Stealth counts on him and what the player sees are one beam.
		if rad_to_deg(axis.angle_to(to.normalized())) > lamp.spot_angle:
			continue
		var q := PhysicsRayQueryParameters3D.create(from, point, 1 | IzbaDoor.DOOR_LAYER)
		if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			return true
	return false


func raise_alarm(pos: Vector3) -> void:
	_lock = lock_time
	PanicSystem.spike(0.35)
	Sfx.play_at("de_shout", global_position + Vector3.UP * (height + 1.6))  # the guard on the deck
	# He is in the beam: he knows he has been seen, however far the lamp
	# (docs/ARCHITECTURE.md, "Заметили").
	var boy := Stealth.player as Player
	if boy != null:
		boy.startle(lamp.global_position, true)
	for e in get_tree().get_nodes_in_group("enemies"):
		if (e as Node3D).global_position.distance_to(pos) < alarm_radius:
			(e as Enemy).alert_to(pos, 1.0)
	alarm_raised.emit(pos)
