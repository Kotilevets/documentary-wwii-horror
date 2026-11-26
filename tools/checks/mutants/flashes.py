"""Breakages of the flash rule (docs/ARCHITECTURE.md, «Вспышки и мерцание»; the count is in «Проверка»,
_test_flashes: «каждую из 29 намеренных ошибок»): each puts back an old formula (the dream lamp, the flare in
the window, the signal flare and the dugout fire at strobe rates, a deeper sway, shimmer or tremble, the pulse
limiter off or by luma, the old pulse depth, the air and the torch leak given raw or eased too fast) or takes
a Flicker.allow_swap() guard off (journal, pause, hiding place, satchel in hiding, passes), and each must fail
_test_flashes. Last full run 26.11.2026 (scratch mutate_flash.py through a probe that ran only _test_flashes):
29 of 29 caught. Lost ids: none. The F9-F12 block was rewritten that day after the pulse cap gave way to the
limiter: the earlier F9 «pulse not capped», F10 «cap at 0.03» and F12 «shader scales the pulse again» (run
earlier on 26.11.2026, 27 of 27 caught) were rewritten in place into the present F9, F10 and F12 (scratch
upd_mutants.py); their old text is in no saved script, and the code they broke (the PULSE_MAX cap, the
shader's own pulse scaling) is gone, so they could only be stale.
Run 26.11.2026 by tools/checks/mutate.py on today's code: 29 of 29 caught."""

RUN = {"args": ["res://tests/test_runner.tscn", "--", "--only=_test_flashes"], "timeout": 600}

MUTANTS = [
    {"name": 'F1 dream lamp at 2.5 and 4.8 Hz',
     "edits": [('src/scenes/interlude_night/night_layout.gd', 'lamp.light_energy = Flicker.light(_lamp_energy, _flicker, _t)', 'lamp.light_energy = _lamp_energy * (1.0 - _flicker * (0.5 + 0.5 * sin(_t * 23.0) * sin(_t * 7.3)))')]},
    {"name": 'F2 window flare at 4.9 Hz',
     "edits": [('src/scenes/interlude_night/night_layout.gd', 'window_light.light_energy = Flicker.light(2.5, 0.3, _t, 2.0) * ', 'window_light.light_energy = (2.2 + sin(_t * 31.0) * 0.6) * ')]},
    {"name": 'F3 signal flare at 4.9 Hz',
     "edits": [('src/props/signal_flare.gd', 'light.light_energy = Flicker.light(6.0 * (1.0 - k), 0.15, _burn)', 'light.light_energy = 6.0 * (1.0 - k) * (0.85 + 0.15 * sin(_burn * 31.0))')]},
    {"name": 'F4 dugout fire at 1.75 and 3.7 Hz',
     "edits": [('src/scenes/act3_garrison/act3_layout.gd', '_fire.light_energy = Flicker.light(1.95, 0.35, _t, 1.0)', '_fire.light_energy = 1.6 + 0.35 * sin(_t * 11.0) + 0.2 * sin(_t * 23.0 + 1.3)')]},
    {"name": 'F5 sway at 2.5 Hz',
     "edits": [('src/rendering/flicker.gd', 'const SWAY_HZ := 1.13', 'const SWAY_HZ := 2.5')]},
    {"name": 'F6 shimmer 15 %',
     "edits": [('src/rendering/flicker.gd', 'const SHIMMER := 0.05', 'const SHIMMER := 0.15')]},
    {"name": 'F7 tremble three times deeper',
     "edits": [('src/rendering/flicker.gd', 'return 0.25 * sin(TAU * 7.9 * t', 'return 0.75 * sin(TAU * 7.9 * t')]},
    {"name": 'F8 swaps never wait',
     "edits": [('src/rendering/flicker.gd', '\tif not swap_ready():\n\t\treturn false', '\tif false:\n\t\treturn false')],
     "note": 'the source edit had CRLF line ends only because the file was CRLF then; written with LF since the 26.11.2026 renormalization (the mutant is about the swap guard, not the CR)'},
    {"name": 'F9 limiter off',
     "edits": [('src/rendering/shaders/film_common.gdshaderinc', 'float v = max(beat, min(floor_v, calm));', 'float v = beat;')]},
    {"name": 'F10 limit at 0.3',
     "edits": [('src/rendering/shaders/film_common.gdshaderinc', 'const float PULSE_DY = 0.08;', 'const float PULSE_DY = 0.3;')]},
    {"name": 'F11 pulse published the old way',
     "edits": [('src/core/panic_system.gd', '("g_heartbeat", pulse * pulse_depth())', '("g_heartbeat", pulse * (0.25 + 0.75 * level))')]},
    {"name": 'F12 limit by luma, not the brightest channel',
     "edits": [('src/rendering/shaders/film_common.gdshaderinc', 'c *= frame_darkening(uv, max(max(c.r, c.g), c.b));', 'c *= frame_darkening(uv, luma(c));')]},
    {"name": 'F13 air not eased',
     "edits": [('src/player/breath_control.gd', 'shown_air += (air - shown_air) * (1.0 - exp(-delta / AIR_SHOWN_TAU))', 'shown_air = air')]},
    {"name": 'F14 air eased over 0.05 s',
     "edits": [('src/player/breath_control.gd', 'const AIR_SHOWN_TAU := 0.3', 'const AIR_SHOWN_TAU := 0.05')]},
    {"name": 'F15 frame given the raw air',
     "edits": [('src/player/breath_control.gd', '("g_air", shown_air)', '("g_air", air)')]},
    {"name": 'F16 leak turns back at once',
     "edits": [('src/player/player.gd', 'const LEAK_MIN_SWING := 0.5', 'const LEAK_MIN_SWING := 0.0')]},
    {"name": 'F17 leak turns back after 0.3 s',
     "edits": [('src/player/player.gd', 'const LEAK_MIN_SWING := 0.5', 'const LEAK_MIN_SWING := 0.3')]},
    {"name": 'F18 leak stays as the doors open',
     "edits": [('src/player/player.gd', 'return torch_leak * _leak_gain * (1.0 - _opened_k)', 'return torch_leak * _leak_gain')]},
    {"name": 'F19 overlay given the raw leak',
     "edits": [('src/player/player.gd', 'mat.set_shader_parameter("leak", shown_leak())', 'mat.set_shader_parameter("leak", torch_leak * _leak_gain)')]},
    {"name": 'F20 dust at 15 %, 12 Hz',
     "edits": [('src/player/hide_overlay.gdshader', '0.89 + 0.07 * hash(seg * 1.7 + 0.3) + 0.04 * hash(seg + floor(TIME * 12.0))', '0.85 + 0.15 * hash(seg + floor(TIME * 12.0))')]},
    {"name": 'F21 pause opens on every Esc',
     "edits": [('src/ui/pause_menu.gd', '\t\tif Flicker.allow_swap():\n\t\t\topen()', '\t\tif true:\n\t\t\topen()')],
     "note": 'the source edit had CRLF line ends only because the file was CRLF then; written with LF since the 26.11.2026 renormalization (the mutant is about the swap guard, not the CR)'},
    {"name": 'F22 pause closes on every Esc',
     "edits": [('src/ui/pause_menu.gd', '\t\telif Flicker.allow_swap():  # the pause', '\t\telse:  # the pause')]},
    {"name": 'F23 journal opens on every J',
     "edits": [('src/player/player.gd', '\t\tif Flicker.allow_swap():\n\t\t\tarchive_ui.open_journal()', '\t\tif true:\n\t\t\tarchive_ui.open_journal()')],
     "note": 'the source edit had CRLF line ends only because the file was CRLF then; written with LF since the 26.11.2026 renormalization (the mutant is about the swap guard, not the CR)'},
    {"name": 'F24 journal closes on every key',
     "edits": [('src/ui/archive_ui.gd', 'if Flicker.allow_swap():  # the paper', 'if true:  # the paper')]},
    {"name": 'F25 E into a hiding place at once',
     "edits": [('src/player/player.gd', 'if not _swaps_view_on_interact() or Flicker.allow_swap():', 'if true:')]},
    {"name": 'F26 satchel in hiding at once',
     "edits": [('src/player/player.gd', 'if not is_hidden or Flicker.allow_swap():', 'if true:')]},
    {"name": 'F27 passes close at once',
     "edits": [('src/act3/pass_check_ui.gd', '\telif event.is_action_pressed("ui_cancel"):\n\t\tif Flicker.allow_swap():', '\telif event.is_action_pressed("ui_cancel"):\n\t\tif true:')]},
    {"name": 'F28 pulse cut to 0.012 again',
     "edits": [('src/core/panic_system.gd', 'return 0.05 * (0.25 + 0.75 * level) * (0.4 + level)', 'return minf(0.05 * (0.25 + 0.75 * level) * (0.4 + level), 0.012)')]},
    {"name": 'F29 beat floor in perceptual tone',
     "edits": [('src/rendering/shaders/film_common.gdshaderinc', 'pow(max(y_calm - PULSE_DY, 0.0), 1.0 / 2.2) / lit;', 'max(lit * calm - PULSE_DY, 0.0) / lit;')]},
]
