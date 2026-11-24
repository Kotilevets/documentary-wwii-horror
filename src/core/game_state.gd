extends Node
## Progress between levels and between sessions (user://progress.json):
## which acts are open, whether the game has been finished, the Witness
## Archive across the whole game, settings (mouse, volume, window).
## The archive is kept across new games: what the witness once found stays
## in it, like a museum the player fills.

signal settings_changed

const SAVE_PATH := "user://progress.json"
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
		"brightness": 1.0, "brightness_checked": false}
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	log_line("start")
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


## A scene has opened: the main menu, an act, the dream, the epilogue.
## Not in headless runs and renders: the tests open scenes hundreds of times.
static func log_scene(scene: Node) -> void:
	if Player.is_scripted_run():
		return
	var scene_name := scene.scene_file_path.get_file().get_basename()
	log_line("scene " + (scene_name if scene_name != "" else str(scene.name)))


## "Выход" in the main menu.
func quit_game() -> void:
	log_line("quit")
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
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


func save() -> void:
	# Renders and headless runs do not touch the player's real progress.
	if save_path == SAVE_PATH and Player.is_scripted_run():
		return
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_warning("GameState: cannot write %s" % save_path)
		return
	f.store_string(JSON.stringify({
		"reached": reached, "last_act": last_act, "finished": finished,
		"archive": archive, "settings": settings,
	}, "  "))


func load_progress() -> void:
	reset()
	if not FileAccess.file_exists(save_path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(d) != TYPE_DICTIONARY:
		return
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
