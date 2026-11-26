class_name MenuStyle
extends RefCounted
## Look of the menus: black and white, flat text buttons, the focused one
## white with a dash before it. No colour (CLAUDE.md, 2).

const DIM := Color(0.5, 0.5, 0.49)
const BRIGHT := Color(0.95, 0.95, 0.93)
const OFF := Color(0.26, 0.26, 0.26)


static func button(text: String, size: int = 34) -> Button:
	var b := Button.new()
	b.set_meta("label", text)
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", DIM)
	b.add_theme_color_override("font_hover_color", BRIGHT)
	b.add_theme_color_override("font_focus_color", BRIGHT)
	b.add_theme_color_override("font_pressed_color", BRIGHT)
	b.add_theme_color_override("font_hover_pressed_color", BRIGHT)
	b.add_theme_color_override("font_disabled_color", OFF)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.focus_entered.connect(func() -> void: b.text = "— " + str(b.get_meta("label")))
	b.focus_exited.connect(func() -> void: b.text = str(b.get_meta("label")))
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			b.grab_focus())
	return b


## Change a menu button's text, keeping the focus dash.
static func set_text(b: Button, text: String) -> void:
	b.set_meta("label", text)
	b.text = ("— " + text) if b.has_focus() else text


static func label(text: String, size: int = 26, color: Color = DIM) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## A grey slider with a light grabber: no theme accent colour.
static func slider(lo: float, hi: float, value: float, width: float = 420.0) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(width, 24)
	s.focus_mode = Control.FOCUS_ALL
	var line := StyleBoxFlat.new()
	line.bg_color = Color(0.3, 0.3, 0.3)
	line.content_margin_top = 2
	line.content_margin_bottom = 2
	var filled := StyleBoxFlat.new()
	filled.bg_color = Color(0.6, 0.6, 0.58)
	var lit := StyleBoxFlat.new()
	lit.bg_color = BRIGHT
	s.add_theme_stylebox_override("slider", line)
	s.add_theme_stylebox_override("grabber_area", filled)
	s.add_theme_stylebox_override("grabber_area_highlight", lit)
	s.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return s


## Full-screen black with archive film grain.
static func backdrop() -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = preload("res://src/ui/film_grain.gdshader")
	r.material = m
	return r


## Focus the first enabled button under `root`.
static func focus_first(root: Node) -> void:
	for c in root.get_children():
		if c is Button and not (c as Button).disabled and (c as Button).visible:
			(c as Button).grab_focus()
			return
