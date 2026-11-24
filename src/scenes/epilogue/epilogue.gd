extends Control
## After Act III: a few lines on black (assets/data/epilogue.json, a draft
## - the author writes the epilogue and the dedication), then the Witness
## Archive count and what was found, then back to the main menu.

const DATA_PATH := "res://assets/data/epilogue.json"

@export var line_time: float = 5.0

var lines: Array = []
var data: Dictionary = {}
var _line: Label
var _summary: VBoxContainer
var _to_menu: Button
var _ended := false


func _ready() -> void:
	GameState.log_scene(self)
	get_tree().paused = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if not Player.is_scripted_run():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	GameState.game_finished()
	var d = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	data = d if typeof(d) == TYPE_DICTIONARY else {}
	lines = data.get("lines", [])
	_build()
	var t := create_tween()
	for l in lines:
		t.tween_callback(_set_line.bind(str(l)))
		t.tween_property(_line, "modulate:a", 1.0, 1.2)
		t.tween_interval(line_time)
		t.tween_property(_line, "modulate:a", 0.0, 1.2)
	t.tween_callback(show_summary)
	if OS.get_cmdline_user_args().has("--summary"):
		show_summary.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if not _ended and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact")):
		show_summary()
		get_viewport().set_input_as_handled()


func found() -> Vector2i:
	var all := GameState.collectible_documents()
	var n := 0
	for id in all:
		if GameState.archive.has(id):
			n += 1
	return Vector2i(n, all.size())


func show_summary() -> void:
	if _ended:
		return
	_ended = true
	_line.visible = false
	var f := found()
	_summary.add_child(MenuStyle.label(str(data.get("archive_line", "%d / %d")) % [f.x, f.y], 34, MenuStyle.BRIGHT))
	for id in GameState.archive:
		var doc := ArchiveDB.get_document(id)
		_summary.add_child(MenuStyle.label("• " + ArchiveUI._loc(doc.get("title", {}), id), 24))
	_to_menu = MenuStyle.button("Главное меню", 30)
	_to_menu.pressed.connect(func() -> void: get_tree().change_scene_to_file(GameState.MENU_SCENE))
	_summary.add_child(_to_menu)
	_summary.visible = true
	_to_menu.grab_focus()


func _set_line(text: String) -> void:
	_line.text = text
	_line.modulate.a = 0.0


func _build() -> void:
	add_child(MenuStyle.backdrop())
	_line = MenuStyle.label("", 34, MenuStyle.BRIGHT)
	_line.set_anchors_preset(Control.PRESET_CENTER)
	_line.custom_minimum_size = Vector2(1200, 200)
	_line.position = Vector2(-600, -100)
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.modulate.a = 0.0
	add_child(_line)
	_summary = VBoxContainer.new()
	_summary.position = Vector2(160, 300)
	_summary.add_theme_constant_override("separation", 12)
	_summary.visible = false
	add_child(_summary)
