class_name Interactable
extends Area3D
## Base for everything the player can use. Lives on physics layer 4.
## No text prompts: every mesh under the object is marked blue-green
## (ColorMask channel INTERACTIVE) automatically on _ready -
## tests/test_runner checks this.

signal interacted(player: Node)

const INTERACT_LAYER := 1 << 3

## Replace albedo with the canonical blue-green; off keeps the texture's own
## brightness (the post pass still tints it).
@export var tint_albedo: bool = true


func _init() -> void:
	collision_layer = INTERACT_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true


func _ready() -> void:
	ColorMask.apply(self, ColorMask.Channel.INTERACTIVE, tint_albedo)


## Override in subclasses; call super to emit the signal.
func interact(player: Node) -> void:
	interacted.emit(player)


## Whether the player may use the object right now.
func can_interact(_player: Node) -> bool:
	return true
