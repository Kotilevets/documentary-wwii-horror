class_name GazeTarget
extends Marker3D
## Something the boy has to hold his eyes on for `dwell` seconds.
## Interrogation: an ordinary thing in the office (portrait, kettle,
## typewriter) pulls him out of the nightmare (GAMEPLAY_AND_SHADERS.md, 4).
## Garrison: a scouting target he has to remember (trucks, a gun nest).
## No marker on screen: the thing itself is lit and in view.

signal fixed(target: GazeTarget)

@export var radius: float = 0.3
@export var dwell: float = 1.5
@export var max_distance: float = 12.0
## Only while active (the interrogation switches its details on).
@export var active: bool = true
## Played once when the gaze has held (bank id, "" - nothing).
@export var sound_id: String = ""

var held := 0.0
var done := false
## His eyes are on it in this physics frame (the garrison's "staring" is
## looking now, not having looked: docs/ARCHITECTURE.md, "Акт III").
var looking := false


func _ready() -> void:
	# Before the level in every physics frame: tree order runs the level,
	# their parent, first, and it sets Stealth.staring from `looking` - the
	# enemies then acted on the look of the frame before.
	process_physics_priority = -1


func _physics_process(delta: float) -> void:
	looking = false
	if done or not active:
		return
	var p := Stealth.player as Player
	if p == null or not p.is_inside_tree():
		return
	# The cellar on the screen (TraumaEcho): nothing here is being looked at.
	if Gaze.looks_at(p.camera, global_position, radius, max_distance) \
			and not TraumaEcho.showing_in(get_tree()):
		looking = true
		held += delta
		if held >= dwell:
			done = true
			if sound_id != "":
				Sfx.play_at(sound_id, global_position)
			fixed.emit(self)
	else:
		held = maxf(held - delta * 0.5, 0.0)
