class_name WallClock
extends Node3D
## A wall clock (ходики): wooden case, a pale face with hands, a pendulum.
## It ticks once a second (Sfx "wall_clock", a loop) and the pendulum swings
## in time. The same tick is heard in the house before the war, in the
## memory at the burned house and in the interrogation room.
## The boy's perception bends it:
##   - panic makes the ticking louder (in the silence he hears nothing else);
##   - with stretch_with_illusion (the interrogation) the nightmare slows
##     time down: at IllusionFactor 1 the clock beats at slow_rate, when the
##     shell falls it is an ordinary clock again;
##   - `stretch` (0..1) is set by a scene directly (the dream after Act I
##     slows the clock with every return to the room).
## Built facing +Z; hang it on a wall and turn it to the room.

@export var stretch_with_illusion := false
## Rate of the clock at full illusion (1 = normal).
@export var slow_rate: float = 0.72
## Slowing set by the scene, 0..1 (1 = slow_rate).
@export_range(0.0, 1.0) var stretch: float = 0.0
## Extra loudness at panic 1, dB.
@export var panic_boost_db: float = 6.0

var rate := 1.0
var player: AudioStreamPlayer3D
var pendulum: Node3D
var _phase := 0.0
var _base_db := 0.0


func _ready() -> void:
	_build()
	player = Sfx.play_at("wall_clock", global_position, 1.0, self)
	if player != null:
		player.pitch_scale = 1.0
		_base_db = player.volume_db


func _process(delta: float) -> void:
	rate = target_rate()
	_phase = fmod(_phase + delta * PI * rate, TAU)
	pendulum.rotation.z = 0.18 * sin(_phase)
	if player != null:
		player.pitch_scale = rate
		player.volume_db = _base_db + panic_boost_db * PanicSystem.level


func target_rate() -> float:
	var k := stretch
	if stretch_with_illusion:
		k = maxf(k, Perception.illusion_factor)
	return lerpf(1.0, slow_rate, clampf(k, 0.0, 1.0))


func _build() -> void:
	var wood := Surfaces.material("wood")
	if wood == null:
		wood = _flat(Color(0.36, 0.3, 0.24))
	var face_mat := _flat(Color(0.78, 0.77, 0.74))
	var dark := _flat(Color(0.08, 0.08, 0.08))
	_mesh(_box(Vector3(0.3, 0.36, 0.08)), Vector3.ZERO, wood)
	# Little gable on top of the case.
	var top := PrismMesh.new()
	top.size = Vector3(0.34, 0.08, 0.08)
	_mesh(top, Vector3(0, 0.22, 0), wood)
	var face := CylinderMesh.new()
	face.top_radius = 0.11
	face.bottom_radius = 0.11
	face.height = 0.01
	_mesh(face, Vector3(0, 0.02, 0.045), face_mat).rotation.x = PI * 0.5
	_mesh(_box(Vector3(0.012, 0.07, 0.004)), Vector3(0.012, 0.045, 0.053), dark).rotation.z = -0.35
	_mesh(_box(Vector3(0.008, 0.095, 0.004)), Vector3(-0.03, 0.0, 0.055), dark).rotation.z = 1.1
	pendulum = Node3D.new()
	pendulum.name = "Pendulum"
	pendulum.position = Vector3(0, -0.18, 0.03)
	add_child(pendulum)
	_mesh(_box(Vector3(0.012, 0.32, 0.01)), Vector3(0, -0.16, 0), dark, pendulum)
	var bob := CylinderMesh.new()
	bob.top_radius = 0.045
	bob.bottom_radius = 0.045
	bob.height = 0.012
	_mesh(bob, Vector3(0, -0.33, 0), wood, pendulum).rotation.x = PI * 0.5
	# Weights on chains, as on village clocks.
	for x in [-0.07, 0.07]:
		_mesh(_box(Vector3(0.004, 0.45, 0.004)), Vector3(x, -0.4, 0.0), dark)
		_mesh(_box(Vector3(0.035, 0.11, 0.035)), Vector3(x, -0.68, 0.0), dark)


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _mesh(m: Mesh, pos: Vector3, mat: Material, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m
