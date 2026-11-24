class_name InvestigatorShell
extends Node3D
## The investigator's "monstrous shell" (CLAUDE.md, 3, Act III): a plaster
## carapace over the face with hollow eye slits, a metal crest grown into
## the skull, plates on the shoulders - and under it an ordinary tired face
## (glasses, bags under the eyes, a cap). As the boy's illusion weakens the
## plates crack apart (crack 0..1); shatter() drops them to the floor.
## Black-and-white only: the red is the armband on the uniform.
## Add as a child of the enemy's Visual node; follows its distortion.

signal shattered

const BODY_SHADER := preload("res://src/rendering/shaders/enemy_body.gdshader")
const HEAD := Vector3(0, 1.62, 0)

## 0 = whole, 1 = about to fall apart.
var crack: float = 0.0:
	set(v):
		var before := crack
		crack = clampf(v, 0.0, 1.0)
		_on_crack(before)
var is_shattered := false

var enemy: Enemy
var _plates: Array[MeshInstance3D] = []
var _rest: Array[Transform3D] = []
var _dirs: Array[Vector3] = []
var _spin: Array[Vector3] = []
var _slits: Array[MeshInstance3D] = []
var _face: Array[GeometryInstance3D] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 1942
	enemy = _find_enemy()
	_build_face()
	_build_mask()
	_build_crest()
	_build_shoulders()


func _process(_delta: float) -> void:
	if enemy == null:
		return
	for gi in _all_geometry():
		gi.set_instance_shader_parameter("feet_origin", enemy.global_position)
		gi.set_instance_shader_parameter("grotesque", enemy.grotesque)


func plates() -> Array[MeshInstance3D]:
	return _plates


## The carapace falls off: plates drop to the floor around the feet.
func shatter(duration: float = 1.2) -> void:
	if is_shattered:
		return
	is_shattered = true
	for s in _slits:
		s.visible = false
	Sfx.play_at("shell_fall", global_position + HEAD)
	for i in _plates.size():
		var pl := _plates[i]
		var delay := _rng.randf_range(0.0, duration * 0.5)
		var t := _rng.randf_range(0.45, 0.75)
		var land := Vector3(_rng.randf_range(-0.45, 0.45), 0.012, _rng.randf_range(-0.55, -0.1))
		var rot := Vector3(PI * 0.5 * (1 if _rng.randf() < 0.5 else -1), _rng.randf_range(-PI, PI), 0)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(pl, "position", land, t).set_delay(delay) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(pl, "rotation", rot, t).set_delay(delay)
	get_tree().create_timer(duration + 0.3, false).timeout.connect(shattered.emit)


# --- building ------------------------------------------------------------------

func _find_enemy() -> Enemy:
	var n := get_parent()
	while n != null and not (n is Enemy):
		n = n.get_parent()
	return n as Enemy


func _material(grey: float, roughness: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = BODY_SHADER
	m.set_shader_parameter("albedo", Color(grey, grey, grey * 0.97))
	m.set_shader_parameter("roughness_value", roughness)
	return m


func _piece(mesh: Mesh, pos: Vector3, rot: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _plate(size: Vector3, pos: Vector3, rot: Vector3, mat: Material) -> void:
	var mi := _piece(_box(size), pos, rot, mat)
	_plates.append(mi)
	_rest.append(mi.transform)
	var out := pos - HEAD
	out.y *= 0.5
	_dirs.append(out.normalized() if out.length() > 0.01 else Vector3.FORWARD)
	_spin.append(Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)))


## The ordinary face, there all along under the shell.
func _build_face() -> void:
	var dark := _material(0.08, 0.6)
	var skin_shadow := _material(0.3, 0.8)
	var metal := _material(0.55, 0.3)
	for side in [-1.0, 1.0]:
		var s := side as float
		# Eyes, tired: lids half down, bags under them.
		_face.append(_piece(_box(Vector3(0.026, 0.009, 0.01)), Vector3(0.042 * s, 1.648, -0.112), Vector3.ZERO, dark))
		_face.append(_piece(_box(Vector3(0.032, 0.012, 0.008)), Vector3(0.042 * s, 1.633, -0.111), Vector3.ZERO, skin_shadow))
		# Brows sag at the outer ends.
		_face.append(_piece(_box(Vector3(0.038, 0.007, 0.01)), Vector3(0.044 * s, 1.672, -0.111),
				Vector3(0, 0, -0.25 * s), dark))
		# Round glasses.
		var ring := TorusMesh.new()
		ring.inner_radius = 0.019
		ring.outer_radius = 0.023
		ring.rings = 16
		ring.ring_segments = 6
		_face.append(_piece(ring, Vector3(0.042 * s, 1.648, -0.122), Vector3(PI * 0.5, 0, 0), metal))
	_face.append(_piece(_box(Vector3(0.02, 0.004, 0.004)), Vector3(0, 1.65, -0.124), Vector3.ZERO, metal))
	_face.append(_piece(_box(Vector3(0.022, 0.045, 0.026)), Vector3(0, 1.618, -0.118), Vector3(-0.2, 0, 0), skin_shadow))
	_face.append(_piece(_box(Vector3(0.05, 0.006, 0.006)), Vector3(0, 1.578, -0.11), Vector3.ZERO, dark))


## Plaster carapace over the face: a grid of angular plates, hollow slits.
func _build_mask() -> void:
	var plaster := _material(0.66, 0.9)
	var w := 0.085
	for row in 4:
		for col in 3:
			var x := (col - 1) * w
			var y := 1.53 + row * 0.07
			var z := -0.138 - 0.012 * (1 - absf(col - 1))
			var rot := Vector3(_rng.randf_range(-0.12, 0.12), (col - 1) * 0.35, _rng.randf_range(-0.15, 0.15))
			_plate(Vector3(w * 1.08, 0.078, 0.022), Vector3(x, y, z), rot, plaster)
	var black := _material(0.0, 1.0)
	for side in [-1.0, 1.0]:
		_slits.append(_piece(_box(Vector3(0.05, 0.016, 0.03)), Vector3(0.045 * (side as float), 1.648, -0.15),
				Vector3(0, 0, 0.3 * (side as float)), black))


## A crest of metal grown into the skull (the helmet and skull fused).
func _build_crest() -> void:
	var metal := _material(0.2, 0.45)
	for i in 7:
		var a := lerpf(-PI * 0.75, PI * 0.75, i / 6.0)
		var pos := HEAD + Vector3(sin(a) * 0.12, 0.2, -cos(a) * 0.12 + 0.02)
		_plate(Vector3(0.07, 0.2, 0.025), pos, Vector3(-cos(a) * 0.35, -a, sin(a) * 0.35), metal)
	_plate(Vector3(0.05, 0.28, 0.05), HEAD + Vector3(0, 0.3, 0.02), Vector3(0.1, 0, 0), metal)


func _build_shoulders() -> void:
	var metal := _material(0.24, 0.5)
	for side in [-1.0, 1.0]:
		var s := side as float
		_plate(Vector3(0.2, 0.035, 0.3), Vector3(0.22 * s, 1.47, 0), Vector3(0, 0, -0.45 * s), metal)
		_plate(Vector3(0.16, 0.03, 0.26), Vector3(0.3 * s, 1.4, 0), Vector3(0, 0, -0.9 * s), metal)


func _all_geometry() -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	for c in get_children():
		if c is GeometryInstance3D:
			out.append(c as GeometryInstance3D)
	return out


func _on_crack(before: float) -> void:
	if is_shattered or _plates.is_empty():
		return
	for i in _plates.size():
		var t := _rest[i]
		t.origin += _dirs[i] * crack * 0.03
		t.basis = t.basis * Basis.from_euler(_spin[i] * crack * 0.18)
		_plates[i].transform = t
	# A dry crack at every third of the way.
	if floori(crack * 3.0) > floori(before * 3.0):
		Sfx.play_at("plaster_crack", global_position + HEAD)
