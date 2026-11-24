class_name IzbaDoor
extends Node3D
## Hinged door. The node origin is the hinge; the panel extends along +X.
## The panel lives on physics layer 5 ("doors"): it blocks the player, a dog
## (Dog adds the layer to its mask) and the enemies' line of sight, but not
## navigation (the navmesh is baked from layer 1 only) and not the bodies of
## men - they open it when they come close.
## The player opens/closes it with the latch (blue-green, interactive).
## The leaf turns in the physics frame, a little at a time. Opening, it
## shoves the boy out of its way - straight off its face, and past its tip
## straight away from its end; it stops against him if that way is blocked.
## Kicked in, it strikes him where it first touches him, once a kick
## (Player.struck). Shutting, or with him held by the collar, it stops
## against him (docs/ARCHITECTURE.md, "Дверь избы").

signal opened
signal closed

const DOOR_LAYER := 1 << 4
## The boy at the latch: the creak is heard by enemies (Stealth loudness),
## halved when he opens it slowly, crouched (Player.care). Enemies opening
## the door make no noise for each other.
const PLAYER_NOISE := 0.5

## Degrees around Y when open (negative swings inward, towards +Z).
@export var open_angle: float = -100.0
@export var open_time: float = 0.8
@export var kick_time: float = 0.25
## Enemies closer than this to the hinge open the door themselves.
@export var enemy_open_distance: float = 1.6
@export var start_open: bool = false
## Off while a story beat wants the door shut until it is kicked in: then
## only an enemy hunting the boy opens it - he kicks it in (_hunting).
@export var enemies_can_open: bool = true

## The most the leaf turns at a time before it looks for the boy in its way
## (degrees): its tip, 1.2 m out, moves 4 cm - well under his radius - so it
## never jumps over him, however long the frame or hard the kick.
const SWING_STEP_DEG := 2.0

var is_open := false
## The panel as it is in the scene (izba_door.tscn, Panel/Shape): how far it
## reaches from the hinge along +X, and half its thickness. Read in _ready.
var leaf_length := 0.0
var leaf_half_thickness := 0.0
## The swing under way: from and to (degrees), how long it takes, and how
## far along it is (0..1; 1 - the leaf at rest).
var _swing_from := 0.0
var _swing_to := 0.0
var _swing_time := 1.0
var _swing_t := 1.0
## Kicked in (open(true)): the leaf strikes the boy it meets - once a kick.
var _kicking := false
var _struck := false

@onready var latch: Interactable = $Latch


func _ready() -> void:
	$Panel.collision_layer = DOOR_LAYER
	$Panel.collision_mask = 0
	var box := ($Panel/Shape as CollisionShape3D).shape as BoxShape3D
	leaf_length = ($Panel as Node3D).position.x + box.size.x * 0.5
	leaf_half_thickness = box.size.z * 0.5
	latch.interacted.connect(_on_latch)
	if start_open:
		is_open = true
		rotation_degrees.y = open_angle


func _on_latch(p: Node) -> void:
	var k: float = p.care() if p != null and p.has_method("care") else 1.0
	toggle(k)
	Stealth.emit_action_noise(sound_point(), PLAYER_NOISE * k, p)


## Where the door sounds: the middle of the doorway, where the panel stands
## when shut, whichever way it swings now - not the hinge post (a sound on
## the post is half inside the wall for Sfx.is_occluded), and not the open
## leaf inside the room (closing it, the latch would sound behind the jamb).
func sound_point() -> Vector3:
	var shut := global_transform.basis * Basis(Vector3.UP, -rotation.y)
	return global_position + shut * ($Panel as Node3D).position


## A shut door stops sound for enemies' ears (Stealth.stops_sound); an open
## or swinging leaf does not - sound goes round it through the doorway.
func blocks_sound() -> bool:
	return not is_open and absf(rotation_degrees.y) < 3.0


## `volume`: of the creak (a careful hand opens it quieter).
func toggle(volume: float = 1.0) -> void:
	if is_open:
		close(volume)
	else:
		open(false, volume)


func open(kick: bool = false, volume: float = 1.0) -> void:
	if is_open:
		return
	is_open = true
	_kicking = kick
	_swing(open_angle, kick_time if kick else open_time)
	Sfx.play_at("door_kick" if kick else "door_creak", sound_point(), volume)
	if kick:
		PanicSystem.spike(0.3)
	opened.emit()


func close(volume: float = 1.0) -> void:
	if not is_open:
		return
	is_open = false
	_kicking = false
	_swing(0.0, open_time)
	Sfx.play_at("door_creak", sound_point(), volume)
	closed.emit()


func _swing(angle: float, time: float) -> void:
	_swing_from = rotation_degrees.y
	_swing_to = angle
	_swing_time = maxf(time, 0.001)
	_swing_t = 0.0
	_struck = false


## The leaf still on its way, or held up against the boy.
func is_swinging() -> bool:
	return _swing_t < 1.0


func _physics_process(delta: float) -> void:
	if _swing_t < 1.0:
		_turn(delta)
	if is_open:
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if (e as Node3D).global_position.distance_to(global_position) < enemy_open_distance \
				and not (e is Dog):
			if enemies_can_open:
				open()
				return
			if _hunting(e as Enemy):
				enemies_can_open = true  # kicked in: the story holds it shut no more
				open(true)
				return


## Held shut by the story (enemies_can_open off), the door is still kicked
## in by an enemy after the boy - suspicious, searching or alerted, not on
## his round or a scripted walk: the leaf does not stop enemy bodies, and he
## would walk through it (docs/ARCHITECTURE.md, "Дверь избы").
static func _hunting(e: Enemy) -> bool:
	return e.state != Enemy.State.PATROL and not e.passive and e.can_process()


## One physics frame of the swing (quadratic ease-out, as it always eased),
## in steps of SWING_STEP_DEG, each one clearing the boy out of the way
## first. Held up by him, the leaf stays where it got to and the swing waits
## for him to move.
func _turn(delta: float) -> void:
	var t := minf(_swing_t + delta / _swing_time, 1.0)
	var target := lerpf(_swing_from, _swing_to, 1.0 - (1.0 - t) * (1.0 - t))
	var angle := rotation_degrees.y
	if (target - angle) * (_swing_to - _swing_from) < 0.0:
		target = angle  # held up last frame further on than this frame's ease
	var boy := get_tree().get_first_node_in_group("player") as Player
	var steps := maxi(1, ceili(absf(target - angle) / SWING_STEP_DEG))
	for i in steps:
		var next := lerpf(angle, target, float(i + 1) / steps)
		if not _clear_way(boy, next):
			return
		rotation_degrees.y = next
	_swing_t = t


## Before the leaf turns to `angle`: the boy in its way there is moved out
## of it along the floor - straight off its face, or past its tip straight
## away from its end - the way an opening door shoves whoever stands behind
## it. False - the leaf stops against him - if
## that way is blocked (a wall, the jamb, a soldier at his back: he is not
## slid along them), if the door is being shut (his own hand pulls it, and
## it must not sweep him out through the doorway), or if he is held by the
## collar (Player.seized). A hidden boy is not in the room. Kicked in, the
## leaf strikes him at the first touch (Player.struck) - pinned against a
## wall too, but not held by the collar.
func _clear_way(boy: Player, angle: float) -> bool:
	if boy == null or boy.is_hidden or not boy.is_inside_tree():
		return true
	var radius := (boy.collision.shape as CapsuleShape3D).radius
	var push := leaf_push(boy.global_position, angle, radius)
	if push == Vector3.ZERO:
		return true
	if boy.seized or is_zero_approx(_swing_to):
		return false
	if _kicking and not _struck:
		_struck = true
		boy.struck()
	boy.move_and_collide(push)
	return leaf_push(boy.global_position, angle, radius).length() < 0.005


## How far a body of `radius` standing at `at` has to move along the floor
## to be clear of the leaf turned to `angle` (degrees, as rotation_degrees.y);
## zero if it is clear already, or above or below the door. The leaf is the
## panel as it is, a box with a square end: beside it he goes straight off
## its face, past its tip straight away from the nearest point of its end.
func leaf_push(at: Vector3, angle: float, radius: float) -> Vector3:
	if absf(at.y - global_position.y) > 1.0:
		return Vector3.ZERO
	var shut := global_transform.basis * Basis(Vector3.UP, -rotation.y)
	var along := shut * Basis(Vector3.UP, deg_to_rad(angle)) * Vector3.RIGHT
	var d := Vector2(along.x, along.z).normalized()
	var across := Vector2(d.y, -d.x)
	var rel := Vector2(at.x, at.z) - Vector2(global_position.x, global_position.z)
	var nearest := d * clampf(rel.dot(d), 0.0, leaf_length) \
			+ across * clampf(rel.dot(across), -leaf_half_thickness, leaf_half_thickness)
	var away := rel - nearest
	var dist := away.length()
	if dist >= radius:
		return Vector3.ZERO
	var need := radius - dist
	if dist < 0.0001:
		# Inside the panel itself: out of its face the way the leaf is turning.
		away = across * signf(_swing_to - _swing_from)
		need = radius + leaf_half_thickness - rel.dot(away)
	var out := away.normalized() * (need + 0.002)
	return Vector3(out.x, 0.0, out.y)
