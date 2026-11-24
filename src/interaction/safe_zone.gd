class_name SafeZone
extends Area3D
## Zone of safety (refuge, partisan campfire, prologue): warm sepia instead
## of hard B&W while the player is inside.

signal player_entered
signal player_exited

## An inactive zone does not tint the picture (the prologue zone is switched
## off when the invasion starts).
@export var active: bool = true
var _inside := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 << 1  # player
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func set_active(value: bool) -> void:
	if value == active:
		return
	active = value
	if _inside:
		if active:
			Perception.enter_safe_zone()
		else:
			Perception.exit_safe_zone()


func _on_body_entered(body: Node3D) -> void:
	if body == Stealth.player:
		_inside = true
		if active:
			Perception.enter_safe_zone()
			player_entered.emit()


func _on_body_exited(body: Node3D) -> void:
	if body == Stealth.player:
		_inside = false
		if active:
			Perception.exit_safe_zone()
			player_exited.emit()
