extends LevelBase
## The night after the village: between Act I and Act II the boy sleeps in
## the forest and dreams of the house (psychological horror, CLAUDE.md, 1:
## no mysticism - the dream is the trauma speaking, as the grotesque
## soldiers are).
##   Stage 0: home, in sepia: the lamp, the clock, four bowls on the table.
##            Nobody is there. The door to the сени is open.
##   Every time he goes out through the сени, he is back in the room
##   (a blink), and the room is worse:
##   Stage 1: the sepia drains away, the ceiling is lower, a stool lies on
##            the floor, the clock slows, a knock at the window.
##   Stage 2: the table is almost empty, a flare in the window, dogs.
##   Stage 3: the door is kicked in, as on the night of the invasion. The
##            сени behind it are lit; a figure stands in the doorway, black
##            against the light, its torch sweeping the floor. The only way out is the cellar hatch
##            (blue-green - the only such thing in the dream). Hidden, he
##            hears the floor creak above, the light passes over the slits,
##            the figure comes closer... and he wakes up.
##   Waking: a hard cut, a gasp; dawn in the forest, in sepia; then Act II.
## Nothing here can catch him: the fear has no rules to lose by. There are
## no words in the dream.

signal stage_changed(stage: int)
signal woke

const ENEMY := preload("res://src/ai/enemy.tscn")
const HATCH := preload("res://src/interaction/cellar_hatch.tscn")
const CEILINGS := [2.6, 2.45, 2.3, 2.15]
const CLOCK_STRETCH := [0.0, 0.4, 0.75, 1.0]
const PANIC_FLOOR := [0.0, 0.15, 0.3, 0.5]
const LAMP := [[0.9, 0.0], [0.75, 0.12], [0.5, 0.3], [0.6, 0.8]]
const DOOR_POINT := Vector3(1.5, 1.2, -2.4)
## He comes back facing the table: the family's places are what he sees.
const TABLE_POINT := Vector3(-1.4, 0.9, 1.0)
const HATCH_AT := Vector3(-0.4, 0, -1.2)
const FIGURE_AT := Vector3(1.5, 0, -2.8)

## Seconds in the cellar before he wakes.
@export var wake_after: float = 10.0
## Black between leaving through the сени and being back in the room.
@export var loop_blink: float = 0.35
## A knock from the сени if he stays in the room this long.
@export var knock_after: float = 30.0
## Seconds of the dawn before Act II.
@export var dawn_time: float = 6.0

@onready var layout: Node3D = $Layout
@onready var gate: Area3D = $LoopGate

var stage := -1
var figure: Enemy
var hatch: HideSpot
var waking := false
var awake := false
var _hidden_time := 0.0
var _stage_time := 0.0
var _knocked := false
var _looping := false
var _creak_in := 0.0
var _t := 0.0
var _sepia := false


func _start_story(full: bool) -> void:
	# Act II is reached once the village is behind: "Продолжить" leads on.
	GameState.act_reached(next_level)
	gate.body_entered.connect(_on_gate)
	player.hidden_changed.connect(_on_hidden_changed)
	player.look_towards(TABLE_POINT)
	Perception.enter_safe_zone()
	_sepia = true
	apply_stage(0)
	Sfx.play_at("memory_room_tone", Vector3(-1.4, 1.2, 1.0))
	if full:
		fade.modulate.a = 1.0
		create_tween().tween_property(fade, "modulate:a", 0.0, 3.0)


func apply_stage(n: int) -> void:
	stage = n
	_stage_time = 0.0
	_knocked = false
	layout.set_ceiling(CEILINGS[n])
	layout.set_table(n)
	layout.set_lamp(LAMP[n][0], LAMP[n][1])
	(layout.clock as WallClock).stretch = CLOCK_STRETCH[n]
	PanicSystem.floor_level = PANIC_FLOOR[n]
	PanicSystem.level = maxf(PanicSystem.level, PANIC_FLOOR[n])
	if n > 0 and _sepia:
		_sepia = false
		Perception.exit_safe_zone()
	match n:
		1:
			_after(1.5, _sound.bind("door_knock", Vector3(-3.4, 1.5, 0)))
		2:
			layout.flare()
			_after(0.8, _sound.bind("dog_bark", Vector3(-12, 0.6, 3)))
			_after(2.6, _sound.bind("dog_bark", Vector3(-10, 0.6, -6)))
		3:
			_last_room()
	stage_changed.emit(n)


func _last_room() -> void:
	layout.block_doorway(true)
	Sfx.play_at("door_kick", DOOR_POINT)
	PanicSystem.spike(0.2)
	gate.set_deferred("monitoring", false)
	figure = ENEMY.instantiate() as Enemy
	figure.name = "Figure"
	figure.passive = true
	figure.has_torch = true
	figure.torch_on = true
	figure.position = FIGURE_AT
	add_child(figure)
	_face_hatch(0.0)
	hatch = HATCH.instantiate() as HideSpot
	hatch.name = "Hatch"
	hatch.position = HATCH_AT
	add_child(hatch)


func _after(seconds: float, f: Callable) -> void:
	get_tree().create_timer(seconds, false).timeout.connect(f)


func _sound(id: String, at: Vector3) -> void:
	if not awake:
		Sfx.play_at(id, at)


# --- the loop through the сени --------------------------------------------------

func _on_gate(body: Node3D) -> void:
	if body != player or stage >= 3 or _looping or waking:
		return
	_looping = true
	fade.modulate.a = 1.0
	_after(loop_blink, _back_in_room)


func _back_in_room() -> void:
	player.velocity = Vector3.ZERO
	player.global_transform = ($Spawns/Start as Node3D).global_transform
	player.look_towards(TABLE_POINT)
	Sfx.play_at("door_creak", DOOR_POINT)
	apply_stage(stage + 1)
	_looping = false
	create_tween().tween_property(fade, "modulate:a", 0.0, 0.8)


# --- the last room and the cellar -------------------------------------------------

func _on_hidden_changed(_is_hidden: bool) -> void:
	_hidden_time = 0.0
	_creak_in = 1.5


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_t += delta
	if waking or stage < 0:
		return
	_stage_time += delta
	if stage < 3 and not _knocked and _stage_time > knock_after:
		_knocked = true
		Sfx.play_at("door_knock", Vector3(1.5, 1.4, -7.8))
	if stage != 3 or figure == null:
		return
	if player.is_hidden:
		_hidden_time += delta
		# The figure comes over to the hatch while he hides.
		var k := clampf(_hidden_time / (wake_after * 0.7), 0.0, 1.0)
		figure.global_position = FIGURE_AT.lerp(HATCH_AT + Vector3(0.9, 0, -0.35), k)
		_creak_in -= delta
		if _creak_in <= 0.0:
			_creak_in = randf_range(1.8, 3.2)
			Sfx.play_at("door_creak", figure.global_position, 0.7)
		if _hidden_time >= wake_after:
			_wake()
			return
	elif player.global_position.distance_to(figure.global_position) < 2.5:
		PanicSystem.apply_continuous(0.25, delta)
	_face_hatch(_t)


## Turn the figure to the hatch, the torch sweeping slowly across it and
## tilting down as he comes closer: the light keeps finding the slits.
func _face_hatch(t: float) -> void:
	var to := HATCH_AT - figure.global_position
	figure.rotation.y = atan2(-to.x, -to.z) + 0.6 * sin(t * 0.9)
	if figure.torch != null:
		var flat := Vector2(to.x, to.z).length()
		figure.torch.rotation.x = -atan2(figure.torch.position.y - 0.15, maxf(flat, 0.3))


# --- waking ----------------------------------------------------------------------

func _wake() -> void:
	if waking:
		return
	waking = true
	fade.modulate.a = 1.0
	if player.is_hidden:
		hatch.eject(player)
	if figure != null:
		figure.queue_free()
		figure = null
	if hatch != null:
		hatch.queue_free()
		hatch = null
	($Layout/Room as Node3D).queue_free()
	# The house was silent; the forest at dawn has a quiet wind.
	var wind := AmbienceBed.new()
	wind.name = "Wind"
	wind.gain_db = -6.0
	add_child(wind)
	PanicSystem.floor_level = 0.0
	PanicSystem.level = 0.55
	# A copy: the scene's own Environment is shared with a restarted dream.
	var env := ($Environment as WorldEnvironment).environment.duplicate() as Environment
	($Environment as WorldEnvironment).environment = env
	env.background_color = Color(0.46, 0.46, 0.44)
	env.ambient_light_energy = 0.8
	env.fog_light_color = Color(0.5, 0.5, 0.48)
	player.sit_at($ForestSeat as Node3D)
	# The gasp of waking, at his own head in the forest: played in the room it
	# would start sixty metres away and never be heard.
	Sfx.play_at("breath_gasp", player.camera.global_position)
	Perception.enter_safe_zone()
	var t := create_tween()
	t.tween_interval(1.0)
	t.tween_property(fade, "modulate:a", 0.0, 2.5)
	t.tween_callback(func() -> void: awake = true)
	t.tween_interval(dawn_time)
	t.tween_property(fade, "modulate:a", 1.0, 2.0)
	t.tween_callback(_to_next)


func _to_next() -> void:
	woke.emit()
	if next_level != "" and is_inside_tree():
		get_tree().change_scene_to_file(next_level)


## The flow test and the menus skip the dream this way.
func _on_reached_forest() -> void:
	if _ending:
		return
	_ending = true
	_to_next()


## --stage=<0..3>  that room of the dream
## --wake          the forest at dawn
func _debug_arg(key: String, value: String) -> void:
	match key:
		"stage":
			apply_stage(clampi(value.to_int(), 0, 3))
		"wake":
			_wake()
			fade.modulate.a = 0.0
