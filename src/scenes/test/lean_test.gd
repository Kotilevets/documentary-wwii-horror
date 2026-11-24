extends Node3D
## Test scene: leaning out (docs/ARCHITECTURE.md, "Выглянуть"). A log wall
## with a doorway; outside, aslant from the door, a soldier with a torch
## stands at his post facing it. The boy stands inside behind the jamb:
## upright he is not seen, leaning right into the doorway he is. Caught, he
## is let go after a pause and put back where he started.
## Arguments after `--`: --lean=left|right|forward holds the lean (renders),
## --crouch crouches.

const LEAN_KEYS := {"left": "move_left", "right": "move_right", "forward": "move_forward"}

@onready var soldier: Enemy = $Soldier
@onready var player: Player = $Player

var _start: Transform3D
var _post: Transform3D


func _ready() -> void:
	_start = player.global_transform
	_post = soldier.global_transform
	soldier.torch_on = true
	soldier.player_caught.connect(_on_caught)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lean="):
			var key: String = LEAN_KEYS.get(arg.get_slice("=", 1), "")
			if key != "":
				Input.action_press("lean")
				Input.action_press(key)
		elif arg == "--crouch":
			Input.action_press("crouch")


func _on_caught(e: Enemy) -> void:
	player.seized_by(e)
	await get_tree().create_timer(2.5).timeout
	player.release()
	soldier.stand_down()
	soldier.global_transform = _post
	player.global_transform = _start
