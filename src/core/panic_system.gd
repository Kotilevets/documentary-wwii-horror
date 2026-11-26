extends Node
## Global panic state (docs/GAMEPLAY_AND_SHADERS.md, section 2).
## PanicLevel in [0.0, 1.0] rises in an enemy's view cone, at violence and
## gunshots; falls by itself. Also drives the heart rhythm used by the
## breath-holding QTE and the heartbeat audio/vignette.

signal panic_changed(level: float)
signal heartbeat

const REST_BPM := 72.0
const MAX_BPM := 165.0

## Units per second the level falls when nothing frightens the player.
@export var decay_per_second: float = 0.06
## Level never falls below this (debug flag --panic=, scripted scenes).
var floor_level: float = 0.0

var level: float = 0.0:
	set(value):
		var clamped := clampf(maxf(value, floor_level), 0.0, 1.0)
		if not is_equal_approx(clamped, level):
			level = clamped
			panic_changed.emit(level)

## Running: the heart races without fear (BreathControl.winded, 0..1).
var exertion: float = 0.0
## How far running alone drives the heart towards MAX_BPM.
const EXERTION_HEART := 0.7

## 0..1 position inside the current heartbeat; 0 = the beat itself.
var beat_phase: float = 0.0
var _rising_this_frame := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func bpm() -> float:
	return lerpf(REST_BPM, MAX_BPM, maxf(level, exertion * EXERTION_HEART))


func beat_period() -> float:
	return 60.0 / bpm()


## How far the panic tunnel closes in on this heartbeat (g_heartbeat at the
## beat; film_common.gdshaderinc, frame_darkening): more with panic, 0.07
## of the screen's radius at the top. The shader keeps any pixel from
## darkening on the beat by more than PULSE_DY of luminance, so the pulse
## is this deep in the dark and never a flash in a lit room
## (docs/ARCHITECTURE.md, "Вспышки и мерцание").
func pulse_depth() -> float:
	return 0.05 * (0.25 + 0.75 * level) * (0.4 + level)


## The breath window round a heartbeat (docs/ARCHITECTURE.md, "Игрок",
## the beat window): at most BEAT_WINDOW seconds either side, and never more
## than BEAT_SHARE of the beat - a racing heart gives no more room, in shares
## of the beat, than a calm one: at 165 bpm +-0.073 s, not +-0.16 s (which
## covered 88 % of the beat, so that any release was "on the beat").
const BEAT_WINDOW := 0.16
const BEAT_SHARE := 0.2


func beat_window() -> float:
	return minf(BEAT_WINDOW, BEAT_SHARE * beat_period())


## True when now is within `window` seconds of a heartbeat (by default the
## breath window, beat_window()).
func is_on_beat(window: float = -1.0) -> bool:
	var w := beat_window() if window < 0.0 else window
	var t := beat_phase * beat_period()
	return t <= w or beat_period() - t <= w


## One-off spike (gunshot, violent scene, flare).
func spike(amount: float) -> void:
	level += amount
	_rising_this_frame = true


## Continuous source (standing in an enemy view cone); call every frame.
func apply_continuous(rate_per_second: float, delta: float) -> void:
	level += rate_per_second * delta
	_rising_this_frame = true


func reset() -> void:
	floor_level = 0.0
	level = 0.0
	exertion = 0.0
	beat_phase = 0.0


func _process(delta: float) -> void:
	if not _rising_this_frame and level > floor_level:
		level -= decay_per_second * delta
	_rising_this_frame = false

	beat_phase += delta / beat_period()
	if beat_phase >= 1.0:
		beat_phase = fmod(beat_phase, 1.0)
		heartbeat.emit()
	# Short pulse right after each beat, for the vignette.
	var pulse := exp(-beat_phase * 9.0)
	RenderingServer.global_shader_parameter_set("g_panic", level)
	RenderingServer.global_shader_parameter_set("g_heartbeat", pulse * pulse_depth())
