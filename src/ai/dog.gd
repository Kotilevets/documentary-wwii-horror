class_name Dog
extends Enemy
## German shepherd with a handler (CLAUDE.md, 3: "лай овчарок").
## Follows the handler; hears better than people and smells the player,
## also inside a hiding spot (less through a cellar than through hay).
## When it finds the player it barks: the bark scares the player and calls
## every soldier in range to the spot, and a soldier who reaches an occupied
## hiding spot pulls the player out. A dog that reaches a visible player bites
## (caught), like a soldier.
## The dog also picks up the player's trail (Stealth.scent_trail): it follows
## it from older steps to newer ones, barking now and then, and the handler
## follows the barking. The trail goes cold after Stealth.SCENT_LIFETIME.

@export var handler: Enemy
@export var smell_radius: float = 4.5
@export var bark_interval: float = 1.3
@export var alarm_radius: float = 25.0
@export var heel_distance: float = 1.6
## How close to a trail point the nose has to pass.
@export var trail_pickup_radius: float = 1.6
## A drop of blood (Wound) is picked up from this far: a bleeding boy is
## tracked from well off his path (docs/ARCHITECTURE.md, "Рана и бинт").
@export var blood_pickup_radius: float = 10.0
## Seconds between barks while following a trail.
@export var trail_bark_interval: float = 4.0

var barks: int = 0
var _bark_cooldown := 0.0
var _scent_spot: HideSpot = null
## Number of the trail point being followed; < 0 when not tracking.
var trail_seq: int = -1
## The last point of the last trail followed to its end: it and anything
## older are not picked up again (else at the end of a trail the dog would
## pick its last point up every other frame, barking, till it went cold).
var _trail_end_seq := -1
## Where the point being followed lies.
var _trail_pos := Vector3.ZERO
## Two points of a trail farther apart than this: the scent breaks there.
## (Blood outlives the steps between drops, so the next live point after an
## old drop may be a step of a walk much later and far off.)
const MAX_TRAIL_GAP := 3.0
var _trail_bark := 0.0


func _ready() -> void:
	super()
	# A shut door stops a dog: it cannot open one (IzbaDoor opens for men
	# only), so it waits at the leaf until a man opens or kicks it in
	# (docs/ARCHITECTURE.md, "Дверь избы").
	collision_mask |= IzbaDoor.DOOR_LAYER


func _apply_kind() -> void:
	pass  # the dog has its own model


func _speak(_delta: float) -> void:
	pass


func _on_alerted() -> void:
	bark()


func _gait_body() -> Gait.Body:
	return Gait.Body.DOG


## A dog smells; it does not look behind stoves or open wardrobes.
func checks_hiding_spots() -> bool:
	return false


func _physics_process(delta: float) -> void:
	_bark_cooldown -= delta
	if not _caught:
		smell(delta)
		_follow_trail(delta)
	super(delta)
	if not _caught and (state == State.ALERT or (state != State.PATROL and suspicion >= 0.7)):
		bark()


## Scent of the player within smell_radius, reduced by the hiding spot.
func smell(delta: float) -> void:
	var p := Stealth.player as Player
	if p == null:
		return
	var radius := smell_radius
	var spot: HideSpot = p.current_hide_spot if p.is_hidden else null
	if spot != null:
		radius *= 1.0 - spot.scent_blocking
	if global_position.distance_to(p.global_position) < radius:
		suspicion = minf(suspicion + 1.2 * delta, 1.0)
		last_known = p.global_position
		_scent_spot = spot


## Picks up the trail, walks it point by point (SUSPICIOUS -> the point ->
## the next one) and barks every trail_bark_interval seconds.
func _follow_trail(delta: float) -> void:
	if state == State.ALERT:
		return
	if trail_seq < 0:
		var pt := Stealth.freshest_scent_near(global_position, trail_pickup_radius)
		if pt.is_empty() or int(pt["seq"]) <= _trail_end_seq:
			pt = Stealth.blood_near(global_position, blood_pickup_radius)
		if pt.is_empty() or int(pt["seq"]) <= _trail_end_seq:
			return
		# Start from the oldest live point nearby so the trail leads forward.
		trail_seq = int(pt["seq"]) - 1
		_trail_pos = pt["pos"]
		_trail_bark = 0.0
	if state == State.SEARCH or state == State.PATROL \
			or global_position.distance_to(last_known) < 0.6:
		var next := Stealth.scent_after(trail_seq)
		var at: Vector3 = next.get("pos", _trail_pos)
		# Into a hiding place (Stealth.scent_into) the trail never breaks.
		if next.is_empty() or (not next.get("into", false)
				and Vector2(at.x - _trail_pos.x, at.z - _trail_pos.z).length() > MAX_TRAIL_GAP):
			_trail_end_seq = trail_seq  # the trail ends, went cold or breaks off
			trail_seq = -1
			return
		trail_seq = int(next["seq"])
		_trail_pos = at
		last_known = at
		suspicion = maxf(suspicion, SUSPICIOUS_AT + 0.1)
		_set_state(State.SUSPICIOUS)
	_trail_bark -= delta
	if _trail_bark <= 0.0:
		_trail_bark = trail_bark_interval
		_bark_cooldown = 0.0
		bark()


func bark() -> void:
	if _bark_cooldown > 0.0:
		return
	_bark_cooldown = bark_interval
	barks += 1
	Sfx.play_at("dog_bark", global_position + Vector3.UP * 0.6)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or e is Dog:
			continue
		if (e as Enemy).global_position.distance_to(global_position) < alarm_radius:
			(e as Enemy).alert_to(last_known, 0.7, _scent_spot)
	var p := Stealth.player as Player
	if p != null and p.global_position.distance_to(global_position) < 20.0:
		PanicSystem.spike(0.06)


func _patrol(delta: float) -> void:
	if handler == null:
		super(delta)
		return
	var heel := handler.global_position + handler.global_transform.basis.x * 1.0
	if global_position.distance_to(heel) > heel_distance:
		_move_towards(heel, handler.walk_speed * 1.3, delta)
	else:
		_apply_gravity_only(delta)
