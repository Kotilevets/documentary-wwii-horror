class_name BreathControl
extends Node
## Breath-holding QTE in a hiding spot (docs/GAMEPLAY_AND_SHADERS.md, 2).
## While an enemy is near the hiding spot:
##   - not holding the breath -> "exposure" grows; at 1.0 a sob gives you away;
##   - holding (hold_breath) -> air runs out; at 0 a loud gasp;
##   - releasing exactly on a heartbeat -> a silent sip of air;
##     releasing off the beat -> an audible exhale.
## Feedback without text: g_air darkens the frame, heartbeat audio/vignette.
## Out of breath after running (`winded`, docs/ARCHITECTURE.md, "Одышка"):
## he pants - audibly, a little noise for enemies near him; the heart races;
## his chest heaves (the view rises and falls); in a hiding place the held
## breath is shorter and not holding it gives him away sooner.
## In the open he can hold his breath too - to stifle a pant or his stomach
## (Hunger) - until the air runs out, then the same gasp; the sob and the
## telling exhale belong to the hiding place only.
## What he hears of his own breath (docs/ARCHITECTURE.md, «Дыхание рвётся»):
## hidden with an enemy within threat_radius, not holding - his own ragged
## breath, louder and quicker as the sob nears (`strain`), the view
## trembling; a catch of breath just before the sob; a quiet sip through the
## nose on a release on the beat; the heart never faint under a held breath
## (HeartbeatAudio). Only his: no noise, no sound_made; the count is the same.

signal sound_made(kind: String, loudness: float)

@export var threat_radius: float = 6.0
@export var close_radius: float = 3.2
## Seconds of held breath at PanicLevel 0 and 1.
@export var capacity_calm: float = 7.0
@export var capacity_panic: float = 3.5
@export var sip_amount: float = 0.35

var air: float = 1.0
## What the frame shows of the air (g_air): it follows `air` over
## AIR_SHOWN_TAU s, so that a sip or a breath brightens the frame
## gradually and pressing the key fast cannot make it flash
## (docs/ARCHITECTURE.md, "Вспышки и мерцание"). The game goes by `air`.
const AIR_SHOWN_TAU := 0.3
var shown_air: float = 1.0
var holding: bool = false
var exposure: float = 0.0
var _lockout: float = 0.0

## Out of breath, 0..1: running fills it, rest empties it.
var winded: float = 0.0
## Seconds of running from rest until he is fully out of breath.
@export var run_to_winded: float = 6.0
## Per second, walking and standing still (or hiding).
@export var recover_walking: float = 0.07
@export var recover_resting: float = 0.15
## He pants above this.
const PANT_FROM := 0.25
## Noise of a pant at the worst (steps: crouched 0.15, walking 0.5, running 1.0).
const PANT_NOISE := 0.3
## Fully winded: the breath holds this fraction of the time; not holding,
## he gives himself away this many times faster.
const WINDED_HOLD := 0.45
const WINDED_EXPOSURE := 2.0
## How far the view rises and falls with each breath (camera v_offset).
const SWAY := 0.012
## Pants so far (tests).
var pants := 0
var _pant_timer := 0.0
var _sway_phase := 0.0

## Off - none of what he hears of his own breath (tests compare the count).
@export var cues := true
## 0..1: how loud his ragged breath is now (0 - not heard).
var strain := 0.0
## As soon as an enemy is within threat_radius; then up with exposure.
const STRAIN_BASE := 0.2
## Seconds from full to silent once the enemy has gone beyond threat_radius.
const STRAIN_FADE := 0.6
## Loudness (linear) and pace (pitch) of the ragged breath, strain 0 -> 1.
const RAGGED_GAIN := Vector2(0.3, 1.0)
const RAGGED_PACE := Vector2(0.9, 1.3)
## The catch of breath: this many seconds before the sob at the close rate.
const CATCH_LEAD := 0.45
## The next catch is ready once the count is this much below the last one
## (or at nothing).
const CATCH_REARM := 0.25
## The view trembles this far (camera v_offset, m) at strain 1, about TREMBLE_HZ.
const TREMBLE := 0.004
const TREMBLE_HZ := 8.0
## Catches of breath so far (tests).
var catches := 0
var _catch_armed := true
var _catch_at := 0.0
var _ragged: AudioStreamPlayer3D = null
var _tremble_a := 0.0
var _tremble_b := 0.0

@onready var player: Player = get_parent()


func _physics_process(delta: float) -> void:
	var hold_input := Input.is_action_pressed("hold_breath")
	step(delta, hold_input, nearest_enemy_distance())


## One simulation step; separated from input for tests.
func step(delta: float, hold_input: bool, enemy_distance: float) -> void:
	_update_winded(delta)
	_lockout = maxf(_lockout - delta, 0.0)
	var want_hold := hold_input and _lockout <= 0.0
	if not player.is_hidden:
		exposure = 0.0
		holding = want_hold
		if holding:
			_drain(delta)
		else:
			air = move_toward(air, 1.0, 0.5 * delta)
		strain = 0.0
		_catch_armed = true
		_pant(delta)
		_update_ragged()
		_publish(delta)
		return

	if want_hold and not holding:
		holding = true
		_catch_armed = true  # he has answered: the next build-up gets its own catch
	elif not want_hold and holding:
		holding = false
		_on_release(enemy_distance)

	if holding:
		_drain(delta)
	else:
		air = move_toward(air, 1.0, 0.25 * delta)
		if enemy_distance < threat_radius:
			var rate := (0.7 + PanicSystem.level) if enemy_distance < close_radius else 0.2
			var grow := rate * lerpf(1.0, WINDED_EXPOSURE, winded)
			_warn_catch((0.7 + PanicSystem.level) * lerpf(1.0, WINDED_EXPOSURE, winded))
			exposure += grow * delta
			if exposure >= 1.0:
				exposure = 0.0
				_catch_armed = true
				PanicSystem.spike(0.1)
				_make_sound("sob", 0.8)
		else:
			exposure = move_toward(exposure, 0.0, 0.3 * delta)
	# Ready again once the count has fallen well below the catch, or to
	# nothing: a catch at a low count (panicking) is over all the same.
	if not _catch_armed and (exposure < _catch_at - CATCH_REARM or exposure <= 0.0):
		_catch_armed = true
	_update_strain(delta, enemy_distance)
	_pant(delta)
	_update_ragged()
	_publish(delta)


## His ragged breath: STRAIN_BASE once an enemy is within threat_radius,
## up with the count to the sob; gone at once when he holds his breath,
## dying away over STRAIN_FADE s when the enemy has gone.
func _update_strain(delta: float, enemy_distance: float) -> void:
	if holding:
		strain = 0.0
		return
	var target := 0.0
	if enemy_distance < threat_radius:
		target = STRAIN_BASE + (1.0 - STRAIN_BASE) * clampf(exposure, 0.0, 1.0)
	strain = target if target >= strain else move_toward(strain, target, delta / STRAIN_FADE)


## The catch of breath: once a build-up, when the sob would be CATCH_LEAD s
## off were the enemy to step up close - at `close_rate`, the count's rate
## inside close_radius (at once if it is nearer than that already). Inside
## close_radius that is the very rate; further off the catch comes sooner,
## so that a step in from the far ring cannot cut the warning short.
func _warn_catch(close_rate: float) -> void:
	if not _catch_armed or close_rate <= 0.0 or (1.0 - exposure) / close_rate > CATCH_LEAD:
		return
	_catch_armed = false
	_catch_at = exposure
	if cues:
		catches += 1
		Sfx.play_at("breath_catch", player.global_position, 1.0, player)


## The ragged breath loop: on while strain is above 0, its loudness and pace
## following strain; freed when it falls silent.
func _update_ragged() -> void:
	if not cues or strain <= 0.0:
		if _ragged != null and is_instance_valid(_ragged):
			_ragged.queue_free()
		_ragged = null
		return
	if _ragged == null or not is_instance_valid(_ragged):
		_ragged = Sfx.play_at("breath_ragged", player.global_position, 1.0, player)
		if _ragged == null:
			return
	_ragged.volume_db = Sfx.volume_of("breath_ragged") + linear_to_db(lerpf(RAGGED_GAIN.x, RAGGED_GAIN.y, strain))
	_ragged.pitch_scale = lerpf(RAGGED_PACE.x, RAGGED_PACE.y, strain)


## The ragged breath playing now, or null (tests).
func ragged_player() -> AudioStreamPlayer3D:
	return _ragged if _ragged != null and is_instance_valid(_ragged) else null


## The held breath runs out; at the end a loud gasp, and a moment before he
## can hold it again.
func _drain(delta: float) -> void:
	air -= delta / hold_capacity()
	if air <= 0.0:
		_gasp()


## The wind knocked out of him (Player.struck): the same loud gasp as when
## the held breath runs out; a held breath breaks.
func knock_out() -> void:
	_gasp()


## A loud gasp for air: enemies hear it, panic rises, and for a moment he
## cannot hold his breath again.
func _gasp() -> void:
	air = 0.35
	holding = false
	_lockout = 1.5
	PanicSystem.spike(0.15)
	_make_sound("gasp", 1.0)


## Seconds the breath holds now: shorter in panic and out of breath.
func hold_capacity() -> float:
	return lerpf(capacity_calm, capacity_panic, PanicSystem.level) * lerpf(1.0, WINDED_HOLD, winded)


func _update_winded(delta: float) -> void:
	if player.sprinting:
		# Hungry, he runs out of breath sooner (Hunger.run_factor).
		var run := run_to_winded * (player.hunger.run_factor() if player.hunger != null else 1.0)
		winded = minf(winded + delta / run, 1.0)
	else:
		var moving := Vector2(player.velocity.x, player.velocity.z).length() > 0.5
		winded = maxf(winded - (recover_walking if moving else recover_resting) * delta, 0.0)
	PanicSystem.exertion = winded


## Out of breath: a pant now and then, quicker the worse it is, and the
## chest heaving. Holding the breath stops both. Hidden, the pant is only
## his own (the risk there is the sob: exposure grows faster).
func _pant(delta: float) -> void:
	var k := clampf((winded - PANT_FROM) / (1.0 - PANT_FROM), 0.0, 1.0)
	var period := lerpf(1.3, 0.55, k)
	_sway_phase = fmod(_sway_phase + delta * TAU / period, TAU)
	_tremble_a = fmod(_tremble_a + delta * TAU * TREMBLE_HZ, TAU)
	_tremble_b = fmod(_tremble_b + delta * TAU * TREMBLE_HZ * 2.3, TAU)
	var tremble := 0.0
	if cues and not holding:
		tremble = strain * TREMBLE * (0.7 * sin(_tremble_a) + 0.3 * sin(_tremble_b))
	player.breath_sway = 0.0 if holding else sin(_sway_phase) * SWAY * smoothstep(0.15, 0.6, winded) + tremble
	if winded < PANT_FROM or holding:
		_pant_timer = minf(_pant_timer, 0.3)
		return
	_pant_timer -= delta
	if _pant_timer > 0.0:
		return
	_pant_timer = period
	pants += 1
	Sfx.play_at("breath_pant", player.global_position, lerpf(0.45, 1.0, k))
	var heard := 0.0 if player.is_hidden else PANT_NOISE * k
	if heard > 0.0:
		Stealth.emit_noise(player.global_position, heard, player)
	sound_made.emit("pant", heard)


func _on_release(enemy_distance: float) -> void:
	if PanicSystem.is_on_beat():
		air = minf(air + sip_amount, 1.0)
		exposure = maxf(exposure - 0.3, 0.0)
		sound_made.emit("sip", 0.0)
		if cues:  # only he hears it: a quiet breath in through the nose
			Sfx.play_at("breath_sip", player.global_position, 1.0, player)
	elif enemy_distance < threat_radius:
		PanicSystem.spike(0.05)
		_make_sound("exhale", 0.45)


func _make_sound(kind: String, loudness: float) -> void:
	var damping := player.current_hide_spot.noise_damping if player.current_hide_spot != null else 0.0
	var heard := loudness * (1.0 - 0.5 * damping)
	sound_made.emit(kind, heard)
	Stealth.emit_noise(player.global_position, heard, player)
	Sfx.play_at("breath_" + kind, player.global_position, 1.0)


func nearest_enemy_distance() -> float:
	var best := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Node3D:
			best = minf(best, player.global_position.distance_to((e as Node3D).global_position))
	return best


func _publish(delta: float) -> void:
	shown_air += (air - shown_air) * (1.0 - exp(-delta / AIR_SHOWN_TAU))
	RenderingServer.global_shader_parameter_set("g_air", shown_air)
