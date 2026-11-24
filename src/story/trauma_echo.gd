class_name TraumaEcho
extends Node
## «Вторжение памяти» (docs/ARCHITECTURE.md): on the road - Acts II and III -
## the moment danger has passed him by (an enemy on his round walks on past
## the boy keeping low and still; a searchlight beam slides off the cover he
## lies behind and moves on), with his panic up, the world goes deaf and the
## picture cuts, for 0.7 s, to the cellar of Act I: dark, the gaps between the
## boards, a torch passing over them, dust, boots overhead. Not mysticism - the
## trauma: all of it he has seen (the invasion, the end of the dream). His
## body stays in the present: enemies go on and hear nothing, and the first
## step he takes breaks the memory off. Otherwise the same hard cut back, a
## start and a jolt of the heart.
## Enemies, hiding spots and shaders are not changed by it.

signal started(cause: StringName, source: Node)
signal ended

const NEAR := &"near"
const LIGHT := &"light"
const DEBUG := &"debug"
const GROUP := &"trauma_echoes"

## The cellar of Act I (src/interaction/cellar_hatch.tscn): its gaps and how
## the world sounds from under its boards. A test keeps them equal.
const CELLAR_VERTICAL := false
const CELLAR_SLIT_WIDTH := 0.16
const CELLAR_SLIT_COUNT := 3
const CELLAR_MUFFLE_HZ := 650.0
const CELLAR_MUFFLE_DB := -5.0
## Above the hiding-spot slits (layer 1), below the archive (10), the level's
## black (20) and the pause menu (30).
const OVERLAY_LAYER := 2
const SLITS_SHADER := preload("res://src/player/hide_overlay.gdshader")

## The torch over the boards: its spot runs along the gaps from end to end.
const LEAK := 0.9
const BAND_FROM := -0.25
const BAND_TO := 1.25
## Seconds the remembered dust takes to settle.
const DUST_FADE := 0.6
## Boots and the floorboard overhead: [seconds into the cut, sound, volume].
const SOUNDS := [[0.1, "step_boot_board", 0.9], [0.3, "floor_creak", 0.7], [0.45, "step_boot_board", 0.8]]
## The boots are this far above his eyes.
const BOARDS_ABOVE := 1.2
## A sepia memory (MemoryFlash) does not begin while an echo runs, nor this
## long after one, s.
const AFTERMATH := 2.0
## The searchlight's sweep is looked ahead in steps of this, s.
const LOOK_AHEAD_STEP := 0.1
## A beam still over his place this long after it left the drawn cone has
## not gone: it lingers, s.
const LINGER := 1.0

## Panic at the moment of relief, at least.
@export_range(0.0, 1.0) var threshold := 0.35
## An enemy has to come this close (horizontally).
@export var near_radius := 3.0
## A dog has to pass this far beyond its nose (Dog.smell_radius) at most:
## close, and it did not catch his scent.
@export var dog_beyond_smell := 1.5
## Relief: the enemy is this much farther than at its closest on this pass,
## and has itself walked this far from where it was then.
@export var relief_margin := 0.3
## He keeps still: not faster than this (m/s, along the ground). Faster
## during the echo - the memory breaks off.
@export var still_speed := 0.3
## The beam must not come back over his place - its cone this many times its
## own (light_widen) - during the echo and light_clear s after it.
@export var light_widen := 1.4
@export var light_clear := 2.0
## The beam over his cover frightens him in itself (panic per second), as a
## torch through the gaps of a hiding place does (Player, 0.35) - up to
## beam_panic_cap; higher only real danger takes him.
@export var beam_panic := 0.2
@export var beam_panic_cap := 0.45
## The cut itself, s.
@export var duration := 0.7
## Hearing goes first: the world is muffled this long before the cut, s.
@export var sound_lead := 0.1
## No new echo sooner than this after the last one, s.
@export var cooldown := 60.0
## Echoes per level at most (each source has one anyway).
@export var max_per_level := 3
@export var panic_spike := 0.12
@export var flinch_strength := 0.8

## Debug (--show-echo): the cut stays at its middle.
var hold := false
## What the running echo came from; empty when idle.
var cause: StringName = &""

## Sources (their node paths) that have had their echo on this level. Kept
## across a reload after capture (LevelBase.resumed) of the same level,
## cleared by a fresh start of a level: «Начать акт заново», a level from the
## menu, the next level.
static var _used: Dictionary = {}
## The level `_used` is about (its scene file).
static var _used_scene := ""
## Seconds until an echo may come again, and since the last one ended.
## Static, like `_used`: a reload after capture does not shorten the pause.
static var _cool := 0.0
static var _since := INF

enum Phase { IDLE, LEAD, CUT }

var _phase := Phase.IDLE
var _t := 0.0
## Enemy -> [least distance on this pass, where he was then]; null once the
## pass has been judged (until he is clear of the boy again).
var _approach: Dictionary = {}
var _beam: Dictionary = {}  # SearchlightTower -> was he lit on this pass
var _level: LevelBase
var _saved_hz := Sfx.OPEN_AIR
var _saved_db := 0.0
var _own_hz := Sfx.OPEN_AIR
var _own_db := 0.0
var _owns_muffle := false
var _next_sound := 0
var _dust := 0.0
var _dust_time := 0.0
var _layer: CanvasLayer
var _mat: ShaderMaterial


static func forget_all() -> void:
	_used.clear()
	_used_scene = ""
	_cool = 0.0
	_since = INF


static func used_count() -> int:
	return _used.size()


static func running_in(tree: SceneTree) -> bool:
	for n in tree.get_nodes_in_group(GROUP):
		if (n as TraumaEcho).is_running():
			return true
	return false


## The cellar is on the screen now (some echo node of the tree).
static func showing_in(tree: SceneTree) -> bool:
	for n in tree.get_nodes_in_group(GROUP):
		if (n as TraumaEcho).is_showing():
			return true
	return false


## MemoryFlash asks: no warm memory while an echo runs, nor AFTERMATH s after
## - on a level that has an echo (left for the menu just after one, the
## aftermath would never run out in Act I).
static func holds_memories_off(tree: SceneTree) -> bool:
	return running_in(tree) or (_since < AFTERMATH and tree.get_first_node_in_group(GROUP) != null)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group(GROUP)
	_build_overlay()
	_level = get_parent() as LevelBase
	if _level != null:
		# LevelBase sets `resumed` in its own _ready, after its children's.
		_level.ready.connect(_on_level_ready.bind(_level), CONNECT_ONE_SHOT)


func _on_level_ready(level: LevelBase) -> void:
	if not level.resumed or level.scene_file_path != _used_scene:
		forget_all()
	_used_scene = level.scene_file_path


func _exit_tree() -> void:
	if _phase != Phase.IDLE:
		_give_back_muffle()
		_phase = Phase.IDLE


func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "EchoOverlay"
	_layer.layer = OVERLAY_LAYER
	_layer.visible = false
	add_child(_layer)
	# Black under the gaps: without it the present would show through them.
	var black := ColorRect.new()
	black.name = "Black"
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(black)
	var slits := ColorRect.new()
	slits.name = "Slits"
	slits.set_anchors_preset(Control.PRESET_FULL_RECT)
	slits.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SLITS_SHADER
	_mat.set_shader_parameter("vertical", CELLAR_VERTICAL)
	_mat.set_shader_parameter("slit_width", CELLAR_SLIT_WIDTH)
	_mat.set_shader_parameter("slit_count", float(CELLAR_SLIT_COUNT))
	_mat.set_shader_parameter("leak", 0.0)
	_mat.set_shader_parameter("dust", 0.0)
	_mat.set_shader_parameter("band", -1.0)
	slits.material = _mat
	_layer.add_child(slits)


func is_running() -> bool:
	return _phase != Phase.IDLE


## True while the cellar is on the screen (after the sound lead).
func is_showing() -> bool:
	return _layer.visible


func material() -> ShaderMaterial:
	return _mat


func _physics_process(delta: float) -> void:
	step(delta)


## One tick; tests call it by hand.
func step(delta: float) -> void:
	var p := Stealth.player as Player
	match _phase:
		Phase.IDLE:
			_cool = maxf(_cool - delta, 0.0)
			_since += delta
			if p != null:
				_watch_near(p)
				_watch_light(p, delta)
		Phase.LEAD:
			if _broken(p):
				_finish(false)
				return
			_t += delta
			var k := clampf(_t / sound_lead, 0.0, 1.0) if sound_lead > 0.0 else 1.0
			_muffle_to(exp(lerpf(log(_saved_hz), log(CELLAR_MUFFLE_HZ), k)),
					lerpf(_saved_db, CELLAR_MUFFLE_DB, k))
			if k >= 1.0:
				_cut_in()
		Phase.CUT:
			if _broken(p):
				_finish(false)
				return
			_t = duration * 0.5 if hold else _t + delta
			_play_due(p)
			_dust = move_toward(_dust, 0.0, delta / DUST_FADE)
			_dust_time += delta
			_mat.set_shader_parameter("band", lerpf(BAND_FROM, BAND_TO, clampf(_t / duration, 0.0, 1.0)))
			_mat.set_shader_parameter("dust", _dust)
			_mat.set_shader_parameter("dust_time", _dust_time)
			if _t >= duration:
				_finish(true)


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


## An enemy on his round came close to him and walks on.
func _watch_near(p: Player) -> void:
	for key in _approach.keys():
		if not is_instance_valid(key):
			_approach.erase(key)
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null:
			continue
		if e.passive or not e.is_visible_in_tree():
			_approach.erase(e)
			continue
		var d := _flat(e.global_position - p.global_position)
		if not _approach.has(e):
			if d <= radius_for(e):
				_approach[e] = [d, e.global_position]
			continue
		var pass_by: Variant = _approach[e]
		if pass_by != null:
			if d < float(pass_by[0]):
				_approach[e] = [d, e.global_position]
				continue
			# The relief comes once a pass, then or never: the gap has grown
			# and he himself has walked on (not the boy crawled off).
			if d >= float(pass_by[0]) + relief_margin \
					and _flat(e.global_position - (pass_by[1] as Vector3)) >= relief_margin:
				_approach[e] = null
				if _near_miss(e, p):
					_try(NEAR, e)
				continue
		if d > radius_for(e) + relief_margin:
			_approach.erase(e)  # clear of him: next time is a new pass


## How close an enemy has to come for a pass to count: a dog - beyond its
## nose (inside it, it smells him and it is no near miss).
func radius_for(e: Enemy) -> float:
	var dog := e as Dog
	return dog.smell_radius + dog_beyond_smell if dog != null else near_radius


## The enemy was on his round and unworried, the boy low and still.
func _near_miss(e: Enemy, p: Player) -> bool:
	return e.state == Enemy.State.PATROL and e.suspicion < Enemy.SUSPICIOUS_AT and still_low(p)


## Crouched and not moving faster than still_speed. Not busy: the crawl under
## the wire moves him though his velocity is 0 (WireGap tweens him).
func still_low(p: Player) -> bool:
	return p.is_crouching and not p.busy() and _flat(p.velocity) <= still_speed


## A searchlight cone went over his cover without lighting him, and moved on.
func _watch_light(p: Player, delta: float) -> void:
	for key in _beam.keys():
		if not is_instance_valid(key):
			_beam.erase(key)
	for node in get_tree().get_nodes_in_group("searchlights"):
		var t := node as SearchlightTower
		if t == null or t.lamp == null:
			continue
		var lit := t.in_beam(p)
		if lit or beam_over(t, p):
			_beam[t] = lit or bool(_beam.get(t, false))
			if not lit and not p.is_hidden and PanicSystem.level < beam_panic_cap:
				PanicSystem.apply_continuous(beam_panic, delta)
		elif _beam.has(t):
			var was_lit: bool = _beam[t]
			_beam.erase(t)
			if not was_lit and still_low(p):
				_try(LIGHT, t)


## The cone (`widen` times the drawn one) is over his shoulders, in range.
func beam_over(t: SearchlightTower, p: Player, widen: float = 1.0) -> bool:
	return t.covers(p.shoulders(), widen)


## A searchlight would come over his place before the echo and light_clear
## after it are over, however fast it passes, or has not left it LINGER s
## on: the cut must not hide that from the player.
func light_coming(p: Player) -> bool:
	var window := sound_lead + duration + light_clear
	var aim := p.shoulders()
	for node in get_tree().get_nodes_in_group("searchlights"):
		var t := node as SearchlightTower
		if t == null or t.lamp == null:
			continue
		# Over him now (just leaving): it must clear first. Not over him: any
		# coming over is too much.
		var clear := not t.will_cover(aim, 0.0, light_widen)
		for i in range(1, int(floor(window / LOOK_AHEAD_STEP + 0.001)) + 1):
			var s := i * LOOK_AHEAD_STEP
			if not t.will_cover(aim, s, light_widen):
				clear = true
			elif clear or s >= LINGER - 0.001:
				return true
	return false


func _key(source: Node) -> String:
	return str(source.get_path()) if source != null and source.is_inside_tree() else ""


func _try(c: StringName, source: Node) -> bool:
	var key := _key(source)
	if key == "" or _used.has(key) or _used.size() >= max_per_level or _cool > 0.0:
		return false
	if PanicSystem.level < threshold or not can_start():
		return false
	_used[key] = true
	start(c, source)
	return true


## Nothing keeps a memory from breaking in now.
func can_start() -> bool:
	var p := Stealth.player as Player
	if p == null or _phase != Phase.IDLE or get_tree().paused:
		return false
	if p.is_hidden or p.is_seated or p.seized or p.satchel.is_open or p.busy():
		return false
	if Perception.sepia > 0.05 or Perception.in_safe_zone() or Perception.is_suppressed():
		return false
	if _level != null and not _level.echo_allowed():
		return false
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		# Anyone looking for him or worried (LevelBase._pursued): it has not passed.
		if e != null and not e.passive and e.is_visible_in_tree() and e.state != Enemy.State.PATROL:
			return false
	for node in get_tree().get_nodes_in_group("searchlights"):
		var t := node as SearchlightTower
		if t != null and t.lamp != null and t.in_beam(p):
			return false
	return not light_coming(p)


## Starts an echo now (the level's triggers, or --show-echo).
func start(c: StringName, source: Node = null) -> void:
	if _phase != Phase.IDLE:
		return
	cause = c
	_saved_hz = Sfx.muffle_hz
	_saved_db = Sfx.muffle_db
	_own_hz = _saved_hz
	_own_db = _saved_db
	_owns_muffle = true
	_phase = Phase.LEAD
	_t = 0.0
	started.emit(c, source)
	if sound_lead <= 0.0:
		_muffle_to(CELLAR_MUFFLE_HZ, CELLAR_MUFFLE_DB)
		_cut_in()


func _cut_in() -> void:
	_phase = Phase.CUT
	_t = 0.0
	_next_sound = 0
	_dust = 0.0
	_mat.set_shader_parameter("leak", LEAK)
	_mat.set_shader_parameter("band", BAND_FROM)
	_mat.set_shader_parameter("dust", 0.0)
	_layer.visible = true


func _play_due(p: Player) -> void:
	while _next_sound < SOUNDS.size() and _t >= float(SOUNDS[_next_sound][0]):
		var s: Array = SOUNDS[_next_sound]
		_next_sound += 1
		if p != null:
			Sfx.play_at(String(s[1]), p.camera.global_position + Vector3.UP * BOARDS_ABOVE, float(s[2]), self)
		if String(s[1]) == "step_boot_board":
			_dust = maxf(_dust, 0.9)


## Caught, hidden, seated, a step taken (or the crawl under the wire, the
## bandage), the satchel opened, a warm memory begun or the level against
## it: the echo is over at once.
func _broken(p: Player) -> bool:
	if p == null or p.seized or p.is_hidden or p.is_seated or p.satchel.is_open:
		return true
	if _flat(p.velocity) > still_speed or p.busy():
		return true
	if Perception.sepia > 0.05 or Perception.in_safe_zone():
		return true
	return _level != null and not _level.echo_allowed()


## `back` - the echo ran its course: the start and the jolt. Cut short - just
## gone. Either way the remembered sounds stop with it.
func _finish(back: bool) -> void:
	_layer.visible = false
	_mat.set_shader_parameter("leak", 0.0)
	_mat.set_shader_parameter("dust", 0.0)
	_mat.set_shader_parameter("band", -1.0)
	_give_back_muffle()
	for c in get_children():
		var a := c as AudioStreamPlayer3D
		if a != null:
			a.stop()
			a.queue_free()
	_phase = Phase.IDLE
	_cool = cooldown
	_since = 0.0
	cause = &""
	if back:
		PanicSystem.spike(panic_spike)
		var p := Stealth.player as Player
		if p != null:
			p.flinch(flinch_strength)
	ended.emit()


## Sets the World muffle while it is still ours; someone else's (capture,
## a hiding spot) is never overwritten.
func _muffle_to(hz: float, db: float) -> void:
	if not _still_ours():
		return
	Sfx.set_muffle(hz, db, 0.0)
	_own_hz = Sfx.muffle_hz
	_own_db = Sfx.muffle_db


func _still_ours() -> bool:
	_owns_muffle = _owns_muffle and absf(Sfx.muffle_hz - _own_hz) < 0.5 and absf(Sfx.muffle_db - _own_db) < 0.01
	return _owns_muffle


func _give_back_muffle() -> void:
	var p := Stealth.player as Player if is_instance_valid(Stealth.player) else null
	if _still_ours() and not (p != null and p.is_hidden):
		Sfx.set_muffle(_saved_hz, _saved_db, 0.0)
	_owns_muffle = false
