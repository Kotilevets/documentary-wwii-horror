class_name MemoryFlash
extends Area3D
## A memory (CLAUDE.md, 2: sepia is "safety and memory"): the boy stops and
## looks at a place he knew, and for a few seconds it stands as it was -
## warm sepia, the house whole, panic eases. Reality breaks in hard: if panic
## rises or anyone raises the alarm, the memory is cut off at once (sepia to
## zero in one frame, a jolt of panic). Plays once.
## No words and no captions: what the place was is left to the player.

signal started
signal ended(interrupted: bool)

## Geometry of the place as it was; hidden until the memory.
@export var ghost: Node3D
## The point the boy has to look at (usually the middle of the ruin).
@export var focus: Marker3D
## Signs of the present (smoke over the ruin) hidden while remembering.
@export var present_only: Node3D
@export var duration: float = 7.0
@export var min_distance: float = 3.0
@export var look_dot: float = 0.85
@export var calm_below: float = 0.45
@export var break_above: float = 0.6
## He has to stop to remember (ground speed at most this): a glance in
## passing is not a memory - and the first step out of the place would cut
## it off for good (docs/ARCHITECTURE.md, "Воспоминание").
@export var still_below: float = 0.3

var used := false
var active := false
var _inside := false
var _time := 0.0
var _mat: StandardMaterial3D
var _tween: Tween
var _tone: AudioStreamPlayer3D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 << 1
	body_entered.connect(func(b: Node3D) -> void:
		if b == Stealth.player: _inside = true)
	body_exited.connect(func(b: Node3D) -> void:
		if b == Stealth.player: _inside = false)
	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	_mat.albedo_color = Color(0.62, 0.6, 0.57, 0.0)
	_mat.roughness = 0.95
	if ghost != null:
		for n in ghost.find_children("*", "GeometryInstance3D", true, false):
			(n as GeometryInstance3D).material_override = _mat
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ghost.visible = false


func _physics_process(delta: float) -> void:
	if active:
		_time += delta
		if _should_break():
			_finish(true)
		elif _time >= duration:
			_finish(false)
	elif not used and _inside and _wants_to_remember():
		_begin()


func _wants_to_remember() -> bool:
	# Not over the cellar of a memory breaking in, nor just after it (TraumaEcho).
	if TraumaEcho.holds_memories_off(get_tree()):
		return false
	var p := Stealth.player as Player
	if p == null or p.is_hidden or PanicSystem.level > calm_below or _alarm():
		return false
	if Vector2(p.velocity.x, p.velocity.z).length() > still_below:
		return false
	var cam := p.camera.global_transform
	var to := focus.global_position - cam.origin
	if Vector2(to.x, to.z).length() < min_distance:
		return false
	return (-cam.basis.z).dot(to.normalized()) > look_dot


func _should_break() -> bool:
	var p := Stealth.player as Player
	return PanicSystem.level > break_above or _alarm() or not _inside \
			or (p != null and p.is_hidden)


func _alarm() -> bool:
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en.is_visible_in_tree() and (en.state == Enemy.State.ALERT or en.state == Enemy.State.SUSPICIOUS):
			return true
	return false


func _begin() -> void:
	used = true
	active = true
	_time = 0.0
	Perception.enter_safe_zone()
	PanicSystem.level = PanicSystem.level - 0.2
	_tone = Sfx.play_at("memory_room_tone", focus.global_position)
	if ghost != null:
		ghost.visible = true
		_fade_ghost(1.0, 1.6)
	if present_only != null:
		present_only.visible = false
	started.emit()


func _finish(interrupted: bool) -> void:
	active = false
	Perception.exit_safe_zone()
	if present_only != null:
		present_only.visible = true
	if interrupted:
		# The house goes silent at once, as the picture goes.
		if is_instance_valid(_tone):
			_tone.queue_free()
		_tone = null
		Perception.cut_sepia()
		PanicSystem.spike(0.15)
		if _tween != null:
			_tween.kill()
		_mat.albedo_color.a = 0.0
		if ghost != null:
			ghost.visible = false
	else:
		_fade_ghost(0.0, 2.0)
		_tween.tween_callback(func() -> void:
			if ghost != null: ghost.visible = false)
	ended.emit(interrupted)


func _fade_ghost(alpha: float, time: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_mat, "albedo_color:a", alpha, time)
