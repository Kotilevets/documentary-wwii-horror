extends Control
## Main menu (the game's main scene): continue from the last act, a new
## game, the acts reached so far, the Witness Archive of everything found,
## settings, exit. Black and white with archive film grain.
## Before the first game it opens on the brightness screen (BrightnessPanel).
## Renders: `-- --demo-progress` (GameState), `-- --show-controls`,
## `-- --show-brightness`.

const MENU_DATA := "res://assets/data/ui/menu.json"
const ARCHIVE_UI := preload("res://src/ui/archive_ui.gd")

var _main: VBoxContainer
var _acts: VBoxContainer
var _settings: SettingsPanel
var _archive: ArchiveUI
var continue_button: Button
var archive_button: Button
var act_buttons: Array[Button] = []


func _ready() -> void:
	GameState.log_scene(self)
	get_tree().paused = false
	PanicSystem.reset()
	Perception.reset()
	Stealth.reset_cover()
	Inventory.clear()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if not Player.is_scripted_run():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build()
	_show(_main)
	# Renders: `-- --show-controls` opens Настройки -> Управление.
	var args := OS.get_cmdline_user_args()
	if Player.is_scripted_run() and args.has("--show-controls"):
		_show(_settings)
		_settings.show_controls()
	elif wants_brightness_check() or (Player.is_scripted_run() and args.has("--show-brightness")):
		_show(_settings)
		_settings.show_brightness(true)


## The first start (never in renders and headless runs: they leave the real
## progress alone).
func wants_brightness_check() -> bool:
	return GameState.needs_brightness_check() and not Player.is_scripted_run()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _main.visible and not _archive.is_open:
		if not (_settings.visible and _settings.back()):
			_show(_main)
		get_viewport().set_input_as_handled()


func start_act(i: int) -> void:
	if not GameState.is_open(i):
		return
	get_tree().change_scene_to_file(GameState.ACTS[i].scene)


func _build() -> void:
	add_child(MenuStyle.backdrop())
	var data = JSON.parse_string(FileAccess.get_file_as_string(MENU_DATA))
	var d: Dictionary = data if typeof(data) == TYPE_DICTIONARY else {}
	var title := MenuStyle.label(str(d.get("title", "")), 72, MenuStyle.BRIGHT)
	title.position = Vector2(160, 170)
	add_child(title)
	var sub := MenuStyle.label(str(d.get("subtitle", "")), 28)
	sub.position = Vector2(164, 270)
	add_child(sub)

	_main = _column()
	var last := clampi(GameState.last_act, 0, GameState.reached - 1)
	continue_button = MenuStyle.button("Продолжить: " + str(GameState.ACTS[last].title))
	continue_button.pressed.connect(start_act.bind(last))
	continue_button.visible = GameState.reached > 1 or GameState.last_act > 0
	_main.add_child(continue_button)
	var new_game := MenuStyle.button("Новая игра")
	new_game.pressed.connect(start_act.bind(0))
	_main.add_child(new_game)
	var acts := MenuStyle.button("Акты")
	acts.pressed.connect(func() -> void: _show(_acts))
	_main.add_child(acts)
	archive_button = MenuStyle.button("Архив свидетеля")
	archive_button.disabled = GameState.archive.is_empty()
	archive_button.pressed.connect(func() -> void: _archive.open_journal())
	_main.add_child(archive_button)
	var settings := MenuStyle.button("Настройки")
	settings.pressed.connect(func() -> void: _show(_settings))
	_main.add_child(settings)
	var quit := MenuStyle.button("Выход")
	quit.pressed.connect(GameState.quit_game)
	_main.add_child(quit)

	_acts = _column()
	for i in GameState.ACTS.size():
		var b := MenuStyle.button(str(GameState.ACTS[i].title))
		b.disabled = not GameState.is_open(i)
		b.pressed.connect(start_act.bind(i))
		_acts.add_child(b)
		act_buttons.append(b)
	var back := MenuStyle.button("Назад", 30)
	back.pressed.connect(func() -> void: _show(_main))
	_acts.add_child(back)

	_settings = SettingsPanel.new()
	_settings.position = Vector2(160, 380)
	_settings.closed.connect(func() -> void: _show(_main))
	add_child(_settings)

	_archive = ARCHIVE_UI.new()
	_archive.recapture_mouse = false
	add_child(_archive)


func _column() -> VBoxContainer:
	var c := VBoxContainer.new()
	c.position = Vector2(160, 380)
	c.add_theme_constant_override("separation", 10)
	add_child(c)
	return c


func _show(panel: Control) -> void:
	for p in [_main, _acts, _settings]:
		(p as Control).visible = p == panel
	if panel == _settings:
		_settings.focus()
	else:
		MenuStyle.focus_first(panel)
