"""Breakages of the heart that only a real audio driver shows (docs/ARCHITECTURE.md, «Игрок»: «Удар слышен в
такт» and «Без швов»; «Проверка», the line on tools/heart_sync_probe.gd: «Саму пробу проверяли поломками сердца»,
seven of them). The probe exits with the number of bad results, so a mutant is caught when it exits non-zero.
P3 and P4 replace the whole of src/player/heartbeat_audio.gd: the version before 25.11 (69c5c91), the first fix.
Converted from the scratchpad heart/mutate.py (v7, PROBE list) by scratchpad checks/convert_heart.py. Last full
run 25.11.2026 (v7 list): all seven exit non-zero (P3 rerun the same evening on 69c5c91, exit 4: the first
run had read HEAD, which by then was already the new heart); the good code exited 0 in five runs of five
(GOOD_RUNS=5 in the source; here RUN "controls": 5: one green run on a real driver proves little, and a
busy machine can starve the queue).
The source wrote CRLF line ends (the file was CRLF then), here LF; none is about the CR itself: P2.
Lost: none of the v7 ids. The first list (on heartbeat_audio_v2.gd, 25.11.2026 morning; its script was overwritten,
only heart/logs/mutate_quick.log and mutate_probe.log name them) had M9 «synthesized anew each push»,
M11 «no cap on the speed-up» and probe P2 «synthesized anew each push», whose edits are nowhere; from v3 on
those ids name other breakages (the same breakage as that P2 is now P4, the whole first-fix file).
Run 26.11.2026 by tools/checks/mutate.py on today's code: 7 of 7 caught, the control green five times of five."""

RUN = {"godot_args": ["--display-driver", "headless", "--audio-driver", "WASAPI"],
       "args": ["--script", "res://tools/heart_sync_probe.gd"], "timeout": 180, "verdict": "exit", "controls": 5}

MUTANTS = [
    {"name": 'P1 push leaves out the queue',
     "edits": [('src/player/heartbeat_audio.gd', 'lead_time(_capacity - room, driver)', 'lead_time(0, driver)')]},
    {"name": 'P2 starts afresh at every push',
     "edits": [('src/player/heartbeat_audio.gd', '\tif beat_clock < 0.0:\n', '\tif true:\n')]},
    {"name": 'P3 the version before 25.11 (69c5c91)',
     "edits": [('src/player/heartbeat_audio.gd', {'git': '69c5c91'})],
     "note": 'the whole file as committed in 69c5c91 (the source read it with git show; the blob is CRLF, as it was then, and is written as stored)'},
    {"name": 'P4 the first fix (synthesized anew each push)',
     "edits": [('src/player/heartbeat_audio.gd', {'copy': 'files/heart_P4_heartbeat_audio_current.gd.txt'})],
     "note": 'the whole file: scratchpad heart/heartbeat_audio_current.gd (25.11.2026 14:04, the first fix), copied with LF'},
    {"name": 'P5 _process passes the latency alone',
     "edits": [('src/player/heartbeat_audio.gd', 'feed(_playback, Time.get_ticks_usec(), driver_time(_latency))', 'feed(_playback, Time.get_ticks_usec(), _latency)')]},
    {"name": 'P6 driver time without the next mix',
     "edits": [('src/player/heartbeat_audio.gd', 'return maxf(AudioServer.get_time_to_next_mix(), 0.0) + engine_lag(', 'return engine_lag(')]},
    {"name": "P7 driver time without the engine's lag",
     "edits": [('src/player/heartbeat_audio.gd', ' + engine_lag(AudioServer.get_mix_rate()) + latency', ' + latency')]},
]
