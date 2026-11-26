extends LevelBase
## Act III "Партизанский отряд (Разведчик и «Банальность зла»)" (CLAUDE.md,
## 3; GAMEPLAY_AND_SHADERS.md, 4). The boy is the detachment's runner:
##   1. Dugout (sepia): he picks a forged pass from the bundle, comparing it
##      with the genuine sample (PassCheckUI: stamp, date, route).
##   2. Checkpoint: a pass that holds lifts the barrier; one that does not
##      - arrest and the interrogation (suspicion SUSPICION_BAD_PASS).
##   3. Garrison: with a pass he walks openly (Stealth.cover). He has to
##      look at three things long enough to remember them (GazeTarget in
##      Scout); a soldier who sees him staring grows suspicious; in the
##      depot yard the pass is no cover (RestrictedZone). Caught -> the
##      interrogation (SUSPICION_CAUGHT).
##   4. At the exit gate - a round-up: every boy to the commandant's office
##      (SUSPICION_DETAINED). The interrogation (Interrogation): the shell
##      of the investigator falls off if he holds the story or his eyes.
##   5. Released: out of the gate, to the forest - the end card.
## Failing the interrogation: a fade to black and a new try from the
## beginning of the interrogation (no depiction of what happens next).

enum Stage { DUGOUT, ROAD, CHECKPOINT, GARRISON, INTERROGATION, RELEASED }

const BRIEFING_PATH := "res://assets/data/act3/briefing.json"
const PASS_ITEM := preload("res://assets/data/items/forged_pass.tres")
const SUSPICION_DETAINED := 0.15
const SUSPICION_CAUGHT := 0.5
const SUSPICION_BAD_PASS := 0.45
const SUSPICION_NO_PASS := 0.6

## Checkpoint across a reload: {"suspicion": float, "pass": String}.
static var _saved: Dictionary = {}

@export var checkpoint_wait: float = 2.5

@onready var layout: Node3D = $Layout
@onready var bundle: Interactable = $Bundle
@onready var pass_ui: PassCheckUI = $PassCheckUI
@onready var interrogation: Interrogation = $Interrogation
@onready var dugout_zone: SafeZone = $DugoutZone
@onready var checkpoint_zone: Area3D = $CheckpointZone
@onready var exit_zone: Area3D = $ExitZone
@onready var scout_root: Node3D = $Scout
@onready var subtitle: Label = $Overlay/Subtitle

var stage: Stage = Stage.DUGOUT
## Id of the pass the boy took ("" - none).
var chosen_pass := ""
var scouted: Array[String] = []
var briefing: Dictionary = {}
var pass_data: Dictionary = {}


func _start_story(full: bool) -> void:
	briefing = _load(BRIEFING_PATH)
	pass_data = PassRules.load_data()
	Stealth.cover = true
	subtitle.text = ""
	# E on the bundle opens the passes - a whole-screen swap, no faster than
	# Flicker allows one (asked only when they are shut: E on an open view is
	# no swap and must not use up the next one).
	bundle.interacted.connect(func(_p: Node) -> void:
		if not pass_ui.is_open and Flicker.allow_swap():
			pass_ui.open())
	pass_ui.pass_chosen.connect(_on_pass_chosen)
	dugout_zone.player_exited.connect(func() -> void:
		if stage == Stage.DUGOUT:
			stage = Stage.ROAD)
	checkpoint_zone.body_entered.connect(_on_checkpoint)
	exit_zone.body_entered.connect(_on_exit)
	interrogation.released.connect(_on_released)
	interrogation.failed.connect(_on_failed)
	for t in scout_targets():
		t.active = false
		t.fixed.connect(_on_scouted)
	if resumed and not _saved.is_empty():
		chosen_pass = str(_saved.get("pass", ""))
		_begin_interrogation(float(_saved.get("suspicion", SUSPICION_DETAINED)), false)
		return
	_saved = {}
	if full:
		_opening()


func _load(path: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if typeof(d) == TYPE_DICTIONARY else {}


func _opening() -> void:
	fade.modulate.a = 1.0
	caption.text = str(briefing.get("title", ""))
	var t := create_tween()
	t.tween_interval(2.5)
	for line in briefing.get("briefing", []):
		t.tween_callback(func() -> void: caption.text = str(line))
		t.tween_interval(4.5)
	t.tween_callback(func() -> void: caption.text = "")
	t.tween_property(fade, "modulate:a", 0.0, 2.5)


func scout_targets() -> Array[GazeTarget]:
	var out: Array[GazeTarget] = []
	for c in scout_root.get_children():
		if c is GazeTarget:
			out.append(c as GazeTarget)
	return out


func chosen_pass_data() -> Dictionary:
	return PassRules.find(pass_data, chosen_pass)


func _say(text: String, seconds: float = 2.5) -> void:
	subtitle.text = ("— " + text) if text != "" else ""
	get_tree().create_timer(seconds, false).timeout.connect(_clear_subtitle.bind(subtitle.text))


func _clear_subtitle(shown: String) -> void:
	if subtitle.text == shown:
		subtitle.text = ""


# --- stages ----------------------------------------------------------------------

func _on_pass_chosen(id: String) -> void:
	chosen_pass = id
	if not Inventory.has_item(PASS_ITEM.id):
		Inventory.add_item(PASS_ITEM)


func _on_checkpoint(body: Node3D) -> void:
	if body != player or stage > Stage.ROAD:
		return
	stage = Stage.CHECKPOINT
	player.velocity = Vector3.ZERO
	player.set_physics_process(false)
	var sentry := get_node_or_null("SentryLeft") as Node3D
	if sentry != null:
		player.look_towards(sentry.global_position + Vector3.UP * 1.5)
	_say(str(briefing.get("checkpoint_ask", "")), checkpoint_wait)
	PanicSystem.spike(0.25)
	get_tree().create_timer(checkpoint_wait, false).timeout.connect(_checkpoint_verdict)


func _checkpoint_verdict() -> void:
	player.set_physics_process(true)
	var p := chosen_pass_data()
	if not p.is_empty() and PassRules.is_valid(p, pass_data):
		_say(str(briefing.get("checkpoint_pass", "")))
		layout.call("open_barrier")
		stage = Stage.GARRISON
		for t in scout_targets():
			t.active = true
	else:
		_say(str(briefing.get("checkpoint_fail", "")))
		_detain(SUSPICION_NO_PASS if p.is_empty() else SUSPICION_BAD_PASS)


func _on_scouted(t: GazeTarget) -> void:
	if not scouted.has(t.name):
		scouted.append(t.name)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	var staring := false
	if stage == Stage.GARRISON:
		for t in scout_targets():
			# Looking at it now, and not just a glance: looking away stops it.
			if not t.done and t.looking and t.held > 0.25:
				staring = true
	Stealth.staring = staring


## A memory breaks in only on the road, in the garrison and after release:
## not in the dugout, at the barrier while the pass is looked at, nor while
## he is being detained or questioned.
func echo_allowed() -> bool:
	return super() and stage in [Stage.ROAD, Stage.GARRISON, Stage.RELEASED]


func _on_exit(body: Node3D) -> void:
	if body == player and stage == Stage.GARRISON:
		_say(str(briefing.get("detained", "")), 3.0)
		_detain(SUSPICION_DETAINED, 2.0)


## Capture in the garrison does not end the act: it leads to the office.
func _on_caught(enemy: Enemy) -> void:
	if stage == Stage.GARRISON or stage == Stage.ROAD:
		player.seized_by(enemy)
		_detain(SUSPICION_CAUGHT)
	elif stage == Stage.RELEASED:
		super._on_caught(enemy)  # caught again after release: seized, cut, reload
	else:
		enemy.stand_down()  # never leave an enemy frozen over a catch nobody handles


func _detain(suspicion: float, delay: float = 1.0) -> void:
	if stage == Stage.INTERROGATION:
		return
	stage = Stage.INTERROGATION
	_saved = {"suspicion": suspicion, "pass": chosen_pass}
	Stealth.staring = false
	var t := create_tween()
	t.tween_interval(delay)
	t.tween_property(fade, "modulate:a", 1.0, 1.0)
	t.tween_callback(_begin_interrogation.bind(suspicion, true))


func _begin_interrogation(suspicion: float, with_fade: bool) -> void:
	stage = Stage.INTERROGATION
	_saved = {"suspicion": suspicion, "pass": chosen_pass}
	for t in scout_targets():
		t.active = false
	var p := chosen_pass_data()
	interrogation.start(suspicion, not p.is_empty() and PassRules.is_valid(p, pass_data))
	fade.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(0.5 if with_fade else 0.2)
	t.tween_property(fade, "modulate:a", 0.0, 1.5)


func _on_released() -> void:
	stage = Stage.RELEASED
	_saved = {}
	var t := create_tween()
	t.tween_interval(1.0)
	t.tween_property(fade, "modulate:a", 1.0, 1.2)
	t.tween_callback(func() -> void:
		player.stand_up((get_node("Spawns/Released") as Node3D).global_transform)
		for e in get_tree().get_nodes_in_group("enemies"):
			(e as Enemy).stand_down()
		_say(str(briefing.get("released", "")), 3.0))
	t.tween_property(fade, "modulate:a", 0.0, 1.5)


func _on_failed() -> void:
	if _ending:
		return
	_ending = true
	_resume_after_intro = true
	var t := create_tween()
	t.tween_property(fade, "modulate:a", 1.0, 2.0)
	t.tween_interval(1.5)
	t.tween_callback(get_tree().reload_current_scene)


## --open-passes             the pass check view
## --garrison                the barrier is open, scouting is live
## --interrogate=<suspicion> straight to the office
## --illusion=<0..1>         during the interrogation: how cracked the shell is
## --reveal                  the shell falls
func _debug_arg(key: String, value: String) -> void:
	match key:
		"open-passes":
			pass_ui.open()
		"garrison":
			_on_pass_chosen("pass_c")
			layout.call("open_barrier")
			stage = Stage.GARRISON
			for t in scout_targets():
				t.active = true
		"interrogate":
			interrogation.opening_pause = 0.5
			_begin_interrogation(value.to_float(), true)
		"illusion":
			interrogation._set_illusion(value.to_float())
		"reveal":
			interrogation._set_illusion(0.0)


func _end_card_text() -> String:
	var line := str(briefing.get("scouted_line", "%d / %d")) % [scouted.size(), scout_targets().size()]
	return super._end_card_text() + "\n" + line
