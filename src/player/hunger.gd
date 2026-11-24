class_name Hunger
extends Node
## Hunger (docs/ARCHITECTURE.md, "Голод и хлеб"). The boy has been on the run
## for days; no bar and no text - his body says it.
##   Above GROWL_FROM his stomach growls now and then: a soldier close by
## hears it plainly and comes to look (an action noise), never close to a
## grab. He feels it coming WARNING s before - a low swell, the view
## shivering a little, the pad trembling - and holding his breath then (the
## belly tensed, in a hiding place or in the open) stifles it to a sound
## nobody walks over for. Hungry, he is out of breath sooner when he runs
## (BreathControl). Bread from the satchel puts it off.
##   The level sets where an act starts (LevelBase.start_hunger): after the
## night in the forest he is hungry.

signal growled(heard: float)
signal ate

const GROWL_FROM := 0.5
## Loudness of a growl (radius = loudness * 14 m): heard within about 3 m in
## the open. Always below the 0.3 at which a hidden boy is grabbed outright
## (Enemy._on_noise): it brings a soldier, not a hand.
const GROWL_LOUD := 0.22
## Holding the breath tenses the belly: the growl is stifled to this share.
const STIFLE := 0.25
## Seconds between the tremor he feels and the growl.
const WARNING := 1.2
## How much hunger a piece of bread takes away.
const BREAD := 0.6
## Below this he is not hungry enough to eat the bread: he keeps it.
const EAT_FROM := 0.2
## Chewing with the mouth shut: quiet, not silent.
const CHEW_NOISE := 0.06
## Running empty: at full hunger he is winded in this share of the time.
const WEAK_RUN := 0.6
## How far the view shivers at the height of the tremor, metres.
const TREMOR := 0.005

## 0 = fed, 1 = starving.
@export_range(0.0, 1.0) var level: float = 0.0
## Per second of play: from fed to growling in about 17 minutes.
@export var rate: float = 0.0005
@export var interval_min: float = 25.0
@export var interval_max: float = 70.0
## The first growl of a level comes no sooner than this.
@export var first_delay_min: float = 20.0
@export var first_delay_max: float = 45.0

var growls := 0
## Seconds to the next growl (counts only while hungry enough).
var timer := 0.0
## The tremor before a growl, 0..1 over WARNING (Player shakes the view by
## tremor_offset()).
var tremor := 0.0
var _warned := false
var _rng := RandomNumberGenerator.new()

@onready var player := get_parent() as Player


func _ready() -> void:
	_rng.randomize()
	timer = _rng.randf_range(first_delay_min, first_delay_max)


func _process(delta: float) -> void:
	if player == null or player.seized or player.is_seated:
		return
	level = minf(level + rate * delta, 1.0)
	if level < GROWL_FROM:
		_warned = false
		tremor = 0.0
		return
	timer -= delta
	if not _warned and timer <= WARNING:
		_warned = true
		Sfx.play_at("stomach_rumble", player.global_position, 1.0, player)
		var pads := Input.get_connected_joypads()
		if not pads.is_empty():
			Input.start_joy_vibration(pads[0], 0.25, 0.05, WARNING)
	tremor = clampf(1.0 - timer / WARNING, 0.0, 1.0) if _warned else 0.0
	if timer <= 0.0:
		growl()


## The stomach growls now. Returns how loud it was heard (0 if not at all).
func growl() -> float:
	_warned = false
	tremor = 0.0
	timer = next_interval()
	growls += 1
	var loud := GROWL_LOUD * lerpf(0.8, 1.0, clampf(inverse_lerp(GROWL_FROM, 1.0, level), 0.0, 1.0))
	var stifled := player.breath != null and player.breath.holding
	if stifled:
		loud *= STIFLE
	var heard := loud * (1.0 - 0.5 * _damping())
	Sfx.play_at("stomach_growl", player.global_position, loud / GROWL_LOUD, player)
	if stifled:
		Stealth.emit_noise(player.global_position, heard, player)
	else:
		# Heard plainly, it is somebody there: a soldier comes to look.
		Stealth.emit_action_noise(player.global_position, heard, player)
	if player.breath != null and player.breath.nearest_enemy_distance() < player.breath.threat_radius:
		PanicSystem.spike(0.04)
	growled.emit(heard)
	return heard


## Seconds to the next growl: sooner the hungrier he is.
func next_interval() -> float:
	var k := clampf(inverse_lerp(GROWL_FROM, 1.0, level), 0.0, 1.0)
	return _rng.randf_range(interval_min, interval_max) * lerpf(1.0, 0.5, k)


## Is he hungry enough to eat the bread rather than keep it?
func wants_bread() -> bool:
	return level >= EAT_FROM


## Eats a piece of bread: the hunger is put off.
func eat() -> void:
	level = maxf(level - BREAD, 0.0)
	_warned = false
	tremor = 0.0
	timer = next_interval()
	Sfx.play_at("chew_bread", player.global_position, 1.0, player)
	Stealth.emit_noise(player.global_position, CHEW_NOISE * (1.0 - 0.5 * _damping()), player)
	ate.emit()


## How much sooner he is winded when running (BreathControl): 1 fed, down
## to WEAK_RUN starving.
func run_factor() -> float:
	return lerpf(1.0, WEAK_RUN, smoothstep(0.3, 1.0, level))


## The view's shiver from the tremor (added to camera.v_offset).
func tremor_offset() -> float:
	if tremor <= 0.0:
		return 0.0
	return sin(Time.get_ticks_msec() * 0.09) * TREMOR * tremor


func _damping() -> float:
	return player.current_hide_spot.noise_damping if player.current_hide_spot != null else 0.0
