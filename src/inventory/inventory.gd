extends Node
## Diegetic inventory: what the teenager carries in the satchel.

signal changed
signal document_collected(document_id: String)

## id -> {"item": ItemData, "count": int}
var _items: Dictionary = {}
## Collected document ids in pickup order (Witness Archive journal).
var documents: Array[String] = []


func add_item(item: ItemData) -> void:
	if _items.has(item.id) and item.stackable:
		_items[item.id].count += 1
	else:
		_items[item.id] = {"item": item, "count": 1}
	if item.document_id != "" and not documents.has(item.document_id):
		documents.append(item.document_id)
		document_collected.emit(item.document_id)
	changed.emit()


func remove_item(id: String) -> bool:
	if not _items.has(id):
		return false
	_items[id].count -= 1
	if _items[id].count <= 0:
		_items.erase(id)
	changed.emit()
	return true


func has_item(id: String) -> bool:
	return _items.has(id)


func count(id: String) -> int:
	return _items[id].count if _items.has(id) else 0


func items() -> Array[ItemData]:
	var out: Array[ItemData] = []
	for entry in _items.values():
		out.append(entry.item)
	return out


func clear() -> void:
	_items.clear()
	documents.clear()
	changed.emit()
