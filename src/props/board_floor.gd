class_name BoardFloor
extends Node3D
## Wooden floor: the izba, the dream room, the office. Boots knock on the
## boards and now and then make them creak; over a cellar the boards shed
## dust on whoever hides below (Gait, Player.boards_overhead;
## docs/ARCHITECTURE.md, "Шаги и походка").
## A box in the node's own space, centred on the node; the floor surface is
## at the node's height. Levels with an earth floor need nothing.

@export var size: Vector3 = Vector3(4, 1, 4)


func _ready() -> void:
	add_to_group("board_floors")


func contains(point: Vector3) -> bool:
	var local := global_transform.affine_inverse() * point
	return absf(local.x) <= size.x * 0.5 and absf(local.z) <= size.z * 0.5 \
			and absf(local.y) <= size.y * 0.5


## The board floor under `point`, or null (earth, grass, snow).
static func at(tree: SceneTree, point: Vector3) -> BoardFloor:
	if tree == null:
		return null
	for f in tree.get_nodes_in_group("board_floors"):
		if (f as BoardFloor).contains(point):
			return f as BoardFloor
	return null
