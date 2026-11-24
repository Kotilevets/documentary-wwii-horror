class_name ItemData
extends Resource
## Data of an inventory item (.tres files in assets/data/items/).
## A document is an item with document_id pointing into ArchiveDB.

@export var id: String = ""
@export var display_name: String = ""
## Mesh shown in the satchel view and in the world.
@export var mesh: Mesh
## Id in assets/data/archive/*.json; empty for ordinary items.
@export var document_id: String = ""
@export var stackable: bool = true
