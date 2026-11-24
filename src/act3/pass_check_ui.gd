class_name PassCheckUI
extends CanvasLayer
## The pass check at the dugout table: the genuine sample on the left, the
## detachment's forgeries on the right, one at a time. The boy compares the
## stamp, the date and the route and takes one. Clean scan: no distortion
## while looking (Perception suppression); the game is paused.

signal pass_chosen(id: String)
signal closed

var is_open := false
var index := 0
var data: Dictionary = {}

var _root: Control
var _sample: PassView
var _candidate: PassView
var _counter: Label
var _today: Label
## The key press that opened the view must not also pick a pass.
var _opened_frame := -1


func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	data = PassRules.load_data()
	_build()
	_root.visible = false


func open() -> void:
	if is_open:
		return
	is_open = true
	_opened_frame = Engine.get_process_frames()
	index = 0
	_refresh()
	_root.visible = true
	Perception.push_suppression()
	get_tree().paused = true
	if not Player.is_scripted_run():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	Perception.pop_suppression()
	get_tree().paused = false
	if not Player.is_scripted_run():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func candidates() -> Array:
	return data.get("candidates", [])


func step(dir: int) -> void:
	var n := candidates().size()
	if n == 0:
		return
	index = posmod(index + dir, n)
	_refresh()


func choose() -> void:
	var c: Dictionary = candidates()[index]
	pass_chosen.emit(str(c.get("id", "")))
	close()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open or Engine.get_process_frames() == _opened_frame:
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("move_left"):
		step(-1)
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("move_right"):
		step(1)
	elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		choose()
	elif event.is_action_pressed("ui_cancel"):
		close()
	else:
		return
	get_viewport().set_input_as_handled()


func _refresh() -> void:
	_sample.pass_data = data.get("sample", {})
	var c := candidates()
	_candidate.pass_data = c[index] if not c.is_empty() else {}
	_counter.text = "%d / %d" % [index + 1, c.size()]
	_today.text = PassRules.human_date(str(data.get("today", "")))


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_CENTER)
	row.add_theme_constant_override("separation", 60)
	row.position = Vector2(-560, -260)
	_root.add_child(row)
	_sample = PassView.new()
	_sample.custom_minimum_size = Vector2(500, 360)
	_candidate = PassView.new()
	_candidate.custom_minimum_size = Vector2(500, 360)
	row.add_child(_column(_sample, "настоящий — образец"))
	row.add_child(_column(_candidate, "из пачки отряда"))
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_CENTER)
	bar.position = Vector2(80, 130)
	bar.add_theme_constant_override("separation", 24)
	_root.add_child(bar)
	var prev := Button.new()
	prev.text = "‹"
	prev.pressed.connect(step.bind(-1))
	_counter = Label.new()
	var next := Button.new()
	next.text = "›"
	next.pressed.connect(step.bind(1))
	for b in [prev, next]:
		(b as Button).flat = true
		(b as Button).add_theme_font_size_override("font_size", 40)
	for n in [prev, _counter, next]:
		bar.add_child(n)
	# No "take" button: the pass in hand is taken by clicking it or with the
	# interact action, like any object in the world.
	_candidate.mouse_filter = Control.MOUSE_FILTER_STOP
	_candidate.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			choose())
	_today = Label.new()
	_today.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_today.position = Vector2(-60, 40)
	_today.add_theme_font_size_override("font_size", 26)
	_root.add_child(_today)


func _column(view: Control, title: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.add_child(view)
	var l := Label.new()
	l.text = title
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", Color(0.55, 0.55, 0.53))
	col.add_child(l)
	return col
