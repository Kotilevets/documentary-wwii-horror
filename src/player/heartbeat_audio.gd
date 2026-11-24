extends AudioStreamPlayer
## Synthesized heartbeat ("lub-dub") following PanicSystem.heartbeat.
## Placeholder until a recorded sound from docs/ASSETS_AND_REFS.md is chosen.

const MIX_RATE := 22050.0
const DUB_DELAY := 0.18
## Under a held breath the beats are never fainter than this, whatever the
## panic: he can count them (docs/ARCHITECTURE.md, «Дыхание рвётся»).
const HOLD_AMP := 0.3

@onready var _player := get_parent() as Player

## Loudness of the beats in the last frame pushed (tests).
var heard_amp := 0.0
var _playback: AudioStreamGeneratorPlayback
var _since_beat := 10.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.15
	stream = gen
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback
	# The engine's playback keeps only a bare pointer to its generator, and the
	# audio thread still mixes it once (the fade-out) after this node is gone.
	# Freed together with the node, the generator was read after free: the
	# rare silent crash (exit 139) or hang on leaving a level
	# (docs/ARCHITECTURE.md, "Известные ограничения прототипа"). Held by the
	# playback, it lives exactly as long as the audio server can reach it.
	_playback.set_meta(&"generator", gen)
	PanicSystem.heartbeat.connect(func() -> void: _since_beat = 0.0)


func _process(_delta: float) -> void:
	heard_amp = amplitude()
	if _playback == null:
		return
	var amp := heard_amp
	for i in _playback.get_frames_available():
		var s := _thump(_since_beat) + 0.7 * _thump(_since_beat - DUB_DELAY)
		_playback.push_frame(Vector2.ONE * s * amp)
		_since_beat += 1.0 / MIX_RATE


## Loudness of the beats now: from the panic, and not below HOLD_AMP while
## he holds his breath.
func amplitude() -> float:
	var amp := lerpf(0.05, 0.6, PanicSystem.level)
	var b: BreathControl = _player.breath if _player != null else null
	if b != null and b.cues and b.holding:
		amp = maxf(amp, HOLD_AMP)
	return amp


static func _thump(t: float) -> float:
	if t < 0.0 or t > 0.15:
		return 0.0
	return sin(TAU * 48.0 * t) * exp(-t * 30.0)
