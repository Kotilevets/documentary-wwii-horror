class_name LevelBase
extends Node3D
## Shared level logic: resets the autoloads, reloads on capture, ends the
## slice in the forest once nobody follows, debug arguments for renders.
## Story levels override _start_story() and _resume_checkpoint().
##
## Debug arguments (after `--` on the command line):
##   --spawn=<Marker name under Spawns>   start position
##   --look=<node path | x,y,z>          turn the player towards a node or a point
##   --panic=<0..1>                       hold panic at least at this level
##   --hide=<HideSpot path>               start inside a hiding spot
##   --sepia                              force safe-zone sepia
##   --crouch                             hold the crouch action
##   --freeze-enemies                     enemies stand still (for screenshots)
##   --silent                             no breath sounds from the boy (renders
##                                        of a search seen from a hiding spot)
##   --no-gunfire                         no distant shots (GunfireAmbience.muted)
##   --no-post                            raw frame without post-processing
##   --brightness=<0.7..1.6>              the picture at this brightness (not saved)
##   --open-doc=<document id>             open the inspection view
##   (levels add their own: _debug_arg)

signal slice_finished

## Tests and screenshots start after the opening.
@export var play_intro: bool = true
## First line of the end card.
@export var ending_title: String = "Конец вертикального среза"
## Scene loaded a few seconds after the end card ("" - stay on the card).
@export_file("*.tscn") var next_level: String = ""
## Checkpoint across a reload after capture (see _resume_checkpoint()).
static var _resume_after_intro := false
## A reload after a capture in the opening, not at a checkpoint, starts the
## opening again from its turn rather than from its quiet beginning (see
## _retries_opening(); Act I: from the flare).
static var _retry_opening := false
## Checkpoints on the way: names of Spawns markers in the order the boy
## reaches them. Coming within checkpoint_radius of the next one while
## nobody is after him saves it; capture or a mine then brings him back
## there, with the satchel as it was and the things he took gone from the
## world. "Начать акт заново" and a new start clear it.
@export var checkpoints: Array[String] = []
@export var checkpoint_radius: float = 4.5
## Wind outside (AmbienceBed); the dream turns it off.
@export var has_wind: bool = true
## Night (a DirectionalLight3D named "Moon" in the level): how well the boy is
## seen in open moonlight, 0..1 (Stealth.set_night, "Свет и тень").
@export var night_sight: float = 0.5
@export var wind_gain_db: float = 0.0
## {"scene", "index", "items": [[path, count]], "documents", "taken", "hunger",
## "bleeding", "bled_for"}
static var _checkpoint: Dictionary = {}

@onready var player: Player = $Player
@onready var forest_zone: SafeZone = get_node_or_null("ForestEdge")
@onready var fade: ColorRect = $Overlay/Fade
@onready var caption: Label = $Overlay/Caption

var _ending := false
## Seconds the player has spent in the forest with nobody on their heels.
var _forest_calm := 0.0
var _in_forest := false
var _documents_total := 0
## Index in `checkpoints` of the last one reached (-1: none).
var checkpoint_index := -1
## Pickups taken in this run (paths from the level).
var _taken: Array[String] = []
## This load is a reload after capture past the checkpoint.
var resumed := false
## This load is a reload after capture in the opening (_retry_opening).
var again := false
## The forest is not a finish line: the slice ends only after this many
## seconds in the forest with no enemy alerted or suspicious.
@export var forest_calm_needed: float = 4.0
## How hungry the boy is when the act starts (Hunger.level; docs/
## ARCHITECTURE.md, "Голод и хлеб").
@export_range(0.0, 1.0) var start_hunger: float = 0.0


func _ready() -> void:
	GameState.log_scene(self)
	PanicSystem.reset()
	Perception.reset()
	Inventory.clear()
	Stealth.clear_scent()
	Stealth.reset_cover()
	var moon := get_node_or_null("Moon") as DirectionalLight3D
	if moon != null:
		Stealth.set_night(night_sight, moon)
	else:
		Stealth.set_day()
	Sfx.set_muffle(Sfx.OPEN_AIR, 0.0, 0.0)
	if has_wind:
		var wind := AmbienceBed.new()
		wind.name = "Wind"
		wind.gain_db = wind_gain_db
		add_child(wind)
	add_to_group("levels")
	GameState.act_started(scene_file_path)
	_documents_total = _count_documents()
	for n in find_children("*", "Pickup", true, false):
		var pickup := n as Pickup
		var gone: Node = pickup.remove_on_pickup if pickup.remove_on_pickup != null else pickup
		pickup.interacted.connect(_on_pickup_taken.bind(get_path_to(gone)))
	fade.modulate.a = 0.0
	caption.text = ""
	for e in get_tree().get_nodes_in_group("enemies"):
		(e as Enemy).player_caught.connect(_on_caught)
	for m in get_tree().get_nodes_in_group("mines"):
		if is_ancestor_of(m):
			(m as TripwireMine).detonated.connect(_on_mine)
	if forest_zone != null:
		forest_zone.player_entered.connect(func() -> void: _in_forest = true)
		forest_zone.player_exited.connect(func() -> void:
			_in_forest = false
			_forest_calm = 0.0)
	if player.hunger != null:
		player.hunger.level = start_hunger
	var resume := _resume_after_intro
	_resume_after_intro = false
	resumed = resume
	again = _retry_opening and not resume
	_retry_opening = false
	_start_story(play_intro and not resume and not OS.get_cmdline_user_args().has("--skip-intro"))
	if resume and _checkpoint.get("scene", "") == scene_file_path:
		_restore_checkpoint()
	else:
		_checkpoint = {}
	_apply_debug_args.call_deferred()


func _exit_tree() -> void:
	Stealth.set_day()
	# Act III's pass gives cover; it must not outlive the level.
	Stealth.reset_cover()


## Starts the level's opening (`full`) or puts the level in its post-opening
## state. Overridden by story levels.
func _start_story(_full: bool) -> void:
	pass


## True if a reload after capture should skip the opening.
func _resume_checkpoint() -> bool:
	return false


## True if a reload after capture, not at a checkpoint, should start the
## opening again from its turn. Overridden by story levels.
func _retries_opening() -> bool:
	return false


func _restarts_at_checkpoint() -> bool:
	return _resume_checkpoint() or checkpoint_index >= 0


func _on_pickup_taken(_by: Node, path: NodePath) -> void:
	_taken.append(str(path))


## Is the boy at the next checkpoint, calm? Then remember it. Not while
## his hands are busy (under the wire, binding the wound).
func _check_checkpoints() -> void:
	if player.busy():
		return
	for i in range(checkpoint_index + 1, checkpoints.size()):
		var m := get_node_or_null("Spawns/" + checkpoints[i]) as Node3D
		if m != null and player.global_position.distance_to(m.global_position) < checkpoint_radius:
			if not _pursued() and not player.is_hidden:
				save_checkpoint(i)
			return


func save_checkpoint(i: int) -> void:
	checkpoint_index = i
	var items: Array = []
	for item in Inventory.items():
		items.append([item.resource_path, Inventory.count(item.id)])
	_checkpoint = {"scene": scene_file_path, "index": i, "items": items,
			"documents": Inventory.documents.duplicate(), "taken": _taken.duplicate(),
			"hunger": player.hunger.level if player.hunger != null else start_hunger,
			"bleeding": player.wound != null and player.wound.bleeding,
			"bled_for": player.wound.bled_for if player.wound != null else 0.0}
	# He stops and gets his breath back: the only sign, no text.
	Sfx.play_at("breath_exhale", player.global_position, 0.6)


func _restore_checkpoint() -> void:
	checkpoint_index = int(_checkpoint.get("index", -1))
	var m := get_node_or_null("Spawns/" + checkpoints[checkpoint_index]) as Node3D
	if m != null:
		player.global_transform = m.global_transform
	_taken.assign(_checkpoint.get("taken", []))
	for path in _taken:
		var n := get_node_or_null(NodePath(path))
		if n != null:
			n.queue_free()
	for entry in _checkpoint.get("items", []):
		var item := load(str(entry[0])) as ItemData
		for k in int(entry[1]):
			if item != null:
				Inventory.add_item(item)
	for d in _checkpoint.get("documents", []):
		if not Inventory.documents.has(d):
			Inventory.documents.append(d)
	if player.hunger != null:
		player.hunger.level = float(_checkpoint.get("hunger", start_hunger))
	if player.wound != null:
		player.wound.set_bleeding(bool(_checkpoint.get("bleeding", false)),
				float(_checkpoint.get("bled_for", 0.0)))
	fade_from_black()


## The picture comes up out of black (a checkpoint, a second try).
func fade_from_black() -> void:
	fade.modulate.a = 1.0
	create_tween().tween_property(fade, "modulate:a", 0.0, 1.5)


func _apply_debug_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		var key := kv[0]
		var value := kv[1] if kv.size() > 1 else ""
		match key:
			"spawn":
				var m := get_node_or_null("Spawns/" + value) as Node3D
				if m != null:
					player.global_transform = m.global_transform
			"look":
				if value.count(",") == 2:
					var c := value.split_floats(",")
					player.look_towards(Vector3(c[0], c[1], c[2]))
				else:
					var target := get_node_or_null(value) as Node3D
					if target != null:
						player.look_towards(target.global_position + Vector3.UP * 1.4)
			"give":
				for id in value.split(",", false):
					var item := load("res://assets/data/items/%s.tres" % id) as ItemData
					if item != null:
						Inventory.add_item(item)
			"satchel":
				player.satchel.open()
			"hunger":
				if player.hunger != null:
					player.hunger.level = clampf(value.to_float(), 0.0, 1.0)
			"bleeding":
				if player.wound != null:
					player.wound.cut()
			"blood-ahead":
				# Frames: drops on the ground ahead of him, as a trail looks.
				if player.wound != null:
					var start := player.global_position
					var ahead := -player.global_transform.basis.z
					for i in value.to_int():
						player.global_position = start + ahead * (1.2 + i * Wound.DROP_SPACING)
						player.wound.drop()
					player.global_position = start
			"pos":
				if value.count(",") == 2:
					var c := value.split_floats(",")
					player.global_position = Vector3(c[0], c[1], c[2])
			"panic":
				PanicSystem.floor_level = clampf(value.to_float(), 0.0, 1.0)
				PanicSystem.level = PanicSystem.floor_level
			"hide":
				var spot := get_node_or_null(value) as HideSpot
				if spot != null:
					spot.admit(player)
			"sepia":
				Perception.enter_safe_zone()
			"crouch":
				Input.action_press("crouch")
			"open-doc":
				player.open_document(value)
			"doc-tab":
				player.archive_ui._tabs.current_tab = value.to_int()
			"print-camera":
				for i in 10:
					await get_tree().physics_frame
				print("camera at ", player.camera.global_position,
						" forward ", -player.camera.global_transform.basis.z,
						" pitch ", rad_to_deg(player.head.rotation.x))
			"pause":
				PauseMenu.open()
			"no-post":
				player.camera.get_node("PostProcess").visible = false
			"freeze-enemies":
				for e in get_tree().get_nodes_in_group("enemies"):
					e.process_mode = Node.PROCESS_MODE_DISABLED
					(e as Enemy)._update_visual_params()
			"silent":
				player.get_node("BreathControl").set_physics_process(false)
			"no-gunfire":
				GunfireAmbience.muted = true
			"brightness":
				# Only the picture: the player's saved setting is left alone.
				RenderingServer.global_shader_parameter_set("g_brightness",
						clampf(value.to_float(), GameState.BRIGHTNESS_MIN, GameState.BRIGHTNESS_MAX))
			_:
				_debug_arg(key, value)


## Level-specific debug arguments.
func _debug_arg(_key: String, _value: String) -> void:
	pass


## Capture (docs/ARCHITECTURE.md, "Поимка"): he is held face to face with
## the one who caught him for SEIZE_HOLD seconds, then a hard cut: black,
## the world goes deaf, only his own heart and breath; then the reload. What
## happens to him is never shown.
const SEIZE_HOLD := 1.1
const BLACK_HOLD := 2.2


func _on_caught(enemy: Enemy) -> void:
	if _ending:
		return
	_ending = true
	_resume_after_intro = _restarts_at_checkpoint()
	_retry_opening = not _resume_after_intro and _retries_opening()
	player.seized_by(enemy)
	var t := create_tween()
	t.tween_interval(SEIZE_HOLD)
	t.tween_callback(cut_to_black)
	t.tween_interval(BLACK_HOLD)
	t.tween_callback(get_tree().reload_current_scene)


## The cut after a capture: black at once, the world muffled almost to
## nothing (the body bus - heart, breath - stays).
func cut_to_black() -> void:
	fade.modulate.a = 1.0
	Sfx.set_muffle(180.0, -40.0, 0.06)


## A mine: a hard cut to black and ringing, then the reload.
func _on_mine(_mine: TripwireMine) -> void:
	if _ending:
		return
	_ending = true
	_resume_after_intro = _restarts_at_checkpoint()
	_retry_opening = not _resume_after_intro and _retries_opening()
	fade.modulate.a = 1.0
	Sfx.play_at("ear_ring", player.camera.global_position)
	var t := create_tween()
	t.tween_interval(3.0)
	t.tween_callback(get_tree().reload_current_scene)


func _physics_process(delta: float) -> void:
	if _ending:
		return
	_check_checkpoints()
	if not _in_forest:
		return
	if _pursued():
		_forest_calm = 0.0
		return
	_forest_calm += delta
	if _forest_calm >= forest_calm_needed:
		_on_reached_forest()


## May a memory break in now (TraumaEcho, docs/ARCHITECTURE.md, «Вторжение
## памяти»)? Not while the level is ending (capture, a mine) or its black is up.
## Levels with scenes of their own add them (Act III).
func echo_allowed() -> bool:
	return not _ending and (fade == null or fade.modulate.a < 0.01)


func _pursued() -> bool:
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en.is_visible_in_tree() and en.state != Enemy.State.PATROL:
			return true
	return false


## Documents found / documents in the level (the end card).
func documents_found() -> Vector2i:
	return Vector2i(Inventory.documents.size(), _documents_total)


func _count_documents() -> int:
	var total := 0
	for n in find_children("*", "Pickup", true, false):
		var item := (n as Pickup).item
		if item != null and item.document_id != "":
			total += 1
	return total


## Text of the end card; levels add their own lines. No documents on the
## level - no documents line ("0 of 0" says nothing). The line break is
## written out: a string across lines would carry this file's CR into it.
func _end_card_text() -> String:
	var d := documents_found()
	if d.y == 0:
		return ending_title
	return "%s\nДокументов в архиве свидетеля: %d из %d" % [ending_title, d.x, d.y]


func _on_reached_forest() -> void:
	if _ending:
		return
	_ending = true
	var t := create_tween()
	t.tween_interval(2.0)
	t.tween_property(fade, "modulate:a", 1.0, 2.5)
	t.tween_callback(func() -> void:
		caption.text = _end_card_text()
		slice_finished.emit()
		if next_level != "":
			# The card waits while the game is paused (Esc on it): until 20.11.2026
			# the next scene loaded under the pause menu.
			get_tree().create_timer(5.0, false).timeout.connect(func() -> void:
				if is_inside_tree():
					get_tree().change_scene_to_file(next_level)))
