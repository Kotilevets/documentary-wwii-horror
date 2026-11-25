extends SceneTree
## When the heartbeat is heard against PanicSystem's beat, and whether it has
## seams, on a real audio driver (docs/ARCHITECTURE.md, «Удар слышен в такт»
## and «Без швов»). Headless runs have a dummy driver that never drains the
## generator, so this one needs a real driver and no window:
##   godot --display-driver headless --audio-driver WASAPI --path . --script res://tools/heart_sync_probe.gd
## (Linux: --audio-driver PulseAudio or ALSA; macOS: CoreAudio). Nothing is
## heard: the heart plays into its own bus, and Master is muted after it. The
## player's saved «Задержка звука» is set to 0 for the run (in memory only:
## a scripted run never saves).
##
## Three steady heart rates; panic changing as in play (rising, frights,
## decay); and steps in panic big enough to be leapt (a fright from rest, two
## steps down) with «Задержка звука» at 300 ms. In ms from PanicSystem's beat
## (the signal comes on the first frame after the beat; the time of the beat
## itself is taken from its phase):
## - "predicted": when HeartbeatAudio says the beat it pushed will be heard;
## - "mixed": found in the sound itself. An AudioEffectCapture on the heart's
##   bus gets every frame as the mixer makes it, 512 at a time; the newest
##   frame read ends the last block mixed. The driver takes its own period at
##   a time, so part of that block waits for the next callback: BLOCK_WAIT
##   frames on average (where the callback falls in the block is not told:
##   +-5 ms). Then come the next callback (AudioServer.get_time_to_next_mix),
##   the driver's output latency and «Задержка звука» (headphones the engine
##   cannot see, set by the player). Each beat is the first loud frame after
##   QUIET s of silence (longer than the gap before the second sound of a
##   beat). This measure does not trust HeartbeatAudio's arithmetic, but it
##   shares the engine's own account of when a mixed frame reaches the ear:
##   what the device adds beyond its reported latency only a microphone at
##   the speaker would show.
## - "mixed - predicted": the median of the one less that of the other: what
##   the heart's lead leaves out of the engine's account (the time to the
##   next mix, the latency, what the engine holds after the queue). Per pass
##   where the driver's callback falls at the probe's read and at the heart's
##   adds +-3 ms, so it is judged on the three steady passes together.
## - "seams": steps between two neighbouring frames of the sound larger than
##   SEAM times the steepest a thump starts at the loudest the beats had in
##   the last BOUND_S. Sound computed anew from the queue the engine reports
##   (it drains the generator in blocks of ~10 ms) jumps at every push.
## - "ran dry": how often the queue was empty when the mixer came for more
##   (AudioStreamGeneratorPlayback.get_skips): a frame longer than the queue,
##   on a loaded machine. Each one is silence and then a seam; such a run says
##   nothing about the heart, repeat it on an idle machine.
## Exit code: the number of passes with a seam or a dry queue, plus the steady
## rates whose median "mixed" is off by more than MIXED_MS, plus 1 if "mixed -
## predicted" of the steady rates together is more than GAP_MS. Only the steady
## passes are judged on time: in the others the delay or the steps put some
## beats off by design (docs/ARCHITECTURE.md, «Без швов»).

const SECONDS := 6.0
const BUS := "HeartSyncProbe"
const QUIET := 0.15
const SEAM := 2.0
## Steepest a thump starts, per second at loudness 1: sin(TAU * 48 t) *
## exp(-30 t) at t = 0. The second sound comes when the first has died to a
## tenth, so the two never add up to much more.
const STEEPEST := TAU * 48.0
## The heart's loudness glides and is heard ~0.2 s after it is pushed.
const BOUND_S := 0.5
## The newest frame captured ends a mixer block of 512 frames (Godot 4.7.2,
## servers/audio/audio_server.cpp): on average half of it still goes to the
## driver at the next callback.
const BLOCK_WAIT := 256.0
## Gates on the steady passes, ms: "mixed" from PanicSystem's beat, each; and
## "mixed - predicted", the three together (good code reads 0 to +2 ms; without
## the time to the next mix, +5 ms and more; without the engine's hold, +9).
const MIXED_MS := 15.0
const GAP_MS := 3.5


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame  # the autoloads are in the tree
	var panic := root.get_node("PanicSystem")
	var state := root.get_node("GameState")
	state.settings["sound_delay_ms"] = 0
	AudioServer.add_bus()
	var bus := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, BUS)
	AudioServer.set_bus_send(bus, "Master")
	AudioServer.set_bus_mute(0, true)  # captured before Master, nothing heard
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 1.0
	AudioServer.add_bus_effect(bus, capture)
	var heart := (load("res://src/player/heartbeat_audio.gd") as GDScript).new() as AudioStreamPlayer
	heart.bus = BUS
	root.add_child(heart)
	var beats: Array[int] = []
	panic.heartbeat.connect(func() -> void:
		beats.append(Time.get_ticks_usec() - int(panic.beat_phase * panic.beat_period() * 1000000.0)))
	var latency := AudioServer.get_output_latency()
	var rate := AudioServer.get_mix_rate()
	print("driver %s, output latency %.3f s, mix rate %d, «Задержка звука» %d ms" % [
		AudioServer.get_driver_name(), latency, rate, roundi(state.call("sound_delay") * 1000.0)])
	var bad := 0
	var steady_m: Array[float] = []
	var steady_p: Array[float] = []
	for level: float in [0.0, 0.5, 1.0, -1.0, -2.0]:
		var changing := level < 0.0
		var steps := level < -1.5
		panic.reset()
		state.settings["sound_delay_ms"] = 300 if steps else 0
		if not changing:
			panic.floor_level = level
			panic.level = level
		await create_timer(1.0).timeout  # the queue now holds this heart rate
		beats.clear()
		capture.clear_buffer()
		var predicted: Array[int] = []
		var mixed: Array[int] = []
		var last := _predicted(heart)
		var quiet := 0.0  # seconds of silence before the current frame
		var amps: Array = []  # [usec, loudness] for the last BOUND_S
		var lowest := 1.0
		var seams := 0
		var worst := 0.0
		var prev := NAN  # no frame before the first one read
		var playback: AudioStreamGeneratorPlayback = heart.get("_playback")
		var delay: float = state.call("sound_delay")
		var skips0 := playback.get_skips()
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < SECONDS * 1000.0:
			if steps:
				panic.level = _stepped_level((Time.get_ticks_msec() - t0) / 1000.0, panic.level)
			elif changing:
				panic.level = _changing_level((Time.get_ticks_msec() - t0) / 1000.0)
			await process_frame
			var now := Time.get_ticks_usec()
			var amp: float = heart.call("amplitude")
			lowest = minf(lowest, amp)
			amps.append([now, amp])
			while amps.size() > 1 and amps[0][0] < now - int(BOUND_S * 1000000.0):
				amps.pop_front()
			var loudest := 0.0
			for a in amps:
				loudest = maxf(loudest, a[1])
			var seam := SEAM * STEEPEST * loudest / rate
			var threshold := 0.25 * lowest
			var n := capture.get_frames_available()
			var buf := capture.get_buffer(n)
			var to_ear := BLOCK_WAIT / rate + AudioServer.get_time_to_next_mix() + latency + delay
			for j in n:
				var x := buf[j].x
				if not is_nan(prev):
					var step := absf(x - prev) / seam
					worst = maxf(worst, step)
					if step > 1.0:
						seams += 1
				prev = x
				if absf(x) >= threshold:
					if quiet >= QUIET:
						var age := float(n - 1 - j) / rate
						mixed.append(now + int((to_ear - age) * 1000000.0))
					quiet = 0.0
				else:
					quiet += 1.0 / rate
			var u := _predicted(heart)
			if u != last:
				predicted.append(u)
				last = u
		var skips := playback.get_skips() - skips0
		var period: float = panic.beat_period()
		var p := _offsets(predicted, beats, period)
		var m := _offsets(mixed, beats, period)
		var gap := NAN if m.is_empty() or p.is_empty() else m[m.size() / 2] - p[p.size() / 2]
		if not changing:
			steady_m.append_array(m)
			steady_p.append_array(p)
		var name := "%3d bpm (window +-%.0f ms)" % [roundi(panic.bpm()), panic.beat_window() * 1000.0]
		if changing:
			name = "steps, «Задержка звука» 300 ms" if steps else "changing"
		print("%s: predicted %s; mixed %s; mixed - predicted %+.1f ms; seams %d (steepest step %.2f of the allowed); the queue ran dry %d times" % [
			name, _stats(p), _stats(m), gap, seams, worst, skips])
		if seams > 0 or skips > 0 or (not changing and (m.is_empty() or is_nan(gap)
				or absf(m[m.size() / 2]) > MIXED_MS)):
			bad += 1
	steady_m.sort()
	steady_p.sort()
	var pooled := NAN if steady_m.is_empty() or steady_p.is_empty() \
			else steady_m[steady_m.size() / 2] - steady_p[steady_p.size() / 2]
	print("steady rates together: mixed - predicted %+.1f ms (at most %.1f)" % [pooled, GAP_MS])
	if is_nan(pooled) or absf(pooled) > GAP_MS:
		bad += 1
	panic.reset()
	state.settings["sound_delay_ms"] = 0
	heart.queue_free()
	await process_frame
	quit(bad)


## Panic in the "changing" pass, `t` s into it: calm, rising 0.3 a second, a
## fright (+0.3), decay as in play, a bigger fright, decay.
static func _changing_level(t: float) -> float:
	if t < 1.0:
		return 0.0
	if t < 2.5:
		return (t - 1.0) * 0.3
	if t < 4.0:
		return 0.75 - (t - 2.5) * 0.06
	return maxf(0.0, 1.0 - (t - 4.0) * 0.06)


## Panic in the "steps" pass, `t` s into it, from `now`: calm, then a fright
## from rest to the top (caught), decay, two steps down (a memory, the
## interrogation's relief) - each leapt, with 0.3 s of «Задержка звука».
static func _stepped_level(t: float, now: float) -> float:
	if t < 1.0:
		return 0.0
	if t < 1.05:
		return 1.0
	if t >= 3.0 and t < 3.05:
		return 0.6
	if t >= 4.5 and t < 4.55:
		return 0.3
	return now


## HeartbeatAudio.last_onset_usec (0 in a version without it: "predicted"
## is then empty, and "mixed" still measures it).
func _predicted(heart: Node) -> int:
	var u: Variant = heart.get("last_onset_usec")
	return int(u) if u != null else 0


## For each time, ms from the nearest beat, sorted. Only times within half a
## beat of the beats recorded: a beat heard just after the window opened may
## belong to one before it, one pushed just before it closed to one after it.
func _offsets(times: Array[int], beats: Array[int], period: float) -> Array[float]:
	var out: Array[float] = []
	if beats.is_empty():
		return out
	var half := 0.5 * period * 1000000.0
	for u in times:
		if u < beats[0] - half or u > beats[-1] + half:
			continue
		var best := INF
		for b in beats:
			if absf(u - b) < absf(best):
				best = u - b
		out.append(best / 1000.0)
	out.sort()
	return out


func _stats(d: Array[float]) -> String:
	if d.is_empty():
		return "none"
	return "%d beats, median %+.1f ms, min %+.1f, max %+.1f" % [d.size(), d[d.size() / 2], d[0], d[-1]]
