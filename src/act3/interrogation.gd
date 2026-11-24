class_name Interrogation
extends Node
## Interrogation at the Secret Field Police (GAMEPLAY_AND_SHADERS.md, 4;
## CLAUDE.md, 3, Act III). The boy sits on a stool before the desk; each
## question has a timer. An answer is checked against the cover story
## (legend) and against what he said before:
##   contradiction / suspicious answer / silence / timeout -> suspicion up,
##   the nightmare comes back a little (IllusionFactor up);
##   an answer that holds the story -> IllusionFactor down.
## Holding his eyes on an ordinary thing in the room (GazeTarget children of
## details_root: portrait, kettle, typewriter) also pulls him out.
## IllusionFactor near zero: the investigator's shell cracks and falls off
## (Enemy.reveal + InvestigatorShell.shatter). Suspicion 1 -> failed.
## Lines: assets/data/act3/interrogation.json (a draft, the author writes
## the final text). No German speech: on screen is the interpreter's Russian.

signal question_asked(id: String)
signal answered(id: String, outcome: String)
signal revealed
signal released
signal failed

const DATA_PATH := "res://assets/data/act3/interrogation.json"
const ILLUSION_CONSISTENT := -0.2
const ILLUSION_DETAIL := -0.34
const ILLUSION_MISTAKE := 0.1
const ILLUSION_SILENCE := 0.05
const SUSPICION := {
	"contradiction": 0.35, "suspicious": 0.3, "silence": 0.2, "timeout": 0.2, "consistent": -0.05,
}
## A forged pass that does not hold up costs this much more on its question.
const BAD_PASS_SUSPICION := 0.15
const REVEAL_AT := 0.05
## Panic does not drop below this while the shell is on.
const ROOM_PANIC := 0.45

@export var investigator: Enemy
@export var shell: InvestigatorShell
## Stool: its -Z is the view at the investigator.
@export var seat: Node3D
## Parent of the GazeTarget details of the room.
@export var details_root: Node3D
## Where the typing comes from: after each answer the investigator types
## it into the protocol (Sfx "typewriter_keys"), silence too.
@export var typewriter: Node3D
@export var typing_delay: float = 0.35
@export var pause_between: float = 1.8
@export var opening_pause: float = 2.5

var data: Dictionary = {}
var running := false
var suspicion := 0.0
var illusion := 1.0
var pass_valid := true
var claims: Dictionary = {}
var q_index := -1
var time_left := 0.0
var selected := 0
var is_revealed := false
## Outcomes in order, for tests and the end card.
var outcomes: Array[String] = []

var _waiting := true
var _ui: CanvasLayer
var _line: Label
var _bar: ColorRect
var _bar_full := 520.0
var _answers: VBoxContainer


func _ready() -> void:
	data = load_data()
	_build_ui()
	_ui.visible = false
	for d in details():
		d.active = false
		d.fixed.connect(_on_detail_fixed)


static func load_data() -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	return d if typeof(d) == TYPE_DICTIONARY else {}


func details() -> Array[GazeTarget]:
	var out: Array[GazeTarget] = []
	if details_root != null:
		for c in details_root.get_children():
			if c is GazeTarget:
				out.append(c as GazeTarget)
	return out


func questions() -> Array:
	return data.get("questions", [])


func start(initial_suspicion: float, valid_pass: bool) -> void:
	running = true
	suspicion = clampf(initial_suspicion, 0.0, 0.95)
	pass_valid = valid_pass
	illusion = 1.0
	is_revealed = false
	claims = {}
	outcomes = []
	q_index = -1
	Perception.set_illusion_factor(1.0)
	if shell != null:
		shell.crack = 0.0
	var p := Stealth.player as Player
	p.sit_at(seat)
	p.look_towards(investigator.global_position + Vector3.UP * 1.62)
	PanicSystem.floor_level = ROOM_PANIC
	PanicSystem.spike(0.3)
	for d in details():
		d.active = true
	_ui.visible = true
	_show_line(str(data.get("opening", "")))
	_set_answers([])
	_waiting = true
	_after(opening_pause, _next_question)


func _process(delta: float) -> void:
	if not running or _waiting:
		return
	time_left -= delta
	var q: Dictionary = questions()[q_index]
	_bar.size.x = _bar_full * clampf(time_left / float(q.get("time", 8.0)), 0.0, 1.0)
	if time_left < 3.0:
		PanicSystem.apply_continuous(0.12, delta)
	if time_left <= 0.0:
		answer(-1)


func _unhandled_input(event: InputEvent) -> void:
	if not running or _waiting:
		return
	var n := _answers.get_child_count()
	if event.is_action_pressed("ui_up") or event.is_action_pressed("move_forward"):
		selected = posmod(selected - 1, n)
		_highlight()
	elif event.is_action_pressed("ui_down") or event.is_action_pressed("move_back"):
		selected = posmod(selected + 1, n)
		_highlight()
	elif event.is_action_pressed("interact") or event.is_action_pressed("ui_accept"):
		answer(selected)
	else:
		for i in 3:
			if event.is_action_pressed("answer_%d" % (i + 1)) and i < n:
				answer(i)
				break
		return
	get_viewport().set_input_as_handled()


## Answer the current question with option `i` (-1: the timer ran out).
func answer(i: int) -> void:
	if not running or _waiting:
		return
	var q: Dictionary = questions()[q_index]
	var outcome := evaluate(q, i)
	if i >= 0:
		claims.merge((q.answers[i] as Dictionary).get("claims", {}), true)
	var add: float = SUSPICION[outcome]
	if q.get("about_pass", false) and not pass_valid:
		add += BAD_PASS_SUSPICION
	suspicion = clampf(suspicion + add, 0.0, 1.0)
	outcomes.append(outcome)
	answered.emit(str(q.get("id", "")), outcome)
	match outcome:
		"consistent":
			_set_illusion(illusion + ILLUSION_CONSISTENT)
		"silence", "timeout":
			_set_illusion(illusion + ILLUSION_SILENCE)
			PanicSystem.spike(0.15)
		_:
			_set_illusion(illusion + ILLUSION_MISTAKE)
			PanicSystem.spike(0.25)
	_show_line(str((data.get("reactions", {}) as Dictionary).get(outcome, "")))
	_set_answers([])
	_waiting = true
	if typewriter != null:
		_after(typing_delay, _type_answer)
	if suspicion >= 1.0:
		_after(pause_between, _fail)
	else:
		_after(pause_between, _next_question)


## "consistent", "contradiction", "suspicious", "silence" or "timeout".
func evaluate(q: Dictionary, i: int) -> String:
	if i < 0:
		return "timeout"
	var a: Dictionary = q.answers[i]
	if a.get("silence", false):
		return "silence"
	if a.get("suspicious", false):
		return "suspicious"
	var legend: Dictionary = data.get("legend", {})
	var said: Dictionary = a.get("claims", {})
	for key in said:
		if legend.has(key) and legend[key] != said[key]:
			return "contradiction"
		if claims.has(key) and claims[key] != said[key]:
			return "contradiction"
	return "consistent"


func _next_question() -> void:
	if not running:
		return
	q_index += 1
	if q_index >= questions().size():
		_release()
		return
	var q: Dictionary = questions()[q_index]
	time_left = float(q.get("time", 8.0))
	selected = 0
	_show_line(str(q.get("text", "")))
	var texts: Array[String] = []
	for a in q.get("answers", []):
		texts.append(str((a as Dictionary).get("text", "")))
	_set_answers(texts)
	_bar.size.x = _bar_full
	_waiting = false
	question_asked.emit(str(q.get("id", "")))


func _on_detail_fixed(_t: GazeTarget) -> void:
	if not running:
		return
	PanicSystem.level = maxf(PanicSystem.level - 0.15, 0.0)
	_set_illusion(illusion + ILLUSION_DETAIL)


func _set_illusion(v: float) -> void:
	if is_revealed:
		return
	illusion = clampf(v, 0.0, 1.0)
	if shell != null:
		shell.crack = 1.0 - illusion
	if illusion <= REVEAL_AT:
		_reveal()
	else:
		Perception.set_illusion_factor(illusion, 0.8)


## The shell falls: a tired man in a uniform with a red armband.
func _reveal() -> void:
	is_revealed = true
	illusion = 0.0
	Perception.set_illusion_factor(0.0, 2.5)
	investigator.reveal(2.5)
	if shell != null:
		shell.shatter()
	PanicSystem.floor_level = 0.0
	revealed.emit()


func _release() -> void:
	_finish()
	released.emit()


func _fail() -> void:
	_finish()
	failed.emit()


func _finish() -> void:
	running = false
	_waiting = true
	PanicSystem.floor_level = 0.0
	for d in details():
		d.active = false
	_ui.visible = false


func _type_answer() -> void:
	if running and typewriter != null:
		Sfx.play_at("typewriter_keys", typewriter.global_position)


func _after(seconds: float, f: Callable) -> void:
	get_tree().create_timer(seconds, false).timeout.connect(f)


# --- UI ------------------------------------------------------------------------
# Subtitles at the bottom; no key hints: the options are chosen with the
# movement/arrow keys and the interact action, or 1-3.

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 9
	add_child(_ui)
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -_bar_full * 0.5
	box.offset_right = _bar_full * 0.5
	box.offset_top = -250
	box.offset_bottom = -40
	box.add_theme_constant_override("separation", 10)
	_ui.add_child(box)
	_line = Label.new()
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.add_theme_font_size_override("font_size", 30)
	_line.add_theme_color_override("font_color", Color(0.92, 0.92, 0.9))
	_line.add_theme_color_override("font_outline_color", Color.BLACK)
	_line.add_theme_constant_override("outline_size", 6)
	box.add_child(_line)
	var track := Control.new()
	track.custom_minimum_size = Vector2(_bar_full, 14)
	box.add_child(track)
	_bar = ColorRect.new()
	_bar.color = Color(0.7, 0.7, 0.68, 0.8)
	_bar.position = Vector2(0, 6)
	_bar.size = Vector2(_bar_full, 3)
	track.add_child(_bar)
	_answers = VBoxContainer.new()
	_answers.add_theme_constant_override("separation", 4)
	box.add_child(_answers)


func _show_line(text: String) -> void:
	_line.text = ("— " + text) if text != "" else ""


func _set_answers(texts: Array[String]) -> void:
	for c in _answers.get_children():
		_answers.remove_child(c)
		c.queue_free()
	for t in texts:
		var l := Label.new()
		l.text = t
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 24)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 5)
		_answers.add_child(l)
	_bar.visible = not texts.is_empty()
	_highlight()


func _highlight() -> void:
	for i in _answers.get_child_count():
		var l := _answers.get_child(i) as Label
		l.add_theme_color_override("font_color",
				Color(0.95, 0.95, 0.93) if i == selected else Color(0.5, 0.5, 0.49))
