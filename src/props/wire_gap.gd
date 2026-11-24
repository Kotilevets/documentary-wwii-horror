class_name WireGap
extends Interactable
## A gap under barbed wire (docs/ARCHITECTURE.md, "Рана и бинт"): someone
## has dug out the earth and propped the lowest strand on a forked stick -
## the stick is the blue-green thing to use. The boy crawls through on his
## belly, from whichever side he is on to the other. The gap is narrow: the
## barbs always catch his forearm (Wound.cut) - the price of a way past
## the eyes on the road.
##   Crawling is heard (an action noise, half as loud crouched - then it is
## slower too); he cannot look about or stop halfway. Caught meanwhile, the
## crawl is cut short.
##   The wire runs along local X; one crosses along local Z, from -Z to +Z
## or back. The wire itself (posts, strands, the invisible wall) is the
## level's: this is only the gap.

signal crawled(player: Node)

## How far from the wire line he lies down and gets up, metres.
const REACH := 0.75
## Eye height lying on the ground.
const CRAWL_EYE := 0.3
## Seconds to get down and to get up.
const LIE_TIME := 0.35
## Crawling noise (Stealth action noise; x Player.care()).
const CRAWL_NOISE := 0.35
## How far through the crawl the barbs catch him (0..1).
const CUT_AT := 0.55
## Depth of the box the interact ray finds, across the wire.
const BOX_DEPTH := 0.7

@export var crawl_time: float = 1.8
## Crouched (carefully) it takes this much longer.
@export var careful_factor: float = 1.6

var busy := false
var _player: Player = null
var _tween: Tween = null
var _cut_done := false


func _init() -> void:
	super()
	# The stick, propping the lowest strand.
	var stick := CSGBox3D.new()
	stick.size = Vector3(0.035, 0.42, 0.035)
	stick.position = Vector3(0.18, 0.2, 0.0)
	stick.rotation.z = 0.25
	stick.use_collision = false
	add_child(stick)
	var fork := CSGBox3D.new()
	fork.size = Vector3(0.03, 0.12, 0.03)
	fork.position = Vector3(0.1, 0.42, 0.0)
	fork.rotation.z = -0.6
	fork.use_collision = false
	add_child(fork)
	# What the interact ray finds: the gap from both sides. Shallow: a ray
	# does not see a shape it starts inside, and his eye comes no closer to
	# the wire line than 0.4 m (the wire's wall and his body) - pressed to
	# the wire, crouched, or turning round where he got up, he finds it.
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 0.7, BOX_DEPTH)
	shape.shape = box
	shape.position = Vector3(0.0, 0.35, 0.0)
	add_child(shape)


func can_interact(player: Node) -> bool:
	var p := player as Player
	return not busy and p != null and not p.seized and not p.is_hidden and not p.is_seated


func interact(player: Node) -> void:
	if not can_interact(player):
		return
	super(player)
	_crawl(player as Player)


## Where he lies down (`side` -1: the -Z side, 1: the +Z side).
func side_point(side: float) -> Vector3:
	return global_transform * Vector3(0.0, 0.0, REACH * signf(side))


## The side of the wire `at` is on: -1 or 1.
func side_of(at: Vector3) -> float:
	return -1.0 if (global_transform.affine_inverse() * at).z < 0.0 else 1.0


func _crawl(p: Player) -> void:
	busy = true
	_player = p
	_cut_done = false
	var from_side := side_of(p.global_position)
	var a := side_point(from_side)
	var b := side_point(-from_side)
	var careful := p.care() < 1.0
	var t := crawl_time * (careful_factor if careful else 1.0)
	if p.satchel.is_open:
		p.satchel.close()
	p.crawling = true
	p.velocity = Vector3.ZERO
	p.collision.disabled = true
	p.look_towards(b + Vector3.UP * 0.25)
	Sfx.play_at("wire_scrape", global_position + Vector3.UP * 0.3, 0.6 if careful else 1.0)
	Stealth.emit_action_noise(global_position, CRAWL_NOISE * p.care(), p)
	_tween = create_tween()
	_tween.tween_property(p, "global_position", a, LIE_TIME * 0.6)
	_tween.parallel().tween_property(p.head, "position:y", CRAWL_EYE, LIE_TIME)
	_tween.tween_method(_crawl_step.bind(a, b), 0.0, 1.0, t)
	_tween.tween_property(p.head, "position:y", Player.CROUCH_EYE, LIE_TIME)
	_tween.tween_callback(_finish)


func _crawl_step(k: float, a: Vector3, b: Vector3) -> void:
	if _player == null:
		return
	if _player.seized:
		_abort()
		return
	_player.global_position = a.lerp(b, k)
	if not _cut_done and k >= CUT_AT:
		_cut_done = true
		Sfx.play_at("cloth_tear", _player.global_position + Vector3.UP * 0.3, 1.0, _player)
		if _player.wound != null:
			_player.wound.cut()


func _finish() -> void:
	if _player != null:
		_player.collision.disabled = false
		_player.crawling = false
		crawled.emit(_player)
	_player = null
	_tween = null
	busy = false


## Caught under the wire: the crawl ends where it is.
func _abort() -> void:
	if _tween != null:
		_tween.kill()
	_tween = null
	if _player != null:
		_player.collision.disabled = false
		_player.crawling = false
	_player = null
	busy = false


func _process(_delta: float) -> void:
	if busy and _player != null and _player.seized:
		_abort()
