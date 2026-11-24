class_name Pickup
extends Interactable
## A thing that goes into the satchel. If the item is a document, the
## inspection view opens right away (Witness Archive).

signal document_picked(document_id: String)

@export var item: ItemData
## Node removed from the world on pickup (defaults to this Area3D).
@export var remove_on_pickup: Node


func _ready() -> void:
	var mesh_node := get_node_or_null("Mesh") as MeshInstance3D
	if mesh_node != null and mesh_node.mesh == null and item != null:
		mesh_node.mesh = item.mesh
	super._ready()


func interact(player: Node) -> void:
	if item == null:
		push_error("Pickup %s has no ItemData" % name)
		return
	Inventory.add_item(item)
	super.interact(player)
	if item.document_id != "":
		document_picked.emit(item.document_id)
		if player.has_method("open_document"):
			player.open_document(item.document_id)
	var target := remove_on_pickup if remove_on_pickup != null else self
	target.queue_free()
