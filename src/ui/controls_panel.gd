class_name ControlsPanel
extends VBoxContainer
## "Управление" in the settings: every action with its key and its gamepad
## button. A key is changed by choosing its row and pressing and releasing
## the new key (Esc - leave it as it was); a key that belonged to another action goes
## to that action instead (Controls.rebind). The gamepad layout is fixed.
## The only place the game names its buttons (CLAUDE.md, 2).

signal closed

## Width of the action column: the longest name must fit, or it pushes
## its key out of the key column (a test measures every name).
const NAME_WIDTH := 600.0

## Action whose new key is awaited ("" - none).
var waiting := ""
## The key pressed while waiting: it becomes the new key when it is
## released (KEY_NONE - none yet).
var _pressed: int = KEY_NONE
var _keys := {}  # action -> Button
var _reset: Button
var _back: Button


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	add_child(MenuStyle.label("Управление", 40, MenuStyle.BRIGHT))
	add_child(_row_label("действие", "клавиша", "геймпад", MenuStyle.OFF))
	for row in Controls.ACTIONS:
		var action: String = row[0]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 0)
		line.add_child(_cell(str(row[1]), NAME_WIDTH))
		var key := MenuStyle.button("", 22)
		key.custom_minimum_size.x = 200
		# No padding: the list has to fit under the menu's title.
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			key.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		key.pressed.connect(_wait_for.bind(action))
		_keys[action] = key
		line.add_child(key)
		line.add_child(_cell(str(Controls.PAD_NAMES.get(action, "")), 200))
		add_child(line)
	for row in Controls.FIXED:
		add_child(_row_label(str(row[0]), str(row[1]), str(row[2]), MenuStyle.DIM))
	var gap := Control.new()
	gap.custom_minimum_size.y = 12
	add_child(gap)
	_reset = MenuStyle.button("Вернуть клавиши по умолчанию", 24)
	_reset.pressed.connect(func() -> void:
		waiting = ""
		GameState.set_setting("keys", {})
		refresh())
	add_child(_reset)
	_back = MenuStyle.button("Назад", 30)
	_back.pressed.connect(func() -> void:
		waiting = ""
		closed.emit())
	add_child(_back)
	refresh()


func focus() -> void:
	refresh()
	(_keys[Controls.ACTIONS[0][0]] as Button).grab_focus()


func refresh() -> void:
	for action in _keys:
		var b := _keys[action] as Button
		MenuStyle.set_text(b, "…" if action == waiting else Controls.key_name(Controls.key_of(action)))


func _wait_for(action: String) -> void:
	waiting = action
	_pressed = KEY_NONE
	refresh()


## While a key is awaited, the key pressed and then released is the new key;
## Esc cancels on its press. Taken on the release, so that Alt + Tab, Win or
## Ctrl + Esc, whose first key reaches the game before the system takes the
## window, never becomes one: their release goes to the other window, and
## the focus loss cancels the wait (_notification). Win / Cmd are never
## taken. Every key press and release is the screen's while it waits; mouse
## and gamepad do not count (the gamepad layout is fixed).
func _input(event: InputEvent) -> void:
	if waiting == "" or not is_visible_in_tree():
		return
	var k := event as InputEventKey
	if k == null:
		return
	get_viewport().set_input_as_handled()
	if k.echo:
		return
	var code := int(k.physical_keycode) if k.physical_keycode != KEY_NONE else int(k.keycode)
	if k.pressed:
		if code == KEY_ESCAPE:
			_stop_waiting()
		elif code != KEY_META and code != KEY_NONE:
			_pressed = code
		return
	# A release with no press while waiting (a key held down while the row was
	# chosen with the mouse) is not a key, nor is one with no code. The Enter
	# that chooses the row never gets here: the button fires on its release.
	if _pressed == KEY_NONE or code != _pressed:
		return
	var keys = GameState.settings.get("keys", {})
	GameState.set_setting("keys", Controls.rebind(keys if typeof(keys) == TYPE_DICTIONARY else {}, waiting, code))
	_stop_waiting()


func _notification(what: int) -> void:
	# Alt + Tab, Ctrl + Esc: the window is gone before the key is released.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and waiting != "":
		waiting = ""
		_pressed = KEY_NONE
		refresh()


func _stop_waiting() -> void:
	var action := waiting
	waiting = ""
	_pressed = KEY_NONE
	refresh()
	(_keys[action] as Button).grab_focus()


func _row_label(a: String, b: String, c: String, color: Color) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 0)
	line.add_child(_cell(a, NAME_WIDTH, color))
	line.add_child(_cell(b, 200, color))
	line.add_child(_cell(c, 200, color))
	return line


func _cell(text: String, width: float, color: Color = MenuStyle.DIM) -> Label:
	var l := MenuStyle.label(text, 22, color)
	l.custom_minimum_size.x = width
	return l
