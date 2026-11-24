class_name GunfireAmbience
extends Node3D
## Distant gunfire (docs/GAMEPLAY_AND_SHADERS.md, 2: panic rises "при
## громких выстрелах"). Every so often a single shot or a short burst is
## heard from one of the source points (Marker3D children) - far off, out of
## sight, never aimed at the boy and never shown. Each one jolts the panic,
## more when it is nearer, and the boy flinches. Silent while `active` is
## off and inside safe zones (sepia: the prologue, a memory, the partisans'
## camp); a shot due then waits until the zone is left.
## The sound placeholders are muffled by distance (AudioStreamPlayer3D air
## absorption); enemies do not react to it.

signal fired(at: Vector3, burst: bool)

## Silences every ambience timer (the test runner, `--no-gunfire` renders);
## fire() called directly still works.
static var muted := false

@export var active: bool = true:
	set(value):
		if value and not active:
			_timer = randf_range(first_delay_min, first_delay_max)
		active = value
## Seconds before the first shot after the node becomes active.
@export var first_delay_min: float = 6.0
@export var first_delay_max: float = 16.0
## Seconds between shots after that.
@export var interval_min: float = 25.0
@export var interval_max: float = 70.0
@export_range(0.0, 1.0) var burst_chance: float = 0.3
## Panic spike for a shot at near_distance and at far_distance (in between
## linearly); a burst frightens a third more.
@export var near_spike: float = 0.3
@export var far_spike: float = 0.08
@export var near_distance: float = 60.0
@export var far_distance: float = 300.0

## Shots heard so far.
var shots := 0
var _timer := 0.0


func _ready() -> void:
	_timer = randf_range(first_delay_min, first_delay_max)


func _process(delta: float) -> void:
	if not active or muted:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	if Perception.in_safe_zone():
		_timer = 2.0  # not inside the refuge; soon after leaving it
		return
	_timer = randf_range(interval_min, interval_max)
	fire(randf() < burst_chance)


## Fire once now from a random source (or `at`). Returns the panic added.
func fire(burst: bool = false, at: Variant = null) -> float:
	var pos: Vector3
	if at is Vector3:
		pos = at
	else:
		var sources := get_children().filter(func(n: Node) -> bool: return n is Marker3D)
		if sources.is_empty():
			return 0.0
		pos = (sources[randi() % sources.size()] as Marker3D).global_position
	Sfx.play_at("gunfire_burst_far" if burst else "gunshot_far", pos)
	shots += 1
	var added := spike_at(pos) * (1.33 if burst else 1.0)
	PanicSystem.spike(added)
	var p := Stealth.player as Player
	if p != null:
		p.flinch(added / near_spike)
	fired.emit(pos, burst)
	return added


## Panic a single shot at `pos` adds for the player where he is now.
func spike_at(pos: Vector3) -> float:
	var p := Stealth.player as Node3D
	var d := far_distance if p == null else p.global_position.distance_to(pos)
	var k := clampf(inverse_lerp(near_distance, far_distance, d), 0.0, 1.0)
	return lerpf(near_spike, far_spike, k)
