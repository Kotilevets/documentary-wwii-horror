extends AudioStreamPlayer
## Synthesized heartbeat ("lub-dub") on PanicSystem's clock.
## Placeholder until a recorded sound from docs/ASSETS_AND_REFS.md is chosen.
##
## A frame pushed into the generator is heard only after everything already
## queued in it, what the engine holds after the queue and the driver's own
## latency: about 0.2 s on Windows (docs/ARCHITECTURE.md, «Удар слышен в
## такт»). Until 25.11.2026 each beat was synthesized when
## PanicSystem.heartbeat fired, so it was heard that much after the beat the
## breath is judged on (is_on_beat: +-0.16 s at rest). Now the beats are
## placed where PanicSystem's clock will be when they are heard, and the sound
## has no seams («Без швов»): a beat's sound always starts at its beginning
## and plays to its end at its own pace; keeping in step with PanicSystem
## moves only when the next beat starts.

const MIX_RATE := 22050.0
const BUFFER_LENGTH := 0.15
## The second sound follows the first by this much at rest...
const DUB_DELAY := 0.18
## ...and by no more than this share of the beat: a fixed 0.18 s split a
## racing beat (0.36 s at 165 bpm) into two halves, the second sound halfway
## between the beats. Set when a beat starts and kept for that beat.
const DUB_SHARE := 0.22
## Under a held breath the beats are never fainter than this, whatever the
## panic: he can count them (docs/ARCHITECTURE.md, «Дыхание рвётся»).
const HOLD_AMP := 0.3
## The engine drains the generator in blocks of about 10 ms, so the queue read
## in a frame is off by up to a block, differently each frame. The beat clock
## runs on from push to push, and each push closes NUDGE of the gap to
## PanicSystem's clock, the next beat coming at most MAX_SLEW sooner or later.
const NUDGE := 0.3
const MAX_SLEW := 0.25
## A heart speeding up or slowing down (a view cone, running, panic falling)
## is, by the time a frame pushed now is heard, ahead of or behind its pace of
## now by half its change of pace times the lead squared: 77 ms at 0.6 a
## second with «Задержка звука» 0.3 s (fourth review, 25.11.2026). The change
## of PanicSystem's beat rate is measured between pushes (track_rate()), and
## the clock is placed and stepped at the pace PanicSystem will have, up to
## MAX_BPM as it rises and to the floor's beat rate as it falls (speeding()).
## When the measure changes, the clock moves with it at once, not by NUDGE. A
## change of MAX_ACCEL beats a second per game second or more is a jump (a
## fright, a step down), which is leapt, not a pace.
const MAX_ACCEL := 2.0
## A gap of more than RESYNC s (a fright from rest, a step down in panic, a
## new «Задержка звука», a reset, a new time scale) is leapt: the clock is set
## to PanicSystem's and the sound goes on as it was. Wherever the clock lands,
## forward or back, the beat it is in starts at once if it began within the
## breath window (heard late by that much), unless the beat heard last began
## within the window of it and so stands for it (_catch_up). The same test is
## made at every push, not only at a leap: gaps under RESYNC can carry the
## beat away from the one that stood for it, out of its window. And at any
## beat: if the beat heard last began within the breath window of it, it
## stands for this one, which is not played again. So no two beats are ever
## heard closer than the window.
const RESYNC := 0.05
## Loudness glides to a new value over FADE s.
const FADE := 0.01
const FADE_FRAMES := 220  # FADE at MIX_RATE
## How often the driver's latency is read again: reading it can be slow (the
## class reference advises against every frame), and it changes only with the
## output device.
const LATENCY_EVERY_MS := 1000
## What the engine holds after the generator's queue, which neither the queue
## nor the driver's latency counts (Godot 4.7.2, servers/audio/: the resampler
## in audio_stream.cpp, the mixer in audio_server.cpp). The resampler takes
## frames from the queue RESAMPLE_CHUNK at a time and plays each one
## RESAMPLE_HISTORY frames after taking it (cubic interpolation), so at the end
## of a mixer block it holds 130 less how far it has got into the last lot:
## resample_hold(). Where that falls depends on the output rate: 66 on average
## at 48 kHz, always 130 at 44.1 kHz (each block takes exactly two lots).
## Every sound is mixed MIX_LOOKAHEAD frames late (kept for fading out). The
## mixer makes MIX_BLOCK frames at a time and the driver takes its own period,
## so on average half a block waits for the next callback. About 9.7 ms at 48
## kHz, 13.2 ms at 44.1: until the second review (25.11.2026) the beats were
## heard that much late, and until the third, 3 ms late at 44.1 kHz.
const RESAMPLE_CHUNK := 128  # generator frames
const RESAMPLE_HISTORY := 2  # generator frames
const MIX_LOOKAHEAD := 64  # output frames
const MIX_BLOCK := 512  # output frames
## Mixer blocks resample_hold() averages over.
const HOLD_BLOCKS := 1024
## When the queue is (nearly) empty - the first push, or the first after it
## ran dry - the engine plays zeros until push_buffer, so every frame pushed is
## heard as much later as synth() takes (0.7-0.8 us a frame on the laptop the
## game is made on: 3 ms for the whole queue, more on a slower one). Then the
## first HEAD_FRAMES go in at once, and the rest behind them.
const HEAD_FRAMES := 512
## The queue ran dry less than this after the newest beat began to be heard:
## no more than a click of its thump was heard, and it does not stand for the
## beat after the silence (that one starts, if it is within the window).
const CUT_HEARD := 0.015
## A thump lasts this long.
const THUMP_LEN := 0.15

@onready var _player := get_parent() as Player

## Loudness the beats glide to, from the last _process (tests).
var heard_amp := 0.0
## Seconds from the last synth() until the newest beat in it is heard, or -1.0
## if it started no beat (tests, tools/heart_sync_probe.gd).
var last_onset_ahead := -1.0
## Time.get_ticks_usec() at which the newest beat pushed will be heard (0:
## none yet).
var last_onset_usec := 0
## PanicSystem.beat_phase (0..1) at the next frame to synthesize, on the
## same clock: a share of the beat, so that a heart speeding up or slowing
## down moves it as it moves PanicSystem. -1.0 before the first push and
## after the queue ran dry (tests set it back to start afresh).
var beat_clock := -1.0
var _playback: AudioStreamGeneratorPlayback
## Frames the generator holds when it is full.
var _capacity := 0
## Three voices, the beat sounding now and the two before it (their tails
## never cut: after a leap back a beat may start while two still ring):
## seconds of game time since each began (INF: silent), and its second
## sound's delay.
var _since := INF
var _dub := DUB_DELAY
var _prev_since := INF
var _prev_dub := DUB_DELAY
var _old_since := INF
var _old_dub := DUB_DELAY
## Game seconds since the newest beat began, at the next frame to synthesize:
## as _since, but it goes on through the engine's silence when the queue ran
## dry (_since is INF then), dated on the engine's clock (_onset_engine_usec).
## INF before the first beat. Whether a beat stands for another is judged by
## it.
var _attack_age := INF
## Share of the beat per frame in the last push: a beat crossed between two
## pushes is placed by the step that crossed it.
var _last_step := 0.0
## Loudness reached by the last frame pushed.
var _amp := 0.0
## AudioServer.get_output_latency(), read every LATENCY_EVERY_MS.
var _latency := 0.0
var _latency_at := -LATENCY_EVERY_MS
## AudioStreamGeneratorPlayback.get_skips() after the last push.
var _skips := 0
## The engine's clock: Time.get_ticks_usec() less «Задержка звука», moved on
## by the time the game stood paused (the stream stands too, and PanicSystem's
## clock). The delay the heart believes may change in the pause menu; the
## sound before the silence and after it go through the same headphones.
## When the newest beat pushed and the last frame pushed reach the engine's
## output (0: none yet): the silence begins at the second if the queue runs
## dry.
var _onset_engine_usec := 0
var _queue_end_usec := 0
## Time.get_ticks_usec() at which the game was paused (0: it is not).
var _paused_usec := 0
## PanicSystem's beat rate (beats a second) at the last push, when that was
## (Time.get_ticks_usec(), moved on by the paused time; 0: no push yet), and
## how fast it changes, beats a second per game second, halved each push
## (track_rate()).
var _rate_was := 0.0
var _rate_usec := 0
var _accel := 0.0
## speeding() at the last push, which the clock was moved on by.
var _speed_was := 0.0
## resample_hold() for the output rate it was last worked out for.
static var _hold_rate := 0.0
static var _hold := 0.0


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = BUFFER_LENGTH
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
	_capacity = _playback.get_frames_available()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		paused(Time.get_ticks_usec())
	elif what == NOTIFICATION_UNPAUSED:
		resumed(Time.get_ticks_usec())


## The game was paused at `now` (Time.get_ticks_usec()): the engine's clock
## stops (the menu, a document read, the window losing focus).
func paused(now: int) -> void:
	_paused_usec = now


## The game goes on at `now`: what is dated on the engine's clock moves on by
## the time it stood. Without this, the beat heard just before the pause was
## as old as the pause after it, and if the first frame after it was longer
## than the queue, it was played again 29-153 ms after itself (fourth review).
func resumed(now: int) -> void:
	if _paused_usec == 0:
		return
	var held := now - _paused_usec
	_paused_usec = 0
	if _onset_engine_usec != 0:
		_onset_engine_usec += held
	if _queue_end_usec != 0:
		_queue_end_usec += held
	if _rate_usec != 0:
		_rate_usec += held


func _process(_delta: float) -> void:
	heard_amp = amplitude()
	if _playback == null:
		return
	var ms := Time.get_ticks_msec()
	if ms - _latency_at >= LATENCY_EVERY_MS:
		_latency = AudioServer.get_output_latency()
		_latency_at = ms
	feed(_playback, Time.get_ticks_usec(), driver_time(_latency))


## Tops up the queue of `playback` (the generator's playback, or a stand-in in
## the tests) at `now` (Time.get_ticks_usec()), with `driver` s from the next
## mix on (driver_time()). A (nearly) empty queue gets HEAD_FRAMES first, and
## the rest behind them: the same frames, heard sooner after `now`.
func feed(playback, now: int, driver: float) -> void:
	var room: int = playback.get_frames_available()
	if room <= 0:
		return
	var head := room
	if room > HEAD_FRAMES and maxi(_capacity, room) - room < HEAD_FRAMES:
		head = HEAD_FRAMES
	_feed(playback, room, head, now, driver, playback.get_skips())
	if head < room:
		_feed(playback, room - head, room - head, now, driver, _skips)


## Pushes the next `count` frames into `playback`, with `room` free at `now`
## and `skips` read before them.
func _feed(playback, room: int, count: int, now: int, driver: float, skips: int) -> void:
	var fresh := skips != _skips or beat_clock < 0.0  # push() starts afresh
	var out := push(room, now, driver, skips, count)
	if not fresh and playback.get_skips() != skips:
		# The queue ran dry while these frames were made (a frame just shorter
		# than the queue): the engine cut what was sounding, and these frames go
		# on from where it was. They fade in, so that only the engine's own cut
		# is heard, not a second one where they begin.
		for i in mini(FADE_FRAMES, out.size()):
			out[i] = out[i] * (float(i) / FADE_FRAMES)
	playback.push_buffer(out)
	# While synth() ran, the queue may have stood empty (after a frame longer
	# than the queue, and before the first push): the engine played zeros and
	# counted skips. Those came before these frames, which are heard whole
	# after them: no reason to start afresh at the next push.
	_skips = playback.get_skips()


## The next `count` frames for the generator (all of `room` if below 0), with
## `room` free at `now` (Time.get_ticks_usec()), `driver` s from the next mix
## on, `skips` times the queue has run dry so far
## (AudioStreamGeneratorPlayback.get_skips()).
func push(room: int, now: int, driver: float, skips: int, count := -1) -> PackedVector2Array:
	var frames := room if count < 0 else count
	_capacity = maxi(_capacity, room)
	var lead := lead_time(_capacity - room, driver)
	var delay := GameState.sound_delay()
	track_rate(now)
	if skips != _skips:
		# The engine played silence where the queue ran out (a frame longer
		# than the queue): what was sounding is cut, start afresh after it. The
		# beat heard last, before the silence, is dated on the engine's clock:
		# it may stand for the one PanicSystem's clock is in, unless the silence
		# cut it before more than a click of it was heard (CUT_HEARD).
		_skips = skips
		beat_clock = -1.0
		_attack_age = INF
		if _onset_engine_usec != 0 and _queue_end_usec - _onset_engine_usec >= int(CUT_HEARD * 1000000.0):
			_attack_age = (float(now - _onset_engine_usec) / 1000000.0 + lead - delay) * Engine.time_scale
	var out := synth(frames, lead, heard_amp)
	if last_onset_ahead >= 0.0:
		last_onset_usec = now + int(last_onset_ahead * 1000000.0)
		_onset_engine_usec = now + int((last_onset_ahead - delay) * 1000000.0)
	_queue_end_usec = now + int((lead - delay + frames / MIX_RATE) * 1000000.0)
	return out


## Measures, at a push at `now` (Time.get_ticks_usec()), how fast
## PanicSystem's beat rate has changed since the last push, in game time. A
## jump (MAX_ACCEL) counts as no change; the measure is halved each push.
func track_rate(now: int) -> void:
	var rate := 1.0 / PanicSystem.beat_period()
	if _rate_usec != 0:
		var game := float(now - _rate_usec) / 1000000.0 * Engine.time_scale
		if game > 0.0:
			var r := (rate - _rate_was) / game
			_accel = 0.5 * _accel + 0.5 * (r if absf(r) < MAX_ACCEL else 0.0)
	_rate_usec = now
	_rate_was = rate


## Game seconds until PanicSystem's beat rate, changing at _accel, reaches its
## bound from `period`: MAX_BPM as it rises; as it falls, the beat rate of the
## floor or of running, which panic does not fall below.
func _to_bound(period: float) -> float:
	if _accel == 0.0:
		return 0.0
	var bound := PanicSystem.MAX_BPM / 60.0
	if _accel < 0.0:
		bound = lerpf(PanicSystem.REST_BPM, PanicSystem.MAX_BPM,
				maxf(PanicSystem.floor_level, PanicSystem.exertion * PanicSystem.EXERTION_HEART)) / 60.0
	return maxf((bound - 1.0 / period) / _accel, 0.0)


## Share of the beat PanicSystem's clock gains in `a` game seconds over its
## pace of now (`period`), its beat rate changing at _accel up to its bound.
func speeding(a: float, period: float) -> float:
	if a <= 0.0:
		return 0.0
	var t := minf(_to_bound(period), a)
	return 0.5 * _accel * t * t + _accel * t * (a - t)


## Beats a game second PanicSystem's clock runs faster than at `period`, `a`
## game seconds from now.
func speeding_rate(a: float, period: float) -> float:
	if a <= 0.0:
		return 0.0
	return _accel * minf(_to_bound(period), a)


## Seconds until a frame pushed now is heard, with `queued` frames already in
## the generator and `driver` s from the next mix on (driver_time()): those
## frames, the driver, and the player's «Задержка звука» for wireless
## headphones the engine cannot see.
static func lead_time(queued: int, driver: float) -> float:
	return float(queued) / MIX_RATE + driver + GameState.sound_delay()


## Seconds a frame pushed now waits besides the frames queued before it: the
## next mix (Godot's own recipe for syncing to audio; below 0 when the
## driver's callback is late), what the engine holds after the queue
## (engine_lag()), and the driver's `latency` (AudioServer.get_output_latency()).
static func driver_time(latency: float) -> float:
	return maxf(AudioServer.get_time_to_next_mix(), 0.0) + engine_lag(AudioServer.get_mix_rate()) + latency


## What the engine holds after the queue on average (resample_hold(),
## MIX_LOOKAHEAD, MIX_BLOCK), mixing at `out_rate` frames a second.
static func engine_lag(out_rate: float) -> float:
	return resample_hold(out_rate) / MIX_RATE + (MIX_LOOKAHEAD + MIX_BLOCK / 2.0) / out_rate


## Generator frames the resampler holds at the end of a mixer block, on
## average, mixing at `out_rate`: it steps through the generator's frames by
## MIX_RATE / out_rate in 16.16 fixed point (as the engine does), from the
## start of a lot at play().
static func resample_hold(out_rate: float) -> float:
	if out_rate <= 0.0:
		return RESAMPLE_CHUNK / 2.0 + RESAMPLE_HISTORY
	if out_rate != _hold_rate:
		var inc := int(MIX_RATE / out_rate * 65536.0)
		var wrap := RESAMPLE_CHUNK << 16
		var off := 0
		var sum := 0.0
		for _n in HOLD_BLOCKS:
			off = (off + MIX_BLOCK * inc) % wrap
			sum += RESAMPLE_CHUNK + RESAMPLE_HISTORY - off / 65536.0
		_hold = sum / HOLD_BLOCKS
		_hold_rate = out_rate
	return _hold


## The next `frames` frames of the heart, gliding to loudness `amp`, the first
## one heard `lead` seconds from now. The beat clock goes on from where the
## last call left it, closing in on where PanicSystem's clock will be at that
## moment (NUDGE, MAX_SLEW) or leaping to it (RESYNC). Sets last_onset_ahead.
func synth(frames: int, lead: float, amp: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(frames)
	if frames <= 0:
		return out
	var period := PanicSystem.beat_period()
	var scale := Engine.time_scale
	var dt := scale / MIX_RATE  # game seconds per frame
	# Share of the beat per frame, at the pace PanicSystem's clock will have
	# when the middle of these frames is heard.
	var step := dt / period + dt * speeding_rate((lead + frames * 0.5 / MIX_RATE) * scale, period)
	var speed := speeding(lead * scale, period)
	var target := fposmod(since_beat_at(PanicSystem.beat_phase, period, lead) / period + speed, 1.0)
	var window := PanicSystem.beat_window()
	last_onset_ahead = -1.0
	if beat_clock >= 0.0:
		beat_clock = maxf(beat_clock + speed - _speed_was, 0.0)
	_speed_was = speed
	if beat_clock < 0.0:
		_restart(target, period, window, lead)
	else:
		var gap := wrapf(target - beat_clock, -0.5, 0.5)
		if absf(gap) * period > RESYNC * scale:
			_leap(target, period, window, lead)
		else:
			if beat_clock < 1.0:
				_catch_up(target, period, window, lead)
			var most := MAX_SLEW * step * frames
			step += clampf(NUDGE * gap, -most, most) / frames
	var glide := absf(amp - _amp) / FADE_FRAMES  # loudness change per frame
	for i in frames:
		if beat_clock >= 1.0:  # a beat falls between this frame and the one before
			beat_clock = fmod(beat_clock, 1.0)
			var by := step if i > 0 else _last_step  # the step that crossed it
			var late := minf(beat_clock / by, 1.0) if by > 0.0 else 0.0  # frames since the beat
			if _attack_age - late * dt > window:  # else the beat heard last stands for it
				_start(late * dt, period)
				last_onset_ahead = lead + (i - late) / MIX_RATE
		var s := beat_sound(_since, _dub) + beat_sound(_prev_since, _prev_dub)
		if _old_since <= _old_dub + THUMP_LEN:
			s += beat_sound(_old_since, _old_dub)
		_amp = move_toward(_amp, amp, glide)
		out[i] = Vector2(s * _amp, s * _amp)
		_since += dt
		_prev_since += dt
		_old_since += dt
		_attack_age += dt
		beat_clock += step
	_last_step = step
	return out


## A beat began `since` s ago: the one sounding becomes the one before, and
## that one the oldest.
func _start(since: float, period: float) -> void:
	_old_since = _prev_since
	_old_dub = _prev_dub
	_prev_since = _since
	_prev_dub = _dub
	_since = since
	_dub = dub_delay(period)
	_attack_age = since


## The beat PanicSystem's clock is in began `target` * `period` ago: it starts
## now, heard late by as much, if that is within the breath `window` and the
## beat heard last did not begin within the window of it (then that one stands
## for it). Otherwise there is none now, and the next comes on time.
func _catch_up(target: float, period: float, window: float, lead: float) -> void:
	if target * period <= window and absf(_attack_age - target * period) > window:
		_start(0.0, period)
		last_onset_ahead = lead


## The first push, or the first after the engine played silence: nothing is
## sounding. The beat PanicSystem's clock is in may start now (_catch_up).
func _restart(target: float, period: float, window: float, lead: float) -> void:
	_since = INF
	_prev_since = INF
	_old_since = INF
	beat_clock = target
	_catch_up(target, period, window, lead)


## A gap too big to close gently: the clock jumps to PanicSystem's, and the
## sound goes on as it was - nothing is cut or moved, so nothing clicks. Only
## which beat comes next changes: the one the clock lands in may start now
## (_catch_up), whether the clock went forward or back, over a beat or not.
func _leap(target: float, period: float, window: float, lead: float) -> void:
	_catch_up(target, period, window, lead)
	beat_clock = target


## Seconds of game time since the last beat, `ahead` real seconds from now,
## with the beat at `phase` now and `period` long (PanicSystem's clock runs on
## game time; the tests and bots speed it up).
static func since_beat_at(phase: float, period: float, ahead: float) -> float:
	return fposmod(phase + ahead * Engine.time_scale / period, 1.0) * period


## How long after the first sound of a beat the second one comes.
static func dub_delay(period: float) -> float:
	return minf(DUB_DELAY, DUB_SHARE * period)


## The heart's sound at loudness 1, `t` s after a beat: the thump and, `dub`
## s later, the second, softer one.
static func beat_sound(t: float, dub: float) -> float:
	return _thump(t) + 0.7 * _thump(t - dub)


## Loudness of the beats now: from the panic, and not below HOLD_AMP while
## he holds his breath.
func amplitude() -> float:
	var amp := lerpf(0.05, 0.6, PanicSystem.level)
	var b: BreathControl = _player.breath if _player != null else null
	if b != null and b.cues and b.holding:
		amp = maxf(amp, HOLD_AMP)
	return amp


static func _thump(t: float) -> float:
	if t < 0.0 or t > THUMP_LEN:
		return 0.0
	return sin(TAU * 48.0 * t) * exp(-t * 30.0)
