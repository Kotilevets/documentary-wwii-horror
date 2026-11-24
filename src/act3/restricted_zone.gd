class_name RestrictedZone
extends Area3D
## A place a village boy has no business in (a depot yard): inside it the
## pass is no cover, enemies notice him as usual (Stealth.exposed()).

signal player_entered
signal player_exited

var _inside := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 << 1  # player
	body_entered.connect(func(b: Node3D) -> void:
		if b == Stealth.player and not _inside:
			_inside = true
			Stealth.enter_restricted()
			player_entered.emit())
	body_exited.connect(func(b: Node3D) -> void:
		if b == Stealth.player and _inside:
			_inside = false
			Stealth.exit_restricted()
			player_exited.emit())


func _exit_tree() -> void:
	if _inside:
		_inside = false
		Stealth.exit_restricted()
