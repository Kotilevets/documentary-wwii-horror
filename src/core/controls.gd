class_name Controls
extends RefCounted
## Controls (docs/ARCHITECTURE.md, "Управление"): the keyboard keys the
## player can rebind (GameState.settings["keys"], the "Управление" screen in
## the settings), the gamepad layout (fixed, Xbox names) and the right stick
## for looking. The world shows no button prompts (CLAUDE.md, 2): this list
## lives only in the settings.

## Rebindable actions in the order of the screen: [action, name].
const ACTIONS := [
	["move_forward", "Вперёд"],
	["move_back", "Назад"],
	["move_left", "Влево (в сумке — выбрать)"],
	["move_right", "Вправо (в сумке — выбрать)"],
	["sprint", "Бежать"],
	["crouch", "Присесть"],
	["interact", "Взять, открыть, спрятаться; в сумке — применить"],
	["hold_breath", "Задержать дыхание"],
	["lean", "Выглянуть: держать и шагнуть вбок или вперёд"],
	["inventory", "Сумка"],
	["archive_journal", "Архив свидетеля"],
]
## Rows that cannot be changed: [name, keyboard and mouse, gamepad].
const FIXED := [
	["Осмотреться", "мышь", "правый стик"],
	["Ответ на допросе", "1, 2, 3", "крестовина, A"],
	["Пауза, назад", "Esc", "Start, B"],
]
## Gamepad buttons as the screen names them.
const PAD_NAMES := {
	"move_forward": "левый стик", "move_back": "левый стик",
	"move_left": "левый стик", "move_right": "левый стик",
	"sprint": "LT", "crouch": "LB", "interact": "A", "hold_breath": "RT", "lean": "RB",
	"inventory": "Y", "archive_journal": "View",
}
const LOOK_ACTIONS := ["look_left", "look_right", "look_up", "look_down"]
const STICK_DEADZONE := 0.15
## Key names the screen shows in Russian.
const KEY_NAMES := {"Space": "Пробел", "Escape": "Esc", "Enter": "Enter"}

## Default keys: action -> physical keycode, from project.godot as this
## system needs them (platform_defaults).
static var _defaults := {}


## Gamepad events and the look actions; called once at start (GameState).
static func install_pad() -> void:
	for a in LOOK_ACTIONS:
		if not InputMap.has_action(a):
			InputMap.add_action(a, STICK_DEADZONE)
	_motion("move_left", JOY_AXIS_LEFT_X, -1.0)
	_motion("move_right", JOY_AXIS_LEFT_X, 1.0)
	_motion("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_motion("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_motion("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_motion("look_right", JOY_AXIS_RIGHT_X, 1.0)
	_motion("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_motion("look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_motion("sprint", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_motion("hold_breath", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_button("crouch", JOY_BUTTON_LEFT_SHOULDER)
	_button("lean", JOY_BUTTON_RIGHT_SHOULDER)
	_button("interact", JOY_BUTTON_A)
	_button("inventory", JOY_BUTTON_Y)
	_button("archive_journal", JOY_BUTTON_BACK)
	_button("ui_cancel", JOY_BUTTON_START)


static func _motion(action: String, axis: JoyAxis, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	if not InputMap.action_has_event(action, e):
		InputMap.action_add_event(action, e)


static func _button(action: String, button: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	if not InputMap.action_has_event(action, e):
		InputMap.action_add_event(action, e)


static func _capture_defaults() -> void:
	if not _defaults.is_empty():
		return
	var found := {}
	for row in ACTIONS:
		found[row[0]] = key_of(row[0])
	_defaults = platform_defaults(found, OS.get_name())


## The keys from project.godot as `os_name` needs them. On macOS control +
## Space switches the keyboard layout (a system shortcut), so with crouch on
## Ctrl the boy could not crouch and hold his breath at once: crouch is C
## there (docs/ARCHITECTURE.md, "Клавиатура по умолчанию").
static func platform_defaults(keys: Dictionary, os_name: String) -> Dictionary:
	var out := keys.duplicate()
	if os_name == "macOS" and int(out.get("crouch", 0)) == KEY_CTRL:
		out["crouch"] = KEY_C
	return out


static func default_key(action: String) -> int:
	_capture_defaults()
	return int(_defaults.get(action, 0))


## The physical key of an action now (0: none).
static func key_of(action: String) -> int:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var k := e as InputEventKey
			return int(k.physical_keycode) if k.physical_keycode != KEY_NONE else int(k.keycode)
	return 0


## Puts the keys in the InputMap: `overrides` (action -> physical keycode)
## over the defaults (project.godot as this system needs them, platform_defaults).
static func apply_keys(overrides: Dictionary) -> void:
	_capture_defaults()
	var codes := {}
	for row in ACTIONS:
		var a: String = row[0]
		codes[a] = int(overrides.get(a, _defaults.get(a, 0)))
	# A key saved for one action before another got it by default (a save
	# from before «Выглянуть» took Q): the default gives way and takes the
	# overriding action's own default - the swap rebind() makes - or none.
	for a in codes:
		var code: int = codes[a]
		if overrides.has(a) or code == 0:
			continue
		for b in overrides:
			if b != a and codes.get(b, 0) == code:
				code = int(_defaults.get(b, 0))
				break
		if code != codes[a] and codes.values().has(code):
			code = 0
		codes[a] = code
	for row in ACTIONS:
		var a: String = row[0]
		var code: int = codes[a]
		for e in InputMap.action_get_events(a):
			if e is InputEventKey:
				InputMap.action_erase_event(a, e)
		if code != 0:
			var k := InputEventKey.new()
			k.physical_keycode = code as Key
			InputMap.action_add_event(a, k)


## New overrides after giving `action` the key `code`: an action that had
## that key gets this action's old one, so no key does two things.
## Entries equal to the defaults are dropped.
static func rebind(overrides: Dictionary, action: String, code: int) -> Dictionary:
	_capture_defaults()
	var out := {}
	for a in overrides:
		out[str(a)] = int(overrides[a])
	var old := key_of(action)
	for row in ACTIONS:
		var other: String = row[0]
		if other != action and key_of(other) == code:
			out[other] = old
	out[action] = code
	for a in out.keys():
		if int(out[a]) == int(_defaults.get(a, -1)):
			out.erase(a)
	return out


## A key as the screen shows it: the letter on this keyboard layout.
static func key_name(code: int) -> String:
	if code == 0:
		return "—"
	var k := code
	if DisplayServer.get_name() != "headless":
		k = DisplayServer.keyboard_get_keycode_from_physical(code as Key)
	var s := OS.get_keycode_string(k as Key)
	return str(KEY_NAMES.get(s, s))
