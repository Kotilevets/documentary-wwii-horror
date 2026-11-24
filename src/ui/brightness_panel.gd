class_name BrightnessPanel
extends VBoxContainer
## "Яркость" in the settings (docs/ARCHITECTURE.md, "Яркость"): two faint
## windows of an izba on black, drawn the way the game draws its darkest
## tones (brightness_test.gdshader). The player moves the slider until the
## left window is barely visible and the right one is gone. The main menu
## shows it once before the first game (GameState.needs_brightness_check).

signal closed

const TEST_SHADER := preload("res://src/ui/brightness_test.gdshader")
const TEST_SIZE := Vector2(640, 220)

var slider: HSlider
var test: ColorRect
var _default: Button
var _done: Button


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	add_child(MenuStyle.label("Яркость", 40, MenuStyle.BRIGHT))
	test = ColorRect.new()
	test.custom_minimum_size = TEST_SIZE
	test.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = TEST_SHADER
	mat.set_shader_parameter("aspect", TEST_SIZE.x / TEST_SIZE.y)
	test.material = mat
	add_child(test)
	var hint := MenuStyle.label("Двигайте ползунок, пока левое окно не станет едва различимым, а правое не исчезнет.", 22)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = TEST_SIZE.x
	add_child(hint)
	slider = MenuStyle.slider(GameState.BRIGHTNESS_MIN, GameState.BRIGHTNESS_MAX, GameState.brightness(), TEST_SIZE.x)
	slider.value_changed.connect(func(v: float) -> void: GameState.set_setting("brightness", v))
	add_child(slider)
	_default = MenuStyle.button("По умолчанию", 24)
	_default.pressed.connect(func() -> void: slider.value = float(GameState.DEFAULT_SETTINGS["brightness"]))
	add_child(_default)
	_done = MenuStyle.button("Готово", 30)
	_done.pressed.connect(func() -> void: closed.emit())
	add_child(_done)


func focus() -> void:
	slider.set_value_no_signal(GameState.brightness())
	slider.grab_focus()
