"""Breakages of the second try of the Act I opening, from the flare (docs/ARCHITECTURE.md, «Сцена «Вторжение»», 8,
and «Прятки в подполе и за печью», «Повтор с ракеты»; 27.11.2026): each must fail _test_invasion_again, or the cellar
part where a mutant says so. Not mutated: the escape left out of _retries_opening (LevelBase never retries a
reload that resumes at the checkpoint, so taking it out of either place alone changes nothing), `again` false on a
resumed load (the same guard), and --intro-scale shortening again_time (a debug argument, no test)."""

RUN = {"args": ["res://tests/test_runner.tscn", "--", "--only=_test_invasion_again"], "timeout": 600}
CELLAR = {"args": ["res://tests/playthrough_runner.tscn", "--", "--only=cellar"], "timeout": 1500}

LB = "src/scenes/level_base.gd"
A1 = "src/scenes/act1_village/act1_village.gd"
INV = "src/story/invasion_sequence.gd"
PAUSE = "src/ui/pause_menu.gd"

MUTANTS = [
    {"name": "G1 a capture in the opening starts it over with the prologue",
     "edits": [(A1, "\treturn invasion.beat != InvasionSequence.Beat.PROLOGUE and invasion.beat != InvasionSequence.Beat.ESCAPE\n",
                "\treturn false\n")]},
    {"name": "G2 the flag outlives its load",
     "edits": [(LB, "\tagain = _retry_opening and not resume\n\t_retry_opening = false\n",
                "\tagain = _retry_opening and not resume\n")]},
    {"name": "G3 a second try keeps the sepia",
     "edits": [(INV, "\tprologue_zone.set_active(not again)\n", "\tprologue_zone.set_active(true)\n")]},
    {"name": "G4 a second try waits the whole prologue",
     "edits": [(INV, "_set_beat(Beat.PROLOGUE, again_time if again else prologue_time)",
                "_set_beat(Beat.PROLOGUE, prologue_time)")]},
    {"name": "G5 a second try starts without the black",
     "edits": [(A1, "\t\t\tfade_from_black()\n", "\t\t\tpass\n")]},
    {"name": "G6 the level never starts the opening again",
     "edits": [(A1, "\t\tinvasion.start(again)\n", "\t\tinvasion.start()\n")]},
    {"name": "G7 leaving by the pause keeps the second try",
     "edits": [(PAUSE, "\tLevelBase._retry_opening = false\n", "")]},
    {"name": "G4p a second try waits the whole prologue (the cellar part)",
     "edits": [(INV, "_set_beat(Beat.PROLOGUE, again_time if again else prologue_time)",
                "_set_beat(Beat.PROLOGUE, prologue_time)")],
     "run": CELLAR},
    {"name": "G6p the level never starts the opening again (the cellar part)",
     "edits": [(A1, "\t\tinvasion.start(again)\n", "\t\tinvasion.start()\n")],
     "run": CELLAR},
]
