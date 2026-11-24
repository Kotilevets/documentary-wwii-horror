class_name Enemy
extends CharacterBody3D
## Occupier / auxiliary policeman (docs/GAMEPLAY_AND_SHADERS.md, 2; CLAUDE.md, 3).
## PATROL -> SUSPICIOUS -> SEARCH / ALERT. Sight: cone + line of sight.
## Hearing: Stealth.noise_emitted. Feeds the player's panic while the player
## is in the cone or close by. Visual distortion is done in shaders; this
## script only feeds them feet_origin / grotesque.

signal player_caught(enemy: Enemy)
signal state_changed(state: State)
## The scripted route given by script_goto() has been walked to the end.
signal scripted_finished

enum State { PATROL, SUSPICIOUS, SEARCH, ALERT }
## OFFICER: field cap, no helmet, no mask (Act III, the GFP investigator).
enum Kind { SOLDIER, FELDGENDARM, POLIZEI, OFFICER }

const SUSPICIOUS_AT := 0.35
## Where the boy was lost: an obvious hiding place this close is looked into.
const REDIRECT_RADIUS := 3.5
## Resting pitch of the chest torch (degrees, down).
const TORCH_PITCH := -22.0
## Darkness (Stealth.player_light, docs/ARCHITECTURE.md "Свет и тень"): with
## no light at all the boy is seen only within DARK_SIGHT of view_distance
## (never nearer than CLOSE_SIGHT) and suspicion grows at DARK_RATE of the
## usual rate. An enemy already chasing him keeps at least ALERT_LIGHT.
const DARK_SIGHT := 0.3
const CLOSE_SIGHT := 3.0
const DARK_RATE := 0.3
const ALERT_LIGHT := 0.6
## What of the boy an enemy can see: his head and both shoulders, a
## teenager's - SHOULDER_DROP below the eyes, SHOULDER_HALF to each side
## across the line of sight (docs/ARCHITECTURE.md, "Враги"). One clear line
## is enough: a post on the line to his head, narrower than 0.3 m x its share
## of the way from the enemy, hides the head, not the boy (each shoulder line
## passes it 0.15 m x that share off).
const SHOULDER_DROP := 0.22
const SHOULDER_HALF := 0.15

@export var kind: Kind = Kind.SOLDIER
## Red armband (stencil 1). Set per character according to the historical brief.
@export var has_armband: bool = false
## Node whose Marker3D children are the patrol points, in order.
@export var patrol_route: Node3D
@export var walk_speed: float = 1.3
@export var chase_speed: float = 3.4
@export var view_distance: float = 16.0
@export var view_angle_deg: float = 80.0
@export var eye_height: float = 1.6
@export var hearing: float = 1.0
@export var wait_at_point: float = 2.0
@export var catch_distance: float = 1.1
@export var gravity: float = 9.8
## Chest torch (a SpotLight3D built in code). Neutral white light only:
## the colour rule allows no coloured light in the world.
@export var has_torch: bool = false
@export var torch_on: bool = false:
	set(value):
		torch_on = value
		if torch != null:
			torch.visible = value and has_torch

var state: State = State.PATROL
var suspicion: float = 0.0
var last_known: Vector3
## Per-enemy distortion multiplier (1 = monster, 0 = ordinary person).
var grotesque: float = 1.0

var _route_idx := 0
var _wait := 0.0
## The navigation path being walked and the first point on it not yet passed
## (_next_path_point).
var _path := PackedVector3Array()
var _path_i := 0
var _search_time := 0.0
## Heading the search looks around (towards where the boy was lost).
var _search_yaw := 0.0
var _caught := false
var _visuals: Array[GeometryInstance3D] = []
## Hiding spot a dog pointed at; checked on arrival.
var _target_spot: HideSpot = null
var _speech_timer := randf_range(6.0, 20.0)
## Story control / sentries: while true and no scripted route, the enemy
## stands at its post (where it was placed) in PATROL and returns there
## after a search.
@export var hold_position := false
var _post: Transform3D
var _script_route: Array[Vector3] = []
var torch: SpotLight3D
## The torch beam on the boy he holds, a metre off, throws light back up at
## him: a faint white glow from below on his own face (_light_from_captive).
var captive_spill: OmniLight3D = null
const SPILL_ENERGY := 0.9
## Walk: limbs swing, footfalls are heard (src/ai/gait.gd).
var gait: Gait
## A figure in a staged scene (the interrogation): no AI, no hearing; only
## the visual parameters are fed every frame.
@export var passive := false
## A house search (the invasion): obvious hiding places (HideSpot.search_check)
## are checked when passed, even while walking a scripted route.
@export var searches_hiding_spots := false:
	set(value):
		if value and not searches_hiding_spots:
			_forget_checked()
		searches_hiding_spots = value
## Obvious hiding place being checked now, seconds left; places already
## checked (or walked to) in this search.
var _inspecting: HideSpot = null
var _inspect_left := 0.0
## Walking up to the place before the check starts (gives up after a while
## if the way is blocked).
var _approaching := false
var _approach_left := 0.0
var _checked: Array[HideSpot] = []
var _tried: Array[HideSpot] = []

@onready var visual: Node3D = $Visual
@onready var nav_agent: NavigationAgent3D = get_node_or_null("NavAgent")


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 1 << 2
	collision_mask = 1 | Stealth.SEE_THROUGH_LAYER
	last_known = global_position
	_post = global_transform
	Stealth.noise_emitted.connect(_on_noise)
	_apply_kind()
	if has_torch:
		_build_torch()
	gait = Gait.new()
	gait.name = "Gait"
	add_child(gait)
	gait.setup(self, visual, _gait_body(), walk_speed, chase_speed)
	for n in visual.find_children("*", "GeometryInstance3D", true, false):
		_visuals.append(n as GeometryInstance3D)
	_update_visual_params()


func _gait_body() -> Gait.Body:
	return Gait.Body.HUMAN


func _apply_kind() -> void:
	visual.get_node("Helmet").visible = kind != Kind.POLIZEI and kind != Kind.OFFICER
	visual.get_node("Cap").visible = kind == Kind.POLIZEI or kind == Kind.OFFICER
	visual.get_node("PlasterMask").visible = kind == Kind.POLIZEI
	visual.get_node("Gorget").visible = kind == Kind.FELDGENDARM
	visual.get_node("Armband").visible = has_armband


func _build_torch() -> void:
	torch = SpotLight3D.new()
	torch.name = "Torch"
	# On the chest, slightly to the right, beam forward and down.
	torch.position = Vector3(0.09, 1.3, -0.2)
	torch.rotation_degrees.x = TORCH_PITCH
	torch.light_color = Color(1, 1, 1)
	torch.light_energy = 5.0
	torch.spot_range = 14.0
	torch.spot_angle = 24.0
	torch.spot_angle_attenuation = 1.6
	torch.shadow_enabled = true
	visual.add_child(torch)
	var lens := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.07, 0.05, 0.02)
	lens.mesh = box
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.95, 0.95, 0.95)
	lens.material_override = m
	torch.add_child(lens)
	torch.visible = torch_on


## How strongly the torch lights `point` (0..1): inside the beam, in range,
## not behind a wall or a closed door.
func torch_light_at(point: Vector3) -> float:
	if torch == null or not torch_on or not is_visible_in_tree():
		return 0.0
	var from := torch.global_position
	var to := point - from
	var dist := to.length()
	if dist > torch.spot_range or dist < 0.01:
		return 0.0
	var axis := -torch.global_transform.basis.z
	var angle := rad_to_deg(axis.angle_to(to / dist))
	if angle > torch.spot_angle:
		return 0.0
	var query := PhysicsRayQueryParameters3D.create(from, point, 1 | IzbaDoor.DOOR_LAYER)
	query.exclude = [get_rid()]
	if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return 0.0
	return (1.0 - dist / torch.spot_range) * sqrt(1.0 - angle / torch.spot_angle)


## Another enemy (a dog) raises the alarm: come and look at `pos`.
## If `spot` is given, the hiding spot there is searched on arrival.
func alert_to(pos: Vector3, amount: float, spot: HideSpot = null) -> void:
	if _caught:
		return
	suspicion = maxf(suspicion, amount)
	last_known = pos
	if spot != null:
		_target_spot = spot
	if state == State.PATROL or state == State.SEARCH:
		_set_state(State.SUSPICIOUS)


func _check_target_spot() -> void:
	if _target_spot == null:
		return
	if global_position.distance_to(_target_spot.global_position) < 2.2 			and _target_spot.occupant != null:
		_catch()
	_target_spot = null


## Story control: walk these points in order (only while in PATROL; an
## alarm interrupts the route, it resumes after the search).
func script_goto(points: Array[Vector3]) -> void:
	_script_route = points.duplicate()
	_wait = 0.0


func has_script_route() -> bool:
	return not _script_route.is_empty()


## Untranslated German speech while patrolling (silent until recorded).
func _speak(delta: float) -> void:
	_speech_timer -= delta
	if _speech_timer <= 0.0:
		_speech_timer = randf_range(12.0, 25.0)
		if state == State.PATROL:
			Sfx.play_at("de_speech", global_position + Vector3.UP * 1.6)


## Called once when the enemy becomes alerted.
func _on_alerted() -> void:
	Sfx.play_at("de_shout", global_position + Vector3.UP * 1.6)


## Act III "prozrenie": the monstrous shell falls away from this person.
## Back to calm patrol: after a staged scene (Act III: the boy has been
## released, the one who caught him forgets about him).
func stand_down() -> void:
	_caught = false
	if captive_spill != null:
		captive_spill.queue_free()
		captive_spill = null
	suspicion = 0.0
	_search_time = 0.0
	_target_spot = null
	_end_inspection()
	_forget_checked()
	_set_state(State.PATROL)


func reveal(duration: float = 2.5) -> void:
	create_tween().tween_property(self, "grotesque", 0.0, duration)


func _physics_process(delta: float) -> void:
	_update_visual_params()
	if _caught:
		_face_captive(delta)
	if _caught or passive:
		return
	_speak(delta)
	var p := Stealth.player as Player
	var sees := p != null and can_see(p)
	# Under cover (Act III, a pass in the pocket) a boy on the street draws
	# no attention; a chase already under way goes on.
	var exposed := Stealth.exposed() or state == State.ALERT
	var noticed := sees and (exposed or Stealth.staring)
	if noticed:
		var dist := global_position.distance_to(p.global_position)
		var rate := lerpf(1.8, 0.35, clampf(dist / view_distance, 0.0, 1.0))
		if p.is_crouching:
			rate *= 0.45
		rate *= lerpf(DARK_RATE, 1.0, seen_light())
		if not exposed:
			rate *= Stealth.STARING_RATE
		suspicion = minf(suspicion + rate * delta, 1.0)
		last_known = p.global_position
	elif state == State.PATROL:
		suspicion = maxf(suspicion - 0.12 * delta, 0.0)
	_feed_panic(p, sees, delta)
	if _inspect(noticed, delta):
		return
	_relax_torch(delta)
	_update_state(p, sees, delta)


func _feed_panic(p: Player, sees: bool, delta: float) -> void:
	if p == null:
		return
	if sees:
		PanicSystem.apply_continuous(0.3 if state != State.ALERT else 0.6, delta)
	elif global_position.distance_to(p.global_position) < 5.0:
		PanicSystem.apply_continuous(0.12, delta)


func _update_state(p: Player, sees: bool, delta: float) -> void:
	if suspicion >= 1.0 and state != State.ALERT:
		_set_state(State.ALERT)
		PanicSystem.spike(0.3)
		_on_alerted()
	elif suspicion >= SUSPICIOUS_AT and state == State.PATROL:
		_set_state(State.SUSPICIOUS)

	match state:
		State.PATROL:
			if not _script_route.is_empty():
				if _move_towards(_script_route[0], walk_speed, delta):
					_script_route.pop_front()
					if _script_route.is_empty():
						_post = global_transform  # hold where the script left him
						scripted_finished.emit()
			elif hold_position:
				_hold_post(delta)
			else:
				_patrol(delta)
		State.SUSPICIOUS:
			if _move_towards(last_known, walk_speed, delta):
				if _go_to_obvious_spot():
					return
				_check_target_spot()
				_begin_search(6.0)
		State.SEARCH:
			_search_time -= delta
			var want := _search_yaw + 0.8 * sin(_search_time * 1.5)
			rotation.y = lerp_angle(rotation.y, want, minf(1.0, 4.0 * delta))
			_apply_gravity_only(delta)
			if _search_time <= 0.0:
				suspicion = minf(suspicion, 0.2)
				_set_state(State.PATROL)
		State.ALERT:
			if sees:
				_move_towards(p.global_position, chase_speed, delta)
				var d := global_position.distance_to(p.global_position)
				# Grab across a table or a bench when the map lets him no closer.
				var blocked := get_real_velocity().length() < 0.2 and d < catch_distance * 1.6
				if d < catch_distance or blocked:
					_catch()
			elif _move_towards(last_known, chase_speed * 0.8, delta):
				if _go_to_obvious_spot():
					return
				_check_target_spot()
				suspicion = 0.8
				_begin_search(8.0)


## Arrived where the boy was lost: look around, centred on that place when
## a table or a wall stopped him short of it, else on where he is facing.
func _begin_search(time: float) -> void:
	_search_time = time
	var to := last_known - global_position
	to.y = 0.0
	_search_yaw = atan2(-to.x, -to.z) if to.length() > 0.5 else rotation.y
	_set_state(State.SEARCH)


func _patrol(delta: float) -> void:
	if patrol_route == null or patrol_route.get_child_count() == 0:
		_apply_gravity_only(delta)
		return
	if _wait > 0.0:
		_wait -= delta
		_apply_gravity_only(delta)
		return
	var point := patrol_route.get_child(_route_idx) as Node3D
	if _move_towards(point.global_position, walk_speed, delta):
		_route_idx = (_route_idx + 1) % patrol_route.get_child_count()
		_wait = wait_at_point


## Returns true when the target (or the closest reachable point) is reached.
## Uses the NavigationAgent3D when a navigation map is baked, otherwise
## walks straight.
func _hold_post(delta: float) -> void:
	var to := _post.origin - global_position
	to.y = 0.0
	if to.length() > 0.5:
		_move_towards(_post.origin, walk_speed, delta)
		return
	_apply_gravity_only(delta)
	rotation.y = lerp_angle(rotation.y, _post.basis.get_euler().y, 3.0 * delta)


func _move_towards(target: Vector3, speed: float, delta: float) -> bool:
	var to := target - global_position
	to.y = 0.0
	if to.length() < 0.35:
		velocity.x = 0.0
		velocity.z = 0.0
		_apply_gravity_only(delta)
		return true
	var step_target := target
	if _nav_ready():
		if nav_agent.target_position.distance_to(target) > 0.3:
			nav_agent.target_position = target
		var final := nav_agent.get_final_position()
		if Vector2(final.x - global_position.x, final.z - global_position.z).length() < 0.4 \
				and nav_agent.is_target_reachable() == false:
			_apply_gravity_only(delta)
			return true  # as close as the map allows
		step_target = _next_path_point()
	var step := step_target - global_position
	step.y = 0.0
	if step.length() < 0.01:
		step = to
	var dir := step.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if not is_on_floor():
		velocity.y -= gravity * delta
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 6.0 * delta)
	move_and_slide()
	return false


## Next point of the navigation path, judged on the ground. The navmesh lies
## 0.2-0.4 m above the feet (cell height 0.1, no detail mesh), while the agent
## measures its progress in 3D against path_desired_distance: a point raised
## 0.4 m is never reached, and the enemy paces on the spot (the Act II village
## policeman at P1). Here a point counts as passed once he stands within that
## distance of it on the ground, and progress only goes forward along a path.
func _next_path_point() -> Vector3:
	var next := nav_agent.get_next_path_position()  # also refreshes the path
	var path := nav_agent.get_current_navigation_path()
	if path.is_empty():
		return next
	if path != _path:
		_path = path
		_path_i = 0
	_path_i = clampi(maxi(_path_i, nav_agent.get_current_navigation_path_index()), 0, path.size() - 1)
	while _path_i < path.size() - 1 and Vector2(path[_path_i].x - global_position.x,
			path[_path_i].z - global_position.z).length() < nav_agent.path_desired_distance:
		_path_i += 1
	return path[_path_i]


func _nav_ready() -> bool:
	if nav_agent == null:
		return false
	var map := nav_agent.get_navigation_map()
	# A map with no navmesh in it answers every query with the world origin:
	# an enemy passing near (0, 0, 0) would take every target as reached.
	return map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0 \
			and not NavigationServer3D.map_get_regions(map).is_empty() \
			and _level_nav_baked()


func _level_nav_baked() -> bool:
	for r in get_tree().get_nodes_in_group("runtime_nav"):
		return (r as RuntimeNavRegion).is_baked
	return true  # level baked in the editor


func _apply_gravity_only(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()


## How lit the boy looks to this enemy (0..1).
func seen_light() -> float:
	var k := Stealth.player_light
	return maxf(k, ALERT_LIGHT) if state == State.ALERT else k


## How far this enemy can see the boy now: less in the dark.
func sight_distance() -> float:
	return maxf(view_distance * lerpf(DARK_SIGHT, 1.0, seen_light()), minf(CLOSE_SIGHT, view_distance))


func can_see(p: Player) -> bool:
	if p.is_hidden:
		return false
	var eye := global_position + Vector3.UP * eye_height
	var target := p.head.global_position
	var to := target - eye
	if to.length() > sight_distance():
		return false
	var forward := -global_transform.basis.z
	if rad_to_deg(forward.angle_to(to.normalized())) > view_angle_deg * 0.5:
		return false
	# World and closed doors block the view - all of him, or he is seen.
	var space := get_world_3d().direct_space_state
	for point in p.sight_points_from(eye):
		var query := PhysicsRayQueryParameters3D.create(eye, point, 1 | IzbaDoor.DOOR_LAYER)
		query.exclude = [get_rid()]
		if space.intersect_ray(query).is_empty():
			return true
	return false


## The points of a boy with his head at `head` that an eye at `eye` looks
## for: the head, then the shoulders across the line between them. When he
## leans out (`lean`, Player.lean_offset) the shoulders go half as far.
static func sight_points(eye: Vector3, head: Vector3, lean := Vector3.ZERO) -> PackedVector3Array:
	var across := Vector3(head.z - eye.z, 0.0, eye.x - head.x)
	if across.length() < 0.001:
		across = Vector3.RIGHT  # straight above or below: any side will do
	across = across.normalized() * SHOULDER_HALF
	var shoulders := head - lean * 0.5 - Vector3.UP * SHOULDER_DROP
	return PackedVector3Array([head, shoulders + across, shoulders - across])


func _on_noise(noise_pos: Vector3, loudness: float, source: Node) -> void:
	if _caught or passive or source == self:
		return
	if source is Player and not Stealth.exposed():
		return
	var dist := global_position.distance_to(noise_pos)
	if loudness <= 0.0 or dist > loudness * Stealth.HEARING_RANGE * hearing:
		return
	# A log wall or a shut door between: heard as if half as loud, a vague
	# sound - nothing to walk over for, and no grabbing through the wall.
	var walled := Stealth.sound_walled(self, eye_height, noise_pos, [get_rid()])
	if walled:
		loudness *= Stealth.WALL_HEARING
	var radius := loudness * Stealth.HEARING_RANGE * hearing
	if radius <= 0.0 or dist > radius:
		return
	suspicion = minf(suspicion + (1.0 - dist / radius) * loudness * 0.9, 1.0)
	last_known = noise_pos
	# A door, a lid, hay heard plainly (no wall between): he comes to look.
	if source is Player and Stealth.noise_is_action and state != State.ALERT and not walled:
		suspicion = maxf(suspicion, SUSPICIOUS_AT)
		if state == State.PATROL or state == State.SEARCH:
			_set_state(State.SUSPICIOUS)
	if source is Player:
		_forget_checked()  # a new sound: places already checked are suspect again
	if (source is Player and (source as Player).is_hidden and dist < 2.5 and loudness >= 0.3
			and not walled and _can_reach(noise_pos)):
		_catch()


## A boy hidden in a room (a board floor: the izba, the office) is grabbed
## only from inside that room: a sob heard through a window or from the
## threshold is no hand through it - he has to come in.
func _can_reach(pos: Vector3) -> bool:
	var room := Stealth.room_at(pos)
	return room == null or room == Stealth.room_at(global_position)


func _catch() -> void:
	if _caught:
		return
	_caught = true
	_light_from_captive()
	_set_state(State.ALERT)
	PanicSystem.spike(1.0)
	player_caught.emit(self)


## Only with the torch on: without it there is no light to throw back.
func _light_from_captive() -> void:
	if torch == null or not torch_on or captive_spill != null:
		return
	captive_spill = OmniLight3D.new()
	captive_spill.name = "CaptiveSpill"
	captive_spill.light_color = Color(1, 1, 1)
	captive_spill.omni_range = 3.8
	captive_spill.omni_attenuation = 1.0
	captive_spill.light_energy = 0.0
	captive_spill.shadow_enabled = false
	captive_spill.position = Vector3(0.0, 1.1, -0.55)  # the boy's chest in the beam
	add_child(captive_spill)
	create_tween().tween_property(captive_spill, "light_energy", SPILL_ENERGY, 0.25)


## Holding the boy he has caught: turned to him, not walking on.
func _face_captive(delta: float) -> void:
	var p := Stealth.player as Node3D
	if p == null or not p.is_inside_tree():
		return
	var to := p.global_position - global_position
	var flat := Vector2(to.x, to.z).length()
	if flat < 0.05 or flat > 4.0:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), minf(1.0, 8.0 * delta))


func _set_state(s: State) -> void:
	if s == State.PATROL and state != State.PATROL and not searches_hiding_spots:
		_forget_checked()
	if s != state:
		state = s
		state_changed.emit(s)


# --- checking hiding places (HideSpot.search_check) -----------------------------

## Whether hiding places within reach get checked: a house search, or any
## state but a calm patrol.
func is_searching() -> bool:
	return searches_hiding_spots or state != State.PATROL


## Dogs sniff; they do not look behind stoves or open wardrobes.
func checks_hiding_spots() -> bool:
	return true


func is_inspecting() -> bool:
	return _inspecting != null


## Searching: an obvious hiding place within reach is checked: walk up to
## its stand point, face it, the torch on it (and the door open). Returns
## true while this holds the enemy. Seeing the boy in the open ends it: the
## chase comes first.
func _inspect(noticed: bool, delta: float) -> bool:
	if _inspecting != null and (noticed or not is_instance_valid(_inspecting)):
		_end_inspection()
		return false
	if _inspecting == null:
		if noticed or not checks_hiding_spots() or not is_searching():
			return false
		_inspecting = _spot_in_reach()
		if _inspecting == null:
			return false
		_approaching = true
		_approach_left = 3.0
	var spot := _inspecting
	if _approaching:
		_approach_left -= delta
		if _move_towards(spot.stand_point(), walk_speed, delta) or _approach_left <= 0.0:
			_approaching = false
			_inspect_left = spot.check_time
			spot.begin_check(self)
		return true
	_inspect_left -= delta
	velocity.x = 0.0
	velocity.z = 0.0
	_apply_gravity_only(delta)
	var point := spot.check_point()
	var to := point - global_position
	if Vector2(to.x, to.z).length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), minf(1.0, 6.0 * delta))
	_aim_torch(spot.global_position + Vector3.UP * 0.3, delta)  # inside, where the boy is
	if spot.search_check == HideSpot.SearchCheck.OPEN and spot.occupant != null \
			and spot.check_time - _inspect_left >= spot.open_delay:
		_end_inspection()
		_catch()  # the door is open: the boy is standing in front of him
		return true
	if _inspect_left <= 0.0:
		_end_inspection()
	return true


func _end_inspection() -> void:
	if _inspecting != null and is_instance_valid(_inspecting):
		if not _checked.has(_inspecting):
			_checked.append(_inspecting)
		if not _approaching:
			_inspecting.end_check(self)
	_inspecting = null
	_approaching = false


func _forget_checked() -> void:
	_checked.clear()
	_tried.clear()


## The nearest unchecked obvious hiding place whose opening is within reach
## and in view (not through a wall or the back of a wardrobe).
func _spot_in_reach() -> HideSpot:
	var best: HideSpot = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("hide_spots"):
		var spot := n as HideSpot
		if spot.search_check == HideSpot.SearchCheck.NONE or _checked.has(spot):
			continue
		var cp := spot.check_point()
		var d := Vector2(cp.x - global_position.x, cp.z - global_position.z).length()
		if d < spot.check_radius and d < best_d and _can_look_at(cp):
			best = spot
			best_d = d
	return best


func _can_look_at(point: Vector3) -> bool:
	var eye := global_position + Vector3.UP * 1.2
	var query := PhysicsRayQueryParameters3D.create(eye, point, 1 | IzbaDoor.DOOR_LAYER)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## The boy was lost at last_known: if an obvious hiding place is close by,
## walk up to it first (once per place); _inspect does the rest.
func _go_to_obvious_spot() -> bool:
	if not checks_hiding_spots():
		return false
	for n in get_tree().get_nodes_in_group("hide_spots"):
		var spot := n as HideSpot
		if spot.search_check == HideSpot.SearchCheck.NONE or _checked.has(spot) \
				or _tried.has(spot):
			continue
		var cp := spot.check_point()
		if Vector2(cp.x - last_known.x, cp.z - last_known.z).length() < REDIRECT_RADIUS:
			_tried.append(spot)
			last_known = Vector3(cp.x, global_position.y, cp.z)
			return true
	return false


## Chest torch pitched at the place being checked.
func _aim_torch(point: Vector3, delta: float) -> void:
	if torch == null:
		return
	var to := point - torch.global_position
	var pitch := clampf(atan2(to.y, Vector2(to.x, to.z).length()), deg_to_rad(-70.0), deg_to_rad(10.0))
	torch.rotation.x = lerp_angle(torch.rotation.x, pitch, minf(1.0, 5.0 * delta))


func _relax_torch(delta: float) -> void:
	if torch != null:
		torch.rotation.x = lerp_angle(torch.rotation.x, deg_to_rad(TORCH_PITCH), minf(1.0, 3.0 * delta))


## Where a point of this body is drawn: the height stretch of the
## distortion (enemy_distort.gdshaderinc, dix_distort_world; the twitch and
## the facets are left out). The caught boy looks at the face he sees.
func drawn_point(p: Vector3) -> Vector3:
	var d := clampf(Perception.distortion * grotesque, 0.0, 1.0)
	var rel := p - global_position
	var h := maxf(rel.y, 0.0)
	var head := smoothstep(1.35, 1.6, h)
	rel.y = h * (1.0 + 0.55 * d) + head * (h - 1.35) * 1.1 * d
	return global_position + rel


func _update_visual_params() -> void:
	for gi in _visuals:
		gi.set_instance_shader_parameter("feet_origin", global_position)
		gi.set_instance_shader_parameter("grotesque", grotesque)
