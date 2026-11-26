extends CanvasLayer
## Pause (Esc) in any level: continue, settings, restart the act, main
## menu. An autoload: it gets Esc only after the level's own views (the
## archive, the pass check) have had their turn, and opens only when the
## game is not already paused by one of them. It also opens by itself when
## the game window loses focus, or when a level lands after it lost it
## (docs/ARCHITECTURE.md, «Пауза»).

var is_open := false
## False from the moment another window takes the focus until it comes back.
var _app_focused := true
var _root: Control
var _list: VBoxContainer
var _settings: SettingsPanel


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false
	get_tree().scene_changed.connect(_on_scene_changed)


func can_open() -> bool:
	return not is_open and not get_tree().paused and get_tree().get_first_node_in_group("levels") != null


func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_IN and what != NOTIFICATION_APPLICATION_FOCUS_OUT:
		return
	if not Player.is_scripted_run():
		focus_changed(what == NOTIFICATION_APPLICATION_FOCUS_IN)


## Another window took the focus (Alt + Tab, Start on Ctrl + Esc, a system
## monitor) or gave it back. Losing it pauses the level: it must not go on
## behind that window and get the boy caught.
func focus_changed(focused: bool) -> void:
	_app_focused = focused
	if not focused:
		focus_lost()


## Opens the pause where Esc would: on a level, not over another open view.
func focus_lost() -> void:
	if can_open():
		open()


## A scene has landed. If the focus went while it was loading, there was no
## level to pause then (change_scene_to_file drops the old level at once and
## adds the new one a frame later), so the new one is paused now. Stays out
## of scripted runs: there _app_focused never changes.
func _on_scene_changed() -> void:
	if not _app_focused:
		focus_lost()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if is_open:
		if _settings.visible:
			if not _settings.back():
				_show_list()
		elif Flicker.allow_swap():  # the pause comes and goes no faster than a flash can bear
			close()
	elif can_open():
		if Flicker.allow_swap():
			open()
	else:
		return
	get_viewport().set_input_as_handled()


func open() -> void:
	is_open = true
	get_tree().paused = true
	_root.visible = true
	_show_list()
	if not Player.is_scripted_run():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	get_tree().paused = false
	if not Player.is_scripted_run():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func restart_act() -> void:
	_leave()
	get_tree().reload_current_scene()


func to_main_menu() -> void:
	_leave()
	get_tree().change_scene_to_file(GameState.MENU_SCENE)


func _leave() -> void:
	# Leaving on the black after a capture or a mine: that reload, which
	# would have gone back to the checkpoint, is not coming.
	LevelBase._resume_after_intro = false
	is_open = false
	_root.visible = false
	get_tree().paused = false


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	_list = VBoxContainer.new()
	_list.position = Vector2(160, 380)
	_list.add_theme_constant_override("separation", 10)
	_root.add_child(_list)
	_list.add_child(MenuStyle.label("Пауза", 40, MenuStyle.BRIGHT))
	var items := [["Продолжить", close], ["Настройки", _show_settings],
			["Начать акт заново", restart_act], ["Главное меню", to_main_menu]]
	for it in items:
		var b := MenuStyle.button(it[0])
		b.pressed.connect(it[1])
		_list.add_child(b)
	_settings = SettingsPanel.new()
	_settings.position = Vector2(160, 380)
	_settings.closed.connect(_show_list)
	_root.add_child(_settings)


func _show_list() -> void:
	_settings.visible = false
	_list.visible = true
	MenuStyle.focus_first(_list)


func _show_settings() -> void:
	_list.visible = false
	_settings.visible = true
	_settings.focus()
