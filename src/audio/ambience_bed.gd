class_name AmbienceBed
extends Node
## A looped sound bed for a whole level, not positional: the wind outside
## (docs/ARCHITECTURE.md, "Звук из укрытия и ветер"). It plays on the World
## bus, so a hiding place muffles it like everything else; inside a house
## (a BoardFloor under the boy) it drops by `indoor_db`. LevelBase adds one
## unless the level says otherwise (the dream is silent).

@export var sound_id: String = "wind"
## Added to the bank's volume_db: a level can be windier than another.
@export var gain_db: float = 0.0
@export var indoor_db: float = -12.0
## dB per second the bed follows him in and out of a house.
@export var fade_rate: float = 10.0

var player: AudioStreamPlayer


func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.name = "Bed"
	player.stream = Sfx.stream_for(sound_id)
	player.bus = Sfx.WORLD_BUS
	player.volume_db = target_db()
	add_child(player)
	if player.stream != null:
		player.play()


func target_db() -> float:
	return Sfx.volume_of(sound_id) + gain_db + (indoor_db if indoors() else 0.0)


## The boy stands (or hides) under a roof: on a board floor.
func indoors() -> bool:
	var p := Stealth.player as Node3D
	return p != null and p.is_inside_tree() \
			and BoardFloor.at(get_tree(), p.global_position + Vector3.UP * 0.05) != null


func _process(delta: float) -> void:
	player.volume_db = move_toward(player.volume_db, target_db(), fade_rate * delta)
