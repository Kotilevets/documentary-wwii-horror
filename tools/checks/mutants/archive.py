"""Breakages of the Witness Archive's references and sources and of the epilogue's dedication (docs/ARCHITECTURE.md,
«Архив свидетеля» and «Оболочка игры: меню, пауза, эпилог, прогресс»; 27.11.2026): each must fail _test_archive or
_test_menus. Not mutated: _open_link in src/ui/archive_ui.gd (an empty link opens nothing): a test cannot watch
OS.shell_open, and since a book without a link is plain text no empty link is drawn for it to open."""

RUN = {"args": ["res://tests/test_runner.tscn", "--", "--only=_test_archive,_test_menus"], "timeout": 600}

UI = "src/ui/archive_ui.gd"
EP = "src/scenes/epilogue/epilogue.gd"
DOCS = "assets/data/archive/act2_documents.json"

MUTANTS = [
    {"name": "A1 the summons from the burned village does not name the burned villages",
     "edits": [(DOCS, '"related": ["ref_chgk", "ref_burned_villages"],', '"related": ["ref_chgk"],')]},
    {"name": "A2 a book without a link is an empty link",
     "edits": [(UI, 'out += ("• [url=%s]%s[/url]\\n" % [url, title]) if url != "" else "• %s\\n" % title',
                'out += "• [url=%s]%s[/url]\\n" % [url, title]')]},
    {"name": "A3 a source with a link is plain text",
     "edits": [(UI, 'if url != "" else "• %s\\n" % title', 'if false else "• %s\\n" % title')]},
    {"name": "A4 the dedication is never shown",
     "edits": [(EP, '\tif dedication != "":\n\t\tout.append(dedication)\n', '\tif dedication != "":\n\t\tpass\n')]},
    {"name": "A5 an empty dedication takes its line",
     "edits": [(EP, '\tif dedication != "":\n', '\tif true:\n')]},
    {"name": "A6 the dedication keeps its spaces",
     "edits": [(EP, 'var dedication := str(data.get("dedication", "")).strip_edges()',
                'var dedication := str(data.get("dedication", ""))')]},
    {"name": "A7 the epilogue plays its lines without the dedication",
     "edits": [(EP, '\tfor l in shown_lines():\n', '\tfor l in lines:\n')]},
    {"name": "A8 the epilogue reads its own file whatever data_path says",
     "edits": [(EP, 'JSON.parse_string(FileAccess.get_file_as_string(data_path))',
                'JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))')]},
]
