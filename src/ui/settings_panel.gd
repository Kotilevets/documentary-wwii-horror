class_name SettingsPanel
extends VBoxContainer
## Settings shared by the main menu and the pause menu: mouse sensitivity,
## volume, full screen, brightness (BrightnessPanel), the controls
## (ControlsPanel). Stored in GameState (user://progress.json).

signal closed

var _mouse: HSlider
var _volume: HSlider
var _fullscreen: Button
var _back: Button
var _controls_button: Button
var _controls: ControlsPanel
var _brightness_button: Button
var _brightness: BrightnessPanel
## The brightness screen was opened straight from the main menu (the first
## start): closing it closes the settings too.
var _brightness_only := false


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	add_child(MenuStyle.label("Настройки", 40, MenuStyle.BRIGHT))
	_mouse = _slider("Чувствительность мыши", 0.3, 2.5, GameState.mouse_factor(),
			func(v: float) -> void: GameState.set_setting("mouse_sensitivity", v))
	_volume = _slider("Громкость", 0.0, 1.0, float(GameState.settings.get("volume", 0.8)),
			func(v: float) -> void: GameState.set_setting("volume", v))
	_fullscreen = MenuStyle.button(_fs_text(), 26)
	_fullscreen.pressed.connect(func() -> void:
		GameState.set_setting("fullscreen", not bool(GameState.settings.get("fullscreen", false)))
		MenuStyle.set_text(_fullscreen, _fs_text()))
	add_child(_fullscreen)
	_brightness_button = MenuStyle.button("Яркость", 26)
	_brightness_button.pressed.connect(show_brightness)
	add_child(_brightness_button)
	_controls_button = MenuStyle.button("Управление", 26)
	_controls_button.pressed.connect(show_controls)
	add_child(_controls_button)
	_back = MenuStyle.button("Назад", 30)
	_back.pressed.connect(func() -> void: closed.emit())
	add_child(_back)
	_controls = ControlsPanel.new()
	_controls.visible = false
	_controls.closed.connect(_hide_sub)
	add_child(_controls)
	_brightness = BrightnessPanel.new()
	_brightness.visible = false
	_brightness.closed.connect(_close_brightness)
	add_child(_brightness)


func show_controls() -> void:
	_show_sub(_controls)
	_controls.focus()


func is_showing_controls() -> bool:
	return _controls.visible


## `only`: opened straight from the main menu; closing it closes the settings.
func show_brightness(only: bool = false) -> void:
	_brightness_only = only
	_show_sub(_brightness)
	_brightness.focus()


func is_showing_brightness() -> bool:
	return _brightness.visible


func _show_sub(panel: Control) -> void:
	for c in get_children():
		(c as CanvasItem).visible = c == panel


## Back from a screen of the settings to their list.
func _hide_sub() -> void:
	var was: Button = null
	if _controls.visible:
		was = _controls_button
	elif _brightness.visible:
		was = _brightness_button
	if was == null:
		return
	_controls.waiting = ""
	for c in get_children():
		(c as CanvasItem).visible = c != _controls and c != _brightness
	was.grab_focus()


## Seen once, the brightness screen is not shown at the start again.
func _close_brightness() -> void:
	GameState.set_setting("brightness_checked", true)
	_hide_sub()
	if _brightness_only:
		_brightness_only = false
		closed.emit()


## Esc / B in the settings: from a screen back to the settings (true);
## otherwise nothing here to go back from (false: the menu closes them).
func back() -> bool:
	if _brightness.visible:
		_close_brightness()
		return true
	if _controls.visible:
		_hide_sub()
		return true
	return false


func focus() -> void:
	_hide_sub()
	# The other menu may have changed them.
	_mouse.set_value_no_signal(GameState.mouse_factor())
	_volume.set_value_no_signal(float(GameState.settings.get("volume", 0.8)))
	MenuStyle.set_text(_fullscreen, _fs_text())
	_mouse.grab_focus()


func _slider(title: String, lo: float, hi: float, value: float, on_change: Callable) -> HSlider:
	add_child(MenuStyle.label(title, 24))
	var s := MenuStyle.slider(lo, hi, value)
	s.value_changed.connect(on_change)
	add_child(s)
	return s


func _fs_text() -> String:
	return "Во весь экран: " + ("да" if bool(GameState.settings.get("fullscreen", false)) else "нет")
