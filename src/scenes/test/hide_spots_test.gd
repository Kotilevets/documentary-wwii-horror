extends Node3D
## Test scene: hiding places and the house search (docs/ARCHITECTURE.md,
## "Укрытия и обыск"). A corner of an izba with a stove, a wardrobe against
## the wall and a cellar hatch. A soldier with a torch searches the room in
## a loop: opens the wardrobe, looks behind the stove, walks over the hatch.
## If he finds the boy he lets go after a pause and the round starts again.
## Arguments after `--`: --hide=<spot node name> starts in that spot,
## --silent switches off breath sounds (renders), --watch lets the boy stand
## in the room unnoticed (Stealth.cover) to watch the search from outside.

@onready var soldier: Enemy = $Soldier
@onready var player: Player = $Player
@onready var route: Node3D = $Route
@onready var wardrobe: HideSpot = $WardrobeHide


func _ready() -> void:
	soldier.searches_hiding_spots = true
	soldier.torch_on = true
	soldier.scripted_finished.connect(_next_round)
	soldier.player_caught.connect(_on_caught)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hide="):
			(get_node(arg.get_slice("=", 1)) as HideSpot).admit.call_deferred(player)
		elif arg == "--silent":
			player.get_node("BreathControl").set_physics_process(false)
		elif arg == "--watch":
			Stealth.cover = true
	_next_round()


func _next_round() -> void:
	wardrobe.close_door()
	soldier.searches_hiding_spots = false
	soldier.searches_hiding_spots = true  # a new search: nothing checked yet
	var pts: Array[Vector3] = []
	for c in route.get_children():
		pts.append((c as Node3D).global_position)
	soldier.script_goto(pts)


func _on_caught(e: Enemy) -> void:
	player.seized_by(e)
	await get_tree().create_timer(2.5).timeout
	player.release()
	soldier.stand_down()
	soldier.global_position = (route.get_child(route.get_child_count() - 1) as Node3D).global_position
	_next_round()
