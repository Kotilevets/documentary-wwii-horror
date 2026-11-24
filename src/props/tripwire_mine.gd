class_name TripwireMine
extends Node3D
## A tripwire across the ground between two stakes, a mine at one end.
## At night a standing boy does not see the wire at all; crouched and
## close (reveal_distance), the wire catches the light. Touching it kills -
## a hard cut to black and ringing in the ears, no gore (CLAUDE.md, 6.4).
## Which mine types were laid where - [НЕ ПОДТВЕРЖДЕНО], the model is generic.
## The wire runs along local +X from the origin.

signal detonated(mine: TripwireMine)

@export var length: float = 3.0
@export var wire_height: float = 0.14
@export var reveal_distance: float = 3.2

var is_detonated := false
var wire: MeshInstance3D
var _trigger: Area3D


func _ready() -> void:
	add_to_group("mines")
	for x in [0.0, length]:
		var stake := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.04, 0.3, 0.04)
		stake.mesh = sm
		stake.position = Vector3(x, 0.15, 0.0)
		stake.material_override = _mat(Color(0.3, 0.29, 0.27), false)
		add_child(stake)
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.06
	cm.height = 0.14
	body.mesh = cm
	body.position = Vector3(0.0, 0.07, 0.12)
	body.material_override = _mat(Color(0.22, 0.22, 0.21), false)
	add_child(body)

	wire = MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(length, 0.008, 0.008)
	wire.mesh = wm
	wire.position = Vector3(length * 0.5, wire_height, 0.0)
	wire.material_override = _mat(Color(0.78, 0.78, 0.76), true)
	wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wire.visible = false
	add_child(wire)

	_trigger = Area3D.new()
	_trigger.collision_layer = 0
	_trigger.collision_mask = 1 << 1  # player
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(length, 0.3, 0.25)
	shape.shape = box
	shape.position = Vector3(length * 0.5, 0.15, 0.0)
	_trigger.add_child(shape)
	add_child(_trigger)
	_trigger.body_entered.connect(_on_body_entered)


func _physics_process(_delta: float) -> void:
	var p := Stealth.player as Player
	wire.visible = p != null and not is_detonated and p.is_crouching \
			and _distance_to_wire(p.global_position) < reveal_distance


func _distance_to_wire(point: Vector3) -> float:
	var a := global_position
	var b := global_transform * Vector3(length, 0, 0)
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(point.x - a.x, point.z - a.z)
	var t := clampf(ap.dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return (ap - ab * t).length()


func _on_body_entered(body: Node3D) -> void:
	if body == Stealth.player:
		detonate()


func detonate() -> void:
	if is_detonated:
		return
	is_detonated = true
	Sfx.play_at("mine_blast", global_position)
	PanicSystem.spike(1.0)
	detonated.emit(self)


static func _mat(c: Color, bright: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	if bright:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
