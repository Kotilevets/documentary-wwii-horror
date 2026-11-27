extends Node
## Progress between levels and between sessions (user://progress.json):
## which acts are open, whether the game has been finished, the Witness
## Archive across the whole game, settings (mouse, volume, window).
## The archive is kept across new games: what the witness once found stays
## in it, like a museum the player fills.
## The file is written through a temporary one and keeps the one before as .bak;
## an unreadable file is put aside as .broken, not wiped (docs/ARCHITECTURE.md,
## "Прогресс"). The marks in the run log - start, build, scenes, frames, quit -
## are written here too ("Метки в журнале запуска").

signal settings_changed

const FrameStats := preload("res://src/core/frame_stats.gd")
const SAVE_PATH := "user://progress.json"
## The format of progress.json (its "version"; migrate()). 0 - the files before
## 27.11.2026, without the key.
const FORMAT_VERSION := 1
## Where the playtest builder puts its stamp: override.cfg next to the pack
## (tools/make_playtest_build.py) - the build date, the commit, the pack's size and SHA-256.
const BUILD_SETTING := "application/config/playtest_build"
## Frames after a scene opens that are not counted: the first one sets the clock, the
## two after it carry the loading.
const FRAMES_SKIPPED := 2
const ITEMS_DIR := "res://assets/data/items"
const ACTS: Array[Dictionary] = [
	{"title": "Акт I. Деревня", "scene": "res://src/scenes/act1_village/act1_village.tscn"},
	{"title": "Акт II. Дорога", "scene": "res://src/scenes/act2_road/act2_road.tscn"},
	{"title": "Акт III. Партизанский отряд", "scene": "res://src/scenes/act3_garrison/act3_garrison.tscn"},
]
const MENU_SCENE := "res://src/ui/main_menu.tscn"
## "keys": action -> physical keycode, only the keys changed by the player
## (Controls, the "Управление" screen).
const DEFAULT_SETTINGS := {"mouse_sensitivity": 1.0, "volume": 0.8, "fullscreen": false, "keys": {},
		"brightness": 1.0, "brightness_checked": false, "sound_delay_ms": 0}
## Range of the brightness (the gamma lift in film_common.gdshaderinc).
const BRIGHTNESS_MIN := 0.7
const BRIGHTNESS_MAX := 1.6

## Tests point this elsewhere.
var save_path := SAVE_PATH
## Number of acts the player has reached (1..ACTS.size()).
var reached := 1
## Index of the act played last (for "Продолжить").
var last_act := 0
var finished := false
## Document ids found in any playthrough, in order of finding.
var archive: Array[String] = []
var settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)
## Which file the last load_progress() read: "" (none - a new game), the file
## itself, or its .tmp or .bak (tests).
var loaded_from := ""
## Why the progress is not written this run ("" - it is): the file is of a newer
## format, or an unreadable file could not be put aside.
var _no_save := ""
## The part of the game whose frames are counted ("game: frames"); "" - none.
var _frames_scene := ""
var _frames := FrameStats.new()
var _frame_usec := 0
var _frames_skip := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	log_line("start")
	log_line("build " + build_stamp())
	Controls.install_pad()
	load_progress()
	apply_settings()
	Inventory.document_collected.connect(_on_document_collected)
	# Renders: `-- --demo-progress` shows the menus as after a full game
	# (in memory only: scripted runs never save to the real file).
	if Player.is_scripted_run() and OS.get_cmdline_user_args().has("--demo-progress"):
		reached = ACTS.size()
		last_act = ACTS.size() - 1
		archive = collectible_documents()


## A line in the run log (user://logs/godot.log) with the local time.
## Godot itself writes no time and nothing at a normal exit, so playtest logs
## are matched to the tester's notes by these lines (docs/ARCHITECTURE.md,
## "Метки в журнале запуска").
static func log_text(what: String, datetime: Dictionary) -> String:
	return "game: %s %04d-%02d-%02d %02d:%02d:%02d" % [what, datetime.year, datetime.month, datetime.day,
			datetime.hour, datetime.minute, datetime.second]


static func log_line(what: String) -> void:
	print(log_text(what, Time.get_datetime_dict_from_system()))


## Which build runs: the playtest builder's stamp, or "sources" (the editor, the
## tests, renders: no override.cfg with a stamp).
static func build_stamp() -> String:
	var stamp := str(ProjectSettings.get_setting(BUILD_SETTING, "")).strip_edges()
	return stamp if stamp != "" else "sources"


## A scene has opened: the main menu, an act, the dream, the epilogue. The frames of
## the part before it go to the log first, then this one's are counted.
## Not in headless runs and renders: the tests open scenes hundreds of times.
func log_scene(scene: Node) -> void:
	if Player.is_scripted_run():
		return
	var scene_name := scene.scene_file_path.get_file().get_basename()
	if scene_name == "":
		scene_name = str(scene.name)
	_log_frames()
	log_line("scene " + scene_name)
	start_frames(scene_name)


## Starts counting the frames of a part of the game anew (log_scene; tests).
func start_frames(scene_name: String) -> void:
	_frames_scene = scene_name
	_frames = FrameStats.new()
	_frame_usec = 0
	_frames_skip = FRAMES_SKIPPED


## The "frames" line of the part counted so far ("" if no frame was counted), and
## the counting stops.
func take_frames() -> String:
	var line := ""
	if _frames_scene != "" and _frames.count > 0:
		line = "frames %s %s" % [_frames_scene, _frames.summary()]
	_frames_scene = ""
	return line


func _log_frames() -> void:
	var line := take_frames()
	if line != "":
		log_line(line)


## The time between frames by the real clock (not the game's, which pauses and
## scales); frames while the window is not in focus are not counted.
func _process(_delta: float) -> void:
	if _frames_scene == "":
		return
	if DisplayServer.get_name() != "headless" and not get_window().has_focus():
		_frame_usec = 0
		return
	var now := Time.get_ticks_usec()
	if _frame_usec > 0:
		if _frames_skip > 0:
			_frames_skip -= 1
		else:
			_frames.add((now - _frame_usec) / 1000.0)
	_frame_usec = now


## "Выход" in the main menu.
func quit_game() -> void:
	_log_frames()
	log_line("quit")
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_log_frames()
		log_line("quit (window closed)")


func act_index(scene_path: String) -> int:
	for i in ACTS.size():
		if ACTS[i].scene == scene_path:
			return i
	return -1


## A level has started: open it, remember it for "Продолжить".
func act_started(scene_path: String) -> void:
	act_reached(scene_path)


## The act is open and "Продолжить" leads to it (also called by the dream
## between acts for the act after it). Not an act - nothing happens.
func act_reached(scene_path: String) -> void:
	var i := act_index(scene_path)
	if i < 0:
		return
	last_act = i
	reached = maxi(reached, i + 1)
	save()


func game_finished() -> void:
	finished = true
	reached = ACTS.size()
	save()


func is_open(i: int) -> bool:
	return i >= 0 and i < reached


## Every document id a pickup in the game can give.
func collectible_documents() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(ITEMS_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		var path := ITEMS_DIR.path_join(f.trim_suffix(".remap"))
		if path.get_extension() != "tres":
			continue
		var item := load(path) as ItemData
		if item != null and item.document_id != "" and not out.has(item.document_id):
			out.append(item.document_id)
	return out


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	apply_settings()
	save()


func apply_settings() -> void:
	var keys = settings.get("keys", {})
	Controls.apply_keys(keys if typeof(keys) == TYPE_DICTIONARY else {})
	RenderingServer.global_shader_parameter_set("g_brightness", brightness())
	var vol := clampf(float(settings.get("volume", 0.8)), 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(vol, 0.0001)))
	AudioServer.set_bus_mute(0, vol <= 0.001)
	if DisplayServer.get_name() != "headless":
		var fs: bool = settings.get("fullscreen", false)
		var mode := DisplayServer.window_get_mode()
		if fs and mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif not fs and mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	settings_changed.emit()


## The player's brightness: 1.0 - the picture as graded, more - lighter shadows.
func brightness() -> float:
	return clampf(float(settings.get("brightness", 1.0)), BRIGHTNESS_MIN, BRIGHTNESS_MAX)


## The brightness screen has not been confirmed yet: the menu shows it first.
func needs_brightness_check() -> bool:
	return not bool(settings.get("brightness_checked", false))


## Multiplier for the player's mouse look.
func mouse_factor() -> float:
	return clampf(float(settings.get("mouse_sensitivity", 1.0)), 0.2, 3.0)


## «Задержка звука»: what wireless headphones add and the engine cannot see
## (HeartbeatAudio.lead_time; docs/ARCHITECTURE.md, «Удар слышен в такт»).
const SOUND_DELAY_MAX_MS := 300.0


## The player's extra sound delay, in seconds (0..0.3).
func sound_delay() -> float:
	return clampf(float(settings.get("sound_delay_ms", 0)), 0.0, SOUND_DELAY_MAX_MS) / 1000.0


## Renders and headless runs neither write the player's real progress nor put it aside.
func _real_file_kept() -> bool:
	return save_path == SAVE_PATH and Player.is_scripted_run()


## Written whole to <file>.tmp and checked, then the old file becomes <file>.bak and
## the new one takes its place: a write cut short leaves the last good progress.
func save() -> void:
	if _real_file_kept() or _no_save != "":
		return
	var text := JSON.stringify({
		"version": FORMAT_VERSION, "reached": reached, "last_act": last_act, "finished": finished,
		"archive": archive, "settings": settings,
	}, "  ")
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("GameState: cannot write %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return
	f.store_string(text)
	f.close()
	# A full disk leaves less than was given: then the old file stays as it was.
	if FileAccess.get_file_as_string(tmp) != text:
		push_warning("GameState: %s was not written whole; %s is left as it was" % [tmp, save_path])
		DirAccess.remove_absolute(tmp)
		return
	if FileAccess.file_exists(save_path):
		var err := DirAccess.rename_absolute(save_path, save_path + ".bak")
		if err != OK:
			push_warning("GameState: cannot move %s to .bak (%s); it is left as it was" % [save_path,
					error_string(err)])
			return
	var moved := DirAccess.rename_absolute(tmp, save_path)
	if moved != OK:
		push_warning("GameState: cannot move %s to %s (%s); the next start reads it there" % [tmp,
				save_path, error_string(moved)])


## The progress in `path`, or null if there is none to read there: no file, an empty
## one, one cut short, not a JSON object. Without an error in the log: an unreadable
## file is expected here.
static func read_progress(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	return json.data if typeof(json.data) == TYPE_DICTIONARY else null


## An older file brought to FORMAT_VERSION, one step after another. 0 -> 1 (27.11.2026):
## the same keys, only "version" is new. The next change of the format adds its step
## here (`if version < 2: ...`).
static func migrate(d: Dictionary, _version: int) -> Dictionary:
	var out := d.duplicate(true)
	out["version"] = FORMAT_VERSION
	return out


## The file, else its .tmp (a write that could not be moved into place: always newer
## than .bak), else its .bak. An unreadable file is put aside as .broken, so that the
## next save cannot push the good .bak out with it.
func load_progress() -> void:
	reset()
	loaded_from = ""
	_no_save = ""
	var from := save_path
	var d = read_progress(save_path)
	if d == null and FileAccess.file_exists(save_path) and not _real_file_kept():
		var broken := save_path + ".broken"
		if DirAccess.rename_absolute(save_path, broken) == OK:
			log_line("%s unreadable, kept as %s" % [save_path.get_file(), broken.get_file()])
		else:
			_no_save = "cannot move %s aside" % save_path.get_file()
			log_line(_no_save + ": progress is not saved this run")
	if d == null:
		for other in [save_path + ".tmp", save_path + ".bak"]:
			d = read_progress(other)
			if d != null:
				from = other
				log_line("progress read from " + other.get_file())
				break
	if d == null:
		return
	loaded_from = from.get_file()
	var version := int(d.get("version", 0))
	if version > FORMAT_VERSION:
		# An older build must not wipe what it cannot read: read what it knows, keep the file.
		if _no_save == "":
			_no_save = "%s is version %d, newer than this build (%d)" % [from.get_file(), version,
					FORMAT_VERSION]
			log_line(_no_save + ": not overwritten")
	else:
		d = migrate(d, version)
	reached = clampi(int(d.get("reached", 1)), 1, ACTS.size())
	last_act = clampi(int(d.get("last_act", 0)), 0, reached - 1)
	finished = bool(d.get("finished", false))
	for id in d.get("archive", []):
		if not archive.has(str(id)):
			archive.append(str(id))
	var s = d.get("settings", {})
	if typeof(s) == TYPE_DICTIONARY:
		for k in DEFAULT_SETTINGS:
			if s.has(k):
				settings[k] = s[k]


## Forget everything (tests; not offered in the menu).
func reset() -> void:
	reached = 1
	last_act = 0
	finished = false
	archive.clear()
	settings = DEFAULT_SETTINGS.duplicate(true)
	Controls.apply_keys({})


func _on_document_collected(id: String) -> void:
	if not archive.has(id):
		archive.append(id)
		save()
