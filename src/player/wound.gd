class_name Wound
extends Node
## A wound (docs/ARCHITECTURE.md, "Рана и бинт"). Barbed wire tears his
## forearm (WireGap): he bleeds, and the blood is a trail - small dark drops
## on the ground behind him (red: CLAUDE.md, 2 - blood) and a smell a dog
## picks up from much farther than his steps (Stealth.lay_blood,
## Dog.blood_pickup_radius). No bar, no text: he winces now and then, and
## the bandage in the satchel is no longer shaken off.
##   A bandage from the satchel (Player.use_item) binds it: BIND_TIME s of
## standing, a quiet rustle of cloth. Unbound, it stops by itself after
## CLOT_TIME s. It neither kills nor weakens him: the danger is the trail.
## In a hiding place he presses it: no drops there.

signal cut_open
signal bound
signal dropped(at: Vector3)

## Metres walked between two drops.
const DROP_SPACING := 1.4
## Standing still (slower than STILL_SPEED): a drop every so many seconds.
const STILL_DROP := 6.0
const STILL_SPEED := 0.2
## Unbound, the blood stops by itself after this long.
const CLOT_TIME := 300.0
## Binding it takes this long; he cannot walk meanwhile.
const BIND_TIME := 3.0
## Tearing cloth and binding it: quiet, not silent (Stealth noise).
const BIND_NOISE := 0.08
## The fright of the cut (PanicSystem spike).
const CUT_PANIC := 0.15
## Drops kept on the ground in a level; the oldest go.
const MAX_DROPS := 120
## Seconds between winces while it bleeds.
const WINCE_MIN := 25.0
const WINCE_MAX := 45.0
## A drop: a dark spot a few centimetres across.
const DROP_RADIUS := 0.035
## Physics layer of flat things laid on the ground - a road, ash - that
## nothing stands on or bumps into but a drop must land on (it would be
## hidden under them otherwise). Only the drop ray looks at it.
const SURFACE_LAYER := 1 << 6

## One mesh and one marked material for every drop.
static var _drop_mesh: CylinderMesh
static var _drop_material: Material

var bleeding := false
## Seconds it has bled since the cut (towards CLOT_TIME).
var bled_for := 0.0
## Seconds of binding left (0 = not binding).
var binding := 0.0
## Drops and winces so far (tests).
var drops := 0
var winces := 0
var _walked := 0.0
var _still := 0.0
var _last := Vector3.ZERO
var _wince := 0.0
var _drop_nodes: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()

@onready var player := get_parent() as Player


func _ready() -> void:
	_rng.randomize()


func _process(delta: float) -> void:
	if player == null or not bleeding:
		return
	if player.seized:
		binding = 0.0  # torn out of his hands
		return
	if binding > 0.0:
		binding -= delta
		if binding <= 0.0:
			binding = 0.0
			bleeding = false
			bound.emit()
		return
	bled_for += delta
	if bled_for >= CLOT_TIME:
		bleeding = false  # it has stopped by itself
		return
	_wince -= delta
	if _wince <= 0.0:
		_wince = _rng.randf_range(WINCE_MIN, WINCE_MAX)
		winces += 1
		Sfx.play_at("breath_hiss", player.global_position, 0.5, player)
		player.flinch(0.15)
	var pos := player.global_position
	if player.is_hidden or player.is_seated or player.crawling:
		_last = pos
		_still = 0.0
		return
	var moved := Vector2(pos.x - _last.x, pos.z - _last.z).length()
	_last = pos
	_walked += moved
	if delta > 0.0 and moved / delta < STILL_SPEED:
		_still += delta
	else:
		_still = 0.0
	if _walked >= DROP_SPACING or _still >= STILL_DROP:
		drop()


## Torn open (WireGap): it bleeds from now on; a hiss through the teeth, a
## start. The first drop falls as soon as he is out from under the wire.
func cut() -> void:
	bleeding = true
	bled_for = 0.0
	binding = 0.0
	_walked = DROP_SPACING
	_still = 0.0
	_last = player.global_position
	_wince = _rng.randf_range(WINCE_MIN, WINCE_MAX)
	PanicSystem.spike(CUT_PANIC)
	player.flinch(0.7)
	Sfx.play_at("breath_hiss", player.global_position, 1.0, player)
	cut_open.emit()


## Binds the wound (Player.use_item has spent the bandage): BIND_TIME s
## standing, a quiet rustle of cloth. False if there is nothing to bind.
func start_binding() -> bool:
	if not bleeding or binding > 0.0 or player.seized:
		return false
	binding = BIND_TIME
	Sfx.play_at("bandage_wrap", player.global_position, 1.0, player)
	Stealth.emit_noise(player.global_position, BIND_NOISE * (1.0 - 0.5 * _damping()), player)
	return true


func is_binding() -> bool:
	return binding > 0.0


## Bleeding as a checkpoint remembers it (LevelBase): no drops carried over,
## `bled` seconds of it already gone by (towards CLOT_TIME).
func set_bleeding(on: bool, bled: float = 0.0) -> void:
	bleeding = on
	bled_for = bled
	binding = 0.0
	_walked = 0.0
	_still = 0.0
	_last = player.global_position
	_wince = _rng.randf_range(WINCE_MIN, WINCE_MAX)


## A drop falls where he stands (a little to the side, on whatever is
## underfoot) and goes into his trail as blood.
func drop() -> void:
	_walked = 0.0
	_still = 0.0
	var off := Vector3(_rng.randf_range(-0.12, 0.12), 0.0, _rng.randf_range(-0.12, 0.12))
	var at := _ground_under(player.global_position + off)
	var level := player.get_parent()
	if level != null:
		var d := MeshInstance3D.new()
		d.name = "BloodDrop%d" % drops
		d.mesh = _mesh()
		d.material_override = _material()
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		d.scale = Vector3(_rng.randf_range(0.7, 1.3), 1.0, _rng.randf_range(0.7, 1.3))
		d.rotation.y = _rng.randf_range(0.0, TAU)
		level.add_child(d)
		d.global_position = at + Vector3.UP * 0.004
		_drop_nodes.append(d)
		while _drop_nodes.size() > MAX_DROPS:
			var old: Node3D = _drop_nodes.pop_front()
			if is_instance_valid(old):
				old.queue_free()
	Stealth.lay_blood(at)
	drops += 1
	dropped.emit(at)


## The drops on the ground now (oldest first).
func drop_nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for d in _drop_nodes:
		if is_instance_valid(d) and not d.is_queued_for_deletion():
			out.append(d)
	return out


## The ground (or floor) under `p`: a ray down past the boy himself.
func _ground_under(p: Vector3) -> Vector3:
	var space := player.get_world_3d().direct_space_state if player.is_inside_tree() else null
	if space == null:
		return p
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.6, p + Vector3.DOWN * 1.0, 1 | SURFACE_LAYER)
	q.exclude = [player.get_rid()]
	var hit := space.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else p


func _damping() -> float:
	return player.current_hide_spot.noise_damping if player.current_hide_spot != null else 0.0


static func _mesh() -> CylinderMesh:
	if _drop_mesh == null:
		_drop_mesh = CylinderMesh.new()
		_drop_mesh.top_radius = DROP_RADIUS
		_drop_mesh.bottom_radius = DROP_RADIUS
		_drop_mesh.height = 0.004
		_drop_mesh.radial_segments = 10
		_drop_mesh.rings = 1
	return _drop_mesh


## Blood: the red channel (CLAUDE.md, 2), a little wet.
static func _material() -> Material:
	if _drop_material == null:
		var m := StandardMaterial3D.new()
		m.roughness = 0.35
		_drop_material = ColorMask._marked(m, ColorMask.Channel.RED, true)
	return _drop_material
