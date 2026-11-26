class_name Player
extends CharacterBody3D
## The teenager (docs/GAMEPLAY_AND_SHADERS.md, section 2): no weapons,
## walk / crouch / sprint, hiding spots, breath control, panic-driven FOV.

signal hidden_changed(is_hidden: bool)

const STAND_EYE := 1.35
const CROUCH_EYE := 0.65
const STAND_HEIGHT := 1.5
const CROUCH_HEIGHT := 0.8
## Render layer the film passes get besides their own (layer 19): kept on
## screen while the camera shows only the satchel (_update_rummage).
const POST_LAYER := 1 << 18

@export var walk_speed: float = 2.2
@export var crouch_speed: float = 1.1
@export var sprint_speed: float = 4.0
@export var mouse_sensitivity: float = 0.0025
## Right stick of a gamepad: radians a second at full tilt (times the
## sensitivity setting); the tilt is squared for fine aim.
@export var stick_look_speed: float = 2.6
@export var base_fov: float = 75.0
## Degrees removed from FOV at PanicLevel 1 (tunnel vision).
@export var panic_fov_narrowing: float = 22.0
@export var gravity: float = 9.8
## Look limits while hidden, degrees.
@export var hidden_yaw_limit: float = 35.0
@export var hidden_pitch_limit: float = 18.0
## Look limits while seated (the interrogation stool), degrees.
@export var seated_yaw_limit: float = 70.0
@export var seated_pitch_limit: float = 35.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var collision: CollisionShape3D = $Collision
@onready var interact_ray: RayCast3D = $Head/Camera3D/InteractRay
@onready var hide_overlay: ColorRect = $HideOverlay/Slits
@onready var satchel: SatchelView = $Head/Camera3D/SatchelView
@onready var breath: BreathControl = get_node_or_null("BreathControl")
@onready var hunger: Hunger = get_node_or_null("Hunger")
@onready var wound: Wound = get_node_or_null("Wound")
@onready var archive_ui: ArchiveUI = $ArchiveUI

var is_crouching := false
var is_hidden := false
## Crawling under barbed wire (WireGap): the crawl moves him, not the keys.
var crawling := false
var current_hide_spot: HideSpot = null
## Seated on a stool (Act III interrogation): no walking, the head turns
## within seated_*_limit around the seat's view.
var is_seated := false
## Caught: held by the collar, no control (seized_by).
var seized := false
var _captor: Node3D = null
## Yaw and pitch at the grab; how far the jerk towards the captor has got.
var _seize_from := Vector2.ZERO
var _seize_k := 0.0
var _seat: Node3D = null
## Noise of the last footstep (0 when standing still); read by tests/debug.
var last_step_loudness := 0.0
## 0..1: how much torch light comes through the gaps of the hiding spot.
var torch_leak := 0.0
## How much of the torch light the overlay paints into the gaps: narrow
## slits concentrate it, a wide opening is lit by the real beam already.
var _leak_gain := 1.0
## 0..1: how far the door of the hiding place has been swung open by a
## searcher (the crack widens into the whole view).
var _opened_k := 0.0
## The torch light in the gaps may turn back - brighten after dimming, or
## dim after brightening - only this long after it last turned, s; until
## then it stays where it is. A beam grazing the edge of the stove or the
## table would otherwise flash in the gaps (docs/ARCHITECTURE.md,
## "Вспышки и мерцание").
const LEAK_MIN_SWING := 0.5
var _leak_dir := 0
var _leak_swing_age := 0.0
var _flinch_tween: Tween = null
## The view's dip in a flinch and its rise and fall with each breath when
## he is out of breath, with the tremble of his ragged breath in hiding
## (BreathControl, «Дыхание рвётся»); together they are camera.v_offset.
var _flinch_dip := 0.0
var breath_sway := 0.0
## Running this frame (the sprint key held while actually moving).
var sprinting := false
## Dust from the boards overhead (0..1, fades over DUST_FADE s); falls so
## far (tests). Only footfalls within DUST_RADIUS m of the cellar count.
const DUST_RADIUS := 1.6
const DUST_FADE := 2.5
var dust := 0.0
var dust_falls := 0
var _dust_time := 0.0

## Leaning out (docs/ARCHITECTURE.md, "Выглянуть"): holding `lean` with a
## step left, right or forward tilts the head out round a jamb or a corner
## while the feet stay put. Metres to the side and forward at full tilt.
const LEAN_SIDE := 0.35
const LEAN_FORWARD := 0.3
## At full tilt the head drops this far and, leaning sideways, rolls this
## far (radians, about 12 degrees) - on the Head node; the camera keeps its
## own roll for the jerk of a capture.
const LEAN_DROP := 0.06
const LEAN_ROLL := 0.21
## How fast the head follows the key, 1/s: 90 % of the way in 0.3 s.
const LEAN_RATE := 8.0
## The head as a ball: it stops at walls, closed doors and the invisible
## barriers (layers 1, 5 and 6), never inside them.
const LEAN_HEAD_RADIUS := 0.15
## The world, IzbaDoor.DOOR_LAYER and Stealth.SEE_THROUGH_LAYER (a test
## holds them equal).
const LEAN_BLOCK_MASK := 1 | 1 << 4 | 1 << 5
## Where the head is leant to, in the boy's own space (x to his right,
## -z ahead); zero when he stands straight.
var _lean := Vector3.ZERO
var _lean_ball: SphereShape3D = null

var _pitch := 0.0
## The satchel's pick is ready for the next push (_pick_in_satchel).
var _pick_armed := true
## Rummaging in the open satchel in a hiding place (_update_rummage).
var _rummaging := false
## What the camera shows when he is not rummaging.
var _view_mask := 0
var _hide_yaw := 0.0
var _hide_pitch := 0.0
var _step_timer := 0.0
var _return_transform: Transform3D


func _ready() -> void:
	Stealth.player = self
	camera.fov = base_fov
	hide_overlay.visible = false
	_view_mask = camera.cull_mask
	# The film passes must stay on screen while only the satchel is shown.
	for pass_node in camera.get_node("PostProcess").get_children():
		if pass_node is VisualInstance3D:
			(pass_node as VisualInstance3D).layers |= POST_LAYER
	_capture_mouse(true)


func _exit_tree() -> void:
	if Stealth.player == self:
		Stealth.player = null
	if is_hidden:
		Sfx.set_muffle(Sfx.OPEN_AIR, 0.0, 0.0)


func is_input_locked() -> bool:
	return satchel.is_open or seized or crawling


## Something takes his hands and his legs for a while: crawling under the
## wire, binding the wound (he can still look about while binding).
func busy() -> bool:
	return crawling or (wound != null and wound.is_binding())


# --- input -----------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if seized:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
			and not is_input_locked() and not is_scripted_run():
		_look(event.relative)
	elif satchel.is_open and event.is_action_pressed("interact"):
		use_item(satchel.selected_item())
	elif event.is_action_pressed("interact") and not is_input_locked() and not busy():
		if not _swaps_view_on_interact() or Flicker.allow_swap():
			try_interact()
	elif event.is_action_pressed("inventory") and not busy():
		# In a hiding place the satchel takes the whole view (_update_rummage).
		if not is_hidden or Flicker.allow_swap():
			satchel.toggle()
	elif event.is_action_pressed("archive_journal"):
		if Flicker.allow_swap():
			archive_ui.open_journal()


func _process(delta: float) -> void:
	_update_rummage()
	camera.v_offset = _flinch_dip + breath_sway + (hunger.tremor_offset() if hunger != null else 0.0)
	if seized:
		_hold_gaze()
		return
	if satchel.is_open and not get_tree().paused:
		_pick_in_satchel()
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick == Vector2.ZERO or is_input_locked() or get_tree().paused:
		return
	_look(stick * stick.length() * stick_look_speed * delta / mouse_sensitivity)


## The satchel open in a hiding place: the slits are a 2D layer over the
## whole view and would hide it, so he looks into the satchel instead of out
## through the gaps - only the satchel (and the film passes) in the dark,
## the slits gone. Close it to watch the room again; sound goes on.
func _update_rummage() -> void:
	var r := is_hidden and satchel.is_open
	if r == _rummaging:
		return
	_rummaging = r
	camera.cull_mask = (SatchelView.LAYER | POST_LAYER) if r else _view_mask
	satchel.set_rummaging(r)
	hide_overlay.visible = is_hidden and not r


## Left / right in the open satchel: the strafe keys or stick, the arrows or
## the d-pad. One push is one step: the stick has to come back towards the
## middle before it steps again.
func _pick_in_satchel() -> void:
	var x := clampf(Input.get_axis("move_left", "move_right") + Input.get_axis("ui_left", "ui_right"), -1.0, 1.0)
	if absf(x) < 0.3:
		_pick_armed = true
	elif absf(x) > 0.5 and _pick_armed:
		_pick_armed = false
		satchel.select_step(1 if x > 0.0 else -1)


func _look(relative: Vector2) -> void:
	relative *= GameState.mouse_factor()
	if is_hidden or is_seated:
		var yl := deg_to_rad(seated_yaw_limit if is_seated else hidden_yaw_limit)
		var pl := deg_to_rad(seated_pitch_limit if is_seated else hidden_pitch_limit)
		_hide_yaw = clampf(_hide_yaw - relative.x * mouse_sensitivity, -yl, yl)
		_hide_pitch = clampf(_hide_pitch - relative.y * mouse_sensitivity, -pl, pl)
		_place_hidden_camera()
		return
	rotate_y(-relative.x * mouse_sensitivity)
	_pitch = clampf(_pitch - relative.y * mouse_sensitivity, deg_to_rad(-80), deg_to_rad(80))
	head.rotation.x = _pitch
	_clamp_lean()


## E into or out of a hiding place swaps the whole view (the boards): such
## a press waits for Flicker.allow_swap(), like the journal and the pause.
func _swaps_view_on_interact() -> bool:
	if is_hidden:
		return true
	if is_seated:
		return false
	interact_ray.force_raycast_update()
	var target := interact_ray.get_collider()
	return target is HideSpot and (target as HideSpot).can_interact(self)


func try_interact() -> bool:
	if is_seated:
		return false
	if is_hidden:
		current_hide_spot.interact(self)
		return true
	interact_ray.force_raycast_update()
	var target := interact_ray.get_collider()
	if target is Interactable and (target as Interactable).can_interact(self):
		(target as Interactable).interact(self)
		return true
	return false


## Turn body (yaw) and head (pitch) towards a world point.
func look_towards(point: Vector3) -> void:
	if is_seated:
		var local := _seat.global_transform.affine_inverse() * point
		_hide_yaw = clampf(atan2(-local.x, -local.z), -deg_to_rad(seated_yaw_limit), deg_to_rad(seated_yaw_limit))
		_hide_pitch = clampf(atan2(local.y, Vector2(local.x, local.z).length()),
				-deg_to_rad(seated_pitch_limit), deg_to_rad(seated_pitch_limit))
		_place_hidden_camera()
		return
	# From the head as it stands straight: the body turns round its own axis.
	var to := point - (head.global_position - lean_offset())
	rotation.y = atan2(-to.x, -to.z)
	_pitch = clampf(atan2(to.y, Vector2(to.x, to.z).length()), deg_to_rad(-80), deg_to_rad(80))
	head.rotation.x = _pitch
	_clamp_lean()


func open_document(document_id: String) -> void:
	archive_ui.open_document(document_id)


## Uses a thing from the satchel (docs/ARCHITECTURE.md, "Голод и хлеб"): a
## document is read, bread eaten if he is hungry. Anything else - or bread
## when he is not hungry - is of no use now: the satchel shakes it. Returns
## whether it was used.
func use_item(item: ItemData) -> bool:
	if item == null or seized:
		return false
	if item.document_id != "":
		satchel.close()
		open_document(item.document_id)
		return true
	if item.id == "bread" and hunger != null and hunger.wants_bread():
		Inventory.remove_item("bread")
		hunger.eat()
		return true
	if item.id == "bandage" and wound != null and wound.bleeding and not wound.is_binding():
		# He binds the wound: the satchel shut, a few seconds standing.
		Inventory.remove_item("bandage")
		satchel.close()
		wound.start_binding()
		return true
	satchel.refuse()
	return false


# --- movement ----------------------------------------------------------------

func _physics_process(delta: float) -> void:
	camera.fov = lerpf(camera.fov, base_fov - PanicSystem.level * panic_fov_narrowing, 4.0 * delta)
	_update_torch_leak(delta)
	_update_dust(delta)
	if is_hidden or is_seated or is_input_locked() or busy():
		velocity = Vector3.ZERO
		last_step_loudness = 0.0
		sprinting = false
		if _lean != Vector3.ZERO:
			_update_lean(Vector2.ZERO, delta)
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	_update_crouch(Input.is_action_pressed("crouch"))
	var run := Input.is_action_pressed("sprint") and not is_crouching
	var speed := crouch_speed if is_crouching else (run_speed() if run else walk_speed)

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if Input.is_action_pressed("lean"):
		# The step keys tilt the head; the feet stay put. Back does nothing,
		# not even shorten a side lean (get_vector would scale it down).
		var want := Vector2(Input.get_axis("move_left", "move_right"),
				Input.get_action_strength("move_forward")).limit_length(1.0)
		_update_lean(want, delta)
		input = Vector2.ZERO
	elif _lean != Vector3.ZERO:
		_update_lean(Vector2.ZERO, delta)
	var dir := (transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	move_and_slide()
	sprinting = run and Vector2(velocity.x, velocity.z).length() > 0.5

	_update_eye(delta)
	_footsteps(delta, sprinting)


## The head goes to eye height - standing or crouched, a little lower while
## leant out.
func _update_eye(delta: float) -> void:
	var eye := CROUCH_EYE if is_crouching else STAND_EYE
	head.position.y = lerpf(head.position.y, eye - _lean_drop(_lean), 10.0 * delta)


## How much lower the head is leant out by `offset` (his own space).
func _lean_drop(offset: Vector3) -> float:
	return LEAN_DROP * minf(offset.length() / LEAN_SIDE, 1.0)


## Where the head is leant to, in the world, from where it would be (zero
## when he stands straight). The enemies' eyes look for his shoulders half
## as far out (Enemy.sight_points).
func lean_offset() -> Vector3:
	return global_basis * _lean


## The middle of his shoulders: under the head, half as far out when he
## leans - where the enemies look for them (Enemy.sight_points). The light
## on him is taken here (Stealth.update_light).
func shoulders() -> Vector3:
	return head.global_position - lean_offset() * 0.5 - Vector3.UP * 0.25


## Keeps a leant head out of the walls at once when he turns: the mouse and
## the stick turn him between physics frames.
func _clamp_lean() -> void:
	if _lean != Vector3.ZERO:
		_set_lean(_lean * _lean_room(_lean))


## What an eye at `eye` looks for of him - his head and both shoulders,
## leant out or not (Enemy.sight_points). An enemy's eyes and a searchlight
## ask the same.
func sight_points_from(eye: Vector3) -> PackedVector3Array:
	return Enemy.sight_points(eye, head.global_position, lean_offset())


## Move the head towards a lean of `want` (x: -1 left .. 1 right, y: 0 ..
## 1 forward), smoothly, and no further than the walls let it.
func _update_lean(want: Vector2, delta: float) -> void:
	var goal := Vector3(want.x * LEAN_SIDE, 0.0, -want.y * LEAN_FORWARD)
	var next := _lean.lerp(goal, 1.0 - exp(-LEAN_RATE * delta))
	if next.length() < 0.001:
		next = Vector3.ZERO
	else:
		next *= _lean_room(next)
	_set_lean(next)


## How much of the lean `offset` (his own space) the head can take before
## a wall, a closed door or a barrier stops it: 0..1. The ball of the head
## is moved out from where the head stands straight.
func _lean_room(offset: Vector3) -> float:
	if _lean_ball == null:
		_lean_ball = SphereShape3D.new()
		_lean_ball.radius = LEAN_HEAD_RADIUS
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _lean_ball
	q.transform = Transform3D(Basis(), global_transform * Vector3(0.0, head.position.y, 0.0))
	q.motion = global_basis * offset
	q.collision_mask = LEAN_BLOCK_MASK
	q.exclude = [get_rid()]
	var r := get_world_3d().direct_space_state.cast_motion(q)
	return r[0] if r.size() == 2 else 1.0


func _set_lean(offset: Vector3) -> void:
	# The drop goes with the lean, also while he cannot move. The eye height
	# itself is not touched here: _update_eye's when he can move, the wire
	# gap's while he crawls (WireGap.CRAWL_EYE), as it was before the lean.
	head.position.y += _lean_drop(_lean) - _lean_drop(offset)
	_lean = offset
	head.position.x = offset.x
	head.position.z = offset.z
	head.rotation.z = -offset.x / LEAN_SIDE * LEAN_ROLL


## Loudness of his steps for Stealth (enemies hear 0..1 x HEARING_RANGE).
const STEP_CROUCH_NOISE := 0.15
const STEP_WALK_NOISE := 0.5
const STEP_RUN_NOISE := 1.0
## On floorboards (BoardFloor; docs/ARCHITECTURE.md, "Шаги мальчика по
## доскам") every step knocks louder, and now and then a board creaks -
## crouched too, less often. A creak is its own noise.
const BOARD_NOISE := 1.3
const CREAK_NOISE := 0.35
@export var board_creak_chance: float = 0.3
@export var board_creak_chance_crouched: float = 0.15
var step_rng := RandomNumberGenerator.new()
## Boards that creaked under him so far (tests).
var creaks := 0

## Running speed: fully out of breath he can no longer run flat out
## (from WINDED_SLOW of the way to the end, down to halfway to a walk).
const WINDED_SLOW := 0.8


func run_speed() -> float:
	var w: float = breath.winded if breath != null else 0.0
	var k := clampf((w - WINDED_SLOW) / (1.0 - WINDED_SLOW), 0.0, 1.0)
	return lerpf(sprint_speed, 0.5 * (sprint_speed + walk_speed), k)


func _update_crouch(want_crouch: bool) -> void:
	if want_crouch == is_crouching:
		return
	if not want_crouch and test_move(global_transform, Vector3.UP * (STAND_HEIGHT - CROUCH_HEIGHT)):
		return  # no room to stand up
	is_crouching = want_crouch
	var capsule := collision.shape as CapsuleShape3D
	capsule.height = CROUCH_HEIGHT if is_crouching else STAND_HEIGHT
	collision.position.y = capsule.height * 0.5


func _footsteps(delta: float, running: bool) -> void:
	var horizontal := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor() or horizontal < 0.3:
		_step_timer = 0.0
		last_step_loudness = 0.0
		return
	_step_timer -= delta
	if _step_timer > 0.0:
		return
	if is_crouching:
		_step_timer = 0.7
		last_step_loudness = STEP_CROUCH_NOISE
	elif running:
		_step_timer = 0.32
		last_step_loudness = STEP_RUN_NOISE
	else:
		_step_timer = 0.55
		last_step_loudness = STEP_WALK_NOISE
	var boards := BoardFloor.at(get_tree(), global_position + Vector3.UP * 0.05) != null
	if boards:
		last_step_loudness *= BOARD_NOISE
	Stealth.emit_noise(global_position, last_step_loudness, self)
	Stealth.lay_scent(global_position)
	Sfx.play_at("step_player_board" if boards else "step_player", global_position, last_step_loudness)
	var chance := board_creak_chance_crouched if is_crouching else board_creak_chance
	if boards and step_rng.randf() < chance:
		creaks += 1
		Sfx.play_at("floor_creak", global_position, 0.8)
		Stealth.emit_noise(global_position, CREAK_NOISE, self)


## Doors, the cellar lid, hay: crouched, he does it slowly and carefully -
## half as loud (docs/ARCHITECTURE.md, "Шум от действий"). Hidden or seated,
## crouch is not tracked: the button held now counts.
const CAREFUL := 0.5


func care() -> float:
	var crouched := Input.is_action_pressed("crouch") if is_hidden or is_seated else is_crouching
	return CAREFUL if crouched else 1.0


# --- hiding ------------------------------------------------------------------

func enter_hide_spot(spot: HideSpot) -> void:
	is_hidden = true
	current_hide_spot = spot
	_return_transform = global_transform
	velocity = Vector3.ZERO
	_set_lean(Vector3.ZERO)
	collision.disabled = true
	global_position = spot.global_position
	_hide_yaw = 0.0
	_hide_pitch = 0.0
	camera.top_level = true
	_place_hidden_camera()
	var mat := hide_overlay.material as ShaderMaterial
	mat.set_shader_parameter("vertical", spot.slits == HideSpot.Slits.VERTICAL)
	mat.set_shader_parameter("slit_width", spot.slit_width)
	mat.set_shader_parameter("slit_count", float(spot.slit_count))
	_leak_gain = clampf(pow(0.16 / spot.slit_width, 2.0), 0.15, 1.0)
	_opened_k = 0.0
	Sfx.set_muffle(spot.muffle_hz, spot.muffle_db)
	hide_overlay.visible = true
	hidden_changed.emit(true)


func exit_hide_spot() -> void:
	is_hidden = false
	current_hide_spot = null
	global_transform = _return_transform
	collision.disabled = false
	camera.top_level = false
	camera.transform = Transform3D.IDENTITY
	hide_overlay.visible = false
	Sfx.set_muffle(Sfx.OPEN_AIR, 0.0)
	hidden_changed.emit(false)


## A torch beam passing over the hiding spot: the gaps flare with light and
## the boy's panic jumps. Purely what he sees and feels; enemies still need
## a sound or a dog to find him.
func _update_torch_leak(delta: float) -> void:
	var target := 0.0
	if is_hidden and current_hide_spot != null:
		var p := current_hide_spot.leak_point()
		for e in get_tree().get_nodes_in_group("enemies"):
			target = maxf(target, (e as Enemy).torch_light_at(p))
	_follow_leak(minf(target * 2.5, 1.0), delta)
	var mat := hide_overlay.material as ShaderMaterial
	mat.set_shader_parameter("leak", shown_leak())
	if is_hidden and current_hide_spot != null and current_hide_spot.is_open and _opened_k == 0.0:
		# The doors swing open: the room comes in loud and clear.
		Sfx.set_muffle(Sfx.OPEN_AIR, 0.0, current_hide_spot.open_delay)
	if is_hidden and current_hide_spot != null and current_hide_spot.is_open and _opened_k < 1.0:
		_opened_k = move_toward(_opened_k, 1.0, delta / maxf(current_hide_spot.open_delay, 0.05))
		mat.set_shader_parameter("slit_width", lerpf(current_hide_spot.slit_width, 1.6, _opened_k))
	if torch_leak > 0.2:
		PanicSystem.apply_continuous(0.35 * torch_leak, delta)


## The torch light in the gaps moves towards `goal` at 4 a second, but turns
## back no sooner than LEAK_MIN_SWING after it last turned.
func _follow_leak(goal: float, delta: float) -> void:
	_leak_swing_age += delta
	var dir := 0
	if goal > torch_leak + 0.0001:
		dir = 1
	elif goal < torch_leak - 0.0001:
		dir = -1
	if dir == 0:
		return
	if dir != _leak_dir:
		if _leak_dir != 0 and _leak_swing_age < LEAK_MIN_SWING:
			return  # too soon to turn back: the light stays where it is
		_leak_dir = dir
		_leak_swing_age = 0.0
	torch_leak = move_toward(torch_leak, goal, 4.0 * delta)


## What the overlay paints into the gaps: the leak by the gaps' width, gone
## as the doors of the hiding place swing open - the room is lit by the real
## beam then, not by dust trembling over half the screen.
func shown_leak() -> float:
	return torch_leak * _leak_gain * (1.0 - _opened_k)


## Boots on the boards over the hiding place (a cellar, HideSpot.under_floor):
## grey dust sifts down through the gaps, he flinches and his heart jumps.
## `at` - the footfall (Gait); only steps right over him count.
func boards_overhead(at: Vector3, loudness: float = 1.0) -> void:
	if not is_hidden or current_hide_spot == null or not current_hide_spot.under_floor:
		return
	var c := current_hide_spot.global_position
	var dist := Vector2(at.x - c.x, at.z - c.z).length()
	if dist > DUST_RADIUS:
		return
	var k := (1.0 - dist / DUST_RADIUS) * clampf(loudness, 0.0, 1.0)
	dust = maxf(dust, 0.45 + 0.55 * k)
	dust_falls += 1
	flinch(0.3 + 0.5 * k)
	PanicSystem.spike(0.02 + 0.04 * k)


func _update_dust(delta: float) -> void:
	dust = move_toward(dust, 0.0, delta / DUST_FADE)
	if is_hidden:
		_dust_time += delta
	var mat := hide_overlay.material as ShaderMaterial
	mat.set_shader_parameter("dust", dust)
	mat.set_shader_parameter("dust_time", _dust_time)


## Start at a sudden loud sound (a shot): the view dips and comes back.
## 0..1+ strength; the camera's own offset, so it works hidden and seated.
func flinch(strength: float) -> void:
	var dip := -0.05 * clampf(strength, 0.0, 1.5)
	if _flinch_tween != null:
		_flinch_tween.kill()
	_flinch_tween = create_tween()
	_flinch_tween.tween_property(self, "_flinch_dip", dip, 0.06)
	_flinch_tween.tween_property(self, "_flinch_dip", 0.0, 0.4).set_trans(Tween.TRANS_SINE)


## Panic added when a kicked-in door leaf strikes him.
const STRUCK_PANIC := 0.2


## A kicked-in door leaf strikes him (IzbaDoor._clear_way; docs/ARCHITECTURE.md,
## "Дверь избы"): a dull blow, a start, and the wind knocked out of him -
## the loud gasp the one who kicked the door hears; a held breath breaks.
func struck() -> void:
	Sfx.play_at("door_hit", camera.global_position)
	flinch(1.5)
	PanicSystem.spike(STRUCK_PANIC)
	if breath != null:
		breath.knock_out()


## Sit down: the camera goes to the seat's transform (its -Z is the view).
## A staged scene takes him over: a hold on him (seized) ends.
func sit_at(seat: Node3D) -> void:
	if is_hidden:
		exit_hide_spot()
	seized = false
	is_seated = true
	_seat = seat
	velocity = Vector3.ZERO
	_set_lean(Vector3.ZERO)
	collision.disabled = true
	global_position = seat.global_position - Vector3.UP * CROUCH_EYE
	_hide_yaw = 0.0
	_hide_pitch = 0.0
	camera.top_level = true
	_place_hidden_camera()


## Stand up at the given place (facing its -Z).
func stand_up(at: Transform3D) -> void:
	seized = false
	is_seated = false
	_seat = null
	global_transform = Transform3D(Basis(Vector3.UP, at.basis.get_euler().y), at.origin)
	_pitch = 0.0
	head.rotation.x = 0.0
	collision.disabled = false
	camera.top_level = false
	camera.transform = Transform3D.IDENTITY


func _place_hidden_camera() -> void:
	var base := _seat.global_transform if is_seated else current_hide_spot.view_transform()
	var look := Basis.from_euler(Vector3(_hide_pitch, _hide_yaw, 0.0))
	camera.global_transform = Transform3D(base.basis * look, base.origin)


# --- capture -----------------------------------------------------------------

## Seconds his head is jerked round to the one who caught him.
const SEIZE_TURN := 0.22
## How far the view rolls when he is jerked by the collar (radians).
const SEIZE_ROLL := 0.09
## Looking up at a face, the eyes stop a little below it (radians), so the
## face hangs in the upper part of the view over the dark figure.
const SEIZE_LIFT := 0.22


## Caught (docs/ARCHITECTURE.md, "Поимка"): a hand on his collar. He is
## pulled out of his hiding place, his head jerks round to the one who
## caught him, he gasps; he can no longer move or look away. Nothing more is
## shown: the level cuts to black (LevelBase._on_caught). Sitting down or
## standing up in a staged scene, or release(), lets go.
func seized_by(captor: Node3D) -> void:
	if seized:
		return
	seized = true
	velocity = Vector3.ZERO
	_set_lean(Vector3.ZERO)
	if satchel.is_open:
		satchel.close()
	if is_hidden:
		current_hide_spot.eject(self)  # pulled out: no sound of his own
	_captor = captor
	Sfx.play_at("seize_grab", camera.global_position)
	Sfx.play_at("breath_gasp", camera.global_position)
	flinch(1.5)
	if is_seated:
		look_towards(seize_face(captor))
		return
	_seize_from = Vector2(rotation.y, _pitch)
	_seize_k = 0.0
	var turn := create_tween()
	turn.tween_property(self, "_seize_k", 1.0, SEIZE_TURN) 			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hold_gaze()
	var roll := create_tween()
	roll.tween_property(camera, "rotation:z", SEIZE_ROLL if randf() < 0.5 else -SEIZE_ROLL, 0.07)
	roll.tween_property(camera, "rotation:z", 0.0, 0.5).set_trans(Tween.TRANS_SINE)


## Where he looks when caught: the captor's face as he sees it - a head
## stretched up by the distortion (Enemy.drawn_point), a dog's head too;
## else 1.6 m up.
static func seize_face(captor: Node3D) -> Vector3:
	if not is_instance_valid(captor):
		return Vector3.ZERO
	var h := captor.get_node_or_null("Visual/Head") as Node3D
	if h == null:
		return captor.global_position + Vector3.UP * 1.6
	if captor is Enemy:
		return (captor as Enemy).drawn_point(h.global_position)
	return h.global_position


## While held: the jerk towards the face, then the eyes stay on it as the
## figure stretches with his panic.
func _hold_gaze() -> void:
	if is_seated or not is_instance_valid(_captor):
		return
	var to := seize_face(_captor) - head.global_position
	if Vector2(to.x, to.z).length() < 0.01:
		return
	var yaw := _seize_from.x + angle_difference(_seize_from.x, atan2(-to.x, -to.z))
	var pitch := atan2(to.y, Vector2(to.x, to.z).length())
	pitch = clampf(pitch - minf(SEIZE_LIFT, maxf(pitch, 0.0) * 0.4), deg_to_rad(-80), deg_to_rad(80))
	rotation.y = lerpf(_seize_from.x, yaw, _seize_k)
	_pitch = lerpf(_seize_from.y, pitch, _seize_k)
	head.rotation.x = _pitch


## Let go (the test scene's searcher lets him go and starts again).
func release() -> void:
	seized = false
	_captor = null


## Headless runs and Movie Maker renders must not depend on the real mouse.
static func is_scripted_run() -> bool:
	return DisplayServer.get_name() == "headless" or Engine.get_write_movie_path() != ""


func _capture_mouse(capture: bool) -> void:
	if is_scripted_run():
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE
