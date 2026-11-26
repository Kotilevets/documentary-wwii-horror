extends Node
## Automated checks of the Act I slice. Run:
##   godot --headless --path . res://tests/test_runner.tscn
##   ... res://tests/test_runner.tscn -- --only=_test_invasion,_test_spotted
## (just these groups of _run, in its order). Exit code = failures + errors
## (tests/run_guard.gd).

const LEVEL := preload("res://src/scenes/act1_village/act1_village.tscn")
const NIGHT := preload("res://src/scenes/interlude_night/night_dream.tscn")

var failures := 0
var passes := 0
## tests/run_guard.gd: errors are failures, a hung run ends. Untyped, so that
## this script still loads when that one does not (and then says so: _guarded).
@onready var _guard = $RunGuard
var _only: PackedStringArray = []
var _ran: PackedStringArray = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _guarded():
		return
	await _run()
	_guard.finish(passes, failures)


## Whether the run may start: not without the guard (tests/run_guard.gd did
## not load - this runner then quits at once, or it would hang at its end),
## not when the guard found this scene loaded a second time (it quits).
func _guarded() -> bool:
	if _guard == null or not _guard.has_method(&"finish"):
		print("FAIL  tests/run_guard.gd did not load: no run without the guard (a parse error above)")
		print("\n0 passed, 1 failed")
		get_tree().quit(1)
		return false
	return _guard.first_start()


func check(cond: bool, name: String, detail: Variant = "") -> void:
	if cond:
		passes += 1
		print("PASS  ", name)
	else:
		failures += 1
		print("FAIL  ", name, "  ", detail)


func frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=").split(",", false)
	# Never touch the player's real progress.
	GameState.save_path = "user://test_progress.json"
	GameState.reset()
	GunfireAmbience.muted = true  # random distant shots would jolt panic mid-test
	await _group(_test_panic)
	await _group(_test_heartbeat)
	await _group(_test_perception)
	await _group(_test_archive)
	await _group(_test_items)
	await _group(_test_color_mask)
	await _group(_test_sound_bank)
	await _group(_test_level)
	await _group(_test_navigation_and_dog)
	await _group(_test_nav_source)
	await _group(_test_invasion)
	await _group(_test_invasion_return)
	await _group(_test_invasion_out_too_early)
	await _group(_test_invasion_found)
	await _group(_test_invasion_behind_door)
	await _group(_test_invasion_dog_at_door)
	await _group(_test_torch_leak)
	await _group(_test_search_checks)
	await _group(_test_invasion_stove_nook)
	await _group(_test_gunfire)
	await _group(_test_footsteps)
	await _group(_test_hiding_sound)
	await _group(_test_occlusion)
	await _group(_test_light)
	await _group(_test_sight_points)
	await _group(_test_lean)
	await _group(_test_trauma_echo)
	await _group(_test_breath_cues)
	await _group(_test_action_noise)
	await _group(_test_door_leaf)
	await _group(_test_dog_at_shut_door)
	await _group(_test_held_door)
	await _group(_test_hearing_walls)
	await _group(_test_capture)
	await _group(_test_spotted)
	await _group(_test_winded)
	await _group(_test_hunger)
	await _group(_test_wound)
	await _group(_test_board_steps)
	await _group(_test_scent_trail)
	await _group(_test_phantoms)
	await _group(_test_phantom_figures)
	await _group(_test_memory)
	await _group(_test_forest_ending)
	await _group(_test_night_dream)
	await _group(_test_act2)
	await _group(_test_act2_checkpoints)
	await _group(_test_wire_gap)
	await _group(_test_patrol_rounds)
	await _group(_test_pass_rules)
	await _group(_test_interrogation_rules)
	await _group(_test_act3)
	await _group(_test_act3_bad_pass)
	await _group(_test_act3_resume)
	await _group(_test_act3_glance)
	await _group(_test_briefing_legend)
	await _group(_test_act3_arrests)
	await _group(_test_game_state)
	await _group(_test_menus)
	await _group(_test_controls)
	await _group(_test_brightness)
	await _group(_test_flashes)
	# A misspelt group would run nothing and pass.
	for g in _only:
		check(_ran.has(g), "--only= names a group of _run", g)


## One group of _run: skipped unless --only= names it (or there is no
## --only=); tests/run_guard.gd names the errors it logs with it.
func _group(test: Callable) -> void:
	var g := String(test.get_method())
	if not _only.is_empty() and not _only.has(g):
		return
	_ran.append(g)
	_guard.begin(g)
	await test.call()
	_guard.end(g)


# --- systems -------------------------------------------------------------------

func _test_panic() -> void:
	PanicSystem.reset()
	PanicSystem.spike(2.0)
	check(is_equal_approx(PanicSystem.level, 1.0), "panic is clamped to 1")
	PanicSystem.level = -1.0
	check(PanicSystem.level == 0.0, "panic is clamped to 0")
	PanicSystem.floor_level = 0.4
	PanicSystem.level = 0.0
	check(is_equal_approx(PanicSystem.level, 0.4), "panic respects floor level")
	PanicSystem.reset()
	check(PanicSystem.bpm() < 80.0, "calm heart rate", PanicSystem.bpm())
	PanicSystem.level = 1.0
	check(PanicSystem.bpm() > 150.0, "panicked heart rate", PanicSystem.bpm())
	PanicSystem.beat_phase = 0.0
	check(PanicSystem.is_on_beat(), "phase 0 is on beat")
	PanicSystem.beat_phase = 0.5
	check(not PanicSystem.is_on_beat(), "phase 0.5 is off beat")
	# The window is a share of the beat: 0.12 s after a calm beat is in it,
	# 0.12 s after a racing one is not (a third of a 0.36 s beat).
	PanicSystem.beat_phase = 0.12 / PanicSystem.beat_period()
	check(not PanicSystem.is_on_beat(), "panicked: 0.12 s after the beat is off it",
			[PanicSystem.beat_window(), PanicSystem.beat_period()])
	var share := 0.0
	for i in 100:
		PanicSystem.beat_phase = i / 100.0
		share += 0.01 if PanicSystem.is_on_beat() else 0.0
	check(share <= 0.42, "panicked: a release at random is on the beat at most 2 times in 5", share)
	PanicSystem.level = 0.0
	PanicSystem.beat_phase = 0.12 / PanicSystem.beat_period()
	check(PanicSystem.is_on_beat() and is_equal_approx(PanicSystem.beat_window(), 0.16),
			"calm: 0.12 s after the beat is on it, the window +-0.16 s", PanicSystem.beat_window())
	PanicSystem.reset()


func _test_heartbeat() -> void:
	PanicSystem.reset()
	var beats := [0]
	var cb := func() -> void: beats[0] += 1
	PanicSystem.heartbeat.connect(cb)
	PanicSystem.level = 1.0
	PanicSystem.floor_level = 1.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500:
		await get_tree().process_frame
	PanicSystem.heartbeat.disconnect(cb)
	PanicSystem.reset()
	check(beats[0] >= 2, "heartbeat fires at high panic", beats[0])

	# The engine's generator playback keeps only a bare pointer to its
	# generator and the audio thread mixes it once more after the node is gone:
	# the generator must outlive the node until the audio server lets go of the
	# playback, and then go with it (no leak while playing levels).
	var hb := (load("res://src/player/heartbeat_audio.gd") as GDScript).new() as AudioStreamPlayer
	add_child(hb)
	await get_tree().process_frame
	var gen: WeakRef = weakref(hb.stream)
	var pb: WeakRef = weakref(hb.get_stream_playback())
	check(hb.get_stream_playback().get_meta(&"generator", null) == hb.stream,
			"heartbeat playback holds its generator")
	hb.free()
	check(gen.get_ref() != null, "heartbeat generator outlives its node while the audio server holds the playback")
	t0 = Time.get_ticks_msec()
	while (gen.get_ref() != null or pb.get_ref() != null) and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame
	check(gen.get_ref() == null and pb.get_ref() == null,
			"heartbeat generator is freed with its playback once the mixer has let go",
			"%d ms" % (Time.get_ticks_msec() - t0))

	# The beat is heard on PanicSystem's clock (docs/ARCHITECTURE.md, «Удар
	# слышен в такт»): a frame pushed now is heard after what is queued, what
	# the engine holds after the queue, the driver and «Задержка звука», so the
	# beats are placed where PanicSystem's clock will be at that moment.
	# Headless, the queue is checked on a model of the engine's audio path; the
	# real one by tools/heart_sync_probe.gd.
	var heart := HEARTBEAT_AUDIO.new() as AudioStreamPlayer
	add_child(heart)
	await frames(2)
	var mix: float = HEARTBEAT_AUDIO.MIX_RATE
	# The player's own «Задержка звука» and a sped-up clock would move every
	# beat below: both are set aside for the block and put back after it.
	var delay_was = GameState.settings.get("sound_delay_ms", null)
	GameState.settings["sound_delay_ms"] = 0
	var scale_was := Engine.time_scale
	Engine.time_scale = 1.0
	PanicSystem.reset()
	var rest := PanicSystem.beat_period()
	PanicSystem.beat_phase = 0.5
	_afresh(heart)  # start afresh, not from the last push
	heart.set("_amp", 1.0)
	var lead := 0.186
	var buf: PackedVector2Array = heart.call("synth", 8192, lead, 1.0)
	var due := 0.5 * rest  # the next beat on PanicSystem's clock
	var k := int(round((due - lead) * mix))
	check(absf(float(heart.get("last_onset_ahead")) - due) < 0.00001,
			"the beat synthesized is heard exactly when PanicSystem beats, not a queue later",
			[heart.get("last_onset_ahead"), due])
	check(_peak(buf, k - 2000, k) == 0.0 and _peak(buf, k, k + int(0.006 * mix)) > 0.8,
			"silence until the frame heard on the beat, the thump from that very frame", [k, _peak(buf, k, k + int(0.006 * mix))])

	PanicSystem.level = 1.0
	PanicSystem.floor_level = 1.0
	var racing := PanicSystem.beat_period()
	PanicSystem.beat_phase = 0.0
	_afresh(heart)
	buf = heart.call("synth", 8192, 0.0, 1.0)
	var dub: float = HEARTBEAT_AUDIO.dub_delay(racing)
	check(is_equal_approx(HEARTBEAT_AUDIO.dub_delay(60.0 / 72.0), 0.18) and is_equal_approx(HEARTBEAT_AUDIO.dub_delay(0.5), 0.11)
			and absf(dub - 0.08) < 0.001,
			"the second sound: 0.18 s at rest, 0.11 s at 120 bpm, 0.08 s at 165", dub)
	check(_peak(buf, int((dub + 0.004) * mix), int((dub + 0.008) * mix)) > 0.3
			and _peak(buf, int((dub + 0.151) * mix), int((racing - 0.001) * mix)) == 0.0,
			"at 165 bpm the second sound follows close behind, the rest of the beat is quiet",
			[_peak(buf, int((dub + 0.151) * mix), int((racing - 0.001) * mix))])

	var saved = GameState.settings.get("sound_delay_ms", null)
	GameState.settings["sound_delay_ms"] = 120
	var with_delay: float = HEARTBEAT_AUDIO.lead_time(2205, 0.03)
	GameState.settings["sound_delay_ms"] = 5000
	var too_much := GameState.sound_delay()
	GameState.settings["sound_delay_ms"] = -50
	var below := GameState.sound_delay()
	if saved == null:
		GameState.settings.erase("sound_delay_ms")
	else:
		GameState.settings["sound_delay_ms"] = saved
	check(absf(with_delay - (0.1 + 0.03 + 0.12)) < 0.00001 and is_equal_approx(too_much, 0.3) and below == 0.0,
			"the lead: what is queued, the driver and «Задержка звука» (0-300 ms)", [with_delay, too_much, below])
	# What the driver adds, as _process takes it: the time to the next mix (read
	# just before and after; a driver callback between the reads is retried),
	# what the engine holds after the queue (9.7 ms at 48 kHz: the resampler's
	# 66 frames on average, the mixer's 64 of lookahead and half its 512-frame
	# block; 13.2 ms at 44.1 kHz, where the resampler holds 130 at every block)
	# and the latency.
	var hold48: float = HEARTBEAT_AUDIO.resample_hold(48000.0)
	var hold44: float = HEARTBEAT_AUDIO.resample_hold(44100.0)
	var lag48: float = HEARTBEAT_AUDIO.engine_lag(48000.0)
	var lag44: float = HEARTBEAT_AUDIO.engine_lag(44100.0)
	var lag_here: float = HEARTBEAT_AUDIO.engine_lag(AudioServer.get_mix_rate())
	var driver_ok := false
	var driver_seen: Array = []
	for attempt in 3:
		var before := maxf(AudioServer.get_time_to_next_mix(), 0.0)
		var driver: float = HEARTBEAT_AUDIO.driver_time(0.25)
		var after := maxf(AudioServer.get_time_to_next_mix(), 0.0)
		var waits := driver - 0.25 - lag_here
		driver_seen.append([before, waits, after])
		driver_ok = driver_ok or (waits >= minf(before, after) - 0.000001 and waits <= maxf(before, after) + 0.000001)
	check(absf(hold48 - 66.03) < 0.01 and hold44 == 130.0
			and absf(lag48 - (hold48 / 22050.0 + 320.0 / 48000.0)) < 0.0000001
			and absf(lag44 - (130.0 / 22050.0 + 320.0 / 44100.0)) < 0.0000001 and driver_ok,
			"after the queue: the time to the next mix, the engine's 9.7 ms (13.2 at 44.1 kHz) and the driver's latency",
			[hold48, hold44, lag48, lag44, driver_seen])
	check(is_equal_approx(HEARTBEAT_AUDIO.since_beat_at(0.9, 0.5, 0.1), 0.05)
			and is_equal_approx(HEARTBEAT_AUDIO.since_beat_at(0.0, 0.5, 0.0), 0.0),
			"since the beat: 0.1 s past a beat due in 0.05 s is 0.05 s after it")
	Engine.time_scale = 2.0
	var sped := HEARTBEAT_AUDIO.since_beat_at(0.0, 1.0, 0.25)
	Engine.time_scale = 1.0
	check(is_equal_approx(sped, 0.5), "sped up for the bots, the heart's clock runs on game time", sped)

	# What _process pushes: the queue it reads, the driver, the beat placed by
	# them; and after the queue ran dry, a fresh start. With 1095 frames queued
	# and 10 ms of driver the lead is 0.0597 s: the beat due in 0.0833 s goes
	# into frame 522.
	PanicSystem.reset()
	var period := PanicSystem.beat_period()
	var dub_rest := HEARTBEAT_AUDIO.dub_delay(period)
	PanicSystem.beat_phase = 0.9
	_afresh(heart)
	heart.set("_capacity", 4095)
	heart.set("heard_amp", 1.0)
	var skips: int = heart.get("_skips")
	var pushed: PackedVector2Array = heart.call("push", 3000, 1000000, 0.01, skips)
	var first := int(round((0.1 * period - (1095 / mix + 0.01)) * mix))
	check(_peak(pushed, 0, first) == 0.0 and _peak(pushed, first, first + int(0.006 * mix)) > 0.8
			and int(heart.get("last_onset_usec")) == 1000000 + int(0.1 * period * 1000000.0)
			and int(heart.get("_onset_engine_usec")) == int(heart.get("last_onset_usec")),
			"pushed: the beat lies where the queue and the driver put it, and the time it is heard is noted",
			[first, _peak(pushed, 0, first), heart.get("last_onset_usec"), heart.get("_onset_engine_usec")])
	pushed = heart.call("push", 300, 2000000, 0.0, skips + 1)
	var anew := true
	for i in 300:
		anew = anew and absf(pushed[i].x - HEARTBEAT_AUDIO.beat_sound(i / mix, dub_rest)) < 0.000001
	check(anew and int(heart.get("_skips")) == skips + 1,
			"after the queue ran dry (the engine played silence) the heart starts afresh: the beat due starts from its beginning, nothing cut mid-sound",
			pushed[100].x)
	# The queue ran dry 20 ms after a beat began to be heard: the engine cut it
	# short. With «Задержка звука» at 300 ms and 20 ms of driver, the frame
	# pushed now is heard 0.32 s on, 0.05 s after that beat began and 30 ms
	# into PanicSystem's beat: the one heard stands for it, it is not heard a
	# second time. Had only 10 ms of it been heard (less than CUT_HEARD), it
	# would not stand for it: the beat is heard again, whole. The beat and the
	# queue's end are dated on the engine's clock, without «Задержка звука»
	# (it may be changed in the pause menu in between): the beat reached the
	# engine's output at 2.97 s, heard at 3.27.
	GameState.settings["sound_delay_ms"] = 300
	PanicSystem.beat_phase = fposmod((0.03 - 0.32) / period, 1.0)
	heart.set("_onset_engine_usec", 2970000)
	heart.set("_queue_end_usec", 2990000)
	pushed = heart.call("push", 4095, 3000000, 0.02, skips + 2)
	check(_peak(pushed, 0, 4095) == 0.0 and float(heart.get("last_onset_ahead")) < 0.0
			and absf(float(heart.get("_attack_age")) - (0.05 + 4095 / mix)) < 0.000001,
			"after the queue ran dry just after a beat was heard, that beat is not heard again",
			[_peak(pushed, 0, 4095), heart.get("last_onset_ahead"), heart.get("_attack_age")])
	heart.set("_onset_engine_usec", 2970000)
	heart.set("_queue_end_usec", 2980000)
	pushed = heart.call("push", 4095, 3000000, 0.02, skips + 3)
	GameState.settings["sound_delay_ms"] = 0
	var again := absf(float(heart.get("last_onset_ahead")) - 0.32) < 0.000001
	for i in 600:
		again = again and absf(pushed[i].x - HEARTBEAT_AUDIO.beat_sound(i / mix, dub_rest)) < 0.000001
	check(again, "after the queue ran dry 10 ms into a beat, the beat is heard again, whole",
			[heart.get("last_onset_ahead"), pushed[100].x])
	# Heard at 3.32 s, it reaches the engine's output at 3.02; the last frame
	# pushed at 3.02 + 4095 frames.
	var end_due := 3000000 + int((0.02 + 4095 / mix) * 1000000.0)
	check(int(heart.get("last_onset_usec")) == 3320000 and int(heart.get("_onset_engine_usec")) == 3020000
			and absi(int(heart.get("_queue_end_usec")) - end_due) <= 1,
			"a push dates its beat when heard, and on the engine's clock without «Задержка звука»",
			[heart.get("last_onset_usec"), heart.get("_onset_engine_usec"), heart.get("_queue_end_usec"), end_due])
	# The game paused (the menu, a document read, the window losing focus)
	# while a beat was being heard: the engine's clock stands, and so does
	# PanicSystem's. The first frame after it is longer than the queue, the
	# queue runs dry: on the engine's clock, the pause left out, the beat heard
	# last began 70 ms before the frames pushed now, as PanicSystem's: it stands
	# for it. Counted with the pause it was 3.07 s old, and the beat was heard
	# twice, 29-153 ms apart (fourth review, 25.11.2026).
	PanicSystem.beat_phase = 0.05 / period
	_afresh(heart)
	heart.set("_capacity", 4095)
	heart.set("_onset_engine_usec", 3070000)
	heart.set("_queue_end_usec", 3100000)
	heart.set("_rate_usec", 3040000)
	heart.call("paused", 3050000)
	heart.call("resumed", 6050000)
	var shifted := [heart.get("_onset_engine_usec"), heart.get("_queue_end_usec"), heart.get("_rate_usec")]
	pushed = heart.call("push", 4095, 6120000, 0.02, skips + 4)
	check(shifted == [6070000, 6100000, 6040000] and _peak(pushed, 0, 4095) == 0.0 and float(heart.get("last_onset_ahead")) < 0.0
			and absf(float(heart.get("_attack_age")) - (0.07 + 4095 / mix)) < 0.000001,
			"after a pause, a frame longer than the queue: the beat heard just before it is not heard again",
			[shifted, _peak(pushed, 0, 4095), heart.get("last_onset_ahead"), heart.get("_attack_age")])
	# The pause reaches the heart as the tree's (NOTIFICATION_PAUSED and
	# UNPAUSED): in a level it is pausable; the runner itself never pauses.
	heart.process_mode = Node.PROCESS_MODE_PAUSABLE
	heart.set("_onset_engine_usec", 7000000)
	var before := Time.get_ticks_usec()
	get_tree().paused = true
	var noted: int = heart.get("_paused_usec")
	OS.delay_usec(2000)
	get_tree().paused = false
	var after := Time.get_ticks_usec()
	var moved_on := int(heart.get("_onset_engine_usec")) - 7000000
	heart.process_mode = Node.PROCESS_MODE_INHERIT
	check(noted >= before and int(heart.get("_paused_usec")) == 0 and moved_on >= 2000 and moved_on <= after - before,
			"the tree paused and going on: the heart's engine clock stands meanwhile", [noted - before, moved_on])
	# What _process hands the engine (feed): the queue may stand empty while the
	# refill is synthesized (after a long frame, before the first push), and
	# the engine counts those skips before the refill is in. Taken again after
	# push_buffer, they do not restart the next push: the beat the refill began
	# plays on whole.
	PanicSystem.beat_phase = 0.0
	_afresh(heart)
	heart.set("_amp", 1.0)
	var s0: int = heart.get("_skips")
	var fake := _FakePlayback.new()
	fake.skips = [s0 + 1, s0 + 3]  # before the refill; after it, two more counted meanwhile
	heart.call("feed", fake, 4000000, 0.0)
	fake.room = 300
	heart.call("feed", fake, 4186000, 0.0)
	var whole := fake.pushed.size() == 4395 and int(heart.get("_skips")) == s0 + 3
	for i in fake.pushed.size():
		whole = whole and absf(fake.pushed[i].x - HEARTBEAT_AUDIO.beat_sound(i / mix, dub_rest)) < 0.000001
	check(whole, "skips counted while the refill was made do not restart the next push: the beat plays on whole",
			[fake.pushed.size(), heart.get("_skips"), fake.pushed[4200].x if fake.pushed.size() > 4200 else null])
	# The empty queue gets a short head first (HEAD_FRAMES), heard while the
	# rest is synthesized; a queue nearly full gets what it has room for.
	check(fake.sizes == [HEARTBEAT_AUDIO.HEAD_FRAMES, 4095 - HEARTBEAT_AUDIO.HEAD_FRAMES, 300],
			"an empty queue is refilled head first, the rest behind it", fake.sizes)
	# The queue runs dry again before the next push: feed hands push the skips
	# it reads now, and the heart starts afresh. The beat begun 0.37 s before
	# is too far to stand for the one 0.17 s back, and that one too far back
	# to start: silence until the next.
	fake.skips = [s0 + 4]
	heart.call("feed", fake, 4200000, 0.0)
	check(fake.pushed.size() == 4695 and _peak(fake.pushed, 4395, 4695) == 0.0 and int(heart.get("_skips")) == s0 + 4,
			"skips counted before a push restart it",
			[fake.pushed.size(), _peak(fake.pushed, 4395, 4695), heart.get("_skips")])
	# The queue runs dry while a push is synthesized: the engine played silence
	# meanwhile, and what is pushed would resume in the middle of the sound. It
	# fades in over FADE_FRAMES instead, and the heart takes the new skips.
	PanicSystem.beat_phase = 0.0
	_afresh(heart)
	heart.set("_amp", 1.0)
	var fade_in: int = HEARTBEAT_AUDIO.FADE_FRAMES
	var s1: int = heart.get("_skips")
	var fake2 := _FakePlayback.new()
	fake2.skips = [s1]
	heart.call("feed", fake2, 5000000, 0.0)
	fake2.room = 300
	fake2.skips = [s1, s1 + 1]  # during the push
	heart.call("feed", fake2, 5186000, 0.0)
	var faded := fake2.pushed.size() == 4395 and int(heart.get("_skips")) == s1 + 1
	if faded:
		for i in 300:
			var x := HEARTBEAT_AUDIO.beat_sound((4095 + i) / mix, dub_rest) * minf(float(i) / fade_in, 1.0)
			faded = faded and absf(fake2.pushed[4095 + i].x - x) < 0.000001
	check(faded, "the queue ran dry while a push was made: it fades in, not resumed in the middle of the sound",
			[fake2.pushed.size(), heart.get("_skips"), fake2.pushed[4100].x if fake2.pushed.size() > 4100 else null])

	# Without seams (docs/ARCHITECTURE.md, «Без швов»): the engine drains the
	# generator in blocks of ~10 ms, so the queue read in a frame is off by a
	# few ms, differently each frame. The beat clock closes the gap by moving
	# the next beat; the sound of a beat always starts at its beginning and
	# goes on untouched. A big gap is leapt: only which beat comes next changes.
	var steepest := TAU * 48.0 / mix  # the steepest a thump starts, per frame at loudness 1
	var fade: int = HEARTBEAT_AUDIO.FADE_FRAMES
	PanicSystem.beat_phase = 0.0
	_afresh(heart)
	var a: PackedVector2Array = heart.call("synth", 300 + fade, 0.0, 1.0)
	var at: float = heart.get("beat_clock")
	var b: PackedVector2Array = heart.call("synth", 300, (300 + fade) / mix + 0.04, 1.0)
	var moved: float = float(heart.get("beat_clock")) - at
	var nominal := 300 / mix / period
	check(absf(b[0].x - a[a.size() - 1].x) <= steepest and absf(moved - 1.25 * nominal) < 0.000001,
			"a queue read 40 ms off in the middle of a beat: the sound goes on without a jump, the next beat moves by at most a quarter",
			[absf(b[0].x - a[a.size() - 1].x), steepest, moved / nominal])
	var sent := 600 + fade
	for n in 30:
		heart.call("synth", 300, sent / mix + 0.007, 1.0)
		sent += 300
	var gap := wrapf(HEARTBEAT_AUDIO.since_beat_at(0.0, period, sent / mix + 0.007) / period
			- float(heart.get("beat_clock")), -0.5, 0.5) * period
	check(absf(gap) < 0.0005, "kept 7 ms off, the gap is closed within 0.4 s of sound", gap)
	# The same the other way: a queue read 40 ms short slows the clock by at
	# most a quarter; kept 7 ms short, the gap is closed as well.
	PanicSystem.beat_phase = 0.0
	_afresh(heart)
	a = heart.call("synth", 300 + fade, 0.04, 1.0)
	at = heart.get("beat_clock")
	b = heart.call("synth", 300, (300 + fade) / mix, 1.0)
	moved = float(heart.get("beat_clock")) - at
	check(absf(b[0].x - a[a.size() - 1].x) <= steepest and absf(moved - 0.75 * nominal) < 0.000001,
			"a queue read 40 ms short in the middle of a beat: no jump, the next beat comes at most a quarter later",
			[absf(b[0].x - a[a.size() - 1].x), steepest, moved / nominal])
	sent = 600 + fade
	for n in 30:
		heart.call("synth", 300, sent / mix - 0.007, 1.0)
		sent += 300
	gap = wrapf(HEARTBEAT_AUDIO.since_beat_at(0.0, period, sent / mix - 0.007) / period
			- float(heart.get("beat_clock")), -0.5, 0.5) * period
	check(absf(gap) < 0.0005, "kept 7 ms short, the gap is closed within 0.4 s of sound", gap)

	# A leap that crosses no beat: the clock jumps, the beat sounding goes on.
	PanicSystem.beat_phase = 0.0
	_afresh(heart)
	heart.call("synth", 441, 0.0, 1.0)  # 0.02 s into a beat
	PanicSystem.beat_phase = 0.3  # 0.25 s further on: a reset, a new time scale
	var c: PackedVector2Array = heart.call("synth", 600, 441 / mix, 1.0)
	var same := true
	for i in 600:
		same = same and absf(c[i].x - HEARTBEAT_AUDIO.beat_sound((441 + i) / mix, dub_rest)) < 0.000001
	check(same and absf(float(heart.get("beat_clock")) - (0.3 + 1041 / mix / period)) < 0.000001,
			"a gap of 0.25 s is leapt: the clock is PanicSystem's at once, the beat sounding plays on untouched",
			[c[0].x, heart.get("beat_clock")])
	# Forward over a beat that began 0.04 s ago (a fright from rest): it starts
	# at once from its beginning, heard 0.04 s late, within the breath window.
	_sounding(heart, 0.6, 0.5, dub_rest)  # the last beat has died away
	PanicSystem.beat_phase = 0.05
	var d: PackedVector2Array = heart.call("synth", 600, 0.0, 1.0)
	var started := true
	for i in 600:
		started = started and absf(d[i].x - HEARTBEAT_AUDIO.beat_sound(i / mix, dub_rest)) < 0.000001
	check(started and float(heart.get("last_onset_ahead")) == 0.0,
			"leapt over a beat 0.04 s back: that beat starts from its beginning at once, not mid-sound", [d[50].x, heart.get("last_onset_ahead")])
	# Forward over a beat that began 0.21 s ago, beyond the window (0.16 s):
	# no beat now; the next one comes on time.
	_sounding(heart, 0.8, 0.5, dub_rest)
	PanicSystem.beat_phase = 0.25
	var e: PackedVector2Array = heart.call("synth", 600, 0.0, 1.0)
	var no_beat := _peak(e, 0, 600) == 0.0 and float(heart.get("last_onset_ahead")) < 0.0
	heart.call("synth", 20000, 600 / mix, 1.0)
	check(no_beat and absf(float(heart.get("last_onset_ahead")) - 0.75 * period) < 0.00001,
			"leapt over a beat too long ago to stand for it: none now, the next on time",
			[_peak(e, 0, 600), heart.get("last_onset_ahead")])
	# Forward over a beat that began 0.054 s ago, while the beat sounding began
	# 0.0675 s ago (two steps in panic in a row): that one stands for it, no
	# second attack 0.01 s after the first.
	_sounding(heart, 0.887, 0.0675, dub_rest)
	PanicSystem.beat_phase = 0.065
	var g: PackedVector2Array = heart.call("synth", 600, 0.0, 1.0)
	var stands := float(heart.get("last_onset_ahead")) < 0.0
	for i in 600:
		stands = stands and absf(g[i].x - HEARTBEAT_AUDIO.beat_sound(0.0675 + i / mix, dub_rest)) < 0.000001
	check(stands, "leapt over a beat the one sounding began near: it stands for it, no second attack", g[100].x)
	# The same after the engine's silence: nothing sounds, but the beat heard
	# 0.0675 s ago still stands for this one.
	_sounding(heart, 0.887, 0.0675, dub_rest)
	heart.set("_since", INF)
	PanicSystem.beat_phase = 0.065
	g = heart.call("synth", 600, 0.0, 1.0)
	check(_peak(g, 0, 600) == 0.0 and float(heart.get("last_onset_ahead")) < 0.0,
			"leapt over a beat heard just before the engine's silence: it stands, not heard again", _peak(g, 0, 600))
	# Back over the beat that began 0.04 s ago (panic falling in a step, a
	# smaller «Задержка звука»): it was early for the beat ahead, 0.125 s off,
	# within the window, and stands for it; that beat is not played again.
	_sounding(heart, 0.05, 0.05 * period, dub_rest)
	PanicSystem.beat_phase = 0.9
	var f: PackedVector2Array = heart.call("synth", 4000, 0.0, 1.0)
	var once := float(heart.get("last_onset_ahead")) < 0.0
	for i in 4000:
		once = once and absf(f[i].x - HEARTBEAT_AUDIO.beat_sound(0.05 * period + i / mix, dub_rest)) < 0.000001
	heart.call("synth", 20000, 4000 / mix, 1.0)
	check(once and absf(float(heart.get("last_onset_ahead")) - 1.1 * period) < 0.00001,
			"leapt back over the beat sounding: it stands for the one ahead, which is not played twice; the one after on time",
			[f[2000].x, heart.get("last_onset_ahead")])
	# Back over a beat that began 0.125 s ago: 0.21 s from the beat ahead, too
	# far to stand for it; that one is played.
	_sounding(heart, 0.15, 0.15 * period, dub_rest)
	PanicSystem.beat_phase = 0.9
	heart.call("synth", 4000, 0.0, 1.0)
	check(absf(float(heart.get("last_onset_ahead")) - 0.1 * period) < 0.00001,
			"leapt back over a beat too far from the one ahead: that one is played", heart.get("last_onset_ahead"))
	# Back without crossing a beat, to 0.08 s past one, while the beat sounding
	# began 0.18 s ago, 0.1 s before it (the beats queued before «Задержка
	# звука» was lowered are heard early by as much): within the window, it
	# stands for it, and that beat is not started again.
	_sounding(heart, 0.3, 0.18, dub_rest)
	PanicSystem.beat_phase = 0.08 / period
	var early: PackedVector2Array = heart.call("synth", 600, 0.0, 1.0)
	var kept := float(heart.get("last_onset_ahead")) < 0.0
	for i in 600:
		kept = kept and absf(early[i].x - HEARTBEAT_AUDIO.beat_sound(0.18 + i / mix, dub_rest)) < 0.000001
	check(kept, "leapt back to just after a beat the one sounding came early for: it stands, no second attack",
			[early[100].x, heart.get("last_onset_ahead")])
	# Back without crossing a beat, into the breath window after one (a smaller
	# «Задержка звука»; or a fright from rest with a long one, a gap of more
	# than half a beat reading as backwards). The beat sounding began 0.3 s
	# before that one, too far to stand for it: that one starts at once.
	_sounding(heart, 0.4, 0.4 * period, dub_rest)
	PanicSystem.beat_phase = 0.04
	var back: PackedVector2Array = heart.call("synth", 600, 0.0, 1.0)
	var caught_up := float(heart.get("last_onset_ahead")) == 0.0
	for i in 600:
		caught_up = caught_up and absf(back[i].x - (HEARTBEAT_AUDIO.beat_sound(i / mix, dub_rest)
				+ HEARTBEAT_AUDIO.beat_sound(0.4 * period + i / mix, dub_rest))) < 0.000001
	check(caught_up, "leapt back into the window after a beat the one sounding is far from: that beat starts at once",
			[back[50].x, heart.get("last_onset_ahead")])
	# A beat crossed at the end of a push sped up 8 times (bots) is placed by
	# the step that crossed it, not by the next push's, 8 times smaller.
	var big := 8.0 / mix / period
	heart.set("_last_step", big)
	_sounding(heart, 1.0 + 0.5 * big, 0.5, dub_rest)
	PanicSystem.beat_phase = 0.5 * big
	heart.call("synth", 10, 0.0, 1.0)
	check(absf(float(heart.get("last_onset_ahead")) + 0.5 / mix) < 0.0000001,
			"a beat crossed between two pushes is placed by the step that crossed it", heart.get("last_onset_ahead"))
	PanicSystem.beat_phase = 0.9995  # a beat in 9 frames
	_sounding(heart, 0.9995, 0.2, 0.18)  # inside the second sound of the beat before
	heart.set("_amp", 1.0)
	var tail: PackedVector2Array = heart.call("synth", 60, 0.0, 1.0)
	var worst := 0.0
	for i in range(1, 60):
		worst = maxf(worst, absf(tail[i].x - tail[i - 1].x))
	check(float(heart.get("last_onset_ahead")) > 0.0 and worst <= 2.0 * steepest,
			"the next beat does not cut the one before short: its tail plays on", worst / steepest)
	# Two catch-ups in a row, 80 ms apart, in a racing heart: the beat started
	# 80 ms before, and the one 80 ms before that, still sounding, play on
	# under the new one; none is cut off.
	PanicSystem.level = 1.0
	PanicSystem.floor_level = 1.0
	PanicSystem.beat_phase = 0.0
	_afresh(heart)
	heart.set("_amp", 1.0)
	var three: PackedVector2Array = heart.call("synth", 1764, 0.0, 1.0)
	var restarted := []
	for n in 2:
		PanicSystem.beat_phase = 0.01
		three.append_array(heart.call("synth", 1764, 0.0, 1.0))
		restarted.append(heart.get("last_onset_ahead"))
	worst = 0.0
	for i in range(1, three.size()):
		worst = maxf(worst, absf(three[i].x - three[i - 1].x))
	PanicSystem.reset()
	check(restarted == [0.0, 0.0] and worst <= 2.0 * steepest,
			"two beats started at once in a row: the ones still sounding play on, none cut off",
			[restarted, worst / steepest])
	# Loudness changing in the loud part of a beat (a fright, the breath let go)
	# glides over 10 ms instead of jumping, then the beat is as loud as asked.
	PanicSystem.beat_phase = 0.0
	_afresh(heart)
	heart.set("_amp", 1.0)
	var loud: PackedVector2Array = heart.call("synth", 331, 0.0, 1.0)  # 15 ms into a beat
	var soft: PackedVector2Array = heart.call("synth", 300, 331 / mix, 0.2)
	worst = absf(soft[0].x - loud[330].x)
	for i in range(1, 300):
		worst = maxf(worst, absf(soft[i].x - soft[i - 1].x))
	var asked := 0.2 * HEARTBEAT_AUDIO.beat_sound((331 + fade) / mix, dub_rest)
	check(absf(loud[330].x) > 0.3 and worst <= 2.0 * steepest and absf(soft[fade].x - asked) < 0.000001,
			"loudness changed in the middle of a beat glides over 10 ms, without a jump",
			[loud[330].x, worst / steepest, soft[fade].x, asked])

	# A heart speeding up (docs/ARCHITECTURE.md, «Сердце ускоряется»): panic
	# rising at 0.6 a second raises PanicSystem's beat rate by 0.93 beats a
	# second each second. Measured between pushes, within 0.2 % after ten, in
	# game time (the same at twice the time scale); a fright (a jump) is not
	# taken for a pace, the measure only halves. push() measures it.
	PanicSystem.reset()
	_afresh(heart)
	for n in 11:
		PanicSystem.level = 0.01 * n
		heart.call("track_rate", 8000000 + n * 16667)
	var paced_up: float = heart.get("_accel")
	PanicSystem.level = 0.4
	heart.call("track_rate", 8000000 + 11 * 16667)
	var halved: float = heart.get("_accel")
	PanicSystem.reset()
	_afresh(heart)
	Engine.time_scale = 2.0
	for n in 11:
		PanicSystem.level = 0.02 * n
		heart.call("track_rate", 8000000 + n * 16667)
	Engine.time_scale = 1.0
	var paced_fast: float = heart.get("_accel")
	PanicSystem.reset()
	_afresh(heart)
	heart.set("_capacity", 4095)
	heart.call("push", 300, 9000000, 0.0, heart.get("_skips"))
	PanicSystem.level = 0.01
	heart.call("push", 300, 9016667, 0.0, heart.get("_skips"))
	var pushed_pace: float = heart.get("_accel")
	PanicSystem.reset()
	check(absf(paced_up - 0.93) < 0.002 and absf(halved - 0.5 * paced_up) < 0.000000001
			and absf(paced_fast - 0.93) < 0.002 and absf(pushed_pace - 0.465) < 0.001,
			"a rise of 0.6 a second is measured as such, in game time, at each push; a fright is no pace",
			[paced_up, halved, paced_fast, pushed_pace])
	# Extrapolated over 0.5 s (the queue and «Задержка звука» 300 ms) at 0.93:
	# 0.116 of a beat at rest; at 0.95 of panic only until MAX_BPM. Falling
	# (0.06 a second), only down to the beat rate panic stops at: the floor's,
	# or running's.
	PanicSystem.reset()
	var bpm_at := func(lv: float) -> float: return 60.0 / lerpf(72.0, 165.0, lv)
	heart.set("_accel", 0.93)
	var gained: Array[float] = [heart.call("speeding", 0.5, rest), heart.call("speeding", 0.5, bpm_at.call(0.95)),
			heart.call("speeding_rate", 0.5, bpm_at.call(0.95))]
	heart.set("_accel", -0.093)
	gained.append(heart.call("speeding", 0.5, bpm_at.call(0.1)))
	gained.append(heart.call("speeding", 0.5, bpm_at.call(0.01)))
	PanicSystem.floor_level = 0.5
	gained.append(heart.call("speeding", 0.5, bpm_at.call(0.51)))
	PanicSystem.reset()
	PanicSystem.exertion = 1.0
	gained.append(heart.call("speeding", 0.5, bpm_at.call(0.71)))
	PanicSystem.reset()
	var due_gain: Array[float] = [0.11625, 0.0355208, 0.0775, -0.011625, -0.0064583, -0.0064583, -0.0064583]
	var gains_ok := true
	for j in due_gain.size():
		gains_ok = gains_ok and absf(gained[j] - due_gain[j]) < 0.000001
	check(gains_ok, "extrapolated with the change of pace, up to MAX_BPM rising, down to the floor or running falling",
			gained)
	# The clock at the pace to come: placed where PanicSystem's will be, and
	# stepped at the pace it will have when the middle of the frames is heard.
	# When the measure changes, the clock moves with it at once, not by NUDGE
	# (it was 0.116 of a beat ahead: a leap otherwise).
	PanicSystem.beat_phase = 0.1
	_afresh(heart)
	heart.set("_accel", 0.93)
	heart.call("synth", 300, 0.5, 1.0)
	var c1: float = heart.get("beat_clock")
	var sp1: float = heart.call("speeding", 0.5, rest)
	var paced: float = 1.0 / mix / rest + float(heart.call("speeding_rate", 0.5 + 150.0 / mix, rest)) / mix
	heart.set("_accel", 0.0)
	heart.call("synth", 300, 0.5 + 300 / mix, 1.0)
	var jumped := c1 - sp1
	var gap2 := wrapf(fposmod(0.1 + (0.5 + 300 / mix) / rest, 1.0) - jumped, -0.5, 0.5)
	var c2_due := jumped + 300 / mix / rest + 0.3 * gap2
	check(absf(c1 - (fposmod(0.1 + 0.5 / rest + sp1, 1.0) + 300 * paced)) < 0.000000001
			and absf(float(heart.get("beat_clock")) - c2_due) < 0.000000001,
			"the clock placed and stepped at the pace to come; moved with the measure at once",
			[c1, heart.get("beat_clock"), c2_due])
	# Gaps under RESYNC can carry PanicSystem's beat away from the beat that
	# stood for it, out of its window: 0.17 s here, the clock just past it.
	# The start test is made at every push, not only at a leap: the beat starts
	# at once (the one sounding plays on). Heard 0.13 s before it, it stands.
	_afresh(heart)
	heart.set("_amp", 1.0)
	_sounding(heart, 0.012, 0.21, dub_rest)
	PanicSystem.beat_phase = 0.04 / rest
	var caught: PackedVector2Array = heart.call("synth", 600, 0.0, 1.0)
	var at_once := float(heart.get("last_onset_ahead")) == 0.0
	for i in 600:
		at_once = at_once and absf(caught[i].x - (HEARTBEAT_AUDIO.beat_sound(i / mix, dub_rest)
				+ HEARTBEAT_AUDIO.beat_sound(0.21 + i / mix, dub_rest))) < 0.000001
	_sounding(heart, 0.012, 0.17, dub_rest)
	PanicSystem.beat_phase = 0.04 / rest
	heart.call("synth", 600, 0.0, 1.0)
	check(at_once and float(heart.get("last_onset_ahead")) < 0.0,
			"a beat the one heard last no longer stands for (nudged out of its window) starts at the next push",
			[caught[50].x, heart.get("last_onset_ahead")])

	# Panic changing as in play, through a model of the engine's audio path
	# (_heart_story): the breath held and let go, a rise, frights, decay. No
	# seam anywhere, and each beat heard close to PanicSystem's: within 15 ms,
	# and within 60 ms in the 0.35 s after a fright (pushed 0.19 s ahead at the
	# old pace, then closed at most a quarter of a step a push); and centred on
	# it, the middle of those offsets within 4 ms (without what the engine holds
	# after the queue, the beats were heard about 10 ms late). The same with
	# «Задержка звука» 300 ms, a fright reaching the ear 0.3 s later (without
	# the change of pace, the beats of the rise were 50 ms late).
	var in_play := func(t: float) -> float:
		if t >= 4.2:
			return 1.0 - (t - 4.2) * 0.06
		if t >= 2.5:
			return 0.75 - (t - 2.5) * 0.06
		if t >= 1.0:
			return (t - 1.0) * 0.3
		return 0.0
	for phys: float in [0.0, 0.3]:
		var story := _heart_story(heart, in_play, 5.5, phys, true)
		var off: Array[float] = []
		var calm: Array[float] = []
		var late_ok := true
		for h: float in story["heard"]:
			if h < 0.5 or h > 5.2:
				continue
			var best := INF
			for bt: float in story["beats"]:
				if absf(h - bt) < absf(best):
					best = h - bt
			off.append(best)
			var fright := (h >= 2.5 and h < 2.85 + phys) or (h >= 4.2 and h < 4.55 + phys)
			if not fright:
				calm.append(best)
			late_ok = late_ok and absf(best) <= (0.06 if fright else 0.015)
		calm.sort()
		var middle := INF
		if not calm.is_empty():
			middle = 0.5 * (calm[(calm.size() - 1) / 2] + calm[calm.size() / 2])
		check(story["seam"] < 0 and not story["dry"] and off.size() >= 8 and late_ok and absf(middle) <= 0.004,
				"panic changing as in play, «Задержка звука» %d ms: no seam, each beat heard on PanicSystem's (within 15 ms, 60 ms after a fright, centred within 4 ms)" % roundi(phys * 1000.0),
				[story["seam"], middle, off])
	# Panic rising at 0.6 a second to the top, with «Задержка звука» 300 ms: the
	# beats are placed at the pace PanicSystem will have, but not past MAX_BPM
	# (unbounded, 22 ms early once it got there; without the change of pace,
	# 48 ms late). From 0.9 s after the rise began (what was queued before it
	# came stays), each within 15 ms.
	var to_top := func(t: float) -> float: return minf(1.0, 0.5 + 0.6 * maxf(t - 1.0, 0.0))
	var risen := _heart_story(heart, to_top, 5.5, 0.3, false)
	var top_off: Array[float] = []
	for h: float in risen["heard"]:
		if h < 1.9 or h > 5.2:
			continue
		var best := INF
		for bt: float in risen["beats"]:
			if absf(h - bt) < absf(best):
				best = h - bt
		top_off.append(best)
	var top_ok := top_off.size() >= 8
	for o: float in top_off:
		top_ok = top_ok and absf(o) <= 0.015
	check(risen["seam"] < 0 and not risen["dry"] and top_ok,
			"panic rising to the top with «Задержка звука» 300 ms: each beat within 15 ms of PanicSystem's",
			[risen["seam"], top_off])

	# Steps in panic big enough to leap (a fright from rest, a step down, a
	# long «Задержка звука») and «Задержка звука» changed in the menu (lowered
	# at rest and in panic; raised by more than half a beat), each at six
	# moments across a beat: no seam; no two beats heard closer than the breath
	# window, nor two attacks within the window of one beat; and every beat
	# from the first frame pushed after the step on (less the window, plus 15
	# ms for the heart's estimate of the queue) heard within the window of
	# PanicSystem's. The attacks are found in the sound with the loudness the
	# heart gave each frame divided out, over one still ringing too; the
	# second sound of a beat (by the panic it was made at) is not one, and a
	# beat the heart began within 40 ms of a second sound, too close to tell
	# apart, is taken at its word. The beats queued before the step stay
	# where they were.
	var bad: Array = []
	for case in [[0.0, 1.0, 0.0, 0.0], [0.0, 0.3, 0.3, 0.3], [0.5, 0.3, 0.3, 0.3], [0.2, 0.0, 0.1, 0.1],
			[0.0, 1.0, 0.3, 0.3], [0.0, 0.0, 0.0, 0.3], [0.5, 0.5, 0.3, 0.0], [0.0, 0.0, 0.0, 0.1],
			[0.3, 0.3, 0.0, 0.1]]:
		for m in 6:
			var step_at := 1.0 + m * rest / 6.0
			var lv0: float = case[0]
			var lv1: float = case[1]
			var phys: float = case[2]  # «Задержка звука» the player really has
			var believed0: float = case[3]  # the one set before the step
			var stepped := func(t: float) -> float: return lv1 if t >= step_at else lv0
			var believed := func(t: float) -> float: return phys if t >= step_at else believed0
			var s2 := _heart_story(heart, stepped, step_at + 1.6, phys, false, believed, step_at)
			var heard0: float = s2["heard0"]
			var per_frame: float = s2["per_frame"]
			var frontier: float = s2["frontier"]
			var dub0 := HEARTBEAT_AUDIO.dub_delay(60.0 / lerpf(72.0, 165.0, lv0)) * mix
			var dub1 := HEARTBEAT_AUDIO.dub_delay(60.0 / lerpf(72.0, 165.0, lv1)) * mix
			var dub_at := func(y: int) -> float: return dub0 if heard0 + y * per_frame < frontier else dub1
			var attacks: Array[float] = []
			for k2: int in _attacks(s2["sound"], s2["level"], dub_at, s2["onsets"]):
				attacks.append(heard0 + k2 * per_frame)
			var w := minf(0.16, 0.2 * 60.0 / lerpf(72.0, 165.0, lv1))  # the breath window after the step
			var twice := false  # two attacks within one window: which is the beat?
			for j in range(1, attacks.size()):
				twice = twice or attacks[j] - attacks[j - 1] < w
			var reported: Array[float] = s2["heard"]
			for j in range(1, reported.size()):
				twice = twice or reported[j] - reported[j - 1] < w
			var judged_from := frontier - w + 0.015
			var missed := 0
			for bt: float in s2["beats"]:
				if bt < judged_from or bt > step_at + 1.4:
					continue
				var near := 0
				for at2: float in attacks:
					if absf(at2 - bt) <= w:
						near += 1
				if near == 0:
					missed += 1
				twice = twice or near > 1
			if s2["seam"] >= 0 or s2["dry"] or twice or missed > 0:
				bad.append([case, m, s2["seam"], twice, missed])
	check(bad.is_empty(), "frights from rest, steps down, «Задержка звука» set and changed: no seam, no beat twice, each beat in its window", bad)
	PanicSystem.reset()
	heart.queue_free()

	# The slider shows the saved delay when built and afresh each time the panel
	# opens (it is shared by the main menu and the pause menu).
	GameState.settings["sound_delay_ms"] = 70
	var layer := CanvasLayer.new()
	add_child(layer)
	var sp := SettingsPanel.new()
	layer.add_child(sp)
	await frames(2)
	var slider: HSlider = sp._delay
	check(slider != null and slider.min_value == 0.0 and slider.max_value == 300.0 and slider.step == 10.0
			and slider.value == 70.0 and sp._delay_label.text.ends_with(": 70 мс"),
			"«Задержка звука» in the settings: 0-300 ms in steps of 10, at the saved value",
			[slider.value if slider != null else null, sp._delay_label.text])
	GameState.settings["sound_delay_ms"] = 40
	sp.focus()
	check(slider.value == 40.0 and sp._delay_label.text.ends_with(": 40 мс"),
			"opened again, it shows the delay as it is now", [slider.value, sp._delay_label.text])
	slider.value = 150.0
	check(is_equal_approx(GameState.sound_delay(), 0.15) and sp._delay_label.text.ends_with(": 150 мс"),
			"moving it sets the delay at once and shows it", sp._delay_label.text)
	slider.value = 0.0
	layer.queue_free()
	await frames(2)
	if delay_was == null:
		GameState.settings.erase("sound_delay_ms")
	else:
		GameState.settings["sound_delay_ms"] = delay_was
	Engine.time_scale = scale_was


## The heart starts afresh at its next synth(): no beat clock, no beat heard,
## no change of pace measured, not paused.
static func _afresh(heart: Node) -> void:
	heart.set("beat_clock", -1.0)
	heart.set("_attack_age", INF)
	heart.set("_onset_engine_usec", 0)
	heart.set("_queue_end_usec", 0)
	heart.set("_paused_usec", 0)
	heart.set("_rate_usec", 0)
	heart.set("_rate_was", 0.0)
	heart.set("_accel", 0.0)
	heart.set("_speed_was", 0.0)


## The heart's clock at `clock`, the beat sounding (and heard last) begun
## `since` s ago with its second sound `dub` s after the first, nothing before.
static func _sounding(heart: Node, clock: float, since: float, dub: float) -> void:
	heart.set("beat_clock", clock)
	heart.set("_since", since)
	heart.set("_attack_age", since)
	heart.set("_dub", dub)
	heart.set("_prev_since", INF)
	heart.set("_old_since", INF)


## The heart through a model of Godot 4.7.2's audio path (servers/audio/
## audio_server.cpp, audio_stream.cpp; drivers/wasapi): the driver takes 480
## frames at 48 kHz every 10 ms, the first time 3.7 ms after the first push;
## the mixer makes 512 at a time, only when the last block is used up; the
## resampler takes the generator's frames 128 at a time (the first 128 it took
## at play() were silence); every sound is 64 frames late; then 10 ms of
## driver latency and `phys` s of headphones («Задержка звука» as it really
## is). 60 game frames a second, each pushing what the queue has room for,
## with the lead the heart would compute: the queue, the time to the next mix,
## what the engine holds (engine_lag), the latency and the delay it believes
## (`believed_at(t)`, else `phys`). Panic set by `level_at(t)`; with `breath`,
## the breath held from 0.3 to 0.8 s. Returns the sound as pushed (sound,
## loudest: the loudness bound of each frame, level: the loudness the heart
## gave it), frame k heard at heard0 + k * per_frame, PanicSystem's beats and
## the beats the heart reported, in seconds heard (and onsets: the frames
## they began at), the first seam (-1 if none), whether the queue ever ran
## dry, and with `mark`, when the first frame pushed at or after it is heard
## (frontier).
func _heart_story(heart: Node, level_at: Callable, seconds: float, phys: float, breath: bool,
		believed_at: Callable = Callable(), mark: float = -1.0) -> Dictionary:
	var mix: float = HEARTBEAT_AUDIO.MIX_RATE
	var steepest := TAU * 48.0 / mix
	var inc := int(mix / 48000.0 * 65536.0)  # the resampler's step, 16.16 fixed point
	PanicSystem.reset()
	_afresh(heart)
	heart.set("_amp", 0.0)
	var now := [0.0]
	var beats: Array[float] = []  # when PanicSystem beat
	var on_beat := func() -> void:
		beats.append(float(now[0]) - PanicSystem.beat_phase * PanicSystem.beat_period())
	PanicSystem.heartbeat.connect(on_beat)
	var frame := 1.0 / 60.0
	var start := frame + 0.0037  # the first driver callback
	var lag: float = HEARTBEAT_AUDIO.engine_lag(48000.0)
	var per_frame := 65536.0 / inc / 48000.0
	var heard0 := start + 0.01 + (130.0 * 65536.0 / inc + 64.0) / 48000.0 + phys
	var sound := PackedFloat32Array()
	var loudest := PackedFloat32Array()  # the loudest each frame can be
	var level := PackedFloat32Array()  # how loud the heart made each frame
	var heard: Array[float] = []
	var onsets: Array[int] = []
	var last_amp := 0.0
	var played := 0  # frames the mixer has made
	var to_mix := 0  # frames of its last block the driver has not taken yet
	var calls := 0  # driver callbacks so far
	var dry := false
	var frontier := -1.0
	for n in int(seconds * 60.0):
		var t := n * frame
		PanicSystem.level = level_at.call(t)
		now[0] = t + frame
		PanicSystem._process(frame)
		var tn := t + frame  # PanicSystem's clock stands at the end of the frame: the push is then
		while start + calls * 0.01 <= tn:
			var todo := 480
			while todo > 0:
				if to_mix == 0:
					played += 512
					to_mix = 512
				var c := mini(to_mix, todo)
				todo -= c
				to_mix -= c
			calls += 1
		var pulled := 128 * (((played - 1) * inc) / (128 * 65536)) if played > 0 else 0
		var queued := sound.size() - pulled
		if queued < 0:
			dry = true
			queued = 0
		var room := 4095 - queued
		if room <= 0:
			continue
		var believed: float = believed_at.call(t) if believed_at.is_valid() else phys
		var lead := queued / mix + (start + calls * 0.01 - tn) + lag + 0.01 + believed
		var amp := lerpf(0.05, 0.6, PanicSystem.level)
		if breath and t >= 0.3 and t < 0.8:
			amp = maxf(amp, HEARTBEAT_AUDIO.HOLD_AMP)  # the breath held, then let go
		var base := sound.size()
		if mark >= 0.0 and frontier < 0.0 and t >= mark:
			frontier = heard0 + base * per_frame
		var was: float = heart.get("_amp")
		heart.call("track_rate", roundi(tn * 1000000.0))  # as push() does
		var out: PackedVector2Array = heart.call("synth", room, lead, amp)
		var glide := absf(amp - was) / HEARTBEAT_AUDIO.FADE_FRAMES  # as synth() glides
		for i in out.size():
			sound.append(out[i].x)
			loudest.append(maxf(amp, last_amp))
			was = move_toward(was, amp, glide)
			level.append(was)
		last_amp = amp
		var onset: float = heart.get("last_onset_ahead")
		if onset >= 0.0:
			heard.append(heard0 + (base + (onset - lead) * mix) * per_frame)
			onsets.append(roundi(base + (onset - lead) * mix))
	PanicSystem.heartbeat.disconnect(on_beat)
	var seam := -1
	for j in range(1, sound.size()):
		if absf(sound[j] - sound[j - 1]) > 2.0 * steepest * loudest[j]:
			seam = j
			break
	return {"sound": sound, "loudest": loudest, "level": level, "beats": beats, "heard": heard,
			"onsets": onsets, "seam": seam, "dry": dry, "heard0": heard0, "per_frame": per_frame,
			"frontier": frontier}


## Frames of `sound` where a thump begins, over silence or over one still
## ringing, in the sound with the loudness the heart gave each frame
## (`level`) divided out (a loudness gliding over a ringing beat is not a
## rise): where the loudest |x| over the next 6 ms reaches 0.3 and twice the
## loudest over the 11 ms before (more than half a 48 Hz cycle, so a zero
## crossing never reads as silence) plus 0.02; the attack is the first frame
## rising 0.05 above that. At most one in 25 ms. Taken on the maxima of
## 22-frame blocks (1 ms). A rise `dub_at.call(y)` frames (within 6 ms) after
## an attack y is that beat's second sound: dropped, it starts no 25 ms; but
## if the heart began a beat within 40 ms of it (`onsets`), closer than this
## tells two rises apart, the two are heard as one, and that beat is kept.
func _attacks(sound: PackedFloat32Array, level: PackedFloat32Array, dub_at: Callable,
		onsets: Array[int]) -> Array[int]:
	const BLOCK := 22
	const PAST := 11
	const NEXT := 6
	var refractory := int(0.025 * HEARTBEAT_AUDIO.MIX_RATE)
	var dub_tol := int(0.006 * HEARTBEAT_AUDIO.MIX_RATE)
	var fuse := int(0.04 * HEARTBEAT_AUDIO.MIX_RATE)
	var x := PackedFloat32Array()
	x.resize(sound.size())
	for k in sound.size():
		x[k] = sound[k] / level[k] if level[k] > 0.0001 else 0.0
	var blocks := x.size() / BLOCK
	var peak := PackedFloat32Array()
	peak.resize(blocks)
	for bi in blocks:
		var m := 0.0
		for k in range(bi * BLOCK, bi * BLOCK + BLOCK):
			m = maxf(m, absf(x[k]))
		peak[bi] = m
	var out: Array[int] = []
	var last := -1000000
	var bl := PAST
	while bl < blocks - NEXT:
		var k := bl * BLOCK
		var ahead := 0.0
		for c in range(bl, bl + NEXT):
			ahead = maxf(ahead, peak[c])
		var before := 0.0
		for c in range(bl - PAST, bl):
			before = maxf(before, peak[c])
		if k - last >= refractory and ahead >= 0.3 and ahead >= 2.0 * before + 0.02:
			var r := k
			while r < k + NEXT * BLOCK and absf(x[r]) < before + 0.05:
				r += 1
			var second := false
			for y: int in out:
				second = second or absf(r - y - float(dub_at.call(y))) < dub_tol
			if not second:
				out.append(r)
				last = r
			else:
				for o: int in onsets:
					if absi(o - r) <= fuse and not out.has(o):
						out.append(o)
						last = o
						break
			bl = r / BLOCK + 1
			continue
		bl += 1
	return out


## A stand-in for AudioStreamGeneratorPlayback in HeartbeatAudio.feed():
## `room` frames free, get_skips() giving `skips` in turn (the last one from
## then on), what is pushed kept in `pushed`, the size of each push in `sizes`.
class _FakePlayback:
	extends RefCounted
	var room := 4095
	var skips: Array[int] = []
	var pushed := PackedVector2Array()
	var sizes := []

	func get_frames_available() -> int:
		return room

	func get_skips() -> int:
		var s: int = skips[0]
		if skips.size() > 1:
			skips.remove_at(0)
		return s

	func push_buffer(frames: PackedVector2Array) -> bool:
		pushed.append_array(frames)
		sizes.append(frames.size())
		return true

## Loudest sample of `buf` in the frames [from, to).
static func _peak(buf: PackedVector2Array, from: int, to: int) -> float:
	var m := 0.0
	for i in range(maxi(from, 0), mini(to, buf.size())):
		m = maxf(m, absf(buf[i].x))
	return m


func _test_perception() -> void:
	Perception.reset()
	PanicSystem.reset()
	PanicSystem.floor_level = 1.0
	PanicSystem.level = 1.0
	check(is_equal_approx(Perception.target_distortion(), 1.0), "distortion follows panic")
	Perception.set_illusion_factor(0.5)
	check(is_equal_approx(Perception.target_distortion(), 0.5), "IllusionFactor scales distortion")
	Perception.push_suppression()
	check(Perception.target_distortion() == 0.0, "document inspection removes distortion")
	Perception.pop_suppression()
	Perception.enter_safe_zone()
	# Wait by time, not by frames: headless frame rate is not fixed.
	var t0 := Time.get_ticks_msec()
	while Perception.sepia <= 0.5 and Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame
	check(Perception.sepia > 0.5, "sepia rises in a safe zone", Perception.sepia)
	Perception.reset()
	PanicSystem.reset()


func _test_archive() -> void:
	var docs := ["act1_kommandantur_order", "act1_registration_notice",
			"ref_jurisdiction_decree_1941", "ref_chgk",
			"act2_arbeitsamt_summons", "ref_burned_villages"]
	for id in docs:
		var d := ArchiveDB.get_document(id)
		check(not d.is_empty(), "archive has " + id)
		check(not d.get("sources", []).is_empty(), id + " has sources")
		for ref in d.get("related", []):
			check(ArchiveDB.has_document(ref), "%s -> %s exists" % [id, ref])
	var allowed_hosts := _hosts_in_historical_archive()
	for id in docs:
		for s in ArchiveDB.get_document(id).get("sources", []):
			if str(s.url) == "":
				# A book: its title must be among the sources of HISTORICAL_ARCHIVE.md.
				var book := str(s.title).get_slice("«", 1).get_slice("»", 0)
				check(book != "" and FileAccess.get_file_as_string("res://docs/HISTORICAL_ARCHIVE.md").contains(book),
						"%s book source is listed in HISTORICAL_ARCHIVE.md" % id, s.title)
				continue
			var host: String = s.url.split("/")[2]
			check(allowed_hosts.has(host), "%s source host is listed in HISTORICAL_ARCHIVE.md" % id, host)
	var order := ArchiveDB.get_document("act1_kommandantur_order")
	var shown := ArchiveUI.render_document(order)
	check(shown.contains("ещё не внесён"), "pending text is shown honestly, not invented")
	var note := ArchiveUI.render_archive_note(order)
	check(note.contains("1941") and note.contains("ЧГК"), "archive note includes related references")


func _hosts_in_historical_archive() -> Array[String]:
	var text := FileAccess.get_file_as_string("res://docs/HISTORICAL_ARCHIVE.md")
	var out: Array[String] = []
	var re := RegEx.new()
	re.compile("https?://([^/\\s)]+)")
	for m in re.search_all(text):
		out.append(m.get_string(1))
	return out


func _test_items() -> void:
	var dir := DirAccess.open("res://assets/data/items")
	for f in dir.get_files():
		if f.get_extension() != "tres":
			continue
		var item := load("res://assets/data/items/" + f) as ItemData
		check(item != null and item.id != "", "item %s loads" % f)
		if item != null and item.document_id != "":
			check(ArchiveDB.has_document(item.document_id), "item %s points to an archive entry" % f)


func _test_color_mask() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	add_child(mi)
	ColorMask.apply(mi, ColorMask.Channel.RED)
	check(ColorMask.channel_of(mi.get_active_material(0)) == 1, "ColorMask writes stencil 1")
	ColorMask.apply(mi, ColorMask.Channel.INTERACTIVE)
	check(ColorMask.channel_of(mi.get_active_material(0)) == 2, "ColorMask rewrites stencil 2")
	mi.queue_free()
	var red_shader := load("res://src/rendering/shaders/enemy_insignia.gdshader") as Shader
	check(red_shader.code.contains("stencil_mode write, compare_always, 1;"), "insignia shader writes stencil 1")
	for pass_name in ["post_base", "post_red", "post_teal"]:
		var sh := load("res://src/rendering/shaders/%s.gdshader" % pass_name) as Shader
		check(sh.code.contains("stencil_mode read, compare_equal"), pass_name + " reads stencil")


# --- level -----------------------------------------------------------------------

func _test_level() -> void:
	var level := LEVEL.instantiate()
	level.play_intro = false
	add_child(level)
	await frames(3)
	level._ending = true  # never reload the scene from inside tests
	var player := level.get_node("Player") as Player
	var enemies := get_tree().get_nodes_in_group("enemies")
	check(enemies.size() == 4, "three people and a dog in the village", enemies.size())
	for e in enemies:
		e.process_mode = Node.PROCESS_MODE_DISABLED

	# Every interactable is blue-green.
	for node in level.find_children("*", "Interactable", true, false):
		for g in (node as Node).find_children("*", "GeometryInstance3D", true, false):
			var mi := g as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			for s in mi.mesh.get_surface_count():
				check(ColorMask.channel_of(mi.get_active_material(s)) == 2,
						"%s is marked blue-green" % level.get_path_to(mi))

	# Looking at a point.
	player.global_position = Vector3(0, 0, -4)
	await frames(2)
	var target := Vector3(10, 1.35, -4)
	player.look_towards(target)
	var fwd := -player.camera.global_transform.basis.z
	check(fwd.dot((target - player.camera.global_position).normalized()) > 0.98,
			"look_towards aims the camera", fwd)

	# Cellar view looks up through the floorboards.
	var hatch := level.get_node("IzbaA/CellarHatch") as HideSpot
	var vfwd := -hatch.view_transform().basis.z
	check(vfwd.y > 0.2, "cellar view point looks upward", vfwd)
	player.look_towards(player.head.global_position + Vector3(0, 3, -10))
	var up_fwd := -player.camera.global_transform.basis.z
	check(up_fwd.y > 0.2 and up_fwd.z < -0.8, "look_towards pitches up for a raised target", up_fwd)

	# Enemy sight.
	var fg := level.get_node("Feldgendarm") as Enemy
	fg.rotation.y = 0.0
	player.global_position = fg.global_position + Vector3(0, 0, -6)
	await frames(2)
	check(fg.can_see(player), "enemy sees the player in front")
	player.global_position = fg.global_position + Vector3(0, 0, 6)
	await frames(2)
	check(not fg.can_see(player), "enemy does not see behind")

	# Enemy hearing.
	fg.suspicion = 0.0
	Stealth.emit_noise(fg.global_position + Vector3(3, 0, 0), 1.0, player)
	check(fg.suspicion > 0.3, "enemy hears a loud noise", fg.suspicion)
	fg.suspicion = 0.0
	Stealth.emit_noise(fg.global_position + Vector3(12, 0, 0), 0.15, player)
	check(fg.suspicion == 0.0, "enemy does not hear a crouched step 12 m away", fg.suspicion)

	# Hiding.
	player.global_position = hatch.global_position + Vector3(0.8, 0, 0)
	await frames(2)
	hatch.interact(player)
	check(player.is_hidden and player.hide_overlay.visible, "player hides in the cellar")
	fg.global_position = hatch.global_position + Vector3(0, 0, -1.5)
	fg.rotation.y = PI
	await frames(2)
	check(not fg.can_see(player), "hidden player is not seen")

	# Breath control.
	var breath := player.get_node("BreathControl") as BreathControl
	var sounds: Array[String] = []
	var rec := func(kind: String, _l: float) -> void: sounds.append(kind)
	breath.sound_made.connect(rec)
	PanicSystem.reset()
	for i in 60:
		breath.step(1.0 / 30.0, false, 2.0)
	check(sounds.has("sob"), "not holding the breath near an enemy ends in a sob", sounds)
	sounds.clear()
	breath.step(0.1, true, 2.0)
	PanicSystem.beat_phase = 0.0
	breath.step(0.1, false, 2.0)
	check(sounds.has("sip"), "release on the heartbeat is a silent sip", sounds)
	sounds.clear()
	breath.step(0.1, true, 2.0)
	PanicSystem.beat_phase = 0.5
	breath.step(0.1, false, 2.0)
	check(sounds.has("exhale"), "release off the beat is an audible exhale", sounds)
	sounds.clear()
	breath.air = 1.0
	for i in 400:
		breath.step(1.0 / 30.0, true, 2.0)
	check(sounds.has("gasp"), "holding too long ends in a gasp", sounds)
	breath.sound_made.disconnect(rec)

	# The sob above came from the hiding spot 1.5 m from the enemy: caught.
	check(fg._caught, "a sob from the hiding spot near an enemy is fatal")

	hatch.interact(player)
	check(not player.is_hidden and not player.hide_overlay.visible, "player leaves the cellar")
	fg.global_position = Vector3(-4, 0, -8)

	# Pickups and the Witness Archive.
	var bread := level.get_node("IzbaA/Bread") as Pickup
	bread.interact(player)
	check(Inventory.has_item("bread"), "bread goes into the satchel")
	var notice := level.get_node("IzbaA/RegistrationNotice") as Pickup
	notice.interact(player)
	check(Inventory.documents.has("act1_registration_notice"), "document is collected")
	check(player.archive_ui.is_open and get_tree().paused, "document inspection opens and pauses")
	check(Perception.is_suppressed(), "inspection suppresses distortion")
	player.archive_ui.close()
	check(not get_tree().paused and not Perception.is_suppressed(), "closing the document resumes the game")

	player.satchel.open()
	await frames(1)
	check(player.satchel._holders.size() == Inventory.items().size(), "satchel shows every item",
			player.satchel._holders.size())
	player.satchel.close()

	# Safe zone at the forest edge.
	Perception.reset()
	player.global_position = level.get_node("ForestEdge").global_position + Vector3(0, -1, 0)
	await frames(5)
	check(Perception.in_safe_zone(), "forest edge is a safe zone")

	level.queue_free()
	await frames(2)


func _test_sound_bank() -> void:
	check(Sfx.stream_for("dog_bark") != null, "bark has a placeholder until recorded")
	check(Sfx.stream_for("breath_sob") != null, "sob has a placeholder until recorded")
	check(Sfx.stream_for("de_speech") == null, "German speech stays silent until recorded")
	check(Sfx.missing_ids().has("de_speech"), "missing recordings are listed")
	var bank = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/sound_bank.json"))
	for id in bank:
		check(str(bank[id].get("source_hint", "")) != "", "sound %s says where to get it" % id)
	var t0 := Time.get_ticks_msec()
	for id in bank:
		Sfx.stream_for(id)
	check(Time.get_ticks_msec() - t0 < 500, "placeholders are loaded, not synthesized in play",
			Time.get_ticks_msec() - t0)
	for id in bank:
		if str(bank[id].get("placeholder", "")) == "":
			continue
		var wav := Sfx.stream_for(id) as AudioStreamWAV
		var pcm := _pcm(wav)
		var peak := 0.0
		for x in pcm:
			peak = maxf(peak, absf(x))
		check(wav != null and pcm.size() > Sfx.MIX_RATE * 0.05 and peak > 0.05 and peak < 0.99,
				"placeholder of %s is a real sound, not clipped" % id, [pcm.size(), peak])
		var loops := Sfx.is_loop(id)
		check(loops == (wav.loop_mode == AudioStreamWAV.LOOP_FORWARD and wav.loop_end == pcm.size()),
				"%s loops only if the bank says so" % id)
		if loops:
			# Continuous loops join smoothly; a beat loop ends in silence and
			# starts with its beat.
			var last := pcm[pcm.size() - 1]
			check(absf(last - pcm[0]) < 0.12 or absf(last) < 0.005, "the loop of %s has no click at the seam" % id,
					[last, pcm[0]])
	# The baked files are what the synthesizer makes now (tools/bake_sounds.gd).
	var kinds: Array[String] = []
	for id in bank:
		var k := str(bank[id].get("placeholder", ""))
		if k != "" and not kinds.has(k):
			kinds.append(k)
	for k in kinds:
		var path: String = Sfx.PLACEHOLDER_DIR + k + ".res"
		var baked := load(path) as AudioStreamWAV if ResourceLoader.exists(path) else null
		var fresh: AudioStreamWAV = Sfx.synth(k)
		check(baked != null and baked.data == fresh.data and baked.loop_mode == fresh.loop_mode,
				"baked placeholder %s is up to date (else run tools/bake_sounds.gd)" % k)
	# The bake tool itself runs without the autoloads: it must still compile.
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://tools/bake_sounds.gd", "--", "--check"], out, true)
	check(code == 0 and str(out).contains("same") and not str(out).contains("SCRIPT ERROR"),
			"tools/bake_sounds.gd runs on its own and finds every baked file up to date", code)
	var clock := _pcm(Sfx.stream_for("wall_clock") as AudioStreamWAV)
	check(clock.size() == Sfx.MIX_RATE * 2, "the clock loop is two seconds: tick, tock", clock.size())
	check(_energy(clock, 0.0, 0.05) > 20.0 * _energy(clock, 0.45, 0.5)
			and _energy(clock, 1.0, 1.05) > 20.0 * _energy(clock, 0.45, 0.5),
			"one beat a second, silence between")
	var engine := _pcm(Sfx.stream_for("engine_far") as AudioStreamWAV)
	check(absf(engine[0]) < 0.01 and _energy(engine, 2.0, 2.5) > 10.0 * _energy(engine, 0.0, 0.1),
			"the far engine comes in slowly")


func _pcm(wav: AudioStreamWAV) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if wav == null:
		return out
	for i in range(0, wav.data.size(), 2):
		out.append(wav.data.decode_s16(i) / 32767.0)
	return out


## Mean square of the samples between two moments, seconds.
func _energy(pcm: PackedFloat32Array, from: float, to: float) -> float:
	var a := int(from * Sfx.MIX_RATE)
	var b := mini(int(to * Sfx.MIX_RATE), pcm.size())
	var e := 0.0
	for i in range(a, b):
		e += pcm[i] * pcm[i]
	return e / maxf(b - a, 1)


func _test_navigation_and_dog() -> void:
	var level := LEVEL.instantiate()
	level.play_intro = false
	add_child(level)
	level._ending = true
	var nav := level.get_node("Navigation") as RuntimeNavRegion
	var t0 := Time.get_ticks_msec()
	while not nav.is_baked and Time.get_ticks_msec() - t0 < 10000:
		await get_tree().physics_frame
	check(nav.is_baked and nav.navigation_mesh.get_polygon_count() > 50, "navmesh is baked at runtime",
			nav.navigation_mesh.get_polygon_count() if nav.navigation_mesh else 0)
	var player := level.get_node("Player") as Player
	player.global_position = Vector3(30, 0, 30)  # out of everyone's way
	# Stop the AI but keep the bodies in the physics space.
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set_physics_process(false)

	# Path from the street into the izba goes through the door, not the wall.
	var map: RID = level.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, Vector3(0, 0, 0), Vector3(-1, 0, 6), true)
	check(path.size() > 2 and path[path.size() - 1].distance_to(Vector3(-1, 0, 6)) < 0.6,
			"path into the izba exists", path)
	var through_door := false
	for pt in path:
		if absf(pt.z - 3.5) < 0.7 and absf(pt.x - 1.5) < 0.8:
			through_door = true
	check(through_door, "path into the izba goes through the door")

	# An enemy walks around the izba instead of into its wall.
	var soldier := level.get_node("Polizei") as Enemy
	soldier.global_position = Vector3(0, 0, 1.5)
	await frames(2)
	var goal := Vector3(0, 0, 10.5)
	var reached := false
	for i in 900:
		if soldier._move_towards(goal, 3.0, 1.0 / 60.0):
			reached = true
			break
		await get_tree().physics_frame
	check(reached, "enemy walks around the izba to the far side", soldier.global_position)

	# Dog: smell through hay, not through the cellar.
	var dog := level.get_node("Shepherd") as Dog
	var hay := level.get_node("Barn/HayHide") as HideSpot
	var hatch := level.get_node("IzbaA/CellarHatch") as HideSpot
	player.global_position = hay.global_position + Vector3(1.2, 0, 0)
	await frames(2)
	hay.interact(player)
	dog.global_position = hay.global_position + Vector3(-1.6, 0, 0)
	dog.suspicion = 0.0
	dog.smell(0.5)
	check(dog.suspicion > 0.0, "dog smells the player through the hay", dog.suspicion)
	hay.interact(player)
	player.global_position = hatch.global_position + Vector3(0.8, 0, 0)
	await frames(2)
	hatch.interact(player)
	dog.global_position = hatch.global_position + Vector3(-1.6, 0, 0)
	dog.suspicion = 0.0
	dog.smell(0.5)
	check(dog.suspicion == 0.0, "the cellar hides the scent at 1.6 m", dog.suspicion)
	hatch.interact(player)

	# Bark calls soldiers to the spot; a soldier at an occupied spot pulls the player out.
	player.global_position = hay.global_position + Vector3(1.2, 0, 0)
	await frames(2)
	hay.interact(player)
	dog.global_position = hay.global_position + Vector3(-1.6, 0, 0)
	dog.smell(0.5)
	var road := level.get_node("SoldierRoad") as Enemy
	road.global_position = hay.global_position + Vector3(0, 0, 8)
	road.state = Enemy.State.PATROL
	dog._bark_cooldown = 0.0
	var panic_before := PanicSystem.level
	dog.bark()
	check(road.state == Enemy.State.SUSPICIOUS and road._target_spot == hay,
			"bark sends the soldier to the hiding spot", [road.state, road._target_spot])
	check(PanicSystem.level > panic_before, "bark nearby raises panic")
	road.global_position = hay.global_position + Vector3(0, 0, 1.2)
	road._check_target_spot()
	check(road._caught, "soldier at the occupied hiding spot pulls the player out")

	level.queue_free()
	await frames(2)


# --- story ---------------------------------------------------------------------

## The opening in fast-forward: the player hides in the cellar during the
## knock, the soldier searches the izba and leaves without finding them.
func _test_invasion() -> void:
	PanicSystem.reset()
	Perception.reset()
	var level := LEVEL.instantiate()
	var seq := level.get_node("Invasion") as InvasionSequence
	seq.prologue_time = 1.5
	seq.warning_time = 2.0
	seq.search_time = 1.5
	seq.linger_time = 2.0
	seq.look_back_time = 1.0
	var beats: Array = []
	seq.beat_changed.connect(func(b: InvasionSequence.Beat) -> void: beats.append(b))
	add_child(level)
	level._ending = true
	var player := level.get_node("Player") as Player
	player.get_node("BreathControl").set_physics_process(false)  # no sobs from a test
	var soldier := level.get_node("SoldierRoad") as Enemy
	var door := level.get_node("IzbaDoor") as IzbaDoor
	var fg := level.get_node("Feldgendarm") as Enemy
	await frames(3)
	check(seq.beat == InvasionSequence.Beat.PROLOGUE, "the level opens with the prologue")
	var clock := level.get_node("IzbaClock") as WallClock
	check(clock.player != null and clock.player.playing and Sfx.is_loop("wall_clock"),
			"the clock ticks in the izba")
	var quiet_db := clock.player.volume_db
	PanicSystem.level = 0.8
	await frames(2)
	await _passes()
	check(clock.rate == 1.0 and clock.player.volume_db > quiet_db + 3.0,
			"in panic the ticking is louder, but time is not bent at home", [clock.rate, clock.player.volume_db])
	PanicSystem.level = 0.0
	var sounds: Array[String] = []
	var on_sound := func(id: String, _p: AudioStreamPlayer3D) -> void: sounds.append(id)
	Sfx.played.connect(on_sound)
	Sfx._missing.clear()  # _test_sound_bank asked for every id: the knock must ask for its own
	check(Perception.in_safe_zone(), "prologue in the izba is a sepia safe zone")
	check(not fg.visible and not soldier.visible, "no occupiers in the prologue")
	check(not seq.flare.autofire, "no flares before the invasion")
	check(not door.is_open, "the door is shut in the prologue")
	check(soldier.torch != null and not soldier.torch_on, "the torch is off in the prologue")
	var c := soldier.torch.light_color
	check(is_equal_approx(c.r, c.g) and is_equal_approx(c.g, c.b), "torch light is colourless", c)
	var hatch := level.get_node("IzbaA/CellarHatch") as HideSpot

	Engine.time_scale = 4.0
	var t0 := Time.get_ticks_msec()
	var entered := false
	var safe_after_invasion := true
	var hid_at := -1
	while seq.beat != InvasionSequence.Beat.ESCAPE and Time.get_ticks_msec() - t0 < 60000 			and not soldier._caught:
		await get_tree().physics_frame
		# As a player would: he hides at the knock, standing - the lid at full
		# loudness, the soldier and the dog just outside the shut door.
		if hid_at < 0 and seq.beat == InvasionSequence.Beat.KNOCK:
			hatch.interact(player)
			hid_at = seq.beat
		var sp := soldier.global_position
		if seq.beat == InvasionSequence.Beat.SEARCH and absf(sp.x) < 2.7 and sp.z > 3.9 and sp.z < 8.2:
			entered = true
		if seq.beat >= InvasionSequence.Beat.INVASION and Perception.in_safe_zone():
			safe_after_invasion = false
	Engine.time_scale = 1.0
	check(beats == [InvasionSequence.Beat.PROLOGUE, InvasionSequence.Beat.INVASION, InvasionSequence.Beat.KNOCK,
			InvasionSequence.Beat.SEARCH, InvasionSequence.Beat.LEAVE, InvasionSequence.Beat.LINGER,
			InvasionSequence.Beat.RETURN, InvasionSequence.Beat.ESCAPE],
			"beats run in order", beats)
	check(seq.beat == InvasionSequence.Beat.ESCAPE, "the sequence reaches the escape", seq.beat)
	check(sounds.has("engine_far"), "a truck is heard far off when they come", sounds)
	check(sounds.has("door_knock") and Sfx.missing_ids().has("de_door") and not Sfx.missing_ids().has("de_shout")
			and not sounds.has("enemy_break_run")
			and not sounds.has("breath_startle") and player.startles == 0,
			"the knock is a demand at the door, not 'I see you': no run, no start (his voice silent until recorded)",
			[player.startles, Sfx.missing_ids()])
	Sfx.played.disconnect(on_sound)
	check(safe_after_invasion, "no sepia after the flare")
	check(fg.visible and seq.flare.autofire, "patrols and flares start with the invasion")
	check(door.is_open, "the door has been kicked in")
	check(soldier.torch_on and soldier.torch.is_visible_in_tree(), "the soldier searches with a torch")
	check(entered, "the soldier searched inside the izba (in the search, not only when he looks back in)")
	check(hid_at == InvasionSequence.Beat.KNOCK and player.is_hidden, "he hid in the cellar at the knock", hid_at)
	check(not soldier._caught and not (level.get_node("Shepherd") as Enemy)._caught,
			"a quiet player in the cellar is not found (the lid at the knock was behind the shut door)")
	check(not soldier.hold_position, "the soldier is back on patrol")
	level.queue_free()
	await frames(2)


## The false departure (docs/ARCHITECTURE.md, "Сцена «Вторжение»", "Ложный
## уход"): the boy sits it out in the cellar. The soldier leaves round the
## corner and stands there by the leave point facing the yard before the
## door, the torch swinging both ways, the dog sniffing; then he comes back
## over the threshold to the look-back point in the middle of the room and
## looks round it, the dog left on the threshold; only then he goes, taking
## the dog from the threshold, and the escape begins. Times are the
## sequence's clock (Stealth.clock): physics may fall behind it under load,
## so his turn is measured from when he has come round, not from a time.
func _test_invasion_return() -> void:
	PanicSystem.reset()
	Perception.reset()
	var level := LEVEL.instantiate()
	var seq := level.get_node("Invasion") as InvasionSequence
	seq.prologue_time = 1.0
	seq.warning_time = 1.0
	seq.search_time = 1.0
	seq.linger_time = 8.0
	var beats: Array = []
	var stamps := {}
	seq.beat_changed.connect(func(b: InvasionSequence.Beat) -> void:
		beats.append(b)
		stamps[b] = Stealth.clock)
	add_child(level)
	level._ending = true
	var player := level.get_node("Player") as Player
	player.get_node("BreathControl").set_physics_process(false)
	var soldier := level.get_node("SoldierRoad") as Enemy
	var dog := level.get_node("Shepherd") as Dog
	var hatch := level.get_node("IzbaA/CellarHatch") as HideSpot
	var leave := seq.leave_point.global_position
	var front := (level.get_node("Invasion/Approach/A2") as Node3D).global_position
	var look := level.get_node("Invasion/LookBack") as Marker3D
	var look_at := look.global_position
	var fwd := -look.global_basis.z
	var face_look := atan2(-fwd.x, -fwd.z)
	await frames(3)
	check(seq.look_back_point == look and fwd.x < -0.5 and fwd.z > 0.5 and absf(look_at.x) < 2.0 \
			and look_at.z > 4.5 and look_at.z < 7.0,
			"he looks back in from the middle of the izba, facing south-west (the table)", [look_at, fwd])
	# The sniff is voiced low: most of it passes the Occluded cut, so it comes
	# through the log wall (a one-pole low-pass at the cut keeps 0.86-0.89 of
	# it; the hiss it was before, 0.18-0.19).
	var wav := Sfx.stream_for("dog_sniff") as AudioStreamWAV
	var low := 0.0
	var whole := 0.0
	if wav != null and wav.format == AudioStreamWAV.FORMAT_16_BITS:
		var pcm := wav.data
		var y := 0.0
		var a := 1.0 - exp(-TAU * Sfx.OCCLUDED_HZ / float(wav.mix_rate))
		for i in range(0, pcm.size() - 1, 2):
			var x := float(pcm.decode_s16(i)) / 32768.0
			y += (x - y) * a
			low += y * y
			whole += x * x
	check(whole > 0.0 and low / whole > 0.6, "the dog's sniff is low enough to come through a wall",
			low / maxf(whole, 1e-9))
	hatch.admit(player)
	var sniffs := {}
	var heard := [0, 0]  # sniffs while he lingers and the boy is in the cellar: reaching him through the wall, all
	var on_sound := func(id: String, p: AudioStreamPlayer3D) -> void:
		if id == "dog_sniff":
			sniffs[seq.beat] = int(sniffs.get(seq.beat, 0)) + 1
			if seq.beat == InvasionSequence.Beat.LINGER and player.is_hidden:
				heard[1] += 1
				if p.bus == Sfx.OCCLUDED_BUS and p.global_position.distance_to(hatch.global_position) < p.max_distance:
					heard[0] += 1
	Sfx.played.connect(on_sound)
	var off_post := 0.0  # farthest from the leave point while lingering
	var turned := false  # come round to face the door front while lingering
	var off_face := 0.0  # widest turn off the way to the door front after that
	var linger_swing := [INF, -INF]  # and its two sides
	var looked := 0.0  # seconds looking round from the look-back point
	var swing := [INF, -INF]  # his yaw then, off the look-back point's -Z
	var dog_in := false  # the dog in the izba while he is back
	var took_dog_at := Vector3.INF  # where he was when the dog was at his heel again
	var last := Stealth.clock
	Engine.time_scale = 4.0
	var t0 := Time.get_ticks_msec()
	while seq.beat != InvasionSequence.Beat.ESCAPE and not soldier._caught and not dog._caught \
			and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().physics_frame
		var step := Stealth.clock - last
		last = Stealth.clock
		var sp := soldier.global_position
		if seq.beat == InvasionSequence.Beat.LINGER:
			off_post = maxf(off_post, Vector2(sp.x - leave.x, sp.z - leave.z).length())
			var want := atan2(-(front.x - sp.x), -(front.z - sp.z))
			var off := wrapf(soldier.rotation.y - want, -PI, PI)
			turned = turned or absf(off) < deg_to_rad(15.0)
			if turned:
				off_face = maxf(off_face, absf(off))
				linger_swing[0] = minf(linger_swing[0], off)
				linger_swing[1] = maxf(linger_swing[1], off)
		elif seq.beat == InvasionSequence.Beat.RETURN:
			var dp := dog.global_position
			if absf(dp.x) < 2.7 and dp.z > 3.9 and dp.z < 8.2:
				dog_in = true
			if not took_dog_at.is_finite() and dog.handler == soldier:
				took_dog_at = sp
			if seq._leg == InvasionSequence.Leg.LOOK \
					and Vector2(sp.x - look_at.x, sp.z - look_at.z).length() < 0.6:
				looked += step
				var rel := wrapf(soldier.rotation.y - face_look, -PI, PI)
				swing[0] = minf(swing[0], rel)
				swing[1] = maxf(swing[1], rel)
	Engine.time_scale = 1.0
	Sfx.played.disconnect(on_sound)
	var at_escape := soldier.global_position
	var order := [InvasionSequence.Beat.PROLOGUE, InvasionSequence.Beat.INVASION, InvasionSequence.Beat.KNOCK,
			InvasionSequence.Beat.SEARCH, InvasionSequence.Beat.LEAVE, InvasionSequence.Beat.LINGER,
			InvasionSequence.Beat.RETURN, InvasionSequence.Beat.ESCAPE]
	check(beats == order, "after the search he leaves, lingers, comes back, and only then the escape", beats)
	var lingered := float(stamps.get(InvasionSequence.Beat.RETURN, 0.0)) - float(stamps.get(InvasionSequence.Beat.LINGER, 0.0))
	check(lingered > seq.linger_time - 0.2 and off_post < 0.6,
			"he lingers behind the corner by the leave point for linger_time", [lingered, off_post])
	check(turned and off_face < deg_to_rad(30.0) and linger_swing[0] < deg_to_rad(-10.0) \
			and linger_swing[1] > deg_to_rad(10.0),
			"facing the yard before the door, the torch swinging a little both ways",
			[turned, rad_to_deg(off_face), rad_to_deg(linger_swing[0]), rad_to_deg(linger_swing[1])])
	check(sniffs.keys() == [InvasionSequence.Beat.LINGER] and int(sniffs[InvasionSequence.Beat.LINGER]) >= 2,
			"the dog sniffs while he lingers, and only then", sniffs)
	check(heard[1] >= 2 and heard[0] == heard[1],
			"in the cellar he hears it, muffled: through the wall, and within its reach", heard)
	check(looked > seq.look_back_time * 0.8 and swing[0] < deg_to_rad(-40.0) and swing[1] > deg_to_rad(40.0) \
			and swing[1] - swing[0] < deg_to_rad(150.0) and absf(swing[0] + swing[1]) * 0.5 < deg_to_rad(20.0),
			"he comes back to the middle of the room and looks round it, both ways, facing the table",
			[looked, rad_to_deg(swing[0]), rad_to_deg(swing[1])])
	check(not dog_in and took_dog_at.is_finite() and took_dog_at.z < 3.7,
			"the dog stays on the threshold while he is back in the izba; he takes it on his way out, past the threshold",
			[dog_in, took_dog_at])
	check(seq.beat == InvasionSequence.Beat.ESCAPE and Vector2(at_escape.x - leave.x, at_escape.z - leave.z).length() < 0.6
			and not soldier.hold_position and dog.handler == soldier and not dog.hold_position,
			"then round the corner again with the dog, and back on his round from there",
			[seq.beat, at_escape, soldier.hold_position, dog.handler])
	check(player.is_hidden and not soldier._caught and not dog._caught,
			"the boy in the cellar is not found", [soldier._caught, dog._caught])
	level.queue_free()
	await frames(2)


## Out too soon (docs/ARCHITECTURE.md, "Ложный уход"), the dog's nose, eyes
## and ears off (from the threshold it sees into the room itself): the
## soldier's eyes must do it. Who climbs out while the soldier stands
## behind the corner and stays in the room is caught when he looks back in,
## not before - the corner hides the room - wherever in the room he stands:
## by the hatch, where the cellar lets out; by the stove, where the gap
## behind it lets out; in the corner by the door, hidden from the threshold
## by the kicked-in leaf; by the west window; by the east wall between the
## door and the stove. Who steps out of the door then is seen from the
## corner. Who is out and back in the cellar before he comes is not found.
func _test_invasion_out_too_early() -> void:
	var spots := {
		"by the hatch": Vector3(-0.8, 0, 6.5),
		"by the stove": Vector3(0.7, 0, 7.8),
		"in the corner by the door": Vector3(-2.3, 0, 4.0),
		"by the west window": Vector3(-2.4, 0, 6.4),
		"by the east wall": Vector3(2.4, 0, 5.2),
	}
	for spot: String in spots:
		var room := await _out_while_lingering(spots[spot])
		check(int(room.caught_in) == InvasionSequence.Beat.RETURN and room.by == "soldier"
				and int(room.up_in) == InvasionSequence.Beat.RETURN and room.up_by == "soldier",
				"out in the room (%s) while he lingers: the soldier sees him when he looks back in, not before" % spot, room)
	var yard := await _out_while_lingering(Vector3(1.5, 0, 2.6))
	check(int(yard.caught_in) == InvasionSequence.Beat.LINGER and yard.up_by == "soldier",
			"out of the door while he lingers: the soldier sees him from the corner, and he is caught", yard)
	var back := await _out_while_lingering(Vector3.INF, 1.5)
	check(int(back.caught_in) < 0 and int(back.up_in) < 0 and int(back.beat) == InvasionSequence.Beat.ESCAPE
			and back.hidden,
			"out of the cellar and back in before he comes back: not found", back)


## The opening till the boy is caught or the escape; he sits in the cellar
## and is let out (eject: no sound) half a second into LINGER, then put at
## `at` (in the room or in the yard before the door; INF: left by the hatch).
## With `back_after` he is let in again (admit: no sound) that many seconds
## after he was let out. The dog's nose, eyes and ears are off. up_in, up_by: the beat when
## the soldier or the dog first stopped patrolling after he was out, and
## which; caught_in, by: the beat he was caught in, and by whom; hidden: in
## the cellar at the end.
func _out_while_lingering(at: Vector3, back_after := -1.0) -> Dictionary:
	PanicSystem.reset()
	Perception.reset()
	var level := LEVEL.instantiate()
	var seq := level.get_node("Invasion") as InvasionSequence
	seq.prologue_time = 1.0
	seq.warning_time = 1.0
	seq.search_time = 1.0
	seq.linger_time = 4.0
	add_child(level)
	level._ending = true
	var player := level.get_node("Player") as Player
	player.get_node("BreathControl").set_physics_process(false)
	var soldier := level.get_node("SoldierRoad") as Enemy
	var dog := level.get_node("Shepherd") as Dog
	dog.smell_radius = 0.0
	dog.trail_pickup_radius = 0.0
	dog.view_distance = 0.0
	dog.hearing = 0.0
	var hatch := level.get_node("IzbaA/CellarHatch") as HideSpot
	await frames(3)
	player.global_position = Vector3(-1.0, 0, 6.3)  # north of the table, in the lamp's light
	player.velocity = Vector3.ZERO
	await frames(2)
	hatch.admit(player)
	var got := {"caught_in": -1, "by": "", "up_in": -1, "up_by": "", "out": false, "at": Vector3.ZERO,
			"back": false, "hidden": false}
	var on_caught := func(_e: Enemy, who: String) -> void:
		if int(got.caught_in) < 0:
			got["caught_in"] = seq.beat
			got["by"] = who
	soldier.player_caught.connect(on_caught.bind("soldier"))
	dog.player_caught.connect(on_caught.bind("dog"))
	var linger_from := -1.0
	var out_at := -1.0
	Engine.time_scale = 4.0
	var t0 := Time.get_ticks_msec()
	while int(got.caught_in) < 0 and seq.beat != InvasionSequence.Beat.ESCAPE \
			and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().physics_frame
		if seq.beat == InvasionSequence.Beat.LINGER and linger_from < 0.0:
			linger_from = Stealth.clock
		if not got.out and linger_from >= 0.0 and Stealth.clock - linger_from > 0.5:
			hatch.eject(player)
			if at.is_finite():
				player.global_position = at
				player.velocity = Vector3.ZERO
			got["out"] = true
			got["at"] = player.global_position
			out_at = Stealth.clock
		if got.out and not got.back and back_after >= 0.0 and Stealth.clock - out_at > back_after:
			hatch.admit(player)
			got["back"] = true
		if got.out and int(got.up_in) < 0 \
				and (soldier.state != Enemy.State.PATROL or dog.state != Enemy.State.PATROL):
			got["up_in"] = seq.beat
			got["up_by"] = "soldier" if soldier.state != Enemy.State.PATROL else "dog"
	Engine.time_scale = 1.0
	got["beat"] = seq.beat
	got["hidden"] = player.is_hidden
	level.queue_free()
	await frames(2)
	return got


## The same opening, but the player stays standing in the izba: found.
func _test_invasion_found() -> void:
	PanicSystem.reset()
	Perception.reset()
	var level := LEVEL.instantiate()
	var seq := level.get_node("Invasion") as InvasionSequence
	seq.prologue_time = 1.0
	seq.warning_time = 1.0
	seq.search_time = 3.0
	add_child(level)
	level._ending = true
	var player := level.get_node("Player") as Player
	player.get_node("BreathControl").set_physics_process(false)
	var soldier := level.get_node("SoldierRoad") as Enemy
	var caught_in := [-1]
	soldier.player_caught.connect(func(_e: Enemy) -> void:
		if caught_in[0] < 0:
			caught_in[0] = seq.beat)
	await frames(3)
	player.global_position = Vector3(-2.2, 0, 7.6)  # far corner, past the table
	Engine.time_scale = 4.0
	var t0 := Time.get_ticks_msec()
	while not soldier._caught and seq.beat != InvasionSequence.Beat.ESCAPE 			and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().physics_frame
	Engine.time_scale = 1.0
	check(soldier._caught and caught_in[0] == InvasionSequence.Beat.SEARCH,
			"a player who did not hide is found in the search (not later, when he looks back in)", [caught_in[0], seq.beat, soldier.state, soldier.global_position, soldier.suspicion, player.global_position, Time.get_ticks_msec() - t0])
	level.queue_free()
	await frames(2)


## The same opening with the boy standing behind the door when it is kicked
## in (docs/ARCHITECTURE.md, "Дверь избы", "Удар вышибленной створки"): the
## leaf strikes him, and the soldier at the door hears his gasp - suspicious
## at once, the sound where the boy is - and finds him. The dog's nose is
## off here: the gasp alone gives him away.
func _test_invasion_behind_door() -> void:
	var got := await _invasion_at_door(false)
	check(int(got.kicks) == 1 and int(got.kicker_state) == Enemy.State.PATROL
			and int(got.kick_beat) == InvasionSequence.Beat.KNOCK and float(got.timer_left) <= 0.0
			and int(got.hits) == 1 and int(got.gasps) == 1 and got.by_gasp
			and float(got.suspicion) >= Enemy.SUSPICIOUS_AT,
			"standing behind the door when it is kicked in, he is struck, and the soldier at the door hears his gasp: suspicious at once", got)
	check(got.caught, "and he is found", got)


## The dog at the door smells him behind it before the kick: the soldier,
## called by its bark, kicks the door in - he does not walk through it, nor
## does the dog (docs/ARCHITECTURE.md, "Дверь избы").
func _test_invasion_dog_at_door() -> void:
	var got := await _invasion_at_door(true)
	check(not got.ghost and not got.dog_ghost,
			"a soldier or a dog never walks through the shut door of the izba", got)
	check(int(got.kicks) == 1 and int(got.kicker_state) != Enemy.State.PATROL and int(got.hits) == 1
			and (int(got.kick_beat) == InvasionSequence.Beat.INVASION
				or (int(got.kick_beat) == InvasionSequence.Beat.KNOCK and float(got.timer_left) > 0.0)),
			"the dog smells the boy behind the shut door: the soldier comes to its bark and kicks the door in at once, not on his beat, and the leaf strikes him", got)
	check(got.released, "kicked in, the door is held shut by the story no more", got)
	check(got.caught, "and he is found", got)


## The invasion in fast-forward with the boy standing behind the shut door
## (0.95 m along it from the hinge, 0.95 m in: clear of the wall, in the
## leaf's way), the dog's nose on or off. Returns: kicks - door_kick sounds;
## kicker_state - the soldier's state when the door opened; hits - door_hit
## sounds; at his loud gasp: gasps, the soldier's suspicion, by_gasp - the
## sound he goes by is the gasp; when the door opened: kick_beat, timer_left
## (of the beat), released (enemies_can_open); ghost / dog_ghost - past the
## door's line into the izba while its door is shut; caught - found by the
## soldier or the dog.
func _invasion_at_door(nose: bool) -> Dictionary:
	PanicSystem.reset()
	Perception.reset()
	var level := LEVEL.instantiate()
	var seq := level.get_node("Invasion") as InvasionSequence
	seq.prologue_time = 1.0
	seq.warning_time = 1.0
	seq.search_time = 3.0
	add_child(level)
	level._ending = true
	var player := level.get_node("Player") as Player
	player.get_node("BreathControl").set_physics_process(false)
	var soldier := level.get_node("SoldierRoad") as Enemy
	var dog := level.get_node("Shepherd") as Dog
	var door := level.get_node("IzbaDoor") as IzbaDoor
	if not nose:
		dog.smell_radius = 0.0
		dog.trail_pickup_radius = 0.0
	await frames(3)
	var got := {"kicks": 0, "kicker_state": -1, "kick_beat": -1, "timer_left": 0.0, "released": false, "hits": 0, "gasps": 0, "suspicion": 0.0, "by_gasp": false,
			"ghost": false, "dog_ghost": false, "caught": false}
	var on_sound := func(id: String, _p: AudioStreamPlayer3D) -> void:
		if id == "door_hit":
			got["hits"] += 1
		elif id == "door_kick":
			got["kicks"] += 1
	var on_noise := func(pos: Vector3, loud: float, src: Node) -> void:
		if src == player and loud > 0.99:
			got["gasps"] += 1
			got["suspicion"] = soldier.suspicion
			got["by_gasp"] = soldier.last_known.distance_to(pos) < 0.01
	var on_opened := func() -> void:
		got["kicker_state"] = soldier.state
		got["kick_beat"] = seq.beat
		got["timer_left"] = seq._timer
		got["released"] = door.enemies_can_open
	Sfx.played.connect(on_sound)
	Stealth.noise_emitted.connect(on_noise)
	door.opened.connect(on_opened)
	player.global_position = door.global_transform * Vector3(0.95, 0, 0.95)
	player.velocity = Vector3.ZERO
	await frames(3)
	got["placed"] = player.global_position
	var line := door.global_position.z + 0.05  # the shut leaf's inner face
	var in_izba := func(at: Vector3) -> bool: return absf(at.x) < 2.7 and at.z > line and at.z < 8.2
	Engine.time_scale = 4.0
	var t0 := Time.get_ticks_msec()
	while not soldier._caught and not dog._caught and seq.beat != InvasionSequence.Beat.ESCAPE \
			and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().physics_frame
		if not door.is_open:
			got["ghost"] = got.ghost or in_izba.call(soldier.global_position)
			got["dog_ghost"] = got.dog_ghost or in_izba.call(dog.global_position)
	Engine.time_scale = 1.0
	Sfx.played.disconnect(on_sound)
	Stealth.noise_emitted.disconnect(on_noise)
	got["caught"] = soldier._caught or dog._caught
	got["beat"] = seq.beat
	got["boy"] = player.global_position
	level.queue_free()
	await frames(2)
	return got


## The soldier's torch shines through the cellar boards: light in the gaps
## and panic, but no detection by itself.
func _test_torch_leak() -> void:
	PanicSystem.reset()
	var level := LEVEL.instantiate()
	level.play_intro = false
	add_child(level)
	level._ending = true
	await frames(3)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set_physics_process(false)
	var player := level.get_node("Player") as Player
	player.get_node("BreathControl").set_physics_process(false)
	var hatch := level.get_node("IzbaA/CellarHatch") as HideSpot
	hatch.interact(player)
	var soldier := level.get_node("SoldierRoad") as Enemy
	check(soldier.torch_on, "the road soldier carries a lit torch after the invasion")
	# Two metres from the hatch, facing it.
	soldier.global_position = hatch.global_position + Vector3(2.0, 0, 0)
	soldier.look_at(hatch.global_position, Vector3.UP)
	soldier.rotation.x = 0.0
	soldier.rotation.z = 0.0
	await frames(30)
	check(soldier.torch_light_at(hatch.global_position + Vector3.UP * 0.15) > 0.1,
			"the beam reaches the hatch", soldier.torch_light_at(hatch.global_position + Vector3.UP * 0.15))
	check(player.torch_leak > 0.5, "light comes through the gaps", player.torch_leak)
	check(PanicSystem.level > 0.1, "the light over the hatch frightens", PanicSystem.level)
	check(not soldier._caught, "light alone does not find the boy")
	soldier.rotate_y(PI)
	await frames(40)
	check(player.torch_leak < 0.05, "the gaps go dark when the beam turns away", player.torch_leak)
	soldier.global_position = hatch.global_position + Vector3(0, 0, -6.0)  # outside, behind the wall
	soldier.look_at(hatch.global_position, Vector3.UP)
	soldier.rotation.x = 0.0
	await frames(40)
	check(player.torch_leak < 0.05, "walls stop the beam", player.torch_leak)
	hatch.interact(player)
	level.queue_free()
	await frames(2)


const ENEMY_SCENE := preload("res://src/ai/enemy.tscn")
const WARDROBE := preload("res://src/interaction/wardrobe_hide.tscn")
const STOVE_NOOK := preload("res://src/interaction/stove_nook.tscn")
const CELLAR := preload("res://src/interaction/cellar_hatch.tscn")


## A bare floor with a wardrobe (door to -Z) at the origin, a cellar hatch
## and a stove nook further along, the player and one soldier. No navmesh:
## the soldier walks straight.
func _search_world() -> Dictionary:
	Stealth.reset_cover()
	var root := Node3D.new()
	var ground := CSGBox3D.new()
	ground.size = Vector3(40, 1, 40)
	ground.position = Vector3(0, -0.5, 0)
	ground.use_collision = true
	root.add_child(ground)
	var wardrobe := WARDROBE.instantiate() as HideSpot
	root.add_child(wardrobe)
	var hatch := CELLAR.instantiate() as HideSpot
	hatch.position = Vector3(5, 0, -1.2)
	root.add_child(hatch)
	var nook := STOVE_NOOK.instantiate() as HideSpot
	nook.position = Vector3(10, 0, 0)  # opening to -Z, like the wardrobe
	root.add_child(nook)
	var player := PLAYER_SCENE.instantiate() as Player
	player.position = Vector3(-15, 0, 15)  # out of sight
	root.add_child(player)
	var soldier := ENEMY_SCENE.instantiate() as Enemy
	soldier.position = Vector3(-6, 0, -1.2)
	soldier.hold_position = true
	soldier.walk_speed = 2.5
	root.add_child(soldier)
	add_child(root)
	await frames(3)
	soldier.nav_agent = null  # straight lines on the bare floor
	player.get_node("BreathControl").set_physics_process(false)
	return {"root": root, "wardrobe": wardrobe, "hatch": hatch, "nook": nook,
			"player": player, "soldier": soldier}


## Walk the soldier along `points` until he is done or has caught someone.
func _walk(soldier: Enemy, points: Array[Vector3]) -> void:
	soldier.script_goto(points)
	Engine.time_scale = 3.0
	var t0 := Time.get_ticks_msec()
	while (soldier.has_script_route() or soldier.is_inspecting()) and not soldier._caught \
			and Time.get_ticks_msec() - t0 < 15000:
		await get_tree().physics_frame
	Engine.time_scale = 1.0


## Obvious hiding places (HideSpot.search_check): a calm patrol walks past,
## a searcher looks in; the cellar is not looked into; walls and the back
## of a wardrobe block the look; a lost boy's last place is checked first;
## behind the stove a breath is heard where the cellar swallows it.
func _test_search_checks() -> void:
	PanicSystem.reset()
	var past: Array[Vector3] = [Vector3(14, 0, -1.2)]

	# A calm patrol passes the wardrobe with the boy inside.
	var w := await _search_world()
	var wardrobe := w.wardrobe as HideSpot
	var soldier := w.soldier as Enemy
	check(wardrobe.is_in_group("hide_spots") and wardrobe.search_check == HideSpot.SearchCheck.OPEN,
			"the wardrobe is a hiding place that gets opened")
	check((w.hatch as HideSpot).search_check == HideSpot.SearchCheck.NONE,
			"the cellar is not an obvious place")
	wardrobe.interact(w.player)
	var opened := [0]
	wardrobe.searched.connect(func(_by: Node) -> void: opened[0] += 1)
	await _walk(soldier, past)
	check(not soldier._caught and not wardrobe.is_open and opened[0] == 0,
			"a calm patrol walks past a wardrobe without opening it", [soldier._caught, wardrobe.is_open])
	(w.root as Node).queue_free()
	await frames(2)

	# A searcher opens an empty wardrobe, looks, and goes on.
	w = await _search_world()
	wardrobe = w.wardrobe as HideSpot
	soldier = w.soldier as Enemy
	soldier.searches_hiding_spots = true
	var t0 := Time.get_ticks_msec()
	await _walk(soldier, past)
	check(wardrobe.is_open and not soldier._caught, "a searcher opens an empty wardrobe and finds nothing")
	check(soldier.global_position.x > 12.0, "then he goes on along his way", soldier.global_position)
	check((wardrobe.get_node("DoorHinge") as Node3D).rotation_degrees.y > 60.0,
			"the wardrobe door stands open", (wardrobe.get_node("DoorHinge") as Node3D).rotation_degrees)
	(w.root as Node).queue_free()
	await frames(2)

	# The same searcher, the boy inside: found as the door swings open.
	w = await _search_world()
	wardrobe = w.wardrobe as HideSpot
	soldier = w.soldier as Enemy
	soldier.searches_hiding_spots = true
	wardrobe.interact(w.player)
	await _walk(soldier, past)
	check(soldier._caught, "a searcher opening the wardrobe finds the boy")
	check(soldier.global_position.x < 1.5, "he found him at the wardrobe", soldier.global_position)
	(w.root as Node).queue_free()
	await frames(2)

	# Behind the wardrobe: its back blocks the look, nothing is opened.
	w = await _search_world()
	wardrobe = w.wardrobe as HideSpot
	soldier = w.soldier as Enemy
	soldier.searches_hiding_spots = true
	soldier.global_position = Vector3(-6, 0, 0.9)
	wardrobe.interact(w.player)
	await _walk(soldier, [Vector3(6, 0, 0.9)] as Array[Vector3])
	check(not soldier._caught and not wardrobe.is_open, "a searcher behind the wardrobe does not open it")
	(w.root as Node).queue_free()
	await frames(2)

	# The cellar: a searcher walks right over it and does not look in.
	w = await _search_world()
	var hatch := w.hatch as HideSpot
	soldier = w.soldier as Enemy
	soldier.searches_hiding_spots = true
	hatch.interact(w.player)
	var looked := [0]
	hatch.searched.connect(func(_by: Node) -> void: looked[0] += 1)
	await _walk(soldier, past)
	check(not soldier._caught and looked[0] == 0, "a searcher walks over the cellar without looking in")
	(w.root as Node).queue_free()
	await frames(2)

	# Behind the stove: he stops, shines the torch in for check_time, goes on.
	w = await _search_world()
	var nook := w.nook as HideSpot
	soldier = w.soldier as Enemy
	soldier.has_torch = true
	soldier._build_torch()
	soldier.torch_on = true
	soldier.searches_hiding_spots = true
	soldier.global_position = Vector3(6, 0, -1.4)
	nook.interact(w.player)
	var player := w.player as Player
	var leak := [0.0]
	var pitch := [0.0]
	var held := [0.0]
	var checking := [false]
	var at := [Vector3.INF]
	nook.searched.connect(func(_by: Node) -> void:
		checking[0] = true
		at[0] = soldier.global_position)
	nook.search_ended.connect(func(_by: Node) -> void: checking[0] = false)
	var on_frame := func() -> void:
		leak[0] = maxf(leak[0], player.torch_leak)
		if checking[0]:
			held[0] += Engine.time_scale / Engine.physics_ticks_per_second
			pitch[0] = minf(pitch[0], soldier.torch.rotation_degrees.x)
	get_tree().physics_frame.connect(on_frame)
	await _walk(soldier, past)
	get_tree().physics_frame.disconnect(on_frame)
	check(not soldier._caught, "a silent boy behind the stove is not found")
	check(Vector2(at[0].x - nook.stand_point().x, at[0].z - nook.stand_point().z).length() < 0.6,
			"he walks up to the opening before he looks in", [at[0], nook.stand_point()])
	check(held[0] > nook.check_time * 0.8 and held[0] < nook.check_time * 1.5,
			"the searcher stands at the stove for its check time", held[0])
	check(pitch[0] < Enemy.TORCH_PITCH - 4.0, "he points the torch down into the gap", pitch[0])
	check(leak[0] > 0.3, "the beam fills the gap", leak[0])
	check(soldier.global_position.x > 12.0, "then he goes on", soldier.global_position)
	check(absf(soldier.torch.rotation_degrees.x - Enemy.TORCH_PITCH) < 3.0,
			"his torch comes back up", soldier.torch.rotation_degrees.x)
	(w.root as Node).queue_free()
	await frames(2)

	# One exhale while he stands at the place: behind the stove it is heard,
	# under the floor it is not.
	for case in [["nook", true], ["hatch", false]]:
		w = await _search_world()
		var spot := w[case[0]] as HideSpot
		soldier = w.soldier as Enemy
		soldier.set_physics_process(false)
		soldier.global_position = spot.check_point() + Vector3(0, 0, -1.2)
		soldier.global_position.y = 0.0
		spot.interact(w.player)
		await frames(2)
		(w.player as Player).get_node("BreathControl")._make_sound("exhale", 0.45)
		check(soldier._caught == case[1], "an exhale next to the searcher: %s -> found %s" % case,
				soldier._caught)
		(w.root as Node).queue_free()
		await frames(2)

	# The boy is lost near the wardrobe: the soldier walks up to it and opens it.
	w = await _search_world()
	wardrobe = w.wardrobe as HideSpot
	soldier = w.soldier as Enemy
	soldier.hold_position = false
	soldier.global_position = Vector3(-6, 0, -3.0)
	wardrobe.interact(w.player)
	soldier.alert_to(Vector3(2.5, 0, -2.5), 0.5)
	Engine.time_scale = 3.0
	t0 = Time.get_ticks_msec()
	while not soldier._caught and Time.get_ticks_msec() - t0 < 15000:
		await get_tree().physics_frame
	Engine.time_scale = 1.0
	check(soldier._caught and wardrobe.is_open,
			"where the boy was lost, the wardrobe close by is opened", [soldier.state, soldier.global_position])
	(w.root as Node).queue_free()
	await frames(2)

	var dog := (load("res://src/ai/dog.tscn") as PackedScene).instantiate() as Dog
	check(not dog.checks_hiding_spots(), "a dog does not open wardrobes")
	dog.free()


## The invasion with the boy behind the stove, silent: the soldier comes to
## the stove, shines his torch into the gap and leaves.
func _test_invasion_stove_nook() -> void:
	PanicSystem.reset()
	Perception.reset()
	var level := LEVEL.instantiate()
	var seq := level.get_node("Invasion") as InvasionSequence
	seq.prologue_time = 1.0
	seq.warning_time = 2.0
	seq.search_time = 1.5
	add_child(level)
	level._ending = true
	var player := level.get_node("Player") as Player
	player.get_node("BreathControl").set_physics_process(false)
	var soldier := level.get_node("SoldierRoad") as Enemy
	var nook := level.get_node("IzbaA/StoveNook") as HideSpot
	var hatch := level.get_node("IzbaA/CellarHatch") as HideSpot
	var by: Array[Node] = []
	nook.searched.connect(func(n: Node) -> void: by.append(n))
	await frames(3)
	check(nook.search_check == HideSpot.SearchCheck.LOOK and hatch.search_check == HideSpot.SearchCheck.NONE,
			"behind the stove is looked into, the cellar is not")
	nook.interact(player)
	check(player.is_hidden, "the boy squeezes in behind the stove")
	Engine.time_scale = 4.0
	var t0 := Time.get_ticks_msec()
	var leak := 0.0
	var searching_seen := false
	var dog_inside := false
	while seq.beat != InvasionSequence.Beat.ESCAPE and Time.get_ticks_msec() - t0 < 60000 \
			and not soldier._caught:
		await get_tree().physics_frame
		leak = maxf(leak, player.torch_leak)
		if seq.beat == InvasionSequence.Beat.SEARCH or seq.beat == InvasionSequence.Beat.RETURN:
			searching_seen = searching_seen or soldier.searches_hiding_spots
			var dp := (level.get_node("Shepherd") as Dog).global_position
			if absf(dp.x) < 2.7 and dp.z > 3.9 and dp.z < 8.2:
				dog_inside = true
	Engine.time_scale = 1.0
	check(searching_seen, "the search is a house search")
	check(not dog_inside, "the dog is left on the threshold while the izba is searched, and when he looks back in")
	check((level.get_node("Shepherd") as Dog).handler == soldier, "and goes with its handler again after")
	check(by.has(soldier), "the soldier looks behind the stove", by)
	check(leak > 0.3, "his torch shines into the gap", leak)
	var dog := level.get_node("Shepherd") as Dog
	check(not soldier._caught, "a silent boy behind the stove is not found",
			[dog.barks, dog._caught, soldier.state, soldier.global_position, seq.beat, by.size()])
	check(seq.beat == InvasionSequence.Beat.ESCAPE and not soldier.searches_hiding_spots,
			"they leave, and the search is over", [seq.beat, soldier.searches_hiding_spots])
	level.queue_free()
	await frames(2)


## Distant gunfire (spec 2: panic "при громких выстрелах"): off-screen
## shots jolt the panic, nearer more, a burst more than a shot; the boy
## flinches; nothing in a safe zone or in the Act I prologue; enemies do not
## react; Act II has it from the start.
## Footsteps and gait (src/ai/gait.gd): limbs swing only while walking,
## footfalls are heard by distance walked, boots knock on boards and creak,
## a dog pads, the boy's own enemies do not take them for his noise; over
## the cellar the boards shed dust on him.
func _test_footsteps() -> void:
	PanicSystem.reset()
	var w := await _search_world()
	var soldier := w.soldier as Enemy
	var player := w.player as Player
	var hatch := w.hatch as HideSpot
	var boards := BoardFloor.new()
	boards.size = Vector3(4, 1, 4)
	boards.position = hatch.position
	(w.root as Node3D).add_child(boards)
	var gait := soldier.gait
	var leg_l := soldier.visual.get_node("LegL") as Node3D
	var leg_r := soldier.visual.get_node("LegR") as Node3D
	var arm_l := soldier.visual.get_node("ArmL") as Node3D
	var band := soldier.visual.get_node("Armband") as Node3D
	var rest_l := leg_l.transform
	check(gait != null and gait.body == Gait.Body.HUMAN, "a soldier walks on two legs")
	check(BoardFloor.at(get_tree(), hatch.global_position + Vector3.UP * 0.05) == boards
			and BoardFloor.at(get_tree(), Vector3(-6, 0.05, -1.2)) == null,
			"boards are found under the hatch, earth elsewhere")

	var sounds: Array[String] = []
	var on_sound := func(id: String, _p: AudioStreamPlayer3D) -> void: sounds.append(id)
	Sfx.played.connect(on_sound)
	var noises := [0]
	var on_noise := func(_pos: Vector3, _l: float, src: Node) -> void:
		if src != player:
			noises[0] += 1
	Stealth.noise_emitted.connect(on_noise)

	await _wait(0.5)
	check(gait.steps == 0 and gait.swing == 0.0 and leg_l.transform.is_equal_approx(rest_l),
			"standing at his post: no steps, legs at rest", [gait.steps, gait.swing])

	# Walking on earth: legs swing both ways and against each other, the left
	# arm against the left leg, the armband with the arm.
	var lo := 0.0
	var hi := 0.0
	var against := true
	var band_follows := true
	soldier.script_goto([Vector3(-1, 0, -1.2)] as Array[Vector3])
	Engine.time_scale = 3.0
	var t0 := Time.get_ticks_msec()
	while soldier.has_script_route() and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().physics_frame
		var a := leg_l.rotation.x
		lo = minf(lo, a)
		hi = maxf(hi, a)
		if absf(a) > 0.1:
			against = against and signf(leg_r.rotation.x) == -signf(a) and signf(arm_l.rotation.x) == -signf(a)
			band_follows = band_follows and absf(band.rotation.x - arm_l.rotation.x) < 0.01
	Engine.time_scale = 1.0
	check(lo < -0.15 and hi > 0.15, "walking, his legs swing forward and back", [lo, hi])
	check(against, "one leg forward, the other back; the arm swings against the leg")
	check(band_follows, "the armband swings with the left sleeve")
	var walked := gait.steps
	check(walked >= 5 and walked <= 9, "about one footfall every 0.7 m (5 m walked)", walked)
	check(sounds.count("step_boot") == walked and not sounds.has("step_boot_board"),
			"every footfall is heard: boots on earth", [sounds.count("step_boot"), walked])
	check(noises[0] == 0, "his own steps are not the boy's noise for the others", noises[0])
	await _wait(1.5)
	check(gait.swing == 0.0 and leg_l.transform.is_equal_approx(rest_l), "he stops: the legs come to rest")

	# Running strides are longer than walking ones.
	var before := gait.steps
	soldier.walk_speed = 3.4
	soldier.global_position = Vector3(-6, 0, 4)
	await frames(2)
	soldier.script_goto([Vector3(-1, 0, 4)] as Array[Vector3])
	Engine.time_scale = 3.0
	t0 = Time.get_ticks_msec()
	while soldier.has_script_route() and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().physics_frame
	Engine.time_scale = 1.0
	soldier.walk_speed = 2.5
	check(gait.steps - before < walked, "running, he takes fewer, longer steps", [gait.steps - before, walked])
	await _wait(1.0)

	# On boards over the cellar, with the boy below: a hollow knock, a creak
	# now and then, dust through the gaps, a flinch. The cellar is not
	# searched, he is not found.
	soldier.global_position = Vector3(1.5, 0, -1.2)
	await frames(2)
	hatch.admit(player)  # set-up: the lid's own noise would bring him to stand over it
	sounds.clear()
	PanicSystem.level = 0.0
	soldier.script_goto([Vector3(8.5, 0, -1.2)] as Array[Vector3])
	var dip := 0.0
	var dust := 0.0
	t0 = Time.get_ticks_msec()
	while soldier.has_script_route() and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
		dip = minf(dip, player.camera.v_offset)
		dust = maxf(dust, player.dust)
	check(sounds.has("step_boot_board") and sounds.has("step_boot"),
			"boots knock on the boards and thud on the earth past them", sounds)
	check(player.dust_falls > 0 and dust > 0.4, "boots right overhead shake dust down on him",
			[player.dust_falls, dust])
	check(dip < -0.01 and PanicSystem.level > 0.0, "he flinches, his heart jumps", [dip, PanicSystem.level])
	var mat := player.hide_overlay.material as ShaderMaterial
	check(float(mat.get_shader_parameter("dust")) > 0.0 or player.dust == 0.0,
			"the dust is drawn in the gaps")
	check(not soldier._caught, "the cellar is not searched: he is not found")
	await _wait(Player.DUST_FADE + 0.5)
	check(player.dust == 0.0, "the dust settles")

	# Boards two metres from the hatch: no dust on him.
	var falls := player.dust_falls
	soldier.global_position = Vector3(3.3, 0, 0.6)
	await frames(2)
	soldier.script_goto([Vector3(6.7, 0, 0.6)] as Array[Vector3])
	t0 = Time.get_ticks_msec()
	while soldier.has_script_route() and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().physics_frame
	check(player.dust_falls == falls, "steps on the boards further off shake nothing down", player.dust_falls - falls)
	hatch.interact(player)
	(w.wardrobe as HideSpot).interact(player)
	player.boards_overhead((w.wardrobe as HideSpot).global_position, 1.0)
	check(player.dust_falls == falls, "nothing falls in a wardrobe: it is not under the floor")
	(w.wardrobe as HideSpot).interact(player)

	# A figure moved by hand (the dream) walks too; a teleport is no step.
	soldier.passive = true
	before = gait.steps
	for i in 60:
		soldier.global_position += Vector3(0, 0, 0.05)
		await get_tree().physics_frame
	check(gait.steps - before >= 3, "a figure moved by the scene walks too", gait.steps - before)
	before = gait.steps
	soldier.global_position += Vector3(6, 0, 0)
	for i in 10:
		await get_tree().physics_frame
	check(gait.steps == before, "a jump is not a step")
	# Far from the boy: counted, not played.
	soldier.global_position = Vector3(19, 0, -14)  # 34+ m from the boy
	player.global_position = Vector3(-15, 0, 15)
	await frames(3)
	sounds.clear()
	before = gait.steps
	for i in 60:
		soldier.global_position += Vector3(0, 0, 0.05)
		await get_tree().physics_frame
	check(gait.steps > before and not sounds.has("step_boot"),
			"steps too far to hear play nothing", [gait.steps - before, sounds])
	soldier.passive = false

	# A dog pads on four legs, diagonal pairs together.
	var dog := (load("res://src/ai/dog.tscn") as PackedScene).instantiate() as Dog
	dog.position = Vector3(-6, 0, 6)
	dog.hold_position = true
	(w.root as Node3D).add_child(dog)
	await frames(3)
	dog.nav_agent = null
	sounds.clear()
	var fl := dog.visual.get_node("LegFL") as Node3D
	var br := dog.visual.get_node("LegBR") as Node3D
	var fr := dog.visual.get_node("LegFR") as Node3D
	var trot := true
	dog.script_goto([Vector3(-2, 0, 6)] as Array[Vector3])
	t0 = Time.get_ticks_msec()
	while dog.has_script_route() and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().physics_frame
		if absf(fl.rotation.x) > 0.1:
			trot = trot and absf(fl.rotation.x - br.rotation.x) < 0.01 and signf(fr.rotation.x) == -signf(fl.rotation.x)
	check(dog.gait.body == Gait.Body.DOG and dog.gait.steps > 0 and trot, "the dog trots on four legs", dog.gait.steps)
	check(sounds.has("step_paw") and not sounds.has("step_boot"), "its paws are heard, not boots", sounds)
	Sfx.played.disconnect(on_sound)
	Stealth.noise_emitted.disconnect(on_noise)
	(w.root as Node).queue_free()
	await frames(2)

	# Where the floors are boards: the izba of Act I over the cellar and
	# behind the stove, not the street.
	var level := LEVEL.instantiate()
	level.play_intro = false
	add_child(level)
	level._ending = true
	await frames(3)
	var izba_hatch := level.get_node("IzbaA/CellarHatch") as HideSpot
	var izba_nook := level.get_node("IzbaA/StoveNook") as HideSpot
	check(izba_hatch.under_floor and BoardFloor.at(get_tree(), izba_hatch.global_position + Vector3.UP * 0.05) != null,
			"Act I: the izba floor is boards over the cellar")
	check(BoardFloor.at(get_tree(), izba_nook.stand_point() + Vector3.UP * 0.05) != null
			and BoardFloor.at(get_tree(), Vector3(0, 0.05, 0)) == null,
			"boards in front of the stove, earth on the street")
	level.queue_free()
	await frames(2)


## How the world sounds from a hiding place (Sfx.set_muffle: the World bus
## through a low-pass) and the wind outside (AmbienceBed).
# --- capture ---------------------------------------------------------------------

## The camera looks at `point` within `tolerance` (dot of the directions;
## 0.95 - about 18 degrees: a face held in the upper part of the view).
func _looks_at(player: Player, point: Vector3, tolerance: float = 0.95) -> bool:
	var fwd := -player.camera.global_transform.basis.z
	return fwd.dot((point - player.camera.global_position).normalized()) > tolerance


func _test_capture() -> void:
	var sounds := {}
	var on_sound := func(id: String, p: AudioStreamPlayer3D) -> void: sounds[id] = p.bus
	var w := await _search_world()
	var player := w.player as Player
	var soldier := w.soldier as Enemy
	var hatch := w.hatch as HideSpot
	soldier.set_physics_process(false)
	soldier.has_torch = true
	soldier._build_torch()
	soldier.torch_on = true
	player.global_position = hatch.global_position + Vector3(0, 0, 1.2)
	await frames(2)
	hatch.interact(player)
	await frames(2)
	# He stands beside the hatch with his back to the boy.
	soldier.global_position = hatch.global_position + Vector3(-1.1, 0, 0.6)
	soldier.rotation.y = PI * 0.5
	soldier.set_physics_process(true)
	PanicSystem.reset()
	Sfx.played.connect(on_sound)
	soldier._catch()
	player.seized_by(soldier)
	await frames(1)
	Sfx.played.disconnect(on_sound)
	check(player.seized and not player.is_hidden and hatch.occupant == null
			and not player.hide_overlay.visible,
			"caught in the cellar: he is pulled out", player.is_hidden)
	check(sounds.get("seize_grab") == "Master" and sounds.get("breath_gasp") == "Master",
			"a hand at his collar and a gasp: his own body, never muffled", sounds)
	check(PanicSystem.level > 0.9, "panic at its height", PanicSystem.level)
	await _wait(0.3)
	await _passes()
	var face := Player.seize_face(soldier)
	check(_looks_at(player, face), "in a fraction of a second his head jerks round to the one who caught him",
			-player.camera.global_transform.basis.z)
	await _wait(0.3)
	# The muffle (0.35 s), the roll of the view and the fear's distortion are
	# tweens and _process: under load they come later than the wall clock.
	await _until(func() -> bool: return (not Sfx.is_muffled() and absf(player.camera.rotation.z) < 0.01
			and Perception.distortion > 0.5), 1.5)
	await _passes()
	var to_boy := player.global_position - soldier.global_position
	to_boy.y = 0.0
	check((-soldier.global_transform.basis.z).dot(to_boy.normalized()) > 0.95,
			"and that one turns to face him", soldier.rotation.y)
	check(not Sfx.is_muffled(), "out of the cellar the world is no longer muffled", Sfx.muffle_hz)
	var real_head := (soldier.get_node("Visual/Head") as Node3D).global_position
	check(Perception.distortion > 0.5 and Player.seize_face(soldier).y > real_head.y + 0.3
			and _looks_at(player, Player.seize_face(soldier)),
			"he looks up at the face his fear has stretched, not where the head really is",
			[Perception.distortion, Player.seize_face(soldier).y, real_head.y])
	check(absf(player.camera.rotation.z) < 0.01, "the jerk of the collar rolls the view and it settles",
			player.camera.rotation.z)
	var fwd := -player.camera.global_transform.basis.z
	var face_dir := (Player.seize_face(soldier) - player.camera.global_position).normalized()
	check(face_dir.y > fwd.y + 0.05, "the face hangs in the upper part of the view", [fwd, face_dir])
	check(soldier.captive_spill != null and soldier.captive_spill.light_energy > 0.5,
			"his torch on the boy throws light back up at his face",
			soldier.captive_spill.light_energy if soldier.captive_spill != null else -1.0)
	var pos := player.global_position
	var yaw := player.rotation.y
	Input.action_press("move_forward")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(300, 0)
	player._unhandled_input(motion)
	await _wait(0.3)
	Input.action_release("move_forward")
	var open_bag := InputEventAction.new()
	open_bag.action = "inventory"
	open_bag.pressed = true
	player._unhandled_input(open_bag)
	check(player.global_position.distance_to(pos) < 0.01 and absf(player.rotation.y - yaw) < 0.001
			and not player.satchel.is_open,
			"held: he can neither move, nor look away, nor open the satchel",
			[player.global_position.distance_to(pos), player.rotation.y - yaw])
	player.release()
	check(not player.is_input_locked(), "let go, he is his own again")

	# Caught by the dog: he looks down at its head.
	var dog := (load("res://src/ai/dog.tscn") as PackedScene).instantiate() as Dog
	(w.root as Node3D).add_child(dog)
	dog.global_position = player.global_position + Vector3(0, 0, -1.0)
	dog.set_physics_process(false)
	player.rotation.y = PI  # back to the dog
	player.seized_by(dog)
	await _wait(0.35)
	await _passes()
	check(_looks_at(player, Player.seize_face(dog)) and player._pitch < -0.05,
			"caught by the dog he looks down at it", player._pitch)
	player.release()
	(w.root as Node).queue_free()
	await frames(2)
	PanicSystem.reset()

	# In a level: a second face to face, then a hard cut to black and deaf
	# world; what happens to him is never shown.
	var level := LEVEL.instantiate()
	level.play_intro = false
	add_child(level)
	await frames(3)
	var lp := level.get_node("Player") as Player
	lp.get_node("BreathControl").set_physics_process(false)
	var captor: Enemy = null
	for e in get_tree().get_nodes_in_group("enemies"):
		e.process_mode = Node.PROCESS_MODE_DISABLED
		if captor == null and not (e is Dog):
			captor = e as Enemy
	level._on_caught(captor)
	await frames(2)
	check(level._ending and lp.seized and level.fade.modulate.a < 0.05,
			"caught: no fade, he is held face to face", level.fade.modulate.a)
	await _wait(LevelBase.SEIZE_HOLD - 0.35)
	check(level.fade.modulate.a < 0.05 and _looks_at(lp, Player.seize_face(captor)),
			"for about a second he sees only the one who caught him", level.fade.modulate.a)
	# The cut, waited for rather than timed (a slow frame on a busy machine
	# once left the 0.06 s muffle 90 % done at a fixed 0.6 s): the first frame
	# the screen is not clear, it is already black - no fade - and a moment
	# later the world is deaf.
	var cut_alpha := -1.0
	var t_cut := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_cut < 1500:
		await get_tree().process_frame
		if level.fade.modulate.a > 0.05:
			cut_alpha = level.fade.modulate.a
			break
	await _wait(0.3)
	var world := AudioServer.get_bus_index(Sfx.WORLD_BUS)
	check(cut_alpha >= 0.999 and level.fade.modulate.a >= 0.999 and Sfx.muffle_db <= -39.0
			and Sfx.muffle_hz <= 200.0, "then a hard cut to black: the world goes deaf",
			[cut_alpha, level.fade.modulate.a, Sfx.muffle_hz, Sfx.muffle_db])
	check(AudioServer.get_bus_volume_db(world) < -30.0 and Sfx.bus_of("breath_gasp") == "Master",
			"only his own heart and breath are left", AudioServer.get_bus_volume_db(world))
	level.queue_free()  # before the reload: the tests are the current scene
	await frames(2)
	LevelBase._resume_after_intro = false
	Sfx.set_muffle(Sfx.OPEN_AIR, 0.0, 0.0)
	PanicSystem.reset()
	Perception.reset()
	Inventory.clear()


# --- spotted ----------------------------------------------------------------------

## "Spotted" (docs/ARCHITECTURE.md, "Заметили"): an enemy who raises the
## alarm breaks into a run (a world sound, never noise for Stealth) and his
## voice slot stays silent; a moment later the boy starts - a flinch and a
## gasp only he hears. Nothing of it on suspicion, a direct grab, phantoms,
## held breath (only the flinch) or from too far; the searchlight always.
func _test_spotted() -> void:
	PanicSystem.reset()
	var heard: Array[Dictionary] = []
	var on_sound := func(id: String, p: AudioStreamPlayer3D) -> void:
		heard.append({"id": id, "bus": String(p.bus), "pos": p.global_position, "at": Stealth.clock})
	var of := func(id: String) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for e: Dictionary in heard:
			if e["id"] == id:
				out.append(e)
		return out
	var noise := [0, 0]  # his, anyone else's
	var on_noise := func(_pos: Vector3, _loud: float, source: Node) -> void:
		noise[0 if source is Player else 1] += 1
	Sfx.played.connect(on_sound)
	Stealth.noise_emitted.connect(on_noise)

	# The voices: silent slots, the policeman's his own.
	var silent := true
	for id: String in ["de_speech", "de_shout", "de_door", "polizei_speech", "polizei_shout"]:
		silent = silent and Sfx.stream_for(id) == null
	check(silent, "the voices stay silent until recorded: no placeholder, nothing like a voice")
	check(Sfx.bus_of("enemy_break_run") == Sfx.WORLD_BUS and Sfx.bus_of("breath_startle") == Sfx.BODY_BUS,
			"the run is a sound of the world (muffled in hiding, behind walls); the gasp is his own body")
	var bank = JSON.parse_string(FileAccess.get_file_as_string(Sfx.BANK_PATH))
	var run_reach := float(bank["enemy_break_run"].get("max_distance", 0.0))
	check(Player.STARTLE_RADIUS <= run_reach, "he starts only at an alarm he could hear",
			[Player.STARTLE_RADIUS, run_reach])
	# The placeholders: the run carries through a wall and lasts past a step;
	# the gasp is short and ends in silence.
	var lunge := _pcm(Sfx.stream_for("enemy_break_run") as AudioStreamWAV)
	var startle := _pcm(Sfx.stream_for("breath_startle") as AudioStreamWAV)
	var low := 0.0
	var whole := 0.0
	var y := 0.0
	var a := 1.0 - exp(-TAU * Sfx.OCCLUDED_HZ / float(Sfx.MIX_RATE))
	for x: float in lunge:
		y += (x - y) * a
		low += y * y
		whole += x * x
	var share := func(pcm: PackedFloat32Array, from: float, to: float) -> float:
		var e_all := 0.0
		var e_part := 0.0
		for i in pcm.size():
			var t := float(i) / Sfx.MIX_RATE
			e_all += pcm[i] * pcm[i]
			if t >= from and t < to:
				e_part += pcm[i] * pcm[i]
		return e_part / maxf(e_all, 1e-9)
	var lunge_len := lunge.size() / float(Sfx.MIX_RATE)
	check(lunge_len >= 0.35 and lunge_len <= 0.5 and whole > 0.0 and low / whole > 0.5,
			"the break into a run is low enough to come through a wall", [lunge_len, low / maxf(whole, 1e-9)])
	# 0.2-0.34 s: the shove and the knocks of kit have died away, only the
	# sole still grinds (4.3 % of the placeholder; a lone thud leaves ~0.1 %).
	var grind: float = share.call(lunge, 0.2, 0.34)
	check(grind >= 0.02, "and it is no single step: the sole still grinds after the shove", grind)
	check(startle.size() > 0 and startle.size() <= int(0.3 * Sfx.MIX_RATE) and absf(startle[startle.size() - 1]) < 0.01,
			"his start is a short gasp that ends in silence", startle.size())

	# Seen in the open, six metres off.
	var w := await _search_world()
	var player := w.player as Player
	var soldier := w.soldier as Enemy
	Sfx._missing.clear()
	heard.clear()
	var alarm := {"at": -1.0, "pos": Vector3.ZERO}
	var on_state := func(s: int) -> void:
		if s == Enemy.State.ALERT and float(alarm["at"]) < 0.0:
			alarm["at"] = Stealth.clock
			alarm["pos"] = soldier.global_position
	soldier.state_changed.connect(on_state)
	player.global_position = soldier.global_position + Vector3(0, 0, -6)
	noise[0] = 0
	noise[1] = 0
	await _until(func() -> bool: return soldier.state == Enemy.State.ALERT, 6.0)
	await _until(func() -> bool: return float(alarm["at"]) >= 0.0 and Stealth.clock - float(alarm["at"]) > 0.45, 3.0)
	var runs: Array[Dictionary] = of.call("enemy_break_run")
	var starts: Array[Dictionary] = of.call("breath_startle")
	var run_pos: Vector3 = runs[0]["pos"] if runs.size() == 1 else Vector3.INF
	var at_pos: Vector3 = alarm["pos"]
	check(soldier.state == Enemy.State.ALERT and runs.size() == 1 and Sfx.is_world_bus(StringName(runs[0]["bus"]))
			and Vector2(run_pos.x - at_pos.x, run_pos.z - at_pos.z).length() < 1.0,
			"he sees the boy: he breaks into a run, heard from where he is", runs)
	check(Sfx.missing_ids().has("de_shout") and not Sfx.missing_ids().has("polizei_shout"),
			"and his shout is asked for - silent until recorded", Sfx.missing_ids())
	var delay: float = float(starts[0]["at"]) - float(alarm["at"]) if starts.size() == 1 else -1.0
	check(starts.size() == 1 and starts[0]["bus"] == "Master" and delay >= 0.1 and delay <= 0.3
			and player.startles == 1,
			"a moment later the boy starts: a gasp only he hears", [starts.size(), delay, player.startles])
	check(noise[0] == 0 and noise[1] == 0, "his start and their run are no noise for the enemies", noise)
	soldier.state_changed.disconnect(on_state)
	(w.root as Node).queue_free()
	await frames(2)

	# Caught in the same moment he is seen: the grab and its gasp, no start.
	w = await _search_world()
	player = w.player as Player
	soldier = w.soldier as Enemy
	var seize := func(e: Enemy) -> void: player.seized_by(e)
	soldier.player_caught.connect(seize)
	heard.clear()
	player.global_position = soldier.global_position + Vector3(0, 0, -0.8)
	soldier.suspicion = 0.999
	await _until(func() -> bool: return player.seized, 3.0)
	await _wait(0.5)
	await _passes()
	var ids: Array[String] = []
	for e: Dictionary in heard:
		ids.append(String(e["id"]))
	check(player.seized and ids.has("seize_grab") and ids.has("breath_gasp") and not ids.has("breath_startle")
			and player.startles == 0,
			"caught as he is seen: a hand at his collar and its gasp, not a start", [ids, player.startles])
	soldier.player_caught.disconnect(seize)
	player.release()
	(w.root as Node).queue_free()
	await frames(2)

	# A direct grab (a hiding place checked) is no alarm: no run, no start.
	w = await _search_world()
	player = w.player as Player
	soldier = w.soldier as Enemy
	heard.clear()
	player.global_position = soldier.global_position + Vector3(0, 0, -1.0)
	soldier.set_physics_process(false)
	soldier._catch()
	await _wait(0.5)
	await _passes()
	check(soldier.state == Enemy.State.ALERT and of.call("enemy_break_run").is_empty()
			and of.call("breath_startle").is_empty() and player.startles == 0,
			"a direct grab is no alarm: no run, no start", heard.size())
	(w.root as Node).queue_free()
	await frames(2)

	# Suspicious - he comes to look: no run, no start.
	w = await _search_world()
	player = w.player as Player
	soldier = w.soldier as Enemy
	heard.clear()
	soldier.alert_to(soldier.global_position + Vector3(3, 0, 0), 0.7)
	await frames(60)
	check(soldier.state != Enemy.State.ALERT and of.call("enemy_break_run").is_empty()
			and of.call("breath_startle").is_empty() and player.startles == 0,
			"he heard something and comes to look: no run, no start", soldier.state)

	# The local policeman: his own silent slots, never German.
	soldier.kind = Enemy.Kind.POLIZEI
	soldier._set_state(Enemy.State.PATROL)
	soldier.suspicion = 0.0
	Sfx._missing.clear()
	soldier._speech_timer = 0.0
	await frames(3)
	var spoke: bool = Sfx.missing_ids().has("polizei_speech") and not Sfx.missing_ids().has("de_speech")
	soldier.alert_to(soldier.global_position + Vector3(3, 0, 0), 1.0)
	await _until(func() -> bool: return soldier.state == Enemy.State.ALERT, 2.0)
	await frames(2)
	check(spoke and soldier.state == Enemy.State.ALERT and Sfx.missing_ids().has("polizei_shout")
			and not Sfx.missing_ids().has("de_shout"),
			"the local policeman speaks and shouts in his own slots, never German", Sfx.missing_ids())
	(w.root as Node).queue_free()
	await frames(2)

	# The dog: it barks, it does not run in boots - and the boy starts.
	w = await _search_world()
	player = w.player as Player
	soldier = w.soldier as Enemy
	soldier.set_physics_process(false)
	var dog := (load("res://src/ai/dog.tscn") as PackedScene).instantiate() as Dog
	dog.hold_position = true
	(w.root as Node).add_child(dog)
	dog.global_position = player.global_position + Vector3(8, 0, 0)
	await frames(3)
	dog.nav_agent = null
	heard.clear()
	dog.alert_to(player.global_position, 1.0)
	await _until(func() -> bool: return dog.state == Enemy.State.ALERT, 2.0)
	await _until(func() -> bool: return player.startles > 0, 1.0)
	await _passes()
	check(dog.state == Enemy.State.ALERT and of.call("enemy_break_run").is_empty() and player.startles == 1
			and of.call("breath_startle").size() == 1,
			"the dog finds him: a bark, no boots breaking into a run, and he starts", [dog.state, heard.size()])

	# His start, called directly: held breath, a second alarm, too far, the beam.
	dog.set_physics_process(false)
	var breath := player.breath
	var near := player.global_position + Vector3(5, 0, 0)
	Stealth.clock += Player.STARTLE_REARM + 0.1
	heard.clear()
	breath.holding = true
	breath.air = 0.6
	PanicSystem.level = 0.5
	player.startle(near)
	await _until(func() -> bool: return player.startles == 2, 1.0)
	await _passes()
	check(player.startles == 2 and of.call("breath_startle").is_empty() and breath.holding
			and is_equal_approx(breath.air, 0.6) and PanicSystem.level <= 0.5 + 0.001,
			"holding his breath he only flinches: the breath stays held, no panic on top",
			[player.startles, breath.air, PanicSystem.level])
	breath.holding = false
	player.startle(near)
	await _wait(0.4)
	check(player.startles == 2, "not twice in a row: one start for one alarm", player.startles)
	Stealth.clock += Player.STARTLE_REARM + 0.1
	player.startle(player.global_position + Vector3(Player.STARTLE_RADIUS + 2.0, 0, 0))
	await _wait(0.4)
	check(player.startles == 2, "an alarm beyond his hearing: no start", player.startles)
	player.startle(player.global_position + Vector3(Player.STARTLE_RADIUS - 2.0, 0, 0))
	await _wait(0.4)
	check(player.startles == 3 and of.call("breath_startle").size() == 1, "within it: a start and a gasp",
			player.startles)
	Stealth.clock += Player.STARTLE_REARM + 0.1
	breath.cues = false
	heard.clear()
	player.startle(near)
	await _wait(0.4)
	breath.cues = true
	check(player.startles == 4 and of.call("breath_startle").is_empty(),
			"with his breath not heard (tests) the start is a flinch only", player.startles)
	Stealth.clock += Player.STARTLE_REARM + 0.1
	player.startle(player.global_position + Vector3(38, 6, 0), true)
	await _wait(0.4)
	check(player.startles == 5, "in a searchlight's beam he starts however far the lamp", player.startles)

	# Phantoms never sound like being seen.
	heard.clear()
	var phantom_ids: Array[String] = []
	var on_phantom := func(id: String, _pos: Vector3) -> void: phantom_ids.append(id)
	var phantoms := player.get_node("PhantomSounds") as PhantomSounds
	phantoms.phantom_played.connect(on_phantom)
	PanicSystem.level = 0.95
	for i in 60:
		phantoms.play_one(player)
	await _wait(0.3)
	phantoms.phantom_played.disconnect(on_phantom)
	var only := not phantom_ids.is_empty()
	for id: String in phantom_ids:
		only = only and (id == "step_player" or id == "dog_bark")
	check(only and of.call("enemy_break_run").is_empty() and of.call("breath_startle").is_empty()
			and player.startles == 5,
			"panic's phantoms are steps and barks, never an alarm", phantom_ids.size())
	PanicSystem.reset()
	(w.root as Node).queue_free()
	await frames(2)

	# The searchlight: the boy in the beam starts though the lamp is over 30 m
	# off, once; the patrol it calls breaks into a run; alarm_raised once.
	TraumaEcho.forget_all()
	var scene := ECHO_SCENE.instantiate()
	add_child(scene)
	await frames(3)
	player = scene.get_node("Player") as Player
	var patrol := scene.get_node("Patrol") as Enemy
	var tower := scene.get_node("Tower") as SearchlightTower
	for n: Node in [player, tower, scene.get_node("TraumaEcho"), player.get_node("BreathControl")]:
		n.set_physics_process(false)
	var raised := [0]
	var on_raised := func(_pos: Vector3) -> void: raised[0] += 1
	tower.alarm_raised.connect(on_raised)
	heard.clear()
	var from_lamp := player.global_position.distance_to(tower.lamp.global_position)
	tower.raise_alarm(player.global_position)
	await _until(func() -> bool: return patrol.state == Enemy.State.ALERT, 2.0)
	await _wait(0.4)
	await _passes()
	check(from_lamp > Player.STARTLE_RADIUS and player.startles == 1 and of.call("breath_startle").size() == 1
			and of.call("enemy_break_run").size() == 1 and raised[0] == 1,
			"the searchlight: he starts once in the beam, the patrol it calls breaks into a run",
			[from_lamp, player.startles, of.call("enemy_break_run").size(), raised[0]])
	# The beam alone, no one near enough to be heard: he still starts.
	patrol.set_physics_process(false)
	Stealth.clock += Player.STARTLE_REARM + 0.1
	tower.raise_alarm(player.global_position)
	await _wait(0.4)
	check(player.startles == 2 and of.call("breath_startle").size() == 2 and raised[0] == 2,
			"caught in the beam with no one near, he starts all the same", [player.startles, raised[0]])
	tower.alarm_raised.disconnect(on_raised)
	scene.queue_free()
	await frames(2)

	Sfx.played.disconnect(on_sound)
	Stealth.noise_emitted.disconnect(on_noise)
	PanicSystem.reset()
	await _wait(1.0)  # let the last sounds end before the next test


# --- out of breath ---------------------------------------------------------------

func _test_winded() -> void:
	var w := await _search_world()
	var player := w.player as Player
	var soldier := w.soldier as Enemy
	var hatch := w.hatch as HideSpot
	var breath := player.breath
	soldier.set_physics_process(false)
	soldier.global_position = Vector3(15, 0, -15)
	PanicSystem.reset()
	check(breath != null and breath.winded == 0.0 and is_equal_approx(PanicSystem.bpm(), PanicSystem.REST_BPM),
			"rested: he breathes quietly, his heart at rest")
	player.global_position = Vector3(-15, 0, 15)
	player.rotation.y = -PI * 0.5  # along +X, open ground
	await frames(2)
	breath.set_physics_process(true)
	Input.action_press("move_forward")
	await _wait(1.0)
	check(breath.winded < 0.01 and breath.pants == 0, "walking does not put him out of breath", breath.winded)
	Input.action_press("sprint")
	Engine.time_scale = 3.0
	await _wait(2.1)  # about six seconds of running
	await _until(func() -> bool: return breath.winded > 0.95, 3.0)  # physics behind the wall clock
	Engine.time_scale = 1.0
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	check(player.sprinting and breath.winded > 0.95, "six seconds of running and he is out of breath", breath.winded)
	check(speed < player.sprint_speed - 0.5 and speed > player.walk_speed,
			"fully winded he can no longer run flat out", speed)
	check(PanicSystem.bpm() > 130.0 and PanicSystem.level < 0.05,
			"his heart races, though he is not afraid", [PanicSystem.bpm(), PanicSystem.level])
	Input.action_release("sprint")
	Input.action_release("move_forward")

	# Standing still he pants: his own sound, a little noise close by.
	var noises: Array[float] = []
	var on_noise := func(_pos: Vector3, loud: float, src: Node) -> void:
		if src == player:
			noises.append(loud)
	var buses := {}
	var on_sound := func(id: String, p: AudioStreamPlayer3D) -> void: buses[id] = p.bus
	Stealth.noise_emitted.connect(on_noise)
	Sfx.played.connect(on_sound)
	soldier.global_position = player.global_position + Vector3(0, 0, 1.6)
	soldier.suspicion = 0.0
	var pants0 := breath.pants
	var sway := 0.0
	var t0 := Time.get_ticks_msec()
	# 1.5 s, and on till two pants have come (physics lags the wall clock).
	while (breath.pants - pants0 < 2 or Time.get_ticks_msec() - t0 < 1500) and Time.get_ticks_msec() - t0 < 5000:
		await get_tree().process_frame
		sway = maxf(sway, absf(player.camera.v_offset))
	var loudest := 0.0
	for n in noises:
		loudest = maxf(loudest, n)
	check(breath.pants - pants0 >= 2 and loudest > 0.1 and loudest <= Player.STEP_WALK_NOISE,
			"standing still he pants: quieter than a step", [breath.pants - pants0, noises])
	check(buses.get("breath_pant") == "Master", "his panting is his own body: never muffled", buses)
	check(soldier.suspicion > 0.0, "a soldier at arm's length hears it", soldier.suspicion)
	soldier.global_position = player.global_position + Vector3(0, 0, 9.0)
	soldier.suspicion = 0.0
	var pants_far := breath.pants
	await _wait(1.2)
	await _until(func() -> bool: return breath.pants > pants_far, 3.0)  # not without a pant
	check(soldier.suspicion == 0.0 and breath.pants > pants_far, "one nine metres off does not",
			[soldier.suspicion, breath.pants - pants_far])
	check(sway > 0.004, "his chest heaves: the view rises and falls", sway)
	Engine.time_scale = 3.0
	await _wait(2.6)  # about eight seconds of rest
	Engine.time_scale = 1.0
	var pants1 := breath.pants
	await _wait(1.0)
	check(breath.winded < 0.05 and breath.pants == pants1 and PanicSystem.bpm() < 80.0
			and absf(player.camera.v_offset) < 0.002,
			"after a few seconds of rest he breathes quietly again", [breath.winded, PanicSystem.bpm()])
	Stealth.noise_emitted.disconnect(on_noise)
	Sfx.played.disconnect(on_sound)

	# Hiding out of breath: the breath does not hold as long and, not held,
	# gives him away sooner. Hidden, his panting is only his own.
	breath.set_physics_process(false)
	soldier.global_position = Vector3(15, 0, -15)
	player.global_position = hatch.global_position + Vector3(0.8, 0, 0)
	await frames(2)
	hatch.interact(player)
	PanicSystem.reset()
	var rested_cap := breath.hold_capacity()
	breath.winded = 1.0
	check(breath.hold_capacity() < rested_cap * 0.5, "out of breath he cannot hold it half as long",
			[breath.hold_capacity(), rested_cap])
	var heard: Array[float] = []
	var rec := func(kind: String, loud: float) -> void:
		if kind == "pant":
			heard.append(loud)
	breath.sound_made.connect(rec)
	var frames_to_sob := func(winded: float) -> int:
		breath.winded = winded
		breath.exposure = 0.0
		var sobs := [0]
		var on := func(kind: String, _l: float) -> void:
			if kind == "sob":
				sobs[0] += 1
		breath.sound_made.connect(on)
		var n := 0
		while sobs[0] == 0 and n < 600:
			breath.winded = winded  # held for the comparison
			breath.step(1.0 / 30.0, false, 2.0)
			PanicSystem.reset()
			n += 1
		breath.sound_made.disconnect(on)
		return n
	var calm_frames: int = frames_to_sob.call(0.0)
	var winded_frames: int = frames_to_sob.call(1.0)
	check(winded_frames < calm_frames * 0.7, "panting in the cellar, the sob comes sooner",
			[winded_frames, calm_frames])
	var all_quiet := not heard.is_empty()
	for h in heard:
		all_quiet = all_quiet and h == 0.0
	check(all_quiet, "in the cellar his panting is only his own: the risk is the sob", heard)
	breath.winded = 1.0
	var before := breath.pants
	for i in 60:
		breath.winded = 1.0
		breath.step(1.0 / 30.0, true, 9.0)
	check(breath.pants == before and player.breath_sway == 0.0, "holding the breath stops the panting and the heaving")
	breath.sound_made.disconnect(rec)
	hatch.interact(player)
	(w.root as Node).queue_free()
	await frames(2)
	PanicSystem.reset()


# --- the boy's steps on floorboards -----------------------------------------------

## Walk `player` along +X from `from` for `sec` seconds; returns what he made:
## {"noises": [loudness...], "sounds": {id: bus}}.
func _walk_player(player: Player, from: Vector3, sec: float, crouch: bool = false) -> Dictionary:
	player.global_position = from
	player.rotation.y = -PI * 0.5
	player.velocity = Vector3.ZERO
	await frames(3)
	var out := {"noises": [], "sounds": {}}
	var on_noise := func(_pos: Vector3, loud: float, src: Node) -> void:
		if src == player:
			(out.noises as Array).append(loud)
	var on_sound := func(id: String, p: AudioStreamPlayer3D) -> void: (out.sounds as Dictionary)[id] = p.bus
	Stealth.noise_emitted.connect(on_noise)
	Sfx.played.connect(on_sound)
	if crouch:
		Input.action_press("crouch")
	Input.action_press("move_forward")
	await _wait(sec)
	Input.action_release("move_forward")
	Input.action_release("crouch")
	await frames(3)
	Stealth.noise_emitted.disconnect(on_noise)
	Sfx.played.disconnect(on_sound)
	return out


func _test_board_steps() -> void:
	var w := await _search_world()
	var player := w.player as Player
	var soldier := w.soldier as Enemy
	soldier.set_physics_process(false)
	soldier.global_position = Vector3(15, 0, -15)
	var boards := BoardFloor.new()
	boards.size = Vector3(14, 1, 6)
	boards.position = Vector3(-8, 0, 12)  # x -15..-1, z 9..15
	(w.root as Node3D).add_child(boards)
	player.board_creak_chance = 0.0
	player.board_creak_chance_crouched = 0.0

	var earth: Dictionary = await _walk_player(player, Vector3(-15, 0, 4), 2.0)
	var all_soft := not (earth.noises as Array).is_empty()
	for n in earth.noises:
		all_soft = all_soft and is_equal_approx(n, Player.STEP_WALK_NOISE)
	check(all_soft and earth.sounds.has("step_player") and not earth.sounds.has("step_player_board"),
			"on earth his steps are soft", earth)
	var wood: Dictionary = await _walk_player(player, Vector3(-14, 0, 12), 2.0)
	var all_louder := not (wood.noises as Array).is_empty()
	for n in wood.noises:
		all_louder = all_louder and is_equal_approx(n, Player.STEP_WALK_NOISE * Player.BOARD_NOISE)
	check(all_louder and wood.sounds.get("step_player_board") == "Master" and not wood.sounds.has("step_player"),
			"on the boards every step knocks louder (his own step: never muffled)", wood)

	# The same soldier eight metres off: hears him on the boards, not on earth.
	soldier.global_position = Vector3(-12, 0, 4) + Vector3(0, 0, -8)
	soldier.suspicion = 0.0
	await _walk_player(player, Vector3(-15, 0, 4), 1.4)
	var on_earth := soldier.suspicion
	soldier.global_position = Vector3(-12, 0, 12) + Vector3(0, 0, -8)
	soldier.suspicion = 0.0
	await _walk_player(player, Vector3(-14, 0, 12), 1.4)
	check(on_earth == 0.0 and soldier.suspicion > 0.0,
			"a soldier eight metres off does not hear him on earth, but hears him on the boards",
			[on_earth, soldier.suspicion])

	# Creaks: on earth never; on boards a creak is a noise of its own.
	player.board_creak_chance = 1.0
	player.board_creak_chance_crouched = 1.0
	var creaks0 := player.creaks
	earth = await _walk_player(player, Vector3(-15, 0, 4), 1.5)
	check(player.creaks == creaks0 and not earth.sounds.has("floor_creak"), "earth does not creak")
	wood = await _walk_player(player, Vector3(-14, 0, 12), 1.5)
	check(player.creaks > creaks0 and (wood.noises as Array).has(Player.CREAK_NOISE)
			and Sfx.is_world_bus(wood.sounds.get("floor_creak", &"")),
			"a board creaks under him: a noise of its own", [player.creaks - creaks0, wood.noises])
	# Crouched: the steps are quiet, but a board can still creak.
	soldier.global_position = Vector3(-12, 0, 12) + Vector3(0, 0, -4)
	soldier.suspicion = 0.0
	player.board_creak_chance_crouched = 0.0
	await _walk_player(player, Vector3(-14, 0, 12), 2.5, true)
	var quiet := soldier.suspicion
	soldier.suspicion = 0.0
	player.board_creak_chance_crouched = 1.0
	await _walk_player(player, Vector3(-14, 0, 12), 2.5, true)
	check(quiet == 0.0 and soldier.suspicion > 0.0,
			"crouched, a soldier four metres off does not hear his steps, only a creaking board",
			[quiet, soldier.suspicion])
	player.board_creak_chance = 0.3
	player.board_creak_chance_crouched = 0.15
	check(player.board_creak_chance > player.board_creak_chance_crouched and player.board_creak_chance < 0.5,
			"walking, about every third step creaks; crouched, half as often")
	(w.root as Node).queue_free()
	await frames(2)
	PanicSystem.reset()


func _test_hiding_sound() -> void:
	var bus := AudioServer.get_bus_index(Sfx.WORLD_BUS)
	check(bus > 0 and AudioServer.get_bus_send(bus) == "Master"
			and AudioServer.get_bus_effect(bus, 0) is AudioEffectLowPassFilter,
			"the world plays on its own bus, through a low-pass")
	var buses := {}
	var on_sound := func(id: String, p: AudioStreamPlayer3D) -> void: buses[id] = p.bus
	Sfx.played.connect(on_sound)
	for id in ["dog_bark", "step_boot_board", "breath_exhale", "step_player", "ear_ring"]:
		var p := Sfx.play_at(id, Vector3(0, -50, 0), 0.01)
		if p != null:
			p.queue_free()
	Sfx.played.disconnect(on_sound)
	check(Sfx.is_world_bus(buses.get("dog_bark", &"")) and Sfx.is_world_bus(buses.get("step_boot_board", &"")),
			"barks and boots are the world", buses)
	check(buses.get("breath_exhale") == "Master" and buses.get("step_player") == "Master"
			and buses.get("ear_ring") == "Master",
			"his own breath, steps and ringing ears are his body: never muffled", buses)

	var w := await _search_world()
	var player := w.player as Player
	var hatch := w.hatch as HideSpot
	var nook := w.nook as HideSpot
	var wardrobe := w.wardrobe as HideSpot
	(w.soldier as Enemy).set_physics_process(false)
	check((player.get_node("Heartbeat") as AudioStreamPlayer).bus == "Master", "nor is his heart")
	check(not Sfx.is_muffled() and not AudioServer.is_bus_effect_enabled(bus, 0)
			and absf(AudioServer.get_bus_volume_db(bus)) < 0.01, "out in the open nothing is muffled")
	hatch.interact(player)
	await _wait(0.6)
	await _until(func() -> bool: return (absf(Sfx.muffle_hz - hatch.muffle_hz) < 1.0
			and absf(AudioServer.get_bus_volume_db(bus) - hatch.muffle_db) < 0.01), 2.0)
	var lp := AudioServer.get_bus_effect(bus, 0) as AudioEffectLowPassFilter
	check(absf(Sfx.muffle_hz - hatch.muffle_hz) < 1.0 and AudioServer.is_bus_effect_enabled(bus, 0)
			and absf(lp.cutoff_hz - hatch.muffle_hz) < 1.0 and hatch.muffle_hz < 1000.0
			and absf(AudioServer.get_bus_volume_db(bus) - hatch.muffle_db) < 0.01 and hatch.muffle_db < 0.0,
			"in the cellar the world is dull and low: only the thuds of boots come through",
			[Sfx.muffle_hz, Sfx.muffle_db])
	hatch.interact(player)
	await _wait(0.6)
	await _until(func() -> bool: return (not Sfx.is_muffled() and not AudioServer.is_bus_effect_enabled(bus, 0)
			and absf(AudioServer.get_bus_volume_db(bus)) < 0.01), 2.0)
	check(not Sfx.is_muffled() and not AudioServer.is_bus_effect_enabled(bus, 0)
			and absf(AudioServer.get_bus_volume_db(bus)) < 0.01, "out again: the world is clear")
	nook.interact(player)
	await _wait(0.6)
	check(not Sfx.is_muffled(), "behind the stove nothing muffles the room", Sfx.muffle_hz)
	nook.interact(player)
	wardrobe.interact(player)
	await _wait(0.6)
	var in_wardrobe := Sfx.muffle_hz
	check(Sfx.is_muffled() and in_wardrobe > hatch.muffle_hz, "in the wardrobe the room is muffled, less than from the cellar",
			in_wardrobe)
	wardrobe.begin_check(w.soldier)
	await _wait(1.2)
	await _until(func() -> bool: return not Sfx.is_muffled(), 2.0)
	check(not Sfx.is_muffled(), "the doors swing open: the room comes in loud and clear", Sfx.muffle_hz)
	wardrobe.end_check(w.soldier)
	wardrobe.interact(player)
	wardrobe.close_door()
	hatch.interact(player)
	await _wait(0.5)
	(w.root as Node).queue_free()
	await frames(2)
	check(not Sfx.is_muffled() and absf(AudioServer.get_bus_volume_db(bus)) < 0.01,
			"a level freed while he hides leaves the world clear")

	var wind_pcm := _pcm(Sfx.stream_for("wind") as AudioStreamWAV)
	var quiet := INF
	var loud := 0.0
	for k in 10:
		var e := _energy(wind_pcm, float(k), float(k) + 1.0)
		quiet = minf(quiet, e)
		loud = maxf(loud, e)
	check(Sfx.is_loop("wind") and loud > 2.0 * quiet, "the wind comes in gusts", [quiet, loud])
	var level := LEVEL.instantiate()
	level.play_intro = false
	add_child(level)
	level._ending = true
	await frames(3)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set_physics_process(false)
	var wind := level.get_node_or_null("Wind") as AmbienceBed
	var p1 := level.get_node("Player") as Player
	check(wind != null and wind.player.playing and wind.player.bus == Sfx.WORLD_BUS
			and (wind.player.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD,
			"Act I: the wind blows outside, looped, on the world bus")
	p1.global_position = (level.get_node("Spawns/Street") as Node3D).global_position
	await _wait(2.0)
	var outside := wind.player.volume_db
	p1.global_position = (level.get_node("Spawns/Izba") as Node3D).global_position
	await _wait(2.0)
	var inside := wind.player.volume_db
	check(outside - inside > 8.0, "under the roof of the izba the wind drops", [outside, inside])
	level.queue_free()
	await frames(2)


# --- sound through walls ---------------------------------------------------------

## Occlusion (Sfx): a world sound with a wall or a closed door between it
## and the boy goes through the Occluded bus (low-passed, quieter) into World;
## his own body never does; while he hides, the hiding muffle rules alone.
func _test_occlusion() -> void:
	var occ := AudioServer.get_bus_index(Sfx.OCCLUDED_BUS)
	var world := AudioServer.get_bus_index(Sfx.WORLD_BUS)
	var wall_lp: AudioEffectLowPassFilter = null
	if occ >= 0 and AudioServer.get_bus_effect_count(occ) > 0:
		wall_lp = AudioServer.get_bus_effect(occ, 0) as AudioEffectLowPassFilter
	check(world > 0 and occ > world and AudioServer.get_bus_send(occ) == Sfx.WORLD_BUS
			and wall_lp != null and wall_lp.cutoff_hz < 1500.0 and AudioServer.is_bus_effect_enabled(occ, 0)
			and AudioServer.get_bus_volume_db(occ) < -3.0,
			"through a wall the world goes by its own bus: low, quieter, then into World (and the hiding muffle)",
			[world, occ])

	var w := await _search_world()
	var root := w.root as Node3D
	var player := w.player as Player
	var hatch := w.hatch as HideSpot
	(w.soldier as Enemy).set_physics_process(false)
	player.global_position = Vector3(-15, 0, 15)
	player.rotation = Vector3.ZERO
	var wall := CSGBox3D.new()
	wall.size = Vector3(6, 3, 0.3)
	wall.position = Vector3(-15, 1.5, 11)
	wall.use_collision = true
	wall.add_to_group(Stealth.SOUND_WALLS)  # the wall of a house
	root.add_child(wall)
	var door := (load("res://src/props/izba_door.tscn") as PackedScene).instantiate() as IzbaDoor
	door.position = Vector3(-16, 0, 18)  # the panel runs along +X: across his line to z = 21
	root.add_child(door)
	await frames(3)
	var behind_wall := Vector3(-15, 0, 8)
	var in_sight := Vector3(-11, 0, 15)
	var behind_door := Vector3(-15.4, 0, 21)
	check(Sfx.is_occluded(behind_wall) and not Sfx.is_occluded(in_sight),
			"a sound behind a log wall is muffled; one in plain sight is not")
	var bark := Sfx.play_at("dog_bark", behind_wall, 0.01)
	var clear := Sfx.play_at("dog_bark", in_sight, 0.01)
	var own := Sfx.play_at("step_player", behind_wall, 0.01)
	check(bark != null and bark.bus == Sfx.OCCLUDED_BUS and clear != null and clear.bus == Sfx.WORLD_BUS,
			"a bark behind the wall goes through the wall bus from its first moment",
			[bark.bus if bark else &"", clear.bus if clear else &""])
	check(own != null and own.bus == "Master", "his own steps are never behind a wall", own.bus if own else &"")
	for p in [bark, clear, own]:
		if p != null:
			p.queue_free()
	check(Sfx.is_occluded(behind_door), "a closed door stops the sound too")
	door.open()
	await _swung(door)
	check(not Sfx.is_occluded(behind_door), "the door swings open: the sound comes in clear")
	door.close()
	await _swung(door)
	await _until(func() -> bool: return door.blocks_sound(), 2.0)
	check(Sfx.is_occluded(behind_door), "shut again: muffled again")

	# A sound that lasts follows the wall: the wall goes, the sound clears.
	var clock := Sfx.play_at("wall_clock", behind_wall, 0.01, root)
	check(clock != null and clock.bus == Sfx.OCCLUDED_BUS, "the clock behind the wall ticks dull")
	wall.position.y = -10.0
	await _wait(0.4)
	check(clock != null and clock.bus == Sfx.WORLD_BUS, "the wall is gone: within a moment the ticking is clear",
			clock.bus if clock else &"")
	wall.position.y = 1.5
	await _wait(0.4)
	check(clock != null and clock.bus == Sfx.OCCLUDED_BUS, "the wall is back: dull again", clock.bus if clock else &"")
	# The same mass as a hedge, a haystack, a tree: no wall for sound.
	wall.remove_from_group(Stealth.SOUND_WALLS)
	var cam := player.camera.global_position
	check(_solid_between(cam, behind_wall + Vector3.UP * 1.1) and not Sfx.is_occluded(behind_wall),
			"behind a hedge or a haystack the same sound is clear")
	await _wait(0.3)
	check(clock != null and clock.bus == Sfx.WORLD_BUS, "and the ticking behind the hedge is clear", clock.bus if clock else &"")
	wall.add_to_group(Stealth.SOUND_WALLS)
	# Crouched behind a crate in a house: his ear is low, but the crate is no wall.
	var crate := CSGBox3D.new()
	crate.size = Vector3(1.0, 0.8, 1.0)
	crate.use_collision = true
	crate.add_to_group(Stealth.SOUND_WALLS)
	root.add_child(crate)
	crate.global_position = player.global_position + Vector3(1.0, 0.4, 0)  # right in front of him
	await frames(3)
	var past_crate := player.global_position + Vector3(8, 0, 0)
	var feet := player.global_position
	var space := player.get_world_3d().direct_space_state
	check(Sfx.SoundWalls.between(space, feet + Vector3.UP * 0.65, past_crate + Vector3.UP * 1.1)
			and not Sfx.SoundWalls.walled(space, get_tree(), feet, feet + Vector3.UP * 0.65, past_crate),
			"crouched behind a crate: the sound comes over it, as for a dog")
	crate.queue_free()

	root.queue_free()
	await frames(3)
	var gone := 0
	for p in Sfx._world_players:
		if not is_instance_valid(p):
			gone += 1
	Sfx.update_occlusion()
	check(Sfx._world_players.all(func(p: AudioStreamPlayer3D) -> bool: return is_instance_valid(p)),
			"freed sounds drop out of the list", gone)

	# Act I: from inside the izba the street is behind the door, the room is not.
	var level := LEVEL.instantiate()
	level.play_intro = false
	add_child(level)
	level._ending = true
	await frames(3)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set_physics_process(false)
	var p1 := level.get_node("Player") as Player
	p1.global_position = (level.get_node("Spawns/Izba") as Node3D).global_position
	var izba_door := level.get_node("IzbaDoor") as IzbaDoor
	izba_door.enemies_can_open = false
	izba_door.close()  # without the intro it stands open
	await _swung(izba_door)
	await _until(func() -> bool: return izba_door.blocks_sound(), 2.0)
	var street := (level.get_node("Spawns/Street") as Node3D).global_position
	var center := (level.get_node("Spawns/Center") as Node3D).global_position
	var clock_at := (level.get_node("IzbaClock") as Node3D).global_position
	var shut := Sfx.is_occluded(street)
	izba_door.open()
	await _swung(izba_door)
	var open := Sfx.is_occluded(street)
	check(shut and not open, "in the izba: the street comes through the door only when it is open", [shut, open])
	check(Sfx.is_occluded(center) and not Sfx.is_occluded(clock_at),
			"the log walls muffle the street; the clock on the wall of the room is clear")
	# One room has no walls in it: not the stove, not the open door leaf.
	var izba_at := (level.get_node("IzbaA") as Node3D).global_position
	var nook_at := (level.get_node("IzbaA/StoveNook") as Node3D).global_position
	p1.global_position = izba_at + Vector3(2.0, 0, -0.6)
	await frames(2)
	check(_solid_between(p1.camera.global_position, nook_at + Vector3.UP * 1.1) and not Sfx.is_occluded(nook_at),
			"in the izba: a sound on the other side of the stove is clear - the stove is no wall")
	var s1 := (level.get_node("Invasion/Search/S1") as Node3D).global_position
	p1.global_position = (level.get_node("IzbaA/CellarHatch") as HideSpot).stand_point()
	await frames(2)
	check(izba_door.is_open and _solid_between(p1.camera.global_position, s1 + Vector3.UP * 1.1)
			and not Sfx.is_occluded(s1), "in the izba: the open door leaf is no wall between him and the doorway")
	p1.global_position = (level.get_node("Spawns/Izba") as Node3D).global_position
	await frames(2)
	# Hiding in the izba: behind the stove (which muffles nothing) and in the
	# cellar the street stays behind the walls, the room stays clear.
	izba_door.close()
	await _swung(izba_door)
	var room := (level.get_node("Invasion/Search/SStove") as Node3D).global_position
	var street_tick := Sfx.play_at("wall_clock", center, 0.01, level)  # a sound that lasts, out in the street
	for spot_name in ["StoveNook", "CellarHatch"]:
		var spot := level.get_node("IzbaA/" + spot_name) as HideSpot
		spot.admit(p1)
		await _wait(0.3)
		check(p1.is_hidden and street_tick.bus == Sfx.OCCLUDED_BUS,
				"hiding (%s) does not make the street jump through the walls" % spot_name, street_tick.bus)
		check(Sfx.is_occluded(center) and not Sfx.is_occluded(room) and not Sfx.is_occluded(clock_at),
				"hidden (%s): the street stays behind the walls, the room is heard from where he hid" % spot_name,
				[Sfx.is_occluded(center), Sfx.is_occluded(room), Sfx.is_occluded(clock_at)])
		spot.eject(p1)
		await _wait(0.3)
	street_tick.queue_free()
	# The memory of the house is in his head: no ruin muffles it.
	check(not Sfx._world_players.has(Sfx.play_at("memory_room_tone", center + Vector3(0, 0, -30), 0.01, level)),
			"the memory's room tone is never put behind a wall")
	p1.global_position = street
	await frames(2)
	check(Sfx.is_occluded(clock_at), "from the street the clock in the izba is dull behind the shut door")
	# A sound at the door itself (a knock on it) is heard as it is from inside.
	p1.global_position = (level.get_node("Spawns/Izba") as Node3D).global_position + Vector3(-2.0, 0, -2.6)
	await frames(2)
	check(not Sfx.is_occluded(izba_door.sound_point()), "a knock on the door is not behind the wall next to it")
	level.queue_free()
	await frames(2)


# --- light and shadow ------------------------------------------------------------

const LEAN_SCENE := preload("res://src/scenes/test/lean_test.tscn")


## Leaning out (docs/ARCHITECTURE.md, "Выглянуть") in its test scene: a log
## wall with a doorway, a soldier outside aslant, the boy inside behind the
## jamb. The soldier does not move: what is checked is what he would see.
func _test_lean() -> void:
	var q_key := false
	for e in InputMap.action_get_events("lean"):
		q_key = q_key or (e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_Q)
	var rb := InputEventJoypadButton.new()
	rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	check(q_key and InputMap.action_has_event("lean", rb) and Controls.PAD_NAMES.get("lean", "") == "RB",
			"«Выглянуть» is Q on the keyboard and RB on a gamepad")
	check(Player.LEAN_BLOCK_MASK == 1 | IzbaDoor.DOOR_LAYER | Stealth.SEE_THROUGH_LAYER,
			"the head stops at walls, closed doors and the invisible barriers", Player.LEAN_BLOCK_MASK)
	var eye := Vector3(0, 1.6, -8)
	var lean := Vector3(Player.LEAN_SIDE, 0, 0)
	var straight := Enemy.sight_points(eye, Vector3(0, 1.35, 0) + lean)
	var leant := Enemy.sight_points(eye, Vector3(0, 1.35, 0) + lean, lean)
	check(leant[0] == straight[0] and (leant[1] - straight[1]).is_equal_approx(-lean * 0.5)
			and (leant[2] - straight[2]).is_equal_approx(-lean * 0.5),
			"leaning out, his shoulders go half as far as his head", leant)

	var scene := LEAN_SCENE.instantiate()
	add_child(scene)
	await frames(3)
	var player := scene.get_node("Player") as Player
	var soldier := scene.get_node("Soldier") as Enemy
	player.get_node("BreathControl").set_physics_process(false)
	soldier.set_physics_process(false)
	var start := player.global_position
	var noises: Array[float] = []
	var on_noise := func(_pos: Vector3, loud: float, src: Node) -> void:
		if src == player:
			noises.append(loud)
	Stealth.noise_emitted.connect(on_noise)
	await _until(func() -> bool: return absf(player.head.position.y - Player.STAND_EYE) < 0.005, 2.0)
	check(not soldier.can_see(player), "upright behind the jamb he is not seen from outside", player.head.global_position)

	Input.action_press("lean")
	Input.action_press("move_right")
	var out: bool = await _until(func() -> bool: return player.head.position.x > Player.LEAN_SIDE - 0.01, 3.0)
	check(out and absf(player.head.position.z) < 0.001,
			"holding «Выглянуть» and a step right, his head goes 0.35 m to the right", player.head.position)
	check(player.global_position.distance_to(start) < 0.01 and player.last_step_loudness == 0.0,
			"his feet stay where they were: no step", [player.global_position - start, player.last_step_loudness])
	check(player.head.rotation.z < -Player.LEAN_ROLL * 0.9
			and player.head.position.y < Player.STAND_EYE - Player.LEAN_DROP * 0.8,
			"his head rolls to the right and drops a little", [player.head.rotation.z, player.head.position.y])
	check(soldier.can_see(player), "leant out into the doorway he is seen", player.head.global_position)
	Input.action_release("move_right")
	var back: bool = await _until(func() -> bool: return absf(player.head.position.x) < 0.005, 2.0)
	check(back and absf(player.head.rotation.z) < 0.02 and not soldier.can_see(player),
			"the step let go, the key still held: the head comes back behind the jamb", player.head.position)
	Input.action_press("move_back")
	await frames(20)
	await _passes()
	check(Vector2(player.head.position.x, player.head.position.z).length() < 0.005
			and player.global_position.distance_to(start) < 0.01,
			"a step back with the key held does nothing", [player.head.position, player.global_position - start])
	# Back as well as right: the head still goes all the way (until the
	# review of 20.11.2026 the back key shortened it to 0.25 m).
	Input.action_press("move_right")
	var full_side: bool = await _until(func() -> bool: return player.head.position.x > Player.LEAN_SIDE - 0.01, 3.0)
	check(full_side and player.global_position.distance_to(start) < 0.01,
			"a step back as well as right: the head goes just as far, the feet stay", player.head.position)
	Input.action_release("move_back")
	# The run key held while leant out: he does not run.
	Input.action_press("sprint")
	await frames(10)
	await _passes()
	check(not player.sprinting and player.global_position.distance_to(start) < 0.01 and player.last_step_loudness == 0.0,
			"the run key held while leant out: no run, no step", [player.sprinting, player.global_position - start])
	Input.action_release("sprint")
	Input.action_release("move_right")
	await _until(func() -> bool: return absf(player.head.position.x) < 0.005, 2.0)
	# The stick pushed halfway: the head goes halfway.
	Input.action_press("move_right", 0.5)
	var half: bool = await _until(func() -> bool: return absf(player.head.position.x - Player.LEAN_SIDE * 0.5) < 0.005, 3.0)
	await frames(20)
	check(half and absf(player.head.position.x - Player.LEAN_SIDE * 0.5) < 0.005,
			"the stick pushed halfway: the head goes halfway out", player.head.position)
	Input.action_release("move_right")
	await _until(func() -> bool: return absf(player.head.position.x) < 0.005, 2.0)
	check(noises.is_empty(), "leaning makes no sound the enemies hear", noises)

	# Standing in view and leaning away from the doorway: the head goes
	# behind the jamb, a shoulder does not - it stays half as far out.
	player.global_position = Vector3(-0.075, 0, 0.45)
	Input.action_press("move_left")
	var left: bool = await _until(func() -> bool: return player.head.position.x < -Player.LEAN_SIDE + 0.01, 3.0)
	var to_head := PhysicsRayQueryParameters3D.create(soldier.global_position + Vector3.UP * soldier.eye_height,
			player.head.global_position, 1 | IzbaDoor.DOOR_LAYER)
	to_head.exclude = [soldier.get_rid()]
	var head_hidden := not player.get_world_3d().direct_space_state.intersect_ray(to_head).is_empty()
	check(left and head_hidden and soldier.can_see(player),
			"in view, leaning away from the doorway: the head is behind the jamb, a shoulder still shows",
			[left, head_hidden, player.head.global_position])
	# The key let go, the step still held: the head comes back and he walks.
	var stood := player.global_position
	Input.action_release("lean")
	var straight_again: bool = await _until(func() -> bool: return absf(player.head.position.x) < 0.005, 2.0)
	check(straight_again and absf(player.head.rotation.z) < 0.02 and player.global_position.distance_to(stood) > 0.1,
			"«Выглянуть» let go: the head comes back and the step walks him again",
			[player.head.position, player.global_position - stood])
	Input.action_release("move_left")

	# Face to the wall a hand's breadth away: leant forward, the head stops a
	# ball's breadth short of it.
	var wall_face := 0.125
	player.global_position = Vector3(-2, 0, wall_face + 0.33)
	player.rotation.y = 0.0  # facing -Z, the wall
	Input.action_press("lean")
	Input.action_press("move_forward")
	var to_wall: bool = await _until(func() -> bool: return player.head.position.z < -0.15, 2.0)
	await frames(20)
	var hz := player.head.global_position.z
	check(to_wall and hz > wall_face + Player.LEAN_HEAD_RADIUS - 0.005 and hz < wall_face + Player.LEAN_HEAD_RADIUS + 0.02,
			"leaning forward to a wall, the head stops short of it", hz)
	Input.action_release("move_forward")
	Input.action_press("move_right")
	var along: bool = await _until(func() -> bool: return player.head.position.x > Player.LEAN_SIDE - 0.01, 3.0)
	player.rotation.y = PI / 2.0  # now facing west: his right is the wall
	await frames(3)
	hz = player.head.global_position.z
	check(along and hz > wall_face + Player.LEAN_HEAD_RADIUS - 0.005
			and player.head.position.x > 0.1 and player.head.position.x < Player.LEAN_SIDE * 0.6,
			"turning to the wall with the head leant out, the head comes off the wall as far as it must",
			[hz, player.head.position])
	Input.action_release("move_right")
	await _until(func() -> bool: return absf(player.head.position.x) < 0.005, 2.0)
	# A flick of the mouse turns him between physics frames: the head is
	# taken out of the wall at once, not a frame later.
	player.rotation.y = -PI / 2.0  # facing east: his right is the room
	Input.action_press("move_right")
	var into_room: bool = await _until(func() -> bool: return player.head.position.x > Player.LEAN_SIDE - 0.01, 3.0)
	player._look(Vector2(-PI / (player.mouse_sensitivity * GameState.mouse_factor()), 0.0))
	hz = player.head.global_position.z
	check(into_room and hz > wall_face + Player.LEAN_HEAD_RADIUS - 0.005,
			"a flick of the mouse to the wall with the head leant out: the head is out of the wall at once", hz)
	Input.action_release("move_right")
	await _until(func() -> bool: return absf(player.head.position.x) < 0.005, 2.0)

	# A closed door and an invisible barrier stop the head; a body of an
	# interactable thing does not.
	var board := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(1.0, 2.4, 0.1)
	board.add_child(shape)
	scene.add_child(board)
	board.global_position = Vector3(-3, 1.2, 2.0)
	player.global_position = Vector3(-3, 0, 2.05 + 0.33)
	player.rotation.y = 0.0
	for pair: Array in [[IzbaDoor.DOOR_LAYER, true, "a closed door"], [Stealth.SEE_THROUGH_LAYER, true, "an invisible barrier"],
			[1 << 3, false, "an interactable thing's body"]]:
		board.collision_layer = pair[0]
		await frames(2)
		Input.action_press("move_forward")
		var moved: bool = await _until(func() -> bool: return player.head.position.z < -0.15, 2.0)
		await frames(40)
		var bz := player.head.global_position.z
		var stopped := bz > 2.05 + Player.LEAN_HEAD_RADIUS - 0.005 and bz < 2.05 + Player.LEAN_HEAD_RADIUS + 0.02
		var full := player.head.position.z < -Player.LEAN_FORWARD + 0.02
		check(moved and stopped == pair[1] and full != pair[1],
				"%s %s the head" % [pair[2], "stops" if pair[1] else "does not stop"], player.head.global_position)
		Input.action_release("move_forward")
		await _until(func() -> bool: return absf(player.head.position.z) < 0.005, 2.0)
	board.queue_free()

	# The satchel open: the step keys pick in it, the head stays straight.
	player.global_position = Vector3(-3, 0, 3.5)
	player.satchel.open()
	Input.action_press("move_right")
	await frames(20)
	await _passes()
	check(absf(player.head.position.x) < 0.001 and player.global_position.distance_to(Vector3(-3, 0, 3.5)) < 0.01,
			"with the satchel open he does not lean", player.head.position)
	player.satchel.close()
	# Crouched, he leans the same, low.
	Input.action_press("crouch")
	var low: bool = await _until(func() -> bool: return (player.head.position.x > Player.LEAN_SIDE - 0.01
			and player.head.position.y < Player.CROUCH_EYE + 0.01), 3.0)
	check(low, "crouched, he leans out just as far, low down", player.head.position)
	Input.action_release("crouch")
	await _until(func() -> bool: return player.head.position.y > Player.STAND_EYE - Player.LEAN_DROP - 0.01, 2.0)
	# Turned towards a point while leant out (a staged look): the body turns
	# round its own axis, not round the leant head.
	var target := Vector3(1.0, 1.2, 6.5)
	player.look_towards(target)
	var fwd := -player.global_basis.z
	var aim := target - player.global_position
	var off := rad_to_deg(Vector2(fwd.x, fwd.z).angle_to(Vector2(aim.x, aim.z)))
	check(absf(off) < 0.5, "turned towards a point while leant out, his body faces it from its own axis", off)
	await _until(func() -> bool: return player.head.position.x > Player.LEAN_SIDE - 0.01, 3.0)
	# At night the light on him is taken at his shoulders, where the enemies
	# look for them: half as far out as the head.
	Stealth.set_night(0.3, null)
	var lamp := scene.get_node("YardLamp") as Light3D
	lamp.visible = false
	soldier.torch_on = false
	var glim := OmniLight3D.new()
	glim.omni_range = 0.15
	scene.add_child(glim)
	glim.global_position = player.shoulders() + Vector3.UP * 0.02
	Stealth._scan_lights()
	Stealth.update_light()
	var lit := Stealth.player_light
	Stealth.set_day()
	glim.queue_free()
	lamp.visible = true
	check(player.shoulders().is_equal_approx(player.head.global_position - player.lean_offset() * 0.5 - Vector3.UP * 0.25)
			and lit > 0.8, "at night the light on him is taken at his shoulders, half as far out as his head", lit)
	# Caught leaning out, sat down, crawling or hidden, he does not lean.
	var y_before := player.head.position.y
	var drop_before := player._lean_drop(player._lean)
	player.seized_by(soldier)
	check(player.head.position.x == 0.0 and player.head.rotation.z == 0.0,
			"caught leaning out: his head is pulled straight at once", player.head.position)
	await frames(20)
	await _passes()
	check(drop_before > Player.LEAN_DROP * 0.9 and absf(player.head.position.y - (y_before + drop_before)) < 0.001
			and player.head.position.x == 0.0,
			"held by the collar, the keys still down: he does not lean, his head is up by as much as the lean lowered it",
			[y_before, drop_before, player.head.position])
	player.release()
	var out_again: bool = await _until(func() -> bool: return player.head.position.x > Player.LEAN_SIDE - 0.01, 3.0)
	var seat := Node3D.new()
	scene.add_child(seat)
	seat.global_position = Vector3(-3, 0.8, 4.5)
	player.sit_at(seat)
	var seated_straight := player.head.position.x == 0.0 and player.head.rotation.z == 0.0
	await frames(20)
	await _passes()
	check(out_again and seated_straight and player.head.position.x == 0.0,
			"sat down in a staged scene, he does not lean, the keys held or not", player.head.position)
	player.stand_up(Transform3D(Basis(), Vector3(-3, 0, 3.5)))
	seat.queue_free()
	out_again = await _until(func() -> bool: return player.head.position.x > Player.LEAN_SIDE - 0.01, 3.0)
	player.crawling = true
	var crawl_back: bool = await _until(func() -> bool: return absf(player.head.position.x) < 0.005, 2.0)
	await frames(10)
	check(out_again and crawl_back and absf(player.head.position.x) < 0.005,
			"crawling, he does not lean: the head comes back, the keys held or not", player.head.position)
	# Under the wire the gap holds his head low (WireGap.CRAWL_EYE); the lean
	# must not lift it (until 20.11.2026, evening, it did: the beam in Act II
	# saw him crawling and binding the wound).
	player.head.position.y = WireGap.CRAWL_EYE
	await frames(20)
	await _passes()
	check(absf(player.head.position.y - WireGap.CRAWL_EYE) < 0.001,
			"crawling, his head stays as low as the wire gap holds it", player.head.position.y)
	player.crawling = false
	out_again = await _until(func() -> bool: return player.head.position.x > Player.LEAN_SIDE - 0.01, 3.0)
	var hatch := CELLAR.instantiate() as HideSpot
	scene.add_child(hatch)
	hatch.global_position = Vector3(-3, 0, 2.6)
	await frames(2)
	hatch.admit(player)
	var at_once := player.head.position.x == 0.0 and player.head.rotation.z == 0.0
	await frames(20)
	await _passes()
	check(out_again and at_once and player.head.position.x == 0.0, "hidden, he does not lean, the keys held or not",
			player.head.position)
	hatch.eject(player)
	Input.action_release("move_right")
	Input.action_release("lean")
	Stealth.noise_emitted.disconnect(on_noise)
	scene.queue_free()
	await frames(2)


## What an enemy sees of the boy (Enemy.can_see, Enemy.sight_points): his head
## and both shoulders; one clear line and he is seen (docs/ARCHITECTURE.md,
## "Враги"). Until 19.11.2026 one line to the head: a post hid him.
func _test_sight_points() -> void:
	var head := Vector3(0, 1.35, 0)
	var shape_ok := true
	# Face-on and on a diagonal: the shoulders lie level, across the line.
	for eye: Vector3 in [Vector3(0, 1.6, -8), Vector3(-6, 1.6, -6)]:
		var pts := Enemy.sight_points(eye, head)
		if pts.size() != 3:
			shape_ok = false
			continue
		var across := pts[1] - pts[2]
		var line := Vector3(head.x - eye.x, 0.0, head.z - eye.z)
		shape_ok = shape_ok and (pts[0] == head and absf(across.length() - 2.0 * Enemy.SHOULDER_HALF) < 0.001
				and absf(across.y) < 0.001 and absf(across.dot(line)) < 0.001
				and absf(pts[1].y - (head.y - Enemy.SHOULDER_DROP)) < 0.001)
	check(shape_ok, "he is seen by his head and two shoulders across the line of sight",
			[Enemy.sight_points(Vector3(0, 1.6, -8), head), Enemy.sight_points(Vector3(-6, 1.6, -6), head)])
	var root := Node3D.new()
	var ground := CSGBox3D.new()
	ground.size = Vector3(30, 1, 30)
	ground.position = Vector3(0, -0.5, 0)
	ground.use_collision = true
	root.add_child(ground)
	var player := PLAYER_SCENE.instantiate() as Player
	root.add_child(player)
	var soldier := ENEMY_SCENE.instantiate() as Enemy
	soldier.hold_position = true
	soldier.position = Vector3(0, 0, -8)
	soldier.rotation.y = PI  # looks towards +Z, at the boy
	root.add_child(soldier)
	add_child(root)
	await frames(3)
	player.get_node("BreathControl").set_physics_process(false)
	player.set_physics_process(false)  # keep the head where the test puts it
	soldier.set_physics_process(false)
	soldier.nav_agent = null
	player.global_position = Vector3.ZERO
	player.head.position.y = Player.STAND_EYE
	await frames(2)
	check(soldier.can_see(player), "in the open, eight metres in front: seen")
	# A post 14 cm wide a metre in front of him, on the line to his head.
	var post := CSGBox3D.new()
	post.size = Vector3(0.14, 3.0, 0.14)
	post.position = Vector3(0, 1.5, -1)
	post.use_collision = true
	root.add_child(post)
	await frames(2)
	var q := PhysicsRayQueryParameters3D.create(soldier.global_position + Vector3.UP * soldier.eye_height,
			player.head.global_position, 1)
	q.exclude = [soldier.get_rid()]
	var head_hidden := not root.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	check(head_hidden and soldier.can_see(player), "a post hides his head, not his shoulders: seen", head_hidden)
	post.size = Vector3(1.2, 3.0, 0.14)
	await frames(2)
	check(not soldier.can_see(player), "behind a board as wide as he is: not seen")
	post.size = Vector3(3.0, 1.0, 0.14)
	post.position = Vector3(0, 0.5, -1)
	await frames(2)
	check(soldier.can_see(player), "behind a waist-high wall, standing: seen over it")
	player.head.position.y = Player.CROUCH_EYE
	await frames(2)
	check(not soldier.can_see(player), "crouched behind it: head and shoulders below the top, not seen")
	root.queue_free()
	await frames(2)


## Light (Stealth.player_light, Enemy.sight_distance): at night the boy in the
## dark is seen nearer and slower; the moon's shadow hides him more; a lamp,
## a torch beam or a flare give him away; light does not pass walls.
func _test_light() -> void:
	check(Stealth.night_sight >= 1.0 and is_equal_approx(Stealth.player_light, 1.0),
			"by day (and in the test worlds) light does not matter")
	var root := Node3D.new()
	var ground := CSGBox3D.new()
	ground.size = Vector3(60, 1, 60)
	ground.position = Vector3(0, -0.5, 0)
	ground.use_collision = true
	root.add_child(ground)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.rotation_degrees = Vector3(-50, 0, 0)  # shines down towards -Z: the moon is up and to +Z
	root.add_child(moon)
	var wall := CSGBox3D.new()  # between the boy at the origin and the moon
	wall.size = Vector3(4, 4, 0.3)
	wall.position = Vector3(0, 2, 1.0)
	wall.use_collision = true
	root.add_child(wall)
	var player := PLAYER_SCENE.instantiate() as Player
	player.position = Vector3(10, 0, 0)
	root.add_child(player)
	var soldier := ENEMY_SCENE.instantiate() as Enemy
	soldier.has_torch = true
	soldier.hold_position = true
	soldier.position = Vector3(10, 0, -12)
	soldier.rotation.y = PI  # looks towards +Z, at the boy
	root.add_child(soldier)
	add_child(root)
	await frames(3)
	player.get_node("BreathControl").set_physics_process(false)
	soldier.set_physics_process(false)
	soldier.nav_agent = null
	Stealth.set_night(0.5, moon)

	Stealth.update_light()
	var open := Stealth.player_light
	check(absf(open - 0.5) < 0.01, "night, open moonlight: he is half seen", open)
	var far := soldier.view_distance * lerpf(Enemy.DARK_SIGHT, 1.0, 0.5)
	check(absf(soldier.sight_distance() - far) < 0.05 and far < 11.0,
			"in moonlight a soldier makes him out only within about ten metres, not sixteen", soldier.sight_distance())
	check(not soldier.can_see(player), "twelve metres off in the moonlight: not seen")
	player.global_position = Vector3(0, 0, 0)
	await frames(2)
	Stealth.update_light()
	var shade := Stealth.player_light
	check(absf(shade - 0.5 * Stealth.MOON_SHADOW) < 0.01, "in the shadow of a wall he is darker still", shade)
	check(soldier.sight_distance() < 8.0 and soldier.sight_distance() >= Enemy.CLOSE_SIGHT,
			"in the shadow he is seen only within about seven metres", soldier.sight_distance())

	# A lamp behind the wall does not light him; one on his side does.
	var lamp := OmniLight3D.new()
	lamp.omni_range = 6.0
	lamp.light_energy = 1.0
	lamp.position = Vector3(0, 1.8, 2.6)
	root.add_child(lamp)
	Stealth._scan_lights()
	Stealth.update_light()
	check(absf(Stealth.player_light - shade) < 0.01, "a lamp behind the wall does not light him", Stealth.player_light)
	lamp.position = Vector3(0.5, 1.8, -1.0)
	await frames(2)
	Stealth.update_light()
	check(Stealth.player_light > 0.85, "next to a lamp he is in full view", Stealth.player_light)
	player.global_position = Vector3(10, 0, 0)
	lamp.position = Vector3(10.5, 1.8, -1.0)
	await frames(2)
	Stealth.update_light()
	check(soldier.can_see(player), "lit by the lamp: seen at twelve metres", Stealth.player_light)
	lamp.visible = false
	Stealth.update_light()
	check(not soldier.can_see(player) and absf(Stealth.player_light - open) < 0.01, "the lamp goes out: dark again")

	# The soldier's torch: the beam on him (even on his legs) gives him away.
	player.global_position = Vector3(10, 0, -1)
	await frames(2)
	Stealth.update_light()
	var dark11 := soldier.can_see(player)
	soldier.torch_on = true
	Stealth._scan_lights()
	Stealth.update_light()
	check(not dark11 and Stealth.player_light > open + 0.1 and soldier.can_see(player),
			"eleven metres off: unseen in the moonlight, seen in the beam of the torch", [dark11, Stealth.player_light])
	soldier.torch_on = false
	Stealth.update_light()
	check(absf(Stealth.player_light - open) < 0.01, "the torch is off: only the moon", Stealth.player_light)

	# A flare in the sky lights the whole street for a few seconds.
	var flare := (load("res://src/props/signal_flare.tscn") as PackedScene).instantiate() as SignalFlare
	flare.autofire = false
	flare.position = Vector3(0, 0, -20)
	root.add_child(flare)
	await frames(2)
	Stealth._scan_lights()
	flare.launch()
	await _wait(1.2)
	Stealth.update_light()
	var under_flare := Stealth.player_light
	check(under_flare > open + 0.15, "a flare over the street: he is seen as if at dawn", under_flare)
	await _wait(flare.burn_time)
	Stealth.update_light()
	check(absf(Stealth.player_light - open) < 0.01, "the flare burns out: night again", Stealth.player_light)
	# On its own: one every 20 s (the count of `interval` stands while one
	# burns), stepped by hand over a minute.
	flare.set_process(false)
	flare.autofire = true
	flare._timer = flare.first_delay
	var went_up: Array[float] = []
	for i in 600:
		flare._process(0.1)
		if flare._burn == 0.0:
			went_up.append((i + 1) * 0.1)
	var period := flare.interval + flare.burn_time
	check(went_up.size() == 3 and absf(went_up[1] - went_up[0] - period) < 0.21
			and absf(period - 20.0) < 0.01,
			"a flare goes up every 20 s: six burning, fourteen dark", went_up)
	flare.autofire = false

	# Suspicion grows slower in the dark (same distance, same stance).
	player.global_position = Vector3(10, 0, -7)
	lamp.position = Vector3(10.5, 1.8, -8.0)
	await frames(2)
	var gains := []
	for lit in [false, true]:
		lamp.visible = lit
		Stealth.update_light()
		soldier.suspicion = 0.0
		soldier.set_physics_process(true)
		await frames(18)  # 0.3 s of his own steps, whatever the load
		soldier.set_physics_process(false)
		gains.append(soldier.suspicion)
	check(gains[0] > 0.0 and gains[0] < 0.8 * gains[1],
			"five metres off in the moonlight he is noticed, but more slowly than under a lamp", gains)
	lamp.visible = false
	player.global_position = Vector3(0, 0, 0)  # the wall's shadow
	await frames(2)
	Stealth.update_light()
	var calm := soldier.seen_light()
	soldier.state = Enemy.State.ALERT
	check(calm < Enemy.ALERT_LIGHT and is_equal_approx(soldier.seen_light(), Enemy.ALERT_LIGHT)
			and soldier.sight_distance() > soldier.view_distance * lerpf(Enemy.DARK_SIGHT, 1.0, calm) + 1.0,
			"a soldier already chasing him does not lose him in the shade", [calm, soldier.seen_light()])
	soldier.state = Enemy.State.PATROL
	root.queue_free()
	await frames(2)
	Stealth.set_day()
	PanicSystem.reset()

	# Levels: Act I is night; leaving it brings back the day.
	var level := LEVEL.instantiate()
	level.play_intro = false
	add_child(level)
	level._ending = true
	await frames(3)
	check(Stealth.night_sight < 1.0 and Stealth.moon != null and Stealth.moon.name == "Moon",
			"Act I is a moonlit night", Stealth.night_sight)
	level.queue_free()
	await frames(2)
	check(Stealth.night_sight >= 1.0 and Stealth.moon == null, "the level is gone: light does not matter again")


# --- noise of his actions ---------------------------------------------------------

## The boy's actions are heard (HideSpot.use_sound/use_noise, IzbaDoor latch):
## the cellar lid, the wardrobe door, hay and the izba door make a sound for
## him and a noise for the enemies, half as loud crouched (Player.care); the
## noise is made out in the open, so it draws a soldier but never catches him.
func _test_action_noise() -> void:
	var w := await _search_world()
	var root := w.root as Node3D
	var player := w.player as Player
	var hatch := w.hatch as HideSpot
	var wardrobe := w.wardrobe as HideSpot
	var nook := w.nook as HideSpot
	var soldier := w.soldier as Enemy
	soldier.set_physics_process(false)
	var hay := (load("res://src/interaction/hay_hide.tscn") as PackedScene).instantiate() as HideSpot
	hay.position = Vector3(-8, 0, 8)
	root.add_child(hay)
	var door := (load("res://src/props/izba_door.tscn") as PackedScene).instantiate() as IzbaDoor
	door.position = Vector3(-10, 0, -10)
	door.enemies_can_open = false
	root.add_child(door)
	await frames(3)
	var noises: Array = []
	var sounds := {}
	var on_noise := func(pos: Vector3, loud: float, src: Node) -> void:
		noises.append({"pos": pos, "loud": loud, "src": src, "hidden": player.is_hidden})
	var on_sound := func(id: String, p: AudioStreamPlayer3D) -> void: sounds[id] = p.volume_db
	Stealth.noise_emitted.connect(on_noise)
	Sfx.played.connect(on_sound)

	player.global_position = hatch.global_position + Vector3(0, 0, 1.0)
	await frames(2)
	hatch.interact(player)
	check(noises.size() == 1 and absf(float(noises[0].loud) - 0.4) < 0.001 and noises[0].src == player
			and not noises[0].hidden and (noises[0].pos as Vector3).distance_to(hatch.global_position) < 0.01,
			"lifting the cellar lid is heard: made while he is still out in the open", noises)
	check(sounds.has("hatch_lid") and Sfx.bus_of("hatch_lid") == Sfx.WORLD_BUS, "and he hears the lid himself", sounds)
	var loud_db: float = sounds.get("hatch_lid", 0.0)
	await _wait(0.2)
	noises.clear()
	sounds.clear()
	Input.action_press("crouch")  # hidden: the button held now counts
	hatch.interact(player)
	Input.action_release("crouch")
	check(not player.is_hidden and noises.size() == 1 and absf(float(noises[0].loud) - 0.4 * Player.CAREFUL) < 0.001
			and not noises[0].hidden, "climbing out carefully, crouched: half as loud", noises)
	check(sounds.has("hatch_lid") and float(sounds.hatch_lid) < loud_db - 5.0, "and the lid itself is quieter",
			[loud_db, sounds.get("hatch_lid")])

	var heard := {}
	for spot in [wardrobe, hay, nook]:
		noises.clear()
		sounds.clear()
		player.global_position = (spot as HideSpot).stand_point()
		await frames(2)
		(spot as HideSpot).interact(player)
		heard[(spot as Node).name] = [noises[0].loud if not noises.is_empty() else 0.0, sounds.keys()]
		await _wait(0.1)
		(spot as HideSpot).interact(player)
		await frames(2)
	check(absf(float(heard.WardrobeHide[0]) - 0.35) < 0.001 and (heard.WardrobeHide[1] as Array).has("door_creak"),
			"the wardrobe door creaks", heard)
	check(absf(float(heard.HayHide[0]) - 0.25) < 0.001 and (heard.HayHide[1] as Array).has("hay_rustle"),
			"the hay rustles, quieter than the lid", heard)
	check(is_zero_approx(float(heard.StoveNook[0])) and (heard.StoveNook[1] as Array).is_empty(),
			"slipping behind the stove makes no sound", heard)

	# Heard plainly, even within the 2.5 m of the catch rule: suspicious, not caught.
	soldier.global_position = hatch.global_position + Vector3(0, 0, -1.5)
	soldier.rotation.y = 0.0  # facing away from the hatch
	soldier.suspicion = 0.0
	player.global_position = hatch.global_position + Vector3(0, 0, 1.0)
	await frames(2)
	hatch.interact(player)
	check(player.is_hidden and not soldier._caught and soldier.suspicion >= Enemy.SUSPICIOUS_AT
			and soldier.state == Enemy.State.SUSPICIOUS and soldier.last_known.distance_to(hatch.global_position) < 0.01,
			"a soldier a step away hears the lid plainly: he turns to look, but the noise does not catch the boy",
			[soldier.suspicion, soldier.state, soldier._caught])
	hatch.eject(player)
	soldier.stand_down()
	# Through a wall the same lid only adds a little, like a step.
	var wall := CSGBox3D.new()
	wall.size = Vector3(4, 3, 0.3)
	wall.use_collision = true
	wall.add_to_group(Stealth.SOUND_WALLS)  # the wall of a house
	root.add_child(wall)
	wall.global_position = hatch.global_position + Vector3(0, 1.5, -1.5)
	soldier.global_position = hatch.global_position + Vector3(0, 0, -2.0)
	soldier.suspicion = 0.0
	await frames(3)
	hatch.interact(player)
	check(soldier.suspicion > 0.02 and soldier.suspicion < Enemy.SUSPICIOUS_AT and soldier.state == Enemy.State.PATROL,
			"through a wall the lid is only a vague sound", [soldier.suspicion, soldier.state])
	hatch.eject(player)
	wall.queue_free()
	soldier.stand_down()
	soldier.global_position = hatch.global_position + Vector3(0, 0, -7.0)
	soldier.suspicion = 0.0
	await frames(3)
	hatch.interact(player)
	check(is_zero_approx(soldier.suspicion), "seven metres off he hears nothing", soldier.suspicion)
	hatch.eject(player)
	# A soldier who hears it walks over and looks round - the cellar he does not open.
	soldier.global_position = hatch.global_position + Vector3(0, 0, -4.0)
	soldier.suspicion = 0.0
	soldier.set_physics_process(true)
	await frames(2)
	hatch.interact(player)
	var nearest := INF
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		await get_tree().physics_frame
		nearest = minf(nearest, soldier.global_position.distance_to(hatch.global_position))
	check(nearest < 1.6 and not soldier._caught and player.is_hidden,
			"he comes to the lid he heard, looks round, and walks on", [nearest, soldier._caught])
	soldier.set_physics_process(false)
	soldier.stand_down()
	# A story or a capture pulling him out makes no noise of his own.
	noises.clear()
	sounds.clear()
	hatch.eject(player)
	hatch.admit(player)
	hatch.eject(player)
	check(noises.is_empty() and not sounds.has("hatch_lid"), "moved in and out by a story: silent", [noises, sounds])

	# The izba door: the latch creaks for enemies too; a soldier's hand does not.
	player.global_position = door.global_position + Vector3(0.6, 0, 1.0)
	await frames(2)
	noises.clear()
	door.latch.interact(player)
	check(door.is_open and noises.size() == 1 and absf(float(noises[0].loud) - IzbaDoor.PLAYER_NOISE) < 0.001
			and noises[0].src == player, "the boy opens the door: its creak is heard", noises)
	await _swung(door)
	noises.clear()
	Input.action_press("crouch")
	await frames(3)
	door.latch.interact(player)
	Input.action_release("crouch")
	check(not door.is_open and noises.size() == 1
			and absf(float(noises[0].loud) - IzbaDoor.PLAYER_NOISE * Player.CAREFUL) < 0.001,
			"closed slowly, crouched: half as loud", noises)
	await _swung(door)
	noises.clear()
	door.open()
	check(noises.is_empty(), "a soldier opening it makes no noise for the others", noises)
	Stealth.noise_emitted.disconnect(on_noise)
	Sfx.played.disconnect(on_sound)
	root.queue_free()
	await frames(3)
	PanicSystem.reset()


# --- the izba door's leaf and the boy in its way -----------------------------------

## The leaf never passes through the boy (IzbaDoor._clear_way). Opened by the
## latch or kicked in, at x1 and with frames four times as long (x4), it
## carries him off its face round to its tip and lets him go there. With a
## wall at his back it stops against him and waits, and goes on once he
## steps away. Shut by his own hand, it stops against him instead of
## sweeping him out through the doorway. A hidden boy is not in its way; one
## held by the collar is not dragged about by it.
func _test_door_leaf() -> void:
	var w := await _search_world()
	var root := w.root as Node3D
	var player := w.player as Player
	(w.soldier as Enemy).set_physics_process(false)
	# He stands where the leaf comes: 0.9 m out from the hinge, 0.35 m in.
	var at := Vector3(0.9, 0, 0.35)
	for kick: bool in [false, true]:
		for speed: float in [1.0, 4.0]:
			# Kicked in at x1 he is holding his breath behind the door.
			player.breath.holding = kick and speed == 1.0
			player.breath.air = 1.0
			player.breath._lockout = 0.0
			var r := await _leaf_case(root, player, kick, speed, at, null, false)
			check(float(r.into) < 0.01 and not r.behind and float(r.moved) > 1.30 and float(r.moved) < 1.50
					and float(r.reach) > float(r.tip) - 0.01 and absf(float(r.angle) - (-100.0)) < 0.5
					and not r.swinging,
					"%s at x%d the leaf never goes through the boy in its way: it carries him round to its tip (about 1.4 m) and lets him go there, and opens all the way" % [
						"kicked in" if kick else "opened by the latch", int(speed)], r)
			if kick:
				check(int(r.hits) == 1 and int(r.gasps) == 1 and float(r.noise) > 0.99 and float(r.panic) > 0.6
						and float(r.lockout) > 1.0 and not r.holding,
						"kicked in at x%d, the leaf strikes him once: a dull blow, the wind knocked out of him - a gasp the one at the door hears - and panic jumps" % int(speed), r)
			else:
				check(int(r.hits) == 0 and int(r.gasps) == 0 and float(r.panic) < 0.05,
						"opened by the latch at x%d, the leaf only moves him: no blow, no gasp" % int(speed), r)
			if kick and speed == 1.0:
				check(r.holding_before and not r.holding and float(r.lockout) > 1.0,
						"holding his breath behind the kicked door, the blow breaks it, and for a moment he cannot hold it again", r)
	var panel := (load("res://src/props/izba_door.tscn") as PackedScene).instantiate() as IzbaDoor
	root.add_child(panel)
	# Another door with a panel of another size (its own copy of the shape:
	# the scene's stays as it is) - the door reads it, not numbers of its own.
	var other := (load("res://src/props/izba_door.tscn") as PackedScene).instantiate() as IzbaDoor
	var other_shape := other.get_node("Panel/Shape") as CollisionShape3D
	var box := (other_shape.shape as BoxShape3D).duplicate() as BoxShape3D
	box.size = Vector3(1.0, 2.05, 0.1)
	other_shape.shape = box
	root.add_child(other)
	await frames(1)
	check(is_equal_approx(panel.leaf_length, 1.2) and is_equal_approx(panel.leaf_half_thickness, 0.04)
			and is_equal_approx(other.leaf_length, 1.1) and is_equal_approx(other.leaf_half_thickness, 0.05),
			"the leaf the door clears the boy of is its panel as it is in the scene: 1.2 m by 8 cm; a 1 m panel 10 cm thick, set 0.6 m out, reaches 1.1 m",
			[panel.leaf_length, panel.leaf_half_thickness, other.leaf_length, other.leaf_half_thickness])
	panel.queue_free()
	other.queue_free()
	# A wall at his back: nowhere to go. The leaf stops against him and waits.
	var wall := CSGBox3D.new()
	wall.size = Vector3(3, 2, 0.3)
	wall.use_collision = true
	var r := await _leaf_case(root, player, true, 4.0, at, wall, false)
	check(float(r.into) < 0.01 and not r.behind and r.swinging and float(r.angle) < -3.0
			and float(r.angle) > -40.0 and float(r.in_wall) < 0.01
			and absf(float(r.waited) - float(r.angle)) < 0.01,
			"with a wall at his back the kicked leaf stops against him, he is not pressed into the wall, and it waits there", r)
	check(int(r.hits) == 1 and int(r.gasps) == 1,
			"pinned against the wall, he is struck once, not again every frame the leaf presses on him or swings on", r)
	check(absf(float(r.after) - (-100.0)) < 0.5 and not r.after_swinging,
			"he steps away: then the leaf swings on, all the way", r)
	# Shutting it from inside, he stands where the leaf comes back.
	r = await _leaf_case(root, player, false, 1.0, Vector3(0.6, 0, 0.8), null, true)
	check(float(r.into) < 0.01 and not r.behind_shut and float(r.moved) < 0.01 and r.swinging
			and float(r.angle) < -10.0 and float(r.angle) > -95.0,
			"shut by his hand with him in its way, the leaf stops against him: it does not sweep him out through the doorway", r)
	check(r.shut_after, "he steps back: then it shuts", r)
	check(int(r.hits) == 0 and int(r.gasps) == 0, "the leaf shut by his hand does not strike him", r)
	# Hidden behind the stove right where the leaf comes: it is not in his way.
	var nook := w.nook as HideSpot
	nook.admit(player)
	await frames(2)
	var hid_at := player.global_position
	var door := (load("res://src/props/izba_door.tscn") as PackedScene).instantiate() as IzbaDoor
	door.enemies_can_open = false
	root.add_child(door)
	door.global_position = Vector3(hid_at.x, 0, hid_at.z) - at
	await frames(2)
	var hidden_struck := [0]
	var on_hidden_sound := func(id: String, _p: AudioStreamPlayer3D) -> void:
		if id == "door_hit" or id == "breath_gasp":
			hidden_struck[0] += 1
	Sfx.played.connect(on_hidden_sound)
	Engine.time_scale = 4.0
	door.open(true)
	await _swung(door)
	Engine.time_scale = 1.0
	Sfx.played.disconnect(on_hidden_sound)
	check(player.global_position.distance_to(hid_at) < 0.001 and absf(door.rotation_degrees.y - (-100.0)) < 0.5
			and hidden_struck[0] == 0,
			"hidden where the leaf swings, the boy is not moved or struck, and the door opens all the way",
			[player.global_position.distance_to(hid_at), door.rotation_degrees.y, hidden_struck[0]])
	nook.eject(player)
	door.queue_free()
	await frames(2)
	# Held by the collar (Player.seized) in the leaf's way: it stops against him.
	player.seized = true
	r = await _leaf_case(root, player, true, 1.0, at, null, false)
	player.seized = false
	check(float(r.into) < 0.01 and float(r.moved) < 0.01 and r.swinging,
			"a boy held by the collar is not dragged about by the leaf: it stops against him", r)
	check(int(r.hits) == 0 and int(r.gasps) == 0 and float(r.panic) < 0.35,
			"held by the collar, he is not struck by the kicked leaf either", r)
	root.queue_free()
	await frames(3)
	PanicSystem.reset()


## A shut door stops a dog (docs/ARCHITECTURE.md, "Дверь избы"): sent
## through it, the shepherd stays on its side of the leaf; opened, the door
## lets it through.
func _test_dog_at_shut_door() -> void:
	var w := await _search_world()
	var root := w.root as Node3D
	(w.soldier as Enemy).set_physics_process(false)
	var door := (load("res://src/props/izba_door.tscn") as PackedScene).instantiate() as IzbaDoor
	door.position = Vector3(-10, 0, -10)
	door.enemies_can_open = false
	root.add_child(door)
	var dog := (load("res://src/ai/dog.tscn") as PackedScene).instantiate() as Dog
	dog.position = door.position + Vector3(0.6, 0, -1.5)
	dog.hold_position = true
	root.add_child(dog)
	await frames(3)
	dog.nav_agent = null
	dog.script_goto([door.position + Vector3(0.6, 0, 1.5)] as Array[Vector3])
	var furthest := -INF
	for i in 180:  # three seconds of game time
		await get_tree().physics_frame
		furthest = maxf(furthest, dog.global_position.z - door.global_position.z)
	check(furthest < 0.0 and dog.has_script_route(),
			"sent through a shut door, the dog stays on its side of the leaf", furthest)
	door.open()
	await _swung(door)
	var t0 := Time.get_ticks_msec()
	while dog.has_script_route() and Time.get_ticks_msec() - t0 < 6000:
		await get_tree().physics_frame
	check(not dog.has_script_route() and dog.global_position.z - door.global_position.z > 1.0,
			"opened, the door lets it through", dog.global_position - door.global_position)
	root.queue_free()
	await frames(3)
	PanicSystem.reset()


## A door the story holds shut (enemies_can_open off; docs/ARCHITECTURE.md,
## "Дверь избы"): a soldier on his round by it leaves it shut; a soldier
## after the boy kicks it in, and from then on it is held no more.
func _test_held_door() -> void:
	var w := await _search_world()
	var root := w.root as Node3D
	var soldier := w.soldier as Enemy
	var door := (load("res://src/props/izba_door.tscn") as PackedScene).instantiate() as IzbaDoor
	door.position = Vector3(-10, 0, -10)
	door.enemies_can_open = false
	root.add_child(door)
	await frames(1)
	soldier.global_position = door.global_position + Vector3(0.6, 0, -1.0)  # outside, 1.2 m from the hinge
	soldier.velocity = Vector3.ZERO
	soldier.stand_down()
	soldier.hold_position = true
	soldier._post = soldier.global_transform
	var kicks := [0]
	var on_sound := func(id: String, _p: AudioStreamPlayer3D) -> void:
		if id == "door_kick":
			kicks[0] += 1
	Sfx.played.connect(on_sound)
	for i in 60:  # a second of game time
		await get_tree().physics_frame
	check(not door.is_open and soldier.state == Enemy.State.PATROL and kicks[0] == 0,
			"a soldier on his round by a door the story holds shut leaves it shut",
			[door.is_open, soldier.state, kicks[0]])
	soldier.alert_to(door.global_position + Vector3(0.6, 0, 1.5), 0.7)
	for i in 5:
		await get_tree().physics_frame
	Sfx.played.disconnect(on_sound)
	check(door.is_open and kicks[0] == 1 and door.enemies_can_open,
			"a soldier after the boy kicks it in, and from then on the story holds it shut no more",
			[door.is_open, kicks[0], door.enemies_can_open, soldier.state])
	await _swung(door)
	root.queue_free()
	await frames(3)
	PanicSystem.reset()


## The izba door opened (`kick`: kicked in) - or, `shutting`, standing open
## and shut by his latch (kicked open first, with him out of the arc) - with
## the boy standing `at` (in the door's own
## frame) in its leaf's way, game time running `speed` times as fast; `wall`,
## if any, set up 0.35 m behind him. Returns: into - the most the leaf was
## ever into him (m); moved - how far he was moved; reach - his distance
## from the hinge after, tip - the leaf's length plus his radius;
## behind - left within the leaf's reach on the side an opening leaf swings
## away from (it went through him); behind_shut - the same for a shutting
## leaf: out past the doorway; angle and swinging - where the leaf got to.
## With a wall: in_wall - how far into it he got; waited - the angle half a
## second later; then, once he has stepped out of the arc, after and
## after_swinging. Shutting: shut_after - shut once he stepped away.
## The blow (Player.struck): hits - door_hit sounds, gasps - breath_gasp
## sounds, noise - his loudest noise for enemies, panic - the most it got
## to (reset first), holding_before / holding / lockout - his held breath
## before and after (BreathControl).
func _leaf_case(root: Node3D, player: Player, kick: bool, speed: float, at: Vector3,
		wall: CSGBox3D, shutting: bool) -> Dictionary:
	var door := (load("res://src/props/izba_door.tscn") as PackedScene).instantiate() as IzbaDoor
	door.position = Vector3(-10, 0, -10)
	door.enemies_can_open = false
	root.add_child(door)
	if shutting:
		player.global_position = door.global_position + Vector3(3.0, 0, at.z)  # out of the arc
		await frames(1)
		door.open(true)
		await _swung(door)
	if wall != null:
		root.add_child(wall)
		wall.global_position = door.global_position + Vector3(0.5, 1.0, at.z + 0.25 + 0.1 + wall.size.z * 0.5)
	player.velocity = Vector3.ZERO
	player.global_position = door.global_position + at
	await frames(3)
	var start := player.global_position
	var radius := (player.collision.shape as CapsuleShape3D).radius
	var into := 0.0
	var heard := {"hits": 0, "gasps": 0, "noise": 0.0}
	var on_sound := func(id: String, _p: AudioStreamPlayer3D) -> void:
		if id == "door_hit":
			heard["hits"] += 1
		elif id == "breath_gasp":
			heard["gasps"] += 1
	var on_noise := func(_pos: Vector3, loud: float, src: Node) -> void:
		if src == player:
			heard["noise"] = maxf(float(heard["noise"]), loud)
	Sfx.played.connect(on_sound)
	Stealth.noise_emitted.connect(on_noise)
	PanicSystem.reset()
	var panic := 0.0
	var holding_before := player.breath.holding
	Engine.time_scale = speed
	if shutting:
		door.close()
	else:
		door.open(kick)
	var t0 := Time.get_ticks_msec()
	while door.is_swinging() and Time.get_ticks_msec() - t0 < (1500 if wall != null or shutting or player.seized else 6000):
		await get_tree().physics_frame
		into = maxf(into, door.leaf_push(player.global_position, door.rotation_degrees.y, radius).length())
		panic = maxf(panic, PanicSystem.level)
	Engine.time_scale = 1.0
	var rel := player.global_position - door.global_position
	var c := Vector2(rel.x, rel.z)
	var a := deg_to_rad(door.rotation_degrees.y)
	var swung := Vector2(sin(a), cos(a))  # the way an opening leaf turns: (-d.y, d.x) for d = (cos, -sin)
	var r := {"into": into, "moved": player.global_position.distance_to(start), "reach": c.length(),
			"tip": door.leaf_length + radius,
			"behind": c.length() < door.leaf_length + radius and c.dot(swung) < 0.0,
			"behind_shut": rel.z < 0.0,
			"angle": door.rotation_degrees.y, "swinging": door.is_swinging()}
	if wall != null:
		var face := wall.global_position.z - wall.size.z * 0.5
		r["in_wall"] = maxf(0.0, player.global_position.z + radius - face)
		await _wait(0.5)
		r["waited"] = door.rotation_degrees.y
		player.global_position = door.global_position + Vector3(3.0, 0, at.z)  # out of the arc
		await _swung(door)
		r["after"] = door.rotation_degrees.y
		r["after_swinging"] = door.is_swinging()
		wall.queue_free()
	if shutting:
		player.global_position = door.global_position + Vector3(3.0, 0, at.z)
		await _swung(door)
		r["shut_after"] = not door.is_open and door.blocks_sound() and not door.is_swinging()
	Sfx.played.disconnect(on_sound)
	Stealth.noise_emitted.disconnect(on_noise)
	r.merge(heard)
	r["panic"] = panic
	r["holding_before"] = holding_before
	r["holding"] = player.breath.holding
	r["lockout"] = player.breath._lockout
	door.queue_free()
	await frames(2)
	PanicSystem.reset()
	return r


# --- enemies hear through walls ----------------------------------------------------

## A sound of the boy's at `from`, heard by `soldier` standing at `at`: his
## suspicion afterwards (he starts calm).
func _heard(soldier: Enemy, at: Vector3, from: Vector3, loud: float, source: Node) -> float:
	soldier.stand_down()
	soldier.global_position = at
	await frames(1)
	Stealth.emit_noise(from, loud, source)
	return soldier.suspicion


## Anything solid (layers 1 and 5) between `a` and `b`, the last 0.25 m not
## counted - what a wall check would have hit before it looked past props.
func _solid_between(a: Vector3, b: Vector3) -> bool:
	var d := b - a
	var q := PhysicsRayQueryParameters3D.create(a, b - d.normalized() * 0.25, Stealth.LIGHT_MASK)
	return not get_viewport().find_world_3d().direct_space_state.intersect_ray(q).is_empty()


## A wall of a building (Stealth.SOUND_WALLS) in the test world.
func _sound_wall(root: Node, size: Vector3, at: Vector3) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.use_collision = true
	b.add_to_group(Stealth.SOUND_WALLS)
	root.add_child(b)
	b.global_position = at
	return b


## What enemies hear (Enemy._on_noise, Stealth.sound_walled): through the wall
## of a building or a shut door the boy is heard as if half as loud - half as
## far; hedges, haystacks and the like are not walls, nor a table over him,
## nor anything inside the same room; an open door leaf is not a door; nobody
## grabs him through a wall.
func _test_hearing_walls() -> void:
	PanicSystem.reset()
	var w := await _search_world()
	var root := w.root as Node3D
	var player := w.player as Player
	var soldier := w.soldier as Enemy
	var hatch := w.hatch as HideSpot
	var wardrobe := w.wardrobe as HideSpot
	soldier.set_physics_process(false)
	var boy := player.global_position
	var ear := Vector3.UP * soldier.eye_height
	var at5 := boy + Vector3(0, 0, -5)
	var open5 := await _heard(soldier, at5, boy, 0.5, player)
	check(absf(open5 - (1.0 - 5.0 / 7.0) * 0.5 * 0.9) < 0.002, "in the open a soldier five metres off hears a step", open5)
	var wall := _sound_wall(root, Vector3(6, 3, 0.3), boy + Vector3(0, 1.5, -1.5))
	await frames(3)
	check(Stealth.walled_off(at5 + ear, boy), "the log wall of a house between them walls the sound off")
	var walled5 := await _heard(soldier, at5, boy, 0.5, player)
	check(is_zero_approx(walled5), "through the wall the same step five metres off is not heard", walled5)
	var walled3 := await _heard(soldier, boy + Vector3(0, 0, -3), boy, 0.5, player)
	var half3 := (1.0 - 3.0 / (0.5 * Stealth.WALL_HEARING * Stealth.HEARING_RANGE)) * 0.5 * Stealth.WALL_HEARING * 0.9
	check(walled3 > 0.0 and absf(walled3 - half3) < 0.002,
			"three metres off through the wall: heard, as if half as loud", [walled3, half3])
	Stealth.noise_is_action = true  # the cellar lid, a door: plainly heard, they send him over
	await _heard(soldier, boy + Vector3(0, 0, -3), boy, 0.6, player)
	Stealth.noise_is_action = false
	check(soldier.state == Enemy.State.PATROL and soldier.suspicion < Enemy.SUSPICIOUS_AT,
			"a lid or a door through a wall does not send him over to look", [soldier.state, soldier.suspicion])
	# The same mass, but a hedge or a haystack: not a wall for sound.
	wall.remove_from_group(Stealth.SOUND_WALLS)
	var hedge := await _heard(soldier, at5, boy, 0.5, player)
	check(_solid_between(at5 + ear, boy + Vector3.UP * 1.1) and absf(hedge - open5) < 0.001,
			"a hedge, a haystack, a barricade in the way: he is heard as in the open", [hedge, open5])
	wall.queue_free()
	await frames(2)

	# A table in a house over him: in the way low down, but not a wall.
	var table := _sound_wall(root, Vector3(1.6, 0.05, 1.6), boy + Vector3(0, 0.75, 0))
	await frames(3)
	var near := boy + Vector3(0, 0, -1.5)
	check(Stealth.sound_wall_between(near + ear, boy + Vector3.UP * 0.3) and not Stealth.walled_off(near + ear, boy),
			"under a table: the table is in the way low down, but it is not a wall")
	var under := await _heard(soldier, near, boy, 0.3, player)
	check(absf(under - (1.0 - 1.5 / 4.2) * 0.3 * 0.9) < 0.002, "under the table he is heard as in the open", under)
	table.queue_free()
	# A dog's ear is low: a crate in a house next to him does not wall the boy off.
	var crate := _sound_wall(root, Vector3(1.0, 0.8, 1.0), boy + Vector3(0, 0.4, -3.4))
	await frames(3)
	soldier.global_position = boy + Vector3(0, 0, -4)
	await frames(1)
	check(Stealth.sound_wall_between(soldier.global_position + Vector3.UP * 0.65, boy + Vector3.UP * 1.1)
			and not Stealth.sound_walled(soldier, 0.65, boy),
			"a dog behind a crate: its nose is low, but the sound comes over the crate")
	crate.queue_free()

	# A shut door walls the sound off; opened, it lets it through; the leaf
	# on its way is no door.
	var door := (load("res://src/props/izba_door.tscn") as PackedScene).instantiate() as IzbaDoor
	door.position = boy + Vector3(-1.0, 0, 3.0)  # the panel runs along +X, across the line
	door.enemies_can_open = false
	root.add_child(door)
	await frames(3)
	var panel := door.get_node("Panel") as Node3D
	var doorway := door.sound_point()  # shut: the middle of the panel
	var panel_shut := panel.global_position
	var beyond := boy + Vector3(-0.4, 0, 6.0)
	var step := Player.STEP_WALK_NOISE * Player.BOARD_NOISE
	var shut := await _heard(soldier, beyond, boy, step, player)
	var shut_stops := Stealth.stops_sound(panel)
	door.open()
	var swinging := Stealth.stops_sound(panel)
	await _swung(door)
	var opened := await _heard(soldier, beyond, boy, step, player)
	check(shut_stops and not swinging and is_zero_approx(shut) and opened > 0.1,
			"a step on the boards six metres off: not heard through the shut door, heard through the open one",
			[shut_stops, swinging, shut, opened])
	var at_open := door.sound_point()
	check(doorway.distance_to(panel_shut) < 0.01 and at_open.distance_to(doorway) < 0.01
			and at_open.distance_to(panel.global_position) > 0.5,
			"open, the door still sounds from the doorway, not from its leaf in the room",
			[doorway, at_open, panel.global_position])
	door.close()
	await frames(6)
	check(absf(door.rotation_degrees.y) > 5.0 and door.sound_point().distance_to(doorway) < 0.01
			and not Stealth.stops_sound(panel),
			"swinging shut: it sounds from the doorway, and is not a door yet", door.rotation_degrees.y)
	await _swung(door)
	check(Stealth.stops_sound(panel), "shut again: a door again")
	door.queue_free()
	await frames(2)

	# The cellar: a sob heard behind a wall two steps off does not get him
	# grabbed; the same sob with no wall between does.
	hatch.admit(player)
	await frames(2)
	var away := hatch.global_position - hatch.stand_point()
	away.y = 0.0
	var far_side := hatch.global_position + away.normalized() * 1.8
	var wall2 := _sound_wall(root, Vector3(4, 3, 0.3), hatch.global_position.lerp(far_side, 0.6) + Vector3(0, 1.5, 0))
	wall2.look_at(wall2.global_position + away, Vector3.UP)
	await frames(3)
	var sob := await _heard(soldier, far_side, player.global_position, 0.6, player)
	var dist := far_side.distance_to(player.global_position)
	check(dist < 2.5 and sob > 0.0 and not soldier._caught,
			"a sob two steps off behind a wall: heard, but nobody grabs him through it", [dist, sob, soldier._caught])
	wall2.queue_free()
	await frames(2)
	await _heard(soldier, far_side, player.global_position, 0.6, player)
	check(soldier._caught, "the same sob with no wall between: he is found", soldier.suspicion)
	soldier.stand_down()
	hatch.eject(player)

	# The wardrobe's own body is no wall: climbing in a step in front of a
	# soldier sends him to look; a sob inside gets the boy found.
	var front := wardrobe.stand_point()
	player.global_position = front
	soldier.stand_down()
	soldier.global_position = front + (front - wardrobe.global_position).normalized() * 0.5
	await frames(2)
	wardrobe.interact(player)
	check(player.is_hidden and soldier.state == Enemy.State.SUSPICIOUS and not soldier._caught,
			"he climbs into the wardrobe a step from a soldier: the creak sends him to look", [soldier.state, soldier.suspicion])
	await _heard(soldier, front, player.global_position, 0.6, player)
	check(soldier._caught, "a sob in the wardrobe with a soldier at its doors: he is found", soldier.suspicion)
	soldier.stand_down()
	wardrobe.eject(player)
	root.queue_free()
	await frames(2)

	# Act I: the log walls and the door of the izba; inside it, no walls.
	var level := LEVEL.instantiate()
	level.play_intro = false
	add_child(level)
	level._ending = true  # a catch does not end the level here
	await frames(3)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set_physics_process(false)
		e.passive = true
	var guard := ENEMY_SCENE.instantiate() as Enemy
	guard.hold_position = true
	level.add_child(guard)
	await frames(2)
	guard.set_physics_process(false)
	var p1 := level.get_node("Player") as Player
	var inside := (level.get_node("Spawns/Izba") as Node3D).global_position
	p1.global_position = inside
	var izba_door := level.get_node("IzbaDoor") as IzbaDoor
	izba_door.enemies_can_open = false
	izba_door.close()  # without the intro it stands open
	await _swung(izba_door)
	check((level.get_node("IzbaA") as Node).is_in_group(Stealth.SOUND_WALLS)
			and (level.get_node("IzbaB") as Node).is_in_group(Stealth.SOUND_WALLS)
			and (level.get_node("Barn") as Node).is_in_group(Stealth.SOUND_WALLS),
			"Act I: both izbas and the barn are walls for sound")
	var street := (level.get_node("Spawns/Street") as Node3D).global_position
	var shut1 := await _heard(guard, street, inside, step, p1)
	izba_door.open()
	await _swung(izba_door)
	var open1 := await _heard(guard, street, inside, step, p1)
	check(is_zero_approx(shut1) and open1 > 0.0,
			"Act I: a soldier on the street hears steps in the izba only through the open door", [shut1, open1])
	izba_door.close()
	await _swung(izba_door)
	var izba := (level.get_node("IzbaA") as Node3D).global_position
	var west := izba + Vector3(-4.2, 0, 1.5)  # outside the west wall, clear of its window
	var by_wall := await _heard(guard, west, inside, step, p1)
	check(Stealth.walled_off(west + ear, inside) and is_zero_approx(by_wall)
			and west.distance_to(inside) < step * Stealth.HEARING_RANGE,
			"Act I: behind the log wall his steps on the boards are not heard - in the open they would be",
			[by_wall, west.distance_to(inside)])
	# The door kicked in, as in the invasion: its leaf stands in the room.
	izba_door.open(true)
	await _swung(izba_door)
	var cellar := level.get_node("IzbaA/CellarHatch") as HideSpot
	cellar.admit(p1)
	await frames(2)
	var by_door := izba + Vector3(1.4, 0, -1.9)  # just inside the door, the kicked-in leaf between him and the cellar
	var north := izba + Vector3(-0.6, 0, -2.8)  # outside the north wall, clear of its window
	guard.global_position = by_door
	await frames(1)
	var leaf_in_way := true
	for h in Stealth.SOUND_HEIGHTS:
		leaf_in_way = leaf_in_way and _solid_between(by_door + ear, p1.global_position + Vector3.UP * h)
	check(leaf_in_way and by_door.distance_to(p1.global_position) < 2.5
			and not Stealth.sound_walled(guard, guard.eye_height, p1.global_position),
			"Act I: the kicked-in leaf stands between the doorway and the cellar, but it is one room", leaf_in_way)
	var sob1 := await _heard(guard, by_door, p1.global_position, 0.6, p1)
	check(guard._caught, "Act I: a sob in the cellar with a soldier just inside the door: he is found", sob1)
	guard.stand_down()
	# Through the north window the sob is heard plainly - but no hand reaches in.
	var window := izba + Vector3(-1.4, 0, -2.9)
	guard.global_position = window
	await frames(1)
	var heard_plainly := not Stealth.sound_walled(guard, guard.eye_height, p1.global_position)
	await _heard(guard, window, p1.global_position, 0.6, p1)
	check(heard_plainly and window.distance_to(p1.global_position) < 2.5 and not guard._caught
			and guard.suspicion > 0.2,
			"Act I: under the window outside a soldier hears the sob plainly, but cannot grab him from there",
			[heard_plainly, guard._caught, guard.suspicion])
	guard.stand_down()
	await _heard(guard, north, p1.global_position, 0.6, p1)
	check(not guard._caught and p1.is_hidden and north.distance_to(p1.global_position) < 2.5,
			"Act I: the same sob, a soldier behind the north wall two steps off: nobody grabs him",
			[guard._caught, north.distance_to(p1.global_position)])
	guard.stand_down()
	cellar.eject(p1)
	# Behind the stove: the stove is no wall between him and the room.
	var nook := level.get_node("IzbaA/StoveNook") as HideSpot
	nook.admit(p1)
	await frames(2)
	var by_stove := izba + Vector3(2.2, 0, -0.4)
	guard.global_position = by_stove
	await frames(1)
	var stove_in_way := _solid_between(by_stove + ear, p1.global_position + Vector3.UP * 1.1)
	await _heard(guard, by_stove, p1.global_position, 0.6, p1)
	check(stove_in_way and guard._caught and by_stove.distance_to(p1.global_position) < 2.5,
			"Act I: behind the stove, a soldier on the other side of it in the room: a sob gets him found",
			[stove_in_way, guard._caught])
	guard.stand_down()
	nook.eject(p1)
	# Closing the open door from inside: the latch is heard on the street.
	izba_door.open()
	await _swung(izba_door)
	# He stands by the latch on the open leaf, on the side it swings away from
	# (in its way, it would stop against him: IzbaDoor._clear_way).
	p1.global_position = izba_door.global_position + Vector3(-0.7, 0, 1.0)
	guard.stand_down()
	guard.global_position = izba + Vector3(-2.0, 0, -4.5)
	await frames(2)
	izba_door.latch.interact(p1)
	check(not izba_door.is_open and guard.state == Enemy.State.SUSPICIOUS,
			"Act I: he shuts the door from inside - a soldier on the street hears the latch and comes",
			[guard.state, guard.suspicion])
	await _swung(izba_door)
	check(izba_door.blocks_sound() and p1.global_position.z > izba_door.global_position.z,
			"and the door is really shut, with him inside", [izba_door.rotation_degrees.y, p1.global_position])
	guard.stand_down()
	level.queue_free()
	await frames(2)


## Controls (Controls, ControlsPanel): the gamepad layout, rebinding keys,
## the "Управление" screen, the right stick.
# --- brightness ------------------------------------------------------------------

func _test_brightness() -> void:
	GameState.reset()
	GameState.apply_settings()
	check(is_equal_approx(GameState.brightness(), 1.0) and GameState.needs_brightness_check(),
			"by default the picture is as graded and the brightness screen is still to be seen")
	# Headless has no renderer to read the global back: check that it is
	# declared and that every pass of the picture and the test picture use it
	# (the effect itself: frames, docs/ARCHITECTURE.md "Яркость").
	var g = ProjectSettings.get_setting("shader_globals/g_brightness")
	check(typeof(g) == TYPE_DICTIONARY and g.get("type") == "float" and is_equal_approx(float(g.get("value", 0.0)), 1.0),
			"the brightness is a global shader parameter, 1.0 by default", g)
	var film := FileAccess.get_file_as_string("res://src/rendering/shaders/film_common.gdshaderinc")
	var finish := film.substr(film.find("vec3 film_finish("))
	var uses := finish.find("c = brightness_lift(c);") > 0 and finish.find("c = brightness_lift(c);") < finish.find("film_grain")
	for pass_name in ["post_base", "post_red", "post_teal"]:
		uses = uses and FileAccess.get_file_as_string("res://src/rendering/shaders/%s.gdshader" % pass_name).contains("film_finish(")
	uses = uses and FileAccess.get_file_as_string("res://src/ui/brightness_test.gdshader").contains("g_brightness")
	check(uses, "all three passes lift the shadows before the grain, and so does the test picture")
	GameState.set_setting("brightness", 1.35)
	GameState.set_setting("brightness", 9.0)
	check(is_equal_approx(GameState.brightness(), GameState.BRIGHTNESS_MAX),
			"too bright is held at the top of the range", GameState.brightness())
	GameState.set_setting("brightness", 1.35)
	GameState.load_progress()
	check(is_equal_approx(GameState.brightness(), 1.35), "the brightness is kept between games")

	# The screen in the settings.
	var layer := CanvasLayer.new()
	add_child(layer)
	var sp := SettingsPanel.new()
	layer.add_child(sp)
	await frames(2)
	sp.focus()
	sp._brightness_button.pressed.emit()
	var panel := sp._brightness
	check(sp.is_showing_brightness() and not sp._back.visible and panel.test.visible
			and (panel.test.material as ShaderMaterial).shader == BrightnessPanel.TEST_SHADER,
			"«Яркость» opens the test picture: two windows on black")
	check(panel.slider.has_focus() and is_equal_approx(panel.slider.value, 1.35),
			"the slider is in hand, at the current value", panel.slider.value)
	panel.slider.value = 1.1
	check(is_equal_approx(GameState.brightness(), 1.1), "moving the slider changes the brightness at once")
	panel._default.pressed.emit()
	check(is_equal_approx(GameState.brightness(), 1.0), "«По умолчанию» brings back the picture as graded")
	check(sp.back() and not sp.is_showing_brightness() and sp._back.visible and not GameState.needs_brightness_check(),
			"Esc / B goes back to the settings; the screen counts as seen")
	layer.queue_free()
	await frames(2)

	# The first start: straight from the main menu, «Готово» leads to the menu.
	GameState.reset()
	var menu := MAIN_MENU.instantiate()
	add_child(menu)
	await frames(2)
	check(GameState.needs_brightness_check() and not menu.wants_brightness_check() and menu._main.visible,
			"renders and test runs never stop at the brightness screen")
	menu._show(menu._settings)
	menu._settings.show_brightness(true)
	await frames(1)
	check(menu._settings.is_showing_brightness() and not menu._settings._back.visible,
			"on the first start the menu opens on the brightness screen alone")
	menu._settings._brightness._done.pressed.emit()
	await frames(1)
	check(menu._main.visible and not menu._settings.visible and not GameState.needs_brightness_check(),
			"«Готово» leads on to the main menu, and the screen is not shown at the start again")
	menu._show(menu._settings)
	check(menu._settings._back.visible and not menu._settings.is_showing_brightness(),
			"the settings open on their list afterwards")
	menu.queue_free()
	await frames(2)
	GameState.reset()
	GameState.apply_settings()


static func _key_event(code: Key, pressed: bool) -> InputEventKey:
	var k := InputEventKey.new()
	k.physical_keycode = code
	k.pressed = pressed
	return k


func _test_controls() -> void:
	GameState.reset()
	var all_bound := true
	for row in Controls.ACTIONS:
		var a: String = row[0]
		var has_key := false
		var has_pad := false
		for e in InputMap.action_get_events(a):
			has_key = has_key or e is InputEventKey
			has_pad = has_pad or e is InputEventJoypadButton or e is InputEventJoypadMotion
		all_bound = all_bound and has_key and has_pad and Controls.PAD_NAMES.has(a)
	check(all_bound, "every action has a key and a gamepad control")
	var rs := InputEventJoypadMotion.new()
	rs.axis = JOY_AXIS_RIGHT_X
	rs.axis_value = 1.0
	var rt := InputEventJoypadMotion.new()
	rt.axis = JOY_AXIS_TRIGGER_RIGHT
	rt.axis_value = 1.0
	var start := InputEventJoypadButton.new()
	start.button_index = JOY_BUTTON_START
	check(InputMap.action_has_event("look_right", rs) and InputMap.action_has_event("hold_breath", rt)
			and InputMap.action_has_event("ui_cancel", start),
			"gamepad: the right stick looks, the right trigger holds the breath, Start pauses")

	check(Controls.key_of("interact") == KEY_E and Controls.key_of("hold_breath") == KEY_SPACE,
			"by default E acts, Space holds the breath")
	GameState.set_setting("keys", Controls.rebind(GameState.settings["keys"], "interact", KEY_F))
	var f := InputEventKey.new()
	f.physical_keycode = KEY_F
	f.pressed = true
	var e_key := InputEventKey.new()
	e_key.physical_keycode = KEY_E
	e_key.pressed = true
	check(Controls.key_of("interact") == KEY_F and f.is_action_pressed("interact") and not e_key.is_action_pressed("interact"),
			"a new key for an action: F acts, E no longer")
	GameState.set_setting("keys", Controls.rebind(GameState.settings["keys"], "interact", KEY_SPACE))
	check(Controls.key_of("interact") == KEY_SPACE and Controls.key_of("hold_breath") == KEY_F,
			"a key taken from another action: the two swap", [Controls.key_of("interact"), Controls.key_of("hold_breath")])
	GameState.save()
	GameState.reset()
	check(Controls.key_of("interact") == KEY_E, "a reset brings the default keys back")
	GameState.load_progress()
	GameState.apply_settings()
	check(Controls.key_of("interact") == KEY_SPACE and Controls.key_of("hold_breath") == KEY_F,
			"changed keys are kept between games")
	# A save from before «Выглянуть» took Q may give Q to another action: Q
	# stays with it, and «Выглянуть» takes that action's own key.
	Controls.apply_keys({"inventory": KEY_Q})
	var on_q := 0
	for row in Controls.ACTIONS:
		on_q += 1 if Controls.key_of(row[0]) == KEY_Q else 0
	check(Controls.key_of("inventory") == KEY_Q and Controls.key_of("lean") == Controls.default_key("inventory")
			and Controls.default_key("inventory") != 0 and on_q == 1,
			"a key saved for an action before «Выглянуть» took it stays there; «Выглянуть» takes that action's key",
			[Controls.key_of("inventory"), Controls.key_of("lean")])
	GameState.apply_settings()
	# On a Mac control + Space switches the keyboard layout: with crouch on
	# Ctrl the boy could not crouch and hold his breath at once.
	var pc := {"crouch": KEY_CTRL, "hold_breath": KEY_SPACE, "interact": KEY_E}
	var mac := Controls.platform_defaults(pc, "macOS")
	var win := Controls.platform_defaults(pc, "Windows")
	check(int(mac["crouch"]) == KEY_C and int(mac["hold_breath"]) == KEY_SPACE and int(mac["interact"]) == KEY_E
			and int(win["crouch"]) == KEY_CTRL and int(pc["crouch"]) == KEY_CTRL,
			"on a Mac crouch is C by default (control + Space switches the layout there), elsewhere Ctrl", [mac, win])
	var on_c: Array[String] = []
	for row in Controls.ACTIONS:
		if row[0] != "crouch" and Controls.default_key(row[0]) == KEY_C:
			on_c.append(row[0])
	check(Controls.default_key("crouch") == (KEY_C if OS.get_name() == "macOS" else KEY_CTRL) and on_c.is_empty(),
			"no other action has C by default, so a Mac's crouch takes no one's key", on_c)

	# The screen.
	var layer := CanvasLayer.new()
	add_child(layer)
	var sp := SettingsPanel.new()
	layer.add_child(sp)
	await frames(2)
	sp.focus()
	sp.show_controls()
	var panel := sp._controls
	check(sp.is_showing_controls() and not sp._back.visible and panel._keys.size() == Controls.ACTIONS.size(),
			"«Управление» opens the list of every action")
	# A name wider than its column pushes its key out of the key column
	# (until 20.11.2026 «Взять, открыть, спрятаться; в сумке — применить» did).
	var too_wide: Array[String] = []
	for line in panel.get_children():
		if line is HBoxContainer and line.get_child(0) is Label:
			var name_cell := line.get_child(0) as Label
			if name_cell.get_minimum_size().x > ControlsPanel.NAME_WIDTH:
				too_wide.append(name_cell.text)
	check(too_wide.is_empty(), "every action's name fits its column", too_wide)
	check(str((panel._keys["interact"] as Button).get_meta("label")) == "Пробел"
			and str((panel._keys["move_forward"] as Button).get_meta("label")) == "W",
			"each key is named: W, Пробел", (panel._keys["interact"] as Button).get_meta("label"))
	(panel._keys["crouch"] as Button).pressed.emit()
	check(panel.waiting == "crouch" and str((panel._keys["crouch"] as Button).get_meta("label")) == "…",
			"choosing a row waits for the new key")
	var crouch_key := Controls.key_of("crouch")
	panel._input(_key_event(KEY_C, true))
	check(Controls.key_of("crouch") == crouch_key and panel.waiting == "crouch", "a key is not taken on its press")
	panel._input(_key_event(KEY_C, false))
	check(Controls.key_of("crouch") == KEY_C and panel.waiting == ""
			and str((panel._keys["crouch"] as Button).get_meta("label")) == "C",
			"the key pressed and released is the new key")
	panel._input(_key_event(KEY_W, true))
	(panel._keys["sprint"] as Button).pressed.emit()
	var sprint_key := Controls.key_of("sprint")
	panel._input(_key_event(KEY_W, false))
	panel._input(_key_event(KEY_NONE, false))
	check(Controls.key_of("sprint") == sprint_key and panel.waiting == "sprint",
			"a release with no press while waiting is no key (W held while the row was chosen, a key with no code)")
	panel._input(_key_event(KEY_META, true))
	panel._input(_key_event(KEY_META, false))
	check(Controls.key_of("sprint") == sprint_key and panel.waiting == "sprint",
			"Win / Cmd is never taken (Windows opens Start on its release)")
	panel._input(_key_event(KEY_ESCAPE, true))
	check(Controls.key_of("sprint") == sprint_key and panel.waiting == "" and sp.is_showing_controls(),
			"Esc leaves the key as it was and stays in the list")
	(panel._keys["sprint"] as Button).pressed.emit()
	panel._input(_key_event(KEY_ALT, true))
	panel.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	panel._input(_key_event(KEY_ALT, false))
	check(Controls.key_of("sprint") == sprint_key and panel.waiting == ""
			and str((panel._keys["sprint"] as Button).get_meta("label")) == Controls.key_name(sprint_key),
			"Alt + Tab away from «…» leaves the key as it was: the focus loss cancels the wait")
	(panel._keys["sprint"] as Button).pressed.emit()
	panel._input(_key_event(KEY_ALT, true))
	panel._input(_key_event(KEY_ALT, false))
	check(Controls.key_of("sprint") == KEY_ALT and panel.waiting == "", "Alt pressed and released on its own is still a key")
	panel._reset.pressed.emit()
	check(Controls.key_of("crouch") == Controls.default_key("crouch") and Controls.key_of("interact") == KEY_E
			and (GameState.settings["keys"] as Dictionary).is_empty(), "the default keys can be brought back")
	check(sp.back() and not sp.is_showing_controls() and sp._back.visible,
			"Esc / B goes from the controls back to the settings")
	check(not sp.back(), "from the settings the menu itself goes back")
	layer.queue_free()
	await frames(2)

	var fake := Node3D.new()
	fake.add_to_group("levels")
	add_child(fake)
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	PauseMenu.open()
	PauseMenu._show_settings()
	PauseMenu._settings.show_controls()
	PauseMenu._unhandled_input(esc)
	check(PauseMenu.is_open and PauseMenu._settings.visible and not PauseMenu._settings.is_showing_controls(),
			"in the pause too: Esc from the controls back to the settings")
	PauseMenu._unhandled_input(esc)
	check(PauseMenu._list.visible, "then to the pause list")
	PauseMenu.close()
	fake.queue_free()
	await frames(2)

	# The right stick turns him; a light tilt turns him slowly. As rates
	# (_stick_rate), not angles after a set wait: load stretches the wait.
	var w := await _search_world()
	var player := w.player as Player
	var full := await _stick_rate(player, 1.0)
	check(full > 2.2 and full < 3.0, "the right stick turns him (about 2.6 rad/s)", full)
	await _passes()
	var yaw := player.rotation.y
	await _passes(3)
	check(absf(angle_difference(yaw, player.rotation.y)) < 0.0001, "and he stops when it is let go")
	var light := await _stick_rate(player, 0.35)
	# Quadratic past the dead zone: Input.get_vector maps 0.35 to
	# (0.35 - 0.15) / 0.85 of full tilt, and the player squares it.
	var want := pow(inverse_lerp(Controls.STICK_DEADZONE, 1.0, 0.35), 2.0)
	check(light > 0.0 and absf(light / full - want) < want * 0.1,
			"a light tilt turns him slowly, for fine aim (quadratic past the dead zone)", [light, full, want])
	GameState.set_setting("mouse_sensitivity", 2.0)
	var doubled := await _stick_rate(player, 1.0)
	GameState.set_setting("mouse_sensitivity", 1.0)
	check(absf(doubled - full) < full * 0.02, "the mouse sensitivity does not change the stick",
			[doubled, full])
	(w.root as Node).queue_free()
	await frames(2)
	GameState.reset()


func _test_gunfire() -> void:
	PanicSystem.reset()
	Perception.reset()
	var level := LEVEL.instantiate()
	level.play_intro = false
	add_child(level)
	level._ending = true
	await frames(3)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set_physics_process(false)
	var gunfire := level.get_node("Gunfire") as GunfireAmbience
	var player := level.get_node("Player") as Player
	check(gunfire.active and gunfire.get_child_count() >= 3,
			"after the invasion distant shots are on, from several far places")
	var nearest := INF
	for m in gunfire.get_children():
		nearest = minf(nearest, (m as Node3D).global_position.distance_to(player.global_position))
	check(nearest > 50.0, "every source is far off, out of sight", nearest)

	var sounds: Array[String] = []
	var on_sound := func(id: String, _p: AudioStreamPlayer3D) -> void: sounds.append(id)
	Sfx.played.connect(on_sound)
	var noises := [0]
	var on_noise := func(_pos: Vector3, _l: float, _s: Node) -> void: noises[0] += 1
	Stealth.noise_emitted.connect(on_noise)

	PanicSystem.level = 0.0
	var near_at := player.global_position + Vector3(55, 0, 0)
	# The dip lasts 0.06 s down and 0.4 s back. Game time is slowed twenty
	# times, and the view is watched until the dip shows, not for a set time:
	# a hitch of a frame under the load of the whole suite, even of seconds,
	# cannot carry it past its bottom unseen. (Watched for 600 ms at x0.25,
	# it saw no frame of the dip at all in 3 runs of 6 on 19.11.2026, with a
	# game running on the same machine: dip 0.0.)
	Engine.time_scale = 0.05
	var near := gunfire.fire(false, near_at)
	check(absf(PanicSystem.level - near) < 0.02 and absf(near - gunfire.near_spike) < 0.02,
			"a shot close by jolts the panic by near_spike", [near, PanicSystem.level])
	check(sounds.has("gunshot_far"), "a single shot is heard", sounds)
	# The dip is a tween (idle frames); physics frames can come in a burst.
	var dip := 0.0
	var seen := 0
	var longest := 0
	var tf := Time.get_ticks_msec()
	var last := tf
	while dip >= -0.03 and Time.get_ticks_msec() - tf < 4000:
		await get_tree().process_frame
		var now := Time.get_ticks_msec()
		longest = maxi(longest, now - last)
		last = now
		seen += 1
		dip = minf(dip, player.camera.v_offset)
	Engine.time_scale = 1.0
	check(dip < -0.03, "the boy flinches",
			{"dip": dip, "frames": seen, "longest_ms": longest, "flinched_is_him": Stealth.player == player})
	await get_tree().create_timer(0.8).timeout
	check(absf(player.camera.v_offset) < 0.005, "and his view comes back", player.camera.v_offset)
	PanicSystem.level = 0.0
	var far := gunfire.fire(false, player.global_position + Vector3(0, 0, 450))
	check(far < near * 0.4 and absf(far - gunfire.far_spike) < 0.02,
			"a far shot frightens much less", [far, near])
	PanicSystem.level = 0.0
	var burst := gunfire.fire(true, near_at)
	check(burst > near * 1.2 and sounds.has("gunfire_burst_far"),
			"a burst frightens more than a single shot", [burst, near, sounds])
	check(noises[0] == 0, "the enemies do not hear it as the boy's noise", noises[0])
	Stealth.noise_emitted.disconnect(on_noise)

	# The timers: silent while muted, firing when not, waiting in a safe zone.
	gunfire.first_delay_min = 0.1
	gunfire.first_delay_max = 0.2
	gunfire.interval_min = 0.2
	gunfire.interval_max = 0.3
	gunfire.active = false
	gunfire.active = true
	var before := gunfire.shots
	await get_tree().create_timer(0.8).timeout
	check(gunfire.shots == before, "muted (tests, --no-gunfire): no shots by the timer")
	GunfireAmbience.muted = false
	Perception.enter_safe_zone()
	await get_tree().create_timer(0.8).timeout
	check(gunfire.shots == before, "no shots inside a safe zone")
	Perception.exit_safe_zone()
	var t0 := Time.get_ticks_msec()
	while gunfire.shots == before and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
	check(gunfire.shots > before, "after leaving it the shots come", Time.get_ticks_msec() - t0)
	GunfireAmbience.muted = true
	Sfx.played.disconnect(on_sound)
	level.queue_free()
	await frames(2)
	PanicSystem.reset()

	# With the opening: quiet through the prologue, on when the squad leaves.
	level = LEVEL.instantiate()
	add_child(level)
	level._ending = true
	await frames(3)
	gunfire = level.get_node("Gunfire") as GunfireAmbience
	var seq := level.get_node("Invasion") as InvasionSequence
	check(seq.beat == InvasionSequence.Beat.PROLOGUE and not gunfire.active,
			"no shots in the prologue: the last quiet evening")
	seq.beat_changed.emit(InvasionSequence.Beat.SEARCH)
	check(not gunfire.active, "nor while the izba is searched")
	seq.beat_changed.emit(InvasionSequence.Beat.ESCAPE)
	check(gunfire.active, "they start when the squad has gone")
	level.queue_free()
	await frames(2)

	var act2 := ACT2.instantiate()
	act2.play_intro = false
	add_child(act2)
	act2._ending = true
	await frames(3)
	var g2 := act2.find_child("Gunfire", true, false) as GunfireAmbience
	check(g2 != null and g2.active and g2.get_child_count() == 3, "Act II: shots far off from the start")
	# The thicket that closes the road is invisible: it must not muffle the shots.
	var p2 := act2.get_node("Player") as Player
	p2.global_position = (act2.get_node("Spawns/Field") as Node3D).global_position
	await frames(2)
	var walled: Array[String] = []
	for src in g2.get_children():
		if Sfx.is_occluded((src as Node3D).global_position):
			walled.append(src.name)
	var unseen_walls: Array[String] = []
	for b in act2.find_children("*", "CSGShape3D", true, false):
		if not (b as CSGShape3D).visible and (b as Node).is_in_group(Stealth.SOUND_WALLS):
			unseen_walls.append(b.name)
	check(walled.is_empty() and unseen_walls.is_empty(),
			"Act II: no far shot is muffled - the invisible thicket, the wire and the hedge are no walls",
			[walled, unseen_walls])
	act2.queue_free()
	await frames(2)
	PanicSystem.reset()


## The navmesh source collected by hand (RuntimeNavRegion.collect_source: CSG
## through its collision faces, everything else through the engine's own
## parsers) is what the engine's parse of the same nodes gives - case by case,
## including the ones no level has yet.
func _test_nav_source() -> void:
	var cases := {}
	# A level root away from the origin: the faces go into the root's space.
	var moved := Node3D.new()
	moved.position = Vector3(10, 0, 0)
	var floor_csg := CSGBox3D.new()
	floor_csg.use_collision = true
	floor_csg.size = Vector3(4, 1, 4)
	moved.add_child(floor_csg)
	cases["a root away from the origin, CSG only"] = moved
	# A static body among CSG.
	var with_body := Node3D.new()
	with_body.position = Vector3(-5, 0, 3)
	var csg_wall := CSGBox3D.new()
	csg_wall.use_collision = true
	with_body.add_child(csg_wall)
	var crate := StaticBody3D.new()
	crate.position = Vector3(0, 0, 6)
	var crate_shape := CollisionShape3D.new()
	crate_shape.shape = BoxShape3D.new()
	crate.add_child(crate_shape)
	with_body.add_child(crate)
	cases["CSG and a static body"] = with_body
	# The root handed in is itself a static body.
	var body := StaticBody3D.new()
	var body_shape := CollisionShape3D.new()
	var body_box := BoxShape3D.new()
	body_box.size = Vector3(4, 1, 4)
	body_shape.shape = body_box
	body.add_child(body_shape)
	cases["a root that is a static body"] = body
	# An obstacle that cuts the navmesh.
	var with_obstacle := Node3D.new()
	var obstacle := NavigationObstacle3D.new()
	obstacle.affect_navigation_mesh = true
	obstacle.vertices = PackedVector3Array([Vector3(-1, 0, -1), Vector3(1, 0, -1),
			Vector3(1, 0, 1), Vector3(-1, 0, 1)])
	obstacle.height = 2.0
	with_obstacle.add_child(obstacle)
	cases["a navigation obstacle"] = with_obstacle
	# A GridMap with collision.
	var with_grid := Node3D.new()
	var lib := MeshLibrary.new()
	lib.create_item(0)
	lib.set_item_mesh(0, BoxMesh.new())
	lib.set_item_shapes(0, [BoxShape3D.new(), Transform3D()])
	var grid := GridMap.new()
	grid.mesh_library = lib
	for x in 3:
		for z in 3:
			grid.set_cell_item(Vector3i(x, 0, z), 0)
	with_grid.add_child(grid)
	cases["a GridMap"] = with_grid
	# A CSG with nothing left (its only child hidden): no faces at all.
	var empty := Node3D.new()
	var comb := CSGCombiner3D.new()
	comb.use_collision = true
	var hidden := CSGBox3D.new()
	hidden.visible = false
	comb.add_child(hidden)
	empty.add_child(comb)
	cases["a CSG with nothing left"] = empty
	for k: String in cases:
		add_child(cases[k])
	await frames(3)  # CSG builds its shape a frame after entering the tree
	for k: String in cases:
		var root: Node = cases[k]
		var nm := NavigationMesh.new()
		nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		nm.geometry_collision_mask = 1 | Stealth.SEE_THROUGH_LAYER
		var engine := NavigationMeshSourceGeometryData3D.new()
		NavigationServer3D.parse_source_geometry_data(nm, engine, root)
		var ours := RuntimeNavRegion.collect_source(nm, root)
		var want := _nav_source_desc(engine)
		var got := _nav_source_desc(ours)
		var something := (engine.get_indices().size() > 0 or engine.get_projected_obstructions().size() > 0
				or k == "a CSG with nothing left")
		check(want == got and something, "navmesh source by hand = the engine's: " + k,
				"engine %s, ours %s" % [want, got])
	for k: String in cases:
		(cases[k] as Node).queue_free()
	await frames(1)


func _nav_source_desc(s: NavigationMeshSourceGeometryData3D) -> String:
	return "tris=%d bounds=%s obstructions=%d" % [s.get_indices().size() / 3, s.get_bounds(),
			s.get_projected_obstructions().size()]


## The dog picks up the trail, walks it towards the player and barks; the
## handler follows the barking. An old trail goes cold.
func _test_scent_trail() -> void:
	PanicSystem.reset()
	var level := LEVEL.instantiate()
	level.play_intro = false
	add_child(level)
	level._ending = true
	var nav := level.get_node("Navigation") as RuntimeNavRegion
	var t0 := Time.get_ticks_msec()
	while not nav.is_baked and Time.get_ticks_msec() - t0 < 10000:
		await get_tree().physics_frame
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set_physics_process(false)
	var player := level.get_node("Player") as Player
	player.get_node("BreathControl").set_physics_process(false)
	player.set_physics_process(false)
	player.global_position = Vector3(-20, 0, 20)  # out of smell range
	var dog := level.get_node("Shepherd") as Dog
	var handler := level.get_node("SoldierRoad") as Enemy
	check(Stealth.scent_trail.is_empty(), "a new level starts without a trail")

	# A walk across open ground, west along z = 12.
	for i in 12:
		Stealth.lay_scent(Vector3(10.0 - i * 1.5, 0, 12))
	check(Stealth.scent_trail.size() == 12, "steps leave a trail", Stealth.scent_trail.size())
	dog.global_position = Vector3(10.5, 0, 12)
	handler.global_position = Vector3(12, 0, 12)
	dog.set_physics_process(true)
	handler.set_physics_process(true)
	var barks0 := dog.barks
	var furthest := 99.0
	for f in 600:
		await get_tree().physics_frame
		furthest = minf(furthest, dog.global_position.x)
	check(dog.barks > barks0, "the dog barks on the trail", dog.barks - barks0)
	check(furthest < -2.0, "the dog walks the trail to its end", furthest)
	check(handler.global_position.x < 9.0, "the handler follows the barking", handler.global_position)

	# Climbing into a hiding place, his trail runs on to where he stood and
	# into the place (Stealth.scent_into). Here he walks in at the gate and
	# reaches for the hay's near corner from the far edge of his reach: he
	# stands 3.06 m from the middle of the hay - out of a dog's nose through
	# hay (2.7 m) and a little over Dog.MAX_TRAIL_GAP (3 m) - and his last
	# step is 1 m short of that. Only the point in the hay, followed across
	# that gap, brings a dog near enough.
	dog.set_physics_process(false)
	handler.set_physics_process(false)
	Stealth.clear_scent()
	var hay := level.get_node("Barn/HayHide") as HideSpot
	var stood := Vector3(11.18, 0, -3.32)
	for x in [6.6, 7.8, 9.0, 10.2]:
		Stealth.lay_scent(Vector3(x, 0, -3.0 - (x - 6.6) / 18.0))
	player.global_position = stood
	hay.interact(player)
	var pts := Stealth.scent_trail.map(func(pt: Dictionary) -> Vector3: return pt["pos"])
	var far := Vector2(stood.x - hay.global_position.x, stood.z - hay.global_position.z).length()
	check(player.is_hidden and pts.size() == 6 and (pts[4] as Vector3).distance_to(stood) < 0.01
			and (pts[5] as Vector3).distance_to(hay.global_position) < 0.01 and far > Dog.MAX_TRAIL_GAP,
			"climbing into the hay, his trail runs on to where he stood and into the hay", [pts, far])
	for e: Enemy in [dog, handler]:
		e.suspicion = 0.0
		e._set_state(Enemy.State.PATROL)
	dog.trail_seq = -1
	dog._trail_end_seq = -1
	dog.global_position = Vector3(6.0, 0, -3.0)  # by the first step
	handler.global_position = Vector3(4.5, 0, -3.0)
	dog.set_physics_process(true)
	handler.set_physics_process(true)
	var smelled := false
	for f in 900:
		await get_tree().physics_frame
		if dog.state == Enemy.State.ALERT:
			smelled = true
			break
	check(smelled and dog.last_known.distance_to(player.global_position) < 0.5,
			"a dog on that trail comes to the hay and smells him in it",
			[Enemy.State.keys()[dog.state], dog.global_position, dog.suspicion])
	dog.set_physics_process(false)
	handler.set_physics_process(false)
	hay.eject(player)

	# A trail older than SCENT_LIFETIME is not picked up.
	Stealth.clear_scent()
	Stealth.lay_scent(Vector3(10, 0, 16))
	Stealth.clock += Stealth.SCENT_LIFETIME + 1.0
	check(Stealth.freshest_scent_near(Vector3(10, 0, 16), 2.0).is_empty(), "an old trail is cold")
	Stealth.clear_scent()
	level.queue_free()
	await frames(2)


## Phantom sounds: only the boy hears them, only when panicking.
func _test_phantoms() -> void:
	PanicSystem.reset()
	var level := LEVEL.instantiate()
	level.play_intro = false
	add_child(level)
	level._ending = true
	await frames(3)
	var player := level.get_node("Player") as Player
	var ph := player.get_node("PhantomSounds") as PhantomSounds
	var played: Array = []
	ph.phantom_played.connect(func(id: String, pos: Vector3) -> void: played.append([id, pos]))
	var heard: Array = []
	var listener := func(_p: Vector3, _l: float, src: Node) -> void: heard.append(src)
	Stealth.noise_emitted.connect(listener)
	ph._timer = 0.0
	for f in 5:
		await get_tree().process_frame  # phantoms run in _process
	check(played.is_empty(), "no phantoms when calm")
	PanicSystem.floor_level = 0.95
	PanicSystem.level = 0.95
	ph._timer = 0.0
	for f in 5:
		await get_tree().process_frame  # phantoms run in _process
	check(played.size() == 1, "panic brings a phantom sound", played.size())
	var heard_from_phantom := false
	for src in heard:
		if src == null or src == ph:
			heard_from_phantom = true
	check(not heard_from_phantom, "enemies do not hear phantoms")
	if not played.is_empty():
		var to: Vector3 = played[0][1] - player.global_position
		var fwd := -player.head.global_transform.basis.z
		check(to.normalized().dot(fwd) < 0.0, "phantoms come from behind")
	Stealth.noise_emitted.disconnect(listener)
	PanicSystem.reset()
	level.queue_free()
	await frames(2)


## Panic lies to the eye (PhantomFigure): a coat on a post is a figure at the
## edge of the view, and a post again when looked at straight. It shows up
## only where the boy is not looking, one at a time; only he sees it.
func _test_phantom_figures() -> void:
	PanicSystem.reset()
	Perception.reset()
	var root := Node3D.new()
	# As in a level: stops when the game is paused (the runner itself never does).
	root.process_mode = Node.PROCESS_MODE_PAUSABLE
	var ground := CSGBox3D.new()
	ground.size = Vector3(80, 1, 80)
	ground.position = Vector3(0, -0.5, 0)
	ground.use_collision = true
	root.add_child(ground)
	var player := PLAYER_SCENE.instantiate() as Player
	root.add_child(player)
	var post := PhantomFigure.new()
	post.chance = 1.0
	post.position = Vector3(0, 0, -15)
	root.add_child(post)
	var other := PhantomFigure.new()
	other.chance = 1.0
	other.disguise = PhantomFigure.Disguise.STUMP
	other.position = Vector3(8, 0, -15)
	root.add_child(other)
	add_child(root)
	await frames(3)
	player.set_physics_process(false)
	player.get_node("BreathControl").set_physics_process(false)
	player.get_node("PhantomSounds").set_process(false)
	player.global_position = Vector3.ZERO
	# Shown only by hand below; seen through, eased and the rest run by itself.
	post._check = 1e9
	other._check = 1e9
	var chest := post.global_position + Vector3.UP * 1.2
	var away := Vector3(0, 1.35, 15)
	var gone: Array[bool] = []
	post.dispelled.connect(func(looked: bool) -> void: gone.append(looked))
	var t0 := 0
	# Only the boy sees it: it never makes a sound for anyone.
	var noises: Array[int] = [0]
	var on_noise := func(_at: Vector3, _loud: float, source: Node) -> void:
		if source != null and (source == post or source == other or post.is_ancestor_of(source)
				or other.is_ancestor_of(source)):
			noises[0] += 1
	Stealth.noise_emitted.connect(on_noise)

	player.look_towards(away)
	check(not post.try_show(player) and not post.figure.visible, "calm: the coat on the post stays a coat")
	PanicSystem.floor_level = 0.9
	PanicSystem.level = 0.9
	_look_aside(player, chest, 25.0)
	check(post.in_view(player.camera) and not post.try_show(player),
			"panic: a figure never appears before his eyes")
	player.look_towards(away)
	check(post.try_show(player) and post.shown and post.figure.visible,
			"panic: out of the view the coat on the post becomes a figure")
	check(post.thing.visible and post.thing.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY,
			"the post is not drawn while the figure stands, its shadow stays")
	var facing := -post.figure.global_transform.basis.z
	var to_boy := (player.global_position - post.global_position) * Vector3(1, 0, 1)
	check(facing.dot(to_boy.normalized()) > 0.95, "the figure stands turned to the boy")
	check(not other.try_show(player), "one figure at a time")
	_look_aside(player, chest, 25.0)
	for f in 5:
		await get_tree().process_frame
	check(post.shown and post.in_view(player.camera), "at the edge of the view the figure stands")
	PanicSystem.floor_level = 0.0
	PanicSystem.level = 0.1
	t0 = Time.get_ticks_msec()
	while Perception.distortion > 0.15 and Time.get_ticks_msec() - t0 < 2000:
		await get_tree().process_frame
	check(post.shown and post.in_view(player.camera),
			"calmer, a figure in his view does not vanish before his eyes")
	var grot := post._parts[0].get_instance_shader_parameter("grotesque") as float
	check(minf(Perception.distortion * grot, 1.0) >= PhantomFigure.MIN_DRAWN - 0.01,
			"and it stays drawn the way fear drew it, not as an ordinary man",
			"%.2f x %.2f" % [Perception.distortion, grot])
	PanicSystem.floor_level = 0.9
	PanicSystem.level = 0.9
	player.look_towards(chest)
	for f in 3:
		await get_tree().process_frame
	check(not post.shown and not post.figure.visible and gone == [true],
			"looked at straight, it is a coat on a post again", gone)
	check(post.thing.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "the post is drawn again")
	player.look_towards(away)
	check(not post.try_show(player) and post._cool > 20.0, "seen through, it keeps away for long", post._cool)
	check(other._cool > 15.0 and not other.try_show(player),
			"one seen through, the other places keep quiet too", other._cool)
	other._cool = 0.0

	# A low wall hides the coat, not the head fear would draw above it.
	post._cool = 0.0
	var low := CSGBox3D.new()
	low.size = Vector3(6, 2, 0.3)
	low.position = Vector3(0, 1, -8)
	low.use_collision = true
	root.add_child(low)
	await frames(3)
	player.look_towards(chest)
	check(post.in_view(player.camera) and not post.try_show(player),
			"behind a low wall its head would show: the figure does not come")
	low.queue_free()
	await frames(2)
	# At the side of the view: the post's axis just out of the frame, its
	# crossbar and the figure's arm not.
	var aside := 20.0
	while aside < 90.0 and _axis_in_frame(player.camera, post):
		aside += 0.25
		_look_aside(player, chest, aside)
	check(aside < 90.0 and post.in_view(player.camera) and not post.try_show(player),
			"the edge of the place in the corner of the view counts as seen", aside)

	# Behind a wall it may come even in the middle of the view.
	post._cool = 0.0
	var wall := CSGBox3D.new()
	wall.size = Vector3(6, 4, 0.3)
	wall.position = Vector3(0, 2, -8)
	wall.use_collision = true
	root.add_child(wall)
	await frames(3)
	player.look_towards(chest)
	check(not post.in_view(player.camera) and post.try_show(player),
			"behind a wall the place is out of view: the figure may come")
	check(not post.looked_at(player.camera), "a figure behind a wall is not seen through")
	player.look_towards(away)
	wall.queue_free()
	await frames(2)
	# The panic eases while he is not looking: it goes unseen.
	PanicSystem.floor_level = 0.0
	PanicSystem.level = 0.1
	gone.clear()
	for f in 3:
		await get_tree().process_frame
	check(not post.shown and gone == [false], "calmer, the figure goes while he is not looking", gone)
	# Come up to it, it does not hold.
	post._cool = 0.0
	PanicSystem.floor_level = 0.9
	PanicSystem.level = 0.9
	player.look_towards(away)
	check(post.try_show(player), "the figure is back after a while")
	# Its face, drawn high above the coat, is looked at straight too.
	t0 = Time.get_ticks_msec()
	while Perception.distortion < 0.85 and Time.get_ticks_msec() - t0 < 2000:
		await get_tree().process_frame
	player.global_position = post.global_position + Vector3(0, 0, 5)
	player.look_towards(player.global_position + Vector3(0, 1.35, 10))
	gone.clear()
	await get_tree().process_frame
	var face := post.global_position + Vector3.UP * PhantomFigure.drawn_height(1.62, Perception.distortion)
	player.look_towards(face)
	for f in 3:
		await get_tree().process_frame
	check(not post.shown and gone == [true], "looked in the face, high above the coat, it is a post again", gone)
	post._cool = 0.0
	player.global_position = Vector3.ZERO
	player.look_towards(away)
	post.try_show(player)
	player.global_position = post.global_position + Vector3(0, 0, 1.6)
	player.look_towards(player.global_position + Vector3(0, 1.35, 10))
	gone.clear()
	for f in 3:
		await get_tree().process_frame
	check(not post.shown and gone == [true], "come up to it, it is a post", gone)
	# Between calm and fear none is made, a standing one is kept; seeing it
	# does not move the panic.
	post._cool = 0.0
	player.global_position = Vector3.ZERO
	player.look_towards(away)
	PanicSystem.floor_level = 0.42
	PanicSystem.level = 0.42
	check(not post.try_show(player), "between calm and fear no figure is made")
	PanicSystem.level = 0.9
	var made := post.try_show(player)
	PanicSystem.level = 0.42
	for f in 5:
		await get_tree().process_frame
	check(made and post.shown, "between calm and fear a standing figure is kept")
	check(is_equal_approx(PanicSystem.level, 0.42), "the figure does not move the panic", PanicSystem.level)
	PanicSystem.floor_level = 0.0
	PanicSystem.level = 0.1
	for f in 3:
		await get_tree().process_frame
	post._cool = 0.0
	PanicSystem.floor_level = 0.9
	PanicSystem.level = 0.9
	player.global_position = post.global_position + Vector3(0, 0, 4)
	player.look_towards(player.global_position + Vector3(0, 1.35, 10))
	check(not post.try_show(player), "too near for a figure to come")
	player.global_position = post.global_position + Vector3(0, 0, 40)
	check(not post.try_show(player), "too far for a figure to come")
	player.global_position = Vector3.ZERO
	player.look_towards(away)
	# Safety begins: a figure standing in his view is gone at once - no soldier
	# in sepia.
	check(post.try_show(player), "out of the view it comes again")
	_look_aside(player, chest, 25.0)
	gone.clear()
	Perception.enter_safe_zone()
	for f in 2:
		await get_tree().process_frame
	check(not post.shown and gone == [false], "safety begins: the figure is gone at once, even in view", gone)
	Perception.exit_safe_zone()
	Perception.reset()
	# A document in his hands pauses the game; the figure goes all the same.
	post._cool = 0.0
	player.look_towards(away)
	var again := post.try_show(player)
	gone.clear()
	Perception.push_suppression()
	get_tree().paused = true
	for f in 3:
		await get_tree().process_frame
	var cut := not post.shown and gone == [false]
	get_tree().paused = false
	Perception.pop_suppression()
	check(again and cut, "a document in his hands: the figure is gone though the game is paused", gone)
	# Sepia: no figures where he is safe.
	post._cool = 0.0
	player.global_position = Vector3.ZERO
	player.look_towards(away)
	Perception.enter_safe_zone()
	t0 = Time.get_ticks_msec()
	while Perception.sepia < 0.3 and Time.get_ticks_msec() - t0 < 3000:
		await get_tree().process_frame
	check(not post.try_show(player), "no figures in sepia")
	Perception.exit_safe_zone()
	Perception.reset()
	# By itself, in time, where he is not looking.
	post._check = 0.0
	t0 = Time.get_ticks_msec()
	while not post.shown and Time.get_ticks_msec() - t0 < 2000:
		await get_tree().process_frame
	check(post.shown, "in panic the figure comes by itself where he is not looking")
	# Only the boy sees it.
	var bodies := post.figure.find_children("*", "CollisionObject3D", true, false)
	var marks := 0
	for n in ["Armband", "Gorget", "PlasterMask", "Cap", "Torch"]:
		if post.figure.has_node(n):
			marks += 1
	var red := 0
	for n in post.figure.find_children("*", "GeometryInstance3D", true, false):
		if PhantomFigure.is_red(n as GeometryInstance3D):
			red += 1
	var enemy_red := 0
	var enemy := (load("res://src/ai/enemy.tscn") as PackedScene).instantiate()
	for n in enemy.find_children("*", "GeometryInstance3D", true, false):
		if PhantomFigure.is_red(n as GeometryInstance3D):
			enemy_red += 1
	enemy.free()
	check(bodies.is_empty() and not post.is_in_group("enemies") and not post.figure.is_in_group("enemies"),
			"the figure has no body and is not an enemy")
	check(marks == 0, "no armband, gorget, mask or cap on the figure")
	check(enemy_red > 0 and red == 0, "the enemies' red is known by its shader, and none of it is on the figure",
			"%d on the enemy, %d on the figure" % [enemy_red, red])
	Stealth.noise_emitted.disconnect(on_noise)
	check(noises[0] == 0, "the figure never makes a sound", noises[0])
	PanicSystem.reset()
	root.queue_free()
	await frames(2)

	# The placement check itself: a figure inside a solid (a stove, a trunk)
	# is caught, though the solid's collision is a hollow shell.
	var site := Node3D.new()
	var floor_csg := CSGBox3D.new()
	floor_csg.size = Vector3(20, 1, 20)
	floor_csg.position = Vector3(0, -0.5, 0)
	floor_csg.use_collision = true
	site.add_child(floor_csg)
	var stove := CSGBox3D.new()
	stove.size = Vector3(3, 3, 3)
	stove.position = Vector3(-5, 1.5, 0)
	stove.use_collision = true
	site.add_child(stove)
	var trunk := CSGCylinder3D.new()
	trunk.radius = 0.5
	trunk.height = 9.0
	trunk.position = Vector3(5, 4.5, 0)
	trunk.use_collision = true
	site.add_child(trunk)
	var in_stove := PhantomFigure.new()
	in_stove.position = Vector3(-5, 0, 0)
	site.add_child(in_stove)
	var in_trunk := PhantomFigure.new()
	in_trunk.disguise = PhantomFigure.Disguise.NONE
	in_trunk.position = Vector3(5, 0, 0)
	site.add_child(in_trunk)
	var in_open := PhantomFigure.new()
	in_open.position = Vector3(0, 0, 5)
	site.add_child(in_open)
	add_child(site)
	await frames(4)
	check(not _stands_free(in_stove) and not _stands_free(in_trunk) and _stands_free(in_open),
			"the placement check catches a figure inside a solid",
			[_stands_free(in_stove), _stands_free(in_trunk), _stands_free(in_open)])
	site.queue_free()
	await frames(2)

	# Where the levels put them: on free ground.
	for scene: PackedScene in [LEVEL, ACT2]:
		var level := scene.instantiate()
		level.play_intro = false
		add_child(level)
		level._ending = true
		await frames(4)
		var found := get_tree().get_nodes_in_group(PhantomFigure.GROUP)
		var stuck: Array[String] = []
		for ph: PhantomFigure in found:
			if not _stands_free(ph):
				stuck.append(str(ph.name) + " " + str(ph.global_position))
		check(found.size() == 3 and stuck.is_empty(),
				"%s: three phantom figures, each on free ground" % scene.resource_path.get_file(),
				"%d, stuck %s" % [found.size(), stuck])
		level.queue_free()
		await frames(2)


## Turn the boy so `point` is `degrees` to the side of the middle of his view.
func _look_aside(player: Player, point: Vector3, degrees: float) -> void:
	var eye := player.head.global_position
	player.look_towards(eye + (point - eye).rotated(Vector3.UP, deg_to_rad(degrees)))


## Nothing of the level in the space of a standing figure but its own thing:
## nothing crossing it (the box), and nothing over it either - CSG collision
## is a hollow shell that a ray from inside does not meet, so a figure inside
## a stove or a trunk is found from high above: past its own thing, the first
## thing met at the middle and the corners must be the ground under its feet.
func _stands_free(ph: PhantomFigure) -> bool:
	var space := ph.get_world_3d().direct_space_state
	var mask := 1 | 4 | 8 | 16 | Stealth.SEE_THROUGH_LAYER
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.6, 0.8)
	q.shape = box
	q.transform = Transform3D(Basis.IDENTITY, ph.global_position + Vector3.UP * 1.0)
	q.collision_mask = mask
	for hit in space.intersect_shape(q, 16):
		if hit["collider"] != ph.thing:
			return false
	for off in [Vector3.ZERO, Vector3(0.4, 0, 0.4), Vector3(-0.4, 0, 0.4), Vector3(0.4, 0, -0.4), Vector3(-0.4, 0, -0.4)]:
		var at: Vector3 = ph.global_position + off
		var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 50.0, at + Vector3.DOWN * 0.5, mask)
		var hit := space.intersect_ray(ray)
		if not hit.is_empty() and hit["collider"] == ph.thing:
			ray.exclude = [hit["rid"]]
			hit = space.intersect_ray(ray)
		if hit.is_empty() or absf((hit["position"] as Vector3).y - ph.global_position.y) > 0.3:
			return false
	return true


## Is any point of the place's axis (feet to the head fear could draw) inside
## the camera's frame?
func _axis_in_frame(cam: Camera3D, ph: PhantomFigure) -> bool:
	var top := PhantomFigure.drawn_height(PhantomFigure.HELMET_TOP, 1.0)
	for i in 12:
		if cam.is_position_in_frustum(ph.global_position + Vector3.UP * lerpf(0.05, top, i / 11.0)):
			return true
	return false


## Looking at the burned house calmly: the house stands again in sepia.
## An alarm cuts the memory off at once.
func _test_memory() -> void:
	PanicSystem.reset()
	Perception.reset()
	var level := LEVEL.instantiate()
	level.play_intro = false
	add_child(level)
	level._ending = true
	await frames(3)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set_physics_process(false)
	var player := level.get_node("Player") as Player
	player.get_node("BreathControl").set_physics_process(false)
	var mem := level.get_node("BurnedHouse/Memory") as MemoryFlash
	check(not mem.ghost.visible, "the house as it was is hidden")
	var tone: Array = [null]
	var on_tone := func(id: String, p: AudioStreamPlayer3D) -> void:
		if id == "memory_room_tone": tone[0] = p
	Sfx.played.connect(on_tone)
	# Six metres east of the ruin, looking away: nothing.
	player.global_position = mem.focus.global_position + Vector3(6, -1.3, 0)
	player.look_towards(player.global_position + Vector3(10, 1.35, 0))
	await frames(10)
	check(not mem.active, "no memory without looking at the place")
	# Walking, a glance is not a memory: he has to stop (MemoryFlash.still_below).
	Input.action_press("move_forward")
	await frames(3)
	player.look_towards(mem.focus.global_position)
	await frames(8)
	check(not mem.active and not mem.used, "walking past and looking at the ruin is no memory: he has to stop",
			player.velocity)
	Input.action_release("move_forward")
	player.look_towards(mem.focus.global_position)
	await frames(10)
	check(mem.active and mem.ghost.visible, "stopped and looking at the ruin, the memory comes back")
	check(tone[0] != null and (tone[0] as AudioStreamPlayer3D).playing, "the house is heard: clock, stove")
	check(Perception.in_safe_zone(), "the memory is in sepia")
	check(not mem.present_only.visible, "no smoke over the house as it was")
	for f in 40:
		await get_tree().process_frame
	check(Perception.sepia > 0.0, "sepia rises in the memory", Perception.sepia)
	# Reality breaks in.
	var soldier := level.get_node("Feldgendarm") as Enemy
	soldier._set_state(Enemy.State.ALERT)
	await frames(2)
	check(not mem.active and not mem.ghost.visible, "an alarm cuts the memory off")
	check(not is_instance_valid(tone[0]), "the house goes silent at once")
	Sfx.played.disconnect(on_tone)
	check(mem.present_only.visible, "the smoke is back")
	check(Perception.sepia == 0.0 and not Perception.in_safe_zone(), "the cut is hard, not a fade", Perception.sepia)
	soldier._set_state(Enemy.State.PATROL)
	await frames(10)
	check(not mem.active, "a memory comes only once")
	level.queue_free()
	await frames(2)


## The forest ends the slice only when nobody is on the boy's heels.
func _test_forest_ending() -> void:
	PanicSystem.reset()
	Perception.reset()
	var level := LEVEL.instantiate()
	level.play_intro = false
	level.forest_calm_needed = 0.5
	level.next_level = ""
	add_child(level)
	await frames(3)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set_physics_process(false)
	var finished := [false]
	level.slice_finished.connect(func() -> void: finished[0] = true)
	var player := level.get_node("Player") as Player
	player.get_node("BreathControl").set_physics_process(false)
	var pol := level.get_node("Polizei") as Enemy
	pol._set_state(Enemy.State.ALERT)
	player.global_position = Vector3(0, 0.1, -35)
	await frames(60)
	check(not level._ending, "no ending while pursued")
	pol._set_state(Enemy.State.PATROL)
	await frames(60)
	check(level._ending, "the forest ends the slice once nobody follows")
	var t0 := Time.get_ticks_msec()
	while not finished[0] and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
	check(finished[0] and (level.get_node("Overlay/Caption") as Label).text.contains("из 2"),
			"the end card counts the documents", (level.get_node("Overlay/Caption") as Label).text)
	level.queue_free()
	await frames(2)


# --- Act II ----------------------------------------------------------------------

const ACT2 := preload("res://src/scenes/act2_road/act2_road.tscn")


## The dream between Act I and Act II: the room that will not let him go.
func _test_night_dream() -> void:
	PanicSystem.reset()
	Perception.reset()
	GameState.reset()
	var level := NIGHT.instantiate()
	level.play_intro = false
	level.loop_blink = 0.1
	add_child(level)
	level.next_level = ""  # set after _ready: the dream has already opened Act II
	await frames(3)
	check(GameState.reached == 2 and GameState.last_act == 1, "after the village Act II is open and «Продолжить» leads there",
			[GameState.reached, GameState.last_act])
	GameState.reset()
	var player := level.get_node("Player") as Player
	player.get_node("BreathControl").set_physics_process(false)
	player.get_node("PhantomSounds").set_process(false)
	var lay: Node3D = level.layout
	var clock: WallClock = lay.clock
	check(level.stage == 0 and Perception.in_safe_zone(), "the dream begins at home, in sepia")
	check(Gaze.looks_at(player.camera, level.TABLE_POINT, 0.5, 6.0), "he faces the table first")
	var bowls := 0
	for b in lay.bowls:
		bowls += 1 if b.visible else 0
	check(bowls == 4 and lay.bread.visible and clock.rate == 1.0, "four bowls, bread, the clock as at home", bowls)
	check(level.hatch == null and level.figure == null, "nobody, and no way down, at first")
	check(not level.has_node("Wind"), "no wind in the dream: the house is silent")
	var gate := level.get_node("LoopGate") as Area3D
	var start := (level.get_node("Spawns/Start") as Node3D).global_position
	var ceilings: Array[float] = [lay.ceiling.position.y]
	for n in [1, 2, 3]:
		player.global_position = gate.global_position - Vector3.UP * 1.1
		await _wait(0.45)
		await _until(func() -> bool: return level.stage == n, 3.0)
		check(level.stage == n, "out through the сени - and back in the room (%d)" % n, level.stage)
		check(player.global_position.distance_to(start) < 0.3, "he is back where he woke in the dream (%d)" % n)
		ceilings.append(lay.ceiling.position.y)
		await frames(2)
		check(absf(clock.rate - lerpf(1.0, clock.slow_rate, level.CLOCK_STRETCH[n])) < 0.01,
				"the clock slows (%d)" % n, clock.rate)
	check(ceilings[0] > ceilings[1] and ceilings[1] > ceilings[2] and ceilings[2] > ceilings[3],
			"the ceiling comes lower each time", ceilings)
	check(not Perception.in_safe_zone(), "the sepia is gone after the first return")
	bowls = 0
	for b in lay.bowls:
		bowls += 1 if b.visible else 0
	var stools := 0
	for st in lay.stools:
		stools += 1 if st.visible else 0
	check(bowls == 0 and stools == 0 and not lay.bread.visible, "the table is empty", [bowls, stools])
	# The last room.
	check(level.figure != null and level.figure.passive and level.figure.torch_on, "a figure with a torch in the doorway")
	check(lay.door_block.use_collision and not gate.monitoring, "the doorway is closed now")
	var hatch: HideSpot = level.hatch
	var teal := hatch != null
	for g in hatch.find_children("*", "MeshInstance3D", true, false):
		var mat := (g as MeshInstance3D).get_active_material(0)
		teal = teal and mat != null and ColorMask.channel_of(mat) == ColorMask.Channel.INTERACTIVE
	check(teal, "the cellar hatch appears, blue-green: the only way out")
	player.global_position = gate.global_position - Vector3.UP * 1.1
	await _wait(0.4)
	check(level.stage == 3, "the сени no longer lead anywhere")
	# Hiding: the figure comes closer, the light passes over the slits.
	player.global_position = start
	level.wake_after = 2.0
	var far: float = level.figure.global_position.distance_to(hatch.global_position)
	hatch.interact(player)
	check(player.is_hidden, "he hides under the floor")
	var leak := 0.0
	for f in 66:  # 1.1 s of _hidden_time, short of wake_after
		await get_tree().physics_frame
		leak = maxf(leak, player.torch_leak)
	check(level.figure.global_position.distance_to(hatch.global_position) < far - 0.3,
			"the figure comes over to the hatch")
	check(leak > 0.2, "its torch light passes over the slits", leak)
	check(BoardFloor.at(get_tree(), hatch.global_position + Vector3.UP * 0.05) != null
			and level.figure.gait.steps > 0, "it walks on the boards over his head", level.figure.gait.steps)
	hatch.interact(player)
	check(not player.is_hidden and level._hidden_time == 0.0 and not level.waking, "coming out too early wakes nothing")
	hatch.interact(player)
	var woke := [false]
	level.woke.connect(func() -> void: woke[0] = true)
	level.dawn_time = 0.2
	await _wait(2.4)
	await _until(func() -> bool: return level.waking, 4.0)
	await _passes()  # the room is freed at the end of the pass
	check(level.waking and player.is_seated and not player.is_hidden, "he wakes")
	check(level.figure == null and level.hatch == null and not level.has_node("Layout/Room"), "the house is gone")
	check(player.camera.global_position.distance_to(level.get_node("ForestSeat").global_position) < 0.05
			and -player.camera.global_transform.basis.z.y > 0.4, "under the firs, looking up at the sky")
	check(Perception.in_safe_zone() and PanicSystem.floor_level == 0.0, "dawn in the forest is safe (sepia)")
	check(level.has_node("Wind"), "a quiet wind in the firs at dawn")
	await _until(func() -> bool: return woke[0], 12.0)  # 1 + 2.5 + dawn + 2 s of tweens
	check(woke[0], "then the road (Act II)")
	level.queue_free()
	await frames(2)


func _test_act2() -> void:
	PanicSystem.reset()
	Perception.reset()
	var level := ACT2.instantiate()
	level.play_intro = false
	add_child(level)
	level._ending = true
	var nav := level.get_node("Navigation") as RuntimeNavRegion
	var t0 := Time.get_ticks_msec()
	while not nav.is_baked and Time.get_ticks_msec() - t0 < 15000:
		await get_tree().physics_frame
	check(nav.is_baked and nav.navigation_mesh.get_polygon_count() > 50, "Act II navmesh is baked")
	check(level.has_node("Wind") and (level.get_node("Wind") as AmbienceBed).gain_db > 0.0,
			"Act II: the wind is stronger over the open road")
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set_physics_process(false)
	var enemies := get_tree().get_nodes_in_group("enemies")
	check(enemies.size() == 5, "Act II: police patrol, two sentries, camp guard and dog", enemies.size())
	var player := level.get_node("Player") as Player
	player.get_node("BreathControl").set_physics_process(false)
	player.get_node("PhantomSounds").set_process(false)

	# Colour rule: every interactable is blue-green.
	var inter := level.find_children("*", "Interactable", true, false)
	check(inter.size() >= 3, "Act II has the summons, bread and bandage", inter.size())
	var all_teal := true
	for node in inter:
		for g in (node as Node).find_children("*", "GeometryInstance3D", true, false):
			var mat := (g as GeometryInstance3D).material_override
			if mat != null and ColorMask.channel_of(mat) != ColorMask.Channel.INTERACTIVE:
				all_teal = false
	check(all_teal, "Act II interactables are blue-green")
	check(level.documents_found().y == 1, "one document on the road", level.documents_found())
	var road_card: String = level._end_card_text()
	check(road_card.contains("\nДокументов в архиве свидетеля: ") and road_card.ends_with(" из 1")
			and not road_card.contains("\r"), "the end card counts the road's document on a line of its own", road_card)

	# The road north is closed at the checkpoint: no path along it.
	var map: RID = level.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, Vector3(0, 0, -55), Vector3(0, 0, -70), true)
	check(path.size() > 0 and path[path.size() - 1].distance_to(Vector3(0, 0, -70)) < 1.0, "a path north exists", path.size())
	var through_field := false
	for pt in path:
		if pt.x > 6.0:
			through_field = true
	check(through_field, "the only way past the checkpoint is through the field")

	# Tripwires: invisible standing, seen crouched and close, deadly to touch.
	var mines := get_tree().get_nodes_in_group("mines")
	check(mines.size() == 10, "ten tripwires in the field", mines.size())
	var mine := mines[0] as TripwireMine
	var near := mine.global_transform * Vector3(mine.length * 0.5, 0, 1.5)
	player.set_physics_process(false)  # keep the crouch the test sets
	player.global_position = near
	player.is_crouching = false
	await frames(3)
	check(not mine.wire.visible, "a standing boy does not see the wire")
	player.is_crouching = true
	await frames(3)
	check(mine.wire.visible, "crouched and close, the wire catches the light")
	player.global_position = near + (near - mine.global_position).normalized() * 5.0
	await frames(3)
	check(not mine.wire.visible, "from afar the wire is invisible again")
	var blown := [false]
	mine.detonated.connect(func(_m: TripwireMine) -> void: blown[0] = true)
	player.global_position = mine.global_transform * Vector3(mine.length * 0.5, 0, 0)
	await frames(4)
	check(blown[0] and PanicSystem.level > 0.9, "touching the wire sets the mine off")
	player.is_crouching = false
	player.set_physics_process(true)
	PanicSystem.reset()

	# Searchlight: the beam finds a boy in the open, not one behind cover.
	var tower := level.get_node("Layout/Camp/Tower") as SearchlightTower
	tower.set_physics_process(false)
	tower.sweep_period = 1000.0  # hold the beam still...
	tower._t = 0.0
	tower._pivot.rotation.y = 0.0  # ...where it will stay
	var lamp_pos := tower.lamp.global_position
	var axis := -tower.lamp.global_transform.basis.z
	# Put the boy where the beam's axis meets the ground.
	var t := -lamp_pos.y / axis.y
	var lit := lamp_pos + axis * t
	player.global_position = lit
	await frames(2)
	check(tower.in_beam(player), "the boy in the beam is lit", lit)
	# A wire post just in front of him, on the line to his head and knee: the
	# beam still finds his shoulders (until 19.11.2026 it looked for the head
	# and the knee only, and the post hid him).
	var wire_post := CSGBox3D.new()
	wire_post.size = Vector3(0.1, 4.0, 0.1)
	wire_post.use_collision = true
	level.add_child(wire_post)
	var post_at := lamp_pos + (player.head.global_position - lamp_pos) * 0.97
	wire_post.global_position = Vector3(post_at.x, 2.0, post_at.z)
	await frames(2)
	check(not _ray_clear(level, lamp_pos, player.head.global_position)
			and not _ray_clear(level, lamp_pos, player.global_position + Vector3.UP * 0.3) and tower.in_beam(player),
			"a wire post hides his head and knee from the beam, not his shoulders: lit")
	wire_post.queue_free()
	await frames(2)
	var alarm := [false]
	tower.alarm_raised.connect(func(_p: Vector3) -> void: alarm[0] = true)
	tower.set_physics_process(true)
	tower.sweep_period = 1000.0  # hold the beam still
	tower._t = 0.0
	for f in 60:
		await get_tree().physics_frame
	check(alarm[0], "standing in the beam raises the alarm")
	var guard := level.get_node("CampGuard") as Enemy
	check(guard.suspicion >= 1.0 or guard.state != Enemy.State.PATROL, "the camp guard is called", guard.suspicion)
	tower.set_physics_process(false)
	tower._lock = 0.0
	# Behind a haystack, between the lamp and the boy.
	var stack := Vector3(16, 0, -99)
	var dir := Vector3(stack.x - lamp_pos.x, 0, stack.z - lamp_pos.z).normalized()
	player.global_position = stack + dir * 1.4
	await frames(2)
	check(not tower.in_beam(player) or not _ray_clear(level, lamp_pos, player.head.global_position),
			"cover stops the beam")
	check(not _ray_clear(level, lamp_pos, player.head.global_position), "the haystack is between")

	# The bread lies in the cold stove of the house he remembers, in its mouth
	# turned to the street: brickwork over it, open in front, in reach of a
	# crouching boy (docs/ARCHITECTURE.md, "Голод и хлеб").
	var bread := level.get_node("Layout/Pickup_bread") as Pickup
	var mem := level.get_node("Layout/BurnedVillage/Memory") as MemoryFlash
	var bp := bread.global_position
	var from_house := Vector2(bp.x - mem.global_position.x, bp.z - mem.global_position.z).length()
	# Brickwork well over the loaf (the stove's top, 1.1 m), not just anything
	# over its middle: a loaf sunk in a charred beam has the beam's top 5 cm up.
	var over: Dictionary = level.get_world_3d().direct_space_state.intersect_ray(
			PhysicsRayQueryParameters3D.create(bp + Vector3.UP * 3.0, bp + Vector3.UP * 0.12, 1))
	check(not over.is_empty() and (over["position"] as Vector3).y > bp.y + 0.4 and from_house < 1.5,
			"Act II: the bread is in the stove of the house he remembers, under its brickwork",
			[bp, from_house, over.get("position")])
	check(_ray_clear(level, bp + Vector3(1.2, 0.1, 0), bp + Vector3(0, 0.1, 0)),
			"Act II: the stove's mouth is open to the street")
	Inventory.clear()
	player.global_position = Vector3(bp.x + 1.0, 0, bp.z)
	Input.action_press("crouch")
	await frames(40)
	player.look_towards(bp)
	await frames(2)
	check(player.is_crouching and player.try_interact() and Inventory.has_item("bread"),
			"Act II: crouched at the stove, he takes the bread out of it")
	Input.action_release("crouch")
	Inventory.clear()
	# The memory there: stopped in its place, looking at the house - it stands
	# again, and the smoke over both ruins is gone while he remembers.
	for e in get_tree().get_nodes_in_group("enemies"):
		(e as Enemy).suspicion = 0.0
		(e as Enemy)._set_state(Enemy.State.PATROL)
	PanicSystem.reset()
	var smoke := mem.present_only
	check(smoke != null and smoke.get_child_count() == 2 and smoke.visible,
			"Act II: the smoke over the two ruins is the present", smoke)
	player.global_position = Vector3(-10.5, 0, -20.8)
	await frames(3)
	player.look_towards(mem.focus.global_position)
	await frames(6)
	check(mem.active and smoke != null and not smoke.visible,
			"Act II: stopped in the ruins and looking at the house, he remembers it, and no smoke")
	player.global_position = Vector3(0, 0, 0)  # out of the place: cut off
	await frames(3)
	check(not mem.active and smoke != null and smoke.visible, "Act II: back in the present, the smoke is back")

	# The gallows: looking at them frightens; not looking does not.
	PanicSystem.reset()
	var sight := level.get_node("Layout/Gallows/Sight") as DreadSight
	player.global_position = Vector3(1, 0, -118)
	player.look_towards(sight.global_position + Vector3(0, 0, 30))
	player.rotation.y += PI  # turn away
	await frames(5)
	check(not sight.seen, "the gallows are not seen with the back turned")
	player.look_towards(sight.global_position)
	await frames(5)
	check(sight.seen and PanicSystem.level > 0.25, "seeing the gallows is a jolt of panic", PanicSystem.level)
	level.queue_free()
	await frames(2)


func _act2_instance(resume: bool) -> Node3D:
	PanicSystem.reset()
	Perception.reset()
	LevelBase._resume_after_intro = resume
	var level := ACT2.instantiate()
	level.play_intro = false
	level.next_level = ""
	add_child(level)
	var player := level.get_node("Player") as Player
	player.get_node("BreathControl").set_physics_process(false)
	player.get_node("PhantomSounds").set_process(false)
	# He starts the road hungry: a growl at a random moment would call a
	# soldier over mid-test. Growls are tested in _test_hunger.
	player.hunger.set_process(false)
	return level


func _bread_pickup(level: Node) -> Pickup:
	for n in level.find_children("*", "Pickup", true, false):
		var p := n as Pickup
		if not p.is_queued_for_deletion() and p.item != null and p.item.id == "bread":
			return p
	return null


const BREAD_ITEM := preload("res://assets/data/items/bread.tres")
const BANDAGE_ITEM := preload("res://assets/data/items/bandage.tres")


## Hunger (Hunger): hungry, his stomach growls - he feels it coming (a low
## swell, the view shivering), a soldier close by hears it and comes to look,
## held breath stifles it (hidden or in the open); he is winded sooner; bread
## from the satchel puts it off.
func _test_hunger() -> void:
	PanicSystem.reset()
	Perception.reset()
	Stealth.reset_cover()
	Inventory.clear()
	var root := Node3D.new()
	var ground := CSGBox3D.new()
	ground.size = Vector3(40, 1, 40)
	ground.position = Vector3(0, -0.5, 0)
	ground.use_collision = true
	root.add_child(ground)
	var player := PLAYER_SCENE.instantiate() as Player
	root.add_child(player)
	add_child(root)
	await frames(3)
	player.set_physics_process(false)
	player.breath.set_physics_process(false)
	player.get_node("PhantomSounds").set_process(false)
	var view_mask := player.camera.cull_mask
	var hunger := player.hunger
	check(hunger != null and hunger.level < 0.01 and hunger.timer >= hunger.first_delay_min - 1.0,
			"the boy has a stomach: fed, and no growl right at the start", hunger.timer if hunger != null else -1.0)
	var heard: Array[float] = []
	var actions: Array[bool] = []
	var on_noise := func(_at: Vector3, loud: float, source: Node) -> void:
		if source == player:
			heard.append(loud)
			actions.append(Stealth.noise_is_action)
	var sounds: Array[String] = []
	var buses := {}
	var on_sound := func(id: String, sp: AudioStreamPlayer3D) -> void:
		sounds.append(id)
		buses[id] = sp.bus
	Stealth.noise_emitted.connect(on_noise)
	Sfx.played.connect(on_sound)

	# Time makes him hungry.
	hunger.level = 0.0
	hunger._process(600.0)
	check(absf(hunger.level - 0.3) < 0.001, "ten minutes on the road and he is getting hungry", hunger.level)
	# Not hungry enough: the stomach is quiet, and the next growl waits.
	hunger.timer = 0.3
	await _wait(0.8)
	check(hunger.growls == 0 and heard.is_empty() and sounds.is_empty() and absf(hunger.timer - 0.3) < 0.001,
			"not that hungry yet: the stomach is quiet, and the next growl does not draw near", hunger.timer)
	# Hungry: first the tremor he feels, then the growl a soldier hears -
	# every time, not only the first.
	hunger.level = 0.7
	for n in 2:
		sounds.clear()
		heard.clear()
		actions.clear()
		hunger.timer = 1.6
		var t0 := Time.get_ticks_msec()
		var felt_at := -1
		var most := 0.0
		var shiver := 0.0
		while hunger.growls == n and Time.get_ticks_msec() - t0 < 4000:
			if felt_at < 0 and sounds.has("stomach_rumble"):
				felt_at = Time.get_ticks_msec()
			most = maxf(most, hunger.tremor)
			shiver = maxf(shiver, absf(hunger.tremor_offset()))
			await get_tree().process_frame
		var lead := (Time.get_ticks_msec() - felt_at) / 1000.0 if felt_at >= 0 else 0.0
		check(hunger.growls == n + 1 and sounds == ["stomach_rumble", "stomach_growl"] and lead > 0.9,
				"hungry: he feels growl %d coming a second before it" % (n + 1), [sounds, lead])
		check(most > 0.6 and shiver > Hunger.TREMOR * 0.3 and hunger.tremor == 0.0 and hunger.tremor_offset() == 0.0,
				"the view shivers as it comes, and is still after it (growl %d)" % (n + 1), [most, shiver])
		if n == 0:
			check(heard.size() == 1 and heard[0] > 0.15 and heard[0] < 0.3 and actions == [true],
					"the growl is heard plainly close by - somebody there - never loud enough to give a hidden boy away outright",
					[heard, actions])
			check(PanicSystem.level < 0.01, "with no soldier about, it does not frighten him", PanicSystem.level)
			var k := inverse_lerp(Hunger.GROWL_FROM, 1.0, 0.7)
			check(hunger.timer >= hunger.interval_min * lerpf(1.0, 0.5, k) - 0.1 and hunger.timer <= hunger.interval_max,
					"the next growl waits a while", hunger.timer)
	check(buses.get("stomach_growl", "") == Sfx.BODY_BUS and buses.get("stomach_rumble", "") == Sfx.BODY_BUS,
			"it is his own body's sound: the hiding place does not muffle it for him", buses)
	# Starving, it comes twice as often.
	hunger.level = 1.0
	var longest := 0.0
	for i in 40:
		longest = maxf(longest, hunger.next_interval())
	check(longest <= hunger.interval_max * 0.5 + 0.01, "starving, it growls twice as often", longest)
	hunger.level = 0.7
	# Holding his breath when he feels it - in the open too - he stifles it.
	player.breath.step(0.1, true, 99.0)
	check(player.breath.holding and not player.is_hidden, "he holds his breath in the open too")
	heard.clear()
	actions.clear()
	var stifled := hunger.growl()
	check(stifled <= Hunger.GROWL_LOUD * Hunger.STIFLE + 0.001 and heard == [stifled] and actions == [false],
			"holding his breath he stifles it to a sound nobody walks over for", [heard, actions])
	# Held too long in the open, the air runs out: a gasp, and a moment
	# before he can hold it again.
	sounds.clear()
	var held := 0.1
	while player.breath.holding and held < 15.0:
		player.breath.step(0.1, true, 99.0)
		held += 0.1
	player.breath.step(0.1, true, 99.0)
	check(sounds.has("breath_gasp") and not player.breath.holding and held > player.breath.capacity_calm - 0.5,
			"held too long, he gasps for air and cannot hold it again at once", [held, sounds])
	player.breath.step(0.1, false, 99.0)
	player.breath.air = 1.0
	player.breath._lockout = 0.0
	PanicSystem.reset()
	# A soldier close by: it frightens the boy, and the soldier comes to look.
	var soldier := ENEMY_SCENE.instantiate() as Enemy
	root.add_child(soldier)
	soldier.set_physics_process(false)
	soldier.global_position = Vector3(0, 0, 2.0)
	await frames(2)
	check(soldier.state == Enemy.State.PATROL and soldier.suspicion < Enemy.SUSPICIOUS_AT,
			"a soldier passing close by, calm", [soldier.state, soldier.suspicion])
	var before := PanicSystem.level
	hunger.growl()
	check(PanicSystem.level > before + 0.03, "a growl with a soldier close by frightens him",
			[before, PanicSystem.level])
	check(soldier.state == Enemy.State.SUSPICIOUS and soldier.suspicion >= Enemy.SUSPICIOUS_AT,
			"and the soldier heard somebody: he comes to look", [soldier.state, soldier.suspicion])
	# Hidden, starving, the soldier right by the hiding place: the place
	# muffles it, and even unmuffled it is no hand reaching in.
	soldier.global_position = Vector3(0, 0, 1.5)
	soldier.suspicion = 0.0
	soldier._set_state(Enemy.State.PATROL)
	hunger.level = 1.0
	var spot := STOVE_NOOK.instantiate() as HideSpot
	var damping := spot.noise_damping
	spot.free()
	player.is_hidden = true
	player.current_hide_spot = null
	var bare := hunger.growl()
	var nook := STOVE_NOOK.instantiate() as HideSpot
	player.current_hide_spot = nook
	var muffled := hunger.growl()
	player.current_hide_spot = null
	player.is_hidden = false
	nook.free()
	check(absf(muffled - bare * (1.0 - 0.5 * damping)) < 0.001 and muffled < bare,
			"the hiding place muffles the growl for the soldier", [bare, muffled])
	check(not soldier._caught and bare < 0.3, "starving and a soldier at arm's length: he comes to look, no hand reaches in",
			[bare, soldier._caught])
	soldier.queue_free()
	await frames(1)
	PanicSystem.reset()
	# Hungry, he is winded sooner.
	check(is_equal_approx(_run_factor_at(hunger, 1.0), Hunger.WEAK_RUN) and is_equal_approx(_run_factor_at(hunger, 0.0), 1.0),
			"starving he is winded in %.0f %% of the time, fed in full" % (Hunger.WEAK_RUN * 100.0))
	player.sprinting = true
	player.breath.winded = 0.0
	hunger.level = 0.0
	player.breath._update_winded(1.0)
	var fed_run := player.breath.winded
	player.breath.winded = 0.0
	hunger.level = 1.0
	player.breath._update_winded(1.0)
	var hungry_run := player.breath.winded
	player.sprinting = false
	player.breath.winded = 0.0
	check(hungry_run > fed_run * 1.6, "a second of running winds a starving boy more", [fed_run, hungry_run])

	# The satchel: pick a thing with left / right, use it.
	Inventory.add_item(BREAD_ITEM)
	Inventory.add_item(BREAD_ITEM)
	Inventory.add_item(BANDAGE_ITEM)
	Inventory.add_item(DOC_ITEM)
	player.satchel.open()
	await frames(1)
	var bread_holder := player.satchel.get_node("Item_bread")
	check(Inventory.items().size() == 3 and player.satchel._holders.size() == 3 and bread_holder.get_child_count() == 2,
			"two breads lie as a little stack", bread_holder.get_child_count())
	Inventory.add_item(BREAD_ITEM)
	Inventory.add_item(BREAD_ITEM)
	check(player.satchel.get_node("Item_bread").get_child_count() == SatchelView.STACK_SHOWN,
			"four breads: the stack shows %d" % SatchelView.STACK_SHOWN, player.satchel.get_node("Item_bread").get_child_count())
	Inventory.remove_item("bread")
	Inventory.remove_item("bread")
	# The strafe keys: right to the next, left from the first round the end.
	player.satchel.selected = 0
	await _hold_action_until("move_right", func() -> bool: return player.satchel.selected != 0)
	check(player.satchel.selected == 1, "the strafe key to the right picks the next thing", player.satchel.selected)
	player.satchel.selected = 0
	await _hold_action_until("move_left", func() -> bool: return player.satchel.selected != 0)
	check(player.satchel.selected == 2, "to the left from the first: round the end to the last", player.satchel.selected)
	# The stick: one push is one step, however many motion events it sends
	# and however long it is held.
	player.satchel.selected = 0
	var steps := 0
	var last := 0
	for v in [0.35, 0.6, 0.8, 1.0, 0.9, 1.0, 0.95, 1.0, 1.0, 1.0, 0.0, 0.0]:
		_stick_x(v)
		await _passes()
		if player.satchel.selected != last:
			steps += 1
			last = player.satchel.selected
	check(steps == 1 and player.satchel.selected == 1, "one push of the stick, held, picks one thing",
			[steps, player.satchel.selected])
	for v in [0.7, 1.0]:
		_stick_x(v)
		await _passes()
	_stick_x(0.0)
	await _passes()
	check(player.satchel.selected == 2, "back to the middle and pushed again: the next", player.satchel.selected)
	player.satchel.selected = Inventory.items().find(BREAD_ITEM)
	player.satchel._place()
	var up := player.satchel.get_node("Item_bread") as Node3D
	check(player.satchel.selected_item() == BREAD_ITEM and up.position.y > 0.0,
			"the picked bread lies closer", player.satchel.selected)
	hunger.level = 0.1
	check(not player.use_item(player.satchel.selected_item()) and Inventory.count("bread") == 2, "not hungry, he keeps the bread")
	await _until(func() -> bool: return absf(up.rotation.y) > 0.01, 0.5)  # the tween's first step
	check(player.satchel._shake != null and player.satchel._shake.is_running() and absf(up.rotation.y) > 0.01,
			"and the bread is shaken, like a head: no text", up.rotation.y)
	hunger.level = 0.9
	heard.clear()
	sounds.clear()
	await _press_action("interact")
	check(Inventory.count("bread") == 1 and absf(hunger.level - (0.9 - Hunger.BREAD)) < 0.01 and hunger.timer > 1.0,
			"hungry, he eats a bread: one fewer, the hunger put off", [Inventory.count("bread"), hunger.level])
	check(sounds.has("chew_bread") and heard.size() == 1 and heard[0] <= Hunger.CHEW_NOISE + 0.001,
			"chewing is quiet, but not silent", heard)
	check((player.satchel.get_node("Item_bread") as Node3D).get_child_count() == 1 and player.satchel.is_open,
			"the satchel stays open with one bread left")
	# Panic narrows the view: the satchel stays in the frame.
	for fov in [player.base_fov, player.base_fov - player.panic_fov_narrowing]:
		player.camera.fov = fov
		player.satchel._process(0.0)
		var inside := true
		for h in player.satchel._holders:
			inside = inside and player.camera.is_position_in_frustum(h.global_position) \
					and player.camera.is_position_in_frustum(h.global_position + Vector3.DOWN * 0.04)
		check(inside, "with the view at %d deg the whole satchel is in the frame" % int(fov), player.satchel.position)
	player.camera.fov = player.base_fov
	# In a hiding place the gaps are drawn over the whole view: there he
	# looks into the satchel instead, and cannot watch the room meanwhile.
	var hide := STOVE_NOOK.instantiate() as HideSpot
	hide.position = Vector3(6, 0, 0)
	root.add_child(hide)
	await frames(1)
	hide.admit(player)
	await frames(2)
	await _passes()
	check(player.is_hidden and player.camera.cull_mask == SatchelView.LAYER | Player.POST_LAYER
			and not player.hide_overlay.visible and player.satchel._glow.visible,
			"open in a hiding place: he looks into the satchel, the gaps gone", player.camera.cull_mask)
	var shown := not player.satchel._holders.is_empty()
	for h in player.satchel._holders:
		for mi in h.get_children():
			shown = shown and ((mi as VisualInstance3D).layers & player.camera.cull_mask) != 0
	var film := 0
	for pass_node in player.camera.get_node("PostProcess").get_children():
		if ((pass_node as VisualInstance3D).layers & player.camera.cull_mask) != 0:
			film += 1
	check(shown and film == 3, "the things and the film passes stay on screen", film)
	player.satchel.close()
	await frames(1)
	await _passes()
	check(player.camera.cull_mask == view_mask and player.hide_overlay.visible and not player.satchel._glow.visible,
			"the satchel shut: the gaps again", player.camera.cull_mask)
	player.satchel.open()
	await frames(1)
	hide.interact(player)
	await frames(2)
	await _passes()
	check(not player.is_hidden and player.camera.cull_mask == view_mask and not player.hide_overlay.visible
			and player.satchel.is_open and not player.satchel._glow.visible,
			"out of the hiding place with the satchel open: the room in view", player.camera.cull_mask)
	hide.queue_free()
	check(not player.use_item(BANDAGE_ITEM) and Inventory.count("bandage") == 1, "a bandage is no use now: kept")
	# A document is read.
	if player.archive_ui.is_open:
		player.archive_ui.close()
	player.satchel.open()
	check(player.use_item(DOC_ITEM) and not player.satchel.is_open and player.archive_ui.is_open,
			"a document from the satchel is read")
	player.archive_ui.close()
	# Seized, nothing is used.
	player.seized = true
	check(not player.use_item(BREAD_ITEM) and Inventory.count("bread") == 1, "held by the collar, he eats nothing")
	player.seized = false
	# Seated at the interrogation, the hunger does not run on.
	player.is_seated = true
	var lvl := hunger.level
	hunger._process(100.0)
	check(hunger.level == lvl, "seated at the interrogation, the stomach waits", hunger.level)
	player.is_seated = false

	Stealth.noise_emitted.disconnect(on_noise)
	Sfx.played.disconnect(on_sound)
	Inventory.clear()
	PanicSystem.reset()
	root.queue_free()
	await frames(2)

	# The acts: a little hungry in the village, hungry on the road after the
	# night in the forest, fed by the partisans before the garrison.
	for pair in [[LEVEL, 0.25], [ACT2, 0.65], [ACT3, 0.15]]:
		var level := (pair[0] as PackedScene).instantiate()
		level.play_intro = false
		add_child(level)
		level._ending = true
		await frames(2)
		var lp := level.get_node("Player") as Player
		check(absf(lp.hunger.level - float(pair[1])) < 0.01,
				"%s starts with hunger %.2f" % [(pair[0] as PackedScene).resource_path.get_file(), pair[1]],
				lp.hunger.level)
		level.queue_free()
		await frames(2)
	check(not Stealth.cover and not Stealth.staring, "a level gone, its cover goes with it", Stealth.cover)
	Stealth.reset_cover()


## Presses an action through the input (as a key would) and lets it go.
func _press_action(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	# Held over a whole main-loop pass as well: the satchel reads the strafe
	# keys in _process, and under load both physics frames can fall into one
	# pass - the key would be up again before _process ever saw it down (the
	# final run of 18.11.2026 failed "the strafe key to the right" so).
	await get_tree().process_frame
	await get_tree().process_frame
	_release_action(action)
	await frames(1)
	# Parsed input is handed out once per main-loop pass, and several physics
	# frames can fall into one pass: without a full pass the press might reach
	# the game only after the caller's check (a "nothing happened" passing
	# vacuously).
	await get_tree().process_frame
	await get_tree().process_frame


## The left stick pushed sideways to `x` (-1..1), as a pad sends it.
func _stick_x(x: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = JOY_AXIS_LEFT_X
	ev.axis_value = x
	Input.parse_input_event(ev)


## An action pressed through Input.parse_input_event stays held until released.
## `action` held till `done` holds or `timeout` real seconds are up, then
## let go: under load the pass whose _process reads the key may come late.
func _hold_action_until(action: StringName, done: Callable, timeout: float = 2.0) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await _until(done, timeout)
	_release_action(action)
	await frames(1)
	await _passes()


func _release_action(action: StringName) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = false
	Input.parse_input_event(ev)
	Input.action_release(action)


func _run_factor_at(hunger: Hunger, lvl: float) -> float:
	var keep := hunger.level
	hunger.level = lvl
	var f := hunger.run_factor()
	hunger.level = keep
	return f


## Checkpoints on the road: reached calmly, they bring the boy back there
## after capture or a mine, with his satchel; a restart clears them.
func _test_act2_checkpoints() -> void:
	var level := _act2_instance(false)
	await frames(3)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set_physics_process(false)
	var player := level.get_node("Player") as Player
	check(level.checkpoint_index == -1 and level.checkpoints.size() == 3, "no checkpoint at the start of the road")
	check(absf(player.hunger.level - 0.65) < 0.01, "after the night in the forest he starts the road hungry",
			player.hunger.level)
	player.global_position = (level.get_node("Spawns/Village") as Node3D).global_position
	await frames(3)
	check(level.checkpoint_index == 0, "the burned village is a checkpoint", level.checkpoint_index)
	var bread := _bread_pickup(level)
	bread.interact(player)
	check(Inventory.has_item("bread"), "bread in the satchel")
	# Running past a checkpoint with someone on his heels does not save it.
	var patrol := get_tree().get_nodes_in_group("enemies")[0] as Enemy
	patrol._set_state(Enemy.State.ALERT)
	player.global_position = (level.get_node("Spawns/Field") as Node3D).global_position
	await frames(3)
	check(level.checkpoint_index == 0, "no checkpoint while chased")
	player.hunger.level = 0.33
	player.wound.cut()  # through the wire on the way, say
	player.wound.bled_for = 100.0
	patrol._set_state(Enemy.State.PATROL)
	await frames(3)
	check(level.checkpoint_index == 1, "calm again at the field: saved", level.checkpoint_index)
	check(level._restarts_at_checkpoint(), "capture now brings him back here")
	# A mine also brings him back (the reload itself is not run here).
	level._on_mine(null)
	check(LevelBase._resume_after_intro, "a mine also restarts at the checkpoint")
	level.queue_free()
	await frames(2)

	# The reload after capture.
	level = _act2_instance(true)
	await frames(3)
	player = level.get_node("Player") as Player
	var field := (level.get_node("Spawns/Field") as Node3D).global_position
	check(level.resumed and level.checkpoint_index == 1 and player.global_position.distance_to(field) < 0.2,
			"back at the field", player.global_position)
	check(Inventory.has_item("bread") and _bread_pickup(level) == null, "the bread is in the satchel, not on the ground")
	check(absf(player.hunger.level - 0.33) < 0.01, "and as hungry as he was there", player.hunger.level)
	check(player.wound.bleeding and player.wound.drops == 0 and player.wound.bled_for >= 100.0
			and player.wound.bled_for < 103.0, "and still bleeding, as long as it had bled: coming back heals nothing",
			player.wound.bled_for)
	var black: float = level.fade.modulate.a
	var lifted: bool = await _until(func() -> bool: return level.fade.modulate.a < 0.01, 5.0)
	check(black > 0.2 and lifted, "he comes back out of black", [black, level.fade.modulate.a])
	level.queue_free()
	await frames(2)

	# "Начать акт заново" (no resume): the road from the start, empty satchel.
	level = _act2_instance(false)
	await frames(3)
	player = level.get_node("Player") as Player
	check(level.checkpoint_index == -1 and LevelBase._checkpoint.is_empty() and not Inventory.has_item("bread")
			and _bread_pickup(level) != null and absf(player.hunger.level - 0.65) < 0.01, "a restart clears the checkpoint")
	check(player.global_position.distance_to((level.get_node("Spawns/Start") as Node3D).global_position) < 0.5,
			"and starts at the beginning of the road")
	check(not player.wound.bleeding, "unhurt")
	level.queue_free()
	await frames(2)

	# Every checkpoint is a safe place to come back to: standing still for
	# three seconds there, nobody notices him.
	var names: Array[String] = ["Village", "Field", "Camp", "Camp"]
	for i in names.size():
		LevelBase._checkpoint = {"scene": ACT2.resource_path, "index": mini(i, 2), "items": [], "documents": [],
				"taken": [], "bleeding": i == 3}
		level = _act2_instance(true)
		var pl := level.get_node("Player") as Player
		if i == 3:
			check(pl.wound.bleeding and pl.wound.drops == 0, "come back to the camp bleeding: no drop at once",
					pl.wound.drops)
		var nav := level.get_node("Navigation") as RuntimeNavRegion
		var t0 := Time.get_ticks_msec()
		while not nav.is_baked and Time.get_ticks_msec() - t0 < 15000:
			await get_tree().physics_frame
		if i == 3:
			# The worst case: drops where he stands and a step towards the road.
			pl.wound.drop()
			Stealth.lay_blood(pl.global_position + Vector3(-Wound.DROP_SPACING - 0.2, 0, 0))
		var who: Array[String] = []
		t0 = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 3000:
			await get_tree().physics_frame
			for e in get_tree().get_nodes_in_group("enemies"):
				var en := e as Enemy
				if en.is_visible_in_tree() and en.state != Enemy.State.PATROL and not who.has(str(en.name)):
					who.append("%s:%s" % [en.name, Enemy.State.keys()[en.state]])
			if level._ending and not who.has("caught"):
				who.append("caught")
		if i == 3:
			check((level.get_node("CampDog") as Dog).trail_seq < 0, "the camp dog does not smell his blood there")
		check(who.is_empty(), "checkpoint %s is a quiet place to come back to%s" % [names[i],
				" bleeding" if i == 3 else ""], who)
		level._ending = true
		level.queue_free()
		await frames(2)
	LevelBase._checkpoint = {}
	LevelBase._resume_after_intro = false
	Inventory.clear()


## A wound (Wound, docs/ARCHITECTURE.md, "Рана и бинт"): torn on the wire,
## he bleeds - dark red drops behind him, a trail a dog smells from far off
## and for long; hidden he presses it, no drops; a bandage from the satchel
## binds it in a few quiet seconds; unbound it stops by itself.
func _test_wound() -> void:
	PanicSystem.reset()
	Perception.reset()
	Stealth.reset_cover()
	Stealth.clear_scent()
	Inventory.clear()

	# Blood in the trail: laid apart from the steps, it outlives them.
	Stealth.lay_scent(Vector3(0, 0, 0))
	Stealth.lay_blood(Vector3(0.3, 0, 0))
	Stealth.lay_scent(Vector3(2, 0, 0))
	var blood_pt: Dictionary = Stealth.scent_trail[1] if Stealth.scent_trail.size() == 3 else {}
	check(Stealth.scent_trail.size() == 3 and blood_pt.get("blood", false),
			"a drop of blood goes into the trail, never merged with a step", Stealth.scent_trail.size())
	check(Stealth.blood_near(Vector3(0.3, 0, 9.5), 10.0) == blood_pt
			and Stealth.blood_near(Vector3(0.3, 0, 10.5), 10.0).is_empty()
			and Stealth.blood_near(Vector3(2, 0, 0), 0.5).is_empty(),
			"blood is smelled within the radius asked, and a step is not blood")
	Stealth.clock += Stealth.SCENT_LIFETIME + 1.0
	check(Stealth.freshest_scent_near(Vector3(2, 0, 0), 2.0) == blood_pt,
			"the steps have gone cold, the blood has not")
	check(Stealth.scent_after(-1) == blood_pt and Stealth.scent_after(int(blood_pt.get("seq", 0))).is_empty(),
			"a trail followed from its start skips the cold steps to the blood")
	Stealth.clock += Stealth.BLOOD_LIFETIME - Stealth.SCENT_LIFETIME
	check(Stealth.freshest_scent_near(Vector3(0.3, 0, 0), 2.0).is_empty()
			and Stealth.blood_near(Vector3(0.3, 0, 0), 10.0).is_empty(), "in the end the blood goes cold too")
	Stealth.clear_scent()
	# A step beside a drop is a point of its own: the drop lives from when it
	# fell, not from his last step there.
	Stealth.lay_blood(Vector3(0, 0, 5))
	Stealth.clock += 100.0
	Stealth.lay_scent(Vector3(0.3, 0, 5))
	Stealth.clock += 60.0
	check(Stealth.scent_trail.size() == 2 and Stealth.blood_near(Vector3(0, 0, 5), 10.0).is_empty(),
			"a step beside a drop does not keep the drop fresh", Stealth.scent_trail.size())
	Stealth.clear_scent()
	# A long walk bleeding: the trail sheds cold steps before live blood.
	for i in 450:
		Stealth.clock += 140.0 / 450.0
		if i % 2 == 0:
			Stealth.lay_blood(Vector3(i * 1.5, 0, 0))
		else:
			Stealth.lay_scent(Vector3(i * 1.5, 0, 0))
	check(not Stealth.blood_near(Vector3(0, 0, 0), 0.5).is_empty() and Stealth.scent_trail.size() <= Stealth.SCENT_MAX_POINTS,
			"after two minutes of walking bleeding the first drop is still smelled", Stealth.scent_trail.size())
	Stealth.clear_scent()

	var root := Node3D.new()
	var ground := CSGBox3D.new()
	ground.size = Vector3(60, 1, 60)
	ground.position = Vector3(0, -0.5, 0)
	ground.use_collision = true
	root.add_child(ground)
	# A crate to stand on: a drop falls on whatever is underfoot.
	var crate := CSGBox3D.new()
	crate.size = Vector3(2, 0.5, 2)
	crate.position = Vector3(20, 0.25, 20)
	crate.use_collision = true
	root.add_child(crate)
	var player := PLAYER_SCENE.instantiate() as Player
	root.add_child(player)
	add_child(root)
	await frames(3)
	player.set_physics_process(false)
	player.breath.set_physics_process(false)
	player.get_node("PhantomSounds").set_process(false)
	player.hunger.set_process(false)
	var wound := player.wound
	check(wound != null and not wound.bleeding and wound.drops == 0 and not player.busy(), "the boy starts unhurt")
	if wound == null:
		root.queue_free()
		await frames(2)
		return
	wound.set_process(false)  # driven by hand below
	var heard: Array[float] = []
	var on_noise := func(_at: Vector3, loud: float, source: Node) -> void:
		if source == player:
			heard.append(loud)
	var sounds: Array[String] = []
	var on_sound := func(id: String, _sp: AudioStreamPlayer3D) -> void:
		sounds.append(id)
	Stealth.noise_emitted.connect(on_noise)
	Sfx.played.connect(on_sound)
	var count := {"cut": 0, "bound": 0}
	wound.cut_open.connect(func() -> void: count["cut"] += 1)
	wound.bound.connect(func() -> void: count["bound"] += 1)
	var blood_points := func() -> int:
		var n := 0
		for pt in Stealth.scent_trail:
			if pt.get("blood", false):
				n += 1
		return n

	# Torn open.
	player.global_position = Vector3(-5, 0, 0)
	wound.cut()
	check(wound.bleeding and count["cut"] == 1 and absf(PanicSystem.level - Wound.CUT_PANIC) < 0.01
			and sounds == ["breath_hiss"], "torn on the wire: it bleeds, a start of fright, a hiss through his teeth",
			[PanicSystem.level, sounds])
	check(heard.is_empty(), "the hiss is his own: nobody hears it", heard)
	# Walking: the first drop at once, then one every DROP_SPACING metres.
	wound._process(0.1)
	check(wound.drops == 1, "the first drop falls at once", wound.drops)
	for i in 50:
		player.global_position += Vector3(0.14, 0, 0)
		wound._process(0.1)
	check(wound.drops >= 5 and wound.drops <= 6, "seven metres walked: a drop every metre and a half", wound.drops)
	var nodes := wound.drop_nodes()
	var red := true
	var flat := true
	for d in nodes:
		red = red and d.get_parent() == root \
				and ColorMask.channel_of((d as MeshInstance3D).material_override) == ColorMask.Channel.RED
		flat = flat and absf(d.global_position.y) < 0.02
	check(nodes.size() == wound.drops and red and flat,
			"the drops lie on the ground behind him, dark red (blood: the red channel)", [nodes.size(), red, flat])
	check(nodes.size() >= 2 and nodes[-1].global_position.x - nodes[-2].global_position.x > 0.9,
			"spaced out along his way")
	check(blood_points.call() == wound.drops and Stealth.scent_trail.size() == wound.drops,
			"every drop is blood in his trail", [blood_points.call(), wound.drops])
	# Standing still, it drips now and then.
	var d1 := wound.drops
	for i in 55:
		wound._process(0.1)
	var none_yet := wound.drops == d1
	for i in 10:
		wound._process(0.1)
	check(none_yet and wound.drops == d1 + 1, "standing still, a drop every few seconds", wound.drops - d1)
	# Hidden he presses it; seated or crawling, nothing falls either.
	for flag in ["is_hidden", "is_seated", "crawling"]:
		var d2 := wound.drops
		player.set(flag, true)
		for i in 80:
			player.global_position += Vector3(0, 0, 0.05)
			wound._process(0.1)
		player.set(flag, false)
		check(wound.drops == d2, "%s: no drops" % flag, wound.drops - d2)
	# Now and then he winces.
	sounds.clear()
	var w0 := wound.winces
	wound._wince = 0.05
	wound._process(0.1)
	check(wound.winces == w0 + 1 and sounds.has("breath_hiss") and wound._wince >= Wound.WINCE_MIN - 0.2
			and heard.is_empty(), "now and then he winces: a hiss only he hears", sounds)
	# Unbound, it stops by itself.
	wound.bled_for = Wound.CLOT_TIME - 0.05
	wound._process(0.1)
	var d3 := wound.drops
	for i in 30:
		player.global_position += Vector3(-0.14, 0, 0)
		wound._process(0.1)
	check(not wound.bleeding and wound.drops == d3, "unbound, it stops by itself after a while", wound.bled_for)
	# Brought back bleeding (a checkpoint): no drop at once.
	wound.set_bleeding(true)
	wound._process(0.1)
	check(wound.bleeding and wound.drops == d3 and wound.bled_for < 1.0, "back at a checkpoint bleeding: no drop at once")
	# A drop falls on whatever he stands on.
	player.global_position = Vector3(20, 0.5, 20)
	wound.drop()
	var top := wound.drop_nodes()[-1]
	check(absf(top.global_position.y - 0.5) < 0.02, "a drop falls on what he stands on", top.global_position.y)
	# Only so many drops are kept on the ground.
	for i in Wound.MAX_DROPS + 10:
		wound.drop()
	await frames(1)
	var on_ground := 0
	for c in root.get_children():
		if str(c.name).begins_with("BloodDrop"):
			on_ground += 1
	check(wound.drop_nodes().size() == Wound.MAX_DROPS and on_ground == Wound.MAX_DROPS,
			"no more than MAX_DROPS drops kept in a level", [wound.drop_nodes().size(), on_ground])
	wound.set_bleeding(false)
	Stealth.clear_scent()

	# The bandage binds it.
	player.global_position = Vector3(0, 0, 0)
	Inventory.add_item(BANDAGE_ITEM)
	Inventory.add_item(BANDAGE_ITEM)
	wound.cut()
	player.satchel.open()
	await frames(1)
	heard.clear()
	sounds.clear()
	check(player.use_item(BANDAGE_ITEM) and Inventory.count("bandage") == 1 and not player.satchel.is_open
			and wound.is_binding() and player.busy() and not player.is_input_locked(),
			"bleeding, a bandage binds the wound: one spent, the satchel shut, his hands busy (he can look about)")
	var loudest := 0.0
	for l in heard:
		loudest = maxf(loudest, l)
	check(sounds.has("bandage_wrap") and absf(loudest - Wound.BIND_NOISE) < 0.001,
			"a quiet rustle of torn cloth, heard only close by", [sounds, heard])
	check(not player.use_item(BANDAGE_ITEM) and Inventory.count("bandage") == 1 and wound.binding > Wound.BIND_TIME - 0.01,
			"one bandage at a time")
	await _press_action("inventory")
	check(not player.satchel.is_open, "binding, he does not open the satchel")
	player.set_physics_process(true)
	var at := player.global_position
	Input.action_press("move_forward")
	await frames(8)
	Input.action_release("move_forward")
	await frames(1)
	player.set_physics_process(false)
	check(Vector2(player.global_position.x - at.x, player.global_position.z - at.z).length() < 0.01,
			"nor walk", player.global_position)
	var d5 := wound.drops
	wound._process(Wound.BIND_TIME - 0.5)
	check(wound.is_binding() and wound.bleeding and wound.drops == d5 and count["bound"] == 0,
			"it takes a few seconds; meanwhile no drops")
	wound._process(0.6)
	check(not wound.bleeding and not wound.is_binding() and not player.busy() and count["bound"] == 1,
			"bound: the blood stops, his hands are free")
	check(not player.use_item(BANDAGE_ITEM) and Inventory.count("bandage") == 1, "bound, the other bandage is kept")
	await _press_action("inventory")
	check(player.satchel.is_open, "and the satchel opens again")
	player.satchel.close()
	# Seized while binding: the bandage is torn out of his hands.
	wound.cut()
	check(player.use_item(BANDAGE_ITEM) and wound.is_binding(), "torn again: the second bandage")
	player.seized = true
	wound._process(0.1)
	check(not wound.is_binding() and wound.bleeding and not player.busy(), "seized, the binding is torn off: it bleeds on")
	check(not wound.start_binding(), "held by the collar, he binds nothing")
	player.seized = false
	wound.set_bleeding(false)

	Stealth.noise_emitted.disconnect(on_noise)
	Sfx.played.disconnect(on_sound)
	Stealth.clear_scent()
	Inventory.clear()
	PanicSystem.reset()
	root.queue_free()
	await frames(2)


## The barbed wire across the end of the field (Act2Layout._field_wire):
## open only for the road, by the camp guard and his dog; the other way is
## the gap under it - crawled through, heard close by, it tears his arm. The
## dog picks blood up from far off the road; plain steps there it misses.
func _test_wire_gap() -> void:
	Stealth.clear_scent()
	Inventory.clear()
	var level := _act2_instance(false)
	var nav := level.get_node("Navigation") as RuntimeNavRegion
	var t0 := Time.get_ticks_msec()
	while not nav.is_baked and Time.get_ticks_msec() - t0 < 15000:
		await get_tree().physics_frame
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set_physics_process(false)
	# The searchlight sweeps the gap too (a hazard of its own, tested in
	# _test_act2): here it would raise alarms that are not the wire's.
	var tower := level.get_node("Layout/Camp/Tower")
	tower.set_physics_process(false)
	tower.set_process(false)
	var player := level.get_node("Player") as Player
	var space := level.get_world_3d().direct_space_state
	var walled := func(x: float) -> bool:
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 1, -82), Vector3(x, 1, -86), player.collision_mask)
		q.exclude = [player.get_rid()]
		return not space.intersect_ray(q).is_empty()
	var open_at: Array[float] = []
	# 13: the gap is crawled under, not walked through.
	for x in [-13.4, -9.0, -4.0, -2.6, 2.6, 4.0, 8.5, 13.0, 15.0, 24.0, 31.4]:
		if not walled.call(x):
			open_at.append(x)
	check(open_at.is_empty() and not walled.call(0.0) and not walled.call(1.8),
			"barbed wire across the end of the field, thicket to thicket, open only for the road", open_at)
	var gap := level.get_node_or_null("Layout/FieldWire/WireGap") as WireGap
	var marked := gap != null
	if gap != null:
		for c in gap.get_children():
			if c is CSGBox3D:
				marked = marked and ColorMask.channel_of((c as CSGBox3D).material) == ColorMask.Channel.INTERACTIVE
	check(marked and gap.global_position.distance_to(WIRE_GAP) < 0.01,
			"a gap is dug under it, the stick propping the strand blue-green")
	if gap == null:
		level._ending = true
		level.queue_free()
		await frames(2)
		return

	var sounds: Array[String] = []
	var on_sound := func(id: String, _sp: AudioStreamPlayer3D) -> void:
		sounds.append(id)
	var heard: Array = []
	var on_noise := func(_at: Vector3, loud: float, source: Node) -> void:
		if source == player:
			heard.append([loud, Stealth.noise_is_action])
	Stealth.noise_emitted.connect(on_noise)
	Sfx.played.connect(on_sound)
	var crawled := [0]
	gap.crawled.connect(func(_p: Node) -> void: crawled[0] += 1)
	var action_noise := func() -> float:
		var most := 0.0
		for h in heard:
			if h[1]:
				most = maxf(most, h[0])
		return most

	# Under the wire, north.
	player.global_position = Vector3(WIRE_GAP.x, 0, WIRE_GAP.z + 1.2)
	player.look_towards(WIRE_GAP + Vector3.UP * 0.2)
	await frames(2)
	heard.clear()
	sounds.clear()
	t0 = Time.get_ticks_msec()
	check(player.try_interact() and gap.busy and player.crawling and player.busy() and player.is_input_locked()
			and player.collision.disabled, "the propped strand: he gets down and crawls under the wire")
	check(absf(action_noise.call() - WireGap.CRAWL_NOISE) < 0.01 and sounds.has("wire_scrape"),
			"the wire shakes and scrapes: heard close by", heard)
	check(not player.try_interact(), "one crawl at a time")
	var lowest := 9.0
	var saved := -1
	while gap.busy and Time.get_ticks_msec() - t0 < 6000:
		lowest = minf(lowest, player.head.position.y)
		saved = maxi(saved, level.checkpoint_index)
		await get_tree().process_frame
	var took := (Time.get_ticks_msec() - t0) / 1000.0
	check(crawled[0] == 1 and not player.crawling and not player.collision.disabled
			and player.global_position.z < WIRE_GAP.z - 0.5 and lowest < WireGap.CRAWL_EYE + 0.05,
			"on his belly to the other side", [player.global_position, lowest, took])
	check(player.wound.bleeding and sounds.has("cloth_tear") and sounds.has("breath_hiss"),
			"the barbs catch his arm: torn cloth, a hiss, and it bleeds", sounds)
	await frames(3)
	check(player.wound.drops >= 1, "the first drop falls as he gets up", player.wound.drops)
	check(saved == -1 and level.checkpoint_index == -1, "nothing is saved on the way under the wire",
			[saved, level.checkpoint_index])
	# Past the wire, by a haystack mid-field: saved - not while his hands
	# are busy - and the checkpoint keeps the wound.
	var camp := (level.get_node("Spawns/Camp") as Node3D).global_position
	check(camp.distance_to(Vector3(WIRE_GAP.x, 0, WIRE_GAP.z - WireGap.REACH)) > level.checkpoint_radius
			and camp.z + level.checkpoint_radius < WIRE_GAP.z - 0.5
			and absf(camp.x - (-2.2)) > Wound.DROP_SPACING + 10.0 + 0.2,
			"the camp checkpoint lies wholly past the wire, beyond the dog's nose from its beat", camp)
	player.global_position = camp + Vector3(0, 0, 1.0)
	player.crawling = true
	await frames(3)
	var saved_busy: int = level.checkpoint_index
	player.crawling = false
	await frames(3)
	check(saved_busy == -1 and level.checkpoint_index == 2 and bool(LevelBase._checkpoint.get("bleeding", false)),
			"past the wire the camp checkpoint is saved, not while busy, and it keeps the wound",
			[saved_busy, level.checkpoint_index])
	# A drop on the road lies on top of it, not hidden under it.
	player.global_position = Vector3(0, 0, -70)
	await frames(2)
	player.wound.drop()
	var on_road := player.wound.drop_nodes()[-1]
	check(on_road.global_position.y > 0.02, "a drop on the road lies on the road", on_road.global_position.y)

	# Back again, crouched: slower and half as loud.
	player.global_position = Vector3(WIRE_GAP.x, 0, WIRE_GAP.z - 1.2)
	player.look_towards(WIRE_GAP + Vector3.UP * 0.2)
	await frames(2)
	heard.clear()
	player.is_crouching = true
	t0 = Time.get_ticks_msec()
	check(player.try_interact(), "and back from the other side")
	player.is_crouching = false
	check(absf(action_noise.call() - WireGap.CRAWL_NOISE * Player.CAREFUL) < 0.01, "crouched: half as loud", heard)
	while gap.busy and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
	var took_careful := (Time.get_ticks_msec() - t0) / 1000.0
	check(crawled[0] == 2 and player.global_position.z > WIRE_GAP.z + 0.5 and took_careful > took + 0.6,
			"and slower", [took, took_careful])

	# Crouched and pressed to the wire, he finds the gap too.
	Input.action_press("crouch")
	player.global_position = Vector3(WIRE_GAP.x + 0.1, 0, WIRE_GAP.z + 0.42)
	await frames(25)
	player.global_position = Vector3(WIRE_GAP.x + 0.1, 0, WIRE_GAP.z + 0.42)
	player.look_towards(WIRE_GAP + Vector3(0.15, 0.25, 0))
	await frames(2)
	var eye_off := absf(player.camera.global_position.z - WIRE_GAP.z)
	var found := player.try_interact()
	Input.action_release("crouch")
	check(found and player.is_crouching and eye_off < 0.5, "crouched, pressed to the wire, he finds the gap",
			[found, player.is_crouching, eye_off])
	t0 = Time.get_ticks_msec()
	while gap.busy and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame

	# Caught under the wire, the crawl ends there.
	player.global_position = Vector3(WIRE_GAP.x, 0, WIRE_GAP.z + 1.2)
	player.look_towards(WIRE_GAP + Vector3.UP * 0.2)
	await frames(2)
	check(player.try_interact(), "under the wire once more")
	await _wait(0.8)
	player.seized = true
	await frames(2)
	check(not gap.busy and not player.crawling and not player.collision.disabled and crawled[0] == 3,
			"seized meanwhile: the crawl is cut short", player.global_position)
	player.seized = false
	Stealth.noise_emitted.disconnect(on_noise)
	Sfx.played.disconnect(on_sound)

	# The camp dog: steps eight metres off the road it misses; blood there it
	# picks up, leaves the road for and barks.
	player.wound.set_bleeding(false)
	player.global_position = (level.get_node("Spawns/Start") as Node3D).global_position
	await frames(2)
	var dog := level.get_node("CampDog") as Dog
	var guard := level.get_node("CampGuard") as Enemy
	var dog_from := dog.global_position
	var guard_from := guard.global_position
	var east := [-99.0]
	var barks0 := dog.barks
	Stealth.clear_scent()
	for i in 11:
		Stealth.lay_scent(Vector3(6, 0, -90.0 - i * 1.4))
	dog.set_physics_process(true)
	guard.set_physics_process(true)
	for f in 360:
		await get_tree().physics_frame
		east[0] = maxf(east[0], dog.global_position.x)
	check(east[0] < 2.0 and dog.barks == barks0, "steps eight metres off the road: the dog misses them",
			[east[0], dog.barks - barks0])
	dog.set_physics_process(false)
	guard.set_physics_process(false)
	dog.global_position = dog_from
	guard.global_position = guard_from
	dog.trail_seq = -1
	Stealth.clear_scent()
	for i in 11:
		Stealth.lay_blood(Vector3(6, 0, -90.0 - i * 1.4))
	# And a step of a walk much later, far off the end of the blood.
	Stealth.lay_scent(Vector3(22, 0, -104))
	var blood_end := Vector3(6, 0, -104)
	dog.set_physics_process(true)
	guard.set_physics_process(true)
	east[0] = -99.0
	var near_end := 99.0
	for f in 1500:
		await get_tree().physics_frame
		east[0] = maxf(east[0], dog.global_position.x)
		near_end = minf(near_end, dog.global_position.distance_to(blood_end))
		if near_end < 1.5 and dog.trail_seq < 0:
			break
	check(east[0] > 4.0 and dog.barks > barks0 and near_end < 1.5, "blood there: the dog leaves the road for it, barking, to its end",
			[east[0], dog.barks - barks0, near_end])
	var barks1 := dog.barks
	for f in 300:
		await get_tree().physics_frame
		east[0] = maxf(east[0], dog.global_position.x)
	check(dog.barks - barks1 <= 2, "at the end of the blood the dog falls quiet", dog.barks - barks1)
	check(east[0] < 11.0, "and does not run on to a step far off that came long after", east[0])
	level._ending = true
	level.queue_free()
	await frames(2)
	LevelBase._checkpoint = {}
	LevelBase._resume_after_intro = false
	Stealth.clear_scent()
	Inventory.clear()
	PanicSystem.reset()


## Where the gap under the field wire is (Act2Layout).
const WIRE_GAP := Vector3(13.0, 0, -84.0)


func _ray_clear(level: Node3D, a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	return level.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# --- Act III ---------------------------------------------------------------------

const ACT3 := preload("res://src/scenes/act3_garrison/act3_garrison.tscn")
const ACT3_SCRIPT := preload("res://src/scenes/act3_garrison/act3_garrison.gd")


func _wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < sec * 1000.0:
		await get_tree().process_frame


## Whole main-loop passes: every node's _process (and every tween) has run at
## least once after this. Physics frames alone do not promise it - under load
## several fall into one pass, before its _process (the final run of
## 18.11.2026 failed three such checks).
func _passes(n: int = 2) -> void:
	for i in n:
		await get_tree().process_frame


## Waits, in real time and whole passes, till `cond` holds or `timeout`
## seconds are up. Whether it held is for the caller's check.
## Until the izba door's leaf has finished its swing. It turns in the
## physics frame, and under load physics falls behind the clock: a set wait
## may end with the leaf still on its way (docs/ARCHITECTURE.md, "Проверка").
func _swung(door: IzbaDoor, timeout: float = 4.0) -> bool:
	return await _until(func() -> bool: return not door.is_swinging(), timeout)


func _until(cond: Callable, timeout: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > timeout * 1000.0:
			return false
		await get_tree().process_frame
	return true


## Radians a second the right stick at `strength` turns him: the angle over
## the very frames that turned him, divided by the sum of their delta (he
## turns in _process by delta). process_frame comes before every _process,
## so each pass adds the delta the player is about to turn by.
func _stick_rate(player: Player, strength: float) -> float:
	Input.action_press("look_right", strength)
	await get_tree().process_frame
	var yaw := player.rotation.y
	var dt := 0.0
	var n := 0
	while dt < 0.3 or n < 5:
		dt += get_process_delta_time()
		n += 1
		await get_tree().process_frame
	var turned := angle_difference(player.rotation.y, yaw)
	Input.action_release("look_right")
	return turned / dt


func _test_pass_rules() -> void:
	var data := PassRules.load_data()
	check(PassRules.is_valid(data.sample, data), "the genuine sample passes its own check")
	var valid: Array[String] = []
	for c in data.candidates:
		if PassRules.is_valid(c, data):
			valid.append(c.id)
	check(valid == ["pass_c"], "exactly one forgery holds up", valid)
	check(PassRules.flaws(PassRules.find(data, "pass_a"), data) == ["stamp"], "square stamp is caught")
	check(PassRules.flaws(PassRules.find(data, "pass_b"), data) == ["date"], "an expired pass is caught")
	check(PassRules.flaws(PassRules.find(data, "pass_d"), data) == ["stamp", "route"],
			"stamp on the wrong side and a route elsewhere are caught",
			PassRules.flaws(PassRules.find(data, "pass_d"), data))
	check(PassRules.flaws({}, data) == ["missing"], "no pass at all is a flaw")
	check(PassRules.human_date("1942-10-31") == "31.10.1942", "dates are shown the Russian way")


func _test_interrogation_rules() -> void:
	var it := Interrogation.new()
	it.data = Interrogation.load_data()
	var qs: Array = it.questions()
	var by_id := {}
	for q in qs:
		by_id[q.id] = q
	check(qs.size() == 5, "five questions", qs.size())
	var shaped := true
	var latin := RegEx.create_from_string("[A-Za-z]")
	var no_latin := true
	for q in qs:
		shaped = shaped and (q.answers as Array).size() == 3 and float(q.time) > 0.0
		if latin.search(str(q.text)) != null:
			no_latin = false
		for a in q.answers:
			if latin.search(str(a.text)) != null:
				no_latin = false
	check(shaped, "every question has three answers and a timer")
	check(no_latin, "no German (no Latin script) in the lines on screen")
	check(it.evaluate(by_id.q_from, 0) == "consistent", "the cover story holds")
	check(it.evaluate(by_id.q_from, 1) == "contradiction", "another village contradicts the legend")
	check(it.evaluate(by_id.q_from, 2) == "silence", "silence is silence")
	check(it.evaluate(by_id.q_from, -1) == "timeout", "the timer running out")
	check(it.evaluate(by_id.q_pass, 1) == "suspicious", "'found it' is suspicious")
	check(it.evaluate(by_id.q_name, 2) == "contradiction", "going to the station contradicts the aunt")
	it.claims = {"from": "Ольховка"}
	check(it.evaluate(by_id.q_again, 0) == "consistent", "the same answer again is consistent")
	it.claims = {"pass_from": "староста"}
	check(it.evaluate({"answers": [{"text": "x", "claims": {"pass_from": "нашёл"}}]}, 0) == "contradiction",
			"an answer against an earlier answer is a contradiction")
	it.free()


func _act3_level() -> Node3D:
	PanicSystem.reset()
	Perception.reset()
	var level := ACT3.instantiate()
	level.play_intro = false
	level.checkpoint_wait = 0.3
	add_child(level)
	var it := level.get_node("Interrogation") as Interrogation
	it.opening_pause = 0.2
	it.pause_between = 0.2
	var player := level.get_node("Player") as Player
	player.get_node("BreathControl").set_physics_process(false)
	player.get_node("PhantomSounds").set_process(false)
	return level


func _test_act3() -> void:
	var level := _act3_level()
	var nav := level.get_node("Navigation") as RuntimeNavRegion
	var t0 := Time.get_ticks_msec()
	while not nav.is_baked and Time.get_ticks_msec() - t0 < 15000:
		await get_tree().physics_frame
	check(nav.is_baked, "Act III navmesh is baked")
	var player := level.get_node("Player") as Player
	var it := level.get_node("Interrogation") as Interrogation
	var enemies := get_tree().get_nodes_in_group("enemies")
	check(enemies.size() == 7, "Act III: two sentries, patrol, yard guard, gun crew, exit guard, investigator", enemies.size())
	check(Stealth.cover, "with the detachment's pass the boy walks openly (cover)")
	# Colour rule.
	var bundle := level.get_node("Bundle") as Interactable
	var teal := true
	for g in bundle.find_children("*", "MeshInstance3D", true, false):
		var mat := (g as MeshInstance3D).get_active_material(0)
		teal = teal and mat != null and ColorMask.channel_of(mat) == ColorMask.Channel.INTERACTIVE
	check(teal, "the bundle of passes is blue-green")
	var inv := level.get_node("OfficeScene/Investigator") as Enemy
	check(inv.kind == Enemy.Kind.OFFICER and inv.visual.get_node("Cap").visible
			and not inv.visual.get_node("Helmet").visible and inv.visual.get_node("Armband").visible,
			"the investigator: cap, no helmet, red armband")

	# 1. The pass check: the view pauses the game, a valid pass is taken.
	var ui := level.get_node("PassCheckUI") as PassCheckUI
	ui.open()
	await frames(1)
	check(ui.is_open and get_tree().paused and Perception.is_suppressed(), "the pass check is a clean, paused view")
	ui.step(1)
	check(ui.index == 1, "passes are leafed through")
	for i in ui.candidates().size():
		if ui.candidates()[i].id == "pass_c":
			ui.index = i
	ui.choose()
	check(not ui.is_open and not get_tree().paused and not Perception.is_suppressed(), "taking a pass closes the view")
	check(level.chosen_pass == "pass_c" and Inventory.has_item("forged_pass"), "the pass is in the satchel")

	# 2. The checkpoint lets him through.
	player.global_position = Vector3(0, 0, -42.6)
	await _wait(0.8)
	await _until(func() -> bool: return level.stage == level.Stage.GARRISON and level.layout.barrier_open, 4.0)
	check(level.stage == level.Stage.GARRISON and level.layout.barrier_open, "a good pass lifts the barrier",
			level.stage)
	for t in level.scout_targets():
		check(t.active, "scouting target %s is live in the garrison" % t.name)

	# 3. Cover on the street; none in the yard; staring draws eyes.
	var patrol := level.get_node("StreetPatrol") as Enemy
	patrol.set_physics_process(false)
	var guard := level.get_node("YardGuard") as Enemy
	player.global_position = guard.global_position + Vector3(-11.5, 0, 0)
	player.look_towards(guard.global_position + Vector3(0, 1.6, 6))
	await frames(10)
	check(guard.can_see(player) and guard.suspicion < 0.01, "on the street a seen boy draws no suspicion", guard.suspicion)
	var trucks := level.get_node("Scout/Trucks") as GazeTarget
	player.look_towards(trucks.global_position)
	await _wait(1.0)
	await _until(func() -> bool: return Stealth.staring and guard.suspicion > 0.05, 2.0)
	check(Stealth.staring and guard.suspicion > 0.05, "a boy staring at the trucks draws the guard's eyes",
			[Stealth.staring, guard.suspicion])
	await _until(func() -> bool: return trucks.done and not Stealth.staring, 5.0)
	check(trucks.done and level.scouted.has("Trucks"), "held long enough, the trucks are remembered")
	check(not Stealth.staring, "after remembering he stops staring")
	guard.stand_down()
	guard.global_transform = guard._post  # he went to look; back to his post
	player.global_position = Vector3(12.5, 0, -72.5)
	player.look_towards(guard.global_position + Vector3.UP * 1.5)
	await _wait(0.5)
	await _until(func() -> bool: return Stealth.in_restricted() and guard.suspicion > 0.3, 3.0)
	check(Stealth.in_restricted() and guard.suspicion > 0.3, "in the depot yard the pass is no cover",
			[Stealth.in_restricted(), guard.suspicion, guard.can_see(player)])
	guard.stand_down()
	guard.set_physics_process(false)
	player.global_position = Vector3(0, 0, -95)
	await frames(5)
	check(not Stealth.in_restricted(), "out of the yard, cover again")

	# 4. The round-up at the exit leads to the office.
	var asked: Array[String] = []
	it.question_asked.connect(func(id: String) -> void: asked.append(id))
	player.global_position = Vector3(0, 0, -101.6)
	await _wait(3.6)
	await _until(func() -> bool: return it.running and player.is_seated, 6.0)
	check(level.stage == level.Stage.INTERROGATION and it.running and player.is_seated,
			"detained at the exit, the boy sits before the investigator", level.stage)
	check(absf(it.suspicion - 0.15) < 0.01 and it.pass_valid, "a light start: stopped in a round-up with a good pass",
			it.suspicion)
	check(player.camera.global_position.distance_to(level.get_node("OfficeScene/Seat").global_position) < 0.05,
			"the camera is on the stool")
	check(Perception.illusion_factor > 0.99 and it.shell.crack < 0.01, "the shell is whole at first")
	var clock := level.get_node("Layout/Office/WallClock") as WallClock
	check(BoardFloor.at(get_tree(), (level.get_node("Layout/Office") as Node3D).global_position + Vector3.UP * 0.05) != null,
			"the office floor is boards: the investigator's boots knock")
	await frames(2)
	await _passes()
	check(clock.player != null and clock.player.playing and absf(clock.rate - clock.slow_rate) < 0.02
			and absf(clock.player.pitch_scale - clock.rate) < 0.001,
			"the clock on the wall beats slowly: the nightmare stretches time", clock.rate)
	var simmer := false
	for c in level.get_node("Layout/Office/Kettle").get_children():
		simmer = simmer or (c is AudioStreamPlayer3D and (c as AudioStreamPlayer3D).playing)
	check(simmer, "the kettle simmers on the stove")
	var heard: Array[String] = []
	var on_sound := func(id: String, _p: AudioStreamPlayer3D) -> void: heard.append(id)
	Sfx.played.connect(on_sound)
	await _wait(0.4)
	await _until(func() -> bool: return asked.size() >= 1, 4.0)
	check(asked.size() == 1, "the first question is asked", asked)

	# Looking at the kettle grounds him: the illusion weakens, the shell cracks.
	var kettle := level.get_node("OfficeScene/Details/Kettle") as GazeTarget
	check(Gaze.looks_at(player.camera, inv.global_position + Vector3.UP * 1.6, 0.3, 6.0),
			"seated, he faces the investigator")
	player.look_towards(kettle.global_position)
	check(Gaze.looks_at(player.camera, kettle.global_position, kettle.radius, 6.0), "he can turn his eyes to the kettle")
	await _wait(1.8)
	await _until(func() -> bool: return kettle.done and absf(it.illusion - 0.66) < 0.02 and it.shell.crack > 0.3, 4.0)
	check(kettle.done and absf(it.illusion - 0.66) < 0.02 and it.shell.crack > 0.3,
			"the kettle pulls him out a little: the shell cracks", [it.illusion, it.shell.crack])
	player.look_towards(inv.global_position + Vector3.UP * 1.6)

	# Holding the story: each answer weakens the nightmare.
	it.answer(0)  # from Ольховка
	check(it.outcomes == ["consistent"] and absf(it.illusion - 0.46) < 0.02, "the legend holds", it.illusion)
	await _wait(0.4)
	await _until(func() -> bool: return asked.size() >= 2 and not it._waiting, 4.0)
	it.answer(0)  # to the aunt, for salt
	await _wait(0.4)
	await _until(func() -> bool: return heard.count("typewriter_keys") >= 2, 3.0)
	check(not it.is_revealed, "not yet")
	check(heard.has("kettle_lid") and heard.count("typewriter_keys") == 2,
			"the kettle lid rattles; each answer is typed into the protocol", heard)
	await _until(func() -> bool: return asked.size() >= 3 and not it._waiting, 4.0)
	it.answer(0)  # the elder wrote the pass
	await _wait(0.4)
	await _until(func() -> bool: return asked.size() >= 4 and not it._waiting, 4.0)
	it.answer(0)  # aunt Masha
	check(it.is_revealed and it.shell.is_shattered, "the shell cracks and falls away", it.illusion)
	await _wait(2.8)
	await _until(func() -> bool: return inv.grotesque < 0.01 and Perception.illusion_factor < 0.01 and clock.rate > 0.99, 4.0)
	check(inv.grotesque < 0.01 and Perception.illusion_factor < 0.01, "an ordinary tired man",
			[inv.grotesque, Perception.illusion_factor])
	check(clock.rate > 0.99, "an ordinary clock again", clock.rate)
	Sfx.played.disconnect(on_sound)
	var fallen := true
	for pl in it.shell.plates():
		fallen = fallen and pl.position.y < 0.2
	check(fallen, "the plates lie on the floor")
	check(inv.visual.get_node("Armband").visible, "the red armband stays")
	var released := [false]
	it.released.connect(func() -> void: released[0] = true)
	it.answer(0)
	await _wait(3.8)
	check(released[0] and level.stage == level.Stage.RELEASED and not player.is_seated, "released", level.stage)
	check(player.global_position.distance_to(level.get_node("Spawns/Released").global_position) < 0.5,
			"he stands outside the gate")
	check(not it._ui.visible, "the questions are gone")

	# 5. The forest ends the act; the end card counts what he remembered.
	level.forest_calm_needed = 0.3
	level.next_level = ""
	for e in enemies:
		(e as Enemy).set_physics_process(false)
	var finished := [false]
	level.slice_finished.connect(func() -> void: finished[0] = true)
	player.global_position = Vector3(0, 0.1, -122)
	await _wait(6.0)
	await _until(func() -> bool: return finished[0], 6.0)
	var card := (level.get_node("Overlay/Caption") as Label).text
	check(finished[0] and card.contains("Акта III") and card.contains("1 из 3"), "the end card of Act III", card)
	check(not card.contains("Документов") and not card.contains("\r"),
			"no documents in Act III: no documents line on its card", card)
	level.queue_free()
	await frames(2)


func _test_act3_bad_pass() -> void:
	var level := _act3_level()
	await frames(3)
	var player := level.get_node("Player") as Player
	var it := level.get_node("Interrogation") as Interrogation
	for e in get_tree().get_nodes_in_group("enemies"):
		e.set_physics_process(false)
	it.failed.disconnect(level._on_failed)
	var failed := [false]
	it.failed.connect(func() -> void: failed[0] = true)
	level._on_pass_chosen("pass_a")
	player.global_position = Vector3(0, 0, -42.6)
	await _wait(3.2)
	check(level.stage == level.Stage.INTERROGATION and not level.layout.barrier_open,
			"a square stamp at the checkpoint: arrested", level.stage)
	await _until(func() -> bool: return it.running, 6.0)
	check(absf(it.suspicion - 0.45) < 0.01 and not it.pass_valid, "the interrogation starts under suspicion", it.suspicion)
	var kettle := level.find_child("Kettle", true, false) as Node3D
	check(it.typewriter != null and not Sfx.is_occluded(it.typewriter.global_position)
			and kettle != null and not Sfx.is_occluded(kettle.global_position + Vector3.UP * 0.1),
			"at the table the typewriter and the kettle are in the room with him: no wall muffles them")
	await _wait(0.4)
	await _until(func() -> bool: return it.running and not it._waiting, 4.0)
	it.answer(1)  # from another village
	await _wait(0.4)
	await _until(func() -> bool: return (it.running and not it._waiting) or failed[0], 4.0)
	it.answer(2)  # "just walking"
	await _wait(0.5)
	await _until(func() -> bool: return failed[0], 4.0)
	check(failed[0] and not it.running, "two contradictions end the interrogation")
	check(not it.is_revealed and it.investigator.grotesque > 0.9, "the monster stays a monster")
	check(ACT3_SCRIPT._saved.get("suspicion", 0.0) == 0.45, "the checkpoint remembers where to start again",
			ACT3_SCRIPT._saved)
	# The level's own failure handler (the test cut it off above). Its reload
	# is not run: the tween is the level's and dies with it. A new level must
	# then begin the interrogation again, not the dugout.
	level._on_failed()
	check(level._ending and LevelBase._resume_after_intro,
			"a failed interrogation reloads as a new try, not a new game", LevelBase._resume_after_intro)
	level.queue_free()
	await frames(2)
	var again := _act3_level()
	await _wait(0.6)
	var it2 := again.get_node("Interrogation") as Interrogation
	check(again.stage == again.Stage.INTERROGATION and it2.running and absf(it2.suspicion - 0.45) < 0.01
			and again.chosen_pass == "pass_a",
			"after the failure the interrogation begins again, not the dugout", [again.stage, it2.suspicion])
	it2._finish()
	again.queue_free()
	await frames(2)
	ACT3_SCRIPT._saved = {}
	LevelBase._resume_after_intro = false


func _test_act3_resume() -> void:
	ACT3_SCRIPT._saved = {"suspicion": 0.45, "pass": "pass_a"}
	LevelBase._resume_after_intro = true
	var level := _act3_level()
	await _wait(0.6)
	var it := level.get_node("Interrogation") as Interrogation
	var player := level.get_node("Player") as Player
	check(level.stage == level.Stage.INTERROGATION and it.running and player.is_seated,
			"after a failure the interrogation begins again", level.stage)
	check(level.chosen_pass == "pass_a" and not it.pass_valid, "with the same pass")
	it._finish()
	level.queue_free()
	await frames(2)
	ACT3_SCRIPT._saved = {}
	# A fresh start forgets the checkpoint.
	ACT3_SCRIPT._saved = {"suspicion": 0.45, "pass": "pass_a"}
	var fresh := _act3_level()
	await frames(3)
	check(fresh.stage == fresh.Stage.DUGOUT and ACT3_SCRIPT._saved.is_empty(), "a new game starts in the dugout")
	fresh.queue_free()
	await frames(2)



## Staring is looking now: eyes off the target stop it at once, long before
## the time held on it drains (docs/ARCHITECTURE.md, "Акт III").
func _test_act3_glance() -> void:
	var level := _act3_level()
	await frames(3)
	var player := level.get_node("Player") as Player
	for e in get_tree().get_nodes_in_group("enemies"):
		(e as Enemy).set_physics_process(false)
	level._debug_arg("garrison", "")
	# South-west of the yard, where the playthrough's runner looks at them
	# from (docs/ARCHITECTURE.md, "Проходимость Акта III"): 19 m, in view.
	player.global_position = Vector3(8.5, 0, -64)
	var drums := level.get_node("Scout/Drums") as GazeTarget
	player.look_towards(drums.global_position)
	await _until(func() -> bool: return drums.held > 1.0, 4.0)
	await _passes()
	check(Stealth.staring and drums.looking and not drums.done, "eyes on the drums: staring",
			[Stealth.staring, drums.held, drums.done])
	player.look_towards(player.global_position + Vector3(-6, 1.4, 0))
	# He turned between physics steps; the second physics_frame comes after
	# exactly one step has run with the new look.
	await frames(2)
	check(not Stealth.staring and not drums.looking and drums.held > 0.8,
			"looking away stops the staring in that same physics step", [Stealth.staring, drums.held])
	await _passes()
	player.look_towards(drums.global_position)
	await frames(2)
	check(Stealth.staring, "eyes back on them: staring again in that same step (the time held stays)", drums.held)
	level.queue_free()
	await frames(2)


## The two arrests nothing else drives through: no pass at all at the
## checkpoint, and a real capture by the guard of the depot yard
## (docs/ARCHITECTURE.md, "Акт III": the interrogation from 0.6 and 0.5).
func _test_act3_arrests() -> void:
	var level := _act3_level()
	await frames(3)
	var it := level.get_node("Interrogation") as Interrogation
	for e in get_tree().get_nodes_in_group("enemies"):
		(e as Enemy).set_physics_process(false)
	(level.get_node("Player") as Player).global_position = Vector3(0, 0, -42.6)
	await _wait(3.2)
	check(level.stage == level.Stage.INTERROGATION and not level.layout.barrier_open and level.chosen_pass == "",
			"no pass at all at the checkpoint: arrested", level.stage)
	await _until(func() -> bool: return it.running, 6.0)
	check(it.running and absf(it.suspicion - ACT3_SCRIPT.SUSPICION_NO_PASS) < 0.01 and not it.pass_valid,
			"with no pass the interrogation starts heavier than with a bad one", it.suspicion)
	it._finish()
	level.queue_free()
	await frames(2)
	ACT3_SCRIPT._saved = {}
	# In the depot yard in front of its guard, everyone else still: he sees
	# him, comes and takes him - the whole way through the enemy's own catch.
	level = _act3_level()
	await frames(3)
	it = level.get_node("Interrogation") as Interrogation
	var player := level.get_node("Player") as Player
	var guard := level.get_node("YardGuard") as Enemy
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != guard:
			(e as Enemy).set_physics_process(false)
	level._debug_arg("garrison", "")
	player.global_position = Vector3(12.5, 0, -72.5)
	player.look_towards(guard.global_position + Vector3.UP * 1.5)
	Engine.time_scale = 4.0
	await _until(func() -> bool: return level.stage == level.Stage.INTERROGATION, 15.0)
	Engine.time_scale = 1.0
	check(level.stage == level.Stage.INTERROGATION and player.seized and guard._caught,
			"in the depot yard the guard comes and takes him", [level.stage, guard.state, guard.suspicion])
	await _until(func() -> bool: return it.running, 6.0)
	check(it.running and absf(it.suspicion - ACT3_SCRIPT.SUSPICION_CAUGHT) < 0.01 and it.pass_valid,
			"caught in the yard: the interrogation starts at 0.5, the pass still holds", it.suspicion)
	it._finish()
	level.queue_free()
	await frames(2)
	ACT3_SCRIPT._saved = {}


## The commander tells the boy the cover story the investigator checks
## him against: name, village, the aunt and the salt.
func _test_briefing_legend() -> void:
	var b = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/act3/briefing.json"))
	var told := ""
	for line in (b as Dictionary).get("briefing", []):
		told += str(line).to_lower() + " "
	var legend: Dictionary = Interrogation.load_data().get("legend", {})
	var missing: Array = []
	for key in legend:
		var word := str(legend[key]).split(" ")[0].to_lower()
		var stem := word.left(word.length() - 1) if word.length() > 4 else word
		if not told.contains(stem):
			missing.append([key, stem])
	check(legend.size() == 4 and missing.is_empty(), "the briefing gives the legend: name, village, aunt, salt", missing)

# --- game shell --------------------------------------------------------------------

const MAIN_MENU := preload("res://src/ui/main_menu.tscn")
const EPILOGUE := preload("res://src/scenes/epilogue/epilogue.tscn")
const PLAYER_SCENE := preload("res://src/player/player.tscn")
const DOC_ITEM := preload("res://assets/data/items/doc_arbeitsamt_summons.tres")


func _test_game_state() -> void:
	GameState.reset()
	var docs := GameState.collectible_documents()
	check(docs.size() == 3, "three documents can be found in the game", docs)
	var known := true
	for id in docs:
		known = known and ArchiveDB.has_document(id)
	check(known, "every findable document is in the archive data")
	GameState.act_started(GameState.ACTS[1].scene)
	check(GameState.reached == 2 and GameState.last_act == 1, "starting Act II opens it")
	GameState.act_started(GameState.ACTS[0].scene)
	check(GameState.reached == 2 and GameState.last_act == 0, "going back does not close acts")
	# The run log marks (docs/ARCHITECTURE.md, "Метки в журнале запуска").
	var mark := GameState.log_text("quit", {"year": 2026, "month": 11, "day": 2, "hour": 9, "minute": 5, "second": 7})
	check(mark == "game: quit 2026-11-02 09:05:07", "a run log mark carries the local time", mark)
	Inventory.clear()
	Inventory.add_item(DOC_ITEM)
	Inventory.clear()
	check(GameState.archive == ["act2_arbeitsamt_summons"], "the witness archive outlives the level", GameState.archive)
	GameState.set_setting("mouse_sensitivity", 2.0)
	GameState.load_progress()
	check(GameState.reached == 2 and GameState.archive.size() == 1 and is_equal_approx(GameState.mouse_factor(), 2.0),
			"progress and settings are saved and loaded")
	# Mouse sensitivity reaches the look.
	var p := PLAYER_SCENE.instantiate() as Player
	add_child(p)
	await frames(1)
	p.rotation.y = 0.0
	p._look(Vector2(100, 0))
	var fast := absf(p.rotation.y)
	GameState.set_setting("mouse_sensitivity", 1.0)
	p.rotation.y = 0.0
	p._look(Vector2(100, 0))
	check(absf(fast - 2.0 * absf(p.rotation.y)) < 1e-4, "mouse sensitivity scales the look", [fast, p.rotation.y])
	p.queue_free()
	await frames(2)
	GameState.reset()


func _test_menus() -> void:
	GameState.reset()
	GameState.reached = 2
	GameState.last_act = 1
	var menu := MAIN_MENU.instantiate()
	add_child(menu)
	await frames(2)
	check(menu.continue_button.visible and menu.continue_button.text.contains("Дорога"),
			"«Продолжить» leads to the last act", menu.continue_button.text)
	var open: Array[bool] = []
	for b in menu.act_buttons:
		open.append(not b.disabled)
	check(open == [true, true, false], "only the reached acts can be chosen", open)
	check(menu.archive_button.disabled, "an empty archive cannot be opened")
	menu.queue_free()
	await frames(2)
	GameState.archive.append("act2_arbeitsamt_summons")
	menu = MAIN_MENU.instantiate()
	add_child(menu)
	await frames(2)
	check(not menu.archive_button.disabled, "with a document the archive opens from the menu")
	menu._archive.open_journal()
	check(menu._archive.is_open and menu._archive._journal.item_count == 1, "the menu journal lists the whole archive")
	menu._archive.close()
	check(not get_tree().paused, "closing the archive unpauses")
	menu.queue_free()
	await frames(2)

	# Pause: only in a level, not over another open view.
	check(not PauseMenu.can_open(), "no pause outside a level")
	check(get_tree().scene_changed.is_connected(PauseMenu._on_scene_changed), "the pause hears of every scene that lands")
	PauseMenu.focus_changed(false)
	check(not PauseMenu.is_open and not get_tree().paused, "losing the window focus outside a level does nothing")
	PauseMenu._on_scene_changed()
	check(not PauseMenu.is_open and not get_tree().paused,
			"nor does a scene with no level that lands while another window has the focus (the main menu)")
	var fake := Node3D.new()
	fake.add_to_group("levels")
	add_child(fake)
	check(PauseMenu.can_open(), "a level can be paused")
	PauseMenu._on_scene_changed()
	check(PauseMenu.is_open and get_tree().paused, "a level that lands after the focus went during its load is paused")
	PauseMenu.close()
	PauseMenu.focus_changed(true)
	PauseMenu._on_scene_changed()
	check(not PauseMenu.is_open and not get_tree().paused, "with the focus back, a level that lands is not paused")
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	Flicker.forget_swaps()  # one key at a time, not mashed (Flicker.SWAP_GAP)
	PauseMenu._unhandled_input(esc)
	check(PauseMenu.is_open and get_tree().paused and PauseMenu._root.visible, "Esc pauses the level")
	PauseMenu._show_settings()
	PauseMenu._unhandled_input(esc)
	check(PauseMenu.is_open and PauseMenu._list.visible, "Esc in the settings goes back to the pause list")
	Flicker.forget_swaps()
	PauseMenu._unhandled_input(esc)
	check(not PauseMenu.is_open and not get_tree().paused, "Esc again continues")
	PauseMenu.focus_changed(false)
	check(PauseMenu.is_open and get_tree().paused and PauseMenu._root.visible, "losing the window focus pauses the level")
	PauseMenu.focus_changed(false)
	check(PauseMenu.is_open and PauseMenu._list.visible, "losing it again leaves the pause as it is")
	PauseMenu.close()
	PauseMenu.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not PauseMenu.is_open and not get_tree().paused, "no focus pause in a headless run or Movie Maker frames")
	get_tree().paused = true
	check(not PauseMenu.can_open(), "no pause over the archive or the pass check")
	PauseMenu.focus_changed(false)
	check(not PauseMenu.is_open, "nor does losing the focus open it there")
	get_tree().paused = false
	PauseMenu.focus_changed(true)
	fake.queue_free()
	await frames(2)

	# Epilogue: the game is finished, the archive is counted.
	var ep := EPILOGUE.instantiate()
	add_child(ep)
	await frames(2)
	check(GameState.finished and GameState.reached == 3, "the epilogue finishes the game")
	ep.show_summary()
	var texts: Array[String] = []
	for c in ep._summary.get_children():
		if c is Label:
			texts.append((c as Label).text)
	check(texts.size() == 2 and texts[0].contains("1 из 3"), "the epilogue counts the witness archive", texts)
	check(ep._to_menu != null and ep._to_menu.has_focus(), "and offers the way back to the menu")
	ep.queue_free()
	await frames(2)
	GameState.reset()


# --- patrol rounds ------------------------------------------------------------

## Every patrol walks its whole round and comes back, in all three acts. The
## navmesh lies a little above the ground, so a path point is never within
## reach in 3D: the Act II village policeman once paced on one spot at P1.
func _test_patrol_rounds() -> void:
	for scene: PackedScene in [LEVEL, ACT2, ACT3]:
		await _patrol_round_in(scene)


func _patrol_round_in(scene: PackedScene) -> void:
	PanicSystem.reset()
	Perception.reset()
	var level := scene.instantiate()
	level.play_intro = false
	add_child(level)
	level._ending = true
	var act := String(level.name)
	var nav := level.get_node("Navigation")
	var t0 := Time.get_ticks_msec()
	while nav is RuntimeNavRegion and not (nav as RuntimeNavRegion).is_baked \
			and Time.get_ticks_msec() - t0 < 15000:
		await get_tree().physics_frame
	# The boy is out of play: far off and still, so nobody turns to him.
	var player := level.get_node("Player") as Player
	player.set_physics_process(false)
	player.get_node("BreathControl").set_physics_process(false)
	player.get_node("PhantomSounds").set_process(false)
	player.global_position = Vector3(400.0, 0.0, 400.0)
	var walkers: Array[Enemy] = []
	var need := 0.0
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e is Dog or e.hold_position or e.patrol_route == null or not level.is_ancestor_of(e):
			continue
		walkers.append(e)
		var n := e.patrol_route.get_child_count()
		var round := 0.0
		for i in n:
			var a := (e.patrol_route.get_child(i) as Node3D).global_position
			var b := (e.patrol_route.get_child((i + 1) % n) as Node3D).global_position
			round += Vector2(b.x - a.x, b.z - a.z).length()
		need = maxf(need, round / e.walk_speed + n * e.wait_at_point)
	check(not walkers.is_empty(), "%s has a patrol on a round" % act)
	var steps := {}
	var last := {}
	var anchor := {}
	var still := {}
	var stuck := {}
	for e in walkers:
		steps[e] = 0
		last[e] = e._route_idx
		anchor[e] = e.global_position
		still[e] = 0.0
	Engine.time_scale = 4.0
	var t := 0.0
	var limit := need * 1.6 + 10.0
	while t < limit:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		var done := true
		for e in walkers:
			if e._route_idx != last[e]:
				steps[e] += 1
				last[e] = e._route_idx
			if e._wait > 0.0 or e.state != Enemy.State.PATROL \
					or (e.global_position - (anchor[e] as Vector3)).length() > 0.3:
				anchor[e] = e.global_position
				still[e] = 0.0
			else:
				still[e] += dt
				if still[e] > 3.0 and not stuck.has(e):
					stuck[e] = "%.1f %.1f %.1f at %.0f s" % [e.global_position.x,
							e.global_position.y, e.global_position.z, t]
			if steps[e] < e.patrol_route.get_child_count():
				done = false
		if done:
			break
	Engine.time_scale = 1.0
	for e in walkers:
		var n := e.patrol_route.get_child_count()
		check(steps[e] >= n and e.state == Enemy.State.PATROL,
				"%s: %s walks his whole round and comes back" % [act, e.name],
				"%d of %d points in %.0f s, %s" % [steps[e], n, t, Enemy.State.keys()[e.state]])
		check(not stuck.has(e), "%s: %s never paces on one spot" % [act, e.name], stuck.get(e, ""))
	level.queue_free()
	await frames(3)


# --- «Вторжение памяти» (docs/ARCHITECTURE.md) --------------------------------

const ECHO_SCENE := preload("res://src/scenes/test/trauma_echo_test.tscn")


func _test_trauma_echo() -> void:
	var hatch := CELLAR.instantiate() as HideSpot
	check(hatch.slits == HideSpot.Slits.HORIZONTAL and not TraumaEcho.CELLAR_VERTICAL
			and is_equal_approx(hatch.slit_width, TraumaEcho.CELLAR_SLIT_WIDTH)
			and hatch.slit_count == TraumaEcho.CELLAR_SLIT_COUNT
			and is_equal_approx(hatch.muffle_hz, TraumaEcho.CELLAR_MUFFLE_HZ)
			and is_equal_approx(hatch.muffle_db, TraumaEcho.CELLAR_MUFFLE_DB),
			"the echo's gaps and muffled world are those of the Act I cellar",
			[hatch.slits, hatch.slit_width, hatch.slit_count, hatch.muffle_hz, hatch.muffle_db])
	hatch.free()
	var with_echo := []
	for path in ["res://src/scenes/act1_village/act1_village.tscn", "res://src/scenes/interlude_night/night_dream.tscn",
			"res://src/scenes/act2_road/act2_road.tscn", "res://src/scenes/act3_garrison/act3_garrison.tscn",
			"res://src/scenes/epilogue/epilogue.tscn"]:
		if FileAccess.get_file_as_string(path).contains("res://src/story/trauma_echo.gd"):
			with_echo.append(path.get_file())
	check(with_echo == ["act2_road.tscn", "act3_garrison.tscn"],
			"the echo is on the road - Acts II and III; not in Act I, the dream or the epilogue", with_echo)
	var defaults := TraumaEcho.new()
	var numbers := [defaults.threshold, defaults.near_radius, defaults.dog_beyond_smell, defaults.relief_margin,
			defaults.still_speed, defaults.light_widen, defaults.light_clear, defaults.beam_panic, defaults.beam_panic_cap,
			defaults.duration, defaults.sound_lead, defaults.cooldown, defaults.max_per_level, defaults.panic_spike,
			defaults.flinch_strength]
	defaults.free()
	check(numbers == [0.35, 3.0, 1.5, 0.3, 0.3, 1.4, 2.0, 0.2, 0.45, 0.7, 0.1, 60.0, 3, 0.12, 0.8],
			"the echo's numbers are those of docs/ARCHITECTURE.md", numbers)

	# Its memory on a real level: a fresh start forgets; a reload after capture
	# keeps the used sources and the 60 s pause; a reload into another level
	# forgets.
	TraumaEcho.forget_all()
	TraumaEcho._used["/root/Elsewhere/Enemy"] = true
	var lv := _act2_instance(false)
	await frames(2)
	var fresh_start := TraumaEcho.used_count() == 0 and TraumaEcho._used_scene == ACT2.resource_path
	lv.queue_free()
	await frames(2)
	TraumaEcho._used["/root/Elsewhere/Enemy"] = true
	TraumaEcho._cool = 30.0
	lv = _act2_instance(true)
	await frames(2)
	var reload_keeps := TraumaEcho.used_count() == 1 and TraumaEcho._cool > 29.0
	lv.queue_free()
	await frames(2)
	TraumaEcho._used_scene = "res://src/scenes/act3_garrison/act3_garrison.tscn"
	lv = _act2_instance(true)
	await frames(2)
	var other_level := TraumaEcho.used_count() == 0 and is_zero_approx(TraumaEcho._cool)
	lv.queue_free()
	await frames(2)
	LevelBase._resume_after_intro = false
	check(fresh_start and reload_keeps and other_level,
			"a fresh start of the level forgets the echoes; a reload after capture keeps them and the pause; another level forgets",
			[fresh_start, reload_keeps, other_level])
	LevelBase._resume_after_intro = true
	PauseMenu.open()
	PauseMenu.close()
	var close_keeps := LevelBase._resume_after_intro
	PauseMenu.open()
	PauseMenu._leave()
	check(close_keeps and not LevelBase._resume_after_intro and not get_tree().paused,
			"on the black after a capture «Продолжить» keeps the reload at the checkpoint; «Начать акт заново» and «Главное меню» drop it",
			close_keeps)
	LevelBase._resume_after_intro = false
	var act3 := (load("res://src/scenes/act3_garrison/act3_garrison.gd") as GDScript).new() as LevelBase
	var allowed := []
	for stage in 6:  # DUGOUT, ROAD, CHECKPOINT, GARRISON, INTERROGATION, RELEASED
		act3.set("stage", stage)
		allowed.append(act3.echo_allowed())
	act3.set("stage", 1)
	act3._ending = true
	allowed.append(act3.echo_allowed())
	act3.free()
	check(allowed == [false, true, false, true, false, true, false],
			"Act III lets a memory in on the road, in the garrison and after release; not in the dugout, at the barrier, detained, questioned or as the level ends",
			allowed)

	TraumaEcho.forget_all()
	var scene := ECHO_SCENE.instantiate()
	add_child(scene)
	await frames(3)
	var player := scene.get_node("Player") as Player
	var patrol := scene.get_node("Patrol") as Enemy
	var tower := scene.get_node("Tower") as SearchlightTower
	var echo := scene.get_node("TraumaEcho") as TraumaEcho
	for n: Node in [player, patrol, tower, echo, player.get_node("BreathControl")]:
		n.set_physics_process(false)
	var dt := 1.0 / 60.0
	var spot_a := Vector3(8, 0, -1.1)
	player.global_position = spot_a
	player.velocity = Vector3.ZERO
	player.is_crouching = true
	patrol.suspicion = 0.0
	patrol.state = Enemy.State.PATROL
	Sfx.set_muffle(Sfx.OPEN_AIR, 0.0, 0.0)
	var overlay := echo.get_node("EchoOverlay") as CanvasLayer
	check(overlay.layer == TraumaEcho.OVERLAY_LAYER
			and TraumaEcho.OVERLAY_LAYER > (player.get_node("HideOverlay") as CanvasLayer).layer
			and TraumaEcho.OVERLAY_LAYER < 10 and not echo.is_showing(),
			"the cellar is drawn on its own layer, over the hiding-spot slits and under the archive, hidden at rest")
	check(TraumaEcho.SLITS_SHADER.code.contains("uniform float band = -1.0;")
			and player.hide_overlay.material.get("shader_parameter/band") == null,
			"the torch spot is off by default: the hiding spots' slits are as they were")
	var black := echo.get_node_or_null("EchoOverlay/Black") as ColorRect
	var mat := echo.material()
	check(black != null and black.color == Color.BLACK and black.get_index() < echo.get_node("EchoOverlay/Slits").get_index()
			and mat.get_shader_parameter("vertical") == TraumaEcho.CELLAR_VERTICAL
			and is_equal_approx(float(mat.get_shader_parameter("slit_width")), TraumaEcho.CELLAR_SLIT_WIDTH)
			and is_equal_approx(float(mat.get_shader_parameter("slit_count")), TraumaEcho.CELLAR_SLIT_COUNT),
			"under the cellar's gaps the present is blacked out", black)

	var starts: Array = []
	echo.started.connect(func(c: StringName, s: Node) -> void: starts.append([c, s]))
	# The polizei walks by on the far side of the stove: x 4 -> 12 along z
	# (z 1.15: 2.25 m from him at the closest, x = 8). Returns his x when the
	# echo started.
	var cur := [patrol]  # lambdas keep the value they were made with: the enemy goes in a box
	var pass_by := func(panic: float, z: float = 1.15) -> Variant:
		var at: Variant = null
		for i in 81:
			var x := 4.0 + i * 0.1
			cur[0].global_position = Vector3(x, 0, z)
			PanicSystem.level = panic
			var was := echo.is_running()
			echo.step(dt)
			if not was and echo.is_running() and at == null:
				at = x
		for i in 60:
			echo.step(dt)
		return at
	var fresh := func() -> void:
		TraumaEcho.forget_all()
		echo._approach.clear()
		echo._beam.clear()
		starts.clear()

	fresh.call()
	check(pass_by.call(echo.threshold - 0.01) == null and starts.is_empty(),
			"an enemy close by: below the panic threshold no echo")
	var second: Variant = pass_by.call(echo.threshold)
	check(second != null, "a pass that gave no echo does not use the enemy up: the next pass can")
	fresh.call()
	var at: Variant = pass_by.call(echo.threshold)
	var relief_x := 8.0 + sqrt(pow(2.25 + echo.relief_margin, 2.0) - 2.25 * 2.25)
	check(at != null and absf(float(at) - relief_x) < 0.15 and starts.size() == 1
			and starts[0][0] == TraumaEcho.NEAR and starts[0][1] == patrol,
			"at the threshold: the echo comes as he walks away, 0.3 m past his closest - not on the way in",
			[at, relief_x, starts])
	check(absf(TraumaEcho._cool + TraumaEcho._since - echo.cooldown) < 0.001 and TraumaEcho._since < 1.5,
			"the 60 s pause counts from the end of the echo", [TraumaEcho._cool, TraumaEcho._since])
	TraumaEcho._cool = 0.0
	check(TraumaEcho.used_count() == 1 and pass_by.call(0.9) == null,
			"the same enemy walking by again: no second echo on this level")
	# A reload: a new enemy node at the same place in the tree is the same one;
	# a new echo node remembers him too.
	var twin := patrol.duplicate() as Enemy
	scene.remove_child(patrol)
	patrol.free()
	twin.name = "Patrol"
	scene.add_child(twin)
	patrol = twin
	cur[0] = twin
	patrol.set_physics_process(false)
	patrol.suspicion = 0.0
	patrol.state = Enemy.State.PATROL
	TraumaEcho._cool = 0.0
	check(pass_by.call(0.9) == null, "reloaded after capture: that enemy (a new node in his place) still has had his echo")
	var other := TraumaEcho.new()
	scene.add_child(other)
	other.set_physics_process(false)
	var other_starts := [0]
	other.started.connect(func(_c: StringName, _s: Node) -> void: other_starts[0] += 1)
	for i in 81:
		patrol.global_position = Vector3(4.0 + i * 0.1, 0, 1.15)
		PanicSystem.level = 0.9
		other.step(dt)
	check(other_starts[0] == 0, "and a new echo node knows it")
	other.free()
	var patrol2 := patrol.duplicate() as Enemy
	patrol2.name = "Patrol2"
	scene.add_child(patrol2)
	patrol2.set_physics_process(false)
	patrol2.global_position = Vector3(30, 0, 30)
	patrol.global_position = Vector3(30, 0, 30)
	var by_second: Variant = null
	for i in 81:
		patrol2.global_position = Vector3(4.0 + i * 0.1, 0, 1.15)
		PanicSystem.level = 0.9
		var was := echo.is_running()
		echo.step(dt)
		if not was and echo.is_running():
			by_second = patrol2.global_position.x
	for i in 60:
		echo.step(dt)
	patrol2.free()
	check(by_second != null and TraumaEcho.used_count() == 2, "another enemy on the same level has his own echo", by_second)
	var stub := LevelBase.new()
	stub.resumed = true
	TraumaEcho._used_scene = ""
	echo._on_level_ready(stub)
	var kept := TraumaEcho.used_count() == 2
	stub.resumed = false
	echo._on_level_ready(stub)
	check(kept and TraumaEcho.used_count() == 0,
			"the memory of echoes survives a reload at a checkpoint, a fresh start of the level clears it")
	stub.free()

	# One pass, one judgement: upright at the moment of relief, crouched a
	# step later - nothing; a new pass after he has gone clear is judged anew.
	fresh.call()
	player.is_crouching = false
	var late: Variant = null
	for i in 81:
		var x := 4.0 + i * 0.1
		patrol.global_position = Vector3(x, 0, 1.15)
		if x > relief_x + 0.15:  # the relief itself falls at 9.2-9.3
			player.is_crouching = true
		PanicSystem.level = 0.9
		echo.step(dt)
		if echo.is_running() and late == null:
			late = x
	for i in 60:
		echo.step(dt)
	var back: Variant = null
	for i in 81:
		var x := 12.0 - i * 0.1
		patrol.global_position = Vector3(x, 0, 1.15)
		PanicSystem.level = 0.9
		echo.step(dt)
		if echo.is_running() and back == null:
			back = x
	for i in 60:
		echo.step(dt)
	check(late == null and back != null, "each pass is judged once, at its relief; the next pass anew", [late, back])
	# A sentry standing still, the boy crawling off: the danger has not gone, he has.
	fresh.call()
	patrol.global_position = Vector3(8, 0, 1.15)
	for i in 41:
		player.global_position = Vector3(8, 0, -1.1 - i * 0.05)
		PanicSystem.level = 0.9
		echo.step(dt)
	for i in 60:
		echo.step(dt)
	player.global_position = spot_a
	check(starts.is_empty(), "the boy crawls off from a sentry who stands: no «пронесло»")
	fresh.call()
	check(pass_by.call(0.9, -1.1 + echo.near_radius + 0.4) == null, "a man passing 3.4 m off is not close")
	fresh.call()
	check(pass_by.call(0.9, -1.1 + echo.near_radius - 0.1) != null, "a man passing 2.9 m off is")
	var dog := (load("res://src/ai/dog.tscn") as PackedScene).instantiate() as Dog
	check(is_equal_approx(echo.radius_for(dog), dog.smell_radius + echo.dog_beyond_smell)
			and is_equal_approx(echo.radius_for(patrol), echo.near_radius),
			"a dog's pass counts beyond its nose: close, and it did not smell him", [echo.radius_for(dog), dog.smell_radius])
	scene.add_child(dog)
	dog.set_physics_process(false)
	dog.state = Enemy.State.PATROL
	dog.suspicion = 0.0
	patrol.global_position = Vector3(30, 0, 30)
	# Its own nose works as it walks: [x when the echo started, top suspicion].
	var dog_pass := func(z: float) -> Array:
		TraumaEcho.forget_all()
		echo._approach.clear()
		dog.suspicion = 0.0
		var r := [null, 0.0]
		for i in 81:
			dog.global_position = Vector3(4.0 + i * 0.1, 0, z)
			dog.smell(dt)
			r[1] = maxf(float(r[1]), dog.suspicion)
			PanicSystem.level = 0.9
			var was := echo.is_running()
			echo.step(dt)
			if not was and echo.is_running() and r[0] == null:
				r[0] = dog.global_position.x
		for i in 60:
			echo.step(dt)
		return r
	var dog_close: Array = dog_pass.call(-1.1 + dog.smell_radius + 0.7)
	var dog_far: Array = dog_pass.call(-1.1 + echo.radius_for(dog) + 0.4)
	var dog_nose: Array = dog_pass.call(-1.1 + dog.smell_radius - 0.5)
	dog.free()
	starts.clear()
	check(dog_close[0] != null and is_zero_approx(float(dog_close[1])) and dog_far[0] == null
			and dog_nose[0] == null and float(dog_nose[1]) >= Enemy.SUSPICIOUS_AT,
			"a dog walking by 5.2 m off (outside its 4.5 m nose, it smells nothing) has passed him close; 6.4 m off it has not; 4 m off it smells him: no echo",
			[dog_close, dog_far, dog_nose])

	fresh.call()
	player.is_crouching = false
	check(pass_by.call(0.9) == null, "upright he is no hiding boy: no echo")
	player.is_crouching = true
	fresh.call()
	player.velocity = Vector3(0.4, 0, 0)
	var creeping: Variant = pass_by.call(0.9)
	fresh.call()
	player.velocity = Vector3(0.25, 0, 0)
	var nearly_still: Variant = pass_by.call(0.9)
	player.velocity = Vector3.ZERO
	fresh.call()
	player.crawling = true  # WireGap moves him under the wire with his velocity at 0
	var crawling: Variant = pass_by.call(0.9)
	player.crawling = false
	check(creeping == null and nearly_still != null and crawling == null,
			"he has to keep still (0.3 m/s at most), crouched; crawling under the wire he is moving, whatever his velocity says",
			[creeping, nearly_still, crawling])
	fresh.call()
	patrol.passive = true
	check(pass_by.call(0.9) == null, "a passive figure (the investigator, the dream's figure) does not count")
	patrol.passive = false
	var states := {}
	for st in [Enemy.State.SUSPICIOUS, Enemy.State.SEARCH, Enemy.State.ALERT]:
		fresh.call()
		patrol.state = st
		states[st] = pass_by.call(0.9)
	patrol.state = Enemy.State.PATROL
	fresh.call()
	patrol.suspicion = Enemy.SUSPICIOUS_AT
	var worried: Variant = pass_by.call(0.9)
	fresh.call()
	patrol.suspicion = Enemy.SUSPICIOUS_AT - 0.01
	var calm: Variant = pass_by.call(0.9)
	patrol.suspicion = 0.0
	check(states.values() == [null, null, null] and worried == null and calm != null,
			"only an enemy on his round and unworried has passed him by: not one who is searching, suspicious or on the alert, even unseen",
			[states, worried, calm])

	fresh.call()
	check(echo.can_start(), "at rest nothing keeps the echo from starting")
	var blocked := {}
	Perception.sepia = 0.5
	blocked["sepia"] = echo.can_start()
	Perception.sepia = 0.0
	Perception.enter_safe_zone()
	blocked["safe zone"] = echo.can_start()
	Perception.exit_safe_zone()
	Perception.push_suppression()
	blocked["document"] = echo.can_start()
	Perception.pop_suppression()
	for flag in ["is_hidden", "is_seated", "seized", "crawling"]:
		player.set(flag, true)
		blocked[flag] = echo.can_start()
		player.set(flag, false)
	player.wound.binding = 1.0
	blocked["binding"] = echo.can_start()
	player.wound.binding = 0.0
	player.satchel.is_open = true
	blocked["satchel"] = echo.can_start()
	player.satchel.is_open = false
	get_tree().paused = true
	blocked["pause"] = echo.can_start()
	get_tree().paused = false
	for st in [Enemy.State.SUSPICIOUS, Enemy.State.SEARCH, Enemy.State.ALERT]:
		patrol.state = st
		blocked[st] = echo.can_start()
	patrol.state = Enemy.State.PATROL
	var ending := LevelBase.new()
	ending._ending = true
	echo._level = ending
	blocked["level ending"] = echo.can_start()
	echo._level = null
	ending.free()
	tower._lock = 1.0
	blocked["beam held after an alarm"] = echo.can_start()
	tower._lock = 0.0
	# Lit now, and the beam sweeps on fast and far: only the light itself says no.
	player.global_position = Vector3(-16, 0, -4)
	tower.sweep_amplitude = 120.0
	tower.sweep_period = 40.0
	tower._t = 0.0
	tower._pivot.rotation.y = 0.0
	var lit_there := tower.in_beam(player) and not echo.light_coming(player)
	blocked["in the beam"] = echo.can_start()
	tower.sweep_amplitude = 20.0
	tower.sweep_period = 14.0
	player.global_position = spot_a
	check(lit_there and not blocked.values().has(true) and echo.can_start(),
			"no echo in sepia, a safe zone, over a document, hidden, seated, seized, under the wire, binding the wound, with the satchel open, on pause, with an enemy searching, suspicious or alert, as the level ends or in the beam",
			blocked)

	# The cut itself.
	fresh.call()
	PanicSystem.level = 0.3
	var clock := [0]
	var sounds: Array = []
	var on_sound := func(id: String, p: AudioStreamPlayer3D) -> void:
		sounds.append([id, p.global_position.y, clock[0]])
	Sfx.played.connect(on_sound)
	var noises := [0]
	var on_noise := func(_pos: Vector3, _loud: float, _src: Node) -> void:
		noises[0] += 1
	Stealth.noise_emitted.connect(on_noise)
	echo.start(TraumaEcho.DEBUG)
	for i in 3:
		echo.step(dt)
	var lead_hz := Sfx.muffle_hz
	var lead_db := Sfx.muffle_db
	check(not echo.is_showing() and lead_hz < Sfx.OPEN_AIR - 1.0 and lead_hz > TraumaEcho.CELLAR_MUFFLE_HZ
			and lead_db < 0.0 and lead_db > TraumaEcho.CELLAR_MUFFLE_DB,
			"hearing goes first: the world fades towards the cellar before the picture cuts", [lead_hz, lead_db])
	var lead_steps := 3
	while not echo.is_showing() and lead_steps < 30:
		echo.step(dt)
		lead_steps += 1
	check(absf(lead_steps * dt - echo.sound_lead) <= dt * 1.01
			and is_equal_approx(Sfx.muffle_hz, TraumaEcho.CELLAR_MUFFLE_HZ)
			and is_equal_approx(Sfx.muffle_db, TraumaEcho.CELLAR_MUFFLE_DB),
			"after 0.1 s the cut: the world sounds as from under the cellar boards", [lead_steps, Sfx.muffle_hz, Sfx.muffle_db])
	var shown := 0
	var bands := []
	var dust_times := []
	var mid := {}
	while echo.is_showing() and shown < 200:
		clock[0] = shown + 1
		echo.step(dt)
		shown += 1
		var m := echo.material()
		if shown in [int(echo.duration * 0.25 / dt), int(echo.duration * 0.5 / dt), int(echo.duration * 0.75 / dt)]:
			bands.append(float(m.get_shader_parameter("band")))
			dust_times.append(float(m.get_shader_parameter("dust_time")))
		if shown == int(echo.duration * 0.5 / dt):
			mid = {"leak": m.get_shader_parameter("leak"), "dust": m.get_shader_parameter("dust")}
	check(absf(shown * dt - echo.duration) <= dt * 1.01, "the cellar is on the screen 0.7 s", shown * dt)
	check(bands.size() == 3 and bands[0] < bands[1] and bands[1] < bands[2] and bands[1] > 0.3 and bands[1] < 0.7
			and dust_times[0] < dust_times[1] and dust_times[1] < dust_times[2]
			and is_equal_approx(float(mid.get("leak", 0.0)), TraumaEcho.LEAK) and float(mid.get("dust", 0.0)) > 0.0,
			"the torch spot runs along the gaps, dust is falling", [bands, dust_times, mid])
	var boots := 0
	var creaks := 0
	var above := true
	var on_time := sounds.size() == TraumaEcho.SOUNDS.size()
	for i in sounds.size():
		var s: Array = sounds[i]
		boots += 1 if s[0] == "step_boot_board" else 0
		creaks += 1 if s[0] == "floor_creak" else 0
		above = above and float(s[1]) > player.camera.global_position.y + 1.0
		if on_time:
			on_time = s[0] == TraumaEcho.SOUNDS[i][1] and absf(int(s[2]) * dt - float(TraumaEcho.SOUNDS[i][0])) <= dt * 1.5
	check(boots == 2 and creaks == 1 and above and on_time, "two boots and a creak of the boards over his head, each in its time", sounds)
	check(noises[0] == 0, "the memory makes no noise for the enemies", noises[0])
	var spent: Array = []
	for c in echo.get_children():
		if c is AudioStreamPlayer3D:
			spent.append(c.is_queued_for_deletion() and not (c as AudioStreamPlayer3D).playing)
	check(is_equal_approx(Sfx.muffle_hz, Sfx.OPEN_AIR) and is_equal_approx(Sfx.muffle_db, 0.0)
			and is_equal_approx(PanicSystem.level, 0.3 + echo.panic_spike) and not spent.has(false),
			"the same hard cut back: hearing back at once, the remembered sounds gone, panic +0.12 once",
			[Sfx.muffle_hz, PanicSystem.level, spent])
	var dip := [0.0]
	await _until(func() -> bool:
		dip[0] = minf(dip[0], player._flinch_dip)
		return false, 0.3)
	check(absf(dip[0] + 0.05 * echo.flinch_strength) < 0.006, "and he starts (a flinch of 0.8)", dip[0])
	Sfx.played.disconnect(on_sound)
	Stealth.noise_emitted.disconnect(on_noise)

	# What cuts it short: then it is just gone - no start, no jolt.
	var cut_short := func(what: String) -> Array:
		TraumaEcho._cool = 0.0
		Sfx.set_muffle(Sfx.OPEN_AIR, 0.0, 0.0)
		PanicSystem.level = 0.3
		if player._flinch_tween != null:
			player._flinch_tween.kill()  # a start shows on the next frame: its tween is what counts
		player._flinch_dip = 0.0
		echo.start(TraumaEcho.DEBUG)
		for i in (3 if what == "seized in the lead" else 12):
			echo.step(dt)
		match what:
			"a step":
				player.velocity = Vector3(1.1, 0, 0)
			"seized in the lead":
				player.seized = true
			"seated":
				player.is_seated = true
			"under the wire":
				player.crawling = true
			"the bandage":
				player.wound.binding = 1.0
			"the satchel":
				player.satchel.is_open = true
			"a warm memory":
				Perception.sepia = 0.5
			"the level":
				var lb := LevelBase.new()
				lb._ending = true
				echo._level = lb
		var ever_shown := false
		for i in 30:
			echo.step(dt)
			ever_shown = ever_shown or echo.is_showing()
		var r := [echo.is_running(), ever_shown, is_equal_approx(Sfx.muffle_hz, Sfx.OPEN_AIR),
				is_equal_approx(PanicSystem.level, 0.3), is_zero_approx(player._flinch_dip) and not (player._flinch_tween != null and player._flinch_tween.is_valid())]
		player.velocity = Vector3.ZERO
		player.seized = false
		player.is_seated = false
		player.crawling = false
		player.wound.binding = 0.0
		player.satchel.is_open = false
		Perception.sepia = 0.0
		if echo._level != null:
			echo._level.free()
			echo._level = null
		return r
	var shorts := {}
	for what in ["a step", "seized in the lead", "seated", "under the wire", "the bandage", "the satchel", "a warm memory", "the level"]:
		shorts[what] = cut_short.call(what)
	check(shorts.values().all(func(r: Array) -> bool: return r == [false, false, true, true, true]),
			"a step taken, seized (even in the 0.1 s before the cut), seated, crawling under the wire, binding the wound, the satchel opened, a warm memory or the level ending: the echo is gone that frame, hearing back, no start, no jolt",
			shorts)
	# Someone else's muffle is never overwritten.
	TraumaEcho._cool = 0.0
	echo.start(TraumaEcho.DEBUG)
	for i in 12:
		echo.step(dt)
	Sfx.set_muffle(180.0, -40.0, 0.0)  # LevelBase.cut_to_black
	for i in 60:
		echo.step(dt)
	check(not echo.is_running() and is_equal_approx(Sfx.muffle_hz, 180.0) and is_equal_approx(Sfx.muffle_db, -40.0),
			"capture's black in the middle: the echo leaves its muffle alone", [Sfx.muffle_hz, Sfx.muffle_db])
	TraumaEcho._cool = 0.0
	Sfx.set_muffle(5000.0, -2.0, 0.0)
	echo.start(TraumaEcho.DEBUG)
	for i in 90:
		echo.step(dt)
	check(not echo.is_running() and is_equal_approx(Sfx.muffle_hz, 5000.0) and is_equal_approx(Sfx.muffle_db, -2.0),
			"hearing goes back to what it was before the echo, not to open air", [Sfx.muffle_hz, Sfx.muffle_db])
	Sfx.set_muffle(Sfx.OPEN_AIR, 0.0, 0.0)
	TraumaEcho._cool = 0.0
	echo.start(TraumaEcho.DEBUG)
	for i in 12:
		echo.step(dt)
	player.is_hidden = true  # into a hiding spot that sounds like the cellar: 650 Hz, -5 dB
	echo.step(dt)
	check(not echo.is_running() and is_equal_approx(Sfx.muffle_hz, TraumaEcho.CELLAR_MUFFLE_HZ),
			"hidden in the middle: the echo ends and leaves the hiding spot's muffle", Sfx.muffle_hz)
	player.is_hidden = false
	Sfx.set_muffle(Sfx.OPEN_AIR, 0.0, 0.0)
	var loose := TraumaEcho.new()
	scene.add_child(loose)
	loose.set_physics_process(false)
	loose.start(TraumaEcho.DEBUG)
	for i in 12:
		loose.step(dt)
	var deaf := Sfx.is_muffled()
	loose.free()
	check(deaf and is_equal_approx(Sfx.muffle_hz, Sfx.OPEN_AIR), "freed in the middle, the echo gives the hearing back")
	# The body stays in the present: under the cellar his legs are his own,
	# and a step ends it.
	TraumaEcho._cool = 0.0
	PanicSystem.level = 0.3
	if player._flinch_tween != null:
		player._flinch_tween.kill()  # the start after the last full echo
	player._flinch_dip = 0.0
	player.global_position = Vector3(0, 0, 10)
	player.velocity = Vector3.ZERO
	player.set_physics_process(true)
	echo.start(TraumaEcho.DEBUG)
	for i in 12:
		echo.step(dt)
	var shown_then := echo.is_showing()
	var from := player.global_position
	Input.action_press(&"move_forward")
	await frames(3)
	Input.action_release(&"move_forward")
	player.set_physics_process(false)
	var walked := Vector2(player.global_position.x - from.x, player.global_position.z - from.z).length()
	echo.step(dt)
	check(shown_then and walked > 0.02 and not echo.is_running() and not echo.is_showing()
			and not (player._flinch_tween != null and player._flinch_tween.is_valid()) and PanicSystem.level <= 0.3 + 0.001,
			"the body stays in the present: under the cellar he can step off, and the step ends it, no jolt",
			[shown_then, walked, echo.is_running(), player._flinch_dip, PanicSystem.level])
	player.velocity = Vector3.ZERO
	player._update_crouch(true)
	player.global_position = spot_a
	patrol.suspicion = 0.0
	patrol.state = Enemy.State.PATROL

	# While it runs and a little after: no warm memory, no scouting by gaze.
	fresh.call()
	player.global_position = Vector3(0, 0, 10)
	player.look_towards(player.camera.global_position + Vector3(0, 0, -5))
	var focus := Marker3D.new()
	scene.add_child(focus)
	focus.global_position = player.camera.global_position + Vector3(0, 0, -5)
	var flash := MemoryFlash.new()
	flash.focus = focus
	scene.add_child(flash)
	flash.set_physics_process(false)
	var gaze := GazeTarget.new()
	scene.add_child(gaze)
	gaze.set_physics_process(false)
	gaze.global_position = player.camera.global_position + Vector3(0, 0, -3)
	PanicSystem.level = 0.3
	gaze._physics_process(dt)
	var idle := [flash._wants_to_remember(), gaze.looking]
	TraumaEcho._cool = 0.0
	echo.start(TraumaEcho.DEBUG)
	for i in 10:
		echo.step(dt)
	var held := gaze.held
	gaze._physics_process(dt)
	var during := [flash._wants_to_remember(), gaze.looking, gaze.held <= held]
	for i in 60:
		echo.step(dt)
	echo.step(1.0)
	var soon_after := flash._wants_to_remember()
	echo.step(1.1)
	PanicSystem.level = 0.3
	var later := flash._wants_to_remember()
	check(idle == [true, true] and during == [false, false, true] and not soon_after and later,
			"no warm memory over the cellar nor 2 s after it; nothing is looked at while the cellar is on the screen",
			[idle, during, soon_after, later])
	TraumaEcho._since = 0.5
	var here := flash._wants_to_remember()
	echo.remove_from_group(TraumaEcho.GROUP)
	var echo_less := flash._wants_to_remember()
	echo.add_to_group(TraumaEcho.GROUP)
	TraumaEcho._since = INF
	check(not here and echo_less,
			"a level with no echo (Act I, from the menu just after one on the road) does not wait out the aftermath",
			[here, echo_less])
	for n: Node in [focus, flash, gaze]:
		n.free()
	player.global_position = spot_a

	# Cooldown and the cap.
	fresh.call()
	TraumaEcho._cool = 10.0
	var cooling: Variant = pass_by.call(0.9)
	echo.step(10.0)
	var cooled: Variant = pass_by.call(0.9)
	check(cooling == null and cooled != null, "no echo sooner than 60 s after the last one", [cooling, cooled])
	fresh.call()
	echo.max_per_level = 1
	TraumaEcho._used["somewhere/else"] = true
	check(pass_by.call(0.9) == null, "no more than max_per_level echoes on a level")
	echo.max_per_level = 3

	# The searchlight. Point B, crouched behind the haystack: the beam sweeps
	# over him and on. The tower is driven by its own clock (sweep_yaw).
	player.global_position = Vector3(-16, 0, 0)
	patrol.global_position = Vector3(30, 0, 30)
	var sweep := func(panic: float, from_t: float, to_t: float) -> Array:
		var r := [null, false, 0.0]  # heading (deg) when the echo started, was he ever lit, top panic before it
		var n := int(round((to_t - from_t) / dt))
		for i in n + 1:
			tower._t = from_t + i * dt
			tower._pivot.rotation.y = tower.sweep_yaw(tower._t)
			if panic >= 0.0:
				PanicSystem.level = panic
			r[1] = r[1] or tower.in_beam(player)
			var was := echo.is_running()
			if not was and r[0] == null:
				r[2] = maxf(r[2], PanicSystem.level)
			echo.step(dt)
			if not was and echo.is_running() and r[0] == null:
				r[0] = rad_to_deg(tower._pivot.rotation.y)
		for i in 60:
			echo.step(dt)
		return r
	var half := tower.sweep_period * 0.25
	fresh.call()
	var hid: Array = sweep.call(0.9, -half, half)
	check(hid[0] != null and float(hid[0]) > 8.0 and float(hid[0]) < 10.5 and not hid[1]
			and starts.size() == 1 and starts[0][0] == TraumaEcho.LIGHT,
			"the beam slides over the haystack he lies behind and leaves its drawn cone: the echo then", [hid, starts])
	fresh.call()
	PanicSystem.level = 0.25
	var by_itself: Array = sweep.call(-1.0, -half, half)
	check(by_itself[0] != null and by_itself[2] <= echo.beam_panic_cap + 0.01,
			"the beam over his cover frightens him by itself up to the threshold (no higher than 0.45)", by_itself)
	fresh.call()
	player.global_position = Vector3(-16, 0, -4)
	var lit: Array = sweep.call(0.9, -half, half)
	check(lit[1] and lit[0] == null, "lit by the beam on its way - that is alarm, no near miss", lit)
	fresh.call()
	player.global_position = Vector3(-16, 0, 0)
	player.velocity = Vector3(0.5, 0, 0)
	var creeping_b: Array = sweep.call(0.9, -half, half)
	player.velocity = Vector3.ZERO
	check(creeping_b[0] == null and not creeping_b[1], "creeping on behind the haystack as the beam leaves: no echo", creeping_b)
	fresh.call()
	tower.sweep_period = 6.0
	player.global_position = Vector3(-16, 0, 0)
	var returns: Array = sweep.call(0.9, -1.5, 1.5)
	tower.sweep_period = 14.0
	fresh.call()
	tower.sweep_amplitude = 11.0
	var lingers: Array = sweep.call(0.9, -half, half)
	tower.sweep_amplitude = 20.0
	# A fast beam not over him now, about to sweep across his place and gone
	# again in 0.7 s: coming, however fast.
	tower.sweep_amplitude = 40.0
	tower.sweep_period = 6.0
	tower._t = -0.3415
	tower._pivot.rotation.y = tower.sweep_yaw(tower._t)
	var arriving := not echo.beam_over(tower, player, echo.light_widen) and echo.light_coming(player)
	tower.sweep_amplitude = 20.0
	tower.sweep_period = 14.0
	check(arriving and returns[0] == null and lingers[0] == null and not returns[1] and not lingers[1],
			"no echo if the beam comes back over him within 2.8 s or does not really leave: the cut must not hide it",
			[arriving, returns, lingers])
	# The look-ahead counts whole steps: a beam that sits on his place (it
	# does not move) comes back even when the window is only just past 1 s.
	tower.sweep_amplitude = 0.0
	tower._pivot.rotation.y = 0.0
	echo.light_clear = 0.25  # window 0.1 + 0.7 + 0.25 = 1.05 s
	var sits := tower.will_cover(player.shoulders(), 0.0, echo.light_widen) and not tower.in_beam(player) \
			and echo.light_coming(player)
	echo.light_clear = 2.0
	tower.sweep_amplitude = 20.0
	check(sits, "a beam that has sat on his place for 1 s comes back: ten steps of 0.1 s are 1 s, not 0.9999")
	# Off to the side of the sweep: 31 degrees from the tower's axis, never
	# under the drawn cone (it reaches 20 + 9), only under the widened one.
	fresh.call()
	var side := tower.global_position + Vector3(sin(deg_to_rad(31.0)), 0, cos(deg_to_rad(31.0))) * 24.0
	player.global_position = Vector3(side.x, 0, side.z)
	PanicSystem.level = 0.3
	var off: Array = sweep.call(-1.0, -half, half)
	check(off[0] == null and is_equal_approx(PanicSystem.level, 0.3),
			"in the open beside the beam's reach: neither fear nor an echo from it", [off, PanicSystem.level])
	player.global_position = Vector3(-16, 0, 0)
	tower._t = 0.0
	tower._pivot.rotation.y = 0.0
	fresh.call()
	PanicSystem.level = 0.0
	for i in 60:
		echo.step(dt)
	var one_second := PanicSystem.level
	PanicSystem.level = 0.44
	for i in 60:
		echo.step(dt)
	var capped := PanicSystem.level
	player.global_position = Vector3(-16, 0, -4)
	PanicSystem.level = 0.0
	for i in 60:
		echo.step(dt)
	var when_lit := PanicSystem.level
	player.global_position = Vector3(-16, 0, 20)
	var beyond := echo.beam_over(tower, player)
	player.global_position = Vector3(-16, 0, 0)
	check(echo.beam_over(tower, player) and absf(one_second - echo.beam_panic) < 0.02
			and capped < echo.beam_panic_cap + 0.005 and capped >= echo.beam_panic_cap - 0.001
			and is_zero_approx(when_lit) and not beyond,
			"the beam over his cover: panic +0.2 a second up to 0.45; lit he is in the light, not afraid of it; out of its range nothing",
			[one_second, capped, when_lit, beyond])

	scene.queue_free()
	await frames(2)
	TraumaEcho.forget_all()
	PanicSystem.reset()
	Perception.reset()
	Sfx.set_muffle(Sfx.OPEN_AIR, 0.0, 0.0)


const BREATH_SCENE := preload("res://src/scenes/test/breath_test.tscn")
const HEARTBEAT_AUDIO := preload("res://src/player/heartbeat_audio.gd")
const BREATH_DT := 1.0 / 60.0
## The fixed run of steps in _test_breath_cues as the BreathControl of before
## 21.11.2026 counted it: every 30th step [step, exposure, air, panic] in
## millionths, and the sounds he made [step, kind] (pants left out).
const BREATH_GOLDEN_MARKS := [[29, 511437, 1000000, 0], [59, 996625, 1000000, 0], [89, 506533, 1000000, 100000], [119, 506533, 913567, 100000], [149, 671033, 1000000, 100000], [179, 745762, 954811, 150000], [209, 190040, 1000000, 250000], [239, 415040, 1000000, 250000], [269, 481706, 972789, 250000], [299, 381706, 1000000, 250000], [329, 231706, 1000000, 250000]]
const BREATH_GOLDEN_EVENTS := [[60, "sob"], [120, "sip"], [175, "exhale"], [197, "sob"]]


## «Дыхание рвётся» (docs/ARCHITECTURE.md): hidden with an enemy near and the
## breath not held, the boy hears his own ragged breath, louder as the sob
## nears, a catch of breath just before it, a quiet sip on a release on the
## beat; under a held breath the heart is never faint. Only what he hears:
## the count to the sob is the same with these cues as without them.
func _test_breath_cues() -> void:
	var bank_ok := Sfx.is_loop("breath_ragged") and not Sfx.is_loop("breath_catch") \
			and not Sfx.is_loop("breath_sip")
	var bank := []
	for id in ["breath_ragged", "breath_catch", "breath_sip"]:
		bank.append([id, Sfx.bus_of(id), Sfx.stream_for(id) != null])
		bank_ok = bank_ok and Sfx.bus_of(id) == Sfx.BODY_BUS and Sfx.stream_for(id) != null
	for kind in ["ragged", "catch", "sip"]:
		bank_ok = bank_ok and ResourceLoader.exists("res://assets/audio/placeholder/%s.res" % kind)
	check(bank_ok, "his ragged breath, the catch and the sip: his body's sounds, placeholders baked, the ragged one a loop",
			bank)

	var w := await _search_world()
	var player := w.player as Player
	var soldier := w.soldier as Enemy
	var hatch := w.hatch as HideSpot
	var breath := player.breath
	var heart := player.get_node("Heartbeat")
	soldier.set_physics_process(false)
	soldier.global_position = Vector3(15, 0, -15)
	PanicSystem.reset()
	breath.winded = 0.0
	check(breath.cues and breath.strain == 0.0 and breath.ragged_player() == null,
			"the cues are on in the player scene; at rest there is no ragged breath")

	var sfx_ids: Array[String] = []
	var on_sfx := func(id: String, _p: AudioStreamPlayer3D) -> void: sfx_ids.append(id)
	var kinds: Array[String] = []
	var on_kind := func(kind: String, _l: float) -> void: kinds.append(kind)
	var noises := [0]
	var on_noise := func(_pos: Vector3, _loud: float, src: Node) -> void:
		if src == player:
			noises[0] += 1
	Sfx.played.connect(on_sfx)
	breath.sound_made.connect(on_kind)
	Stealth.noise_emitted.connect(on_noise)

	# Out in the open, an enemy at arm's length: none of it.
	for i in 60:
		breath.step(BREATH_DT, false, 2.0)
	check(breath.strain == 0.0 and breath.ragged_player() == null and not sfx_ids.has("breath_ragged")
			and not sfx_ids.has("breath_catch"),
			"out in the open no ragged breath and no catch: they belong to the hiding place", [breath.strain, sfx_ids])
	breath.step(BREATH_DT, true, 99.0)
	var open_held: float = heart.call("amplitude")
	breath.step(BREATH_DT, false, 99.0)
	breath.air = 1.0
	check(open_held >= 0.3 - 0.000001, "in the open too, under a held breath the heart can be counted", open_held)

	player.global_position = hatch.global_position + Vector3(0.8, 0, 0)
	await frames(2)
	hatch.interact(player)
	sfx_ids.clear()
	for i in 60:
		breath.step(BREATH_DT, false, 99.0)
	check(player.is_hidden and breath.strain == 0.0 and breath.ragged_player() == null
			and player.breath_sway == 0.0 and not sfx_ids.has("breath_ragged"),
			"hidden with nobody near: no ragged breath, the view still", [breath.strain, player.breath_sway])

	# A soldier walks up from 8 m to 1 m (1.3 m/s, a walk).
	PanicSystem.reset()
	breath.exposure = 0.0
	breath.air = 1.0
	sfx_ids.clear()
	kinds.clear()
	var d := 8.0
	var t := 0.0
	var loop_from := -1.0
	var loop_dist := 0.0
	var first_db := 0.0
	var first_pitch := 0.0
	var entry_strain := 0.0
	var last_db := -INF
	var last_pitch := 0.0
	var louder := true
	var catch_at: Array[float] = []
	var sob_at := -1.0
	while sob_at < 0.0 and t < 15.0:
		var n_sfx := sfx_ids.size()
		var n_kinds := kinds.size()
		breath.step(BREATH_DT, false, d)
		t += BREATH_DT
		if sfx_ids.slice(n_sfx).has("breath_catch"):
			catch_at.append(t)
		if kinds.slice(n_kinds).has("sob"):
			sob_at = t
		else:
			var r := breath.ragged_player()
			if r != null:
				if loop_from < 0.0:
					loop_from = t
					loop_dist = d
					first_db = r.volume_db
					first_pitch = r.pitch_scale
					entry_strain = breath.strain
				elif r.volume_db < last_db - 0.0001 or r.pitch_scale < last_pitch - 0.0001:
					louder = false
				last_db = r.volume_db
				last_pitch = r.pitch_scale
			elif loop_from >= 0.0:
				louder = false  # it must not drop out on the way
		d = maxf(d - 1.3 * BREATH_DT, 1.0)
	var base := Sfx.volume_of("breath_ragged")
	check(loop_from > 0.0 and loop_dist < breath.threat_radius and loop_dist > breath.threat_radius - 0.05
			and entry_strain >= 0.2 and entry_strain <= 0.21 and absf(first_pitch - (0.9 + 0.4 * 0.2)) < 0.01,
			"his ragged breath starts as the soldier comes within 6 m, at once at a fifth of its strength",
			[loop_from, loop_dist, entry_strain, first_pitch])
	check(sob_at - loop_from >= 2.0, "walking up from 6 m, he is heard in the ragged breath seconds before the sob",
			[loop_from, sob_at])
	check(louder and absf(first_db - (base + linear_to_db(0.3 + 0.7 * 0.2))) < 0.3 and first_pitch < 1.0
			and last_db > base - 1.0 and last_pitch > 1.25,
			"the ragged breath grows louder and quicker as the sob nears: from under half its loudness to full",
			[first_db, first_pitch, last_db, base, last_pitch])
	check(catch_at.size() == 1 and sob_at - catch_at[0] <= 0.45 + BREATH_DT
			and sob_at - catch_at[0] >= 0.45 - 3.0 * BREATH_DT,
			"a catch of breath, once, about 0.45 s before the sob", [catch_at, sob_at])

	# Panic 1 and out of breath, the worst case: still every sob has its catch first.
	var seq := ""
	var since_catch := -1.0
	var min_gap := INF
	for i in 240:
		PanicSystem.level = 1.0
		breath.winded = 1.0
		var n_sfx := sfx_ids.size()
		var n_kinds := kinds.size()
		breath.step(BREATH_DT, false, 2.0)
		var c := sfx_ids.slice(n_sfx).has("breath_catch")
		var s := kinds.slice(n_kinds).has("sob")
		seq += "X" if c and s else ("C" if c else ("S" if s else ""))
		if c:
			since_catch = 0.0
		elif since_catch >= 0.0:
			since_catch += BREATH_DT
		if s and not c:
			min_gap = minf(min_gap, since_catch)
	var re := RegEx.new()
	re.compile("^(CS)+C?$")
	check(re.search(seq) != null and seq.count("S") >= 5 and min_gap >= 0.25,
			"panicking and out of breath: one catch before every sob, a quarter of a second ahead at the worst",
			[seq, min_gap])
	PanicSystem.reset()
	breath.winded = 0.0

	# Holding the breath: the ragged breath stops, the heart is loud enough to count.
	breath.exposure = 0.5
	breath.air = 1.0
	breath.step(BREATH_DT, false, 2.0)
	var was_on := breath.ragged_player() != null
	var calm_amp: float = heart.call("amplitude")
	breath.step(BREATH_DT, true, 2.0)
	check(was_on and breath.holding and breath.strain == 0.0 and breath.ragged_player() == null
			and player.breath_sway == 0.0,
			"he holds his breath: the ragged breath stops at once, the view is still", [was_on, breath.strain])
	var held_amp: float = heart.call("amplitude")
	PanicSystem.level = 1.0
	var panic_held: float = heart.call("amplitude")
	PanicSystem.level = 0.0
	await _passes(2)  # its _process has run with the breath held
	var pushed: float = heart.get("heard_amp")
	var ragged_stream := Sfx.stream_for("breath_ragged")
	var live_ragged := func() -> int:
		var n := 0
		for c in player.get_children():
			if c is AudioStreamPlayer3D and (c as AudioStreamPlayer3D).stream == ragged_stream \
					and not c.is_queued_for_deletion():
				n += 1
		return n
	var left_on: int = live_ragged.call()
	breath.cues = false
	var held_no_cues: float = heart.call("amplitude")
	breath.cues = true
	check(is_equal_approx(calm_amp, 0.05) and held_amp >= 0.3 - 0.000001 and is_equal_approx(held_no_cues, 0.05),
			"under the held breath the heart is loud enough to count, calm as he is", [calm_amp, held_amp, held_no_cues])
	check(is_equal_approx(panic_held, 0.6) and pushed >= 0.3 - 0.000001,
			"in panic the held heart stays at its full 0.6, and the beats pushed out are the loud ones", [panic_held, pushed])
	check(left_on == 0, "the ragged breath he stopped is gone, not left playing", left_on)

	sfx_ids.clear()
	kinds.clear()
	noises[0] = 0
	PanicSystem.beat_phase = 0.0
	breath.step(BREATH_DT, false, 2.0)
	check(kinds.has("sip") and sfx_ids.has("breath_sip") and not kinds.has("exhale") and noises[0] == 0,
			"released on the beat: a quiet sip through the nose", [kinds, sfx_ids])
	breath.step(BREATH_DT, true, 2.0)
	sfx_ids.clear()
	kinds.clear()
	PanicSystem.beat_phase = 0.5
	breath.step(BREATH_DT, false, 2.0)
	check(kinds.has("exhale") and not sfx_ids.has("breath_sip"), "off the beat, the old exhale and no sip",
			[kinds, sfx_ids])

	# 1.2 s at 2 m: the ragged breath and the catch, not yet the sob.
	PanicSystem.reset()
	breath.exposure = 0.0
	breath._catch_armed = true
	sfx_ids.clear()
	kinds.clear()
	noises[0] = 0
	var c0 := breath.catches
	var sway := 0.0
	var top_strain := 0.0
	var flips := 0
	var last_sign := 0.0
	var most_loops := 0
	for i in 72:
		breath.step(BREATH_DT, false, 2.0)
		sway = maxf(sway, absf(player.breath_sway))
		top_strain = maxf(top_strain, breath.strain)
		var sg := signf(player.breath_sway)
		if sg != 0.0 and last_sign != 0.0 and sg != last_sign:
			flips += 1
		if sg != 0.0:
			last_sign = sg
		most_loops = maxi(most_loops, live_ragged.call())
	var ragged := breath.ragged_player()
	check(breath.catches == c0 + 1 and breath.ragged_player() != null and sfx_ids.has("breath_catch")
			and kinds.is_empty() and noises[0] == 0,
			"the ragged breath and the catch are his alone: no noise, nothing an enemy hears", [kinds, noises[0], sfx_ids])
	check(ragged != null and ragged.bus == Sfx.BODY_BUS and ragged.get_parent() == player and most_loops == 1,
			"the ragged breath plays on him, on his body's bus: the hiding place does not muffle it",
			[str(ragged.bus) if ragged != null else "-"])
	check(sway > 0.0005 and sway <= 0.004 * top_strain + 0.00001 and flips >= 12,
			"while he hears it the view trembles, a few millimetres, several times a second", [sway, top_strain, flips])

	# The soldier walks off: the ragged breath dies away.
	var s0 := breath.strain
	var fade := 0.0
	var half_on := false
	var half_seen := false
	while breath.strain > 0.0 and fade < 3.0:
		breath.step(BREATH_DT, false, 9.0)
		fade += BREATH_DT
		if not half_seen and fade >= s0 * 0.6 * 0.5:
			half_seen = true
			half_on = breath.ragged_player() != null
	check(half_on and fade <= s0 * 0.6 + 2.0 * BREATH_DT and breath.ragged_player() == null,
			"the soldier walks off: the ragged breath dies away in about half a second", [s0, fade, half_on])

	# A step back and in again, the count barely down: no second catch.
	PanicSystem.reset()
	breath.exposure = 0.0
	breath._catch_armed = true
	var n_dip := 0
	var dip_from := breath.catches
	while breath.catches == dip_from and n_dip < 600:
		breath.step(BREATH_DT, false, 2.0)
		n_dip += 1
	for i in 20:
		breath.step(BREATH_DT, false, 9.0)
	var after_dip := breath.catches
	kinds.clear()
	n_dip = 0
	while not kinds.has("sob") and n_dip < 600:
		breath.step(BREATH_DT, false, 2.0)
		n_dip += 1
	check(breath.catches == after_dip and kinds.has("sob"), "a step back and in again: one build-up, one catch",
			[breath.catches - after_dip])

	# A catch at 2 m, then away a while: the count falls; when he is back, a
	# fresh catch.
	var n_away := 0
	var away_from := breath.catches
	while breath.catches == away_from and n_away < 600:
		breath.step(BREATH_DT, false, 2.0)
		n_away += 1
	for i in 90:
		breath.step(BREATH_DT, false, 9.0)
	var back_catches := breath.catches
	kinds.clear()
	var n_back := 0
	while not kinds.has("sob") and n_back < 600:
		breath.step(BREATH_DT, false, 2.0)
		n_back += 1
	check(breath.catches == back_catches + 1, "the soldier is back after a while: a fresh catch before the sob",
			[breath.catches - back_catches, n_back])

	# After the catch he holds his breath and lets go off the beat: a fresh
	# catch before the sob, not a sob out of nowhere.
	PanicSystem.reset()
	breath.exposure = 0.0
	var before_hold := breath.catches
	var n_hold := 0
	while breath.catches == before_hold and n_hold < 600:
		breath.step(BREATH_DT, false, 2.0)
		n_hold += 1
	for i in 18:
		breath.step(BREATH_DT, true, 2.0)
	PanicSystem.beat_phase = 0.5
	kinds.clear()
	var after_hold := breath.catches
	var warned_first := false
	n_hold = 0
	while not kinds.has("sob") and n_hold < 600:
		breath.step(BREATH_DT, false, 2.0)
		n_hold += 1
		if breath.catches > after_hold and not kinds.has("sob"):
			warned_first = true
	check(kinds.has("exhale") and breath.catches == after_hold + 1 and warned_first,
			"he held after the catch and let go off the beat: a fresh catch, then the sob", [kinds, breath.catches - after_hold])

	# Panicking and winded, the catch comes at once, at a count of nothing; the
	# soldier walks off before the sob and comes back: a catch again first.
	PanicSystem.reset()
	breath.exposure = 0.0
	breath._catch_armed = true
	var low_from := breath.catches
	for i in 2:
		PanicSystem.level = 1.0
		breath.winded = 0.5
		breath.step(BREATH_DT, false, 2.0)
	var low_catch := breath.catches - low_from
	for i in 60:
		PanicSystem.level = 1.0
		breath.winded = 0.5
		breath.step(BREATH_DT, false, 9.0)
	var back_from := breath.catches
	var low_warned := false
	kinds.clear()
	var n_low := 0
	while not kinds.has("sob") and n_low < 600:
		PanicSystem.level = 1.0
		breath.winded = 0.5
		breath.step(BREATH_DT, false, 2.0)
		n_low += 1
		if breath.catches > back_from and not kinds.has("sob"):
			low_warned = true
	check(low_catch == 1 and low_warned and breath.catches == back_from + 1,
			"a catch at a count of nothing, the soldier away and back: the next sob has its catch too",
			[low_catch, breath.catches - back_from, n_low])
	PanicSystem.reset()
	breath.winded = 0.0

	# The soldier stood 4 m off a long while, then stepped up close: the catch
	# came in good time all the same.
	breath.exposure = 0.0
	breath._catch_armed = true
	kinds.clear()
	var far_t := 0.0
	var far_catch := -1.0
	var far_from := breath.catches
	while breath.exposure < 0.9 and far_t < 10.0:
		breath.step(BREATH_DT, false, 4.0)
		far_t += BREATH_DT
		if far_catch < 0.0 and breath.catches > far_from:
			far_catch = far_t
	while not kinds.has("sob") and far_t < 20.0:
		breath.step(BREATH_DT, false, 2.0)
		far_t += BREATH_DT
		if far_catch < 0.0 and breath.catches > far_from:
			far_catch = far_t
	check(far_catch > 0.0 and breath.catches == far_from + 1 and far_t - far_catch >= 0.45 - 3.0 * BREATH_DT,
			"he stood 4 m off a long while and stepped up: still the catch in good time", [far_catch, far_t])

	# The count is the same with the cues as without: exposure, air, sobs, step for step.
	var run := func(with_cues: bool) -> Array:
		breath.cues = with_cues
		PanicSystem.reset()
		breath.exposure = 0.0
		breath.air = 1.0
		breath.winded = 0.5
		breath.holding = false
		breath._lockout = 0.0
		breath._catch_armed = true
		breath.strain = 0.0
		breath._pant_timer = 0.0
		var steps := []
		for i in 330:
			var hold := (i >= 90 and i < 120) or (i >= 150 and i < 175) or (i >= 260 and i < 280)
			PanicSystem.beat_phase = 0.0 if i == 120 else 0.5
			var n_kinds := kinds.size()
			breath.step(BREATH_DT, hold, 2.0 if i < 200 else 2.0 + (i - 200) * 0.06)
			steps.append([breath.exposure, breath.air, breath.holding, breath.winded, PanicSystem.level,
					kinds.slice(n_kinds)])
		return steps
	sfx_ids.clear()
	var on_steps: Array = run.call(true)
	var cue_sfx := sfx_ids.duplicate()
	sfx_ids.clear()
	var c_before := breath.catches
	var off_steps: Array = run.call(false)
	var heard := []
	for st in on_steps:
		heard.append_array(st[5])
	check(on_steps == off_steps and heard.has("sob") and heard.has("sip") and heard.has("exhale"),
			"with the cues as without: the same count, air and sobs, step for step",
			[heard.count("sob"), heard.has("sip"), heard.has("exhale")])
	var marks := []
	var events := []
	for i in on_steps.size():
		for k in on_steps[i][5]:
			if k != "pant":
				events.append([i, k])
		if i % 30 == 29:
			marks.append([i, roundi(on_steps[i][0] * 1000000.0), roundi(on_steps[i][1] * 1000000.0),
					roundi(on_steps[i][4] * 1000000.0)])
	check(marks == BREATH_GOLDEN_MARKS and events == BREATH_GOLDEN_EVENTS,
			"the count, the air and the sobs of a fixed run are those of before 21.11.2026", [marks, events])
	var sway_off := 0.0
	breath.winded = 0.0
	breath.exposure = 0.3
	for i in 30:
		breath.step(BREATH_DT, false, 2.0)
		sway_off = maxf(sway_off, absf(player.breath_sway))
	check(cue_sfx.has("breath_ragged") and cue_sfx.has("breath_catch") and cue_sfx.has("breath_sip")
			and not sfx_ids.has("breath_ragged") and not sfx_ids.has("breath_catch") and not sfx_ids.has("breath_sip")
			and breath.catches == c_before and breath.ragged_player() == null
			and breath.strain > 0.0 and sway_off == 0.0,
			"switched off, he hears none of it and the view does not tremble", [cue_sfx.count("breath_catch"), sfx_ids, sway_off])
	breath.cues = true
	breath.winded = 0.0
	breath.exposure = 0.3
	breath.step(BREATH_DT, false, 2.0)
	var playing := breath.ragged_player() != null
	hatch.interact(player)  # he climbs out
	breath.step(BREATH_DT, false, 2.0)
	check(playing and not player.is_hidden and breath.strain == 0.0 and breath.ragged_player() == null
			and player.breath_sway == 0.0, "he climbs out: the ragged breath stops", [playing, breath.strain])

	# A catch at a count of nothing (panicking, winded), out and straight back
	# in with the soldier still there: the next sob has its catch too.
	hatch.interact(player)  # back in
	PanicSystem.reset()
	breath.exposure = 0.0
	breath._catch_armed = true
	for i in 2:
		PanicSystem.level = 1.0
		breath.winded = 0.5
		breath.step(BREATH_DT, false, 2.0)
	hatch.interact(player)  # out
	for i in 5:
		breath.step(BREATH_DT, false, 2.0)
	hatch.interact(player)  # in again
	var again_from := breath.catches
	var again_warned := false
	kinds.clear()
	var n_again := 0
	while not kinds.has("sob") and n_again < 600:
		PanicSystem.level = 1.0
		breath.winded = 0.5
		breath.step(BREATH_DT, false, 2.0)
		n_again += 1
		if breath.catches > again_from and not kinds.has("sob"):
			again_warned = true
	check(player.is_hidden and again_warned and breath.catches == again_from + 1,
			"out after a catch and straight back in: the next sob has its catch too", [breath.catches - again_from, n_again])
	hatch.interact(player)  # out for good
	PanicSystem.reset()
	breath.winded = 0.0

	Sfx.played.disconnect(on_sfx)
	breath.sound_made.disconnect(on_kind)
	Stealth.noise_emitted.disconnect(on_noise)
	(w.root as Node).queue_free()
	await frames(2)
	PanicSystem.reset()

	# The test scene: the soldier's round over the cellar.
	var scene := BREATH_SCENE.instantiate()
	add_child(scene)
	await frames(3)
	var sp := scene.get_node("Player") as Player
	var ss := scene.get_node("Soldier") as Enemy
	ss.player_caught.disconnect(Callable(scene, "_on_caught"))  # its release would outlive the check
	var live: Array[String] = []
	var on_live := func(id: String, _p: AudioStreamPlayer3D) -> void:
		if id == "breath_ragged" or id == "breath_catch":
			live.append(id)
	var on_live_kind := func(kind: String, _l: float) -> void:
		if kind == "sob":
			live.append("sob")
	Sfx.played.connect(on_live)
	sp.breath.sound_made.connect(on_live_kind)
	var was_hidden := sp.is_hidden
	Engine.time_scale = 3.0
	await _until(func() -> bool: return live.has("sob"), 12.0)
	Engine.time_scale = 1.0
	var ci := live.find("breath_catch")
	check(was_hidden and live.size() >= 3 and live[0] == "breath_ragged" and ci > 0 and ci < live.find("sob"),
			"the test scene: the soldier's round over the cellar - the ragged breath, the catch, then the sob", live)
	Sfx.played.disconnect(on_live)
	sp.breath.sound_made.disconnect(on_live_kind)
	scene.queue_free()
	await frames(2)
	PanicSystem.reset()
	Sfx.set_muffle(Sfx.OPEN_AIR, 0.0, 0.0)


# --- flashes ---------------------------------------------------------------------

## The most swings of `values` by `step` or more inside any `per` values in a
## row - with `per` the rate, the most in any second. A swing is a change of
## `step` from the last extreme the other way, as tools/flash_check.py counts
## a block's transitions (a flash is two).
func _most_swings(values: PackedFloat32Array, step: float, per: int) -> int:
	var hits: Array[int] = []
	var hi := values[0]
	var lo := values[0]
	var dir := 0
	for i in range(1, values.size()):
		var v := values[i]
		hi = maxf(hi, v)
		lo = minf(lo, v)
		if dir >= 0 and hi - v >= step:
			hits.append(i)
			dir = -1
			hi = v
			lo = v
		elif dir <= 0 and v - lo >= step:
			hits.append(i)
			dir = 1
			hi = v
			lo = v
	var most := 0
	var a := 0
	for b in hits.size():
		while hits[b] - hits[a] >= per:
			a += 1
		most = maxi(most, b - a + 1)
	return most


## Deep swings of a light a second at most: changes by 6 % of its top or
## more - a tremble within 5 % (Flicker.SHIMMER) never counts.
func _deep_swings(energy: PackedFloat32Array, fps: int) -> int:
	var top := 0.0
	for e in energy:
		top = maxf(top, e)
	return _most_swings(energy, 0.06 * top, fps)


## The ring of frame_darkening (film_common.gdshaderinc): 1 inside the tunnel
## radius `r0`, 0 from r0 + 0.38 on (smoothstep with the edges reversed).
func _tunnel(r: float, r0: float) -> float:
	var t := clampf((r0 + 0.38 - r) / 0.38, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Flashes and flicker (docs/ARCHITECTURE.md, "Вспышки и мерцание"): no light,
## pulse or key makes more than two flashes a second (four swings of 0.1 in
## luminance), and flicker that goes on stays under one and a half (three).
func _test_flashes() -> void:
	const FPS := 60
	var dt := 1.0 / FPS

	# Flicker itself: a slow sway 0..1, a tremble of at most 1 peak to peak.
	var sway := PackedFloat32Array()
	var lo := 1.0
	var hi := -1.0
	var tr_lo := 1.0
	var tr_hi := -1.0
	for i in 120 * FPS:
		var t := i * dt
		var s := Flicker.sway(t)
		sway.append(s)
		lo = minf(lo, s)
		hi = maxf(hi, s)
		tr_lo = minf(tr_lo, Flicker.tremble(t, 0.7))
		tr_hi = maxf(tr_hi, Flicker.tremble(t, 0.7))
	check(lo >= -0.001 and hi <= 1.001 and hi - lo > 0.9, "Flicker: the sway goes from 0 to 1", [lo, hi])
	check(_most_swings(sway, 0.05, FPS) <= 3, "the sway turns at most three times a second (one and a half flashes)",
			_most_swings(sway, 0.05, FPS))
	check(Flicker.SHIMMER <= 0.05, "a light trembles by 5 % at most", Flicker.SHIMMER)
	check(tr_hi - tr_lo <= 1.0001 and tr_hi - tr_lo > 0.8, "the tremble is at most 1 peak to peak: SHIMMER of a light",
			tr_hi - tr_lo)

	# The lamp of the dream, every room: deep only slowly.
	var layout := (load("res://src/scenes/interlude_night/night_layout.gd") as GDScript).new() as Node3D
	layout.lamp = OmniLight3D.new()
	layout.window_light = OmniLight3D.new()
	var lamp_rooms: Array = (load("res://src/scenes/interlude_night/night_dream.gd") as GDScript) \
			.get_script_constant_map()["LAMP"]
	var lamp_worst := 0
	var lamp_lo := 99.0
	var lamp_hi := 0.0
	for room in lamp_rooms:
		layout.set_lamp(room[0], room[1])
		var e := PackedFloat32Array()
		for i in 60 * FPS:
			layout._process(dt)
			e.append(layout.lamp.light_energy)
		lamp_worst = maxi(lamp_worst, _deep_swings(e, FPS))
		if room == lamp_rooms[3]:
			for x in e:
				lamp_lo = minf(lamp_lo, x)
				lamp_hi = maxf(lamp_hi, x)
	check(lamp_worst <= 3, "the dream's lamp gutters deeply only slowly: at most three swings a second",
			lamp_worst)
	check(lamp_lo < 0.2 and lamp_hi > 0.55, "in the last room it still dies down almost to nothing",
			[lamp_lo, lamp_hi])
	# The flare in the window: it sways, then fades.
	layout.flare(6.0)
	var win := PackedFloat32Array()
	for i in 6 * FPS:
		layout._process(dt)
		win.append(layout.window_light.light_energy)
	layout._process(dt)
	check(_deep_swings(win, FPS) <= 3 and win[0] > 1.5 and layout.window_light.light_energy < 0.001,
			"the flare in the window sways, not strobes, and goes out", _deep_swings(win, FPS))
	layout.lamp.free()
	layout.window_light.free()
	layout.free()

	# The signal flare over the village (red light).
	var flare := (load("res://src/props/signal_flare.tscn") as PackedScene).instantiate() as SignalFlare
	flare.autofire = false
	add_child(flare)
	await frames(1)
	flare.set_process(false)
	flare.launch()
	var fl := PackedFloat32Array()
	for i in int(flare.burn_time * FPS):
		flare._process(dt)
		fl.append(flare.light.light_energy)
	check(_deep_swings(fl, FPS) <= 3 and fl[0] > 4.5, "the signal flare sways as it falls, never strobes",
			_deep_swings(fl, FPS))
	flare.queue_free()
	PanicSystem.reset()

	# The fire in the Act III dugout.
	var act3 := (load("res://src/scenes/act3_garrison/act3_layout.gd") as GDScript).new() as Node3D
	act3._fire = OmniLight3D.new()
	var fire := PackedFloat32Array()
	for i in 60 * FPS:
		act3._process(dt)
		fire.append(act3._fire.light_energy)
	check(_deep_swings(fire, FPS) <= 3, "the dugout fire flickers deeply only slowly", _deep_swings(fire, FPS))
	act3._fire.free()
	act3.free()

	# The heartbeat pulse in the panic tunnel: as deep as ever in the dark, and
	# no pixel darkens on a beat by more than PULSE_DY (the shader's limit,
	# modelled here line by line).
	var film := FileAccess.get_file_as_string("res://src/rendering/shaders/film_common.gdshaderinc")
	var dy_at := film.find("const float PULSE_DY = ")
	var pulse_dy := film.substr(dy_at + 23, 12).get_slice(";", 0).to_float() if dy_at >= 0 else 1.0
	check(pulse_dy > 0.0 and pulse_dy <= 0.08, "a pixel darkens on a heartbeat by 0.08 of luminance at most",
			pulse_dy)
	check(film.contains("float beat = smoothstep(radius - g_heartbeat + 0.38, radius - g_heartbeat, r);")
			and film.contains("float floor_v = pow(max(y_calm - PULSE_DY, 0.0), 1.0 / 2.2) / lit;")
			and film.contains("float v = max(beat, min(floor_v, calm));")
			and film.contains("c *= frame_darkening(uv, max(max(c.r, c.g), c.b));"),
			"the shader holds the beat to PULSE_DY by the brightest channel (the model below is the shader's)")
	PanicSystem.level = 1.0
	var full_depth := PanicSystem.pulse_depth()
	PanicSystem.level = 0.0
	var calm_depth := PanicSystem.pulse_depth()
	PanicSystem.reset()
	check(absf(full_depth - 0.07) < 0.001 and calm_depth < 0.01,
			"the tunnel closes in on a beat by 0.07 at full panic, as before, and hardly at all when calm",
			[full_depth, calm_depth])
	var worst_dy := 0.0
	var dark_kept := 1.0
	var bright_cut := 1.0
	for p in [0.2, 0.5, 0.75, 1.0]:
		var radius := lerpf(0.62, 0.3, p)
		var shift: float = 0.05 * (0.25 + 0.75 * p) * (0.4 + p)
		for li in range(1, 21):
			var l := li / 20.0
			for k in 451:
				var r := k / 500.0
				var calm := _tunnel(r, radius)
				var beat := _tunnel(r, radius - shift)
				var lit := maxf(l, 0.0001)
				var y_calm := pow(clampf(lit * calm, 0.0, 1.0), 2.2)
				var floor_v := pow(maxf(y_calm - pulse_dy, 0.0), 1.0 / 2.2) / lit
				var v := maxf(beat, minf(floor_v, calm))
				worst_dy = maxf(worst_dy, y_calm - pow(clampf(lit * v, 0.0, 1.0), 2.2))
				if calm - beat > 0.01:
					var kept := (calm - v) / (calm - beat)
					if l <= 0.4:
						dark_kept = minf(dark_kept, kept)
					elif p == 1.0 and l == 1.0:
						bright_cut = minf(bright_cut, kept)
	check(worst_dy <= pulse_dy + 0.0001, "on any pixel, however bright, the beat darkens by PULSE_DY at most: no flash",
			worst_dy)
	check(dark_kept > 0.999, "on a dark pixel (0.4 and below) the pulse keeps its whole depth", dark_kept)
	check(bright_cut < 0.5, "on a white pixel at full panic it throbs less than half as deep", bright_cut)
	check(FileAccess.get_file_as_string("res://src/core/panic_system.gd")
			.contains("global_shader_parameter_set(\"g_heartbeat\", pulse * pulse_depth())"),
			"the shader is given the pulse by pulse_depth()")

	# The air the frame shows: eased, so a key tapped fast cannot flash it.
	var w := await _search_world()
	var player := w.player as Player
	var breath := player.breath
	var air_worst := 0
	for period in [0.24, 0.4, 0.6, 0.9]:
		breath.air = 1.0
		breath.shown_air = 1.0
		PanicSystem.level = 1.0
		var y := PackedFloat32Array()
		for i in 6 * FPS:
			breath.winded = 1.0  # the fastest drain: panicked and out of breath
			breath.step(dt, fmod(i * dt, period) < period * 0.5, INF)
			var s := clampf(1.0 - breath.shown_air, 0.0, 1.0)
			y.append(pow(1.0 - 0.8 * s * s * (3.0 - 2.0 * s), 2.2))
		air_worst = maxi(air_worst, _most_swings(y, 0.1, FPS))
	check(air_worst <= 3, "the hold key tapped two to four times a second: the frame changes at most three times a second",
			air_worst)
	check(FileAccess.get_file_as_string("res://src/player/breath_control.gd")
			.contains("global_shader_parameter_set(\"g_air\", shown_air)"), "the frame is given the eased air")
	breath.air = 0.2
	for i in FPS:
		breath._publish(dt)
	check(absf(breath.shown_air - breath.air) < 0.05, "the frame catches up with the air within a second",
			[breath.shown_air, breath.air])
	PanicSystem.reset()
	breath.winded = 0.0

	# The torch light in the gaps: a beam that keeps grazing an edge.
	var leak_worst := 0
	for period in [0.04, 0.1, 0.24, 0.5, 0.9]:
		for duty in [0.2, 0.5, 0.8]:
			player.torch_leak = 0.0
			player._leak_dir = 0
			player._leak_swing_age = 0.0
			var y := PackedFloat32Array()
			for i in 5 * FPS:
				player._follow_leak(1.0 if fmod(i * dt, period) < period * duty else 0.0, dt)
				y.append(pow(0.92 * 0.95 * player.torch_leak, 2.2))
			leak_worst = maxi(leak_worst, _most_swings(y, 0.1, FPS))
	check(leak_worst <= 3, "a beam flickering on an edge: the gaps change at most three times a second", leak_worst)
	player.torch_leak = 0.0
	player._leak_dir = 0
	player._leak_swing_age = 0.0
	for i in int(0.3 * FPS):
		player._follow_leak(1.0, dt)
	var lit := player.torch_leak
	for i in int(0.6 * FPS):
		player._follow_leak(0.0, dt)
	check(lit > 0.99 and player.torch_leak < 0.01, "but a beam that comes lights the gaps at once and goes out after it",
			[lit, player.torch_leak])
	player.torch_leak = 1.0
	player._opened_k = 1.0
	var opened := player.shown_leak()
	player._opened_k = 0.0
	check(opened == 0.0 and is_equal_approx(player.shown_leak(), player._leak_gain),
			"the doors swung open: the gaps' light is gone with them", opened)
	player._opened_k = 1.0
	player._update_torch_leak(dt)
	var painted: float = (player.hide_overlay.material as ShaderMaterial).get_shader_parameter("leak")
	player._opened_k = 0.0
	check(player.torch_leak > 0.5 and painted == 0.0, "and the overlay is given what is shown, not the raw leak",
			[player.torch_leak, painted])
	PanicSystem.reset()
	player.torch_leak = 0.0
	var overlay := FileAccess.get_file_as_string("res://src/player/hide_overlay.gdshader")
	check(overlay.contains("0.04 * hash(seg + floor(TIME * 12.0))") and not overlay.contains("0.15 * hash(floor(along"),
			"the dust in the gaps trembles by 4 % twelve times a second, not 15 %")
	check(pow(0.92, 2.2) - pow(0.92 * 0.96, 2.2) < 0.08, "4 % on the brightest gap changes the luminance by under 0.1")

	# Keys that swap the whole screen: mashed, at most one swap per SWAP_GAP.
	Flicker.forget_swaps()
	var allowed := 0
	for i in 10:
		allowed += int(Flicker.allow_swap())
	check(allowed == 1 and not Flicker.swap_ready(), "ten presses at once: one swap")
	await _wait(Flicker.SWAP_GAP + 0.05)
	check(Flicker.swap_ready() and Flicker.allow_swap(), "after SWAP_GAP a press swaps again")
	var fake := Node3D.new()
	fake.add_to_group("levels")
	add_child(fake)
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	Flicker.forget_swaps()
	var swaps := 0
	var was := PauseMenu.is_open
	for i in 10:
		PauseMenu._unhandled_input(esc)
		swaps += int(PauseMenu.is_open != was)
		was = PauseMenu.is_open
	check(swaps == 1 and PauseMenu.is_open and get_tree().paused, "Esc mashed ten times: the pause opens once and stays",
			swaps)
	PauseMenu.close()
	var journal := InputEventAction.new()
	journal.action = "archive_journal"
	journal.pressed = true
	Flicker.forget_swaps()
	swaps = 0
	was = player.archive_ui.is_open
	for i in 10:
		player._unhandled_input(journal)
		player.archive_ui._unhandled_input(journal)
		swaps += int(player.archive_ui.is_open != was)
		was = player.archive_ui.is_open
	check(swaps == 1 and player.archive_ui.is_open, "J mashed ten times: the journal opens once and stays", swaps)
	player.archive_ui.close()
	# E at the wardrobe, mashed: in once; then the satchel in there, mashed.
	var wardrobe := w.wardrobe as HideSpot
	var shape := wardrobe.get_node_or_null("Shape") as Node3D
	player.global_position = wardrobe.global_position + Vector3(0, 0, -1.1)
	await frames(2)
	player.look_towards(shape.global_position if shape != null else wardrobe.global_position + Vector3.UP)
	await frames(2)
	var e_key := InputEventAction.new()
	e_key.action = "interact"
	e_key.pressed = true
	Flicker.forget_swaps()
	swaps = 0
	was = player.is_hidden
	for i in 10:
		player._unhandled_input(e_key)
		swaps += int(player.is_hidden != was)
		was = player.is_hidden
	check(swaps == 1 and player.is_hidden, "E mashed at the wardrobe: in once, and he stays in", swaps)
	var bag := InputEventAction.new()
	bag.action = "inventory"
	bag.pressed = true
	Flicker.forget_swaps()
	swaps = 0
	was = player.satchel.is_open
	for i in 10:
		player._unhandled_input(bag)
		swaps += int(player.satchel.is_open != was)
		was = player.satchel.is_open
	check(swaps == 1 and player.satchel.is_open, "in a hiding place the satchel, mashed, opens once", swaps)
	player.satchel.close()
	if player.is_hidden:
		wardrobe.interact(player)
	# The passes: Esc straight after the E that opened them waits.
	var passes := PassCheckUI.new()
	add_child(passes)
	await frames(1)
	passes.open()
	await _passes(2)  # not the frame it opened in
	Flicker.forget_swaps()
	Flicker.allow_swap()  # the E on the bundle
	passes._unhandled_input(esc)
	var stayed := passes.is_open
	Flicker.forget_swaps()
	passes._unhandled_input(esc)
	check(stayed and not passes.is_open, "the passes: Esc right after the E that opened them waits, later it closes them",
			[stayed, passes.is_open])
	passes.queue_free()
	Flicker.forget_swaps()
	fake.queue_free()
	(w.root as Node).queue_free()
	await frames(2)
	await _wait(1.5)  # the wardrobe's creak and his panting die away before the runner quits
