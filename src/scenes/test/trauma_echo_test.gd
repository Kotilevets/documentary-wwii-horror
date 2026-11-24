extends Node3D
## Test scene: «Вторжение памяти» (docs/ARCHITECTURE.md). Night. A burned
## stove (point A): a polizei with a torch walks by on its far side, 2.25 m
## from the boy crouched behind it. 24 m off, a searchlight whose beam
## sweeps over a haystack in front of point B. Caught, he is let go after a
## pause and put back where he started.
## Arguments after `--`: --spot=a|b crouches him at the point; --panic=0.5
## holds the panic floor; --show-echo starts the echo at once and holds it
## at its middle (for a frame).

@onready var player: Player = $Player
@onready var echo: TraumaEcho = $TraumaEcho

var _start: Transform3D


func _ready() -> void:
	TraumaEcho.forget_all()
	PanicSystem.reset()
	Stealth.set_night(0.5, $Moon as DirectionalLight3D)
	Sfx.set_muffle(Sfx.OPEN_AIR, 0.0, 0.0)
	for e in get_tree().get_nodes_in_group("enemies"):
		(e as Enemy).player_caught.connect(_on_caught.bind(e))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spot="):
			var m := get_node_or_null("Spots/" + arg.get_slice("=", 1).to_upper()) as Marker3D
			if m != null:
				player.global_transform = m.global_transform
			Input.action_press("crouch")
		elif arg.begins_with("--panic="):
			PanicSystem.floor_level = clampf(arg.get_slice("=", 1).to_float(), 0.0, 1.0)
			PanicSystem.level = PanicSystem.floor_level
		elif arg == "--show-echo":
			echo.hold = true
			echo.start.call_deferred(TraumaEcho.DEBUG)
	_start = player.global_transform


func _exit_tree() -> void:
	Stealth.set_day()


func _on_caught(_by: Enemy, e: Enemy) -> void:
	player.seized_by(e)
	await get_tree().create_timer(2.5).timeout
	player.release()
	e.stand_down()
	player.global_transform = _start
