class_name HideSpot
extends Interactable
## Hiding place: cellar (podpol), hayloft, wardrobe, behind the stove.
## The player's camera moves to `view_point` and looks out through narrow
## slits (see src/player/hide_overlay.gdshader).
##
## Searching enemies treat hiding places by how obvious they are
## (`search_check`, docs/ARCHITECTURE.md, "Укрытия и обыск"):
##   NONE - not looked into (cellar under the floor, hay); only a dog or a
##          sound gives the boy away;
##   LOOK - a searcher who passes within reach stops and shines his torch
##          into it for `check_time` seconds (behind the stove); only
##          silence saves the boy, and the place muffles little;
##   OPEN - a searcher who passes within reach opens it (wardrobe): whoever
##          is inside is found.
## A calm patrol never checks anything: only an enemy who is searching
## (Enemy.is_searching()).

signal searched(by: Node)
signal search_ended(by: Node)

enum Slits { HORIZONTAL, VERTICAL }
enum SearchCheck { NONE, LOOK, OPEN }

@export var view_point: Marker3D
@export var slits: Slits = Slits.HORIZONTAL
## 0..1 gap between boards; smaller = less visible to the player.
@export_range(0.02, 0.5) var slit_width: float = 0.12
## Number of gaps across the view (1 = a single crack or opening).
@export_range(1, 6) var slit_count: int = 3
## How hard it is for an enemy to spot an occupant who makes noise
## (multiplies the hearing of nearby enemies).
@export_range(0.0, 1.0) var noise_damping: float = 0.6
## How much of the occupant's scent is hidden from dogs (1 = none gets out).
@export_range(0.0, 1.0) var scent_blocking: float = 0.5
@export var search_check: SearchCheck = SearchCheck.NONE
## Seconds a searcher spends on the place.
@export var check_time: float = 3.0
## How close (m, along the ground) a searcher has to pass the check point.
@export var check_radius: float = 1.6
## Point, in the spot's own space, that a searcher looks at: the opening.
## It has to be visible from where he stands (walls and the spot's own
## body block the look).
@export var check_offset: Vector3 = Vector3(0, 0.6, 0)
## Where a searcher stands to check the place (spot's own space): in front
## of the opening, so the check is seen from inside.
@export var stand_offset: Vector3 = Vector3(0, 0, -1.0)
## Where torch light is sampled for the glow in the gaps (spot's own space):
## inside a cellar or a nook, in front of the doors of a wardrobe.
@export var leak_offset: Vector3 = Vector3(0, 0.15, 0)
## Under the floorboards (the cellar): boots overhead shed dust through the
## gaps (Player.boards_overhead).
@export var under_floor: bool = false
## How the world sounds from inside (Sfx.set_muffle): low-pass cutoff (Hz)
## and volume (dB) of everything but his own breath and heart.
## Sfx.OPEN_AIR (20000) - not muffled.
@export var muffle_hz: float = 20000.0
@export var muffle_db: float = 0.0
## Getting in and out is heard (docs/ARCHITECTURE.md, "Шум от действий"):
## `use_sound` (Sfx id) for the boy, `use_noise` (Stealth action noise) for
## the enemies; crouched, both are halved (Player.care). The noise is made
## while he is still out in the open (before he hides, after he comes out):
## heard plainly it brings a soldier to look, but it never counts as a sound
## from inside. Only the player's own action is heard: stories and captures
## use admit/eject.
@export var use_sound: String = ""
@export_range(0.0, 1.0) var use_noise: float = 0.0
## OPEN: the door a searcher swings open (rotated about its own Y).
@export var door: Node3D
@export var door_open_angle: float = -100.0
## OPEN: seconds from the start of the check until the door is open and
## the occupant is in plain view.
@export var open_delay: float = 0.7

var occupant: Node = null
var is_open := false


func _ready() -> void:
	super()
	add_to_group("hide_spots")


func can_interact(player: Node) -> bool:
	return occupant == null or occupant == player


func interact(player: Node) -> void:
	# How carefully: asked before he moves (hidden, only the button counts).
	var k: float = player.care() if player.has_method("care") else 1.0
	if occupant == null:
		_make_noise(player, k)
		# His trail runs into the place (a dog on it comes right here).
		Stealth.scent_into((player as Node3D).global_position, global_position)
		occupant = player
		player.enter_hide_spot(self)
	elif occupant == player:
		occupant = null
		player.exit_hide_spot()
		_make_noise(player, k)
	super.interact(player)


func _make_noise(player: Node, k: float) -> void:
	if use_sound != "":
		Sfx.play_at(use_sound, check_point(), k)
	if use_noise > 0.0:
		Stealth.emit_action_noise(global_position, use_noise * k, player)


## A story or a capture moves him in or out: no sound of his own, no noise.
func admit(player: Node) -> void:
	if occupant == null:
		occupant = player
		player.enter_hide_spot(self)
		interacted.emit(player)


func eject(player: Node) -> void:
	if occupant == player:
		occupant = null
		player.exit_hide_spot()
		interacted.emit(player)


func view_transform() -> Transform3D:
	return view_point.global_transform if view_point != null else global_transform


func check_point() -> Vector3:
	return global_transform * check_offset


func leak_point() -> Vector3:
	return global_transform * leak_offset


func stand_point() -> Vector3:
	return global_transform * stand_offset


## A searcher starts checking the place.
func begin_check(by: Node) -> void:
	if search_check == SearchCheck.OPEN and door != null and not is_open:
		is_open = true
		var t := create_tween()
		t.tween_property(door, "rotation_degrees:y", door_open_angle, open_delay) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if search_check == SearchCheck.OPEN:
		Sfx.play_at("door_creak", check_point())
	searched.emit(by)


func end_check(by: Node) -> void:
	search_ended.emit(by)


## OPEN: shut the door again (a level reset, the test scene's next round).
func close_door() -> void:
	is_open = false
	if door != null:
		door.rotation_degrees.y = 0.0
