class_name PhantomSounds
extends Node
## Psychological horror of panic (GAMEPLAY_AND_SHADERS: distorted
## perception): above `threshold` the boy starts to hear things that are not
## there - a step right behind him, a dog barking somewhere back down the
## road. Only he hears them: they never go to Stealth, enemies do not react.
## The higher the panic, the more often.

signal phantom_played(id: String, position: Vector3)

@export var threshold: float = 0.55
## Seconds between phantoms at threshold and at full panic.
@export var interval_calm: float = 14.0
@export var interval_panic: float = 5.0

var _timer := 8.0
var _rng := RandomNumberGenerator.new()


func _process(delta: float) -> void:
	var p := get_parent() as Player
	if p == null or PanicSystem.level < threshold or get_tree().paused:
		_timer = maxf(_timer, 3.0)
		return
	_timer -= delta
	if _timer > 0.0:
		return
	var k := inverse_lerp(threshold, 1.0, PanicSystem.level)
	_timer = lerpf(interval_calm, interval_panic, k) * _rng.randf_range(0.7, 1.3)
	play_one(p)


func play_one(p: Player) -> void:
	var behind := p.head.global_transform.basis.z
	behind.y = 0.0
	behind = behind.normalized() if behind.length() > 0.01 else Vector3.BACK
	var side := behind.cross(Vector3.UP) * _rng.randf_range(-0.6, 0.6)
	var id: String
	var dist: float
	var volume: float
	if _rng.randf() < 0.6:
		id = "step_player"  # someone's step, right behind
		dist = _rng.randf_range(2.5, 4.5)
		volume = 0.5
	else:
		id = "dog_bark"     # back down the road
		dist = _rng.randf_range(18.0, 30.0)
		volume = 0.35
	var pos := p.global_position + (behind + side).normalized() * dist
	Sfx.play_at(id, pos, volume)
	phantom_played.emit(id, pos)
