"""The run guard's own checks (tests/run_guard.gd; docs/ARCHITECTURE.md, "Проверка", "Сторож прогона";
26.11.2026). Each mutant is what the guard is there for: before it, G1-G3 passed green (the errors were only in
the log), G4 hung until killed, G5 left Godot idle for ever; G6 started the run over and over (the deadline and
the errors began afresh with each load), G7 left the runner calling a guard with no script and never quitting.
Every one must now end by itself and fail.
A misspelt --only= name is checked by hand (a run is a control and must be green): `-- --only=_test_itemz`
fails "--only= names a group of _run".
Run 26.11.2026 by tools/checks/mutate.py on today's code: 7 of 7 caught."""

RUN = {"args": ["res://tests/test_runner.tscn", "--", "--only=_test_items"], "timeout": 300}

T = "tests/test_runner.gd"
START = "func _test_items() -> void:\n"

MUTANTS = [
    {"name": "G1 a script error mid-group (the rest of the group never runs)",
     "edits": [(T, START, START + '\tvar d := {}\n\tvar x: int = d["missing"]\n\tprint(x)\n')]},
    {"name": "G2 a script error after an await",
     "edits": [(T, START, START + '\tawait get_tree().process_frame\n\tvar d := {}\n\tvar x: int = d["missing"]\n'
                                  '\tprint(x)\n')]},
    {"name": "G3 push_error in a group",
     "edits": [(T, START, START + '\tpush_error("the guard\'s own check")\n')]},
    {"name": "G4 an await that never comes back",
     "edits": [(T, START, START + "\tawait get_tree().create_timer(3600.0).timeout\n"),
               ("tests/test_runner.tscn", "deadline = 1800.0", "deadline = 20.0")]},
    {"name": "G5 the runner's script does not parse",
     "edits": [(T, START, START + "\tvar nothing := NoSuchClassAnywhere.new()\n\tprint(nothing)\n")],
     "parse_ok": True},
    {"name": "G6 a test reloads the current scene: the runner itself",
     "edits": [(T, START, START + "\tget_tree().reload_current_scene()\n")]},
    {"name": "G7 the guard's own script does not parse",
     "edits": [("tests/run_guard.gd", "func errors() -> int:\n", "func errors() -> int:\n\tvar nothing := NoSuchClassAnywhere.new()\n")],
     "parse_ok": True},
]
