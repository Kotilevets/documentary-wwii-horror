class_name InvasionSequence
extends Node
## Act I opening "Invasion" (CLAUDE.md, 3): a quiet evening in the izba in
## sepia -> a flare, the picture turns hard B&W -> a soldier with a dog comes
## up the road to the door, knocks and shouts, the player has a few seconds
## to hide -> the door is kicked in, the izba is searched -> they leave - and
## linger behind the corner, and come back for one more look -> the village
## patrols start, the player makes for the forest.
## The sequence only gives orders (routes, door, sounds); catching and
## hearing are the ordinary Enemy/Dog systems, so hiding works as everywhere.
## The search is a house search (Enemy.searches_hiding_spots): the soldier
## looks behind the stove on his way; the cellar under the floor he walks
## over (docs/ARCHITECTURE.md, "Укрытия и обыск").
## The false departure (LINGER, RETURN): the steps stop behind the corner,
## the dog sniffs by the wall, the torch lies on the ground before the door;
## who comes out too soon is caught (docs/ARCHITECTURE.md, "Ложный уход").

signal beat_changed(beat: Beat)

enum Beat { PROLOGUE, INVASION, KNOCK, SEARCH, LEAVE, LINGER, RETURN, ESCAPE }
## Where the soldier is in RETURN: walking in, looking, walking away.
enum Leg { IN, LOOK, OUT }

@export var prologue_time: float = 25.0
## Seconds between the knock and the kick: the time to hide.
@export var warning_time: float = 12.0
## Seconds the soldier stands in the izba after walking the search points.
@export var search_time: float = 8.0
## Seconds he stands behind the corner after leaving, facing the yard before
## the door, before he comes back for one more look.
@export var linger_time: float = 14.0
## Seconds he stands at look_back_point, in the middle of the room, when he
## comes back: one whole sweep of the torch, LOOK_SWING to each side.
@export var look_back_time: float = 5.0
## Seconds between the dog's sniffs while he lingers.
@export var sniff_every: float = 3.2

## How far his torch swings to each side of where he faces: behind the
## corner (the yard before the door), and looking back into the room - his
## view is 80 degrees, so the room's far corners need the swing. Behind the
## corner it swings at SWING_RATE; the look is one whole swing, there and
## back, however long look_back_time is.
const LINGER_SWING := deg_to_rad(20.0)
const LOOK_SWING := deg_to_rad(60.0)
const SWING_RATE := 1.3
## How near the dog's place on the threshold he must be, on his way out after
## the look back in, to take the dog to his heel again.
const THRESHOLD_REACH := 1.2

@export var soldier: Enemy
@export var dog: Dog
@export var door: IzbaDoor
@export var flare: SignalFlare
## Sepia zone inside the izba, active only in the prologue.
@export var prologue_zone: SafeZone
## Where the squad waits during the prologue (out of sight, down the road).
@export var squad_start: Marker3D
## The squad walks these Marker3D children to the door, in order.
@export var approach_route: Node3D
## Points inside the izba the soldier walks during the search.
@export var search_route: Node3D
## Where the squad goes after the search before the patrol resumes.
@export var leave_point: Marker3D
## Where the dog is left while the soldier searches the izba: the threshold,
## outside (its -Z faces the door). Without it the dog follows him in.
@export var dog_wait: Marker3D
## Where he stands when he comes back for one more look: in the middle of
## the room, past the kicked-in leaf (from the threshold the leaf hides the
## north-west of the room and the cellar hatch); its -Z is the middle of his
## swing. Without it, the first search point, facing the way he came in.
@export var look_back_point: Marker3D

var beat: Beat = Beat.PROLOGUE
var _timer := 0.0
var _others: Array[Enemy] = []
var _dog_handler: Enemy = null
var _leg := Leg.IN
var _sniff_in := 0.0
## The yaw he faces while he stands (LINGER, the look), and the time of the
## swing round it.
var _face_yaw := 0.0
var _swing_t := 0.0


func _ready() -> void:
	soldier.scripted_finished.connect(_on_route_finished)
	door.opened.connect(_on_door_opened)


## Called by the level once everything is in the tree.
func start() -> void:
	flare.autofire = false
	door.enemies_can_open = false
	prologue_zone.set_active(true)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != soldier and e != dog:
			_others.append(e as Enemy)
			_set_present(e as Enemy, false)
	soldier.global_position = squad_start.global_position
	dog.global_position = squad_start.global_position + Vector3.RIGHT
	soldier.hold_position = true
	soldier._post = soldier.global_transform
	_set_present(soldier, false)
	_set_present(dog, false)
	_set_beat(Beat.PROLOGUE, prologue_time)


## The state right after the invasion: door broken in, patrols walking.
func skip() -> void:
	flare.autofire = true
	door.enemies_can_open = true
	door.start_open = true
	door.is_open = true
	door.rotation_degrees.y = door.open_angle
	prologue_zone.set_active(false)
	soldier.hold_position = false
	soldier.torch_on = true
	beat = Beat.ESCAPE
	set_process(false)


func _process(delta: float) -> void:
	match beat:
		Beat.PROLOGUE, Beat.KNOCK:
			_timer -= delta
			if _timer <= 0.0:
				_next_from_timer()
		Beat.SEARCH:
			if soldier.has_script_route():
				return
			_timer -= delta
			soldier.rotate_y(delta * 0.9 * sin(_timer * 1.3))
			if _timer <= 0.0:
				_leave()
		Beat.LINGER:
			_sniff_in -= delta
			if _sniff_in <= 0.0:
				_sniff_in = sniff_every
				Sfx.play_at("dog_sniff", dog.global_position + Vector3.UP * 0.45)
			_swing(delta, LINGER_SWING, SWING_RATE)
			_timer -= delta
			if _timer <= 0.0:
				_return()
		Beat.RETURN:
			if _leg == Leg.OUT:
				_take_dog_on_threshold()
			if _leg != Leg.LOOK:
				return
			_swing(delta, LOOK_SWING, TAU / maxf(look_back_time, 0.1))
			_timer -= delta
			if _timer <= 0.0:
				_leg = Leg.OUT
				var pts := _away()
				var inside := _points(search_route)
				if look_back_point != null and not inside.is_empty():
					pts.push_front(inside[0])  # out over the threshold, not through the leaf
				soldier.script_goto(pts)


## While he stands his post turns from side to side round `_face_yaw`, and
## he turns after it (Enemy._hold_post): the torch sweeps. A chase or a
## search of his own leaves the post where it is till he is back.
func _swing(delta: float, amplitude: float, rate: float) -> void:
	_swing_t += delta
	var yaw := _face_yaw + amplitude * sin(_swing_t * rate)
	soldier._post = Transform3D(Basis(Vector3.UP, yaw), soldier._post.origin)


## The yaw that faces `to` (a node looks down its -Z).
static func _yaw_to(to: Vector3) -> float:
	return atan2(-to.x, -to.z)


func _next_from_timer() -> void:
	if beat == Beat.PROLOGUE:
		_invade()
	elif beat == Beat.KNOCK:
		_enter()


func _invade() -> void:
	prologue_zone.set_active(false)
	flare.launch()
	flare.autofire = true
	_set_present(soldier, true)
	_set_present(dog, true)
	soldier.torch_on = true
	for e in _others:
		_set_present(e, true)
	Sfx.play_at("dog_bark", squad_start.global_position)
	Sfx.play_at("engine_far", squad_start.global_position)
	soldier.script_goto(_points(approach_route))
	_set_beat(Beat.INVASION, 0.0)


func _knock() -> void:
	Sfx.play_at("door_knock", door.sound_point())
	# A demand at the door, not "I see you": he has not been seen, so no
	# alarm to start at either (docs/ARCHITECTURE.md, "Заметили").
	Sfx.play_at("de_door", soldier.global_position + Vector3.UP * 1.6)
	PanicSystem.spike(0.25)
	_set_beat(Beat.KNOCK, warning_time)


func _enter() -> void:
	door.enemies_can_open = true
	door.open(true)
	_park_dog()
	soldier.searches_hiding_spots = true
	soldier.script_goto(_points(search_route))
	_set_beat(Beat.SEARCH, search_time)


func _leave() -> void:
	soldier.searches_hiding_spots = false
	_unpark_dog()
	soldier.script_goto(_away())
	_set_beat(Beat.LEAVE, 0.0)


## The dog is left on the threshold, outside, while the soldier is in the
## izba (the search, the look back in): at his heel it would smell the boy
## behind the stove.
func _park_dog() -> void:
	if dog_wait != null:
		_dog_handler = dog.handler
		dog.handler = null
		dog.hold_position = true
		dog._post = dog_wait.global_transform


## At his heel again.
func _unpark_dog() -> void:
	if _dog_handler != null:
		dog.handler = _dog_handler
		dog.hold_position = false
		_dog_handler = null


## Out of the izba again after the look back in, he takes the dog from the
## threshold: called to his heel from the middle of the room, it would come
## in after him and smell the boy behind the stove.
func _take_dog_on_threshold() -> void:
	if _dog_handler == null or dog_wait == null:
		return
	var to := dog_wait.global_position - soldier.global_position
	if Vector2(to.x, to.z).length() < THRESHOLD_REACH:
		_unpark_dog()


## Out through the door (the last approach point stands in front of it),
## then round the corner to the leave point.
func _away() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var approach := _points(approach_route)
	if not approach.is_empty():
		pts.append(approach[approach.size() - 1])
	pts.append(leave_point.global_position)
	return pts


## Behind the corner, facing the yard before the door; the dog sniffs.
func _linger() -> void:
	_face_yaw = soldier.rotation.y
	var approach := _points(approach_route)
	if not approach.is_empty():
		var to := approach[approach.size() - 1] - soldier.global_position
		to.y = 0.0
		if to.length() > 0.01:
			_face_yaw = _yaw_to(to)
	_swing_t = 0.0
	_sniff_in = minf(1.0, sniff_every * 0.3)
	_set_beat(Beat.LINGER, linger_time)


## Back to the door, over the threshold (the first search point) and to the
## look-back point, for one more look round the room; the dog is left on
## the threshold again.
func _return() -> void:
	var pts: Array[Vector3] = []
	var approach := _points(approach_route)
	if not approach.is_empty():
		pts.append(approach[approach.size() - 1])
	var inside := _points(search_route)
	if not inside.is_empty():
		pts.append(inside[0])
	if look_back_point != null:
		pts.append(look_back_point.global_position)
	_park_dog()
	_leg = Leg.IN
	soldier.script_goto(pts)
	_set_beat(Beat.RETURN, look_back_time)


func _on_route_finished() -> void:
	match beat:
		Beat.INVASION:
			if door.is_open:
				_enter()  # the player has opened the door: no knocking
			else:
				_knock()
		Beat.LEAVE:
			_linger()
		Beat.RETURN:
			if _leg == Leg.IN:
				_leg = Leg.LOOK
				_face_yaw = _look_yaw()
				_swing_t = 0.0
			elif _leg == Leg.OUT:
				_unpark_dog()  # if a chase took him past the threshold
				soldier.hold_position = false
				_set_beat(Beat.ESCAPE, 0.0)


## The middle of his swing when he looks back in: the look-back point's -Z,
## or (without one) the way he came in over the threshold.
func _look_yaw() -> float:
	if look_back_point != null:
		var f := -look_back_point.global_basis.z
		return _yaw_to(Vector3(f.x, 0.0, f.z))
	var approach := _points(approach_route)
	var inside := _points(search_route)
	if not approach.is_empty() and not inside.is_empty():
		var to := inside[0] - approach[approach.size() - 1]
		to.y = 0.0
		if to.length() > 0.01:
			return _yaw_to(to)
	return soldier.rotation.y


## The player opening the door ends the prologue at once.
func _on_door_opened() -> void:
	if beat == Beat.PROLOGUE:
		_invade()


func _set_beat(b: Beat, time: float) -> void:
	beat = b
	_timer = time
	beat_changed.emit(b)


func _set_present(e: Enemy, present: bool) -> void:
	e.visible = present
	e.process_mode = Node.PROCESS_MODE_INHERIT if present else Node.PROCESS_MODE_DISABLED
	if present:
		e.suspicion = 0.0
		e.last_known = e.global_position


static func _points(route: Node3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for c in route.get_children():
		out.append((c as Node3D).global_position)
	return out
