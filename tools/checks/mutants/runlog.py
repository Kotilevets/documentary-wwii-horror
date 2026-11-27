"""Breakages of the run log marks and of progress.json (docs/ARCHITECTURE.md, «Прогресс» and «Метки в журнале
запуска»; 27.11.2026): each must fail _test_run_log or _test_progress_file. Two things are not mutated here: the
lines themselves (print - the tests do not read the output; their text is GameState.log_text, which
_test_game_state checks) and the guard of the player's own file in headless runs (_real_file_kept: a mutant there
would run with the real user data; _test_progress_file checks the guard directly). The builder's stamp
(tools/make_playtest_build.py) is Python, outside these runs."""

RUN = {"args": ["res://tests/test_runner.tscn", "--", "--only=_test_run_log,_test_progress_file"], "timeout": 300}

GS = "src/core/game_state.gd"
FS = "src/core/frame_stats.gd"

MUTANTS = [
    {"name": "L1 the stamp ignores override.cfg",
     "edits": [(GS, 'var stamp := str(ProjectSettings.get_setting(BUILD_SETTING, "")).strip_edges()', 'var stamp := ""')]},
    {"name": "L2 the frames of the loading are counted",
     "edits": [(GS, "\t\tif _frames_skip > 0:\n\t\t\t_frames_skip -= 1\n", "\t\tif false:\n\t\t\t_frames_skip -= 1\n")]},
    {"name": "L3 the counting goes on after its line",
     "edits": [(GS, '\t_frames_scene = ""\n\treturn line\n', "\treturn line\n")]},
    {"name": "L4 a headless run counts the frames of its scenes",
     "edits": [(GS, "func log_scene(scene: Node) -> void:\n\tif Player.is_scripted_run():\n\t\treturn\n",
                "func log_scene(scene: Node) -> void:\n")]},
    {"name": "L5 a percentile above the worst frame",
     "edits": [(FS, "minf((i + 0.5) * BIN_MS, worst)", "(i + 0.5) * BIN_MS")]},
    {"name": "L6 the last bin reads its middle, not the worst",
     "edits": [(FS, "return worst if i == BINS - 1 else minf((i + 0.5) * BIN_MS, worst)",
                "return minf((i + 0.5) * BIN_MS, worst)")]},
    {"name": "L7 bins of 1 ms",
     "edits": [(FS, "const BIN_MS := 0.25", "const BIN_MS := 1.0")]},
    {"name": "P1 the file before is deleted, not kept as .bak",
     "edits": [(GS, 'var err := DirAccess.rename_absolute(save_path, save_path + ".bak")',
                "var err := DirAccess.remove_absolute(save_path)")]},
    {"name": "P2 no format version in the file",
     "edits": [(GS, '"version": FORMAT_VERSION, "reached": reached', '"reached": reached')]},
    {"name": "P3 an unreadable file is left where it is",
     "edits": [(GS, "\tif d == null and FileAccess.file_exists(save_path) and not _real_file_kept():\n",
                "\tif false:\n")]},
    {"name": "P4 .bak is read before .tmp",
     "edits": [(GS, '[save_path + ".tmp", save_path + ".bak"]', '[save_path + ".bak", save_path + ".tmp"]')]},
    {"name": "P5 a file of a newer format is overwritten",
     "edits": [(GS, "\tif version > FORMAT_VERSION:\n", "\tif false:\n")]},
    {"name": "P6 an unreadable file logs an error (JSON.parse_string)",
     "edits": [(GS, "\tvar json := JSON.new()\n\tif json.parse(FileAccess.get_file_as_string(path)) != OK:\n"
                    "\t\treturn null\n\treturn json.data if typeof(json.data) == TYPE_DICTIONARY else null\n",
                "\tvar d = JSON.parse_string(FileAccess.get_file_as_string(path))\n"
                "\treturn d if typeof(d) == TYPE_DICTIONARY else null\n")]},
    {"name": "P7 no check that the temporary file came out whole",
     "edits": [(GS, "\tif FileAccess.get_file_as_string(tmp) != text:\n", "\tif false:\n")],
     "survives": "no test can make a write come out short (a full disk): the read-back is only read, never "
                 "tripped (docs/ARCHITECTURE.md, «Прогресс»)"},
]
