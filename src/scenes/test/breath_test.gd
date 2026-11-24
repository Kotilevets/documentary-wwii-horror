extends Node3D
## Test scene: «Дыхание рвётся» (docs/ARCHITECTURE.md). Night. The boy sits
## in a cellar; a soldier walks his round back and forth over the hatch.
## Hidden, with the soldier within 6 m and the breath not held, the boy hears
## his own ragged breath, louder as the sob nears, and a catch of breath just
## before it; released on the beat, a quiet sip through the nose. Caught, he
## is let go after a pause and put straight back into the cellar.
## Arguments after `--`: --panic=0.5 holds the panic floor; --winded=1 holds
## him out of breath at least that much; --still - the soldier stands 2 m
## from the hatch.

@onready var player: Player = $Player
@onready var hatch: HideSpot = $CellarHatch
@onready var soldier: Enemy = $Soldier

## --winded: he never gets his breath back below this.
var winded_floor := 0.0


func _ready() -> void:
	PanicSystem.reset()
	Stealth.set_night(0.5, $Moon as DirectionalLight3D)
	Sfx.set_muffle(Sfx.OPEN_AIR, 0.0, 0.0)
	soldier.player_caught.connect(_on_caught)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--panic="):
			PanicSystem.floor_level = clampf(arg.get_slice("=", 1).to_float(), 0.0, 1.0)
			PanicSystem.level = PanicSystem.floor_level
		elif arg.begins_with("--winded="):
			winded_floor = clampf(arg.get_slice("=", 1).to_float(), 0.0, 1.0)
			player.breath.winded = winded_floor
		elif arg == "--still":
			soldier.patrol_route = null
			soldier.global_position = hatch.global_position + Vector3(0, 0, 2)
	_hide.call_deferred()


func _physics_process(_delta: float) -> void:
	if winded_floor > 0.0:
		player.breath.winded = maxf(player.breath.winded, winded_floor)


func _exit_tree() -> void:
	Stealth.set_day()


func _hide() -> void:
	if not player.is_hidden:
		player.global_position = hatch.global_position + Vector3(0.8, 0, 0)
		hatch.interact(player)


func _on_caught(_by: Enemy) -> void:
	if player.seized:
		return
	player.seized_by(soldier)
	get_tree().create_timer(2.5).timeout.connect(_let_go)


## Let go after a pause and straight back into the cellar, without a sound:
## a test scene, not a level - no standing in the open in front of the
## soldier to be caught again.
func _let_go() -> void:
	player.release()
	soldier.stand_down()
	hatch.admit(player)
